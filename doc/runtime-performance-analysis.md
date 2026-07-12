# 《窃律者》运行时性能分析

日期：2026-07-11，2026-07-12 更新
结论状态：已完成静态审计、同机运行采样、首批优化与回归验证；场景加载和 HUD 分配仍待后续处理。

## 1. 结论摘要

当前“玩起来卡卡的”主要不是战斗规则复杂度或硬件不足，而是战斗表现层在高刷新率下持续做了过多重复工作。

最关键的两个问题是：

1. **棋盘静止时仍每帧整板重绘。** `IsometricBoard` 把地块、叠加层、单位、血条、意图、宝石、选区和特效都放在同一个 `_draw()` 中。当前行动单位、玩家待机动画或任意草地/状态叠加层都会让它每帧 `queue_redraw()`，从而反复重建整个 8×8 棋盘的 Canvas 绘制命令。
2. **攻击模式下，每次鼠标移动都会同步重算完整攻击范围和命中预览。** 同一格内的鼠标移动也没有去重。实测单次攻击高亮查询约 **5.6 ms**；本机 160 Hz 显示器每帧预算只有 **6.25 ms**，再叠加棋盘重绘后会直接错过刷新周期，表现为鼠标移动、选目标时明显不顺滑。

复杂草地、毒雾和烟雾关卡还会启用 6 个持续更新的 `SubViewport`，但 A/B 结果表明它们是次要成本；真正占大头的是棋盘 `_process()` 引发的整板重绘和攻击预览重算。

此外，进入战斗存在约 **0.4–0.8 秒同步初始化**和 **42–87 ms 首帧尖峰**，会造成切场景时停一下。战斗事件播放器中的串行等待则会带来“节奏慢”的体感，但它和实际掉帧应分开处理。

## 2. 测试环境与方法

测试机器就是当前项目所在电脑：

- CPU：AMD Ryzen 7 9700X，8 核 16 线程
- GPU：NVIDIA GeForce RTX 5070 Ti
- 内存：约 48 GB
- 主显示器：3840×2160，160 Hz
- 引擎：Godot 4.6.3 Stable
- 渲染器：OpenGL 3.3 Compatibility
- 项目渲染方式：`gl_compatibility`

采样使用实际窗口渲染，关闭 VSync 和 FPS 上限以暴露真实帧耗时；每个稳态阶段预热 120 帧、采样 360 帧。对照组只在诊断脚本中临时停用棋盘 `_process()` 或停用叠加层 `SubViewport`，没有修改游戏实现。

因此本文数据适合判断热点和优化优先级，不应当作发布版的最终 FPS 承诺。Debug 构建、后台程序和驱动调度会造成一定波动。

## 3. 关键采样结果

### 3.1 1600×900 稳态 A/B

| 场景 | 默认平均帧耗时 | 停止棋盘 `_process()` | 完全静态 | 判断 |
|---|---:|---:|---:|---|
| 教学战 `tutorial_001` | 约 2.9 ms | 约 0.68 ms | 约 0.68 ms | 约 76% 的帧时间来自棋盘持续更新/重绘 |
| 复杂叠加层 `toxic_furnace` | 约 4.0 ms | 约 0.95 ms | 约 0.73 ms | 整板重绘仍是主体，6 个 SubViewport 约再增加 0.2 ms |

`toxic_furnace` 默认约 226 个 draw calls、765 个渲染对象；教学战约 175 个 draw calls、630 个渲染对象。对一个 8×8 回合制棋盘来说，这不是 GPU 顶点量问题，而是单一 CanvasItem 反复生成大量细碎绘制命令的问题。

### 3.2 4K / 160 Hz 实机结果

代表性复测结果：

| 场景 | 平均 | P95 | P99 | 160 Hz 帧预算 |
|---|---:|---:|---:|---:|
| 教学战 | 4.29 ms | 5.79 ms | 6.55 ms | 6.25 ms |
| `toxic_furnace` | 4.36 ms | 5.82 ms | 6.67 ms | 6.25 ms |

P99 已经超过 160 Hz 的 6.25 ms 帧预算。另一轮采样中教学战 P95 达到 9.82 ms、最大帧 22.61 ms，说明在后台负载或资源调度稍有扰动时会连续错过高刷刷新周期。高配置电脑并不能消除这种主线程重复工作的结构性开销。

### 3.3 鼠标高亮查询

每种模式循环查询 512 次、轮换 64 个格子的平均耗时：

| 模式 | 教学战单次平均 | `toxic_furnace` 单次平均 |
|---|---:|---:|
| 无动作 | 0.0048 ms | 0.0058 ms |
| 移动 | 1.01 ms | 0.85 ms |
| 攻击 | 5.70 ms | 5.58 ms |

攻击模式的单次查询已经接近整个 160 Hz 帧预算。鼠标移动时还会触发棋盘高亮更新和整板绘制，所以这是最符合“操作时卡卡的”描述的直接根因。

### 3.4 切入战斗

4K 采样中观察到：

- 战斗场景冷加载：约 0.53–0.63 秒；
- 场景 `_ready()` 同步初始化：约 0.40–0.79 秒；
- 第一帧：教学战约 42 ms，复杂叠加层关卡约 87 ms。

这是切场景停顿，不是稳态 FPS 低。复杂关卡首次出现新敌人时，档案解锁还会同步写盘，多次写入可能放大这次尖峰。

## 4. 根因定位

### P0：棋盘每帧整板重绘

证据位置：

- `scripts/ui/isometric_board.gd:272-326`：棋盘永久启用 `_process()`。
- `scripts/ui/isometric_board.gd:277-278`：只要存在当前行动单位，就把画面标记为 dirty。
- `scripts/ui/isometric_board.gd:288-294`：玩家和史莱姆待机动画每帧推进，也会让整板 dirty。
- `scripts/ui/isometric_board.gd:329-337`：每帧遍历全部地块判断是否存在动画叠加层。
- `scripts/ui/isometric_board.gd:414-432`：每帧再次遍历地块，并为 SubViewport 重设更新模式。
- `scripts/ui/isometric_board.gd:599-643`：一次 `_draw()` 重画地块、实体、掉落物、单位、单位 UI、特效和槽位面板。
- `scripts/ui/isometric_board.gd:595-596` 与 `scripts/map/iso_coordinates.gd:183-198`：`_draw()` 每次多次调用 `_sorted_cells()`；每次都重新生成 64 格数组并执行排序。

这里的核心问题不是某个 draw call 特别昂贵，而是架构把静态和动态内容绑定在同一个 CanvasItem 上。一个只需要更新的行动光环或 10 FPS 待机帧，会迫使整个棋盘重建绘制命令。

### P0：鼠标移动触发重复的攻击预览计算

证据位置：

- `scripts/ui/board_input_adapter.gd:26-34`：每个 `InputEventMouseMotion` 都发出 `cell_hovered`，没有“格子未变化则返回”的保护。
- `scripts/ui/battle_scene.gd:617-647`：每次 hover 都调用 `_controller.get_highlights(_hover_cell)`。
- `scripts/battle/battle_query_service.gd:26-109`：每次都重新创建整套结果字典并计算动作范围、路径、效果和意图叠加层。
- `scripts/battle/battle_query_service.gd:353-366`：攻击范围每次扫描整个 8×8 棋盘。
- `scripts/battle/battle_query_service.gd:393-436`：再针对当前格计算分裂、爆炸、光束和死亡宝石预览。

这些结果在同一个战斗状态、同一个动作下大部分是不变的，却没有状态版本缓存。高轮询率鼠标和高刷显示器会让这个问题更明显。

### P1：叠加层使用多个持续更新的 SubViewport

证据位置：

- `scripts/ui/isometric_board.gd:340-411`：草地、毒雾、烟雾分别创建独立 SubViewport 和 ShaderMaterial。
- `scripts/ui/isometric_board.gd:414-422`：活跃路径使用 `SubViewport.UPDATE_ALWAYS`。

复杂关卡会同时启用 6 个 SubViewport。它们的直接 GPU 成本在本机约为每帧 0.1–0.2 ms，当前不是第一优先级；但它们增加显存、渲染对象和同步面，低端 GPU 上会更突出。现有美术规范要求保留草地摆动、雾气漂移和前后两段遮挡语义，优化时应复用共享图集或较少的 Viewport，而不是直接删除动画。

### P1：战斗初始化包含同步资源和存档工作

证据位置：

- `scripts/ui/isometric_board.gd:699-738`：每个棋盘实例通过 `Image.load_from_file()` 同步读取四张水体生成图。运行日志明确警告这种加载方式不适用于导出，应改为导入资源后正常 `load/preload`。
- `scripts/ui/doodle_unit_sprites.gd:63-77`、`female_adventurer_sprites.gd:113-125`、`slime_sprites.gd:83-97`：实例级缓存配合 `ResourceLoader.CACHE_MODE_IGNORE`，新棋盘会绕过全局资源缓存重新加载素材。
- `scripts/ui/female_adventurer_sprites.gd:88-110` 与 `slime_sprites.gd:100` 之后：首次使用每个动画帧时会从纹理取 Image、逐像素扫描包围盒并创建 AtlasTexture。
- `scripts/services/profile_service.gd:14-20`、`144-163`：每个首次解锁标记都会立即同步写 `profile.json`，并更新存档槽元数据；同一战斗出现多个新敌人时会连续写盘。

### P1：HUD 在状态刷新时反复销毁并创建控件

证据位置：

- `scripts/ui/battle_scene.gd:2505-2552`：一次状态刷新会更新整个 HUD、重新取高亮并安排多次延迟布局。
- `scripts/ui/battle_hud_presenter.gd:430-460`：检查面板先 `queue_free()` 所有槽位控件再重建。
- `scripts/ui/battle_hud_presenter.gd:856-869`：时间轴每次刷新全部销毁再重建。

这不会每帧发生，但会在移动、攻击、切换动作和回合推进时制造分配、布局与释放尖峰，使“点一下后顿一下”的体感更明显。

### P2：主菜单也保持持续刷新

证据位置：

- `scripts/main/main_root.gd:65-71`：主菜单每帧更新 56 个字典粒子并重画粒子 Canvas。
- `scripts/ui/pixel_menu_button.gd:43-56`：5 个菜单按钮无论是否 hover 都每帧更新 Shader 参数并 `queue_redraw()`。
- `scenes/main/main_menu_background.gdshader`：4 层 FBM 全屏动态雾效。

本机主菜单约 1.7 ms，暂时不是战斗卡顿主因，但在核显、节能模式或 4K 笔记本上会造成无必要的功耗和风扇负载。

### 体感问题：事件播放包含有意的串行等待

`scripts/ui/battle_event_player.gd` 会按 beat 串行播放，普通伤害、区域效果、爆炸恢复等含 0.2–0.75 秒等待。大量事件虽然 FPS 可能正常，仍可能让玩家觉得反馈拖沓。项目已有 0.75×–2.0×战斗动画速度设置，因此应先解决真实掉帧，再用批处理和节奏调整处理这一层体感，避免把两类问题混为一谈。

## 5. 建议的优化顺序

### 第一阶段：先解决两项 P0

1. **拆分棋盘绘制层。** 至少拆成静态地形层、地块叠加层、单位层、单位 UI 层、高亮/路线层、VFX 层。静态地形只在状态或尺寸变化时重画；行动光环只重画自己的小层；单位待机动画以素材真实帧率更新单位层，而不是驱动整板 160 FPS 重画。
2. **移除 `active_turn_unit_uid` 导致的无条件整板 dirty。** 行动光环改成独立 CanvasItem/节点，或只在 30/60 Hz 更新光环层。
3. **缓存排序格子和地块动画签名。** 棋盘尺寸或 origin 变化时才重建 `_sorted_cells`；地块状态变更时才重算 active overlay paths。
4. **鼠标 hover 按格去重。** `pick_cell()` 结果与上一次相同时直接返回，不再计算高亮。
5. **缓存动作高亮。** 以 `state revision + selected_action + player uid` 为 key 缓存 reachable/attack range/静态 overlay；鼠标变化只算当前格专属的路径或命中预览。
6. **一次构建宝石上下文。** 攻击范围扫描前构建一次红槽上下文，不要在 64 格循环中重复查询相同的光、重力、分裂和爆炸状态。

第一阶段验收目标：

- 教学战静止帧在 4K 下 P95 小于 3 ms；
- 攻击模式 hover 查询小于 0.5 ms；
- 同一格内移动鼠标不触发查询和重绘；
- 4K/160 Hz 下教学战与复杂叠加层战斗 P99 均低于 6.25 ms，并保留至少 30% 余量。

### 第二阶段：处理切场景和操作尖峰

1. 水体生成图改用导入后的 Texture/Image 资源，不在每个棋盘 `_ready()` 中直接读文件。
2. 单位、宝石、动画帧资源使用共享缓存；移除正常运行路径中的 `CACHE_MODE_IGNORE`。
3. 在地图进入战斗前异步预热战斗场景和本关单位素材。
4. Profile 解锁改为内存批量记录，在场景稳定后或固定时机一次落盘。
5. 时间轴、槽位、状态图标改为节点复用或按差异更新，避免整组 `queue_free + new`。

第二阶段验收目标：战斗冷切入小于 200 ms，首个可见帧小于 16.7 ms；重复进入战斗不应出现同步资源读取警告。

### 第三阶段：图形选项与低端适配

1. 增加 60/120/无限 FPS 档和 VSync 选项。当前项目没有显式帧率上限，高刷屏会把主线程压力放大。
2. 增加“叠加层动画质量”设置：高档保留当前连续 shader，中档降更新频率，低档使用静态帧；保持叠加层的玩法可读性和前后遮挡语义。
3. 主菜单在无 hover、无过渡时降低粒子和按钮更新频率；必要时为全屏 FBM 提供低质量路径。

## 6. 玩家侧临时缓解办法

在后续优化完成前，可用以下方式进一步减轻体感：

- 暂时使用窗口模式，避免以 4K 全屏运行；
- 如果显卡控制面板支持，为该程序临时限制到 60 或 120 FPS，并保持稳定 VSync；
- 战斗动画速度调到 1.5× 或 2.0×只能改善串行动画的等待感，不能修复鼠标攻击预览和整板重绘导致的掉帧。

## 7. 建议新增的性能回归门禁

建议增加独立的性能探针，不混入普通语义测试：

- `battle_idle_frame_probe`：教学战与 `toxic_furnace` 各采样 600 帧；
- `battle_hover_query_probe`：分别测 idle/move/attack 64 格循环；
- `battle_scene_cold_start_probe`：记录 load、instantiate、ready、first visible frame；
- 固定输出平均、P95、P99、最大帧、draw calls、渲染对象、节点数；
- 性能结果写入 `artifacts/verify/performance.json`，只在专用机器上设硬门槛，普通开发机保留趋势对比。

## 8. 最终判断

本项目的卡顿是可定位、可修复的，且不需要降低核心玩法复杂度。优先改掉“每帧整板重绘”和“每次鼠标移动重算攻击预览”后，当前硬件应能非常轻松地稳定运行；复杂叠加层、资源预热和 HUD 节点复用属于随后收益明确的第二批工作。

## 9. 首批优化实施记录（2026-07-12）

本轮完成以下改动：

1. `BoardInputAdapter` 记录上一次逻辑格，同一格内的连续 MouseMotion 不再重复发出 `cell_hovered`；单位槽位 hover 仍逐事件更新，避免同格内不同槽位失去响应。
2. `BattleQueryService` 缓存移动可达范围和攻击范围；移动路径、命中范围、致死预测和黑槽死亡效果仍按当前 hover 格实时计算。
3. Controller 在状态变更和无 `state_changed` 的移动、攻击、主动触发完成后显式清理范围缓存；缓存 key 同时包含 state、玩家、位置、范围和编辑器无限行动状态作为防御。
4. 攻击范围扫描前只计算一次光宝石状态，不再对 64 个格重复查询相同条件。
5. 棋盘环境型连续重绘合并到最高 60 Hz；交互 setter、移动 Tween、投射物 Tween 和显式 VFX 仍可即时请求重绘。
6. `_sorted_cells()` 按棋盘尺寸和 origin 方向缓存，避免一次 `_draw()` 内四次重新创建并排序 64 格数组。
7. `set_hover`、`set_timeline_hover_unit`、`set_active_turn_unit` 对相同值直接返回，减少重复失效。

同机 1600×900、Compatibility、关闭 VSync、预热后复测：

| 指标 | 优化前 | 首批优化后 | 变化 |
|---|---:|---:|---:|
| 移动 hover 查询平均 | 约 0.85–1.01 ms | 0.027 ms | 约降低 97% |
| 攻击 hover 查询平均 | 约 5.58–5.70 ms | 0.029 ms | 约降低 99.5% |
| 稳态平均帧耗时 | 约 2.9 ms | 0.99 ms | 约降低 66% |
| 720 个渲染帧中的棋盘重建 | 原逻辑接近逐帧 | 46 次 | 环境动画不再跟随无限帧率重建 |

复测 P95 为 2.35 ms、P99 为 3.36 ms；较慢帧主要是保留的实际重绘帧。数值来自诊断运行，不作为跨机器硬门槛。

本轮新增 `board_input_adapter_test.gd`、`battle_query_cache_test.gd`，并扩展 `battle_renderer_timing_test.gd`，覆盖同格去重、缓存防污染、缓存清理、60 Hz 合并和排序缓存。下一批优先处理同步资源加载、Profile 连续写盘以及 HUD 控件反复重建。

验证结果：

- `tools/verify fast`：23/23 通过；
- `tools/verify all`：69 通过、3 失败；3 项与仓库已记录的基线问题一致，分别是 `overlay_render_contract_test`、`water_frame_composite_test`、`water_render_contract_test`，不在本轮优化范围内；
- 可执行宝石语义覆盖：71/90（78.88%）；
- 三枚爆炸宝石的固定战斗快照通过，战斗与事件不变式无违反。
