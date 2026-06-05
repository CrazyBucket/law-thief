# 宝石 v1 技术方案

## 文档目标

本文档把《宝石设计文档 v1》落到当前 Godot 项目的技术实现层，重点解决三件事：

- 同 tag 多颗宝石在红 / 蓝 / 黑槽中的等级结算。
- 不同 tag 之间的组合、染色、回响等联动如何进入规则层。
- 宝石获取、敌人生成、奖励、商店等来源如何使用统一的等级池子。

当前项目已有基础宝石运行时，包括：

- `resources/gems/gem_defs.json`：宝石定义。
- `scripts/data/gem_state.gd`：战斗内宝石实例。
- `scripts/data/slot_state.gd`：红 / 蓝 / 黑槽与双色槽。
- `scripts/rules/gem_rules.gd`：拔出、插入、主动触发。
- `scripts/rules/gem_effects.gd`：各类宝石效果入口。
- `scripts/rules/attack_pipeline.gd`：攻击 tag 管线。
- `scripts/services/data_registry.gd`：定义加载、奖励 roll、遭遇战生成。

本方案不推翻这些入口，而是在其上增加一层“宝石 tag 解析与等级上下文”。效果函数只消费已经解析好的上下文，避免每颗宝石在各自代码里重复计算等级、槽位和组合。

## 设计边界

### 本期范围

- 宝石基础字段扩展：tag、元素、池子等级、组合声明。
- 槽位内同 tag 数量结算为 1 / 2 / 3 级效果。
- 红槽主动攻击、蓝槽受击 / 接触、黑槽死亡结算的统一触发上下文。
- v1 核心宝石：爆炸、引力、剧毒、导电、燃烧、冰冻、分裂。
- 第一批组合：爆炸 + 燃烧、爆炸 + 剧毒、剧毒 + 燃烧、光 + 元素染色。
- 回响的抽取规则与防递归机制。
- 宝石奖励池、敌人生成池、商店池的等级权重方案。

### 暂不展开

- 完整背包 UI 与局外收藏。
- 宝石升级 / 合成系统。
- 所有视觉表现的最终美术资源。
- 极端组合的完整平衡数值。

## 核心概念

### Gem Definition

`resources/gems/gem_defs.json` 继续作为静态定义源，但需要扩展为以 tag 为中心的结构：

```json
{
  "gem_explosion": {
    "tag": "explosion",
    "element": "explosion",
    "pool_tier": 1,
    "rarity": "common",
    "max_stack_level": 3,
    "ability_profiles": {
      "unit_red_active": "explosion",
      "blue_damaged": "explosion",
      "black_death": "explosion"
    },
    "combos": ["fire", "poison"]
  }
}
```

字段含义：

- `tag`：规则身份。同 tag 多颗计入同一等级。
- `element`：组合与染色使用，可与 `tag` 相同，也可为空。
- `pool_tier`：池子等级，用于奖励 / 敌人 / 商店解锁。
- `max_stack_level`：默认 3，限制同一槽位同 tag 最高效果等级。
- `ability_profiles`：保留现有 profile 机制，作为效果函数路由。
- `combos`：声明该 tag 可与哪些 tag / element 联动，用于数据校验和 UI 提示。

### Gem Instance

`GemState` 继续只保存运行时差异：

- `uid`
- `gem_id`
- `owner_uid`
- `slot_index`
- `def_overrides`

不把等级写入 `GemState`。等级由当前槽位布局即时解析，这样拔出、插入、分裂继承、强塞过载后不会留下过期等级。

### Slot Group

一个单位或地块上，同一种槽位类型形成一个 slot group。

例如玩家拥有 3 个红槽，其中 2 个插了爆炸，1 个插了燃烧：

- 红槽 `explosion` 等级为 2。
- 红槽 `fire` 等级为 1。
- 红槽存在 `explosion + fire` 组合。

双色槽参与对应颜色的 group。若一个双色槽同时接受红 / 蓝，但实际插入的是红色宝石，本次只按插入宝石所在触发语义参与对应 group。

## Tag 等级池子

### 等级定义

同一 owner 的同一槽位语义下，同 tag 数量映射为等级：

| 数量 | 等级 | 语义 |
| --- | --- | --- |
| 0 | 0 | 不触发 |
| 1 | 1 | 基础机制 |
| 2 | 2 | 形态质变 |
| 3+ | 3 | 过载强化 |

等级只表达“效果强度层级”，不等同于稀有度。

### 解析入口

新增建议脚本：

- `scripts/rules/gem_tag_resolver.gd`
- `scripts/data/gem_effect_context.gd`，如果 GDScript 类型收益不高，也可以先用 Dictionary。

核心 API：

```gdscript
static func build_context(state: GameState, owner: Variant, slot_type: String, timing: String, primary_slot: SlotState = null) -> Dictionary
```

返回结构：

```gdscript
{
  "owner_uid": "player_1",
  "slot_type": "red",
  "timing": "active",
  "primary_tag": "explosion",
  "tag_levels": {"explosion": 2, "fire": 1},
  "tag_counts": {"explosion": 2, "fire": 1},
  "tags": ["explosion", "fire"],
  "combos": ["explosion_fire"],
  "source_gem_uids": ["gem_1", "gem_2", "gem_3"],
  "echo_depth": 0
}
```

所有宝石效果都从这个 context 读取等级：

- 爆炸红槽 1 级：十字 1 格。
- 爆炸红槽 2 级：3x3。
- 爆炸红槽 3 级：3x3，2 倍伤害。

而不是在 `explode_cross_at()` 内自行扫描槽位。

### 池子等级

池子等级用于控制“什么时候能出现哪些 tag / 几级组合条件”。

建议拆成三层：

- `pool_tier`：宝石定义自身等级，控制是否进入候选池。
- `source_tier`：来源等级，普通战、精英战、Boss、商店、事件各自不同。
- `chapter_tier`：章节等级，随地图推进提高上限。

实际 roll 流程：

1. 根据来源得到 `source_tier` 和稀有度权重。
2. 根据章节得到 `chapter_tier`。
3. 过滤 `gem.pool_tier <= min(source_tier, chapter_tier)` 的宝石。
4. 用稀有度权重和 tag 权重 roll 出 gem_id。
5. 若本来源允许“组合教学”，可对指定 tag 加权，但仍不直接塞满 3 级。

建议新增配置：

- `resources/gems/gem_pools.json`

示例：

```json
{
  "normal_chest": {
    "source_tier": 1,
    "rarity_weights": {"common": 70, "uncommon": 25, "rare": 5},
    "tag_weights": {"explosion": 1.0, "poison": 1.0, "gravity": 0.8}
  },
  "elite_combat": {
    "source_tier": 2,
    "rarity_weights": {"common": 35, "uncommon": 45, "rare": 20}
  },
  "boss_reward": {
    "source_tier": 3,
    "rarity_weights": {"uncommon": 30, "rare": 50, "epic": 20}
  }
}
```

`DataRegistry` 目前已经有 `_SOURCE_RARITY_WEIGHTS`，后续可迁移到 JSON，避免池子逻辑继续硬编码。

## 触发管线

### 红槽

红槽是主动攻击或主动触发。推荐统一接入 `AttackPipeline`：

1. `AttackPipeline._gem_hooks_prepare()` 收集红槽 tag context。
2. 根据 `primary_tag` 和 `tag_levels` 添加攻击 tag。
3. `AttackPipeline._phase_hit()` 只处理攻击管线通用事件。
4. 复杂效果调用 `GemEffects.apply_red_tag(ctx, gem_ctx)`。

红槽多 tag 同时存在时，按以下优先级处理：

1. 形态改变类：分裂、光束。
2. 空间改变类：爆炸、引力。
3. 命中附加类：燃烧、剧毒、导电、冰冻。
4. 额外触发类：反击、回响。

这样可以避免“先爆炸还是先上毒”在不同函数里不一致。

### 蓝槽

蓝槽主要由受击、接触、远程攻击、强制位移触发。推荐把触发时机固定为：

- `owner_damaged`
- `on_contact`
- `forced_move`
- `ranged_incoming`

`GemEffects.run_unit_hooks()` 当前已能按 timing 跑 hook，但还缺“同 tag 等级上下文”。后续应在 `_run_slot_hook()` 前构建 context，并传给具体效果。

蓝槽需要注意：

- 一次伤害事件中，同 tag 蓝槽只触发一次，等级由数量决定。
- 分裂蓝槽的伤害拦截要发生在 `CombatRules.apply_damage()` 早期。
- 接触类效果应由 `ContactResolver` 统一发出，避免移动接触和攻击接触规则不同。

### 黑槽

黑槽由死亡结算触发。当前 `GemEffects.BLACK_DEATH_PROFILE_ORDER` 已有固定顺序，后续应升级为数据化顺序：

1. 生存替换：分裂。
2. 位置控制：引力、冰冻。
3. 区域伤害：爆炸、导电、燃烧、剧毒。
4. 清算 / 追加：光、反击、回响。

黑槽规则必须防止无限递归：

- 每次死亡结算带 `death_chain_id`。
- 同一个单位同一个 tag 在同一个 `death_chain_id` 中最多结算一次。
- 回响触发的黑槽效果继承 `death_chain_id`，并增加 `echo_depth`。

## 组合规则

### 组合解析

新增建议脚本：

- `scripts/rules/gem_combo_resolver.gd`

组合不是新宝石，而是 context 上的派生标签：

```gdscript
{
  "combos": ["explosion_fire", "explosion_poison"],
  "combo_levels": {"explosion_fire": 1}
}
```

组合等级建议先取参与 tag 的最低等级：

```text
combo_level = min(level(tag_a), level(tag_b))
```

如果后续设计需要，也可以给某些组合设置独立公式。

### 第一批组合

| 组合 | 触发位置 | 技术落点 |
| --- | --- | --- |
| 爆炸 + 燃烧 | 爆炸后产生火焰 | 爆炸结算结束后调用 `TileRules.create_fire()` |
| 爆炸 + 剧毒 | 爆炸后产生毒雾 | 爆炸影响格调用 `TileRules.create_poison_fog()` |
| 剧毒 + 燃烧 | 生成毒烟 | 新增 `TILE_MOD_TOXIC_SMOKE`，同时具备火焰和毒雾语义，持续 1 回合 |
| 光 + 元素 | 染色光束 | 光束命中时按元素追加状态；爆炸类在光束终点触发 |

组合触发应尽量挂在“主效果完成后”的统一点，而不是混入主效果本身。例如爆炸负责“哪些格子被爆”，组合负责“这些格子额外生成什么”。

## 回响规则

回响需要特殊处理，因为它会调用其他 tag 效果。

规则：

- 回响不能抽到回响。
- 同一次触发内，同一个 source gem 不能被重复抽取。
- `echo_depth` 默认 0，最大 1；未来如果有遗物突破，再显式放宽。
- 回响抽到的效果使用被抽 tag 的同槽位语义。
- 回响 1 级抽 1 个 tag，2 级抽 2 个不同 tag，3 级抽 2 个 tag 且其中一个使用 `level + 1` 的强化上限，但最高仍按 3 级裁剪。

建议新增：

- `scripts/rules/gem_echo_rules.gd`

API：

```gdscript
static func resolve_echo_tags(state: GameState, gem_ctx: Dictionary, rng_key: String) -> Array[Dictionary]
```

返回每个被抽 tag 的临时 context，由 `GemEffects` 按普通 tag 效果执行。

## 数据与本地化

### 宝石定义拆分

建议把 `gem_defs.json` 扩展为只放“身份与表现”，把数值放到独立表：

- `resources/gems/gem_defs.json`
- `resources/gems/gem_effect_levels.json`
- `resources/gems/gem_pools.json`
- `resources/gems/gem_combos.json`

`gem_effect_levels.json` 负责描述每个 tag / 槽位 / 等级的参数：

```json
{
  "explosion": {
    "red": {
      "1": {"shape": "cross", "radius": 1, "damage": 12},
      "2": {"shape": "square", "radius": 1, "damage": 12},
      "3": {"shape": "square", "radius": 1, "damage": 24}
    }
  }
}
```

第一阶段可以只把会频繁调参的数值外置；复杂流程仍保留在 GDScript。

### 描述文本

UI 描述不应手写三份长文本。建议由 `DataRegistry.get_gem_effect_description()` 基于：

- tag
- slot_type
- level
- combos

生成。中文文本仍进 `localization/strings.csv`。

## 与现有系统的衔接

### `AttackPipeline`

保留现有攻击 tag，但从“逐颗 gem 添加 tag”升级为“按 tag context 添加 tag”。

当前：

```gdscript
_add_attack_tags_from_red_profile(ctx, profile)
```

建议：

```gdscript
var gem_ctx := GemTagResolver.build_context(ctx.state, ctx.attacker, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
GemAttackTagMapper.apply_to_attack_context(ctx, gem_ctx)
```

### `GemEffects`

`GemEffects` 保留为规则实现集合，但效果函数签名逐步增加 context：

```gdscript
static func apply_explosion_red(state: GameState, owner: UnitState, target_cell: Vector2i, gem_ctx: Dictionary, events: Array[Dictionary]) -> void
```

### `DataRegistry`

新增职责：

- 加载 `gem_pools.json`。
- 加载 `gem_effect_levels.json`。
- 提供 `get_gem_tag()`、`get_gem_pool_tier()`、`get_gem_level_params()`。
- 将 `roll_spawnable_gem_id()` 改为基于 pool 配置。

### `RunState`

跨战保存仍只保存 gem_id / overrides，不保存解析等级。这样玩家槽位变化后，下场战斗会自然按当前布局重新计算等级。

## 验收口径

第一阶段完成后，以下行为必须成立：

- 同一单位红槽插 1 / 2 / 3 个爆炸，攻击范围形态与伤害按设计变化。
- 同一单位蓝槽插 1 / 2 / 3 个导电，被攻击反击概率按设计变化。
- 同一单位黑槽插 1 / 2 / 3 个分裂，死亡分裂属性按等级变化。
- 爆炸 + 燃烧会在爆炸后生成火焰。
- 爆炸 + 剧毒会在爆炸后生成毒雾。
- 回响不会抽到回响，也不会在一次触发中无限递归。
- 普通战、精英战、Boss 奖励使用不同池子，低章节不会提前 roll 出高等级池宝石。

## Todo

### P0 架构地基

- [x] 新增 `GemTagResolver`，按 owner / slot_type / timing 解析 `tag_levels`、`tag_counts`、`combos`。
- [x] 给 `gem_defs.json` 补 `tag`、`element`、`pool_tier`、`max_stack_level` 字段。
- [x] 给 `DataRegistry` 增加 `get_gem_tag()`、`get_gem_element()`、`get_gem_pool_tier()`。
- [x] 新增 `gem_pools.json`，把 `_SOURCE_RARITY_WEIGHTS` 迁出硬编码。
- [x] 新增最小单测：同槽位 1 / 2 / 3 颗同 tag 能解析为 1 / 2 / 3 级。

### P1 红蓝黑等级效果

- [x] 爆炸红槽 1 / 2 / 3 级接入等级 context，覆盖普通攻击与主动触发。
- [x] 爆炸按红 / 蓝 / 黑槽 1 / 2 / 3 级重做参数读取。
- [x] 导电按红 / 蓝 / 黑槽 1 / 2 / 3 级重做概率、弹射次数、死亡落雷。
- [x] 分裂按红 / 蓝 / 黑槽 1 / 2 / 3 级重做分裂数量、分伤、分身属性。
  - [x] 红槽 2 / 3 级：4 / 5 发弹道与预览同步。
  - [x] 蓝槽 2 级：受击伤害在自身与周围合法单位之间均分。
  - [x] 蓝槽 3 级：受伤后生成 1 血临时分身，每回合限一次。
  - [x] 黑槽 2 / 3 级：分身属性保留 50% / 80%。
- [x] 引力、剧毒、燃烧、冰冻接入同一等级 context。
  - [x] 引力红槽：普通攻击范围按等级 +0 / +1 / +2，并已接到射程 / AI / 预览。
  - [x] 剧毒蓝槽 2 级：回合结束向最近未中毒友方传播 1 层毒。
- [x] 黑槽死亡结算增加 `death_chain_id`，防止连锁递归失控。

### P2 组合与特殊 tag

- [x] 新增 `GemComboResolver`，组合等级默认取参与 tag 最小等级。
- [x] 实现爆炸 + 燃烧：爆炸后生成火焰。
- [x] 实现爆炸 + 剧毒：爆炸后生成毒雾。
- [x] 实现剧毒 + 燃烧：新增毒烟地块 modifier。
- [x] 新增光、反击、回响三个宝石定义和最低可玩效果。
- [x] 新增 `GemEchoRules`，实现防抽自身、防递归、强化版抽取。

### P3 池子、遭遇与奖励

- [x] `roll_spawnable_gem_id()` 改为使用 `gem_pools.json`。
- [x] 敌人生成根据章节、房间类型、敌人模板选择 source pool。
- [x] 战斗奖励、事件奖励、商店商品分别接入不同 pool。
- [x] 增加"教学加权"配置，允许指定章节更容易出现某些组合材料。
- [x] 给 debug console 增加查看当前 pool 候选的命令。

### P4 UI 与表现

- [x] 槽位 tooltip 显示当前 tag 等级和组合。
- [x] 宝石奖励界面显示 pool tier / 稀有度 / tag。
- [x] 攻击预览显示组合后的范围，例如爆炸 2 级 3x3。
- [x] 事件流补齐爆炸、毒雾、火焰、光束、回响的 visual event。
- [x] 本地化补齐所有新增宝石和等级描述。

### P5 回归测试

- [x] 新增 `gem_tag_resolver_test.gd`。
- [x] 新增 `gem_pool_roll_test.gd`，验证来源、章节、权重过滤。
- [x] 新增 `gem_combo_test.gd`，覆盖爆炸 + 燃烧、爆炸 + 剧毒、剧毒 + 燃烧。
- [x] 新增 `gem_echo_test.gd`，覆盖不抽自身和最大递归深度。
- [x] 扩展现有 `blue_black_combo_test.gd`、`attack_tag_combo_test.gd`，改为验证等级 context。

## 当前已知问题

- `scripts/tests/blue_black_combo_test.gd` 的黑槽剧毒旧断言已对齐等级 context：`poison` 1 级只校验 debuff 转移，2 / 3 级再校验毒雾与 `poison_burst`。当前该矩阵测试已可作为有效回归。
- 当前与 P1 / P2 相关的回归测试已覆盖：`skill_test.gd`、`gem_tag_resolver_test.gd`、`gem_pool_roll_test.gd`、`gem_combo_test.gd`、`gem_echo_test.gd`、`blue_black_combo_test.gd`、`attack_tag_combo_test.gd`、`gem_level_context_test.gd`、`status_test.gd`。
- 当前剩余主要是静态检查 warning（例如 shadowed identifier / unused parameter），不影响本轮 P1 / P2 机制落地与测试通过。

## 推荐落地顺序

1. 先做 `GemTagResolver` 和测试，不改实际效果。
2. 把爆炸迁移到等级 context，作为第一颗完整样板。
3. 接入组合 resolver，先只做爆炸 + 燃烧 / 剧毒。
4. 把导电、分裂迁移，覆盖红 / 蓝 / 黑三种触发复杂度。
5. 做池子 JSON 化，让奖励和敌人生成开始吃同一套过滤规则。
6. 最后接光、反击、回响，因为它们依赖组合和递归防护。

这条顺序能保证每一步都有可测行为，不需要一次性重写全部宝石。
