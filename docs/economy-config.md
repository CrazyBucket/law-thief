# 经济配置

局内金币奖励与商店价格集中在 `resources/adventure/economy_config.json`，调整数值不需要改脚本。

## 战斗金币

`combat_rewards` 分为三档：

- `normal`：普通战斗（`NORMAL_COMBAT`）
- `elite`：精英战斗（`ELITE_COMBAT`）
- `boss`：Boss 战（`END`，同时兼容 `BOSS` / `BOSS_COMBAT`）

每档使用包含上下限的整数区间：

```json
"normal": {"min": 8, "max": 12}
```

同一局中，同一个房间的结果由局种子和房间 id 确定；重新进入或读档不会改变奖励。

## 商店价格

`shop_prices` 先按物品类型分组，再按稀有度配置整数区间：

```json
"gem": {
  "default": {"min": 12, "max": 18},
  "rare": {"min": 27, "max": 33}
}
```

当前基础类型为 `gem`、`relic`、`consumable`。每种类型必须保留 `default`，未单独配置的稀有度会回退到该区间。商店生成货架时只随机一次并把价格写入房间快照，所以读档、返回商店和购买结算都会使用同一价格。

消耗品目前只有定价能力；仓库尚未定义消耗品资源、背包和购买交付流程。补齐这些内容后可直接复用 `EconomyService.get_shop_price_range()` 与 `roll_shop_price()`。
