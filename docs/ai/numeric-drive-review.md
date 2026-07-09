# Numeric Drive Review

## 2026-07-07 / Phase 01

Scope reviewed:

- combat config, status config, AI profile config, gem effect level config
- unit balance config for patrol guard, stone bow guard, fission slime
- current overload numeric flow

What is in a good place:

- A real config -> validator -> test -> verify chain now exists for multiple balance layers.
- Stone bow guard's utility scoring is no longer trapped in code constants; its behavior weights now live in `unit_defs.balance`.
- Patrol guard already uses unit balance values for its main semantic knobs (`rampage_move_bonus`, `charge_bonus`, `charge_min_steps`).

What still needed correction before calling the numeric-drive work "complete":

- `OverloadRules.ai_control_probability()` still used a hard-coded formula before this phase's follow-up change.
- Semantic contract coverage is still only 38 / 90, so many configurable gem semantics are not yet protected by executable design contracts.
- Some tests still encode old constants directly instead of reading the balance surface they are meant to verify.

Direction check:

- Continue moving formulas into named config fields rather than only extracting isolated constants.
- Prefer existing config surfaces (`combat_config`, `unit_defs.balance`, `status_config`, `ai_profiles`) over inventing a new one unless the domain truly needs its own schema.
- Treat every new balance field as incomplete until validator coverage and at least one focused test are added.

## 2026-07-07 / Phase 02

Scope reviewed:

- overload backlash and AI-control probability flow
- review hygiene: issue logging and phase review artifacts

What improved in this phase:

- `OverloadRules.ai_control_probability()` now reads its clamp, baseline, penalty, and max-probability values from `combat_config`.
- `balance_config_test` now covers the new overload fields and validates type safety for the new combat-config surface.
- Overload tests were partially decoupled from fixed constants by reading `CombatConfig` for operation backlash damage.

Review judgment:

- Direction is still good. We are externalizing behavior formulas into existing balance surfaces rather than scattering new ad hoc config files.
- The next phase should target semantic coverage and the remaining hard-coded reward/growth formulas, not another round of tiny constant extraction.

## 2026-07-07 / Phase 03

Scope reviewed:

- event/economy numeric references
- config validation versus runtime resolution
- verify coverage for adventure-side numeric tests

What improved in this phase:

- `economy_config.amount_refs` is now part of the validated balance surface rather than a loose JSON convention.
- Event definitions can reference shared numeric values through `amount_ref`, and `RoomEffectExecutor` resolves those refs at runtime for both effects and resource-gate conditions.
- `economy_service_test`, `room_effect_executor_test`, and `event_service_test` now help cover the adventure-side numeric path, and `tools/verify` runs the first two classes of checks more often.
- The adventure-side numeric chain has fresh execution evidence from targeted tests plus a manual equivalent run of the current fast suite.

Review judgment:

- Direction remains healthy: this phase moved from "constants extracted into data" to "data is actually the execution authority".
- One important gap remains outside pure mechanics: player-facing event copy is still free to duplicate numeric values by hand, so behavior and text can drift unless we add a templating/localization layer later.
- Verification ergonomics are weaker than they should be on Windows because the wrapper scripts are currently less reliable than the native Godot test entrypoint.

## 2026-07-07 / Phase 04

Scope reviewed:

- player-facing numeric copy for events and map rules
- validator coverage for text tokens
- changed-file verification routing for adventure-side services/resources

What improved in this phase:

- Event and map-rule copy can now render numeric placeholders from the same data that drives behavior, through `NumericTextResolver`.
- Debug event labels/body text no longer duplicate the toll, heal, and gold amounts by hand; they use `amount_ref` tokens backed by `economy_config.amount_refs`.
- Map rule descriptions now render percent deltas from their actual modifier values, instead of spelling out `+10%`, `-20%`, or `+50%` separately from the effect payload.
- `AdventureConfigValidator` now validates text tokens for known amount refs and known rule effect ids.
- `tools/verify changed` now routes adventure resource/service changes through the broader fast suite, including `adventure_rule_registry_test` and `shop_service_test`.

Review judgment:

- Direction is good: the work is moving from numeric data driving only mechanics toward numeric data also driving player-visible choice text.
- This is still intentionally lightweight. It is not a full localization system, but it removes the most dangerous current drift pattern while preserving the existing JSON authoring style.
- Remaining risk: any new plain text that embeds numbers without tokens can still drift, so a future localization/schema pass should make numeric placeholders a stronger convention.

## 2026-07-07 / Phase 05

Scope reviewed:

- REST_SITE heal ratio source
- shared numeric reference resolution
- validation of unknown `amount_ref` usage

What improved in this phase:

- `REST_SITE` no longer hard-codes its `0.2` heal ratio directly in `room_defs`; it now references `rest_site_heal_ratio` from `economy_config.amount_refs`.
- `EconomyService.resolve_numeric_field()` is now the shared runtime path for inline `amount` and referenced `amount_ref` values.
- `RoomEffectExecutor` and `RoomFlowService` both use the same resolver, so rest healing and event effects no longer maintain separate amount-ref logic.
- `AdventureConfigValidator` now rejects unknown `amount_ref` values when a reference catalog is available.
- `room_flow_service_test` and `full_run_contract_test` now assert that rest healing starts from the configured base ratio before modifiers are applied.

Review judgment:

- Direction remains aligned: we are removing isolated numeric literals from room behavior and folding them into the same config -> validator -> runtime -> test chain.
- The shared resolver is a better shape than copying amount-ref parsing into each service.
- New concern: `amount_refs` is now carrying both absolute quantities and ratios. It works mechanically, but future schema design should make units/types more explicit.

## 2026-07-07 / Phase 06

Scope reviewed:

- amount reference schema clarity
- compatibility between legacy numeric refs and typed refs
- text rendering and config validation after typed-ref migration

What improved in this phase:

- `economy_config.amount_refs` now uses typed object refs for current data: each ref carries `value`, `kind`, and `unit`.
- `EconomyService.get_amount_ref()` still accepts legacy numeric refs, while `get_amount_ref_def()` exposes metadata for typed refs.
- `NumericTextResolver` can render both legacy numeric refs and typed object refs, so event copy stays tied to the same numeric source.
- `AdventureConfigValidator` now validates typed amount refs and requires `value`, `kind`, and `unit` for object refs.
- Tests now assert that `rest_site_heal_ratio` is a ratio with `max_hp` unit metadata, not just a raw `0.2`.

Review judgment:

- This is a meaningful schema-quality improvement: references are no longer just an untyped bag of numbers.
- Backward compatibility is preserved, which keeps the migration path sane while allowing current authored data to be more explicit.
- Remaining risk: the validator checks that `kind` and `unit` exist, but it does not yet enforce action-specific unit compatibility such as preventing a `max_hp` ratio from being used as a gold cost.

## 2026-07-08 / Phase 07

Scope reviewed:

- action-specific `amount_ref` compatibility
- resource-gate condition validation
- validator error quality for malformed authored data

What improved in this phase:

- `AdventureConfigValidator` now binds typed amount refs to their use site:
  - resource grants/costs and `resource_gte` require `flat/<resource_id>`
  - direct heal/damage effects require `flat/hp`
  - percent heal effects require `ratio/max_hp`
- Resource effects and resource-gate conditions now report a missing `resource_id` explicitly.
- Legacy numeric refs still pass compatibility checks as a migration path, while current typed refs get stricter validation.
- `room_effect_executor_test` now covers wrong-kind and wrong-unit examples, including using a rest-heal ratio as a gold cost and using a flat HP ref as a percent heal.

Review judgment:

- Direction is still aligned: the numeric surface is not only easier to edit, it is harder to wire into the wrong semantic slot.
- This is higher-value than another round of constant extraction because it prevents whole classes of authoring mistakes before runtime.
- Remaining risk: inline `amount` literals are still intentionally accepted and therefore do not carry unit metadata. That keeps compatibility easy, but authored content can still bypass the typed-ref safety net.

## 2026-07-08 / Phase 08

Scope reviewed:

- authored adventure event/room numeric payloads
- validator strictness for inline `amount`
- remaining raw amount readers outside the adventure config path

What improved in this phase:

- Current authored adventure config already uses `amount_ref` for numeric room/event effects and conditions.
- `AdventureConfigValidator` now rejects inline `amount` fields when an amount-ref catalog is supplied, so future authored event/room data cannot silently bypass typed refs.
- `RoomEffectExecutor` still supports inline `amount` at runtime, preserving service-internal hydrated values such as modified rest healing after rule multipliers are applied.
- `room_effect_executor_test` now covers authored inline amount rejection.

Review judgment:

- This is the right boundary: authored data is strict, runtime plumbing remains flexible.
- The adventure-side amount-ref path now has a clearer contract: content authors edit named typed refs, not anonymous numbers hidden inside effects.
- Remaining risk has moved outside this subsystem: relic effect registration still reads raw `amount` values directly, so the next high-value pass should bring relic numeric effects under a comparable config/validator/test chain.

## 2026-07-08 / Phase 09

Scope reviewed:

- relic action amount payloads
- `DataRegistry` relic amount-ref loading
- relic definition validation and runtime amount resolution

What improved in this phase:

- Added `resources/relics/relic_numeric_refs.json` as the typed numeric surface for relic action amounts.
- Migrated current relic action amounts from inline `amount` to named `amount_ref` entries:
  - autopsy-log heal
  - cracked-amulet shield
  - pressure-valve temporary move
  - reinforced-base shield
- `DataRegistry` now loads, validates, and exposes relic amount refs before relic definitions are validated.
- `RelicEffectRegistry` resolves `amount_ref` at runtime while keeping inline `amount` compatibility for direct/test calls.
- `BalanceConfigValidator` now validates relic amount-ref schema and rejects authored inline amount fields when a ref catalog is available.
- `balance_config_test` and `status_test` cover the new validator and runtime shield path.

Review judgment:

- This removes the specific raw `effect.get("amount", 1)` debt from relic action amounts and gives designers one named place to tune these values.
- The design is intentionally parallel to the adventure amount-ref path, which keeps authoring concepts consistent across systems.
- Remaining risk: relic modifier values, ratio fields, and per-slot formulas still use raw fields such as `value`, `ratio`, and `per_empty_slot`. Those should be pulled into the same typed-ref/validator style in a later pass.

## 2026-07-08 / Phase 10

Scope reviewed:

- relic modifier values
- relic ratio and per-empty-slot formula inputs
- verify routing for relic resource changes

What improved in this phase:

- `resources/relics/relic_numeric_refs.json` is now the shared typed numeric surface for relic action amounts, modifier values, ratios, and per-slot formula inputs.
- Current relic effect numeric fields moved from inline authored values to refs:
  - `value_ref` for numeric modifier values
  - `ratio_ref` for max-HP reduction
  - `per_empty_slot_ref` for empty-slot range bonuses
- `RelicEffectRegistry` now resolves those refs through one `_resolve_number()` path.
- `BalanceConfigValidator` now validates expected `kind/unit` per relic field and rejects inline authored numeric values when refs are available.
- `attack_miss_chance` now aggregates as a float instead of being truncated through the integer additive modifier path.
- `tools/verify changed` now routes `resources/relics/` changes through the fast suite.

Review judgment:

- This materially improves editability: most active relic effect numbers now live in one named, typed file rather than inside effect payloads.
- The validator is doing useful semantic work, not just type checking; it catches using a damage ref as a chance, a shield ref as max-HP ratio, or an inline value where a ref is required.
- Remaining risk: relic `weight_rules` still use raw thresholds and multipliers in `relic_defs`. Those are selection-balance numbers rather than effect execution numbers, but they should get their own typed config surface.

## 2026-07-08 / Phase 11

Scope reviewed:

- relic `weight_rules`
- relic selection-weight thresholds and multipliers
- runtime `compute_relic_weight()` path

What improved in this phase:

- Relic selection numbers now use the same typed numeric-ref surface as relic effects.
- `weight_rules` now use:
  - `value_ref` for numeric thresholds such as slot-count requirements
  - `multiplier_ref` for selection-weight multipliers
- String match values such as `gem_split`, `black`, and `relic_copper_wire` stay inline because they are ids, not numeric balance values.
- `DataRegistry.compute_relic_weight()` resolves ref-backed thresholds and multipliers at runtime.
- `BalanceConfigValidator` now validates weight-rule ref usage, including wrong threshold units and inline multiplier drift.
- `balance_config_test` covers validator failures and runtime weight computation through refs.

Review judgment:

- The relic side now has a much more coherent authoring model: effect numbers and selection-weight numbers are edited through named typed refs.
- Keeping string ids inline is the right boundary; pushing ids into numeric refs would make the data less legible without improving balance editability.
- Remaining risk has moved upward: player-facing relic descriptions still spell out numbers by hand, so text can drift from `relic_numeric_refs`.

## 2026-07-08 / Phase 12

Scope reviewed:

- player-facing relic description numbers
- relic text token validation
- `DataRegistry.get_relic_def()` description hydration path

What improved in this phase:

- Relic descriptions can now render numeric placeholders from `resources/relics/relic_numeric_refs.json`.
- Current relic descriptions that reference tunable effect/weight numbers now use `{relic_numeric_ref:...}`, `{relic_numeric_signed:...}`, or `{relic_numeric_percent:...}` tokens instead of duplicating values by hand.
- `BalanceConfigValidator.validate_relic_defs()` now validates relic description tokens and rejects unknown numeric refs.
- `DataRegistry` renders relic descriptions at load time, so existing UI call sites can keep reading `desc` without learning token semantics.
- `get_relic_def()` now returns a duplicate, reducing accidental mutation of the loaded definition cache.
- `balance_config_test` covers rendered description output and invalid description-token rejection.

Review judgment:

- This closes the main behavior/text drift loop for current ref-backed relic numbers: designers tune the numeric ref and both mechanics and visible description follow it.
- Keeping the resolver in `DataRegistry` is the right boundary for now because relic definitions are already consumed as hydrated data by UI and shop flows.
- New issue exposed: `relic_painkiller` still describes a numeric damage cap, but the behavior is currently represented as a boolean `first_damage_absorb` modifier and hard-coded to cap incoming damage at 1 in `CombatRules.apply_damage()`.

## 2026-07-08 / Phase 13

Scope reviewed:

- `relic_painkiller` first-damage cap behavior
- relic numeric refs for damage-cap modifiers
- runtime damage application path in `CombatRules.apply_damage()`

What improved in this phase:

- Added `relic_painkiller_damage_cap` to `resources/relics/relic_numeric_refs.json`.
- `relic_painkiller` now uses the same numeric token system for its description and exposes a `first_damage_cap` modifier backed by that ref.
- `CombatRules.apply_damage()` no longer hard-codes `incoming = 1`; it queries `first_damage_cap` and applies it as an upper bound.
- `BalanceConfigValidator` now validates `first_damage_cap` as `flat/damage`, so shield or chance refs cannot be wired into that slot.
- `status_test` now verifies that painkiller caps only the first incoming damage event and that the cap is driven through relic numeric refs.

Review judgment:

- Splitting `first_damage_absorb` from `first_damage_cap` is cleaner than changing the existing boolean modifier into a number; the former answers "can it trigger?" and the latter answers "what number does it use?"
- The cap is applied with `min(incoming, cap)`, preserving cap semantics even if future tuning raises the value above small incoming hits.
- This removes the last known raw numeric value from current relic descriptions and brings the corresponding behavior under the same typed-ref chain.

## 2026-07-09 / Phase 14

Scope reviewed:

- shop offer counts and shop-pool config authority
- adventure map-rule modifier allow-list
- old shop room resolution path

What improved in this phase:

- Removed obsolete `shop_offer_count` from `resources/adventure/economy_config.json`; shop item counts now live only in `resources/adventure/shop_pools.json`.
- `AdventureConfigValidator.validate_shop_pools()` now validates shop offer counts as integer, non-negative values and requires non-empty source ids.
- The validator also rejects a shop pool that would offer zero total items.
- `RoomFlowService` no longer pre-rolls `RunService.get_or_roll_gem_offer(room_id, "shop", 3)` in the resolved SHOP branch; shop offers are generated by `ShopService` from `shop_pools.json`.
- `AdventureConfigValidator.MODIFIER_IDS` now only allows modifiers that `AdventureRuleRegistry.query_modifier()` actually handles: `gold_gain_mult`, `shop_price_mult`, and `rest_heal_mult`.
- Tests cover valid/invalid shop pool config and reject the previously allowed-but-unhandled `shop_offer_count_bonus` modifier.
- `docs/game-completion-engineering-spec.md` was updated so the engineering spec no longer presents unimplemented modifiers or obsolete `shop_offer_count` as active config.

Review judgment:

- This phase reduces config authority drift rather than adding another knob: designers now have one place to edit shop offer composition.
- Tightening the modifier allow-list is important for numeric-drive quality because a "valid" number that runtime ignores is worse than a missing feature.
- Remaining broader risk: reward/offer counts outside shop flows still need a fuller pass, especially battle reward option counts and relic offer counts requested from UI call sites.

## 2026-07-09 / Phase 15

Scope reviewed:

- non-shop battle reward relic offer counts
- battle reward relic source selection
- `RunService` offer API defaults

What improved in this phase:

- Added `resources/adventure/reward_offer_config.json` as the authored config for battle reward relic sources and offer counts.
- `DataRegistry` now loads, validates, and exposes battle reward offer config by room type.
- `BattleScene` no longer owns `_ENCOUNTER_RELIC_SOURCE` or passes fixed `3` counts into battle reward relic offers.
- `AdventureConfigValidator.validate_reward_offer_config()` validates non-empty relic sources and integer, non-negative offer counts.
- `balance_config_test` covers valid reward config, room-type lookup, default fallback lookup, and invalid reward config.
- `RunService.get_or_roll_relic_offer()` and `RunService.get_or_roll_gem_offer()` no longer have hidden `count = 3` defaults, forcing call sites to pass an explicit count.
- `docs/game-completion-engineering-spec.md` now lists the battle reward offer config surface.

Review judgment:

- This closes the current non-shop battle reward count drift: designers can tune battle relic offer count and source in one JSON file instead of editing UI code.
- Moving the room-type source map out of `BattleScene` is the right ownership boundary; UI now presents the reward and services/config decide what the reward is.
- Removing `RunService` count defaults is a useful guardrail because future reward flows cannot accidentally inherit the old hard-coded count.
- Remaining risk: `DataRegistry` still has a defensive fallback if the reward config is missing, so validation must remain part of normal startup/test coverage rather than relying on fallback behavior as an authoring path.

## 2026-07-09 / Phase 16

Scope reviewed:

- battle reward `relic_source` references
- shop `gem_source` / `relic_source` references
- source-id ownership between reward config, gem pools, and relic source weights

What improved in this phase:

- `AdventureConfigValidator.validate_reward_offer_config()` can now validate battle reward relic sources against a known relic-source set.
- `AdventureConfigValidator.validate_shop_pools()` can now validate shop gem and relic sources against known gem/relic source sets.
- `DataRegistry` now exposes `get_gem_pool_source_ids()` and `get_relic_source_ids()`.
- `DataRegistry` performs cross-config validation for `resources/adventure/shop_pools.json` after gem pools and relic source weights are loaded.
- `DataRegistry` validates `resources/adventure/reward_offer_config.json` against loaded relic source ids.
- `balance_config_test` now verifies source ids are loaded and rejects unknown shop/reward source references.

Review judgment:

- This is a high-leverage data-driven guardrail: a mistyped reward source now fails validation instead of silently changing rarity behavior.
- Keeping cross-config validation in `DataRegistry` is the right boundary because `ShopService` loads before `DataRegistry` in autoload order and should not depend on registry state during its own `_ready()`.
- Remaining risk: runtime lookup methods still have permissive fallbacks for unknown source ids, so authored configs are protected but arbitrary future runtime call sites can still bypass strictness.

## 2026-07-09 / Phase 17

Scope reviewed:

- runtime gem pool lookup fallback
- runtime relic source weight fallback
- offer generation behavior for unknown source ids

What improved in this phase:

- `DataRegistry.get_gem_pool_def()` now returns an empty dictionary for unknown gem sources instead of falling back to `global`.
- `DataRegistry.get_relic_source_weights()` now returns an empty dictionary for unknown relic sources instead of falling back to `{"common": 100.0}`.
- Added `has_gem_pool_source()` and `has_relic_source()` helper APIs for explicit source checks.
- `get_spawnable_gem_ids_for_source()` and `roll_spawnable_gem_id()` now return empty results for unknown gem sources.
- `get_relic_pool()` and `roll_relic_for_source()` now return empty results for unknown relic sources.
- `roll_gem_offer()` now returns empty offer slots for unknown gem sources instead of accidentally drawing from a default pool.
- `balance_config_test` covers unknown gem and relic source runtime behavior.

Review judgment:

- This closes the gap left by Phase 16: source typos are no longer hidden either by authored config validation or by lower-level runtime fallbacks.
- Returning empty/placeholder reward results is preferable to substituting another pool because it preserves the existing UI failure shape while making the data problem visible to tests and QA.
- The change intentionally keeps the public debug query path usable: unknown sources produce no candidates rather than causing a hard crash.

## 2026-07-09 / Phase 18

Scope reviewed:

- battle reward config loading
- battle reward default entry semantics
- `DataRegistry` battle reward source/count helpers

What improved in this phase:

- `resources/adventure/reward_offer_config.json` is now required when loading battle reward offer config.
- `DataRegistry._load_reward_offer_config_from_json()` no longer fabricates a `normal_chest` / `3` fallback when the file is missing or unreadable.
- `DataRegistry.get_battle_reward_offer_config()` no longer fabricates a reward entry if loaded config is empty.
- `get_battle_relic_offer_source()` and `get_battle_relic_offer_count()` no longer carry their own `normal_chest` / `3` defaults.
- `balance_config_test` verifies that an authored `battle_rewards.default` entry is required, while unknown room types still use the configured default.

Review judgment:

- This makes the battle reward offer config a real authority instead of a best-effort override over code defaults.
- Keeping the room-type fallback to the authored `default` entry is still useful: it supports future room types without reintroducing hidden numeric values.
- The failure mode is now cleaner for data work: missing config fails validation, while incomplete room-specific coverage falls back only to explicitly authored data.

## 2026-07-09 / Phase 19

Scope reviewed:

- authored adventure event player copy
- authored map-rule player copy
- authored relic descriptions
- numeric text token validation

What improved in this phase:

- `NumericTextResolver` now exposes `strip_tokens()` and `has_literal_number_outside_tokens()` so validators can distinguish token ids from visible copy.
- `AdventureConfigValidator` rejects Arabic/full-width numeric literals in event titles, event bodies, option labels, map-rule names, and map-rule descriptions.
- `BalanceConfigValidator` rejects Arabic/full-width numeric literals in relic descriptions.
- Numeric tokens such as `{amount_ref:event_1_gold}` remain valid even when the token id contains a digit.
- `balance_config_test` covers valid tokenized copy and invalid literal-number copy for events, map rules, and relic descriptions.

Review judgment:

- This turns a style rule into an executable data contract: future visible numbers in these config-backed text surfaces must come from the same numeric refs as behavior.
- Limiting the first check to Arabic/full-width digits is intentional. It catches the highest-risk drift pattern without rejecting natural Chinese copy such as "一个" or "一种".
- Remaining risk: other player-facing text surfaces outside these authored config files can still embed numbers manually and should be audited separately.

## 2026-07-09 / Phase 20

Scope reviewed:

- normal save-slot summary copy
- internal seed/coordinate leakage in player UI
- code-authored numeric player copy outside JSON configs

What improved in this phase:

- `SaveService._build_slot_summary()` no longer reads `current_map_pos` to build the normal active-run subtitle.
- Active run slots no longer show `map_seed` or map coordinates.
- Active run slots now show player-facing progress: current chapter and owned relic count.
- `run_save_corruption_recovery_test` verifies that active slot summaries do not contain seed or coordinate text and do contain player-facing progress.
- A separate open issue records that `adventure_map_scene.gd` still displays `调试种子 %d`, which appears debug-facing and needs a boundary audit.

Review judgment:

- This removes a concrete normal-UI leak called out by the working agreement: seed and coordinate details belong behind debug/editor UI, not in the save selector.
- The replacement copy still uses dynamic numbers, but they describe player-facing progress rather than hidden deterministic state.
- `./tools/verify changed` passed. `./tools/verify all` also proved the new run-save assertion, but exposed unrelated overlay/water visual contract failures that are now tracked separately.
