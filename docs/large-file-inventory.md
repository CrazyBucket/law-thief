# 大文件盘点与拆分候选

盘点时间：2026-07-14  
范围：项目工作区；排除 `.git/`、`.godot/`、`artifacts/`。  
说明：资源按文件体积筛选，代码/配置按准确行数筛选。当前工作区原本已有大量修改，本盘点未修改任何既有文件。

## 结论

- 盘点时体积最大的运行时资源是 `assets/audio/menu_bgm_lawthief.wav`，18.13 MB；该冗余 WAV 已于 2026-08-09 移除，菜单统一使用 1.69 MB OGG。
- 四个核心巨石已完成结构拆分：入口 `battle_scene.gd`、`isometric_board.gd`、`gem_effects.gd`、`data_registry.gd` 当前分别为 915、456、988、657 行；最大拆分层为 1,189 行。
- 生产脚本统一采用 600 行审查线和不可豁免的 1,300 行硬上限；超过 600 行必须登记职责与百行档预算，至少保留 50 行余量，回落后必须删除登记。
- 当前下一批结构候选是 `balance_config_validator.gd`、`battle_editor_cli.gd` 和 `battle_hud_presenter.gd`，但都已处于硬上限内，不再以单纯减少行数为目标。
- 盘点发现的两张相同旧标题图已于 2026-08-09 删除；主菜单只保留实际使用的 `assets/ui/main_title_v2.png`。
- `tmp/` 当前有 152 个文件、约 18.6 MB，且其中 37 个文件已被 Git 跟踪；它们仍需明确“评审产物”还是“正式资源”。

## 已执行

- 已从 `BattleScene` 抽取 `scripts/ui/battle_reward_overlay.gd`：它单独负责奖励弹窗外壳、卡片横向滚动、操作按钮和卡片入场/悬停效果。
- 业务选择、结算状态机和存档推进仍保留在 `BattleScene`，保证本次只移动表现层共用机制，不改变奖励语义。
- 已从 `BattleScene` 抽取 `scripts/ui/battle_reward_card_factory.gd`：掉落宝石、槽位嵌入、宝石和遗物卡片只渲染内容并以回调交还选择；内容目录与外观服务显式注入。
- 已从 `IsometricBoard` 抽取 `scripts/ui/battle_light_beam_fx.gd`：光束节点、渐变、清理和染色过渡由专用层持有，棋盘只注入投影与视觉配置。
- 已从 `IsometricBoard` 抽取 `scripts/ui/battle_projectile_fx.gd`：齐射状态、贝塞尔插值、绘制和完成信号由专用层持有，棋盘不再维护投射物数组。
- 已从 `IsometricBoard` 抽取 `scripts/ui/battle_particle_fx.gd`：程序粒子、序列帧、生命周期和绘制由专用层持有；棋盘仅提交表现描述并注入纹理缓存。
- 已从 `BattleHudPresenter` 抽取 `scripts/ui/battle_hud_relic_bar.gd`：遗物栏布局、图标缓存、悬停反馈和点击接线由独立组件持有，Presenter 仅注入库存、纹理与详情回调。
- 已从 `DataRegistry` 抽取 `scripts/services/encounter_enemy_resolver.gd`：固定敌军、权重编组与随机候选的解析无状态化；战斗 RNG 以回调注入，避免解析器读取全局服务。
- 已从 `DataRegistry` 抽取 `scripts/services/encounter_catalog_loader.gd`：遭遇目录扫描、重复检测与校验报告通过显式回调组合，注册表只保存通过校验的内容。
- 已从 `BalanceConfigValidator` 抽取 `scripts/services/gem_def_validator.gd`：宝石字段、稀有度、组合与能力档案校验集中在单一纯静态模块，原验证器保留兼容入口。
- 已从 `BattleQueryService` 抽取 `scripts/ui/battle_overlay_presenter.gd`：兼容 overlay/route schema、去重、元数据与敌方意图表现投影由纯 presenter 负责，查询服务降至 576 行。
- `IsometricBoard` 已删除旧 `set_highlights()`、散字段 fallback 与重复描边路径，统一由 `set_overlays()` 接收 presenter/map specs。
- `BattleScene` 已按流程基类、编辑器适配和场景入口拆为 1,170 / 717 / 915 行；奖励、编辑器、槽位面板、重绘节奏、战斗特效和 overlay 契约继续由原测试固化。
- 菜单音乐已收口到 `AudioService` 的 OGG 播放入口，移除重复场景播放器和未引用 WAV。
- `IsometricBoard` 已抽取后景覆盖层和动画状态容器；高亮、路线、地表后景以 30 Hz 独立更新，单位、前景遮挡和 HUD 顺序保持不变。
- 战斗场景与棋盘的可选资源缓存已分别抽取为 `battle_scene_lazy_resources.gd` 和 `battle_board_resources.gd`；编辑器/结算脚本、实体贴图和战斗着色器不再无条件进入普通战斗冷加载路径。
- 已从 `BattleScene` 抽取并按需加载 `battle_reward_view.gd`：宝石、掉落物、槽位嵌入和遗物视图构建不再进入普通战斗冷加载路径，公开构建入口保持转发兼容。
- 水层节点顺序保持稳定，水面材质、生成图、上下水面纹理和浅水遮罩改为首次出现相应水体时加载；浅水层以状态 revision 和棋盘变换作为扫描缓存键。
- 棋盘固定底图的非白内容区域改为预计算常量，移除每次入场约 39 万次像素检查；渲染契约测试会重新扫描源 PNG，确保常量与实际素材同步。
- 敌人意图规划增加可采纳路径下界：通用近战与裂变史莱姆跳过不可能更优的 A*，石弓守卫复用开火锚点并用无权 BFS 下界筛选原加权 A*；候选顺序、完整 footprint 和评分规则保持不变。
- 单位意图柔光由原生径向渐变替代逐像素脚本生成；主菜单按每帧一个图标预热 22 个意图资源并在完成后自我释放，降低首战单位 UI 的同步加载尖峰。
- 棋盘的槽位范围规则改由控制器回调注入，毒雾表现改用轻量视觉几何模块，不再显式加载 `GemRules`/`BoardUtils`；普通控制器按需加载编辑器服务，暂停菜单与离场确认框首次使用时创建。
- 主菜单在正式渲染客户端后台预取战斗场景，普通、精英和 Boss 房间统一通过线程转场进入战斗；架构守卫禁止重新引入同步战斗切场。
- 战斗编辑器的面板/检查器构建、放置预览、摘要、宝石/遗物列表和状态按钮已抽取为 526 行的 `battle_editor_view.gd`，仅在编辑器战斗中动态加载；`BattleScene` 因此减少 385 行。
- 宝石插入/拔出槽位面板的绘制、命中和 hover 状态已抽取为 278 行的 `battle_unit_slot_panel_renderer.gd`；普通战斗保持不加载，首次进入插入或拔出动作时才通过棋盘资源表创建。
- 光束、投射物、粒子、Shader 池、预热器和特效纹理从棋盘急切预载改为首帧后四阶段准备；对应播放入口可独立即时加载，棋盘显式预载闭包进一步降至 28 文件、6,636 行。
- 玩家与史莱姆待机动画改为仅在实际贴图帧变化时重绘；行动光环以 30 Hz 采样，静止教学战的整板重绘由原 60 Hz 降至实测约 29–31 Hz，移动和战斗动画仍保留 60 Hz。
- 两张未被运行时引用的旧标题图已删除，共减少约 1.05 MB；当前标题 `main_title_v2.png` 保留。
- `IsometricBoard` 已按 FX 基础、移动动画、单位渲染、地表渲染和生命周期入口拆为 856 / 519 / 830 / 769 / 456 行，原场景脚本路径不变。
- `GemEffects` 已按共享运行时原语、效果结算和触发门面拆为 105 / 1,189 / 988 行；为避免规则依赖环，爆炸、冲击、攻击管线与位移模块保持调用时或最终门面加载。
- `DataRegistry` 已按稳定查询 API 与运行时加载/恢复实现拆为 1,179 / 657 行，autoload 路径和公开方法保持不变。
- 文件体积守卫已升级为统一硬上限并加入自检；源码编码守卫同时拒绝替换字符和常见 UTF-8/GBK 乱码特征。
- 本轮不处理美术资源压缩、字体裁剪或 `tmp/` 评审图归档；当前资源可用性优先。

## 体积大于等于 100 KB 的全部文件

| 大小 | 文件 |
| ---: | --- |
| 6.69 MB | `assets/ui/fusion-pixel-12px-zh_hans.ttf` |
| 2.12 MB | `assets/ui/adventure_map_sky_ruins.png` |
| 1.98 MB | `assets/ui/background.png` |
| 1.69 MB | `assets/audio/menu_bgm_lawthief.ogg` |
| 1.61 MB | `assets/ui/tiles.png` |
| 1.57 MB | `assets/ui/main_menu_bg.png` |
| 748.6 KB | `assets/tiles/mew_water_bottom.png` |
| 728.8 KB | `assets/tiles/mew_water_top.png` |
| 430.5 KB | `assets/demo/doodle-rpg/ALL SPRITES/Sheet Grassy.png` |
| 391.8 KB | `assets/demo/doodle-rpg/ALL SPRITES/Sheet.png` |
| 365.1 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Random.PNG` |
| 322.8 KB | `tmp/map_icon_review/elite_combat_candidate_alpha.png` |
| 314.2 KB | `tmp/map_icon_review/shop_candidate_alpha.png` |
| 310.9 KB | `tmp/map_icon_review/end_candidate_alpha.png` |
| 307.9 KB | `tmp/map_icon_review/end_boss_candidate_alpha.png` |
| 300.9 KB | `assets/ui/main_title_v2.png` |
| 277.9 KB | `tmp/map_icon_review/normal_combat_candidate_alpha.png` |
| 250.8 KB | `assets/overlays/effects/overlay_toxic_smoke_body.png` |
| 244.2 KB | `tmp/map_icon_review/event_candidate_alpha.png` |
| 233.4 KB | `tmp/map_icon_review/rest_site_candidate_alpha.png` |
| 194.4 KB | `tmp/map_icon_review/start_candidate3_alpha.png` |
| 187.7 KB | `tmp/map_icon_review/start_candidate_alpha.png` |
| 177.3 KB | `assets/overlays/vegetation/overlay_grass_thicket.png` |
| 171.8 KB | `tmp/map_icon_review/start_candidate2_alpha.png` |
| 161.4 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Sword Swing/Frames2.PNG` |
| 142.2 KB | `assets/overlays/vegetation/overlay_grass_tall.png` |
| 122.4 KB | `scripts/ui/isometric_board.gd` |
| 123.5 KB | `assets/units/female-adventurer/frame dimensions.png` |
| 106.9 KB | `scripts/ui/battle_scene.gd` |
| 110.6 KB | `assets/demo/doodle-rpg/ALL SPRITES/Extras.png` |
| 105.5 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Sword Swing/Frames3.PNG` |
| 105.5 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Sword Swing/Frames1.PNG` |
| 103.1 KB | `assets/overlays/vegetation/overlay_grass_patch.png` |

## 代码/测试大文件（大于等于 500 行）

这些文件不一定都应拆分；测试文件通常是场景集合，需先判断是否只是数据量大。

| 行数 | 文件 | 初步判断 |
| ---: | --- | --- |
| 3,390 | `scripts/ui/isometric_board.gd` | P0：棋盘绘制、单位/覆盖物、宝石、移动动画和战斗特效编排仍集中在一个 Control |
| 2,892 | `scripts/ui/battle_scene.gd` | P0：战斗页面、输入、流程、结果页和动画接线仍集中在一个 Control |
| 2,479 | `scripts/rules/gem_effects.gd` | P0：宝石触发、伤害/位移、死亡链、光束/导电、毒/分裂等规则集中 |
| 1,829 | `scripts/services/data_registry.gd` | P0：数据加载、解析、查询、随机池、奖励、运行时实例化、存档恢复集中 |
| 1,518 | `scripts/services/balance_config_validator.gd` | P1：多个配置域共用一个校验器，适合按配置域拆分 |
| 1,241 | `scripts/ui/battle_hud_presenter.gd` | P1：状态检查、槽位提示、时间线、遗物栏、布局适配集中 |
| 1,226 | `scripts/debug/battle_editor_cli.gd` | P1：命令分发、参数解析、对象变更、导入导出、格式化集中 |
| 1,008 | `scripts/services/adventure_config_validator.gd` | P1：冒险、遭遇、经济、奖励、地图规则校验集中 |
| 983 | `scripts/rules/attack_pipeline.gd` | P1：攻击阶段与大量宝石/遗物特例混在同一管线 |
| 911 | `scripts/tests/balance_config_test.gd` | P2：测试数据/断言量大，先保持边界清晰再拆 |
| 839 | `scripts/services/run_service.gd` | P1：运行状态、路线、奖励、恢复与持久化边界需确认 |
| 823 | `scripts/main/main_root.gd` | P1：主菜单、设置、页面构建、粒子、音乐、元控制台集中 |
| 790 | `scripts/rules/status_rules.gd` | P1：状态增减、触发与派生效果集中 |
| 788 | `scripts/map/tile_renderer.gd` | P1：地图瓦片、房间路线、覆盖物和绘制逻辑集中 |
| 781 | `scripts/debug/battle_editor_service.gd` | P1：编辑器操作与运行时状态变更集中 |
| 758 | `scripts/rules/board_utils.gd` | P1：棋盘查询、路径、占用和规则辅助集中 |
| 713 | `scripts/tests/fission_slime_test.gd` | P2：单敌人场景测试较大，确认是否可按行为拆分 |
| 634 | `scripts/battle/battle_query_service.gd` | P1：战斗查询接口边界较宽 |
| 583 | `scripts/services/relic_effect_registry.gd` | P1：遗物效果注册/执行可按触发时机或主题拆分 |
| 582 | `scripts/rules/overload_rules.gd` | P1：过载计算与效果触发集中 |
| 561 | `scripts/ui/battle_event_player.gd` | P1：事件解释、动画调度和表现层状态推进集中 |
| 548 | `scripts/ui/rich_tooltip.gd` | P2：可按内容模型、布局和主题拆分 |
| 526 | `scripts/ui/battle_editor_view.gd` | P2：编辑器专用视图组件，保持按需加载且不再扩张 BattleScene |
| 508 | `scripts/tests/blue_black_combo_test.gd` | P2：组合场景测试较大 |

## 建议的拆分顺序

### 第一批：先拆表现层巨石

1. `battle_scene.gd`
   - `BattleInputCoordinator`：点击、悬停、拖放、宝石槽位操作。
   - `BattleSettlementView`：结算、金币、宝石、遗物、掉落选择和战斗结果页。
   - `BattleEditorView`：编辑器面板、工具预览、检查器和编辑器操作接线。
   - `BattleHudPresenter` 已存在，应继续把状态面板/顶部栏/按钮刷新迁出；主场景只保留生命周期和依赖注入。

2. `isometric_board.gd`
   - `BoardRenderer`：瓦片、网格、高亮、路线和地图标牌。
   - `UnitRenderer`：单位精灵、朝向、状态、血条、意图和槽位扇区。
   - `GemVisualLayer`：掉落宝石、持有宝石、插入/提取动画。
   - `CombatFxLayer`：闪电、爆炸、毒雾、投射物、光束和伤害表现。
   - 保留 `IsometricBoard` 作为状态快照、坐标转换、输入命中和子渲染器编排入口。

### 第二批：拆规则与数据边界

3. `gem_effects.gd`
   - 按触发时机拆成 unit/tile hook、damage interception、death chain、displacement、light/element、spawn/split 六组；先保持现有静态入口，内部转发到主题模块。
   - 每组迁移后用现有 gem contract、事件校验和固定 seed 场景锁定语义，避免把拆分误当成规则变更。

4. `data_registry.gd`
   - `ContentLoader`：JSON 加载/解析/引用校验。
   - `ContentQuery`：单位、宝石、瓦片、覆盖物、遗物查询。
   - `RewardPoolService`：宝石/遗物池与随机 offer。
   - `BattleStateFactory`：战斗状态创建、编辑器 payload 和恢复。

5. 校验器
   - `BalanceConfigValidator` 按 relic/gem/unit/combat/status 五个配置域拆分。
   - `AdventureConfigValidator` 按 progression/encounter/economy/reward/map 五个配置域拆分。

### 第三批：治理重复资源与中型文件

- 将 `tmp/` 评审图移到明确的非运行时归档位置，或加入忽略规则；删除/移动前先确认是否被设计评审引用。
- 对重复标题图保留一个正式来源，另一个改为引用或删除；这属于资源变更，需单独确认运行时引用。
- `attack_pipeline.gd`、`status_rules.gd`、`enemy_ai.gd`、`board_utils.gd` 等 600–1,000 行文件在第一批完成后再拆，避免同时改变战斗状态与表现层边界。

## 重构护栏

- 每次只迁移一个职责簇，保持原入口函数签名，先通过转发降低调用方改动面。
- 涉及战斗或宝石行为时，遵循 `AGENTS.md` 的 `context`、`snapshot`、`coverage`、`verify` 顺序；设计源与实现冲突时先记录冲突。
- `IsometricBoard` 拆分不能引入新的直接 `unit.pos = ...` 写入；移动仍通过 `GameState.move_unit()`，表现层状态也要同步占用索引。
- 每批迁移后运行架构测试、事件形状校验和对应 gem semantic contract；不要只以普通测试全绿作为完成标准。
- 资源压缩、格式转换和重复资源清理应与代码拆分分开提交，便于回滚和定位体积变化。
