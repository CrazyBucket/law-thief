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

## 2026-07-10 / Phase 21

Scope reviewed:

- semantic validation for `resources/gems/gem_effect_levels.json`
- malformed numeric data as an authoring failure mode
- runtime/player-copy boundaries exposed by the gem-level audit

What improved in this phase:

- `BalanceConfigValidator.validate_gem_effect_levels()` now checks known slot and tag ids in addition to field names and primitive types.
- Enumerated effect shapes are constrained to supported values (`cross`/`square`, `single`/`cross`).
- Discrete counts and radii must be non-negative integers; chances and ratios must remain in `[0, 1]`; multipliers and visual dimensions must stay positive.
- Split direction offsets must be non-empty and unique, preventing duplicate projectiles created solely by malformed data.
- `balance_config_test` verifies each validation class with deliberately malformed authoring data.

Review judgment:

- This is the correct responsibility boundary for a data-driven combat system: runtime behavior may remain procedural, but authored numeric data must fail early when it cannot describe a meaningful legal state.
- The constraints are deliberately field-semantic rather than tag-specific behavior rules, so adding a new gem mechanic still requires an explicit schema change instead of silently accepting arbitrary numbers.
- The audit uncovered a larger unresolved problem: `battle_hud_presenter.gd` shows slot-agnostic `gem.level.{tag}.{level}` localization strings containing hard-coded numbers. The current split Lv2/Lv3 strings disagree with configured ratios. This is recorded as an open issue and should be the next player-facing numeric-drive phase.

## 2026-07-10 / Phase 22

Scope reviewed:

- battle HUD gem-level tooltip copy
- slot-specific gem effect level config
- localization template ownership for player-visible numbers

What improved in this phase:

- Added `DataRegistry.get_gem_effect_level_summary(tag, slot_type, level)`, which selects the effective configured level and formats its values for localized display.
- Added slot-scoped localization templates such as `gem.level.red.split`; templates contain semantic text and placeholders, while ratios, counts, patterns, and booleans are resolved from the current JSON definition.
- `BattleHudPresenter` now uses the summary API whenever it has battle state. It no longer renders the old tag-only `gem.level.{tag}.{level}` strings or the generic baseline description alongside it.
- Removed the old tag-only numeric localization keys, including the split Lv2/Lv3 70% strings that contradicted the active 50%/30% config.
- `gem_level_context_test` exercises the registry and the presenter itself, proving the visible red split values follow the configured level definitions.

Review judgment:

- Giving the registry ownership of parameter formatting keeps the UI thin: the presenter asks for player-ready copy and does not need to understand every gem field.
- Slot-scoped templates are the necessary minimum for correctness because the same tag has different red/blue/black mechanics. Keeping one template per slot/tag is a much smaller and safer text surface than duplicating every level's numbers.
- The remaining design debt is explicit: `BattleQueryService` still uses context-free generic descriptions for previews. It should move to a context-aware summary path instead of inheriting the HUD implementation ad hoc.
- Verification also showed that the current `verify` command does not force CSV translation reimport; this toolchain gap is recorded separately rather than treating the first stale-resource failure as a product failure.

## 2026-07-10 / Phase 23

Scope reviewed:

- battle cell and death-preview gem copy
- reuse of the slot-scoped HUD summary in a non-HUD presentation layer

What improved in this phase:

- `BattleQueryService` now derives a tag context from the actual state owner and slot before producing preview text.
- Its unit, tile, and black-death preview paths all use the same `DataRegistry` level-summary API as the HUD.
- The generic effect-description API remains only as a fallback when an effect has no authored level definition.
- `gem_level_context_test` proves query text for red split Lv2 exposes the configured 50% ratio rather than stale 70% copy.

Review judgment:

- This keeps the ownership clean: query code supplies context, the registry renders configured values, and neither presentation layer recreates gem-specific numeric text.
- A fallback remains appropriate for intentionally configuration-free mechanics, but it is no longer the normal path for level-driven gems.

## 2026-07-10 / Phase 24

Scope reviewed:

- echo tag-selection count by level
- red/blue/black echo config completeness
- runtime selection and description consistency

What improved in this phase:

- Added `echo_tag_count` to each authored echo level: 1 at Lv1 and 2 at Lv2/Lv3 for every slot scope.
- Red echo now has explicit Lv1/Lv2 config entries with a zero follow-up ratio, rather than relying on the absence of a definition to imply no extra damage.
- `GemEchoRules.resolve_echo_tags()` reads `echo_tag_count` from the scope-specific level definition and returns no picks if the required data is absent.
- Validator rules now recognize and require a positive integer echo count.
- `gem_echo_test` directly verifies all red echo levels select exactly their configured count.

Review judgment:

- This is a meaningful numerical ownership improvement, not a cosmetic JSON migration: the number of copied effects changes combat output and now has a single editable authority.
- Treating missing echo count as no selection is intentionally strict. Authored data must fail validation during normal load; the runtime guard prevents an accidental fallback from changing combat behavior silently.

## 2026-07-10 / Phase 25

Scope reviewed:

- blue explosion trigger shape by level
- black explosion death/chain behavior by level
- executable gem semantic-contract coverage

What improved in this phase:

- Added blue explosion contract cases for Lv1's non-detonating normal hit and burning detonation, Lv2's any-damage cross blast, and Lv3's any-damage 3x3 blast.
- Added black explosion contract cases for the base death blast, Lv2's follow-up chain after an explosion kill, and Lv3's doubled main blast with the chain still using base damage.
- The new blue Lv2 contract exposed that both blue trigger paths ignored `blast_pattern: cross` and always used the square explosion helper.
- Added `_append_blue_explosion_by_pattern()` and routed both the damaged hook and forced-displacement hook through it.
- Semantic-contract coverage increased from `38 / 90` to `44 / 90`.

Review judgment:

- The helper removes a particularly dangerous form of data-drive drift: the config field existed, passed validation, and even appeared in authored level data, but did not control runtime behavior.
- Keeping the two trigger sources behind one helper prevents the same shape regression from reappearing only on forced movement.
- Black explosion contracts deliberately position units away from board-edge collision outcomes, so they prove explosion/chain semantics rather than incidental knockback collision damage.

## 2026-07-10 / Phase 26

Scope reviewed:

- black gravity pull, slow, and root progression by level
- semantic-contract coverage for black-slot death effects
- blue gravity's conflicting trigger models

What improved in this phase:

- Added one executable contract per black gravity level, covering the configured one-tile pull, Lv2 slow, and Lv3 root.
- Each case kills a mounted enemy through normal combat and asserts the nearby unit's final board position and resulting status state.
- Semantic-contract coverage increased from `44 / 90` to `47 / 90`.
- The audit found that blue gravity has two incompatible runtime interpretations: pre-hit projectile deflection follows the detailed design, while a separate damaged hook redirects damage and applies slow/root.
- The conflict is recorded in `docs/ai/semantic-conflicts.md`; no blue gravity behavior or contract was added under an unapproved interpretation.

Review judgment:

- Black gravity now has a useful numeric-drive boundary: `pull_steps`, `slow_on_pull`, and `root_on_pull` are authored fields whose level progression is validated through actual battle outcomes.
- The root assertion intentionally expects one turn, matching the implementation and the detailed design's "add one root" language; the first failing draft expected two, which was a test-fixture error rather than a runtime bug.
- Pausing blue gravity is the correct engineering decision. A contract would otherwise give false authority to one of the competing mechanics and make later product correction more expensive.

## 2026-07-10 / Phase 27

Scope reviewed:

- blue conductive rebound probability progression
- black conductive death-strike target progression
- ownership of arc damage values across conductive paths

What improved in this phase:

- Added fixed-seed contracts for blue conductive: Lv1 can miss its rebound roll, Lv2 can rebound, and Lv3 always rebounds.
- Added black conductive contracts for one random strike, two unique strikes, and the Lv3 all-target strike in the death radius.
- The black cases assert actual true damage and `lightning` events after a normal combat kill.
- Semantic-contract coverage increased from `47 / 90` to `53 / 90`.
- The audit found that `arc_hit_damage` is not consumed by the gem paths: red derives damage from the attack and a ratio, blue uses owner attack damage, and black uses `lightning_death_damage`.

Review judgment:

- The level fields are now meaningfully executable: blue `rebound_chance` controls a seeded chance roll, while black `strike_count` and `strike_all_targets` control target cardinality and selection behavior.
- The blue tests deliberately use deterministic trigger and non-trigger seeds. They prove the gameplay branches without pretending that two samples statistically validate a probability distribution; the configured interval and type remain protected by the balance validator.
- Damage consolidation must wait for numeric/product intent. Rewiring all conductive effects to `arc_hit_damage` would be a behavioral change with no design authority, so the unused configuration and divergent damage sources are recorded rather than silently normalized.

## 2026-07-10 / Phase 28

Scope reviewed:

- blue fire contact, created-overlay, doubling, and once-per-turn semantics
- black fire death radius, target priority, count, and duration progression
- ownership and validation of black-fire numeric values
- reliability of per-case semantic-contract reporting

What improved in this phase:

- Added four blue-fire and three black-fire executable cases. They cover all six design rows, including the blue Lv3 once-per-turn limit and black Lv2 occupied-cell priority.
- Confirmed the intentional cross-system composition for blue fire: creating or refreshing fire under an occupant immediately applies the overlay's enter effect. Lv2 therefore adds two burning stacks in total, and Lv3 doubles after both additions.
- Replaced black fire's global base plus level-bonus calculation with complete absolute `death_fire_radius`, `death_fire_count`, and `death_fire_duration` values on every level row.
- Removed the obsolete black-fire combat-config keys, accessors, and constants. Player-facing level summaries now render the same absolute values used by execution.
- Added required-field and integer/positivity validation for black-fire rows, and made combat config reject unknown keys.
- Fixed the semantic runner's per-case accounting so later failures cannot be printed or counted as passes after an earlier failure.
- Semantic coverage increased from `53 / 90` to `59 / 90`.

Review judgment:

- Absolute level rows are the right editing surface here. A designer can now change one black-fire tier without reconstructing a base-plus-delta formula spread across two files.
- The blue stack totals are not a hidden duplicate trigger: they are the documented contact effect composed with the separately documented fire-overlay enter effect. The contracts make that interaction visible and preserve the once-per-turn doubling boundary.
- Required-field enforcement is still incomplete across the rest of `gem_effect_levels.json`. Black fire is now strict, but other families can still lose fields and fall back silently; that remains an explicit next-stage schema task.

## 2026-07-10 / Phase 29

Scope reviewed:

- red/blue ice movement floors and contact progression
- black ice radius, sluggish, slow, and freeze progression
- shared radius ownership between black ice and black conductive
- all-target representation for black conductive
- reliability of referenced relic numeric branches and the verification harness

What improved in this phase:

- Added explicit `slowed_min_move_points` values to red/blue ice. Lv1 keeps the global floor of 1; Lv2/Lv3 can reduce movement to 0 as stated by the detailed gem design.
- Slow status instances now preserve the strongest lower movement floor across later stacks without changing ordinary slow sources.
- Added complete blue-ice contracts for one-stack contact, two-stack zero-floor contact, and both sides of the Lv3 “already slowed” condition.
- Added black-ice Lv1/Lv2 design contracts plus a separate Lv3 implementation-observation case. The latter records current paralysis behavior without counting it as authored freeze.
- Moved `ice_death_radius` out of global combat config. Black ice now owns `death_radius`; black conductive owns `strike_radius`.
- Removed black conductive's `strike_count: 999` sentinel and added conditional validation for counted versus all-target modes. Summaries render “all targets”.
- Fixed `per_empty_slot_ref`, `empty_slot_mult_ref`, and `rng_chance_ref` branch guards in relic modifier evaluation.
- Expanded strict required-field schemas to red/blue ice, black ice, and black conductive.
- Semantic coverage is now `61 / 90 = 67.77%`: five newly verified ice rows were added, while three previously overstated red-freeze rows were removed from the verified set.

Review judgment:

- A source-specific slow floor belongs in status payload, not in the global slow definition. This keeps the detailed Lv2 exception data-driven without changing every other slow source.
- Radius values belong with each gem level. The removed `ice_death_radius` name concealed cross-mechanic coupling and made one edit affect conductive behavior unexpectedly.
- Removing three green coverage rows is a correctness improvement. Their tests proved placeholder paralysis, not the authored freeze/frostbite state machine.
- Freeze cannot be finished responsibly until frostbite lifetime/removal is specified. The implementation gap and the related player/enemy paralysis lifecycle inconsistency remain explicit open issues.
- `verify fast` still reports 23/23 while selected logs contain GDScript assertion failures. Direct Phase 29 evidence therefore comes from isolated, clean runs of the balance validator, status test, level-context test, and 78-case semantic contract suite in addition to the wrapper summary.

## 2026-07-11 / Phase 30

Scope reviewed:

- trustworthiness of `tools/verify` under Godot assertion behavior
- stale gravity and explosion regression expectations
- stone-bow intent damage versus attack-pipeline execution
- explosion level ownership across normal attack, active trigger, black death, AI scoring, and player-facing summaries

What improved in this phase:

- `tools/verify` now fails a test on either a non-zero process exit or any `SCRIPT ERROR:` in its log. Hidden GDScript assertions can no longer produce a green wrapper result.
- Non-zero exits are captured inside an `if/else`, preserving complete-suite execution even though the shared Godot helper enables `set -e`.
- Gravity test units now use `GameState.register_unit()`, preserving occupancy invariants. The diagonal case verifies the shared cardinal path rule: move one cell, then stop before the blocker and damage both units.
- Removed the obsolete “four explosions deal triple damage” expectation. Normal and active-trigger tests now prove counts above the authored maximum clamp to Lv3's 2x damage.
- Centralized explosion blast-pattern and damage-multiplier resolution in `GemEffects`. Red/black level rows are strict, black Lv3 explicitly owns its 2x multiplier, and attack execution no longer duplicates the formula.
- Ordinary attack previews and AI scoring use the same configured explosion amount. The deterministic stone-bow contract now proves a displayed 12-damage explosion matches the 12 damage delivered by execution and previews the affected cells.
- Black explosion's HUD/query summary now displays its configured multiplier alongside chain behavior.
- Strict full-suite auditing exposed and repaired five additional false-green fixtures/contracts: enemy extra attacks now use the status API, iron-boots immunity owns an active run fixture, enemy-red range tests stay in bounds, editor import uses `user://`, and normal/hover relic textures share initialization order.
- Strict `verify fast` and `verify changed` both pass `23 / 23`; semantic coverage remains honestly unchanged at `61 / 90 = 67.77%` because this phase repaired evidence quality rather than claiming new design rows.
- Strict `verify all` completes with `67 / 70`; only the three previously recorded overlay/water rendering contracts remain red.

Review judgment:

- Checking logs in the runner is the correct minimum invariant for this test style. Requiring every legacy test to be rewritten before trusting any result would leave the suite falsely green in the meantime.
- Explosion amount is now edited in one level row and observed by execution, preview, AI scoring, and UI summary. The remaining global base damage is a separate base parameter, not a competing level multiplier.
- The preview helper intentionally handles only damage shapes representable by one scalar. Light, split, and echo combinations need a structured multi-component intent model; that limitation is recorded rather than hidden behind an invented total.
- Full-suite evidence is now complete under the stricter verifier. Its remaining three visual failures are isolated in the issue ledger rather than being conflated with the green numeric-drive surface.

## 2026-07-11 / Phase 31

Scope reviewed:

- completeness and ownership of every gem-effect level row
- validator behavior for missing, extra, and misplaced fields
- black counter reflection, vulnerable, and disarm progression
- attack blocking across player actions, enemy intent, and shared attack execution

What improved in this phase:

- Replaced partial required-field checks with an explicit schema for all 30 slot/tag groups. Every group must define levels 1/2/3, every level must contain its complete semantic field set, and fields declared for another group are rejected.
- Added the missing black-counter level table: Lv1 reflects actual HP lost, Lv2 also applies one turn of vulnerable, and Lv3 also applies one stack of disarm.
- Damage bookkeeping now records actual HP loss before death hooks run, so a 50-damage overkill against 7 HP reflects 7 rather than 50.
- Added `disarmed` as a first-class status and routed attack permission through status rules, the shared attack pipeline, player action availability, battle queries, and enemy intent/execution.
- Added validator mutation cases for a missing group, missing level, missing field, cross-group field, and extra level. Three black-counter semantic contracts cover all authored levels and prove that disarm rejects a real follow-up attack.
- A field-to-read audit found at least one runtime consumer for every field currently authored in `gem_effect_levels.json`.
- Current evidence is `verify fast/changed: 23 / 23`, direct semantic-contract execution: 81 cases passing, and executable design coverage: `64 / 90 = 71.11%`.
- Strict `verify all` remains `67 / 70`; the only failures are the same three tracked overlay/water rendering contracts, with no new combat, numeric, status, AI, or semantic-contract regression.

Review judgment:

- This closes a high-risk data-drive failure mode: authored data can no longer disappear, drift into the wrong gem family, or exist without the black-counter runtime consuming it while validation stays green.
- Black counter is now a genuinely level-driven mechanic. Its numbers are edited in one level row and exercised through normal death, status, and attack paths rather than an isolated calculation helper.
- The new attack-block boundary is appropriately centralized in `StatusRules` and enforced again in `AttackPipeline`, so UI availability and AI planning cannot be the sole authority for legality.
- Disarm's exact lifecycle is provisional because the detailed design specifies only “+1 disarm”. The current one-attack-opportunity convention is recorded in the issue ledger instead of being presented as settled product semantics.

## 2026-07-11 / Phase 32

Scope reviewed:

- remaining high-value conflicts in freeze/frostbite, blue gravity, and conductive damage ownership
- red-counter level data and status payload semantics
- Lv2 tagged retaliation and Lv3 kill-refresh execution

What improved in this phase:

- Replaced red counter's `mark_stacks: 1/2/3` level sentinel with three direct fields: `mark_duration`, `retaliation_with_tags`, and `grant_extra_attack_on_kill`.
- Counter marks now snapshot those semantic flags in their watcher payload. The damage resolver consumes the flags directly instead of reconstructing behavior from `level >= 2/3`.
- Reapplying a mark preserves the stronger semantic flags and the longer duration. Legacy payloads with the former `level` field remain readable without allowing new config to author that field.
- Removed the now-unused `counter_mark.default_level` status fallback and updated the dynamic HUD/query summary to render the same direct fields used by execution.
- Added executable contracts for Lv2 and Lv3. Lv2 proves TAG propagation through fire's direct-plus-overlay composition; Lv3 proves a lethal retaliation grants one configured extra attack.
- Direct evidence passes: balance config, skill behavior, level-context copy, and all 83 semantic contract cases. Executable design coverage is now `66 / 90 = 73.33%`.
- Strict `verify changed` passes `23 / 23`; `verify all` remains `67 / 70`, with only the same three tracked overlay/water rendering contracts failing.

Review judgment:

- The new table is a substantially better editing surface: each value says what it changes, and changing a boolean cannot accidentally masquerade as adding status stacks.
- Storing resolved semantics on the mark is appropriate because the mark is the delayed gameplay state. It also makes save/debug inspection explain itself without requiring the original gem count.
- The audit correctly did not force progress on ambiguous areas. Frostbite lifetime, blue gravity's duplicate trigger model, and conductive damage ownership remain product decisions rather than engineering defaults.
- Red counter's pre-hit ordering was exposed as a separate conflict. Phase 32 preserves it intentionally; changing both data representation and lethal-trade behavior in one phase would make review evidence ambiguous.

## 2026-07-11 / Phase 33

Scope reviewed:

- red, blue, and black split ownership across all level rows
- red split execution and AI scoring
- blue damage sharing and temporary-clone creation/lifetime boundaries
- black clone stats, slot/gem inheritance, enemy drops, player control, and presentation state
- fission-slime unit override and split-specific relic overrides

What improved in this phase:

- Replaced blue split's two ordinal booleans with explicit `redirect_mode`, `redirect_ratio`, `redirect_radius`, `temp_clone_count`, `temp_clone_hp`, `temp_clone_stat_ratio`, `temp_clone_duration`, and `temp_clone_per_turn_limit` fields. Black split now also authors `clone_count` beside `stat_ratio`.
- Removed the four competing split globals for red damage ratio, blue redirect ratio/radius, and black stat ratio. Red execution and enemy AI now resolve the same level-row damage ratio; blue and black runtime paths read their complete active rows.
- Added cross-field validation so inactive temporary-clone rows cannot carry convincing non-zero knobs, active rows require positive values, redirect ratios stay in `(0, 1]`, and clone counts remain positive integers. Mutation tests reject the obsolete `spawn_temp_clone` sentinel and malformed split rows.
- Blue Lv3 now spawns after actual surviving HP loss, uses its configured HP/stat/count/duration/cap, inherits no slots, and is excluded from black split control and merge lifecycle.
- Black death clones now scale attack, armor, movement, speed, and max HP with upward rounding. Slots and gems are round-robin partitioned exactly once; only inherited split gems are disabled/locked, and inherited enemy originals are consumed rather than duplicated as drops.
- The fission-slime 50% override now affects Lv1 as authored, while higher black levels keep their stronger 50%/80% rows. Player-only split relic modifiers no longer alter enemies.
- Added executable contracts for blue split Lv1/Lv2 and black split Lv1-Lv3. They prove exact damage shares, two-clone counts, all-stat ratios, total slot/gem conservation, disabled split counts, and zero duplicate drops.
- Evidence passes: direct balance validation, the fission-slime split assertions, all 88 semantic contract cases, `verify changed: 23 / 23`, and `verify all: 67 / 70`. The full-suite failures remain the same three recorded overlay/water visual contracts. Executable design coverage is now `71 / 90 = 78.88%`.

Review judgment:

- Split tuning is now a coherent editing surface: a designer changes one level row and sees the same values in execution, AI scoring where applicable, validation, and HUD/query summaries. Unit and relic modifiers are explicit override layers rather than hidden alternative bases.
- The black clone rewrite follows the highest-authority detailed design and removes real state multiplication, not merely cosmetic duplication. Slot/gem conservation is now an executable invariant.
- Blue Lv3 is intentionally not counted as design-covered. Its numeric behavior is wired and observed, but player control and phase-relative lifetime require a product decision.
- The 60% Slime Crown blue override does not meaningfully affect equal-sharing levels; this is recorded as a relic/gem interaction conflict rather than papered over with a new formula.
- The independent fission-slime suite exposed trample overlap errors in `_cell_occupancy`. They predate and do not invalidate the split contracts, but remain a real state-model issue and a verifier blind spot.
- No external design document was changed because Phase 33 implements the existing authoritative split table. Newly discovered ambiguities are recorded here and in `semantic-conflicts.md` instead of inventing product semantics.

## 2026-07-11 / Phase 34

Scope reviewed:

- blue and black light level semantics, targeting, exposure lifetime, and black settlement
- red/blue/black echo tag selection and Lv3 empowerment
- black echo execution inside a real deferred/non-deferred death chain
- trustworthiness of existing red-echo Lv3 and black-light Lv3 coverage claims

What improved in this phase:

- Found that death-chain deduplication rejected every intended black-echo replay after the original tag had resolved. Echo-depth replays now bypass only that owner/tag dedupe; ordinary duplicate death hooks and recursive echo selection remain guarded.
- `GemEchoRules` no longer uses `echo_level >= 3` to decide whether a selected tag should be moved into the empowered position. It reads direct blue strength and black repeat fields instead.
- Validation now requires `first_tag_strength` and `first_tag_repeat_count` to be positive integers, with mutation tests for zero values.
- Added real lethal-path contracts for black echo Lv1 and Lv2. Lv1 proves one selected explosion executes twice in total; Lv2 proves two distinct tags through two conductive strikes and two frost pulses.
- Added a black echo Lv3 implementation-observation contract for its configured first-tag repeat, without claiming that repetition is the authored meaning of empowerment.
- Downgraded red echo Lv3 and black light Lv3 from design coverage. The former is a generic follow-up-damage placeholder; the latter ignores lethal tags and Lv2 settlement strength.
- The semantic suite now contains 91 passing cases. Honest executable design coverage remains `71 / 90 = 78.88%`: two new black-echo rows replace two overstated rows rather than inflating the headline.
- Final evidence passes `verify changed: 23 / 23` and `verify all: 67 / 70`; the only full-suite failures remain the same three recorded overlay/water visual contracts.

Review judgment:

- Allowing explicit echo-depth replay is narrower and clearer than weakening death-chain deduplication globally. It fixes the intended mechanic without reopening duplicate black effects elsewhere.
- Direct strength/repeat fields are the correct data boundary, but they do not make the product meaning of “empowered” self-evident. Lv3 remains unverified until that meaning is authored.
- Black light cannot be repaired as a numeric-table exercise alone. It first needs lethal gem-tag transport and a defined mapping from each tag to settlement strength.
- Blue echo should be replaced by a complete tag-effect registry rather than extending its current switch one tag at a time. Silent no-op selections are incompatible with trustworthy data-driven content.
- Lowering false coverage while fixing black echo is a net quality gain. The review ledger now distinguishes values that are editable from semantics that are actually complete.

## 2026-07-11 / Phase 35

Scope reviewed:

- whether combat-config keys have real runtime consumers
- scalar enemy-intent damage versus multi-hit/multi-target gem attacks
- split/light execution formulas, geometry, intent copy, and Utility AI scoring
- attack dispatch and disarm classification for red/custom enemy intents

What improved in this phase:

- Added typed `IntentDamageComponent` data carrying source, damage per hit, instance count, predicted target applications, affected cells, and certainty. `IntentState.damage` remains a compatibility view instead of the only representation.
- Added pure `LightBeamRules`; execution and preview now share beam directions, blocker truncation, endpoints, and affected cells without making preview depend on the full execution pipeline.
- Added shared `GemEffects.red_split_damage()` and `red_light_damage()` formulas. Execution, structured preview, dynamic intent text, and AI damage scoring now preserve the same configured ratios and floor order, including light + split's two-stage scaling.
- Split intent copy no longer hard-codes `x3`; it renders the resolved shot count. Multi-beam light copy renders its configured/resolved beam count.
- AI scoring for ordinary melee/ranged attacks and explosion/split/light red skills now reads predicted damage from the same structured profile instead of using raw attack, a fixed explosion base, or a hard-coded light `0.5`.
- Removed the zero-consumer `arc_hit_damage` combat key/accessor/fallback and added a validator regression that rejects it as stale configuration.
- Reconnected `counter_attack` and `echo_attack` to enemy execution, and classified slam, trample, lawless attack, and damaging plunder as attacks for disarm gating.
- Added focused execution contracts for light Lv2, light + split, split Lv3 ranged geometry, multi-cell units hit by multiple split projectiles, counter/echo dispatch, and custom-intent disarm.
- Final evidence passes `verify changed: 23 / 23` and `verify all: 67 / 70`. The only full-suite failures remain the same three tracked overlay/water visual contracts; semantic coverage remains honestly unchanged at `71 / 90 = 78.88%` because this phase adds preview/integration contracts rather than claiming new gem-design rows.

Review judgment:

- The dependency direction is now healthy: execution, preview, and AI depend on small pure geometry/formula rules. The first implementation temporarily made preview depend on `AttackPipeline`; phase review caught and removed that coupling before broad verification.
- Keeping the scalar field as a compatibility projection allows incremental migration without preserving its old ambiguity as the authoritative model.
- The model is deliberately honest rather than exhaustive. Arc chains, random echo results, future status damage, defenses, and reactive redirects still need component producers.
- Two runtime/design gaps were exposed instead of normalized: adjacent split loses its backward extra shot, and light endpoint explosions ignore explosion level semantics. Both are logged as conflicts rather than receiving invented placement/composition rules.

## 2026-07-11 / Phase 36

Scope reviewed:

- lethal-damage metadata from attack execution through immediate and deferred death hooks
- direct, redirected, elemental, collision, and forced-hazard damage attribution
- displacement/spike settlement order and occupancy invariants
- trustworthiness of combination and trample fixtures

What improved in this phase:

- Added canonical `DamageContext` data for source, reason, ordered unique gem tags, resolved gem context, and actual HP loss. `CombatTransaction`, normal/true damage, immediate death, and deferred death now preserve the same payload.
- Damage events expose canonical `damage_tags`, and `EventValidator` rejects malformed or duplicate tag arrays. Legacy reason-only damage receives a narrow inferred tag only where the mechanism is unambiguous.
- Primary red attacks carry their resolved active context. Split redirection preserves incoming context; arc damage, gravity collision, explosion collision, light reflection, and status ticks have explicit component-level attribution.
- Extended context through wall/unit/entity collisions and forced tile entry. Enemy-specific gravity execution was found during static review and connected to the same path.
- Corrected forced spike semantics: every traversed spike now uses configured collision damage and vulnerable, while final landing cleanup no longer settles the same entity twice.
- Repaired transient trample occupancy after successful relocation and changed the all-blocked fixture so it really exhausts the radius-2 search and proves `space_squeeze` rather than passing on base skill damage.
- Repaired the 128-case red-tag matrix, which directly assigned `player.pos`; every case now moves through `GameState` and explicitly validates event shape plus battle invariants.
- Focused evidence passes for combat transactions, immediate/deferred black-light context, displacement, gravity, explosion, fission slime, enemy red gems, arc, status, 128 red combinations, 160 blue/black combinations, and 91 semantic cases.
- Strict `verify changed` passes `23 / 23`; strict `verify all` remains `67 / 70`, with only the same three tracked overlay/water visual contracts failing. Executable design coverage remains honestly unchanged at `71 / 90 = 78.88%` because this phase completes transport and evidence quality rather than the still-undefined black-light settlement mapping.

Review judgment:

- `DamageContext` belongs at the transaction boundary. Death hooks no longer have to reverse-engineer semantics from a reason string, and secondary mechanisms can deliberately narrow or preserve tags at their point of creation.
- Transport and product semantics are now cleanly separated. The code can deliver lethal tags reliably, but black light is not called complete until design defines what each tag settles and how Lv2 strength changes it.
- Phase review prevented two false conclusions: the old trample squeeze test never reached squeeze, and the combination matrix was not invariant-clean despite its pass marker. Both now provide executable evidence instead of console optimism.
- A survivable fully blocked trample remains incompatible with the single-occupant index. Likewise, redirected/hazard tag attribution is an authored-policy gap. Both remain explicit conflicts rather than receiving hidden assumptions.
- The public displacement calls have accumulated positional policy arguments. The new context parameter is backward-compatible, but a later combat-transaction phase should replace those booleans and scalar tails with a typed/options object before adding more displacement policies.

## 2026-07-11 / Phase 37

Scope reviewed:

- fission-slime trample damage composition and no-space squeeze tuning
- star-relocation search geometry and its relationship to squeeze damage
- player attack highlight geometry, lethal thresholds, and black-death preview
- duplicate/no-op damage calculations in the attack pipeline
- unit-balance and combat-config authoring safety

What improved in this phase:

- Added `trample_collision_damage` beside `trample_damage` in the fission-slime balance row. Intent copy now shows their configured total, while structured preview exposes separate skill and collision components and execution composes the same values.
- Added configured star-relocation maximum distance and squeeze damage per tile. `BoardUtils` generates each outer square ring from that radius, and `Displacement` derives squeeze damage from the same fields rather than owning a second fixed `2`.
- Unit-balance validation now rejects unknown fields and requires the complete fission-slime balance row. Combat-config validation requires positive integer relocation radius and non-negative integer squeeze damage.
- Replaced `BattleQueryService`'s hand-written light/split/explosion preview with `IntentPreviewRules.build_red_attack_profile()`. Gravity range, multi-beam light, split geometry, explosion shapes, and endpoint compositions now share one preview source.
- Added per-component post-mitigation prediction that consumes shield in hit order and applies vulnerable per hit. Black-death explosion cells are shown for structured lethal attacks at any HP, while blue split/gravity and active counter marks suppress an uncertain lethal claim.
- Removed the unused `AttackContext.final_damage` shield calculation and unsupported `piercing` tag. Actual shield consumption remains solely in `CombatRules` instead of being traced through a value execution never used.
- Added contracts for configured trample 3 + 1 preview/execution, dynamic radius-based squeeze setup, strict config mutation failures, and player hover at 10 damage versus 10 HP with/without 1 shield.
- Direct targeted tests pass for balance config, intent consistency, fission slime, skill behavior, and displacement. Strict `verify changed` passes `23 / 23`; strict `verify all` remains `67 / 70`, with only the same three tracked overlay/water visual failures. Semantic coverage remains `71 / 90 = 78.88%`.

Review judgment:

- Trample is now a useful editing surface: skill damage, collision contribution, search radius, and per-tile squeeze damage each have one named authority and validation. The UI no longer advertises 3 while execution silently deals 4.
- Reusing structured profiles in player query code closes an important consumer gap left after Phase 35. A shared model is only valuable if enemy intent, AI, and player-facing previews all consume it.
- Lethal preview deliberately stops at deterministic current-state mitigation. It does not claim to simulate probabilistic defenses, delayed statuses, arc chains, relic caps, or recursive black-death cascades; those gaps remain explicit.
- Review surfaced two unresolved design issues rather than changing behavior: the detailed collision document calls a complete radius-2 ring “12 cells” although runtime has 16, and its no-space “nearest cell” instruction has no legal destination/tie-break after every candidate is blocked.
- Removing the fake piercing path is preferable to retaining an API-shaped promise with no behavior. Future armor penetration should be modeled at the transaction mitigation boundary and verified through execution, preview, and event evidence together.
## 2026-07-12 / Phase 38

Scope reviewed:

- `DataRegistry` startup ownership for gem, unit, and encounter catalogs
- whole-file replacement versus hardcoded deep-merge fallback
- schema completeness and cross-catalog references
- production encounter enumeration versus test-only fixtures

What improved in this phase:

- Removed the complete in-code gem, unit, and encounter catalogs from `DataRegistry`; JSON is now the sole runtime authority for those definitions.
- Gem definitions now reject missing and unknown fields, invalid colors/levels/rarities, duplicate semantic tags, unknown combo tags, and unknown effect profiles before conversion to runtime colors.
- Unit definitions now reject missing base stats, unknown fields, malformed slots/footprints, unknown initial gems, and unknown behavior ids. Patrol, stone-bow, and fission behaviors require their complete behavior-owned balance rows.
- Encounter files now validate nested enemy groups, weighted random candidates, board bounds including large-unit footprints, tile/entity/overlay ids, tile slots, and unknown fields before any `Vector2i` hydration occurs.
- Moved four behavior-test encounters to `tests/fixtures/encounters`. They load only in debug builds and are hidden from normal `get_encounter_ids()` enumeration while remaining directly loadable by tests.
- Added regression evidence that runtime catalog ids exactly equal authored JSON ids and that omitted fields cannot be supplied by a hidden in-code definition.

Problems surfaced and recorded:

- `CombatConfig`, `StatusConfig`, and `AIProfiles` still own duplicate numeric fallback tables.
- Gem-pool rarity weights, relic-source weights, and enemy slot curves still have `DataRegistry` fallback constants.
- These are now a named open issue and the next single-authority cleanup target; Phase 38 does not claim that the entire numeric system is complete.

Review judgment:

- Whole-catalog replacement is the correct boundary for primary authored content. Per-instance gem overrides still use deep merge intentionally because they are runtime modifiers, not a second base catalog.
- Keeping behavior scripts in `BehaviorRegistry` is appropriate, but authored `behavior_id` values must be checked against that registry; Phase 38 adds this check so typo fallback cannot alter an enemy archetype silently.
- Hiding test fixtures at enumeration time preserves existing deterministic behavior tests without polluting profile unlock flags or normal encounter selection.
- No design-source conflict was introduced: this phase changes failure and authoring semantics for invalid data, not any valid battle formula.

Verification at review point:

- headless editor import/compile passed
- focused `balance_config_test` passed
- focused `encounter_load_test` created all 22 production encounters successfully
- strict `verify fast`: `23 / 23`
- strict `verify changed`: `23 / 23`
- strict `verify all`: `67 / 70`; only the same three tracked overlay/water visual contracts failed
- semantic coverage unchanged at `71 / 90 = 78.88%`

## 2026-07-12 / Phase 39

Scope reviewed:

- combat/status/AI configuration ownership and missing-field behavior
- behavior-owned unit balance rows
- gem/relic pool weights, enemy slot curves, economy prices, and shop counts
- release-build handling of invalid authored catalogs

What improved in this phase:

- Removed the remaining combat numeric mirror from `Constants`. `CombatConfig` now loads a complete validated file and exposes required values without per-call balance fallbacks.
- Replaced `StatusConfig`'s hardcoded deep-merge table with complete authored status rows. Defaults and status-specific multipliers now have one JSON authority and strict schema validation.
- Added explicit AI profile defaults to JSON and removed in-code profile, alias, and tuning tables. Every resolved profile is complete, and unit definitions reject unknown profile ids.
- Removed hardcoded global gem rarity weights, relic-source weights, enemy slot curves, behavior scores, economy prices, and shop offer counts. Their loaders use validated whole-file replacement.
- Added missing barrel radius and smoke/puddle durations to the authored combat surface, then migrated runtime consumers and tests to those accessors.
- Review caught several loaders that logged invalid data but still assigned it outside debug builds. Gem levels, relic refs/defs, reward offers, and reward UI now clear and reject invalid catalogs before assignment.
- Repaired a false-green patrol test: it now supplies the authored unit identity and uses `GameState.move_unit()`, so behavior lookup and occupancy invariants are genuinely exercised.

Review judgment:

- A data file is not authoritative merely because code reads it. Authority requires complete schema, whole-table replacement, no duplicate fallback values, and refusal to execute malformed content; the core loaders now follow that rule.
- Zero remains an error sentinel at a few generic runtime/query boundaries, but it is no longer a second authored balance value. Structural board/render dimensions and algorithmic absence values are intentionally not classified as tunable combat balance.
- The next residual audit should focus on consumer-side `.get(field, literal)` calls over already-complete gem level rows. Those literals can still hide a broken caller even though catalog validation guarantees valid startup data.

Verification at review point:

- focused balance, status, AI, economy, shop, patrol, stone-bow, fission-slime, and pool tests passed
- headless editor import/compile passed
- strict `verify fast`: `23 / 23`
- final snapshots and strict changed/all verification pending after the residual consumer audit

## 2026-07-12 / Phase 40

Scope reviewed:

- every consumer of complete gem effect level rows
- remaining combat/status/pathfinding literals
- board-size-derived search and shot geometry

What improved in this phase:

- Removed hidden numeric defaults from red/blue/black gem-level consumers across attack, contact, damage, death, echo, clone, pillar, and beam paths.
- Added authored blue-explosion turn-start damage and blue-gravity redirect radius; complete schema validation requires both on every level.
- Moved lawless attack bonus, water movement cost, and generic navigation weights into status, combat, and AI data.
- Replaced fixed split-shot board bounds and black-split spawn search radius with current board dimensions.
- Removed the final hardcoded painkiller cap and empty-coffin ratio compatibility values from their active authored paths.

Review judgment:

- Complete startup validation and required consumer reads now reinforce each other. A malformed row cannot enter runtime, and a wrong consumer scope can no longer restore an obsolete rule through a literal fallback.
- Fixed collision `max(1, moved tiles)` remains code because the authority document explicitly defines it as an invariant formula, not a tuning table.
- Blue explosion's turn-start aura conflicts with detailed gem design. Its amount is data-driven for honesty, while the trigger remains an explicit compatibility observation pending product resolution.

Verification at review point:

- headless compile passed
- strict `verify fast`: `23 / 23`
- semantic coverage unchanged at `71 / 90 = 78.88%`

## 2026-07-12 / Phase 41

Scope reviewed:

- adventure map dimensions and room distribution
- chapter progression and encounter selection
- relic catalog completeness and runtime selection defaults
- deterministic seed compatibility and false-green map evidence

What improved in this phase:

- Added `adventure_progression.json` as the sole authority for chapter count, map size, chapter seed stride, room rules/weights, event pool, combat pools, and per-chapter Boss encounters.
- The map generator derives its final layer from grid size and accepts the validated map config. Fixed start/end weights remain explicit so old seeds consume RNG in the same order.
- Runtime cross-validates progression encounter and event references after production catalogs load.
- Refactored `map_test` away from hardcoded 8/14/64 and from assertions that could print `PASS` after script errors. It now reads authored constraints and exits nonzero on failures.
- Strengthened relic definitions to a complete schema and removed runtime `common/global/1` selection fallbacks. Placeholder empty-pool behavior is explicitly modeled.

Review judgment:

- This is the highest-leverage authoring surface outside combat: adding a chapter, reweighting room flow, changing map size, or replacing encounter pools now happens in one file with reference validation.
- The config preserves the existing fully generated map model. GDD's preference for hand-authored room templates is a product/content direction, not something this numeric migration should silently redesign.
- Data edits are now easy enough that versioning becomes the next systemic risk. Active runs do not pin a balance catalog version, so the issue is recorded rather than hidden by deterministic seeds.

Verification at review point:

- focused progression config validation passed
- focused deterministic map topology/rule test passed
- focused complete relic catalog validation passed
- tutorial and three-red-explosion deterministic snapshots passed without invariant violations
- strict `verify changed`: `23 / 23`
- strict `verify all`: `67 / 70`; only the same tracked overlay/water visual contracts failed
- semantic coverage remains `71 / 90 = 78.88%`; all 19 uncovered rows remain explicitly reported
