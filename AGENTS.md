# AI Working Agreement

## First Commands

Run these before changing battle or gem behavior:

```bash
./tools/context <relevant Chinese or English terms>
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/coverage
./tools/verify changed
```

Use `./tools/verify fast` while iterating and `./tools/verify all` before broad battle changes.
Machine-readable output is written under `artifacts/verify/`.
Only executable cases in `tests/contracts/gem_semantics.json` count as semantic verification.
Green ordinary tests do not imply that uncovered gem semantics are correct.

## Design Semantics

The external design root is:

```text
/Users/jinhuiwu/code/learning-notes/game/design/law-thief
```

Read sources in this order:

1. `详细设计/宝石/宝石_v1.md` for gem slot/count behavior.
2. `详细设计/数值/数值设计_v1.md` for formulas and numeric intent.
3. `GDD.md` for current product intent.
4. `Technical_Architecture.md` for architecture and invariants.
5. Repository tests and implementation describe current behavior, not necessarily correct semantics.

When sources conflict, explicitly report the conflict before changing behavior. Do not silently
make implementation, tests, and localization agree with an assumption.
Known unresolved conflicts are recorded in `docs/ai/semantic-conflicts.md`.

## Snapshot Probe

Create an initial encounter snapshot:

```bash
./tools/snapshot --encounter tutorial_001 --seed 1
```

Create a deterministic gem combat probe:

```bash
./tools/snapshot \
  --gems gem_explosion,gem_explosion,gem_explosion \
  --slot red \
  --action attack
```

The result is `artifacts/verify/snapshot.json`. It contains:

- design source paths and authority order;
- before/after battle state;
- compact state diff;
- emitted events;
- battle and event invariant violations.

## Testing Rules

- Prefer `ScenarioBuilder` over copying unit/gem fixture helpers.
- Prefer `StateSnapshot` and `StateDiff` when diagnosing stateful failures.
- Every scenario should validate battle invariants and event shape.
- Use fixed seeds.
- A test must encode an explicit design rule, not duplicate an implementation formula.
- When changing gem semantics, update the design document or call out why it cannot be updated.

## UI Copy and Comments

- Player-facing text must sound like game UI, not debug output, implementation notes, or AI-generated instructions.
- Do not show internal ids, coordinates, seeds, room ids, event ids, script names, or rule ids in normal player UI. Put them behind debug/editor UI only.
- Keep persistent UI copy short and state-based: one label should express one thing such as state, command, result, or warning.
- Prefer in-world terms: room, route, threat, slot, gem, intent, reward. Avoid engineering terms like node, payload, event id, hover, or schema in player-facing text.
- Do not use long instructional strings as permanent HUD text. First-time tutorials and tooltips may explain controls; the main HUD should show the current choice or result.
- New player-facing strings should go through localization data, or the change must explicitly explain why temporary hard-coded text is acceptable.
- Code comments should explain design intent, invariants, ordering constraints, or non-obvious tradeoffs. Do not add comments that merely restate what the next line of code does.
- When touching UI, check visual hierarchy, color semantics, overlap, and whether debug-only details are leaking into the normal player experience.

## Battle State Mutation Rules

- Do not add new direct `unit.pos = ...` writes in battle rules, AI, or presentation code except constructors, clones, import/deserialization, or documented no-side-effect planning helpers.
- Use `GameState.move_unit()` for existing movement until `CombatTransaction` is introduced, so `_cell_occupancy` stays synchronized.
- New movement events must include `type`, `uid`, `from`, and `to`; avoid writing ad hoc `move_step` dictionaries in multiple places.
- New damage events must include the victim identity (`uid` and/or `victim_uid`) in addition to `pos`, `damage`, and `is_crit`.
- Presentation-state application must preserve the same invariants as real state. If a display state moves a unit, its occupancy index must move too.
- AI preview/scoring should use no-side-effect position helpers instead of temporarily mutating a real `UnitState`.
- The staged plan for this work lives in `docs/combat-transaction-refactor-todo.md`.

## Relevant Paths

```text
scripts/testkit/                 reusable scenario, snapshot, and diff helpers
scripts/tools/ai_snapshot.gd     one-command AI probe
scripts/debug/                   runtime invariant validators
scripts/rules/gem_effects.gd     gem effect execution
scripts/rules/gem_tag_resolver.gd gem count/level semantics
scripts/rules/attack_pipeline.gd attack calculation and tags
resources/gems/                  gem definitions and pools
```
