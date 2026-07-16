# Business Script Size Boundaries

Business scripts over 600 lines must appear here. The register is a guardrail,
not a waiver: each entry records the remaining responsibility boundary and the
next safe extraction direction. Tests and one-off tooling are excluded.

| File | Line budget | Current responsibility boundary | Next extraction direction |
| --- | ---: | --- | --- |
| `scripts/ui/isometric_board.gd` | 3445 | Board lifecycle, coordinate conversion, input hit tests, draw orchestration | Unit rendering, gem visuals, and board surface rendering remain separate candidates; FX layers are already separate. |
| `scripts/ui/battle_scene.gd` | 3248 | Scene lifecycle and composition root for battle UI | Keep extracting view-only input, settlement, and editor adapters. |
| `scripts/rules/gem_effects.gd` | 2401 | Compatibility facade for gem trigger rules | Split by trigger timing behind the existing public facade. |
| `scripts/services/data_registry.gd` | 1837 | Content loading, public catalog queries, reward pool policy, run restoration | Continue moving catalog loaders and pool policy into injected services. |
| `scripts/services/balance_config_validator.gd` | 1262 | Compatibility validator facade | Keep domain validators isolated by config family. |
| `scripts/debug/battle_editor_cli.gd` | 1226 | Legacy command parsing and compatibility UI formatting | Route more command parsing through editor service DTOs. |
| `scripts/ui/battle_hud_presenter.gd` | 1122 | HUD composition and state projection | Extract independent layout and interaction presenters. |
| `scripts/rules/attack_pipeline.gd` | 928 | Attack sequencing facade | Keep special-effect phases behind explicit attack context helpers. |
| `scripts/services/adventure_config_validator.gd` | 924 | Compatibility validator facade for adventure content | Keep progression, encounter, economy, reward, and map validators separate. |
| `scripts/main/main_root.gd` | 832 | Application shell lifecycle and scene composition | Extract page-specific builders only when they have no shell lifecycle dependency. |
| `scripts/map/tile_renderer.gd` | 788 | Tile and route drawing primitives | Separate only reusable rendering primitives; preserve draw ordering at the caller. |
| `scripts/services/run_service.gd` | 772 | Run lifecycle, persistence boundary, and recovery orchestration | Extract persistence codecs and reward claims that have no lifecycle dependency. |
| `scripts/rules/status_rules.gd` | 755 | Status mutation and trigger facade | Keep action-specific status rules in focused modules. |
| `scripts/rules/board_utils.gd` | 758 | Stateless board geometry, occupancy, and path helpers | Split only by pure geometry versus state-aware queries when call-site duplication falls. |
| `scripts/debug/battle_editor_service.gd` | 645 | Editor command dispatch and runtime state mutation | Encounter codec is separate; continue separating mutation families only with shared transaction boundaries. |
