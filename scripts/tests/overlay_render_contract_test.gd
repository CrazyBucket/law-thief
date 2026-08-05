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
			if sprite != null and sprite.material is ShaderMaterial:
				var material := sprite.material as ShaderMaterial
				if material.shader == cloud_shader:
					cloud_viewport_count += 1
					_require(material.get_shader_parameter("shadow_color") is Color, "cloud material should expose its shadow palette")
					_require(material.get_shader_parameter("mid_color") is Color, "cloud material should expose its midtone palette")
					_require(material.get_shader_parameter("highlight_color") is Color, "cloud material should expose its highlight palette")
					_require(float(material.get_shader_parameter("opacity")) > 0.0, "active cloud material should remain visible")
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
