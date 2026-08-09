# 大文件盘点与拆分候选

盘点时间：2026-07-14  
范围：项目工作区；排除 `.git/`、`.godot/`、`artifacts/`。  
说明：资源按文件体积筛选，代码/配置按准确行数筛选。当前工作区原本已有大量修改，本盘点未修改任何既有文件。

## 结论

- 盘点时体积最大的运行时资源是 `assets/audio/menu_bgm_lawthief.wav`，18.13 MB；该冗余 WAV 已于 2026-08-09 移除，菜单统一使用 1.69 MB OGG。
- 代码侧最需要优先拆分的是 `battle_scene.gd`（3,687 行）和 `isometric_board.gd`（3,660 行）；两者同时混合了 UI、输入、战斗流程、编辑器、奖励结算、绘制和动画。
- 规则侧的首要候选是 `gem_effects.gd`（2,479 行），其次是 `attack_pipeline.gd`（983 行）和 `status_rules.gd`（790 行）。
- 数据/校验侧的主要候选是 `data_registry.gd`（1,853 行）、`balance_config_validator.gd`（1,518 行）和 `adventure_config_validator.gd`（1,008 行）。
- 发现一对内容完全相同的大图：`assets/ui/main_title.png` 与 `assets/demo/doodle-rpg/ALL SPRITES/UI/title.png`，SHA-256 相同，各 537.2 KB。
- `tmp/` 下有 75 个文件、约 2.72 MB，且其中 32 个文件已被 Git 跟踪；它们应在资源拆分前明确“评审产物”还是“正式资源”。

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
- `BattleScene` 当前为 3,248 行，`IsometricBoard` 当前为 3,380 行；组件测试持续固化奖励、战斗特效和 overlay 输入/渲染契约。
- 菜单音乐已收口到 `AudioService` 的 OGG 播放入口，移除重复场景播放器和未引用 WAV。

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
| 537.2 KB | `assets/ui/main_title.png` |
| 537.2 KB | `assets/demo/doodle-rpg/ALL SPRITES/UI/title.png` |
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
| 140.6 KB | `scripts/ui/battle_scene.gd` |
| 137.3 KB | `scripts/ui/isometric_board.gd` |
| 123.5 KB | `assets/units/female-adventurer/frame dimensions.png` |
| 110.6 KB | `assets/demo/doodle-rpg/ALL SPRITES/Extras.png` |
| 105.5 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Sword Swing/Frames3.PNG` |
| 105.5 KB | `assets/demo/doodle-rpg/ALL SPRITES/Knight/Sword Swing/Frames1.PNG` |
| 103.1 KB | `assets/overlays/vegetation/overlay_grass_patch.png` |

## 代码/测试大文件（大于等于 500 行）

这些文件不一定都应拆分；测试文件通常是场景集合，需先判断是否只是数据量大。

| 行数 | 文件 | 初步判断 |
| ---: | --- | --- |
| 3,687 | `scripts/ui/battle_scene.gd` | P0：战斗页面、输入、编辑器、奖励结算、结果页、动画接线集中在一个 Control |
| 3,660 | `scripts/ui/isometric_board.gd` | P0：棋盘绘制、单位/覆盖物、槽位、宝石、移动动画、战斗特效集中在一个 Control |
| 2,479 | `scripts/rules/gem_effects.gd` | P0：宝石触发、伤害/位移、死亡链、光束/导电、毒/分裂等规则集中 |
| 1,853 | `scripts/services/data_registry.gd` | P0：数据加载、解析、查询、随机池、奖励、运行时实例化、存档恢复集中 |
| 1,518 | `scripts/services/balance_config_validator.gd` | P1：多个配置域共用一个校验器，适合按配置域拆分 |
| 1,241 | `scripts/ui/battle_hud_presenter.gd` | P1：状态检查、槽位提示、时间线、遗物栏、布局适配集中 |
| 1,226 | `scripts/debug/battle_editor_cli.gd` | P1：命令分发、参数解析、对象变更、导入导出、格式化集中 |
| 1,008 | `scripts/services/adventure_config_validator.gd` | P1：冒险、遭遇、经济、奖励、地图规则校验集中 |
| 983 | `scripts/rules/attack_pipeline.gd` | P1：攻击阶段与大量宝石/遗物特例混在同一管线 |
| 911 | `scripts/tests/balance_config_test.gd` | P2：测试数据/断言量大，先保持边界清晰再拆 |
| 839 | `scripts/services/run_service.gd` | P1：运行状态、路线、奖励、恢复与持久化边界需确认 |
| 832 | `scripts/main/main_root.gd` | P1：主菜单、设置、页面构建、粒子、音乐、元控制台集中 |
| 790 | `scripts/rules/status_rules.gd` | P1：状态增减、触发与派生效果集中 |
| 788 | `scripts/map/tile_renderer.gd` | P1：地图瓦片、房间路线、覆盖物和绘制逻辑集中 |
| 781 | `scripts/debug/battle_editor_service.gd` | P1：编辑器操作与运行时状态变更集中 |
| 758 | `scripts/rules/board_utils.gd` | P1：棋盘查询、路径、占用和规则辅助集中 |
| 713 | `scripts/tests/fission_slime_test.gd` | P2：单敌人场景测试较大，确认是否可按行为拆分 |
| 670 | `scripts/rules/enemy_ai.gd` | P1：敌人意图、评分、执行前后处理集中 |
| 634 | `scripts/battle/battle_query_service.gd` | P1：战斗查询接口边界较宽 |
| 583 | `scripts/services/relic_effect_registry.gd` | P1：遗物效果注册/执行可按触发时机或主题拆分 |
| 582 | `scripts/rules/overload_rules.gd` | P1：过载计算与效果触发集中 |
| 561 | `scripts/ui/battle_event_player.gd` | P1：事件解释、动画调度和表现层状态推进集中 |
| 548 | `scripts/ui/rich_tooltip.gd` | P2：可按内容模型、布局和主题拆分 |
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
