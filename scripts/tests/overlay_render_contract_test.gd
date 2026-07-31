extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var battle := packed.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var board := battle.get_node("BoardLayer/IsometricBoard") as Control
	var state: GameState = board.state
	state.get_tile(Vector2i(0, 0)).tile_id = Constants.TILE_GRASS
	state.get_tile(Vector2i(1, 0)).add_modifier(Constants.TILE_MOD_POISON_FOG, 2)
	state.get_tile(Vector2i(2, 0)).add_modifier(Constants.TILE_MOD_TOXIC_SMOKE, 1)
	var echo_gem_uid := ""
	for unit: UnitState in state.units.values():
		for slot: SlotState in unit.slots:
			if slot != null and not slot.gem_uid.is_empty():
				echo_gem_uid = slot.gem_uid
				break
		if not echo_gem_uid.is_empty():
			break
	_require(not echo_gem_uid.is_empty(), "render fixture must expose one gem for echo visuals")
	state.overload_echo_gems[echo_gem_uid] = state.turn_index + 1
	await process_frame
	await process_frame
	var viewports := board.find_children("OverlayShaderViewport*", "SubViewport", true, false)
	_require(viewports.size() == 6, "grass, fog, and smoke must keep six shader-backed texture sources")
	var cloud_shader := load("res://scenes/battle/overlay_cloud_parts.gdshader") as Shader
	var cloud_viewport_count := 0
	for viewport in viewports:
		var overlay_viewport := viewport as SubViewport
		_require(overlay_viewport.transparent_bg, "%s must render with transparency" % overlay_viewport.name)
		_require(overlay_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "%s must animate continuously" % overlay_viewport.name)
		_require(overlay_viewport.get_child_count() == 1, "%s must contain one shader sprite" % overlay_viewport.name)
		if overlay_viewport.get_child_count() == 1:
			var sprite := overlay_viewport.get_child(0) as Sprite2D
			_require(sprite != null and sprite.material is ShaderMaterial, "%s must use a shader material" % overlay_viewport.name)
			if sprite != null and sprite.material is ShaderMaterial and (sprite.material as ShaderMaterial).shader == cloud_shader:
				cloud_viewport_count += 1
	_require(cloud_viewport_count == 2, "poison fog and toxic smoke must share the cloud atlas through separate palette shaders")
	var cloud_lifecycle: RefCounted = board.get("_poison_cloud_lifecycle")
	cloud_lifecycle.call("sync", state, 1.0)
	var fog_before_swap: Dictionary = cloud_lifecycle.call("visuals_for_cell", Vector2i(1, 0))
	board.call("set_battle_state", state.clone())
	var fog_after_swap: Dictionary = cloud_lifecycle.call("visuals_for_cell", Vector2i(1, 0))
	_require(fog_after_swap == fog_before_swap, "presentation state replacement must not restart active poison cloud fades")
	board.call("set_battle_state", state)
	var echo_viewport := board.find_child("GemEchoShaderViewport", true, false) as SubViewport
	_require(echo_viewport != null, "gem echoes must create a dedicated shader viewport")
	if echo_viewport != null:
		_require(echo_viewport.transparent_bg, "gem echo smoke must render with transparency")
		_require(echo_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "gem echo smoke must animate continuously while visible")
		_require(echo_viewport.get_child_count() == 1 and echo_viewport.get_child(0).material is ShaderMaterial, "gem echo smoke must use a shader material")
	var echo_icon_viewports := board.find_children("GemEchoIconShaderViewport*", "SubViewport", true, false)
	_require(echo_icon_viewports.size() == 1, "the visible echo gem type must have one shader-recolored icon source")
	if echo_icon_viewports.size() == 1:
		var echo_icon_viewport := echo_icon_viewports[0] as SubViewport
		_require(echo_icon_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "visible echo icons must animate continuously")
		_require(echo_icon_viewport.get_child_count() == 1 and echo_icon_viewport.get_child(0).material is ShaderMaterial, "echo gem icons must pass through their recolor shader")
	var board_source := FileAccess.get_file_as_string("res://scripts/ui/isometric_board.gd")
	var ground_highlight_draw := board_source.find("\t_draw_overlay_outlines()")
	var entity_draw := board_source.find("\t\t_draw_entity_at_grid(grid, drawn_entities)")
	var hover_draw := board_source.find("\t\t\tTileRenderer.draw_hover_outline")
	var unit_body_draw := board_source.find("\t\t\t_draw_unit_body(unit)")
	var front_overlay_draw := board_source.find("\t\t\t_draw_front_tile_overlay_at(grid, true)", unit_body_draw)
	var entity_ui_draw := board_source.find("\t\t\t_draw_entity_ui(entity)", front_overlay_draw)
	var unit_ui_draw := board_source.find("\t\t\t_draw_unit_ui(unit)", entity_ui_draw)
	_require(unit_body_draw >= 0 and front_overlay_draw > unit_body_draw, "front overlay pass must render after unit bodies")
	_require(ground_highlight_draw >= 0 and ground_highlight_draw < entity_draw, "cell highlights must render below props and barrels")
	_require(hover_draw >= 0 and hover_draw < entity_draw, "cell hover outline must render below props and barrels")
	_require(board_source.find("func _draw_front_tile_overlays") < 0, "front overlays must not be drawn as a global post-unit pass")
	_require(entity_ui_draw > front_overlay_draw, "destructible entity HP must render above board effects")
	_require(unit_ui_draw > entity_ui_draw, "unit UI must remain above destructible entity HP")
	_require(not board_source.contains("set_highlights") and not board_source.contains("_draw_highlight_outlines"), "renderer must not retain the legacy highlight API or draw path")
	var unit_ui_fn := board_source.substr(board_source.find("func _draw_unit_ui"), 900)
	_require(unit_ui_fn.contains("_draw_hp_bar") and unit_ui_fn.contains("_draw_unit_statuses") and unit_ui_fn.contains("_draw_gem_icons"), "unit UI pass must own hp, statuses, and gems")
	var entity_ui_fn := board_source.substr(board_source.find("func _draw_entity_ui"), 700)
	_require(entity_ui_fn.contains("entity.max_hp <= 0") and entity_ui_fn.contains("draw_combined_hp_bar"), "entity UI must show HP only for destructible entities")
	var shader_source := FileAccess.get_file_as_string("res://scenes/battle/overlay_drift.gdshader")
	_require(shader_source.contains("TIME") and shader_source.contains("VERTEX"), "overlay drift must remain GPU animated")
	var cloud_shader_source := FileAccess.get_file_as_string("res://scenes/battle/overlay_cloud_parts.gdshader")
	_require(cloud_shader_source.contains("shadow_color") and cloud_shader_source.contains("mid_color") and cloud_shader_source.contains("highlight_color"), "poison cloud shader must own fog and smoke palette mapping")
	_require(cloud_shader_source.contains("TIME") and cloud_shader_source.contains("opacity"), "poison cloud shader must keep restrained alpha breathing")
	var cloud_layout_source := FileAccess.get_file_as_string("res://scripts/map/overlay_cloud_layout.gd")
	_require(cloud_layout_source.contains("NOMINAL_CHARACTER_HEIGHT") and cloud_layout_source.contains("\"front\": vertical >= 0.55"), "poison cloud distribution must use character height and low front parts")
	_require(cloud_layout_source.contains("\"direction\"") and cloud_layout_source.contains("\"particles\""), "poison cloud parts must keep independent directions and bridge particles")
	var cloud_renderer_source := FileAccess.get_file_as_string("res://scripts/map/poison_cloud_renderer.gd")
	_require(cloud_renderer_source.contains("_draw_cell_anchor") and cloud_renderer_source.contains("diamond_corners"), "poison cloud effects must visibly anchor to their owning cell")
	var lifecycle_source := FileAccess.get_file_as_string("res://scripts/map/poison_cloud_lifecycle.gd")
	_require(lifecycle_source.contains("FADE_IN_SECONDS") and lifecycle_source.contains("FADE_OUT_SECONDS") and lifecycle_source.contains("_smoothstep01"), "poison cloud groups must fade smoothly in and out")
	_require(board_source.contains("_poison_cloud_lifecycle.visuals_for_cell"), "both poison cloud draw passes must consume lifecycle alpha")
	_require(board_source.contains("_poison_cloud_lifecycle.prepare_state_change(state, value)"), "presentation state clones must not restart every poison cloud fade")
	var echo_shader_source := FileAccess.get_file_as_string("res://scenes/battle/gem_echo_smoke.gdshader")
	_require(echo_shader_source.contains("TIME") and echo_shader_source.contains("fbm"), "gem echo smoke must remain procedurally animated")
	_require(echo_shader_source.contains("smoke_stream") and echo_shader_source.contains("fract(time") and not echo_shader_source.contains("smoke_ribbon") and not echo_shader_source.contains("ring_radius"), "gem echo smoke must use visibly travelling puffs instead of static ribbons or a circular border")
	_require(board_source.contains("_draw_echo_smoke"), "board gem icons and slot sectors must render the echo smoke layer")
	_require(board_source.contains("_display_gem_texture"), "board echo gems must use shader-recolored icon textures")
	_require(board_source.contains("_gem_content_bounds"), "echo wisps must size against visible gem pixels instead of transparent texture padding")
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		battle.queue_free()
		await process_frame
		quit(1)
		return
	print("OVERLAY_RENDER_CONTRACT_TEST_PASS")
	battle.queue_free()
	await process_frame
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
