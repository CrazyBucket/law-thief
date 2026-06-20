# Encounter template guide

Battle maps are hand-authored 8×8 templates under `resources/encounters/`. A template may combine all three enemy composition forms:

- `enemies`: fixed monsters at fixed positions; always spawned.
- `enemy_groups`: weighted complete formations; exactly one group is selected.
- `random_enemies`: independent weighted monster rolls at preset positions.

All composition rolls use the combat RNG context, so the same run seed, encounter id, and room id reproduce the same formation.

```json
{
  "player_spawn": [1, 6],
  "enemies": [
    {"def_id": "unit_patrol_guard", "pos": [5, 3]}
  ],
  "enemy_groups": [
    {"weight": 2, "enemies": [
      {"def_id": "unit_bomb_rat", "pos": [6, 1]},
      {"def_id": "unit_stone_bow_guard", "pos": [6, 6]}
    ]}
  ],
  "random_enemies": [
    {"pos": [4, 5], "candidates": [
      {"def_id": "unit_bomb_rat", "weight": 3},
      {"def_id": "unit_patrol_guard", "weight": 1}
    ]}
  ]
}
```

Random candidates must fit the same footprint at their slot. In particular, do not mix a 2×2 unit with 1×1 units unless every affected cell is reserved for the largest candidate.

Map hazards use existing encounter fields:

- `tiles`: `tile_water`, `tile_ice`, `tile_grass`, `tile_bush`, or a slotted `tile_pillar`.
- tile `overlays`: `poison_fog`, `fire`, `toxic_smoke`, or `poison_puddle`, with `duration`.
- `entities`: `entity_rock`, `entity_prop`, `entity_spike`, or `entity_barrel`.

Keep at least one readable route between player and enemies, and avoid placing blocking entities on any unit footprint.
