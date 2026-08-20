# Business Script Size Boundaries

Business scripts over 600 lines must appear here. The register is a guardrail,
not a waiver: each entry records the remaining responsibility boundary and the
next safe extraction direction. Registered budgets use 100-line bands and no
production script may exceed the non-waivable 1,300-line hard limit. Entries
must retain at least 50 lines of headroom and be removed after a file returns
to 600 lines or fewer. Tests and one-off
tooling are excluded.

| File | Line budget | Current responsibility boundary | Next extraction direction |
| --- | ---: | --- | --- |
| `scripts/ui/isometric_board_fx_base.gd` | 1000 | Shared board state plus combat-FX playback coordination and FX resource access | Keep new rendering and input behavior out of the FX foundation. |
| `scripts/ui/isometric_board_unit_renderer.gd` | 900 | Unit sprites, nameplates, statuses, gems, intent badges, and unit hit geometry | Split unit UI into an independent layer before adding another persistent unit overlay. |
| `scripts/ui/isometric_board_surface_renderer.gd` | 900 | Draw orchestration, tiles, overlays, water, entities, routes, and slot-panel integration | Keep unit details and combat animation state in their dedicated inherited layers. |
| `scripts/ui/battle_scene.gd` | 1100 | Battle scene lifecycle, player input, turn flow, pause flow, and animation wiring | Keep result, editor, tutorial, and layout implementations in inherited collaborators. |
| `scripts/ui/battle_scene_flow_base.gd` | 1300 | Battle settlement, rewards, result navigation, shared refresh, and view dependencies | Extract another complete result flow before adding a new post-battle mode. |
| `scripts/ui/battle_scene_editor_adapter.gd` | 800 | Editor interaction, tutorial overlays, preview formatting, and relic-detail presentation | Keep release battle lifecycle and reward policy out of this adapter. |
| `scripts/rules/gem_effects.gd` | 1100 | Compatibility facade and active/passive gem trigger dispatch | Keep resolved effect families behind the inherited resolution boundary. |
| `scripts/rules/gem_effects_resolution.gd` | 1300 | Death, elemental reaction, arc, poison, light, echo, and split resolution | Extract a complete effect family before adding another trigger family here. |
| `scripts/services/data_registry.gd` | 800 | Content loading, battle-state creation, encounter parsing, and run restoration | Keep new catalog queries and reward policy out of the runtime assembly layer. |
| `scripts/services/data_registry_base.gd` | 1300 | Stable content-query, reward-pool, localization, and gem-profile compatibility API | Extract a focused query family before adding another public catalog domain. |
| `scripts/services/balance_config_validator.gd` | 1300 | Compatibility validator facade | Keep domain validators isolated by config family. |
| `scripts/debug/battle_editor_cli.gd` | 1300 | Legacy command parsing and compatibility UI formatting | Route more command parsing through editor service DTOs. |
| `scripts/ui/battle_hud_presenter.gd` | 1300 | HUD composition and state projection | Extract independent layout and interaction presenters; old-mage inspection is isolated in `old_mage_hud_panel.gd`. |
| `scripts/rules/attack_pipeline.gd` | 1000 | Attack sequencing facade | Keep special-effect phases behind explicit attack context helpers. |
| `scripts/services/adventure_config_validator.gd` | 1000 | Compatibility validator facade for adventure content | Keep progression, encounter, economy, reward, and map validators separate. |
| `scripts/main/main_root.gd` | 900 | Application shell lifecycle and scene composition | Extract page-specific builders only when they have no shell lifecycle dependency. |
| `scripts/map/tile_renderer.gd` | 900 | Tile and route drawing primitives | Separate only reusable rendering primitives; preserve draw ordering at the caller. |
| `scripts/services/run_service.gd` | 900 | Run lifecycle, persistence boundary, and recovery orchestration | Extract persistence codecs and reward claims that have no lifecycle dependency. |
| `scripts/rules/status_rules.gd` | 800 | Status mutation and trigger facade | Keep action-specific status rules in focused modules. |
| `scripts/rules/board_utils.gd` | 900 | Stateless board geometry, occupancy, and path helpers | Split only by pure geometry versus state-aware queries when call-site duplication falls. |
| `scripts/rules/overload_rules.gd` | 700 | Overload insertion chains, mutation lifecycle, echo cleanup, and AI-control execution | Extract AI-control execution and movement accounting as one focused rules module. |
| `scripts/services/relic_effect_registry.gd` | 700 | Data-driven relic event dispatch, shared actions, and modifier evaluation | Move stateful or relic-specific actions into focused rule modules while keeping dispatch here. |
| `scripts/debug/battle_editor_service.gd` | 700 | Editor command dispatch and runtime state mutation | Encounter codec is separate; continue separating mutation families only with shared transaction boundaries. |
| `scripts/rules/behaviors/behavior_old_mage.gd` | 1200 | Authored Boss resource loop, spell resolution, and phase-specific intent planning | Extract spell families into a dedicated old-mage spell rules helper if a second Boss uses the same presentation or targeting patterns. |
| `scripts/ui/shop_scene.gd` | 800 | Shop scene composition, offer browsing, purchase feedback, and carried-gem embedding | Extract the carried-gem embed dialog into a focused adventure UI presenter when another room reuses its interaction. |
| `scripts/services/event_content_runtime.gd` | 1100 | Authored event state machines, deterministic room snapshots, and event-only gem/relic transactions for the first nine production events | Extract shared item-selection and reward-placement policies before adding the next event batch. |
