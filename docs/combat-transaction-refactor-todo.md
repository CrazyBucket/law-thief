# Combat Transaction Refactor TODO

## Purpose

这篇文档记录一项高价值代码层改造：引入战斗状态事务层 `CombatTransaction`（或 `BattleMutationContext`），把战斗中的状态变更、事件生成、表现态应用收敛到同一个可验证入口。

目标不是把文件机械拆小，而是减少三类长期风险：

- 规则层直接改 `GameState`，但事件流没有完整记录。
- 事件流记录了动画提示，但缺少足够字段恢复真实业务目标。
- 表现层播放事件时自行推断状态，导致显示态、真实态、占格索引漂移。

相关代码入口：

```text
scripts/data/game_state.gd
scripts/debug/event_validator.gd
scripts/debug/battle_invariant_checker.gd
scripts/rules/combat_rules.gd
scripts/rules/attack_pipeline.gd
scripts/rules/displacement.gd
scripts/rules/gem_effects.gd
scripts/rules/intent_system.gd
scripts/rules/enemy_ai.gd
scripts/rules/stone_bow_guard_rules.gd
scripts/rules/fission_slime_rules.gd
scripts/battle/battle_action_service.gd
scripts/ui/battle_event_player.gd
scripts/testkit/scenario_builder.gd
scripts/testkit/state_snapshot.gd
scripts/testkit/state_diff.gd
```

## Baseline Evidence

以下是启动本次重构时的基线，保留用于解释改造动机；当前完成状态见后文的 Closure Evidence。

项目当时已经有一部分正确基础：

- `GameState.move_unit()` 会同步 `_cell_occupancy`。
- `BattleInvariantChecker` 已能发现死亡单位占格、占格索引不一致、多格单位越界等问题。
- `EventValidator` 已对 `move_step`、`damage`、`explode` 等事件做基础字段校验。
- `StateSnapshot` / `StateDiff` / `./tools/snapshot` 已能记录 action 前后状态和事件流。

但当时状态变更仍然分散：

- 规则/战斗/UI 中仍存在多处直接 `*.pos = ...`。
- 玩家移动、敌方移动、强制位移分别手写 `move_step`。
- 多处 `damage` 事件只带 `pos` 和 `damage`，不带 `uid` / `victim_uid`。
- `BattleEventPlayer` 表现态中直接改 `unit.pos`，不会同步 `_cell_occupancy`。
- AI 评分和意图构建里存在临时改 `unit.pos` 再改回的模式。

这些问题短期不一定让测试变红，但会在机制组合增长后制造隐蔽漂移：动画找错目标、路径预览和执行不一致、显示态查 `get_unit_at(pos)` 时拿到旧占格。

## Target Architecture

新增一个轻量事务对象：

```text
CombatTransaction
  |- 持有 GameState
  |- 持有 events: Array[Dictionary]
  |- 统一提交 move / damage / kill / spawn / status 等状态变化
  |- 统一生成事件
  |- 在 debug/test 下校验事件和战斗不变量
```

建议文件：

```text
scripts/rules/combat_transaction.gd
scripts/rules/combat_event_builder.gd
scripts/tests/combat_transaction_test.gd
```

`CombatTransaction` 负责真实规则态；`CombatEventBuilder` 可作为纯事件工厂，供旧代码过渡期使用。

### Core API Sketch

```gdscript
class_name CombatTransaction
extends RefCounted

var state: GameState
var events: Array[Dictionary] = []

static func begin(state: GameState, existing_events: Array[Dictionary] = []) -> CombatTransaction

func move_unit(unit: UnitState, to_pos: Vector2i, opts: Dictionary = {}) -> void
func damage_unit(unit: UnitState, amount: int, source_uid: String, reason: String, opts: Dictionary = {}) -> int
func kill_unit(unit: UnitState, killer_uid: String = "", reason: String = "") -> void
func spawn_unit(unit: UnitState, opts: Dictionary = {}) -> void
func apply_status(unit: UnitState, status_id: String, stacks: int, duration: int, source_uid: String, opts: Dictionary = {}) -> void
func append_event(event: Dictionary) -> void
func finish(context: String = "") -> Array[Dictionary]
```

`opts` 用于承载当前已经存在的分支语义：

```text
forced: bool
voluntary: bool
source_uid: String
skip_tile_enter: bool
skip_gem_hooks: bool
collision_damage: int
attacker_uid: String
is_crit: bool
keep_facing: bool
event_reason: String
```

## Event Contracts

### `move_step`

必填字段：

```text
type: "move_step"
uid: String
from: Vector2i
to: Vector2i
```

建议扩展字段：

```text
source_uid: String
forced: bool
reason: String
path_index: int
path_total: int
```

规则：

- `from != to`。
- `uid` 必须对应执行移动的单位。
- 任何物理位置变化都必须通过事务生成 `move_step`，除非明确是无动画瞬移并记录原因。
- 事务内部调用 `state.move_unit()`，禁止调用方直接改 `unit.pos`。

### `damage`

必填字段目标：

```text
type: "damage"
uid: String
victim_uid: String
pos: Vector2i
damage: int
is_crit: bool
```

建议扩展字段：

```text
attacker_uid: String
source_uid: String
reason: String
lethal: bool
remaining_hp: int
```

兼容策略：

- 第一阶段允许 `uid` 和 `victim_uid` 同时写入，消费方优先读 `uid`。
- `pos` 保留用于动画落点，但不能作为唯一业务目标。
- 第三阶段再升级 `EventValidator`，让 `damage` 必须有 `uid`。

### `spawn` / `die` / `status`

这些事件可以后迁移，但新代码应避免继续扩散裸事件：

- `spawn` 必须带 `uid`、`pos`、`unit_id` 或 `entity_id`。
- `die` 必须带 `uid`、`pos`、`reason`，可带 `killer_uid`。
- `status` 必须带 `uid`、`status_id`、`stacks`、`duration`。

## View State Application

`BattleEventPlayer` 不能继续直接修改显示态字段。

目标方式：

```text
BattleEventPlayer
  -> PresentationStateApplier
  -> GameState.move_unit / transaction-style apply
```

最低要求：

- 应用 `move_step` 时使用 `display_state.move_unit(unit, to_pos)`，同步显示态占格索引。
- 应用 `damage` 时优先按 `uid` / `victim_uid` 找单位。
- 只有历史事件缺 uid 时才允许 fallback 到 `get_unit_at(pos)`。
- fallback 应逐步被测试覆盖并最终删除。

## AI Preview Positioning

AI 评分不应通过临时写 `unit.pos` 来计算“如果站在某格”的射程和 footprint。

建议新增无副作用工具：

```gdscript
BoardUtils.occupied_cells_at(unit: UnitState, anchor: Vector2i) -> Array[Vector2i]
BoardUtils.distance_between_unit_at_and_unit(unit_a: UnitState, anchor_a: Vector2i, unit_b: UnitState) -> int
BoardUtils.are_units_adjacent_at(unit_a: UnitState, anchor_a: Vector2i, unit_b: UnitState) -> bool
BoardUtils.projectile_origin_cell_at(attacker: UnitState, anchor: Vector2i, target_pos: Vector2i) -> Vector2i
```

迁移目标：

- `enemy_ai.gd` 不再临时写 `enemy.pos`。
- `stone_bow_guard_rules.gd` 不再临时写 `enemy.pos` / `unit.pos`。
- `fission_slime_rules.gd` 不再临时写 `unit.pos`。
- `intent_system.gd` 构建预览时使用无副作用位置视图。

## Implementation TODO

## Current Implementation Progress

本轮已落地的改动：

- [x] 新增 `scripts/rules/combat_event_builder.gd`，统一构造 `move_step`、`damage`、`explode` 等基础事件。
- [x] 新增 `scripts/rules/combat_transaction.gd`，先覆盖移动与伤害这两个高频状态变更入口。
- [x] `BattleActionService.try_move()` 与 `IntentSystem._execute_move()` 已改用 `CombatTransaction`。
- [x] `attack_pipeline.gd`、`displacement.gd`、`entity_rules.gd`、`enemy_behavior.gd`、`gem_effects.gd` 等高频事件入口已开始改用 `CombatEventBuilder`。
- [x] `damage` 事件在新入口中写入 `uid` / `victim_uid`，旧字段 `pos` 保留给表现层兼容。
- [x] `CombatTransaction.damage_unit()` / `true_damage_unit()` 会在无外部事件 sink 时临时绑定自身事件数组，确保受伤/死亡连锁事件不丢失。
- [x] 攻击管线、强制位移、实体碰撞、敌人特殊行为与主要宝石伤害路径已迁移到事务伤害入口，减少裸 `damage` 事件构造。
- [x] 新增 `combat_transaction_test`，并将其纳入 `./tools/verify changed` 的战斗核心回归。
- [x] `BattleEventPlayer._prime_event_state()` 应用 `move_step` 时同步 display state 占格。
- [x] `BattleEventPlayer` 对连续爆炸 cluster 批量播放 `explode`、`damage`、`move_step`、`split_spawn` 与范围特效，避免同一结算链在表现层排队。
- [x] `BoardUtils` 增加无副作用位置辅助，用于 AI/意图计算“站在某格时”的 footprint、距离和射击原点。
- [x] `enemy_ai.gd`、`stone_bow_guard_rules.gd`、`fission_slime_rules.gd`、`intent_system.gd` 已迁出临时 `unit.pos` 评分模式。
- [x] `CombatTransaction` 增加显式事件 sink 绑定，玩家移动、AI 移动和强制位移期间的地形/宝石连锁伤害会进入同一事件流。
- [x] 规则层剩余直接 `CombatRules.apply_damage()` / `apply_true_damage()` 入口已收口到事务伤害入口，事务内部除外。
- [x] `EventValidator` 已将 `damage.uid` / `damage.victim_uid` 升级为强制字段，并补充事务契约测试。

完成收口项：

- [x] `CombatTransaction` 已扩展到显式击杀、状态、生成和宝石位置转移；tile enter 继续由移动规则显式调用。
- [x] 运行时单位生成已通过 `UnitSpawnService` 收口，并拆分生成来源与奖励资格。
- [x] `CombatEventBuilder` 已覆盖 spawn/die/status/gem_transfer/transform 及主要范围表现事件。
- [x] 增加显示态移动后 `_cell_occupancy` 一致性的专门测试。
- [x] 清理非构造场景的直接 `unit.pos = ...`；仅保留注册前的 detached split clone 初始化，并由架构门禁显式豁免。

### P0 - 事务边界和文档落地

- [x] 新增 `docs/combat-transaction-refactor-todo.md`。
- [x] 在 `AGENTS.md` 写明战斗状态变更规则。
- [x] 搜索并记录直接 `*.pos =`、裸 `move_step`、裸 `damage` 事件位置，最终由 `tools/combat_architecture_guard` 自动扫描。
- [x] 明确迁移期间兼容策略：先新增事务入口，不一次性强改所有调用点。

### P1 - Event Builder 与显示态同步

- [x] 新增 `scripts/rules/combat_event_builder.gd`。
- [x] 提供 `move_step()`、`damage()`、`explode()` 等基础工厂方法。
- [x] `damage()` 统一写入 `uid` 和 `victim_uid`。
- [x] `BattleEventPlayer._prime_event_state()` 应用移动时改用 `display_state.move_unit()`。
- [x] `BattleEventPlayer._apply_event_state()` 伤害目标优先按 uid 查找。
- [x] 补测试：显示态移动后 `_cell_occupancy` 与单位位置一致。

### P2 - CombatTransaction 最小可用

- [x] 新增 `scripts/rules/combat_transaction.gd`。
- [x] 支持 `move_unit()`：状态移动、facing、`move_step` 事件、`on_unit_move` 信号。
- [x] 支持 `damage_unit()`：调用 `CombatRules.apply_damage()`，写完整 `damage` 事件。
- [x] 支持绑定现有 `events` 数组，兼容旧函数签名。
- [x] `finish()` 在 debug/test 中调用 `EventValidator` 和 `BattleInvariantChecker`。
- [x] 补 `combat_transaction_test.gd`：移动、伤害、死亡、无效输入与 snapshot trace。

### P3 - 迁移高频移动入口

- [x] 迁移 `BattleActionService.try_move()`。
- [x] 迁移 `IntentSystem._execute_move()`。
- [x] 迁移 `Displacement._push_directional()`。
- [x] 迁移 `Displacement.star_relocate()`。
- [x] 保持现有事件顺序，尤其爆炸后 damage/move 批处理顺序。
- [x] 跑 `./tools/verify changed` 和 displacement / intent 相关测试。

### P4 - 迁移高频伤害事件

- [x] 迁移 `AttackPipeline.AttackContext.push_damage_event()`。
- [x] 迁移 `GemEffects` 中裸 `damage` 事件。
- [x] 迁移 `EnemyBehavior`、`EntityRules`、`BombRatRules` 中裸 `damage` 事件。
- [x] 所有 `damage` 事件补齐 `uid` / `victim_uid`。
- [x] `EventValidator` 将 `damage` 的必填字段升级为 `uid`、`victim_uid`、`pos`、`damage`、`is_crit`。
- [x] 更新受影响测试断言。

### P5 - 清理 AI 临时改位

- [x] 新增 BoardUtils 无副作用位置工具。
- [x] 迁移 `enemy_ai.gd` 中的临时 `enemy.pos = ...`。
- [x] 迁移 `stone_bow_guard_rules.gd` 中的临时改位。
- [x] 迁移 `fission_slime_rules.gd` 和 `intent_system.gd` 中的临时改位。
- [x] 补 intent consistency 测试，验证预览路径和执行事件一致。

### P6 - 长期收口

- [x] 禁止新增裸 `events.append({"type": "damage"...})`，由 `tools/combat_architecture_guard` 阻断。
- [x] 禁止新增战斗规则中的直接 `unit.pos = ...`，构造/clone 除外。
- [x] 将运行时 `spawn`、`die`、`status` 状态变更入口迁移到事务层；底层合并器和死亡钩子保留在事务内部。
- [x] Snapshot 输出中增加 `transaction_trace`，便于复盘。
- [x] 文档更新到 `docs/system-stability-roadmap.md`，外部 `Technical_Architecture.md` 同步声明事务边界。

## Closure Evidence

截至 2026-07-16，本专项的 Acceptance Criteria 已全部满足：

- `tools/combat_architecture_guard` 随每次 `tools/verify` 执行，禁止裸关键事件、绕过事务的伤害/状态入口、运行时单位注册和非法位置写入。
- `StateSnapshot` 输出 `transaction_trace`，记录操作、主体、来源/原因、revision 与关键结果。
- `CombatTransaction` 聚焦测试覆盖事件 shape、伤害/死亡、事件 sink、移动连锁、标准化 damage tags 与 snapshot trace。
- `PresentationStateApplier` 专项测试覆盖展示态移动、伤害按 uid 定位、死亡与 `_cell_occupancy` 同步。
- 确定性 encounter/gem snapshot 的 event violations 与 battle invariant violations 均为 0。
- `tools/verify changed`、`tools/verify fast` 与 `tools/verify all` 是最终闭环门槛；结果以 `artifacts/verify/report.json` 为准。

## Migration Rules

- 每个阶段都必须保持现有事件顺序，尤其 UI 依赖的批处理顺序。
- 不允许为了迁移事务层偷偷改变宝石语义、伤害公式、AI 决策权重。
- 涉及宝石或战斗行为前，先执行 `AGENTS.md` 的 First Commands。
- 每个迁移点至少补一个验证：事件 shape、状态 diff、不变量三者之一。
- 遇到设计文档、测试、实现冲突时，先记录冲突，不要用事务层改造掩盖语义选择。

## Verification

基础命令：

```bash
./tools/context 战斗 状态 事务 事件 位移 伤害
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/coverage
./tools/verify changed
```

迭代命令：

```bash
./tools/verify fast
./tools/snapshot --encounter tutorial_001 --seed 1
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion --slot red --action attack
```

重点测试：

```text
scripts/tests/displacement_test.gd
scripts/tests/intent_consistency_contract_test.gd
scripts/tests/gem_semantic_contract_test.gd
scripts/tests/explosion_test.gd
scripts/tests/attack_tag_combo_test.gd
scripts/tests/manual/battle_stress_test.gd
```

## Acceptance Criteria

- 高频真实移动入口通过事务层提交。
- 表现态应用移动不会破坏 `_cell_occupancy`。
- 高频 `damage` 事件都有 `uid` / `victim_uid`，表现层不再靠坐标猜目标。
- `EventValidator` 能捕获缺 uid 的新 `damage` 事件。
- AI 评分/预览不再通过临时改 `unit.pos` 计算站位。
- `./tools/verify changed` 通过。
- 相关 snapshot 无 event violations 和 battle invariant violations。

## Known Risks

- `BattleEventPlayer` 依赖事件顺序做批处理，迁移时不能随意重排事件。
- 某些 gem 连锁会在伤害中触发额外事件，事务层需要允许嵌套追加而不丢顺序。
- `CombatRules.apply_damage()` 已经负责死亡、副作用和信号，`CombatTransaction.damage_unit()` 不能重复结算。
- AI 预览用无副作用位置工具时，必须覆盖多格单位 footprint，否则会引入新漂移。
- 旧事件兼容期内，表现层 fallback 不能马上删除。
