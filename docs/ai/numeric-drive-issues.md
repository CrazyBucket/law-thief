# Numeric Drive Issues

This file records problems exposed while implementing the numeric-drive plan, including issues not directly fixed in the same change.

## Open

### Balance data has no content version or run snapshot

- Runtime saves record a ruleset version, but they do not record a hash/version of combat, gem, AI, economy, progression, encounter, unit, or relic data.
- Editing a JSON value therefore changes the behavior of an active run after reload; deterministic seeds reproduce RNG choices but not the former authored rules.
- Impact: the new single-authority data surface makes tuning much easier, but serious balancing, replay comparison, telemetry cohorts, and save compatibility need a `balance_version` plus either immutable versioned catalogs or a run-start config snapshot.

### Runtime map topology is still fully algorithmic

- `GDD.md` prefers hand-authored room templates with randomized content, while the current `AdventureMapGenerator` creates the complete square route graph algorithmically.
- Phase 41 makes that generator's progression numbers data-driven but deliberately does not replace its topology model.
- Impact: room-flow tuning is now simple, but authored pacing beats, guaranteed teaching sequences, and deliberate route tradeoffs still require a template/catalog layer above the generator.

### Design root lookup is broken on this Windows workspace

- `./tools/context ...` reports `DESIGN_ROOT_MISSING /Users/jinhuiwu/code/learning-notes/game/design/law-thief`.
- The actual design docs are available locally under `D:/code/learning-notes/game/design/law-thief`.
- Impact: design lookup tooling is less trustworthy than the source documents themselves until the path resolution is fixed.

### Several passing tests still exit with resource leak warnings

- `stone_bow_guard_test.gd` currently passes but exits with `ObjectDB instances leaked at exit` and `resources still in use at exit`.
- `overload_test.gd` reproduces the same warnings after passing.
- Additional fast-suite runs show the same class of warnings in `battle_renderer_timing_test.gd`, `bomb_rat_test.gd`, `explosion_test.gd`, and `intent_consistency_contract_test.gd`.
- Impact: test signal is noisier than it should be, and real lifecycle regressions may be easier to miss.

### Text encoding diagnostics can be misleading

- UTF-8 reads show that most previously suspected corruption in `gem_effects.gd`, `attack_pipeline.gd`, `contact_resolver.gd`, `overload_rules.gd`, and runtime logs was caused by Windows PowerShell's default decoding rather than damaged source text.
- Phase 39 repaired the genuinely corrupted source comment previously found in `scripts/rules/ai_profiles.gd`.
- Impact: the product strings inspected in this phase are intact, but tooling that reads UTF-8 without an explicit encoding can still create false-positive audits.

### Semantic contract coverage is still low for a data-driven system

- Current executable design coverage is `71 / 90 = 78.88%`.
- Large gaps remain in blue gravity, red/black freeze semantics, blue split Lv3, blue/black light, red/blue echo Lv3 semantics, and blue echo generally.
- Impact: moving more balance into data increases leverage, but also increases risk if semantic coverage does not expand with it.

### Black light settlement ignores lethal damage tags

- Detailed gem design says black light clears every exposed target by triggering effects from the lethal attack's tags, with Lv2 adding one level of effect strength and Lv3 adding blind.
- Phase 36 adds canonical lethal-damage context to immediate and deferred death hooks. It preserves source, reason, actual HP loss, canonical gem tags, and the resolved gem-tag context through direct attacks, split redirection, elemental secondary damage, displacement collisions, and forced spike entry.
- `_resolve_black_light()` still deals the placeholder `exposure stacks × dead owner's attack`, removes exposure, and only reads Lv3 blind. It exposes the received tags on diagnostic beam events, but does not map those tags to settlement effects; the Lv2 row still has no semantic strength field.
- Phase 34 downgrades the former black-light Lv3 coverage to an implementation observation.
- Impact: transport is no longer the blocker, but all three black-light rows remain behaviorally incomplete until per-tag settlement and strength semantics are authored.

### Secondary damage-tag attribution is not fully authored

- Phase 36 uses an explicit working policy: primary red attacks carry their resolved active tags; arc rebounds and gravity collisions use their own narrow tag; explosion-driven collisions use `explosion`; status ticks infer `fire` or `poison`; split redirection preserves the incoming context.
- Existing design sources do not define whether a redirected hit should add `split`, whether a light beam should retain unrelated carried tags after dye transitions, or whether a spike kill should report the initiating displacement tag, the hazard, or both.
- Impact: the canonical transport is deterministic and testable, but changing black-light settlement before this attribution policy is authored could make edge-case outcomes depend on an engineering convention.

### Exposure lifetime has no authoritative runtime owner

- `GDD.md` says exposure lasts until the end of the current turn. The higher-authority detailed gem document defines settlement interactions but does not state a duration.
- `status_config.light_exposed.default_duration` is `0`, so runtime exposure persists until black light explicitly removes it.
- Impact: black-light target eligibility can span more turns than the GDD describes. A duration decision is required before adding expiry contracts.

### Blue light's extra-beam target policy is not level-distinct

- `GDD.md` clarifies that the first reflected beam travels opposite the incoming direction; current runtime targets the attacker first, which is consistent with that rule.
- For additional beams, runtime immediately appends every enemy unit and takes dictionary order at every level. Detailed design reserves “prefer enemy direction” for Lv3, while Lv2 only says to reflect two beams.
- Impact: Lv2 and Lv3 target selection are mechanically identical apart from beam count, and empty-direction reflection is not modeled when too few units exist.

### Blue echo implements only a hand-written subset of gem tags

- Blue echo manually handles conductive, fire, poison, ice, and light. Explosion, gravity, split, and counter are silently ignored.
- The ice branch calls the red hit/freeze helper rather than replaying a blue-slot contact/defense effect.
- Impact: `echo_tag_count` can select a valid authored blue tag that produces no echo, so blue echo levels cannot be considered generally implemented even though their count/strength fields are consumed.

### Echo Lv3 empowered-tag semantics are undefined in executable terms

- Detailed design says one of two selected tags triggers in an empowered form, but it does not define empowerment per tag.
- Red echo currently adds a generic 50% follow-up hit, blue echo uses a hand-written first-tag strength of 2, and black echo repeats the first tag once. These are three unrelated interpretations.
- Phase 34 downgrades red echo Lv3 and keeps black echo Lv3 as implementation observations. Lv1/Lv2 black echo remain design-verifiable because they only require one or two distinct normal replays.
- Impact: a per-tag empowered-effect contract or an explicit generic rule is needed before any echo Lv3 row can be authoritative.

### Blue split Lv3 temporary-clone action lifecycle is unspecified

- Detailed gem design says the 1-HP, 30%-stat clone disappears after one turn, but does not say whether a player-owned temporary clone gets its own action or exactly which phase boundary consumes that turn.
- Runtime creates the clone on the owner's team and expires it from `GemEffects.tick_turn_start()`, but does not add a player clone to the controllable queue. Depending on when the owner is hit, a player clone can disappear without ever receiving an action.
- Phase 33 data-drives and verifies the configured HP, stat ratio, duration, count, and per-turn cap, while deliberately excluding this row from executable design coverage.
- Impact: counting blue split Lv3 as complete would overstate behavior. Product design must specify team control and phase timing before the lifecycle can be authoritative.

### Slime Crown's blue split override does not compose with equal sharing

- `relic_slime_crown` authors a 60% blue damage-transfer override. Blue split Lv2/Lv3 author full equal sharing among the owner and every nearby unit, represented by `redirect_ratio: 1.0`.
- Override resolution takes the larger ratio, so 60% changes Lv1's 50% random transfer but has no effect on Lv2/Lv3's 100% shared pool.
- Impact: the relic description appears level-agnostic, while its mechanical value currently disappears at higher blue-split levels. Product design must decide whether the relic changes the shared pool, the owner's share, or only Lv1.

### Fission-slime trample violates occupancy invariants during overlap

- The trample transition begins with the player inside a 2x2 slime footprint, while `_cell_occupancy` stores only one unit per cell. Phase 36 rebuilds occupancy immediately after every successful relocation, so normal trample and spike-landing cases now finish with a valid index.
- Phase 36 also repaired the old all-blocked test: it had not blocked the full radius-2 search and passed on base trample damage without ever executing `space_squeeze`. The new case proves the squeeze event with a lethal 5-HP fixture and validates final invariants.
- A survivable target with every relocation cell blocked would still remain overlapped with the slime, which the single-occupant index cannot faithfully represent.
- Impact: ordinary and lethal-fallback paths are now verified, but the authored survivable fallback needs either a multi-occupancy transition model or a different product rule.

### A scalar intent damage value cannot summarize multi-hit gem combinations

- `IntentState.damage` can represent a single direct hit or a single explosion amount, but combinations such as light + explosion, split volleys, and echo follow-ups can damage one or more targets several times.
- Phase 30 makes ordinary explosion attacks use the configured explosion amount in preview and AI scoring. It deliberately leaves light-combination previews on their existing base value instead of claiming a misleading total.
- Phase 35 adds typed `IntentDamageComponent` entries with source, per-hit damage, instance count, predicted target applications, affected cells, and certainty. Deterministic direct, explosion, split, light, and light-composition paths now populate those entries; the old scalar remains a compatibility view of the first component.
- Phase 37 adds separate configured skill/collision components for fission-slime trample and makes player attack highlights consume the same structured profile used by enemy intent/AI.
- Remaining impact: arc bounces, random echo-selected tags, delayed status damage, defenses, and reactive redirection are not yet represented as components. The model can carry them, but the corresponding pure preview rules still need to be implemented before totals are exhaustive.

### Structured lethal preview is deliberately conservative, not a combat simulator

- Phase 37 predicts post-shield/vulnerable damage per component and can show black-death explosion cells for any structured lethal attack instead of only targets at 1 HP.
- Blue split, blue gravity, and an active red-counter mark make the lethal result uncertain, so the preview suppresses death-gem cells rather than guessing. Painkiller-style target relics, probabilistic reactions, black-death cascades, arc chains, and delayed status ticks are not simulated.
- Impact: player hover no longer owns a drifting damage threshold, but absence of a death preview does not guarantee survival when an unmodeled secondary effect can kill the target.

### Close-range split attacks can emit fewer shots than the configured level

- Detailed design requires red split to fire 3 / 4 / 5 shots. `SplitShotRules` adds a backward shot at Lv2 and a forward shot at Lv3, but an adjacent melee aim places the backward shot on the attacker's own cell and filters it out.
- As a result, the enemy-only `split_melee_attack` path resolves 3 / 3 / 4 cells rather than 3 / 4 / 5, while ranged split correctly resolves the configured counts when geometry permits.
- Phase 35 intentionally displays the resolved component count rather than the old hard-coded `x3`, so the UI no longer hides the discrepancy.
- Impact: the missing close-range projectile needs an authored placement rule. Choosing a replacement direction in code would invent formation semantics that the design table does not specify.

### Light endpoint explosions bypass red explosion level semantics

- The normal explosion attack path reads `blast_pattern` and `damage_multiplier` from the red explosion level row.
- The light + explosion composition always calls a raw cross blast at every beam endpoint with `explosion_cross_damage`, so additional red explosion gems do not change its shape or damage.
- Phase 35's structured preview mirrors this runtime behavior instead of claiming level scaling that execution does not provide.
- Impact: product design must confirm whether light carries the fully leveled explosion effect or a deliberately fixed endpoint burst before this composition can share the normal explosion resolver.

### Disarm lifecycle is not fully specified by design

- Detailed gem design says black counter Lv3 applies one stack of disarm, but does not define whether disarm blocks movement or the exact point at which a stack is consumed.
- Phase 31 models one stack as one blocked attack opportunity: attacks are gated, movement remains available, and the stack is consumed when the player's action window ends or the enemy finishes its action.
- Impact: the implementation is coherent and executable, but its lifecycle remains a product convention rather than fully authored design semantics. A later design decision may change turn timing without changing the configured stack count.

### Authored freeze semantics are not implemented

- Detailed gem design defines freeze as a distinct state with a one-turn skip, 25% extra incoming damage, and a 50% frostbite roll on thaw; frostbite then changes incoming and outgoing damage.
- Runtime still represents ice freeze as `paralyzed` plus slow. It has no frozen damage modifier and no frostbite state, and frostbite lifetime is not specified by the design source.
- Phase 29 deliberately downgrades the three red-ice contracts and black-ice Lv3 case to implementation observations rather than claiming design coverage.
- Impact: wet-target red ice, red Lv3, and black Lv3 are behaviorally incomplete and cannot be made authoritative by changing numbers alone.

### Paralysis turn consumption is inconsistent between player and enemy paths

- Enemy execution explicitly checks and removes `paralyzed` before skipping its action.
- Global turn-start ticking can expire a one-turn paralysis before the next player phase, while player attack and slot-operation services do not consistently gate on `StatusRules.can_act()`.
- Impact: paralysis and the current freeze placeholder need a dedicated turn-flow test and a single status-consumption path before skip-a-turn semantics can be trusted for both teams.

### Arc damage has competing or unused numeric authorities

- Phase 35 removes the unused `arc_hit_damage` config/accessor/fallback and makes the validator reject it, so the balance surface no longer exposes a value that has no runtime effect.
- Red conductive derives arc damage from the triggering attack and `arc_chain_damage_ratio`; blue conductive uses the damaged owner's full attack damage; black conductive uses `lightning_death_damage`.
- The numeric design only names a single "arc damage" entry and does not resolve whether these are intentionally distinct values or which configuration owns each path.
- Impact: the no-op authoring trap is gone, but balancing one conductive slot can still unexpectedly depend on unit attack stats. A product/numeric-design decision is still needed before consolidating or explicitly naming the three slot-specific models.

### Red counter can preempt and cancel incoming damage

- Detailed gem design says the marked target damages the watcher and then the watcher adds a normal attack. Runtime intercepts the incoming damage before HP loss, resolves the retaliation first, and cancels the original damage entirely if the retaliation kills its source.
- `skill_test.gd` explicitly protects this preemptive behavior, so it is not an accidental untested edge case. Phase 32 leaves the ordering unchanged while removing the unrelated level sentinel.
- Impact: changing retaliation order can alter lethal trades and Lv3 refresh outcomes. Product design must decide whether red counter is a post-hit retaliation or a preemptive interrupt before the implementation and contract can be made authoritative.

### Verify tooling is brittle on this Windows desktop environment

- Direct `./tools/verify changed` emits WSL startup noise in this workspace before running Godot.
- The command can still complete successfully, but the startup noise makes logs look scarier than the actual test result.
- Impact: verification remains usable, but the signal is noisier than it should be.

### Verify does not automatically reimport changed CSV translations

- After editing `localization/strings.csv`, `./tools/verify` can still run the older generated `.translation` resources and therefore miss or fail new runtime copy.
- Running Godot once in headless editor mode reimports the CSV and refreshes the actual runtime resource.
- Impact: localization-backed numeric-copy tests need an explicit import step before verification until the verify tool owns that preparation.

### Verify artifact logs can contain stale failures

- `artifacts/verify/report.json` and `artifacts/verify/verify.log` describe the latest `verify` run, but old per-test logs may remain beside them.
- A broad grep over `artifacts/verify/*.log` can therefore surface historical failures that were not part of the current run.
- Impact: debugging from artifacts requires checking the latest `verify.log` test list before treating any per-test log as current evidence.

### `battle_scene.tscn` still has invalid ext_resource UIDs

- `battle_renderer_timing_test` emits warnings that several `res://scenes/battle/battle_scene.tscn` ext_resource UIDs are invalid and Godot is falling back to text paths.
- Impact: the scene still loads, but asset references are carrying editor-level integrity debt that can create noisy warnings and fragile scene metadata.

### Full visual contract suite currently has overlay/water failures

- Strict `./tools/verify all` on 2026-07-11 passes 67 tests and fails the same 3 visual tests; all newly exposed combat, fixture, editor-path, and ordinary UI assertion failures were repaired in Phase 30.
- `overlay_render_contract_test` fails layer-order assertions: front overlay pass, unit UI, and selection outlines are not above the expected passes.
- `water_frame_composite_test` fails PNG save attempts under `/tmp/law_thief_water_frames/` and reports single-tile frame mismatches.
- `water_render_contract_test` fails to locate entity/unit draw commands and reports draw-order assertions for entities and unit UI.
- Impact: numeric-drive and changed-suite evidence is clean, but full visual contract health remains explicitly red and needs a separate visual/rendering phase.

### Debug-only seed display boundaries need an audit

- `scripts/ui/adventure_map_scene.gd` still renders `调试种子 %d`.
- This appears intentionally debug-facing, but the boundary between debug/editor UI and normal player UI needs to stay explicit.
- Impact: seed display is acceptable behind debug UI, but should not leak into normal run selection or player-facing HUD.

## Resolved / Mitigated

### Adventure progression and relic catalogs retained hardcoded defaults

- Phase 41 moves chapter count, map size, chapter seed stride, room weights/constraints, event pool, combat encounter pools, and chapter Boss sequence into one strict `adventure_progression.json`.
- The terminal layer is derived from map size, so changing the map no longer requires maintaining both `8` and `14`. Encounter/event ids are cross-validated against their authored catalogs.
- Map generation preserves the prior RNG consumption for fixed start/end nodes by explicitly authoring their compatibility weights.
- Relic definitions now require complete identity, rarity, pool, base-weight, uniqueness, and effect fields. Runtime no longer fabricates `common`, `global`, or weight `1` when authored values are absent.
- The placeholder relic remains the only catalog row allowed to have an empty pool, and that exception is explicit through `placeholder: true`.

### Gem-level consumers retained hidden numeric defaults

- Phase 40 replaces consumer-side `level_def.get(field, old_value)` calls with required reads from complete validated gem-level rows.
- Blue explosion turn-start damage and blue gravity redirect radius are now explicit level fields; the former remains recorded as a design conflict rather than being silently treated as authored semantics.
- Lawless attack bonus, water movement cost, and generic pathfinding weights moved to status/combat/AI configuration respectively.
- Split-shot bounds and black-split empty-cell search now derive from current board dimensions instead of fixed `0..7` and radius `4` limits.

### Core config loaders retained duplicate numeric defaults

- Phase 39 removes combat balance fallbacks from `Constants`; `CombatConfig` now accepts only a complete, valid `combat_config.json` and required accessors no longer carry duplicate values.
- `StatusConfig` no longer owns or deep-merges a complete `_DEFAULTS` table. Every registered status row explicitly authors stacks/duration and special multipliers in `status_config.json`.
- `AIProfiles` now loads aliases, tuning, complete profile defaults, and profile overrides solely from `ai_profiles.json`; unit profile references are validated against the resulting registry.
- Gem-pool rarity/tag weights, relic-source rarity weights, and enemy slot curves no longer have fabricated `DataRegistry` defaults. Economy and shop counts/prices were brought under the same strict whole-file policy.
- Review also fixed loaders that reported invalid gem-level, relic-ref, relic-def, reward, or reward-UI data but still assigned it in release builds. Invalid catalogs are now rejected before whole-table replacement.
- A patrol fixture was found passing only because missing identity fell through to old behavior defaults; it now identifies the authored unit and moves through `GameState`, keeping occupancy invariants valid.

### Primary content catalogs were shadowed by hardcoded registration

- `DataRegistry` previously registered complete in-code gem and unit catalogs, then deep-merged `gem_defs.json` and `unit_defs.json` over them. Missing fields and unreadable files silently inherited stale values.
- It also registered tutorial, template, and behavior-test encounters in code before replacing only encounter ids that happened to have JSON files. Four test encounters leaked through the same public catalog used by profile flags and the normal encounter picker.
- Phase 38 removes the three hardcoded catalog builders. Gem and unit JSON now pass complete schema, type, unknown-field, behavior-profile, effect-profile, and gem-reference validation before replacing the runtime catalog as a whole.
- Production encounters now load deterministically from `resources/encounters`; every file validates unit/tile/entity/overlay references, board bounds, weighted choices, and nested payload shape before parsing.
- The four behavior-test encounters live under `tests/fixtures/encounters`, load only in debug builds, and remain directly addressable while `catalog_visible: false` keeps them out of normal enumeration.
- `balance_config_test` proves runtime gem/unit ids exactly match the corresponding JSON keys, visible encounter ids exactly match production filenames, omitted/stale fields and bad references are rejected, and hidden fixtures remain loadable.

### Trample preview and execution had hidden numeric composition

- Fission-slime intent authored/displayed `trample_damage: 3`, while execution silently added a hard-coded `+1` collision amount and delivered 4. The no-space branch separately hard-coded 2 squeeze damage beside a fixed radius-2 search.
- Phase 37 adds `trample_collision_damage` to the unit balance row and exposes skill/collision as separate intent components. Preview text, structured total, and execution now all resolve 3 + 1 from the same unit data.
- Star relocation now reads maximum search distance and squeeze damage per tile from combat config, generates every outer ring from that radius, and derives the squeeze amount from those fields. Validation rejects unknown unit-balance keys and malformed relocation values.

### Player attack highlights duplicated gem geometry and guessed lethal HP

- `BattleQueryService` separately implemented light rays, split cells, explosion cells, and gravity range, then added black-death previews only when the hovered unit had `hp <= 1`.
- Phase 37 replaces that path with `IntentPreviewRules.build_red_attack_profile()`. Hover and no-hover attack previews use configured attack damage, shared gem geometry, per-hit shield/vulnerable mitigation, and conservative defense detection.
- A focused query contract proves 10 configured damage previews a 10-HP black explosion and that 1 shield removes the false lethal/death-gem area.

### Attack pipeline exposed a no-op piercing/final-damage path

- `AttackPipeline` computed `final_damage` after shield subtraction and recognized a `piercing` tag, but execution always sent `base_damage` to `CombatRules`; the computed value only appeared in optional trace output and piercing had no producer or authored design.
- Phase 37 removes the dead field, trace calculation, and unsupported tag. `CombatRules` remains the single shield-consumption authority; any future piercing mechanic must enter as an explicit transaction-level mitigation policy with contracts.

### Lethal damage context was lost before immediate and deferred death hooks

- Phase 36 introduces `DamageContext` as the canonical transport for source, reason, tags, gem context, and actual HP loss.
- `CombatTransaction`, `CombatRules`, damage events, and both death-hook queues now preserve the same normalized context. Split redirection, arc/light/explosion secondary paths, enemy gravity, collision damage, and forced spike entry have explicit propagation rules.
- Focused contracts prove direct and deferred fire+poison kills, a gravity-tagged wall-collision kill, canonical tag ordering/deduplication, and damage-event validation.

### Forced displacement could misclassify and double-settle spike entry

- Intermediate forced-move cells previously called tile entry without `forced/source` options, so a passed-through spike used normal 5 damage instead of configured collision damage 10 and omitted vulnerable.
- The final displacement cleanup then processed the landing entity a second time, allowing a landing spike to settle twice.
- Phase 36 carries forced/source/damage context through every moved-through cell and skips the already processed entity during final cleanup. Contracts prove both pass-through and landing spikes deal exactly one configured 10-damage hit and one vulnerable stack.

### Combat matrix fixtures bypassed occupancy mutation rules

- `attack_tag_combo_test.gd` directly assigned `player.pos` in all 128 cases. Cases with explosion or gravity printed occupancy invariant errors while still reaching the pass marker.
- Phase 36 routes fixture movement through `GameState.move_unit()` and explicitly validates events plus battle invariants for every matrix case.
- `fission_slime_test.gd` also now proves the actual `space_squeeze` branch instead of accepting unrelated base damage as evidence.

### Enemy counter/echo and custom damage intents could bypass attack dispatch or disarm

- `counter_attack` and `echo_attack` had authored enemy intents and execution handlers but were absent from `IntentSystem`'s attack dispatch list, so they could display without resolving damage.
- Fission slam/trample, lawless attacks, and bomb-rat plunder damage were also absent from the attack classification used by disarm.
- Phase 35 registers these damage intents consistently. Focused contracts prove counter/echo dispatch and prove a disarmed fission slime cannot retain a slam intent.

### Combat config exposed an unused fixed arc-hit value

- `arc_hit_damage` was validated and editable but had zero runtime call sites; active red arc damage uses `arc_chain_damage_ratio` instead.
- Phase 35 removes the config key, accessor, and fallback constant. A validator mutation test rejects the obsolete key.

### Black echo was suppressed by death-chain deduplication

- Normal black death effects mark each owner/tag pair as resolved for the active death chain. Black echo then tried to replay the same owner/tag pair and was rejected by that guard, so real lethal paths produced no additional effect.
- Phase 34 treats `echo_depth > 0` as an intentional replay while preserving ordinary death-chain deduplication and recursion guards. Black echo Lv1 now replays one selected death tag; Lv2 replays two distinct selected tags.
- The resolver chooses an empowered first tag from direct `first_tag_strength` / `first_tag_repeat_count` data rather than branching on `level >= 3`, and validation now requires both values to be positive integers.
- Real-death contracts prove two explosions at Lv1 and two conductive strikes plus two frost pulses at Lv2. Lv3's configured repeat remains an implementation observation pending empowered-tag design.

### Split levels had competing globals, inert sentinels, and duplicate clone state

- Before Phase 33, blue split levels stored only `spawn_temp_clone` / `even_redirect_distribution` booleans while ratio, radius, temporary-clone stats, HP, duration, and cap lived in globals or code. Black split cloned the full slot outline onto both children, synthesized a split gem, could erase an unrelated black gem, and then dropped the enemy originals as duplicates.
- Blue rows now directly author redirect mode, ratio, radius, and every temporary-clone parameter. Black rows author clone count and stat ratio. Cross-field validation rejects dormant non-zero clone knobs, active zero knobs, invalid ratios/counts, and the obsolete boolean sentinel.
- Black clones partition the original slots and gems exactly once, lock only actually inherited black split gems, scale speed with the rest of the stats, and suppress duplicate enemy drops. The fission-slime 50% unit override now composes as an explicit minimum over the level ratio.
- Red split execution and AI scoring share the same level-row ratio, and player relic overrides no longer leak onto enemy units. Five new executable design contracts cover blue Lv1/Lv2 and black Lv1-Lv3, raising coverage from `66 / 90` to `71 / 90`.

### Red counter encoded behavior through a fake stack count

- Before Phase 32, red-counter rows authored `mark_stacks: 1/2/3`, but the status did not have meaningful stacks. Runtime stored that number as a hidden level sentinel and branched on `>= 2` for tagged retaliation and `>= 3` for kill refresh.
- The level rows now directly author `mark_duration`, `retaliation_with_tags`, and `grant_extra_attack_on_kill`. The mark payload stores those semantics, and the resolver no longer infers gameplay from an ordinal number.
- Legacy mark payloads containing `level` remain readable for active-save compatibility, but new authored data and runtime state no longer produce the sentinel. The obsolete status `default_level` fallback was removed.
- Executable Lv2/Lv3 contracts prove tagged retaliation through the complete fire-composition path and attack refresh after a lethal retaliation. Coverage rises from `64 / 90` to `66 / 90`.

### Gem-effect level data could be incomplete or silently ignored

- Before Phase 31, most slot/tag rows could omit a level or known field and fall back to plausible runtime defaults; a field valid for another gem family could also be accepted. The entire `black:counter` group was absent even though detailed design defined all three levels.
- Phase 31 gives all 30 slot/tag groups an explicit schema, requires levels 1/2/3 and every semantic field, supports only declared optional fields, and rejects unknown levels plus cross-group fields. Mutation tests cover missing groups, levels, fields, and misplaced fields.
- The black-counter rows now author reflection multiplier, vulnerable duration, and disarm stacks. Runtime reads all three, and a field-to-read audit found a consumer for every field currently declared in `gem_effect_levels.json`.
- Three executable contracts prove reflection uses actual HP lost rather than overkill damage, Lv2 applies vulnerable, and Lv3 applies disarm that blocks a follow-up attack. Coverage rises from `61 / 90` to `64 / 90`.

### Verify could report assertion failures as passing tests

- Godot can log `SCRIPT ERROR: Assertion failed` and still exit with code 0, so Phase 29's wrapper summary incorrectly reported three failing selected tests as passing.
- Phase 30 makes `tools/verify` require both a zero exit code and a log without `SCRIPT ERROR:`. It reports the failure reason and tails the failing log when either condition fails.
- The hidden failures were resolved at their source: gravity fixtures now register occupancy, diagonal pull expects the shared stop-before-blocker rule, the obsolete fourth-stack explosion assertion was removed, and stone-bow preview now matches configured explosion execution.
- Strict `verify fast` and `verify changed` both pass `23 / 23`; strict `verify all` now reaches a complete `67 / 70` result instead of stopping at the first non-zero test, and its three failures are the visual contracts tracked above.

### Full-suite tests depended on obsolete fixtures and platform-specific paths

- Strict verification exposed five additional false-green areas: enemy bonus actions used a removed temp flag, iron boots lacked an active run, enemy-red tests used out-of-bounds or ambiguous positions, editor import wrote to Unix `/tmp`, and relic hover textures were initialized in a different order from normal textures.
- Phase 30 migrates the tests to `StatusRules.grant_extra_attack()`, starts an isolated run for relic ownership, uses valid deterministic range boundaries and semantic damage-event selection, writes editor payloads through `user://`, and aligns both relic texture rect initialization paths.
- Direct repaired tests pass cleanly, and the strict full suite confirms all five are now green.

### Explosion preview and execution had duplicate numeric authorities

- Attack execution read red explosion shape/multiplier from the level table, while active triggering still derived multipliers from raw gem count and ordinary enemy previews used base attack damage.
- Phase 30 centralizes blast shape, damage multiplier, and scaled damage in `GemEffects`; attack execution, active triggering, black-death execution, intent preview, and AI scoring now share that resolver.
- Red and black explosion rows now require their semantic fields. Black Lv3 owns its `damage_multiplier: 2.0`, and the localized level summary renders the same multiplier.
- Counts above the authored maximum clamp to Lv3 in both ordinary attacks and active triggering, matching the detailed 1/2/3-level design.

### Ice and conductive death radii shared a misleading global key

- `ice_death_radius` controlled both black ice and black conductive despite belonging by name to only one mechanic.
- Phase 29 moves the values into `death_radius` on black-ice rows and `strike_radius` on black-conductive rows, then removes the global combat key, accessor, and constant.
- Required-field validation and runtime lookups now keep each radius beside the behavior it controls.

### Ice level 2 could not author a zero movement floor

- Detailed ice design allows red/blue Lv2 slow to reduce movement to zero, while the global slow status intentionally retains a minimum of one for ordinary sources.
- Phase 29 adds `slowed_min_move_points` to red/blue ice rows and carries the strongest lower floor in the slow status payload when effects stack.
- Blue contracts prove Lv1 retains a floor of one, Lv2 can reach zero, and Lv3 only applies sluggish when the contact target was already slowed.
- Black ice Lv1/Lv2 contracts prove the configured 3x3 boundary, sluggish effect, and Lv2 slow. Net semantic coverage increases from `59 / 90` to `61 / 90` after removing three overstated red-freeze rows from the verified set.

### Relic numeric refs were skipped by branch guards

- `relic_empty_shell` authors `per_empty_slot_ref`, but `_eval_modifier_entry()` previously entered the calculation only when the obsolete inline `per_empty_slot` field existed.
- Phase 29 recognizes inline or referenced forms for `per_empty_slot`, `empty_slot_mult`, and `rng_chance` before resolving the value.
- The previously false-green status assertion now passes and proves two empty slots produce the configured +2 range bonus.

### Black conductive used a fake count sentinel for all-target mode

- Black conductive Lv3 stored `strike_count: 999` even though runtime used `strike_all_targets: true` and ignored the count.
- Phase 29 removes the sentinel. Counted targeting now requires a positive count, all-target targeting forbids one, and player-facing summaries render “all targets” instead of 999.

### Black fire balance was split between global bases and per-level bonuses

- Phase 28 replaces `fire_death_fire_count` / `fire_death_radius` plus level bonuses with complete per-level `death_fire_count`, `death_fire_radius`, and `death_fire_duration` values in `gem_effect_levels.json`.
- The black-death runtime reads only the active level row. Obsolete combat-config keys, accessors, and constants were removed, and the HUD/query summary now displays the same absolute values.
- `validate_combat_config()` now rejects unknown keys, so removed or misspelled global knobs cannot remain as convincing but inert data.
- Black-fire rows require all four semantic fields and validate radius, count, and duration as integers with positive count/duration.

### Blue and black fire level semantics lacked executable contracts

- Phase 28 adds four blue-fire cases and three black-fire cases, covering all six design rows and the blue Lv3 once-per-turn cap.
- Blue contracts prove the composed overlay behavior: Lv2 contact applies one stack directly and one from fire created under the attacker; Lv3 doubles the combined stack total only once in the turn.
- Black contracts prove five-fire empty-cell preference, occupied-cell preference at Lv2, the exact two-tile radius, and Lv3's seven fires with three-turn duration.
- Semantic-contract coverage increased from `53 / 90` to `59 / 90`.

### Semantic contract per-case reporting could print false passes

- The contract runner previously compared a global boolean before and after each case. Once any case failed, later failing cases could still print `CONTRACT_PASS` because the boolean remained true.
- Phase 28 tracks a monotonic failure count per case, so a case is counted and printed as passing only when it adds no failures.

### Blue and black conductive level semantics lacked executable contracts

- Phase 27 added six fixed-seed contract cases across blue and black conductive levels.
- Blue cases prove Lv1 can fail its 33% rebound, Lv2 can trigger its 66% rebound, and Lv3 always rebounds; black cases prove one random strike, two non-repeating strikes, and the Lv3 all-target strike.
- The black cases assert true-damage results and lightning event counts through the real owner-death hook, not an isolated helper.
- Semantic-contract coverage increased from `47 / 90` to `53 / 90`.
- The contracts intentionally preserve the observed slot-specific damage sources and surface their unresolved ownership conflict in the open issue above.

### Black gravity level semantics lacked executable contracts

- Phase 26 added fixed-seed contract cases for black gravity at every level: Lv1 pulls a neighboring unit one tile, Lv2 also applies slow, and Lv3 also applies one-turn root.
- The cases assert final position and status state after the mounted target dies, so the pull is proven through the real death-effect path rather than a helper-level imitation.
- Semantic-contract coverage increased from `44 / 90` to `47 / 90`.
- Blue gravity remains intentionally excluded: its post-hit redirect/slow/root behavior conflicts with the detailed design's projectile-deflection-only model and is tracked in `semantic-conflicts.md`.

### Blue explosion blast-shape config was ignored at runtime

- Phase 25 found that blue explosion entries configured as `blast_pattern: cross` still executed the square `_explode_at()` path for both damage and forced-displacement triggers.
- Both paths now share `_append_blue_explosion_by_pattern()`, which uses `explode_cross_at()` for the authored cross shape and `explode_square_at()` for square.
- New executable contracts cover blue explosion's normal-hit gate, burning trigger, cross/square level progression, black death blast, level-2 chain, and level-3 main-blast multiplier behavior.
- The semantic contract suite now verifies `44 / 90` design rows.

### Battle HUD gem-level copy was a separate, drifting numeric authority

- Phase 22 replaced `gem.level.{tag}.{level}` HUD lookups with `DataRegistry.get_gem_effect_level_summary(tag, slot_type, level)`.
- New localization templates are scoped by red/blue/black slot and contain only semantic wording plus placeholders; their values are formatted from `gem_effect_levels.json` at runtime.
- The old tag-only numeric localization keys were removed so future code cannot accidentally reconnect to a second numeric authority.
- `gem_level_context_test` proves red split Lv2/Lv3 display configured 50%/30% values and verifies the actual `BattleHudPresenter` detail lines no longer contain the stale 70% copy.
- Phase 23 extended the same summary path to battle query previews.

### Battle query previews used generic gem effect descriptions

- Phase 23 added a context-aware `_slot_effect_summary()` adapter in `BattleQueryService`.
- Unit-slot previews, tile-slot previews, and black-death previews now resolve the owner tag level from `GameState` and reuse `DataRegistry.get_gem_effect_level_summary()`.
- When an effect intentionally has no authored level definition, the old generic description remains only as a safe fallback.
- `gem_level_context_test` verifies the query preview for red split Lv2 shows configured 50% and not the stale 70% copy.

### Echo tag selection count was hard-coded by level

- Phase 24 added `echo_tag_count` to every red/blue/black echo level entry in `gem_effect_levels.json`.
- `GemEchoRules.resolve_echo_tags()` now reads that count from the active slot scope rather than owning the old `1 / 2 / 2` rule.
- Red echo now explicitly configures its zero follow-up ratios at Lv1/Lv2; its Lv3 50% follow-up remains authored alongside the selected tag count.
- The gem effect validator requires `echo_tag_count` to be a positive integer, and `gem_echo_test` proves runtime selection count follows the config.

### Gem effect level config accepted semantically invalid numeric values

- Phase 21 strengthened `BalanceConfigValidator.validate_gem_effect_levels()` beyond basic JSON types.
- It now rejects unknown slots/tags, invalid blast/fog shapes, fractional or negative discrete values, out-of-range chance/ratio values, non-positive visual/damage multipliers, and duplicate split direction offsets.
- `balance_config_test` covers representative invalid enum, count, probability, ratio, multiplier, tag, slot, and direction data.
- This protects configured numeric inputs at load time; it does not yet solve the HUD text drift tracked above.

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
