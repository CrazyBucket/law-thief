# Known Semantic Conflicts

These conflicts must be surfaced when related behavior changes. Do not silently pick the current
implementation merely because existing tests pass.

## Explosion Stack Levels

- Detailed gem design says red explosion count 1/2/3 means cross / 3x3 / 3x3 with 2x damage.
- Current implementation also permits a fourth stack and turns it into 3x damage.
- Existing `explosion_test.gd` explicitly tests the fourth-stack behavior.
- Localization describes level 3 inconsistently: Chinese says `伤害加倍`, while English says
  `damage tripled`.

Default authority: the detailed gem design. Treat fourth-stack behavior as an implementation
extension until product design confirms it.

## Older MVP Numbers

`Prototype_MVP.md` and parts of `Technical_Architecture.md` contain older prototype damage values,
such as 2-point explosion examples. Current detailed gem and numeric design specify 12 damage.

Default authority: detailed gem and numeric design.

## Fire And Poison Fog Reaction

- `详细设计/宝石/宝石_v1.md` says fire + poison creates toxic smoke for 1 turn, with both fire and poison fog effects.
- `详细设计/地块/地块.md` says poison fog disappears when it encounters fire or explosion.
- Product direction on 2026-06-17 explicitly expects fire to create toxic smoke when it meets poison fog.

Default authority: detailed gem design plus current product direction. Current implementation treats fire entering poison fog and poison fog entering fire as the same reaction: consume fire/poison fog and create `toxic_smoke`. Water still takes precedence over this reaction.
