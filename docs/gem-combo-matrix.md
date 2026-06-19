# 宝石组合矩阵

本文档记录当前实现中的红槽组合语义，便于排查“应该组合”和“不应该组合”的边界。数据来源以 `resources/gems/gem_defs.json` 为准；测试契约见 `tests/contracts/gem_semantics.json`。

## 术语

- 特殊组合：`combos` 数据声明的两类 tag 触发额外规则，例如爆炸+燃烧生成火焰。
- 并行叠加：多个红槽 tag 各自执行，不产生额外 combo 事件，例如爆炸和引力可以各自生效，但不是特殊组合。
- 光束改写：`light` 会改写普通攻击为光束。光束下只保留本文列出的染色、末端爆炸、分裂光束；未声明的普通后处理不再偷偷执行。

## 特殊组合

| 组合 | 当前语义 | 关键验证 |
| --- | --- | --- |
| 爆炸 + 燃烧 | 爆炸命中后在爆炸格生成火焰 | `combo/explosion_fire/red` |
| 爆炸 + 剧毒 | 爆炸命中后在爆炸格生成毒雾 | `combo/explosion_poison/red` |
| 燃烧 + 剧毒 | 命中格生成毒烟 | `combo/fire_poison/red` |
| 光 + 剧毒 | 改为毒染色光束；命中附带中毒，不在落点生成毒雾 | `combo/light_poison/red` |
| 光 + 燃烧 | 改为火染色光束；命中附带燃烧，不在落点生成火焰 | `combo/light_fire/red` |
| 光 + 导电 | 改为电染色光束；命中后从目标触发电弧弹射 | `combo/light_arc/red` |
| 光 + 冰冻 | 改为冰染色光束；命中使目标缓速，不触发普通冰的自身缓速 | `combo/light_ice/red` |
| 光 + 爆炸 | 光束命中沿途单位，爆炸只在光束末端结算 | `combo/light_explosion/red` |

## 形态叠加

| 组合 | 当前语义 | 关键验证 |
| --- | --- | --- |
| 光 + 分裂 | 发射多道光束；1/2/3 级分裂分别为 3/4/5 道；不再生成普通分裂弹 | `combo/light_split/red` |
| 分裂 + 非光红槽 tag | 走普通分裂射击，命中弹道继续携带对应 tag | `attack_tag_combo_test.gd` |

## 明确不组合

| 组合 | 当前语义 | 关键验证 |
| --- | --- | --- |
| 光 + 引力 | 只发射普通光束，不触发引力拉拽；光束不是投射物，不受蓝槽引力偏转 | `combo/light_gravity/red_not_declared`、`light_gem_effect_test.gd` |
| 光 + 反击 | 只发射普通光束，不触发反击后处理 | `light_gem_effect_test.gd` 覆盖光束后处理屏蔽 |
| 光 + 回响 | 只发射普通光束，不触发回响追击 | `light_gem_effect_test.gd` 覆盖光束后处理屏蔽 |

## 排查原则

1. 如果 `gem_defs.json` 的 `combos` 没声明，不能新增特殊 combo 事件。
2. 光束是攻击方式改写，不是普通攻击落点附魔；毒雾、火焰、引力拉拽、自身缓速等普通落点/后处理不能默认沿用。
3. 分裂属于形态叠加。遇到光束时改为多道光束；遇到非光攻击时走普通分裂弹。
4. 新增组合时必须同时更新本文件、`tests/contracts/gem_semantics.json`，并补充对应脚本测试。
