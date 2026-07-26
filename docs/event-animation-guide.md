# 战斗表现层重构指南

当前事件的完整并发与结算屏障矩阵见
[`battle-animation-playback-policy.md`](battle-animation-playback-policy.md)。

## 目标

这份文档不再描述“当前 `battle_scene.gd` 如何批处理事件”，而是定义战斗表现层接下来的重构方向，并持续记录当前重构进度。

这次重构要解决的核心问题不是代码风格，而是以下三个稳定性问题：

- 动画结算顺序容易错乱，连锁事件一多就开始依赖人工 `await`
- 棋盘显示状态和真实逻辑状态切换频繁，容易出现位置跳变
- 上一个动作尚未完整播放，下一段敌方行动或战斗结束逻辑就开始推进

重构目标是把 `battle_scene.gd` / `isometric_board.gd` 中混杂的职责拆开，并建立一个**单一的表现调度入口**。

---

## 当前问题总结

### 1. `battle_scene.gd` 职责过多

当前 `battle_scene.gd` 同时负责：

- 玩家输入后的 action 调度
- HUD 刷新
- 预览面板和检视面板
- 事件批处理与动画播放
- `_display_state` 的推进
- 敌方回合循环
- battle end / reward / 跳场景

这导致“表现调度”和“界面刷新”强耦合，只要新增一种事件或 UI 分支，就容易破坏现有时序。

### 2. `isometric_board.gd` 同时承担渲染、输入、动画运行时

当前 `isometric_board.gd` 同时负责：

- 棋盘绘制
- 单位绘制
- 高亮与 hover
- 鼠标拾取与点击
- 位移动画
- 投射物动画
- 粒子 / 爆炸 / gem 特效
- 朝向与选中态

这使得 board 不再是单纯的 renderer，而变成了一个“又画又管又播”的巨型对象。

### 3. `animation_finished` 语义过宽

当前 board 用同一个 `animation_finished` 信号承载多类动画结束语义：

- 单位移动结束
- 并行位移结束
- 投射物结束
- 某些未来可能加入的表现结束

这类全局完成信号在规模小时可用，但一旦同时存在多种表现，就很容易出现等待了错误动画、或者外层误以为“整段表现已经结束”的问题。

### 4. `_display_state` 与真实 state 切换过于脆弱

当前表现逻辑依赖：

- `_start_presentation()` 切到 `_display_state`
- `_prime_event_state()` 预写状态
- board 通过 offset 假装对象仍在动画途中
- `_finish_presentation()` 再切回 `_controller.state`

这套方式不是不能用，但它要求：

- 表现态只能由一个地方推进
- board 的临时动画缓存不能被中途清空
- 下一段 presentation 不能在上一段 offset 尚未收尾时开始

当前这些约束主要靠布尔值和人工 `await` 维持，稳定性不够。

### 5. 当前锁是布尔锁，不是状态机

当前流程依赖 `_player_animating`、`_presentation_playing`、`_enemy_phase_running` 等标志位挡输入和挡流程。

这类锁能解决最基础的问题，但不能严谨表达：

- 当前是玩家表现中，还是敌人表现中
- battle end 是否已到达但尚未 flush
- reward overlay 是否正在阻塞输入
- 当前是否允许切换到下一只敌人

后续事件复杂度继续增长时，布尔锁会越来越难维护。

---

## 目标架构

目标不是把代码机械拆成 4 个文件，而是建立下面这套职责边界：

```text
BattleScene
  |- BattleEventPlayer
  |- BattleHudPresenter
  |- BoardInputAdapter
  |- BoardRenderer
```

### 1. `BattleScene`

`BattleScene` 最终只保留“协调器”职责：

- 接收 controller 返回结果
- 调用 `BattleEventPlayer` 播放整段 presentation
- 在 presentation 完成后推进 phase / reward / navigation
- 负责把 renderer、HUD、input adapter 连接起来

它不再直接处理事件批次细节，也不再手动穿插大量动画等待逻辑。

### 2. `BattleEventPlayer`

这是这次重构的核心。

职责：

- 作为**唯一的主表现调度器**
- 接受 `presentation_state + final_state + events`
- 顺序或批量播放事件
- 独占 `_display_state` 的推进权
- 统一管理播放锁 / 队列 / flush battle end 时机

应迁入这个模块的逻辑包括：

- `_play_presented_events`
- `_collect_consecutive_events`
- `_collect_blast_tail`
- `_play_damage_batch`
- `_play_area_fx_batch`
- `_play_parallel_move_batch`
- `_play_move_path_batch`
- `_play_projectile_volley`
- `_prime_event_state`
- `_apply_event_state`

核心原则：

- 外层不再直接 `await _board.animation_finished`
- 外层只 `await event_player.play(...)`
- 任何 battle end、enemy next turn、reward popup 都必须等 event player 完成

### 3. `BattleHudPresenter`

职责：

- 根据当前 view state 刷新 HUD
- 刷新按钮可用性、顶部信息、turn queue、预览面板、检视面板
- 统一处理“当前应该展示 `_display_state` 还是 `_controller.state`”

它不负责：

- 事件时序
- renderer 动画
- 控制器 action 执行

### 4. `BoardInputAdapter`

职责：

- 处理鼠标移动、点击、拾取
- 调用坐标换算，把屏幕输入翻译成 grid intent
- 根据当前状态决定是否屏蔽输入

它不负责：

- 棋盘绘制
- 动画等待
- HUD 刷新

迁移目标是把当前 `_gui_input()` 和相关 cell emit 逻辑从 board 本体中拆出去。

### 5. `BoardRenderer`

职责：

- 只关心“如何画”和“如何执行底层视觉效果”
- 维护局部动画缓存，例如 move offset、投射物轨迹、粒子、gem visuals
- 对外暴露明确的低层播放接口

它不负责：

- phase 流程
- 敌方轮询
- `_display_state` 生命周期管理
- HUD 与输入判断

`BoardRenderer` 仍然可以保留低层 API，例如：

- `animate_move(...)`
- `animate_move_path(...)`
- `animate_moves_parallel(...)`
- `play_projectiles(...)`
- `play_explosion(...)`
- `play_damage_effect(...)`

但这些 API 只应该由 `BattleEventPlayer` 调用。

---

## 新的时序原则

### 原则零：先规划，后播放

规则事件不能再直接驱动 renderer。`BattlePresentationPlanner` 必须先把完整事件流编译为 beat；
每个 beat 都包含：

- `kind`：投射物、爆炸、电弧、位移等演出家族
- `mode`：`serial` 或 `parallel`
- `visuals`：起手、弹道、扩散等视觉阶段
- `impacts`：展示态伤害和命中反馈
- `impact_motions`：与冲击伤害同时启动的击退等位移
- `aftermath`：地块变化、分裂生成等后续阶段

任何新事件类型都必须先登记 presentation policy。未登记类型会同时被
`EventValidator` 和 `BattlePresentationPlanner` 拒绝，不能进入播放阶段。

禁止新增“在 `BattleEventPlayer` 主循环里看到事件后临时决定怎么 await”的分支。
并发关系必须在 renderer 启动任何动画之前由 planner 决定。

### 命中时序约束

- 投射物：同一 volley 的弹道并发；弹道完成后才应用该 volley 的 impact。
- 爆炸：先启动爆炸视觉；冲击波到达时同时应用范围伤害并启动击退，烟尘等余波继续播放。
- 强制位移：规则层统一产出 `move_step`；撞墙、实体或单位时追加 `displacement_impact`。表现层按单位归并为一条运动序列，禁止调用方自行拼接位移动画。
- 受击：所有 `damage` 事件都通过统一伤害反馈入口触发单位受击状态；具体单位优先使用专用受击帧，没有专用素材时使用动作帧回退。
- 电弧：同一跳的电弧并发；电弧抵达后应用该跳伤害；下一跳随后开始。
- 光束：同一轮光束并发；伤害绑定光束 impact，不允许先扣展示态生命。
- 纯伤害：只有不存在前置视觉时，才允许作为独立 damage beat 播放。

### 原则一：任何时刻只能有一个主 presentation 在播放

“主 presentation”指一次玩家动作、一次敌方动作、一次 reward 前的收尾、一次 battle end 收尾。

不允许：

- 玩家动作播放到一半开始敌方行动
- 敌方 A 的表现未结束就开始敌方 B
- battle end 回调先到达并直接跳场景

### 原则二：显示态只允许由 `BattleEventPlayer` 推进

`_display_state` 或未来的 `presentation_state` 必须只有一个 owner。

这样可以避免：

- HUD 一边读逻辑态，一边 board 在画表现态
- 某段事件还没播完，外层先切回真实 state
- `set_battle_state()` 导致 renderer 清空临时动画缓存而出现跳变

### 原则三：批处理由 planner 决定，播放只属于 `BattleEventPlayer`

文档原本强调的 `damage` / `move_step` / `projectile` 批处理逻辑仍然保留；
但它不应再作为 `battle_scene.gd` 的内部技巧，而应成为 `BattleEventPlayer` 的职责。

也就是说：

- 规则层负责产出因果顺序正确的事件流
- `BattlePresentationPlanner` 在播放前识别 beat 并选择串行或并行
- `BattleEventPlayer` 只执行已经规划完成的 beat，并在 impact 推进展示态
- `BoardRenderer` 只负责执行底层表现

### 原则四：等待语义要从“全局 finished”改成“明确的播放任务”

短期内可以保留 board 现有信号；
但中期目标是把等待语义收口为更明确的接口，例如：

- `await event_player.play_move_batch(...)`
- `await event_player.play_projectile_batch(...)`
- `await event_player.play_action(result)`

而不是让外层四处直接等待 board 的泛化完成信号。

### 原则五：battle end 只能在事件播放 drain 后触发

当前 `_pending_battle_result` 的思路是对的，但应由 `BattleEventPlayer` 或表现协调层统一托管：

- battle 结束时先记录 pending result
- 当前表现播放完毕后统一 flush
- flush 之后才能弹奖励、切场景、恢复输入

---

## 模块迁移建议

### 从 `battle_scene.gd` 迁到 `BattleEventPlayer`

- 事件循环与批处理函数
- `_display_state` 的推进逻辑
- 播放完成后的 flush 逻辑
- 敌方单次 action 的表现播放封装

### 从 `battle_scene.gd` 迁到 `BattleHudPresenter`

- `_refresh()` 及其子刷新函数
- 状态面板、预览、queue、按钮状态
- view state 选择逻辑

### 从 `isometric_board.gd` 迁到 `BoardInputAdapter`

- `_gui_input()`
- hover / click 输入翻译
- 输入开关控制

### `isometric_board.gd` 作为 `BoardRenderer` 暂时保留的内容

- 棋盘与单位绘制
- move offset / strike / projectile / particle / gem visual 等低层表现运行时
- 局部视觉缓存
- 纯绘制辅助函数

这一步允许先“逻辑拆分，文件名暂不改”，等职责稳定后再正式 rename。

---

## 当前进展

截至当前代码状态，已经完成的改动有：

- 已抽出 `BattleEventPlayer`，`battle_scene.gd` 不再自己维护事件批处理与 presentation state
- 已抽出 `BoardInputAdapter`，`isometric_board.gd` 不再直接处理 `_gui_input()`
- 已抽出 `BattleHudPresenter`，`battle_scene.gd` 的 HUD 刷新职责已明显收口
- `isometric_board.gd` 已开始把动画运行时集中到 `_anim` / `BoardAnimationHostState`

当前仍在继续推进的方向：

- 继续收窄 `isometric_board.gd` 的 renderer 边界
- 逐步减少外层对 `animation_finished` 的泛化依赖
- 评估是否把动画宿主进一步独立成单独文件

---

## 推荐落地顺序

### Phase 1：先抽 `BattleEventPlayer`（已完成）

第一步不要同时动 HUD 和 input。

先做最小重构：

- 新建 `BattleEventPlayer`
- 把 `_play_presented_events` 相关逻辑整体迁入
- `BattleScene` 改成只发起 `await event_player.play(...)`
- 保持 renderer 仍然是当前 board

这一步的目标不是结构完美，而是先把**时序控制收口到一个地方**。

### Phase 2：把 presentation state 的 owner 固定下来（已完成）

- `BattleEventPlayer` 持有并更新 presentation state
- `BattleScene` 只通过 `event_player.get_view_state()` 或 signal 获取当前显示态
- 避免外层直接切换 board state 导致缓存重置

### Phase 3：抽 `BoardInputAdapter`（已完成）

- 把 `_gui_input()` 拆出去
- board 改成纯显示对象
- 输入屏蔽统一看 event player / scene state

### Phase 4：抽 `BattleHudPresenter`（已完成）

- HUD 从 scene 中剥离
- 让 scene 只保留 orchestration

### Phase 5：收窄 `BoardRenderer` 接口（进行中）

- 逐步减少外层对 `animation_finished` 的直接依赖
- 让 board 只对 `BattleEventPlayer` 暴露低层视觉能力

---

## TODO

### P0：先解决顺序错乱与跳变

- [x] 新建 `BattleEventPlayer`，迁移事件循环与批处理逻辑
- [x] 把 `_prime_event_state` / `_apply_event_state` 一并迁入 `BattleEventPlayer`
- [x] `BattleScene` 改为只调用 `await event_player.play(...)`
- [x] 禁止 `BattleScene` 继续直接 `await _board.animation_finished`
- [x] 把 battle end 的 pending / flush 收口到表现播放完成后统一处理

**验收标准：**

- 玩家动作播完前不会开始敌方动作
- 敌方 A 播完前不会开始敌方 B
- battle end 不会在表现未结束时直接弹奖励或切场景
- 常见爆炸 / 击退 / 投射物链路不再出现明显跳变

### P1：把职责边界真正拆开

- [x] 新建 `BoardInputAdapter`，迁移 `_gui_input()`
- [x] 新建 `BattleHudPresenter`，迁移 `_refresh()` 相关 UI 刷新逻辑
- [x] `BattleScene` 仅保留 orchestration 与装配逻辑
- [x] 统一 view state 来源：播放中读 presentation state，空闲时读 controller state

**验收标准：**

- `BattleScene` 不再同时维护 HUD、输入、事件播放三套逻辑
- board 不再直接承担输入翻译职责
- HUD 刷新不再依赖表现播放内部细节

### P2：清理 renderer 接口

- [ ] 将 `isometric_board.gd` 的职责收敛为 `BoardRenderer`（进行中：动画运行时已集中到 `_anim` / `BoardAnimationHostState`）
- [x] 减少泛化 `animation_finished` 的外溢使用范围（`BattleEventPlayer` 已改用明确的 move / projectile task）
- [x] 为 move / projectile / parallel move 建立更明确的等待语义
- [ ] 评估 gem visual / damage text / overlay 是否继续留在 renderer，还是拆成独立 visual layer

**验收标准：**

- board 对外接口更少、更明确
- 新增动画类型时，不需要继续往 `BattleScene` 塞 `await` 分支
- renderer 可以独立演进，不影响 phase 调度

---

## 文档结论

接下来这份文档的指导思想只有一句话：

**批处理仍然重要，但真正要先解决的是“谁负责播完整段表现”。**

在新架构里：

- 规则层负责产出顺序正确的事件流
- `BattleEventPlayer` 负责把整段表现可靠播完
- `BoardRenderer` 负责执行底层视觉效果
- `BoardInputAdapter` 负责输入翻译
- `BattleHudPresenter` 负责界面展示
- `BattleScene` 只负责把这些东西串起来

先把“单一表现调度器”立住，再继续优化批处理和视觉细节，后面的动画问题才会真正收敛。
