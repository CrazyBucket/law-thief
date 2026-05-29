# 遗物系统 TODO

用于在正式开工前，对遗物系统的基础设施、依赖关系与实现顺序进行统一排序。当前策略是：**先打地基，再接效果，最后做复杂遗物**。

## 当前优先级结论

1. RNG 系统
2. 稀有度定义与遗物池
3. 局内外解锁与运行时状态
4. 遗物事件与 modifier 查询层
5. 发放流程（奖励 / 商店 / 事件）
6. 简单遗物落地验证
7. 复杂结构型遗物（新增槽位 / 双色槽 / 随机变形）

---

## P0：RNG 系统 ✅ 已完成

### 目标

先把遗物相关随机的可复现性和隔离性做好，避免后续增加任意一次随机调用就污染掉落、商店、事件结果。

### TODO

- [x] 设计遗物专用随机域，不与战斗随机、地图随机共用同一调用步进
  - `RngService` 已支持 `domain` 独立计步，每个 domain 拥有独立步进计数器
- [x] 支持按 `domain` 独立计步，而不是全局共享 step
- [x] 为关键结果建立快照 / 队列机制
  - [x] 战斗奖励候选 → `derive_relic_offer_seed(room_id)` + `ScopedRng`
  - [x] Boss 遗物候选 → 同上，`rarity` 过滤在池子层完成
  - [x] 商店货架 → `derive_shop_seed(room_id)` 衍生固定种子，SL 重进结果不变
  - [x] 事件奖励候选 → `derive_gem_offer_seed(room_id)` 同机制
- [x] 明确 save/load 后是否需要复用已生成结果，而不是重新 roll
  - 采用"上下文种子衍生"策略：`ScopedRng.reset()` 重置步进，同操作序列结果完全一致
- [x] 约定遗物系统允许调用随机的入口，禁止业务代码私自直接 roll
  - 全部裸 `randi()` / `randf()` 已从 `gem_effects.gd`、`status_rules.gd`、`tile_rules.gd`、`attack_pipeline.gd` 迁移到 `RngService`
  - 视觉/特效随机统一通过 `RngService.visual_randf*` / `visual_randi*` 调用

### 新增接口（可供遗物系统直接使用）

| 接口 | 用途 |
|---|---|
| `RngService.derive_combat_seed(encounter_id, room_id)` | SL 安全的战斗种子 |
| `RngService.derive_shop_seed(room_id)` | SL 安全的商店种子 |
| `RngService.derive_relic_offer_seed(room_id, offer_index)` | 遗物奖励候选种子 |
| `RngService.derive_gem_offer_seed(room_id, offer_index)` | 宝石奖励候选种子 |
| `RngService.weighted_pick(domain, items, weights)` | 加权随机选取 |
| `RngService.create_scoped_rng(seed)` → `ScopedRng` | 隔离有状态 RNG，不污染全局 counter |
| `ScopedRng.reset()` | SL 重进时重置步进，保证序列一致 |

### 验收标准

- [x] 同一局种子下，遗物奖励候选稳定可复现
- [x] 插入无关随机调用，不会影响遗物候选结果（domain 隔离）
- [x] 存档后读取，已生成的候选结果保持一致（`ScopedRng.reset()` 机制）

---

## P1：稀有度定义与遗物池 ✅ 已完成

### 目标

先明确"遗物是什么"和"遗物从哪来"，避免后续把稀有度、掉落来源、解锁条件混在一起。

### TODO

- [x] 定义遗物稀有度结构
  - [x] `common` / `rare` / `boss`（boss 的 `_RARITY_WEIGHTS` 基础权重为 0，仅通过来源表启用）
- [x] 定义遗物基础字段（`resources/relics/relic_defs.json`）
  - [x] `id`（JSON key）
  - [x] `name`（显示名）
  - [x] `rarity`（common / rare / boss）
  - [x] `base_weight`（目前均为 1.0，支持后续细调）
  - [x] `pool_types`（`["global"]` / `["boss_drop"]` / `["shop_only"]`）
  - [x] `unlock_condition`（flag 字符串，如 `"boss_slime_king"`）
  - [x] `unique`（是否整局唯一）
  - [x] `effects`（占位 `[]`，P4 起逐步填充）
- [x] 设计遗物池分类（`_SOURCE_RARITY_WEIGHTS` 常量 + `get_relic_pool(source, ...)`）
  - [x] 普通宝箱 `normal_chest`：common 65% / rare 25% / boss 10%
  - [x] 精英战斗 `elite_combat`：common 40% / rare 40% / boss 20%
  - [x] 大型宝箱 `large_chest`：common 10% / rare 60% / boss 30%
  - [x] 商店货架 `shop`：common 50% / rare 35% / boss 15%
  - [x] 商店专属池：`pool_types` 包含 `"shop_only"` 的遗物仅在 shop 来源出现
- [x] 明确唯一性与互斥规则
  - [x] `unique: true` → 已持有则从候选池移除
  - [x] `unlock_condition` → 未解锁则不进入候选池

### 新增接口

| 接口 | 用途 |
|---|---|
| `DataRegistry.get_relic_def(id)` | 获取遗物定义 dict |
| `DataRegistry.get_relic_rarity(id)` | 获取稀有度字符串 |
| `DataRegistry.get_relic_ids()` | 所有已加载遗物 id |
| `DataRegistry.get_relic_pool(source, owned, flags)` | 按来源+持有+解锁筛选候选池 |
| `DataRegistry.roll_relic_for_source(domain, source, ...)` | 两段式抽取（先 roll 稀有度，再等权 pick） |
| `DataRegistry.roll_relic_offer(domain, source, count, ...)` | 一次生成 N 个不重复的遗物（三选一用） |

### 验收标准

- [x] 新增一个遗物时，只需要在 JSON 里加一条，不需要改池子代码结构
- [x] 任意发放来源都能先筛池子，再做随机，不靠散落 if 判断

---

## P2：动态权重修正 ✅ 已完成

### 目标

让 build 倾向能影响候选概率，但不直接污染稀有度定义。

### TODO

- [x] 设计统一的权重计算管线
  - [x] 基础权重：`base_weight`（JSON 字段，默认 1.0）
  - [x] 来源权重：`_SOURCE_RARITY_WEIGHTS` 控制稀有度概率分布（P1 完成）
  - [x] 条件过滤：`get_relic_pool` 负责（P1 完成）
  - [x] 动态权重修正：`compute_relic_weight(relic_id, weight_ctx)` 遍历 `weight_rules` 做乘积
- [x] 约定权重修正输入（`weight_ctx` Dictionary）
  - [x] 当前拥有的宝石：`owned_gems: Array[String]`
  - [x] 当前拥有的遗物：`owned_relics: Array[String]`
  - [x] 宝石颜色集合：`gem_colors: Array[String]`（"red"/"blue"/"black"）
  - [x] 总槽位数：`total_slots: int`
  - [x] 空置槽位数：`empty_slots: int`
  - [x] 传入空 Dict 时退化为等权，无破坏性
- [x] 支持特定 build 提高某类遗物出现率
  - [x] 拥有 `gem_split` → 史莱姆皇冠权重 ×5
  - [x] 拥有 `gem_conductive` → 导热铜线 ×3、镀银电缆 ×2.5
  - [x] 拥有 `relic_copper_wire` → 镀银电缆额外 ×2
  - [x] 空槽 ≥ 2 → 空棺 ×3，空壳 ×2
  - [x] 蓝色宝石 → 旧式压力阀 ×2
  - [x] 槽位 ≥ 3 → 加固底座 ×2
  - [x] 黑色宝石 → 验尸记录 ×2.5
- [x] 约定动态权重只改 `weight`，不直接篡改 `rarity`

### 新增接口与规则格式

`compute_relic_weight(relic_id, weight_ctx)` 负责计算，`weight_rules` 写在 JSON 里：

```json
"weight_rules": [
  {"type": "has_gem",            "value": "gem_split",    "multiplier": 5.0},
  {"type": "has_gem_color",      "value": "blue",         "multiplier": 2.0},
  {"type": "has_relic",          "value": "relic_copper_wire", "multiplier": 2.0},
  {"type": "slot_count_gte",     "value": 3,              "multiplier": 2.0},
  {"type": "empty_slot_count_gte","value": 2,             "multiplier": 3.0}
]
```

`roll_relic_for_source` / `roll_relic_offer` 新增末尾可选参数 `weight_ctx: Dictionary`：
- 有上下文 → 候选按动态权重加权 pick
- 无上下文（空 Dict）→ 退化为等权，与旧行为兼容

### 验收标准

- [x] 史莱姆皇冠这类 build 关联 relic 可以独立调权重（JSON 配置即可）
- [x] 权重修正规则新增时，只需改 JSON，不需要改掉落主流程代码

---

## P3：局内外解锁系统 ✅ 已完成

### 目标

拆清楚"永久解锁"和"本局拥有"，避免后续把图鉴、掉落资格、战斗状态混为一谈。

### TODO

- [x] 设计局外 Profile / Meta 数据
  - [x] 已解锁 relic（`seen_relic_<id>` flag）
  - [x] 已解锁职业（`class_<id>` flag）
  - [x] 已击败 boss（`boss_<encounter_id>` flag）
  - [x] 图鉴 / 成就事实（通用 `flag: String` 数组，存档持久化）
- [x] 设计单局 Run 数据
  - [x] 当前拥有 relic 列表（`RunState.owned_relics`）
  - [x] 已生成奖励候选快照（`RunState.relic_offer_snapshots`，SL 安全）
  - [x] relic runtime state（`RelicRuntimeState`：charges / cooldown / kv flags）
- [x] 设计单场 Battle 临时状态
  - [x] `GameState.battle_temp_flags`（每场战斗开始清空）
- [x] 统一解锁条件表达
  - [x] 所有条件统一为 `ProfileService.unlock_flag(String)` 写入
  - [x] 遗物池筛选通过 `ProfileService.get_unlock_flags()` 读取
  - [x] `AchievementService` 改为委托 `ProfileService`

### 新增文件

| 文件 | 职责 |
|---|---|
| `scripts/data/relic_runtime_state.gd` | 遗物运行时状态数据类（charges / cooldown / kv flags） |
| `scripts/data/run_state.gd` | 单局状态数据类（拥有遗物、候选快照、runtime 索引） |
| `scripts/services/run_service.gd` | 单局 autoload：get_or_roll_relic_offer / acquire_relic / 存读档 |

### 新增 API

| 接口 | 用途 |
|---|---|
| `RunService.start_run(master_seed, map_seed)` | 开启新局，初始化 RunState |
| `RunService.end_run()` | 结束局，删 run_save.json |
| `RunService.acquire_relic(id)` | 获取遗物，自动写入图鉴 |
| `RunService.get_or_roll_relic_offer(room_id, source, count)` | SL 安全的奖励候选（首次 roll，之后读快照）|
| `RunService.get_weight_ctx(state?)` | 构建 DataRegistry 所需权重上下文 |
| `ProfileService.unlock_flag(flag)` | 写入永久解锁 flag（自动存档）|
| `ProfileService.get_unlock_flags()` | 获取所有解锁 flag（供池筛选） |
| `ProfileService.mark_seen_relic(id)` | 遗物图鉴 |
| `ProfileService.mark_enemy_seen/killed(id)` | 怪物图鉴 |

### 验收标准

- [x] 解锁条件可配置，不需要每个遗物单独手写判断逻辑
- [x] 局外、局内、单场状态边界清晰

---

## P4：遗物事件系统与 modifier 查询层 ✅ 已完成

### 目标

建立遗物统一生效入口，避免未来在 `CombatRules`、`GemRules`、`TileRules`、`BattleActionService` 里到处写 `has_relic(...)`。

### TODO

- [x] 设计遗物事件词表
  - [x] `battle_start`（破损护符：每场战斗 +2 护甲）
  - [x] `turn_start` / `turn_end`
  - [x] `unit_die`（验尸记录：玩家击杀回 2 血）
  - [x] `after_extract` / `after_insert`（加固底座：嵌入宝石 +1 护甲）
  - [x] `battle_win`
  - [x] `before_attack` / `after_attack_hit` / `before_damage_taken` / `after_damage_taken` / `move_step`（词表已定义，待接入 action）
- [x] 设计 modifier 查询词表
  - [x] `attack_damage_mult`（接入 `CombatRules.attack_damage`）
  - [x] `arc_damage_mult`（导热铜线：电弧伤害 ×1.3，接入 `_calc_arc_damage`）
  - [x] `collision_damage_mult` / `extract_range_bonus` / `insert_range_bonus` / `move_bonus`（词表已定义）
  - [x] `forced_move_immune`（接入 `Displacement.knockback` / `pull_toward`）
  - [x] `tile_effect_immune`（词表已定义）
  - [x] `first_damage_absorb`（止痛药：首次受伤降为 1，接入 `CombatRules.apply_damage`）
- [x] 约定通用 effect handler 与 script handler 的边界
  - 通用 action：`add_armor` / `heal` / `add_move` / `mark_flag`
  - 复杂遗物可在 `_dispatch_action` 里追加专属 action
- [x] 明确复杂遗物是否允许脚本特例
  - 允许；P7 复杂遗物通过注册 action 或直接扩展 `fire_event` 接入

### 新增文件

| 文件 | 职责 |
|---|---|
| `scripts/services/relic_effect_registry.gd` | 事件分发中枢 + modifier 查询层（autoload） |

### 新增 API

| 接口 | 用途 |
|---|---|
| `RelicEffectRegistry.fire_event(event_id, state, payload)` | 触发遗物事件，遍历当前局持有遗物，按 effects 配置执行 action |
| `RelicEffectRegistry.query_modifier(modifier_id, state, ctx?)` | 查询 modifier，乘数叠乘、加成叠加、bool 任一为 true |

### 接入点汇总

| 接入点 | 事件 / modifier |
|---|---|
| `BattleController._connect_relic_signals` | `battle_start`, `turn_start`, `turn_end`, `unit_die`, `battle_win` |
| `GemRules.extract` | `after_extract` |
| `GemRules.insert` | `after_insert` |
| `CombatRules.apply_damage` | modifier: `first_damage_absorb` |
| `CombatRules.attack_damage` | modifier: `attack_damage_mult` |
| `GemEffects._calc_arc_damage` | modifier: `arc_damage_mult` |
| `Displacement.knockback / pull_toward` | modifier: `forced_move_immune` |

### 验收标准

- [x] 新遗物优先通过配置 + handler 接入
- [x] 只有少数复杂遗物需要特例脚本

---

## P5：发放流程接入 ✅ 已完成

### 目标

把遗物真正接到 run loop 中，明确玩家在哪些节点获得遗物。

### TODO

- [x] 普通战斗胜利后的遗物奖励流程（`battle_scene._apply_battle_end` 胜利分支）
- [x] Boss 战后的专属遗物奖励流程（`ELITE_COMBAT` → `elite_combat` 来源，池概率更高）
- [ ] 商店售卖遗物流程（P5 暂不做，等 SHOP 房间实现）
- [ ] 事件给予遗物流程（等 EVENT 房间实现）
- [x] 避免同一来源重复发放相同候选（`RunService.get_or_roll_relic_offer` 首次 roll + snapshot，SL 安全）
- [x] UI 层显示稀有度、名称、描述、解锁状态（动态建 CanvasLayer 弹窗）

### 实现要点

- `_ENCOUNTER_RELIC_SOURCE` 映射表：`NORMAL_COMBAT → normal_chest`，`ELITE_COMBAT → elite_combat`
- `_apply_battle_end` 胜利且 run 活跃时调 `RunService.get_or_roll_relic_offer`
- 弹窗为纯 GDScript 动态构建（`CanvasLayer layer=80`），无需新 .tscn
- 每张遗物卡展示名称、稀有度、效果提示；可选「跳过」
- 玩家选择后调 `RunService.acquire_relic`，然后自动导航回冒险地图
- `GameService.finish_battle` 延迟到选择结束后才触发（`_finish_battle_and_navigate`）

### 验收标准

- [x] 存在完整的"战斗胜利 → 候选生成 → 玩家领取 → 写入 RunState → 自动返回地图"闭环

---

## P6：先落地的验证遗物

### 目标

先用低风险遗物验证系统完整性，不一开始就上结构型遗物。

### 第一批建议

- [ ] `破损护符`：每场战斗开始获得护甲
- [ ] `加固底座`：向自身嵌入宝石后获得护甲
- [ ] `止痛药`：每场战斗第一次受伤降为 1
- [ ] `导热铜线`：导电弹射目标数 +1
- [ ] `验尸记录`：黑槽击杀回血

### 验收标准

- 至少覆盖 battle_start / after_insert / before_damage_taken / unit_die / modifier query 这几类核心入口

---

## P7：复杂遗物与结构升级

### 目标

在基础系统稳定后，再做会改槽位结构或需要复杂上下文的遗物。

### TODO

- [ ] 槽位结构升级
  - [ ] 支持新增槽位
  - [ ] 支持复合槽 / 双色槽
  - [ ] 支持槽位 UI 展示升级
- [ ] 复杂遗物落地
  - [ ] `棱镜`
  - [ ] `相位扳手`
  - [ ] `空棺`
  - [ ] `嫁祸`
  - [ ] `微型赌场`
  - [ ] `混沌发射器`
  - [ ] `史莱姆皇冠`
- [ ] 为链式篡律、随机变形、build 识别补充运行时上下文

### 验收标准

- 能支持“新增槽位 / 槽位升格 / 随机改宝石 / 条件型强联动 relic”而不推翻前面的框架

---

## 暂定实施顺序

### 第一阶段

- [ ] P0 RNG 系统
- [ ] P1 稀有度定义与遗物池
- [ ] P2 动态权重修正

### 第二阶段

- [ ] P3 局内外解锁系统
- [ ] P4 遗物事件系统与 modifier 查询层

### 第三阶段

- [ ] P5 发放流程接入
- [ ] P6 第一批验证遗物

### 第四阶段

- [ ] P7 复杂遗物与槽位结构升级

---

## 当前建议

当前优先实现：**P0 RNG 系统**。

原因：

- 后续遗物奖励、商店、事件、随机变形都依赖稳定随机
- RNG 设计不先定，后面任何候选系统都可能返工
- 它是遗物掉落与 save/load 一致性的底层前提
