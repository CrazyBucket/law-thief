# Numeric Drive Issues

This file records problems exposed while implementing the numeric-drive plan, including issues not directly fixed in the same change.

## Open

### Design root lookup is broken on this Windows workspace

- `./tools/context ...` reports `DESIGN_ROOT_MISSING /Users/jinhuiwu/code/learning-notes/game/design/law-thief`.
- The actual design docs are available locally under `D:/code/learning-notes/game/design/law-thief`.
- Impact: design lookup tooling is less trustworthy than the source documents themselves until the path resolution is fixed.

### Several passing tests still exit with resource leak warnings

- `stone_bow_guard_test.gd` currently passes but exits with `ObjectDB instances leaked at exit` and `resources still in use at exit`.
- `overload_test.gd` reproduces the same warnings after passing.
- Additional fast-suite runs show the same class of warnings in `battle_renderer_timing_test.gd`, `bomb_rat_test.gd`, `explosion_test.gd`, and `intent_consistency_contract_test.gd`.
- Impact: test signal is noisier than it should be, and real lifecycle regressions may be easier to miss.

### Text encoding is visibly corrupted in several runtime strings

- Multiple strings in `overload_rules.gd` and some test output appear mojibake-corrupted.
- Impact: player-facing or debug-facing text is harder to inspect, and future copy updates become riskier.

### Semantic contract coverage is still low for a data-driven system

- Current executable design coverage is `38 / 90 = 42.22%`.
- Large gaps remain in blue/black gem semantics, especially for explosion, gravity, conductive, fire, ice, split, light, counter, and echo branches.
- Impact: moving more balance into data increases leverage, but also increases risk if semantic coverage does not expand with it.

### Verify tooling is brittle on this Windows desktop environment

- Direct `./tools/verify changed` emits WSL startup noise in this workspace before running Godot.
- The command can still complete successfully, but the startup noise makes logs look scarier than the actual test result.
- Impact: verification remains usable, but the signal is noisier than it should be.

### Verify artifact logs can contain stale failures

- `artifacts/verify/report.json` and `artifacts/verify/verify.log` describe the latest `verify` run, but old per-test logs may remain beside them.
- A broad grep over `artifacts/verify/*.log` can therefore surface historical failures that were not part of the current run.
- Impact: debugging from artifacts requires checking the latest `verify.log` test list before treating any per-test log as current evidence.

### `battle_scene.tscn` still has invalid ext_resource UIDs

- `battle_renderer_timing_test` emits warnings that several `res://scenes/battle/battle_scene.tscn` ext_resource UIDs are invalid and Godot is falling back to text paths.
- Impact: the scene still loads, but asset references are carrying editor-level integrity debt that can create noisy warnings and fragile scene metadata.

### Full visual contract suite currently has overlay/water failures

- `./tools/verify all` on 2026-07-09 passed 67 tests and failed 3 tests unrelated to the save-slot copy change.
- `overlay_render_contract_test` fails layer-order assertions: front overlay pass, unit UI, and selection outlines are not above the expected passes.
- `water_frame_composite_test` fails PNG save attempts under `/tmp/law_thief_water_frames/` and reports single-tile frame mismatches.
- `water_render_contract_test` fails to locate entity/unit draw commands and reports draw-order assertions for entities and unit UI.
- Impact: changed-suite signal remains green for the current numeric-drive changes, but full visual contract health is not clean.

### Debug-only seed display boundaries need an audit

- `scripts/ui/adventure_map_scene.gd` still renders `调试种子 %d`.
- This appears intentionally debug-facing, but the boundary between debug/editor UI and normal player UI needs to stay explicit.
- Impact: seed display is acceptable behind debug UI, but should not leak into normal run selection or player-facing HUD.

## Resolved / Mitigated

### Normal save-slot summary exposed internal seed and map coordinates

- Phase 20 removed `map_seed` and `current_map_pos` from the normal save-slot subtitle.
- Active runs now show player-facing progress, `第 N 章 · 持有遗物 X`, using run-state fields.
- `run_save_corruption_recovery_test` verifies that active slot summaries do not expose seed or coordinate text.
- Residual debug seed display in `adventure_map_scene.gd` is tracked separately because it appears debug-facing rather than normal save-slot UI.

### Un-templated player copy could drift away from configured numeric values

- Phase 19 added literal-number checks for authored adventure event text, map-rule text, and relic descriptions.
- Numeric text tokens are stripped before checking, so token ids may contain digits without triggering false positives.
- Event titles/bodies/options and map-rule names/descriptions now reject Arabic/full-width numeric literals outside `{amount_ref:...}` or `{effect_percent_delta:...}`.
- Relic descriptions now reject Arabic/full-width numeric literals outside `{relic_numeric_ref:...}`, `{relic_numeric_signed:...}`, or `{relic_numeric_percent:...}`.
- The first pass intentionally does not reject Chinese quantity words such as "一个" to avoid false positives in natural language copy.

### Runtime reward/gem source lookups had permissive fallbacks

- Phase 17 removed the global-pool fallback from `DataRegistry.get_gem_pool_def()` for unknown gem sources.
- Phase 17 removed the common-only fallback from `DataRegistry.get_relic_source_weights()` for unknown relic sources.
- Unknown gem sources now produce empty spawnable candidates and empty gem offer slots.
- Unknown relic sources now produce empty relic pools and placeholder relic offers.
- `balance_config_test` covers the strict runtime behavior for missing gem and relic sources.

### Authored reward/shop source references could point at missing pools

- Phase 16 added optional known-source validation to `AdventureConfigValidator.validate_reward_offer_config()` and `validate_shop_pools()`.
- `DataRegistry` now exposes gem/relic source ids and performs cross-config validation after loading gem pools and relic source weights.
- Battle reward `relic_source` values must exist in `resources/adventure/relic_source_weights.json`.
- Shop `gem_source` values must exist in `resources/gems/gem_pools.json`, and shop `relic_source` values must exist in `resources/adventure/relic_source_weights.json`.
- `balance_config_test` now rejects unknown reward and shop source ids.

### Non-shop battle reward offer counts needed a single config authority

- Phase 15 added `resources/adventure/reward_offer_config.json` as the authored source for battle reward relic sources and offer counts.
- `BattleScene` now asks `DataRegistry` for battle reward source/count instead of owning a room-type source map or passing a fixed `3`.
- `AdventureConfigValidator.validate_reward_offer_config()` validates configured battle reward entries.
- `RunService.get_or_roll_relic_offer()` and `RunService.get_or_roll_gem_offer()` no longer provide a hidden `count = 3` default, so future call sites must pass an explicit configured count.
- Phase 18 removed `DataRegistry`'s defensive `normal_chest` / `3` fallback for missing battle reward config; the authored `default` entry is now required.

### Shop offer count had conflicting/obsolete config authority

- Phase 14 removed the unused `shop_offer_count` from `resources/adventure/economy_config.json`.
- `resources/adventure/shop_pools.json` is now the only authored source for shop gem/relic offer counts.
- `RoomFlowService` no longer pre-rolls a hard-coded 3 gem shop offer; `ShopService` owns shop offer generation.
- `AdventureConfigValidator.validate_shop_pools()` now validates integer, non-negative offer counts, non-empty source ids, and non-empty total offers.

### Adventure rule validator allowed unhandled numeric modifiers

- Phase 14 tightened `AdventureConfigValidator.MODIFIER_IDS` to match the modifiers handled by `AdventureRuleRegistry.query_modifier()`.
- The previously allowed `shop_offer_count_bonus`, `event_reward_mult`, and `battle_reward_option_bonus` are no longer accepted without runtime semantics.
- `adventure_rule_registry_test` now verifies that an unhandled modifier is rejected.
- `docs/game-completion-engineering-spec.md` now lists those ids as future candidates rather than active first-batch modifiers.

### Painkiller damage cap was hard-coded behind a boolean relic modifier

- Phase 13 added `relic_painkiller_damage_cap` to `resources/relics/relic_numeric_refs.json`.
- `relic_painkiller` now exposes `first_damage_cap` with a `value_ref`, and its description renders the same ref through a relic numeric token.
- `CombatRules.apply_damage()` now queries `first_damage_cap` instead of hard-coding `incoming = 1`.
- `BalanceConfigValidator` validates `first_damage_cap` as `flat/damage`, and `status_test` covers the first-hit-only runtime path.

### Relic descriptions could drift from numeric refs

- Phase 12 moved current ref-backed relic description numbers to text tokens resolved from `resources/relics/relic_numeric_refs.json`.
- `DataRegistry` renders relic descriptions during load, and `BalanceConfigValidator` rejects unknown relic numeric tokens.
- `balance_config_test` covers rendered description output and invalid token rejection.
- Phase 13 removed the remaining known exception, `relic_painkiller`, by adding a numeric ref for its first-damage cap.

### Relic weight rules used raw numeric values

- Phase 11 moved relic selection-weight thresholds and multipliers into `resources/relics/relic_numeric_refs.json`.
- `weight_rules` now use `value_ref` for numeric thresholds and `multiplier_ref` for selection-weight multipliers.
- `DataRegistry.compute_relic_weight()` resolves those refs at runtime.
- `BalanceConfigValidator` rejects inline authored weight thresholds and multipliers when refs are available.
- Remaining relic drift risk is now player-facing description text, tracked separately.

### Relic action amounts used raw effect fields

- Phase 09 moved current relic action amounts into `resources/relics/relic_numeric_refs.json`.
- `DataRegistry` loads and validates those refs before validating `relic_defs`.
- `RelicEffectRegistry` now resolves `amount_ref` through `DataRegistry`, while keeping inline `amount` compatibility for direct runtime/test calls.
- Remaining relic numeric fields were tracked separately and further reduced in Phase 10.

### Relic modifier and ratio fields used raw numeric values

- Phase 10 moved current relic modifier values, max-HP reduction ratio, and per-empty-slot formula inputs into `resources/relics/relic_numeric_refs.json`.
- `RelicEffectRegistry` now resolves `value_ref`, `ratio_ref`, and `per_empty_slot_ref` through the same numeric-ref path.
- `BalanceConfigValidator` rejects inline authored values for those fields and checks expected `kind/unit`.
- During this pass, `attack_miss_chance` was found to be truncated by integer additive modifier aggregation; it now aggregates as a float.
- Remaining relic selection-balance numbers are tracked separately as raw weight-rule values.

### Typed amount-ref compatibility was not enforced by action type

- Phase 07 added validator checks that bind typed refs to their use sites: resource actions and gates require flat resource units, direct HP effects require flat HP, and percent healing requires a max-HP ratio.
- Regression coverage now rejects representative wrong-kind and wrong-unit authored data.
- Remaining raw amount readers outside the adventure config path are tracked separately.

### Inline authored adventure amounts could bypass unit metadata

- Phase 08 tightened `AdventureConfigValidator` so authored event/room numeric payloads must use `amount_ref` when an amount-ref catalog is available.
- Runtime inline amounts are still allowed for service-internal hydrated values, but content data now goes through named typed refs.
- Remaining raw amount readers outside adventure config are tracked separately.
