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
