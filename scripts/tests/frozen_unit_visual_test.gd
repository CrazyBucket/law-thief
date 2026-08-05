extends SceneTree

const FrozenStatusRules = preload("res://scripts/rules/frozen_status_rules.gd")

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
	var target: UnitState = state.units.get(state.player_uid, null)
	_require(target != null, "battle fixture must expose the player unit")
	if target != null:
		FrozenStatusRules.apply(state, target, 1, "visual_test")
		board.queue_redraw()
	await process_frame
	await process_frame
	await process_frame
	var viewports := board.find_children("FrozenUnitShaderViewport*", "SubViewport", true, false)
	_require(viewports.size() == 1, "one frozen unit should create one shader viewport")
	if viewports.size() == 1:
		var viewport := viewports[0] as SubViewport
		_require(viewport.transparent_bg, "frozen unit shader viewport must preserve transparency")
		_require(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "frozen unit shader must animate while the status is active")
		_require(str(viewport.get_meta("frozen_unit_uid", "")) == target.uid, "frozen shader viewport must belong to the frozen unit")
		_require(viewport.get_child_count() == 1, "frozen shader viewport should contain one sprite")
		if viewport.get_child_count() == 1:
			var sprite := viewport.get_child(0) as Sprite2D
			_require(sprite != null and sprite.material is ShaderMaterial, "frozen unit sprite must use a shader material")
			if sprite != null and sprite.material is ShaderMaterial:
				var material := sprite.material as ShaderMaterial
				_require(material.shader != null and material.shader.resource_path.ends_with("frozen_unit.gdshader"), "frozen unit must use the dedicated ice shader")
				var uniform_names: Array = material.shader.get_shader_uniform_list().map(func(entry): return str(entry.get("name", "")))
				_require("ice_tint" in uniform_names and "tint_strength" in uniform_names, "frozen shader should expose its recolor contract")
				_require("rim_width" in uniform_names, "frozen shader should expose its silhouette rim contract")
				_require(material.get_shader_parameter("unit_tint") is Color, "frozen material should receive the rendered unit tint")
	if target != null:
		target.remove_status(Constants.STATUS_FROZEN)
	await process_frame
	await process_frame
	_require(board.find_children("FrozenUnitShaderViewport*", "SubViewport", true, false).is_empty(), "shader viewport should be released after thawing")
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		battle.queue_free()
		await process_frame
		quit(1)
		return
	print("FROZEN_UNIT_VISUAL_TEST_PASS")
	battle.queue_free()
	await process_frame
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
