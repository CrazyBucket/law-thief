extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Battle Renderer Timing Test ===")
	var scene: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	var battle_scene = scene.instantiate()
	root.add_child(battle_scene)
	await process_frame
	var board = battle_scene.get_node("BoardLayer/IsometricBoard")
	var shots := [
		{"from": Vector2i(1, 1), "to": Vector2i(5, 1)},
		{"from": Vector2i(1, 1), "to": Vector2i(4, 0)},
		{"from": Vector2i(1, 1), "to": Vector2i(4, 2)},
	]
	board.play_projectiles(shots)
	var animation_state = board.get("_anim")
	assert(animation_state.active_projectiles.size() == 3, "renderer must activate the full split volley in one frame")
	await board.projectile_animation_finished
	var blast_timing: Dictionary = board.play_explosion_batch([{"type": "explode", "pos": Vector2i(4, 3)}])
	assert(float(blast_timing.impact_time) > 0.0)
	assert(float(blast_timing.impact_time) < float(blast_timing.duration))
	var arc_timing: Dictionary = board.play_electrical_batch([
		{"type": "arc", "from": Vector2i(3, 3), "target_pos": Vector2i(5, 2)},
		{"type": "arc", "from": Vector2i(3, 3), "target_pos": Vector2i(5, 4)},
	])
	assert(float(arc_timing.impact_time) > 0.0)
	assert(float(arc_timing.impact_time) < float(arc_timing.duration))
	await create_timer(maxf(float(blast_timing.duration), float(arc_timing.duration)) + 0.1).timeout
	battle_scene.queue_free()
	await process_frame
	print("BATTLE_RENDERER_TIMING_TEST_PASS")
	quit()
