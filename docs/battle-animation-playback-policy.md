# 战斗动画播放策略

这份文档定义战斗事件的动画并发与结算屏障。代码权威入口是
`BattlePresentationPlanner`；新增事件必须同时登记 `mode` 与 `barrier`，不能在
`BattleEventPlayer` 里临时追加固定 `await`。

## 两个互相独立的问题

- `mode` 决定同一 beat 内的动画是串行还是并行。
- `barrier` 决定下一条具有因果关系的 beat 何时可以开始。

`await` Godot timer 不会占住操作系统线程，但会暂停当前战斗表现协程。另一方面，
在一帧内批量创建节点、材质、Tween，或首次准备 shader，确实会消耗 Godot 主线程
和渲染线程。两类卡顿必须分别处理。

## 屏障定义

| 屏障 | 下一 beat 的启动时机 | 适用条件 |
| --- | --- | --- |
| `complete` | 动画和空间运动全部完成后 | 后续事件依赖当前位置、占格、存活可见性 |
| `impact` | 弹道或效果抵达命中帧后 | 命中时推进展示态，烟尘、闪光、消散继续播放 |
| `none` | 当前帧启动效果并应用展示态后 | 纯反馈、纯装饰或没有可见运动的状态事件 |

如果 `impact` beat 内同时包含击退等 `impact_motions`，整个 beat 自动升级为
`complete`，但爆炸烟尘等视觉尾段本身仍不参与等待。

## 完整事件矩阵

| 事件 | beat 家族 | 同 beat 播放 | 屏障 | 说明 |
| --- | --- | --- | --- | --- |
| `move_step` | move | 自动：同单位路径串行，不同强制位移并行 | `complete` | 后续落点依赖占格 |
| `displacement_impact` | move | 同一来源并行 | `complete` | 撞击回弹属于空间运动 |
| `impact_charge` | impact | 冲刺与命中位移按命中帧编排 | `complete` | 冲刺和击退全部收口后继续 |
| `projectile` | projectile | 同 volley 并行 | `impact` | 抵达后结算伤害 |
| `projectile_deflect` | projectile | 同 volley 并行 | `impact` | 抵达后继续 |
| `explode` | blast | 同爆炸簇并行 | `impact` | 命中帧结算；烟尘与 shader 消散不阻塞 |
| `light_beam` | light_beam | 同轮并行 | `impact` | 命中帧结算；余辉不阻塞 |
| `arc` | electrical | 同一跳并行 | `impact` | 命中帧结算；电弧消散不阻塞下一跳 |
| `lightning` | electrical | 同一轮并行 | `impact` | 与电弧相同 |
| `damage` | damage | 连续纯伤害并行反馈 | `none` | 伤害反馈启动时立即推进展示态 |
| `poison_burst` | area_fx | 同类连续事件并行 | `none` | 云雾是视觉尾段 |
| `fire_burst` | area_fx | 同类连续事件并行 | `none` | 火焰消散不阻塞 |
| `frost_pulse` | area_fx | 同类连续事件并行 | `none` | 冰霜消散不阻塞 |
| `split_spawn` | split_spawn | 连续分裂并行 | `none` | 生成态与闪光同帧出现 |
| `gem_flash` | single | 按事件顺序启动 | `none` | 纯提示 |
| `gem_transfer` | single | 按事件顺序应用 | `none` | 当前无空间动画 |
| `miss` | single | 按事件顺序启动 | `none` | 纯反馈 |
| `toxic_smoke` | single | 按事件顺序应用 | `none` | 当前无独立阻塞动画 |
| `entity_destroyed` | single | 按事件顺序应用 | `none` | 当前无独立销毁动画 |
| `trample_start` | single | 按事件顺序应用 | `none` | 动作标记，运动由后续事件负责 |
| `die` | single | 串行 | `complete` | 死亡表现完成后才移除展示态单位 |
| `spawn` | single | 按事件顺序启动 | `none` | 单位出现与闪光同步 |
| `transform` | single | 按事件顺序启动 | `none` | 变形态与闪光同步 |
| `status` | single | 按事件顺序应用 | `none` | 当前没有独立运动 |
| `heal` | single | 按事件顺序应用 | `none` | 当前没有独立运动 |
| `knockback` | single（兼容） | 串行 | `complete` | 新规则必须改用 `move_step` |

## 电弧专项

规则层按真实因果顺序产出“本跳全部电弧 → 本跳全部伤害 → 下一跳”。播放器只把
同一跳的电弧合成一个并行 beat，并等待 `impact_time`；不再等待
`duration - impact_time` 的消散时间。

底层电弧仍运行在 Godot 主线程/渲染线程。为避免每次连锁命中都在同一帧创建两套
`ColorRect + ShaderMaterial + Tween`，棋盘在进入场景时预建 lightning、radial 和
cloud shader 节点池，并在首帧提交一次不可见的极小绘制来预热 shader；播放时租用，
结束后归还。超过池容量时仍允许临时扩容，保证效果不会因性能策略而丢失。

## 维护约束

1. 规则层只负责产出真实因果事件顺序。
2. Planner 决定事件聚类、并发方式和屏障；未登记事件直接拒绝播放。
3. Player 只等策略要求的阶段，不能为了“看起来慢一点”增加结算延迟。
4. Renderer 返回 `impact_time` 和 `duration`；视觉尾段自行收尾。
5. 位移、死亡等状态依赖动画必须完成；粒子、闪光、余辉不能阻塞结算。
