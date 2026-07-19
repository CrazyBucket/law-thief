# AI Working Agreement

## Verification Cadence

Do not run tests before editing unless the task is specifically to reproduce or diagnose a failure.
Start with read-only inspection. Before changing battle or gem behavior, gather design context with:

```bash
./tools/context <relevant Chinese or English terms>
./tools/design affected
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
```

After editing, run the smallest relevant test with `./tools/verify test <test_name>`. Use
`./tools/verify changed` only when several related files changed or no single test represents the
impact. Do not run `fast` or `all` by default: `all` is reserved for CI or an explicit user request,
and `fast` requires a concrete cross-system risk that focused tests cannot cover. State that reason
before starting either suite. Manual probes and stress tests run only through
`./tools/verify manual`. `verify` already refreshes semantic coverage, so do not follow it with a
separate `coverage` run. Use `./tools/verify changed --list` to inspect selection without Godot.
Machine-readable output is written under `artifacts/verify/`.
Only executable cases in `tests/contracts/gem_semantics.json` count as semantic verification.
Green ordinary tests do not imply that uncovered gem semantics are correct.

## Design Context And Documentation Sync

`DESIGN_INDEX.md` in the external design root is the single entry point for humans and AI.
Do not hand-edit generated `AI_CONTEXT*.md` files. Use:

```bash
./tools/design find <terms>
./tools/design topic <terms> [--copy]
./tools/design build
./tools/design check
./tools/design affected
./tools/design sync-check --strict
./tools/design refresh
```

Before changing product behavior or numeric semantics, run `design affected` and read the listed
authority sources. Update the matching authoritative design document in the same task as the code,
then run `design refresh` to rebuild and check the generated chat contexts. Generated contexts are
local ignored artifacts. `verify` refreshes them and runs the strict design sync guard when the local
design repository is available. For a pure refactor with provably unchanged behavior, set a
non-empty `DESIGN_SYNC_SKIP_REASON` for that verification run; do not use it for unfinished docs.

The design tool locates a sibling `learning-notes/game/design/law-thief` checkout by default and
also accepts `DESIGN_ROOT`. Windows users can run the same commands through `tools\design.cmd`.

## Design Semantics

The external design root is normally discovered as:

```text
../learning-notes/game/design/law-thief
```

If the repositories are not siblings, set `DESIGN_ROOT` to the absolute design directory. The
legacy `/Users/jinhuiwu/code/learning-notes/game/design/law-thief` path remains a fallback.

Read sources in this order:

1. `详细设计/宝石/宝石_v1.md` for gem slot/count behavior.
2. `详细设计/数值/数值设计_v1.md` for formulas and numeric intent.
3. `GDD.md` for current product intent.
4. Repository tests and implementation describe current behavior, not necessarily correct semantics.

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
- transaction trace for state mutations routed through `CombatTransaction`;
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

## Overlay And Texture Visual Spec

- Only when the task directly involves overlay art, board-surface textures, or overlay/tile shader visuals, read `docs/ui-overlay-art-spec.md`.
- Do not read that spec for unrelated combat logic, economy, localization, or general scripting tasks.

## Visual Asset Source Rules

- AI agents must not hand-author SVG assets. Do not write SVG XML, assemble vector paths, trace shapes into SVG, or generate SVG markup through scripts.
- Do not use a hand-authored SVG as an intermediate step and rasterize it to bypass this rule.
- Reuse approved project art when suitable. When a new visual asset is required, use the available image generation or image editing workflow and deliver a normal raster asset such as PNG or WebP.
- Programmatic drawing is acceptable only for runtime rendering, shaders, debug probes, or explicitly requested procedural visuals; it must not be checked in as a substitute for authored art.
- Existing SVG assets may remain in the project, but agents must not create new ones or materially redraw them unless the user explicitly overrides this rule.

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
tools/combat_architecture_guard  static transaction/event mutation guard
tools/test_log_guard            strict Godot runtime-error log gate
tools/ui_architecture_guard     query/presenter/board overlay boundary gate
tools/player_copy_guard         player/debug copy boundary and localization-policy gate
tools/persistence_architecture_guard test/tool player-save isolation gate
tools/ui_visual_regression      capture/compare fixed UI scenarios at three resolutions
scripts/rules/gem_effects.gd     gem effect execution
scripts/rules/gem_tag_resolver.gd gem count/level semantics
scripts/rules/attack_pipeline.gd attack calculation and tags
scripts/services/procedural_encounter_generator.gd deterministic normal-battle generation
resources/gems/                  gem definitions and pools
```
