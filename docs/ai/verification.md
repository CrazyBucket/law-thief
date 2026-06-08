# AI Verification

## Commands

```bash
./tools/context 爆炸
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/coverage
./tools/verify changed
./tools/verify fast
./tools/verify all
```

`snapshot.json` is intended as the fastest debugging artifact. It records the state before and
after a deterministic action, a compact diff, events, invariant failures, and authoritative design
document paths.

`semantic-coverage.json` is the trust boundary. A gem/slot/level is `VERIFIED` only when an
independent expectation from the design document exists in `tests/contracts/gem_semantics.json`
and passes `gem_semantic_contract_test.gd`. Everything else is reported as `UNVERIFIED`.

## Adding Focused Tests

Use `ScenarioBuilder` to create a deterministic state, execute a public rule entry point, then use
`StateSnapshot.capture()` and `StateDiff.between()` to explain the result. Avoid adding another
private copy of helpers such as `_spawn_guard` or `_mount_gems`.

## Semantics

The repository intentionally treats implementation and existing tests as evidence of current
behavior, not as the final semantic authority. Detailed design documents under
`/Users/jinhuiwu/code/learning-notes/game/design/law-thief/详细设计` win by default. Any conflict must
be surfaced rather than silently normalized.
