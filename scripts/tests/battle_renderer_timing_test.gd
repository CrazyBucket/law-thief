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
	var animation_state = board.get("_anim")
	var player = board.state.get_player()
	assert(player != null)
	board.play_unit_hit(player.uid)
	assert(animation_state.hit_elapsed.has(player.uid), "all unit renderers should enter a shared hit state")
	var collision_duration: float = board.animate_unit_motions_parallel([{
		"type": "displacement_impact",
		"uid": player.uid,
		"from": player.pos,
		"contact": player.pos + Vector2i(1, 0),
	}])
	assert(collision_duration > 0.0, "blocked displacement should create a visible lunge and recoil")
	assert(animation_state.move_offsets.has(player.uid), "blocked displacement should own a real visual offset")
	await board.move_animation_finished
	animation_state.pulse_time = 10.0
	board.set("_last_continuous_redraw_tick", -1)
	assert(board._continuous_redraw_due(), "continuous redraw should run for a new 60 Hz tick")
	assert(not board._continuous_redraw_due(), "continuous redraw should be deduplicated inside one 60 Hz tick")
	animation_state.pulse_time += 1.0 / 60.0
	assert(board._continuous_redraw_due(), "continuous redraw should resume on the next 60 Hz tick")
	assert(board._sorted_cells().size() == 64, "renderer should provide all board cells")
	assert(board.get("_sorted_cells_cache").size() == 64, "renderer should cache the sorted board traversal")
	var shots := [
		{"from": Vector2i(1, 1), "to": Vector2i(5, 1)},
		{"from": Vector2i(1, 1), "to": Vector2i(4, 0)},
		{"from": Vector2i(1, 1), "to": Vector2i(4, 2)},
	]
	board.play_projectiles(shots)
	var projectile_fx = board.get("_projectile_fx")
	assert(projectile_fx != null and projectile_fx.active_count() == 3, "renderer must activate the full split volley in one frame")
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
