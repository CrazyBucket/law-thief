# Known Semantic Conflicts

These conflicts must be surfaced when related behavior changes. Do not silently pick the current
implementation merely because existing tests pass.

## Explosion Stack Levels (Resolved In Phase 30)

- Detailed gem design defines only levels 1/2/3: cross / 3x3 / 3x3 with 2x damage.
- Runtime previously split authority: the normal attack pipeline used the authored level table, while an active-trigger helper derived `count - 1` and could turn a fourth stack into 3x damage. A stale test asserted that extension.
- Phase 30 resolves the conflict in favor of the detailed design. Every execution path resolves the clamped tag level and reads shape/multiplier from `gem_effect_levels.json`; four or more copies remain at authored Lv3 behavior.
- Dynamic localization now renders the configured multiplier rather than owning a separate doubled/tripled sentence.

## Older MVP Numbers

`Prototype_MVP.md` and parts of `Technical_Architecture.md` contain older prototype damage values,
such as 2-point explosion examples. Current detailed gem and numeric design specify 12 damage.

Default authority: detailed gem and numeric design.

## Fire And Poison Fog Reaction

- `详细设计/宝石/宝石_v1.md` says fire + poison creates toxic smoke for 1 turn, with both fire and poison fog effects.
- `详细设计/地块/地块.md` says poison fog disappears when it encounters fire or explosion.
- Product direction on 2026-06-17 explicitly expects fire to create toxic smoke when it meets poison fog.
- `blue_black_combo_test.gd` currently expects some black-death `explosion+poison+fire_gem`
  combinations to increase the raw `poison_fog` tile count, but the implementation converts those
  cells to `toxic_smoke` when poison fog enters fire. This failure exists on `HEAD` before the
  combat transaction damage refactor.

Default authority: detailed gem design plus current product direction. Current implementation treats fire entering poison fog and poison fog entering fire as the same reaction: consume fire/poison fog and create `toxic_smoke`. Water still takes precedence over this reaction.

## Blue Gravity Trigger Model

- Detailed gem design defines blue gravity as ranged-projectile deflection: 50% at level 1, 75% at level 2 with enemy/ground targeting, and 100% at level 3.
- `gem_effect_levels.json` additionally defines `slow_on_damaged` and `root_on_damaged` fields.
- `AttackPipeline._try_deflect()` performs pre-hit projectile deflection using `deflect_chance` and `redirect_enemy_only`.
- `GemEffects._run_unit_damaged_effect()` separately redirects damage to an adjacent unit and applies the slow/root fields after the target has already been damaged; this path does not read `deflect_chance` or `redirect_enemy_only`.

Default authority: detailed gem design. Do not add blue-gravity semantic contracts or alter its behavior until product design decides whether the post-hit redirect/slow/root behavior is an intentional extension or implementation debt.

## Ice Slow Minimum Movement

- `详细设计/宝石/宝石_v1.md` says red and blue ice at level 2 apply two slow stacks and may reduce movement to `0`.
- `GDD.md` describes slow as having a minimum movement of `1`, and `详细设计/怪物/精英怪设计1.md` repeats that minimum for the elite's level-1 blue ice.
- Runtime previously used the global `status_config.slowed.min_move_points = 1` for every slow source and therefore could not express the level-2 exception.

Default authority: the detailed gem design for level progression. Red/blue ice level 1 and non-ice slow sources retain the global minimum of 1; red/blue ice levels 2 and 3 author an explicit minimum of 0 in their level rows.

## Freeze Is Not Paralysis

- `详细设计/宝石/宝石_v1.md` defines freeze as a distinct one-turn state: skip the unit's turn, take 25% extra damage, then have a 50% chance to gain frostbite on thaw.
- The same source defines frostbite as 25% extra incoming damage and 25% lower outgoing damage, but does not state its duration or removal rule.
- Current runtime maps every ice freeze branch to `paralyzed` plus slow. It does not apply the 25% frozen damage modifier, does not create frostbite, and presents the status as paralysis.
- Existing red-ice semantic contracts only assert that placeholder paralysis and therefore do not prove the authored freeze rule.

Default authority: the detailed gem design. Treat the current paralysis path as an incomplete implementation, not verified freeze semantics. Do not count red ice rows or black ice level 3 as design-covered until freeze/frostbite are modeled and frostbite lifetime is decided.

## Red Counter Retaliation Ordering

- `详细设计/宝石/宝石_v1.md` says that after the marked target damages the watcher, the watcher adds a normal attack.
- `CombatRules.apply_damage()` currently resolves the counter mark before applying the incoming damage. If the retaliation kills the damage source, the original damage returns zero and never reaches the watcher.
- `skill_test.gd` explicitly asserts this preemptive kill and damage cancellation, while the ordinary counter test describes the effect as a follow-up.
- Phase 32 removes the fake `mark_stacks` level sentinel but deliberately preserves this ordering conflict.

Default authority: the detailed gem design suggests post-hit retaliation, but it does not explicitly define lethal-trade behavior. Do not reorder red counter or change whether lethal retaliation cancels incoming damage until product design resolves that edge case.

## Black Split Slot Inheritance (Resolved In Phase 33)

- `详细设计/宝石/宝石_v1.md` says two death clones evenly partition the source slots and inherit gems in their assigned positions; inherited black split gems become disabled and locked.
- Runtime previously copied the full slot outline to both clones, copied only selected gems, then forced a synthetic split gem into each clone's first black slot. This duplicated slots, could replace an unrelated inherited black gem, and allowed enemy source gems to drop after cloned copies had already been created.
- Phase 33 resolves the conflict in favor of the detailed design. The children collectively inherit one copy of the source slot/gem set, and only an actually inherited split gem is disabled and locked. Enemy originals that were inherited are consumed instead of also dropping.

Default authority: detailed gem design. The former full-outline behavior and its regression assertion are obsolete.

## Blue Split Temporary Clone Lifecycle

- `详细设计/宝石/宝石_v1.md` defines one 1-HP clone with 30% stats, a one-turn lifetime, and a once-per-turn trigger, but does not define player control or the exact phase boundary of that lifetime.
- Current runtime creates a same-team clone after surviving damage. It is intentionally excluded from black split inheritance/merge and from the player split-clone fallback queue, but a player-owned clone is not otherwise given a controllable action.
- Phase 33 verifies the numeric row and once-per-turn implementation as an observation, not as complete authored semantics.

Default authority: detailed gem design for the numeric values. Do not count blue split Lv3 as design-covered until product design specifies whether the clone acts and when its lifetime expires for each team.

## Slime Crown Versus Blue Equal Sharing

- The relic description presents blue split as a 60% transfer override without limiting it to a level.
- Blue split Lv2/Lv3 instead define full equal sharing among the owner and all nearby units. The current maximum-override rule leaves the 100% shared pool unchanged, so the relic affects Lv1 only.

Default authority is unresolved. Product design must define whether the relic modifies the shared pool, share weights, or only random-transfer mode before changing runtime or player-facing copy.

## Black Light Settlement Model

- `详细设计/宝石/宝石_v1.md` defines black light as clearing all exposed targets and applying effects based on the lethal attack's tags. Lv2 adds one level of effect strength; Lv3 additionally blinds.
- Phase 36 propagates canonical lethal gem tags and resolved gem context through immediate and deferred death hooks, including redirected, collision, and status damage. Diagnostic black-light beam events prove the tags arrive intact.
- Runtime still deals direct damage from the dead owner's attack and exposure stacks, while Lv2 changes only beam width. No authored mapping defines what fire, poison, gravity, arc, split, or other lethal tags settle, or what “effect strength +1” means for each result.
- The former black-light Lv3 contract proved the direct-damage placeholder and blind, not the authored tag settlement, so Phase 34 no longer counts it as design coverage.

Default authority: detailed gem design. Transport is complete, but do not add black-light design coverage or invent a settlement formula until per-tag and strength semantics are authored.

## Lethal Damage Tag Attribution

- The design requires black light to inspect lethal-damage tags but does not define attribution for composed secondary damage.
- Phase 36 uses a documented implementation policy: primary red attack components carry all resolved active tags; arc and gravity secondary damage use their narrow mechanism tag; explosion-driven collision uses `explosion`; fire/poison ticks infer their status tag; split redirection preserves the incoming context.
- Ambiguous cases remain: whether split redirection should also add `split`, whether dyed light retains every carried tag, and whether a spike kill reports the initiating displacement tag, a hazard tag, or both. The gem tag vocabulary currently has no spike/hazard tag.
- Bomb-rat `black_suicide` intentionally remains untagged because detailed monster design says it force-triggers whichever black-slot abilities are mounted rather than defining the self-kill as explosion damage.

Default authority is incomplete. Preserve the Phase 36 policy as an explicit implementation convention, not product truth, until composition and hazard attribution are authored.

## Fission-Slime Trample No-Space Fallback

- `详细设计/机制/碰撞.md` says that when star relocation finds no legal cell, the target takes damage equal to the displacement distance and is then forcibly reset to the nearest cell. It does not define how a “nearest” cell can be chosen or occupied after every legal radius-2 candidate was declared blocked.
- The same section calls the distance-2 outer ring “12 cells”, while a complete Chebyshev/square radius-2 perimeter has 16 cells. The former runtime scanned all 16, and Phase 37's configurable ring generator deliberately preserves that ordering and count.
- Trample begins with the target inside the fission slime's 2x2 footprint, but `GameState._cell_occupancy` represents only one live unit per cell and the invariant checker forbids overlap.
- Runtime currently applies a fixed 2-point squeeze penalty and leaves a survivor at the overlapped origin. Phase 36 repairs occupancy after successful relocation and verifies a lethal all-blocked fallback, but a surviving fallback cannot be represented faithfully.

Default authority: collision design for the intended penalty, but the outer-ring shape, final-cell rule, and architecture are unresolved. Do not remove four candidates, hide the overlap, evict an arbitrary blocker, silently move a survivor, or weaken occupancy invariants without authored geometry/tie-break rules and an explicit transaction design.

## Exposure Lifetime

- `GDD.md` says exposure lasts until the end of the current turn.
- The higher-authority detailed gem document does not specify duration, and runtime stores exposure with zero duration until black light removes it.

Default authority is incomplete. Preserve the current lifetime only as an implementation observation until detailed design confirms end-of-turn expiry or persistent exposure.

## Blue Light Extra-Beam Targeting

- `GDD.md` says the reflected direction is opposite the incoming hit direction, which supports reflecting the first beam toward the attacker.
- Detailed design says Lv2 reflects two beams and Lv3 reflects three while preferring enemy directions. Runtime targets enemy units for every available beam at all levels and emits fewer beams when there are too few units.

Default authority: detailed gem design plus the GDD clarification for the first beam. Extra-beam direction selection and empty-ray behavior need explicit rules before blue-light rows are counted as fully covered.

## Echo Lv3 Empowerment

- Detailed design says one of the two selected tags is empowered, without defining what empowered means for each tag.
- Runtime currently uses a generic 50% follow-up hit for red, strength 2 in a partial blue tag switch, and one extra execution for black.
- Phase 34 removes red echo Lv3 from design coverage and keeps black echo Lv3 as an implementation observation. Black Lv1/Lv2 normal replay semantics are unaffected and executable.

Default authority: detailed gem design. Product design must define a generic empowerment rule or per-tag empowered effects before the three Lv3 echo rows can be made authoritative.

## Close-Range Split Shot Count

- `详细设计/宝石/宝石_v1.md` requires red split to produce 3 / 4 / 5 shots.
- The current geometry uses a backward extra shot at Lv2. For the enemy's adjacent-only split action, that shot lands on the attacker's occupied cell and is discarded, producing 3 / 3 / 4 resolved cells.
- Ranged split can produce all 3 / 4 / 5 shots, so the conflict is specific to close-range placement rather than the level table.

Default authority: detailed gem design. Do not claim close-range Lv2/Lv3 shot-count coverage or choose a substitute direction until the intended four/five-shot formation is authored.

## Light And Explosion Level Composition

- Red explosion levels author blast shape and damage multiplier for the explosion tag.
- The light + explosion composition currently emits a fixed cross burst with base explosion damage at each beam endpoint, bypassing those level fields.
- Existing design sources specify the individual tags but do not state whether a transported endpoint explosion keeps its full level semantics.

Default authority is incomplete for the composition. Preview should remain honest to runtime, but design coverage and a behavior change require an explicit rule for transported explosion level/shape.

## Blue Explosion Turn-Start Aura

- `详细设计/宝石/宝石_v1.md` defines blue explosion as reacting to fire or forced displacement at Lv1, then to any damage at Lv2, with a larger blast at Lv3.
- `gem_defs.json` also assigns explosion to the legacy `blue_turn_start` ability slot, and runtime deals one point to the first adjacent enemy at the holder's turn start.
- Phase 40 moves that existing one-point amount into the complete blue-explosion level rows as `turn_start_damage`, so it is no longer a hidden code literal. It deliberately does not remove the trigger or count it as authored semantics.

Default authority: the detailed gem design does not support a turn-start aura. Preserve current behavior only as an explicit compatibility observation until product design either removes `blue_turn_start` from explosion or authors its targeting, damage scaling, and relationship to the reactive blast.
