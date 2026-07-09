# 游戏全流程与可扩展规则工程 Spec

文档状态：实施版 v1  
适用阶段：从当前机制原型推进到可外部试玩的工程垂直切片  
最后复核基线：`./tools/verify all` 通过 `56/56`，宝石语义契约覆盖率 `30%`

## 1. 文档目的

本文档定义《窃律者》从当前战斗原型推进到“可稳定完成一整局”的工程目标、架构边界、
验收标准和 TODO 顺序。

当前阶段不要求确定最终策划内容，也不要求补齐正式美术与音频。事件文本、商店价格、
奖励数量、地图规则数值均允许使用占位配置，但系统必须形成真实、可保存、可测试、
可替换配置的闭环。

本文档约束的是工程能力，不替代以下设计权威：

1. `详细设计/宝石/宝石_v1.md`
2. `详细设计/数值/数值设计_v1.md`
3. `GDD.md`
4. `Technical_Architecture.md`

涉及宝石和战斗数值时仍按上述权威顺序处理冲突。本 Spec 中出现的经济与地图规则数值
仅作为工程默认值，不视为最终设计结论。

### 1.1 与现有仓库文档的关系

- `docs/run-state-management-plan.md` 描述当前已经落地的状态管理方案。
- 本 Spec 将商店经济、通用事件、地图规则和完整恢复正式纳入下一阶段工程范围，因此
  覆盖旧方案中“商店经济与商品购买暂不展开”的范围约束。
- `docs/system-stability-roadmap.md` 继续约束战斗系统稳定性治理；本 Spec 不取代它。
- `docs/battle-editor-technical-plan.md` 的剩余效率工具继续暂缓，不因本 Spec 自动提级。
- GDD 只提出“地图可增加经济、血量等属性规则”的方向，尚未定义最终获取方式和数值。
  本 Spec 只建设承载能力，不替产品设计作最终决定。

---

## 2. 当前判断

项目已经具备可运行的战斗、地图、奖励、遗物、存档与章节骨架，但完整度仍低，主要原因
不是缺少更多内容，而是完整游戏流程尚未成为一套可验证、可扩展的系统。

当前关键缺口：

- 非战斗房间仍由 `AdventureService.resolve_pending_room()` 集中硬编码结算。
- 商店只有候选生成，没有货币、购买、库存和恢复语义。
- 事件房间没有通用事件定义、选项、条件和效果执行能力。
- 地图节点虽有 `MapNode.properties`，但没有规则定义、持久化、展示和结算能力。
- 地图规则无法影响金币、奖励、房间、战斗或后续地图生成。
- 局内经济没有统一账本，无法解释一次资源变化来自哪里。
- 流程测试集中在局部模块，尚未验证一整局跨场景、退出和恢复。
- 现有规则测试数量较多，但宝石独立语义契约覆盖率仍很低。

因此，本阶段目标不是继续快速增加玩法，而是建立足以承载未来想法的稳定结构。

---

## 3. 工程目标

### 3.1 核心目标

完成一条可自动验证的完整游戏链路：

```text
新开局
→ 生成地图与地图规则
→ 选择路线
→ 战斗 / 事件 / 商店 / 休息
→ 获得并消费局内资源
→ 地图规则修改后续结算
→ 跨场景保存与恢复
→ 章节推进
→ 通关或失败
→ 记录整局结果
```

### 3.2 质量目标

- 所有跨场景业务真相都可序列化。
- 所有局内资源变化都通过统一入口。
- 所有房间都使用统一生命周期，不在场景脚本中直接发奖励。
- 所有地图规则都通过固定 modifier / hook 影响系统。
- 所有随机候选都由固定 seed 生成并锁定快照。
- 所有关键流程都能无头测试，不依赖手动点击才能验证。
- 新增一种房间效果或地图规则时，不需要修改多个无关模块。
- 策划数值和候选池可通过 JSON 修改，不要求改 GDScript。

### 3.3 非目标

本阶段不负责：

- 决定最终金币产出、价格和奖励平衡。
- 设计大量正式随机事件。
- 设计正式 Boss、关卡、敌人与宝石。
- 完成局外成长和职业系统。
- 完成正式美术、音效和剧情演出。
- 为未来所有可能机制建设通用 DSL。
- 为了缩短文件长度而进行无行为收益的重构。

---

## 4. 完成定义

### 4.1 工程垂直切片完成

满足以下条件时，视为“全流程工程闭环完成”：

- 任意固定 seed 可以完成至少一整局自动流程。
- 普通战、精英战、休息、事件、商店、章节终点均可真实进入并结算。
- 玩家拥有可持久化金币，并可在商店完成至少一种购买。
- 事件房间可展示至少两个选项，并执行至少两类通用效果。
- 地图节点可携带至少一种规则修改器，例如 `gold_gain_mult = 1.1`。
- 地图规则能真实影响后续结算，并在 UI 中可见、在日志中可解释。
- 在地图、房间选择、奖励选择和商店购买后退出，均可恢复到合法状态。
- 同一房间和同一交易不会因为重进或读档重复结算。
- 通关和失败都会生成一条完整 run history。
- `./tools/verify all` 通过，并包含整局流程契约。

### 4.2 可试玩版本完成

工程闭环完成后，还需满足：

- 可导出并启动正式构建。
- 正式构建不暴露调试编辑器。
- 菜单、地图、房间与奖励界面支持完整鼠标流程。
- 关键操作有明确失败原因和资源变化反馈。
- 存档损坏时可回退到最近一次有效快照或给出明确提示。

---

## 5. 架构原则

### 5.1 RunState 是整局唯一业务真相

所有需要跨房间、跨场景、跨启动恢复的状态必须属于 `RunState`。

应纳入：

- 当前章节与地图进度。
- 玩家生命、槽位、宝石和遗物。
- 金币与未来其他局内资源。
- 当前生效的全局地图规则。
- 节点局部规则与已发现状态。
- 房间生命周期状态。
- 奖励、事件、商店候选快照。
- 已完成的交易和结算记录。
- 本局统计与结果摘要。

场景节点只负责展示和提交命令，不保存业务真相。

### 5.2 候选生成与玩家决策分离

随机生成候选不等于完成结算。

例如商店必须区分：

```text
生成库存 → 查看库存 → 选择商品 → 校验金币 → 提交购买 → 记录交易
```

事件必须区分：

```text
生成事件 → 查看选项 → 选择选项 → 校验条件 → 执行效果 → 记录结果
```

所有候选在首次生成后锁定快照，读档不得重新随机。

### 5.3 效果执行与 UI 分离

UI 不得直接执行以下行为：

- 修改金币。
- 发放宝石或遗物。
- 修改生命。
- 添加地图规则。
- 标记房间完成。

UI 只能调用服务命令，并根据返回的结构化结果刷新。

### 5.4 数值配置化，语义代码化

以下内容应放入 JSON 配置：

- 初始金币。
- 房间金币奖励。
- 商店价格。
- 商店库存数量。
- 事件选项成本与收益。
- 地图规则 modifier 数值。
- 房间和奖励池权重。

以下内容应由代码保证：

- 是否允许购买。
- 是否可重复领取。
- modifier 如何叠加。
- 候选如何锁定。
- 保存与恢复边界。
- 事务成功或失败后的状态一致性。

### 5.5 先建立有限词表，不建设任意脚本系统

事件、商店和地图规则共享有限的 effect / modifier 词表。新增词条必须有明确语义、
校验和测试。

不允许在 JSON 中执行任意 GDScript，也不允许用字符串表达式动态求值。

---

## 6. 目标模块

建议逐步形成以下模块边界。名称允许根据实现调整，但职责不可重新混杂。

```text
scripts/services/
  room_flow_service.gd       房间生命周期与事务入口
  room_effect_executor.gd    通用非战斗效果执行
  adventure_rule_registry.gd 地图/局内 modifier 与 hook
  economy_service.gd         金币账本、价格与交易
  event_service.gd           事件候选、选项条件和提交
  shop_service.gd            商店库存、购买和售罄状态

resources/adventure/
  economy_config.json
  room_defs.json
  event_defs.json
  map_rule_defs.json
  reward_offer_config.json
  shop_pools.json
```

### 6.1 AdventureService

保留职责：

- 地图生成、导入与导出。
- 当前坐标和可进入节点查询。
- 进入节点与场景导航。
- 章节切换。

移出职责：

- 具体房间奖励。
- 事件效果。
- 商店交易。
- 金币修改。
- 地图规则执行。

### 6.2 RoomFlowService

负责所有房间统一生命周期：

```text
UNENTERED
→ ENTERED
→ AWAITING_DECISION
→ RESOLVED
→ LEFT
```

最低 API：

```gdscript
func enter_room(room_id: String) -> Dictionary
func get_room_view(room_id: String) -> Dictionary
func submit_room_command(room_id: String, command: Dictionary) -> Dictionary
func leave_room(room_id: String) -> Dictionary
```

返回结果必须包含：

```gdscript
{
  "ok": true,
  "room_id": "chapter_1:3_4",
  "state": "RESOLVED",
  "events": [],
  "summary": "",
  "errors": []
}
```

### 6.3 EconomyService

金币是第一种局内通用资源，但接口应允许后续增加其他资源。

最低 API：

```gdscript
func get_balance(resource_id: String = "gold") -> int
func can_afford(cost: Dictionary) -> bool
func grant(resource_id: String, base_amount: int, reason: String, ctx: Dictionary = {}) -> Dictionary
func spend(resource_id: String, amount: int, reason: String, ctx: Dictionary = {}) -> Dictionary
```

所有资源变化返回账本条目：

```gdscript
{
  "resource_id": "gold",
  "base_amount": 10,
  "final_amount": 11,
  "before": 20,
  "after": 31,
  "reason": "normal_combat_reward",
  "modifiers": [
    {"id": "map_rule_gold_gain_10", "operation": "multiply", "value": 1.1}
  ]
}
```

规则：

- 不允许余额变为负数。
- 增减资源必须有 `reason`。
- modifier 后的取整方式必须集中定义。
- 同一个事务 ID 不可重复提交。
- 所有账本条目必须可序列化。

### 6.4 AdventureRuleRegistry

地图规则、事件获得的临时规则、未来奖励经济遗物，通过这一层影响非战斗系统。

最低能力：

```gdscript
func query_modifier(modifier_id: String, base_value: Variant, ctx: Dictionary = {}) -> Variant
func fire_hook(hook_id: String, payload: Dictionary = {}) -> Array[Dictionary]
func validate_rule(rule: Dictionary) -> Array[String]
```

第一批 modifier 词表：

| modifier_id | 语义 | 合并方式 |
| --- | --- | --- |
| `gold_gain_mult` | 获得金币倍率 | 叠乘 |
| `shop_price_mult` | 商店价格倍率 | 叠乘 |
| `rest_heal_mult` | 营地回血倍率 | 叠乘 |

后续候选 modifier 在有运行时语义前不要加入校验白名单：

| modifier_id | 预期语义 | 合并方式 |
| --- | --- | --- |
| `shop_offer_count_bonus` | 商店候选数量加成 | 相加 |
| `event_reward_mult` | 事件数值奖励倍率 | 叠乘 |
| `battle_reward_option_bonus` | 战后奖励候选数量加成 | 相加 |

第一批 hook 词表：

| hook_id | 时机 |
| --- | --- |
| `run_start` | 新局建立后 |
| `chapter_start` | 新章节地图生成后 |
| `room_enter` | 房间进入后、展示前 |
| `room_resolve` | 房间事务成功后 |
| `shop_purchase` | 商店购买成功后 |
| `battle_reward_claimed` | 战后奖励领取后 |
| `chapter_end` | 章节推进前 |
| `run_end` | 通关或失败结算时 |

地图规则不得直接调用 UI 或修改场景节点。

### 6.5 EventService

事件定义示例：

```json
{
  "event_debug_cache": {
    "title_key": "event.debug_cache.title",
    "body_key": "event.debug_cache.body",
    "weight": 1.0,
    "options": [
      {
        "id": "take_gold",
        "label_key": "event.debug_cache.take_gold",
        "conditions": [],
        "effects": [
          {"action": "grant_resource", "resource_id": "gold", "amount": 10}
        ]
      },
      {
        "id": "install_rule",
        "label_key": "event.debug_cache.install_rule",
        "conditions": [],
        "effects": [
          {"action": "add_adventure_rule", "rule_id": "map_rule_gold_gain_10"}
        ]
      }
    ]
  }
}
```

第一批 condition 词表：

- `resource_gte`
- `hp_below_ratio`
- `has_relic`
- `not_has_relic`
- `has_carried_gem`
- `chapter_gte`

第一批 effect 词表：

- `grant_resource`
- `spend_resource`
- `heal_player`
- `damage_player`
- `grant_relic`
- `grant_gem`
- `add_adventure_rule`
- `remove_adventure_rule`

默认事件只用于验证能力，不代表最终事件设计。

### 6.6 ShopService

商店必须先实现最小真实交易，不等待最终经济设计。

最低能力：

- 固定 seed 生成商品库存。
- 商品至少支持宝石与遗物两种类型。
- 每个商品拥有稳定 `offer_id`、基础价格和最终价格。
- 最终价格通过 `shop_price_mult` 计算。
- 购买前检查金币、商品状态和携带限制。
- 购买成功后扣费、发货并标记售罄。
- 失败时不得部分扣费或部分发货。
- 退出并继续后库存、价格和售罄状态不变。

暂不实现：

- 出售。
- 刷新商店。
- 复杂折扣。
- 商品升级。
- 讨价还价。

### 6.7 现有实现映射

为避免实施时“新规范”和“当前仓库”各说各话，以下映射视为本 Spec 的默认迁移起点：

| 当前实现 | 当前职责 | 目标去向 |
| --- | --- | --- |
| `scripts/services/adventure_service.gd` | 地图进度、房间进入、非战斗房间硬编码结算 | 保留地图与导航；移出房间奖励、商店、事件、金币结算 |
| `scripts/services/run_service.gd` | RunState 生命周期、战斗跨场恢复、部分房间快照 | 保留 RunState 读写与公共事务；新增房间、账本、规则持久化支撑 |
| `scripts/data/run_state.gd` | 当前整局核心存档结构 | 扩展为本 Spec 定义的完整 RunState |
| `scripts/map/map_node.gd` | 地图节点结构，已含 `properties` | 继续作为节点固定属性容器；不执行规则 |
| `scripts/ui/adventure_room_placeholder.gd` | 占位房间 UI | 演进为房间统一展示壳，内部按 `room_type` 切换事件 / 商店 / 休息视图 |
| `scripts/services/save_service.gd` | 档位文件组织与基础 JSON 读写 | 增加临时文件校验、备份与原子替换 |

实施要求：

- Phase 1 之前，不要求立即搬空 `AdventureService`，但禁止继续向 `resolve_pending_room()` 增加新业务分支。
- 新服务优先放在 `scripts/services/` 下，除非后续已有更清晰的目录约定。
- 迁移期间允许旧入口调用新服务，但不允许新功能反向依赖旧硬编码路径。

---

## 7. 地图规则系统

### 7.1 设计目标

地图不只承担路线选择，也允许玩家通过有限操作修改后续规则。例如：

- 后续获得金币 `+10%`。
- 商店价格 `-10%`。
- 营地回血提高。
- 战斗奖励多展示一个候选。

当前阶段只建立系统能力，不决定地图规则的正式来源、稀有度和最终数值。

### 7.2 规则作用域

每条地图规则必须声明作用域：

| scope | 生命周期 |
| --- | --- |
| `node` | 只影响指定节点 |
| `chapter` | 只影响当前章节 |
| `run` | 影响整局 |

未来如需路线范围或相邻节点范围，应新增明确 scope，不用坐标特判模拟。

### 7.3 数据结构

规则定义：

```json
{
  "map_rule_gold_gain_10": {
    "name_key": "map_rule.gold_gain_10.name",
    "desc_key": "map_rule.gold_gain_10.desc",
    "default_scope": "run",
    "effects": [
      {"modifier": "gold_gain_mult", "value": 1.1}
    ]
  }
}
```

运行时实例：

```gdscript
{
  "instance_id": "rule_42",
  "rule_id": "map_rule_gold_gain_10",
  "scope": "run",
  "source": "event_debug_cache",
  "chapter": 1,
  "node_id": "",
  "stacks": 1,
  "runtime": {}
}
```

### 7.4 MapNode.properties

`MapNode.properties` 仅保存节点局部、生成后固定的数据，例如：

```gdscript
{
  "rule_ids": ["map_rule_shop_discount_node"],
  "event_id": "event_debug_cache",
  "encounter_pool": "chapter_1_normal",
  "tags": ["high_risk"]
}
```

要求：

- 必须随地图进度序列化与反序列化。
- 地图生成器只负责分配属性，不执行属性效果。
- 节点属性必须能在地图预览 UI 中读取。
- 未知属性必须被校验或忽略并记录，不得导致存档崩溃。

### 7.5 规则叠加与取整

统一顺序：

```text
base
→ additive bonus
→ multiplicative modifiers
→ override（仅明确允许的 modifier）
→ clamp
→ rounding
```

默认工程规则：

- 金币与价格最终取整使用 `roundi`。
- 最终金币奖励最小为 `0`。
- 最终购买价格最小为 `0`。
- modifier 计算必须返回 trace，便于 UI 展示和测试诊断。

以上默认值可配置，但同一种 modifier 不得在不同模块使用不同取整方式。

---

## 8. 房间事务与幂等

### 8.1 Room ID

房间 ID 必须包含章节，避免跨章节坐标复用：

```text
chapter_1:3_4
chapter_2:3_4
```

不得继续把裸坐标 `3_4` 作为整局唯一房间 ID。

### 8.2 房间运行时状态

建议在 `RunState` 增加：

```gdscript
var room_states: Dictionary = {}
```

示例：

```gdscript
{
  "chapter_1:3_4": {
    "status": "AWAITING_DECISION",
    "room_type": "SHOP",
    "snapshot": {},
    "transactions": [],
    "result": {}
  }
}
```

`resolved_rooms` 可迁移进 `room_states`，或在兼容期保留只读迁移。

### 8.3 事务规则

每次会改变 RunState 的玩家决策都必须拥有稳定事务 ID：

```text
chapter_1:3_4:shop:offer_2
chapter_1:5_1:event:event_debug_cache:install_rule
chapter_1:7_2:battle_reward:gem_fire
```

提交要求：

- 校验全部通过后再修改状态。
- 修改失败时状态保持不变。
- 同事务 ID 重复提交返回原结果，不重复扣费或发奖励。
- 成功提交后立即保存。

---

## 9. RunState 目标结构

建议逐步补充：

```gdscript
var resources: Dictionary = {"gold": 0}
var resource_ledger: Array = []
var adventure_rules: Array = []
var room_states: Dictionary = {}
var run_stats: Dictionary = {}
var run_phase: String = "MAP"
var pending_decision: Dictionary = {}
```

### 9.1 run_phase

用于恢复时确定玩家应返回哪个流程：

- `MAP`
- `BATTLE`
- `BATTLE_REWARD`
- `ROOM`
- `RUN_COMPLETE`
- `RUN_FAILED`

### 9.2 pending_decision

只保存尚未提交的业务决策上下文，例如：

```gdscript
{
  "type": "shop",
  "room_id": "chapter_1:3_4"
}
```

恢复场景时根据 `run_phase` 与 `pending_decision` 重建 UI，不把 Control 节点状态写进存档。

### 9.3 存档写入

需要从直接覆盖升级为：

```text
序列化
→ 写入临时文件
→ 读取并校验临时文件
→ 备份现有文件
→ 原子替换正式文件
```

最低保留一个最近有效备份。

### 9.4 run_history 目标结构

`RunHistoryService` 记录的每条 run history 至少应包含：

```gdscript
{
  "run_id": "run_20260608_001",
  "result": "win",
  "chapter_reached": 3,
  "ended_at": 1760000000,
  "master_seed": 12345,
  "summary": {
    "gold_earned": 65,
    "gold_spent": 30,
    "owned_relics": ["relic_alpha", "relic_beta"],
    "active_rule_ids": ["map_rule_gold_gain_10"]
  }
}
```

要求：

- `run_id` 必须稳定且可用于日志与故障排查。
- `summary` 只保存结果摘要，不复刻整份 RunState。
- 胜利与失败都必须写 history，禁止只记录胜利。

---

## 10. UI 与反馈要求

本阶段不要求正式美术，但要求信息完整。

### 10.1 地图界面

必须显示：

- 当前金币。
- 当前全局地图规则摘要。
- hover 节点的房间类型、状态和节点局部规则。
- 节点是否已结算。
- 进入节点后可能受到的已知 modifier。

### 10.2 商店界面

必须显示：

- 当前金币。
- 商品名称、类型、基础价格、最终价格。
- 价格被哪些规则修改。
- 是否已售罄。
- 无法购买的明确原因。

### 10.3 事件界面

必须显示：

- 事件标题与正文。
- 每个选项的成本和已知结果。
- 不满足条件的原因。
- 选择后产生的结构化结果摘要。

### 10.4 资源反馈

金币变化至少显示：

```text
金币 +11（基础 +10，地图规则 +10%）
```

不允许只更新数字而不说明来源。

---

## 11. 测试与质量门槛

### 11.1 新增测试层级

#### A. 纯规则测试

- EconomyService 加钱、扣钱、余额不足、modifier 与取整。
- AdventureRuleRegistry 作用域、叠加、未知规则校验。
- RoomEffectExecutor 每个 effect 的成功与失败。
- EventService 条件、选择、幂等。
- ShopService 库存、价格、购买、售罄、幂等。

#### B. 状态序列化测试

- RunState 新字段 round-trip。
- 地图节点 properties round-trip。
- 商店待选择状态恢复。
- 事件待选择状态恢复。
- 已完成交易不会重复执行。
- 旧版本存档迁移或明确拒绝。

#### C. 全流程契约

至少提供固定 seed 场景：

```text
新局
→ 普通战胜利
→ 领取宝石
→ 事件获得金币
→ 地图规则使金币收益 +10%
→ 商店购买商品
→ 休息
→ 章节推进
→ 保存并恢复
→ 最终通关
```

每一步验证：

- RunState 合法。
- 房间状态合法。
- 资源账本守恒。
- 事件 shape 合法。
- 保存后 round-trip 等价。

#### D. 故障注入

- 重复提交同一购买。
- 奖励领取后立即退出。
- 写入损坏存档。
- 未知规则 ID。
- 不足金币购买。
- 手持已有宝石时领取新宝石。

### 11.2 持续门槛

- 改动 adventure / run / economy / room 代码时，必须运行对应全流程契约。
- `./tools/verify all` 必须纳入新增测试。
- 新增 modifier、condition、effect 时必须同时新增契约。
- 不得只通过普通单元测试宣称流程完成。
- 宝石语义覆盖率必须持续提高，不因全流程开发暂停。

### 11.3 代码质量门槛

每个新系统必须满足：

- 服务 API 返回结构化结果，不只返回 `bool`。
- 失败路径不产生部分状态修改。
- 随机数只通过 `RngService` 的稳定 domain。
- JSON 定义加载时有 schema 校验。
- 未知 action / modifier / condition 在调试与测试中视为失败。
- UI 不直接修改 RunState。
- 跨场景状态不保存在场景节点字段中。

### 11.4 配置 schema 最小要求

本阶段不要求引入外部 schema 工具，但至少要做到：

- 顶层 key、必填字段、枚举值和数值类型有集中校验函数。
- 校验失败时返回可读错误，包含文件名、定义 ID 和字段名。
- 调试与测试环境默认对非法配置 fail fast。
- 正式构建可选择拒绝加载存档或回退到安全默认值，但必须记录日志。

最低配置约束建议：

| 文件 | 必填字段 |
| --- | --- |
| `economy_config.json` | `starting_gold`、`normal_combat_gold`、`elite_combat_gold` |
| `event_defs.json` | `title_key`、`body_key`、`options` |
| `map_rule_defs.json` | `name_key`、`desc_key`、`effects` |
| `room_defs.json` | `room_type`、`ui_kind`、`effects` |
| `shop_pools.json` | `pool_id`、`offers` |

---

## 12. 分阶段 TODO

TODO 状态使用：

- `[ ]` 未开始
- `[~]` 进行中
- `[x]` 完成并通过验收
- `[-]` 明确取消

### Phase 0：基线与护栏

目标：先定义工程边界，防止继续向集中式服务追加临时逻辑。

- [x] 建立本 Spec 对应的全流程测试入口。
- [x] 将当前 `41/41` 验证结果作为基线记录。
- [x] 为 `RunState`、地图进度和房间结果建立 round-trip 测试。
- [x] 修复领取新宝石覆盖现有手持宝石的问题。
- [x] 为房间、交易与奖励定义稳定 ID 规范。
- [x] 为 adventure JSON 定义增加加载校验入口。
- [x] 将未知 effect / modifier / condition 在测试中设为失败。
- [x] 记录 `AdventureService.resolve_pending_room()` 的现有行为清单，作为迁移基线。

验收：

- 不新增正式玩法，也能自动验证当前流程没有退化。
- 后续模块可以安全迁移，不依赖手玩确认。

### Phase 1：RunState 与房间生命周期

目标：建立统一流程状态和幂等事务。

- [x] RunState 增加 `resources`、`resource_ledger`。
- [x] RunState 增加 `room_states`、`run_phase`、`pending_decision`。
- [x] 房间 ID 升级为包含章节的稳定 ID。
- [x] 实现 `RoomFlowService`。
- [x] 将休息点迁移为房间 effect，不再由 AdventureService 直接回血。
- [x] 将当前事件直接发遗物逻辑迁移为房间 effect。
- [x] 将房间结果与重复结算保护迁移到统一事务。
- [x] 为旧 `resolved_rooms` 提供迁移或开发期明确失效策略。
- [x] 让 `adventure_room_placeholder.gd` 改为通过房间视图模型渲染，而不是直接执行结算。

验收：

- AdventureService 不再决定具体房间奖励。
- 任意非战斗房间都遵循统一生命周期。
- 重复进入和重复提交不会重复结算。

### Phase 2：经济与最小商店

目标：形成第一条真实资源获取与消费闭环。

- [x] 新增 `economy_config.json`，所有默认数值标记为占位值。
- [x] 实现 `EconomyService` 与账本。
- [x] 战斗胜利通过统一入口获得占位金币。
- [x] 实现 `ShopService` 固定 seed 库存。
- [x] 实现宝石与遗物商品。
- [x] 实现购买事务、余额校验和售罄状态。
- [x] 实现最小商店 UI。
- [x] 验证商店退出与继续恢复。
- [x] 为价格 trace 增加 UI 文案格式化工具，避免各界面各自拼接字符串。

占位默认值建议：

```json
{
  "starting_gold": 0,
  "normal_combat_gold": 10,
  "elite_combat_gold": 20,
  "boss_combat_gold": 40,
  "gem_base_price": 15,
  "relic_base_price": 30
}
```

商店候选数量属于 `resources/adventure/shop_pools.json`：

```json
{
  "default": {
    "gem_offer_count": 2,
    "relic_offer_count": 1,
    "gem_source": "shop",
    "relic_source": "shop"
  }
}
```

战斗奖励候选数量属于 `resources/adventure/reward_offer_config.json`：

```json
{
  "battle_rewards": {
    "NORMAL_COMBAT": {
      "relic_source": "normal_chest",
      "relic_offer_count": 3
    }
  }
}
```

这些数字只用于打通工程，不构成策划结论。

验收：

- 玩家能通过战斗获得金币，并在商店完成一次真实购买。
- 所有金币变化可从账本解释。
- 修改 JSON 后无需修改代码即可调整数值。

### Phase 3：通用事件

目标：事件房间不再是单一硬编码奖励。

- [x] 新增 `event_defs.json`。
- [x] 实现 condition 校验器。
- [x] 实现通用 `RoomEffectExecutor`。
- [x] 实现事件候选快照与选项提交。
- [x] 实现最小事件 UI。
- [x] 提供至少两个 debug 事件验证资源、生命、遗物和规则效果。
- [x] 验证事件选择前退出、选择后退出和重复提交。
- [x] 为每个 effect 返回结构化摘要，供日志、UI 和测试共用。

验收：

- 新增只使用现有词表的事件时，不需要修改 GDScript。
- 事件效果失败时不会产生部分状态。

### Phase 4：地图规则与地图修改能力

目标：地图可以承载并展示会影响后续流程的规则。

- [x] 新增 `map_rule_defs.json`。
- [x] 实现 `AdventureRuleRegistry`。
- [x] MapNode properties 纳入地图序列化。
- [x] 地图生成器支持给节点分配配置化 properties。
- [x] RunState 支持 `node`、`chapter`、`run` 三种规则作用域。
- [x] 实现 `gold_gain_mult`。
- [x] 实现 `shop_price_mult`。
- [x] 实现至少一个非经济 modifier。
- [x] 地图 UI 展示当前全局规则与节点局部规则。
- [x] 所有 modifier 计算输出 trace。

验收：

- 获得 `金币 +10%` 规则后，后续金币结算真实变化。
- 保存并继续后规则仍生效。
- 切换章节后 chapter scope 规则正确清除，run scope 规则保留。

### Phase 5：全流程恢复与存档加固

目标：任何关键决策点退出都不会破坏整局。

- [x] 存档改为临时文件校验后原子替换。
- [x] 保留最近有效备份。
- [x] 为 `run_phase` 建立恢复路由。
- [x] 支持从地图、房间、商店、事件、战后奖励恢复。
- [x] 通关与失败写入完整 run history。
- [x] 增加故障注入测试。
- [x] 增加整局固定 seed 无头测试。
- [x] 为损坏存档定义用户可见提示文案与回退策略。

验收：

- 所有关键退出点均可恢复。
- 重复操作和损坏存档不会造成资源复制或整局无提示丢失。

### Phase 6：核心规则可信度与架构收口

目标：在流程稳定后提高已有核心玩法可信度，不盲目扩大功能。

- [x] 宝石语义契约覆盖率提升到至少 `30%`。
- [x] 优先覆盖黑槽死亡链、蓝槽受击链和三级效果。
- [x] 将 EventValidator 接入调试构建关键行动出口。
- [x] 扩展随机压力测试的行动类型和 seed 集。
- [x] 为 AI 意图预览与执行增加一致性契约。
- [x] 根据实际重复与风险收口位移、事件和表现层接口。
- [x] 仅在存在明确迁移计划和回归保护时拆分大型文件。

验收：

- 架构调整由测试与真实风险驱动。
- 不以“代码看起来更优雅”作为单独完成标准。

### Phase 7：发布工程

目标：项目可以稳定交付给外部试玩。

- [x] 增加 `export_presets.cfg`。
- [x] 增加一键导出脚本。
- [x] 增加 CI，运行 `./tools/verify all`。
- [x] 增加导出包启动冒烟测试。
- [x] 确保正式构建关闭调试编辑器和开发控制台。
- [x] 完整鼠标流程与基本键盘焦点导航。

验收：

- 可生成可启动的试玩包。
- 开发环境通过不等于完成，导出包也必须通过冒烟测试。

---

## 13. 明确暂缓

以下工作在新的设计信息出现前不进入高优先级 TODO：

- 商店出售、刷新和复杂价格机制。
- 大量正式随机事件。
- 地图规则宝石的正式获取方式和最终数值。
- 完整背包与仓库。
- Boss、职业、局外成长。
- 完整本地化。
- 无素材情况下的完整 AudioService。
- 战斗编辑器效率工具。
- 对 `battle_scene.gd`、`isometric_board.gd` 的一次性大重写。

---

## 14. 决策规则

新增 TODO 前，必须回答：

1. 它是否提升完整流程、可靠性、可解释性或未来内容接入效率？
2. 它是否可以在没有新策划内容的情况下验收？
3. 它是否有自动测试或结构化验证方式？
4. 它是否避免把业务真相写入 UI 或场景节点？
5. 它是否提供配置口，而不是再次硬编码临时数值？

若前 3 项均为否，该工作默认不进入当前工程阶段。

重构前，必须回答：

1. 当前具体风险是什么？
2. 哪个测试能证明迁移前后行为一致？
3. 重构完成后，新增哪类能力会明显更简单？

无法回答时，不进行重构。

---

## 15. TODO 完成规范

单个 TODO 只有同时满足以下条件，才允许从 `[ ]` 更新为 `[x]`：

- 行为已经通过公共服务入口落地，不依赖测试专用捷径。
- 对应数据可以保存、加载并完成 round-trip。
- 成功、失败和重复提交路径均有测试。
- 调试输出或结构化结果可以解释状态变化原因。
- 相关旧入口已经迁移，或明确记录兼容期与删除条件。
- `./tools/verify changed` 通过；涉及共享流程时 `./tools/verify all` 通过。
- 文档中的模块职责、词表或数据结构已同步更新。

每个 Phase 完成时，必须额外执行一次固定 seed 全流程契约，并记录：

```text
完成的能力：
仍使用的占位配置：
发现但未解决的设计问题：
已知技术债：
验证命令与结果：
```

Phase 不以“创建了目标类或文件”为完成标准，以该阶段验收条件成立为完成标准。

---

## 16. 推荐近期执行顺序

最近一轮只做以下内容：

1. Phase 0：全流程护栏、稳定 ID、手持宝石奖励冲突。
2. Phase 1：RunState 与 RoomFlowService。
3. Phase 2：金币账本与最小商店。
4. Phase 3：两个 debug 事件。
5. Phase 4：`gold_gain_mult` 与地图规则展示。

完成后暂停扩展，使用固定 seed 自动流程和真实试玩共同评估：

- 地图规则是否值得成为核心系统。
- 事件和商店需要多复杂。
- 哪些数字最影响体验。
- 哪些架构问题是真实问题，而不是预想问题。

---

## 17. 最小交付切片

为了避免长时间停留在“文档正确但没有形成可玩的垂直切片”，本 Spec 额外定义三个必须可合并的交付切片：

### Slice A：统一房间壳与幂等结算

范围：

- `room_states`
- 稳定 room / transaction ID
- `RoomFlowService`
- 休息点与当前事件占位迁移

禁止混入：

- 商店购买
- 新地图规则
- 新正式内容

完成信号：

- 同一房间重进不重复结算。
- 读档后仍能恢复到正确房间状态。

### Slice B：金币闭环与最小商店

范围：

- `EconomyService`
- `resource_ledger`
- 固定库存商店
- 一次完整购买

禁止混入：

- 刷新商店
- 多货币
- 出售

完成信号：

- 一次战斗产出金币后，能在商店稳定消费，且账本可解释。

### Slice C：事件与地图规则最小联动

范围：

- `EventService`
- `RoomEffectExecutor`
- `AdventureRuleRegistry`
- `gold_gain_mult`

禁止混入：

- 任意脚本化事件系统
- 复杂规则来源

完成信号：

- 事件添加 `gold_gain_mult` 后，后续金币收益立即可见、可保存、可测试。
