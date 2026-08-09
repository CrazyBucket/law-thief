extends SceneTree

const ImpactPresenter = preload("res://scripts/ui/impact_animation_presenter.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Battle Renderer Timing Test ===")
	var scene: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	var battle_scene = scene.instantiate()
	root.add_child(battle_scene)
	await process_frame
	var board = battle_scene.get_node("BoardLayer/IsometricBoard")
	var board_texture := board.get_node("Grids") as Sprite2D
	var expected_crop := Rect2(70.0, 76.0, 1116.0, 1102.0)
	assert(_scan_board_texture_content_rect(board_texture.texture).is_equal_approx(expected_crop), "board texture pixels must match the precomputed crop contract")
	assert(board._board_texture_content_rect().is_equal_approx(expected_crop), "board texture crop must retain the authored non-white bounds")
	assert(board.get("_slot_panel_renderer") == null, "ordinary battle startup should not load the slot panel renderer")
	assert(board.get("_beam_layer") == null, "ordinary battle first frame should not create combat FX layers")
	board.configure_unit_slot_panels(
		Constants.ACTION_INSERT,
		func(_uid: String, _index: int) -> Dictionary: return {"ok": true},
		func(_uid: String) -> bool: return true
	)
	assert(board.get("_slot_panel_renderer") != null, "slot actions should load the slot panel renderer on demand")
	await process_frame
	board.clear_unit_slot_panels()
	await process_frame
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
	animation_state.idle_phase[player.uid] = 0.0
	assert(not board._advance_unit_idle_phase(player, 0.04), "idle animation should not redraw inside the same authored frame")
	assert(board._advance_unit_idle_phase(player, 0.07), "idle animation should redraw when its authored frame advances")
	animation_state.pulse_time = 10.0
	board.set("_last_active_aura_redraw_tick", -1)
	assert(board._active_aura_redraw_due(), "active aura should draw on a new 30 Hz tick")
	animation_state.pulse_time += 0.018
	assert(not board._active_aura_redraw_due(), "active aura should reuse the current 30 Hz sample")
	animation_state.pulse_time += 0.018
	assert(board._active_aura_redraw_due(), "active aura should redraw on the next 30 Hz sample")
	animation_state.pulse_time = 10.0
	board.set("_last_back_overlay_redraw_tick", -1)
	assert(board._back_overlay_redraw_due(), "back overlays should redraw for a new 30 Hz tick")
	assert(not board._back_overlay_redraw_due(), "back overlay redraw should deduplicate inside one 30 Hz tick")
	animation_state.pulse_time += 1.0 / 60.0
	assert(not board._back_overlay_redraw_due(), "back overlays should retain draw commands between half ticks")
	animation_state.pulse_time += 1.0 / 60.0
	assert(board._back_overlay_redraw_due(), "back overlays should redraw on the next 30 Hz tick")
	var back_overlay_layer: Control = board.get("_back_overlay_layer")
	assert(back_overlay_layer != null and back_overlay_layer.show_behind_parent, "back overlays should render behind units")
	var previous_back_draw_count: int = int(back_overlay_layer.get("draw_count"))
	board.set_hover(Vector2i(0, 0))
	await process_frame
	assert(int(back_overlay_layer.get("draw_count")) > previous_back_draw_count, "hover changes should refresh the back overlay layer")
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
	var shader_layer: Control = board.get("_beam_layer")
	assert(shader_layer != null, "the first shader effect should ensure the combat FX layer")
	var shader_child_count_before_arc := shader_layer.get_child_count()
	var arc_timing: Dictionary = board.play_electrical_batch([
		{"type": "arc", "from": Vector2i(3, 3), "target_pos": Vector2i(5, 2)},
		{"type": "arc", "from": Vector2i(3, 3), "target_pos": Vector2i(5, 4)},
	])
	assert(
		shader_layer.get_child_count() == shader_child_count_before_arc,
		"normal electrical volleys should reuse prewarmed shader nodes instead of allocating on impact"
	)
	assert(float(arc_timing.impact_time) > 0.0)
	assert(float(arc_timing.impact_time) < float(arc_timing.duration))
	var impact_timing: Dictionary = ImpactPresenter.play(board, {
		"type": "impact_charge",
		"uid": player.uid,
		"from": player.pos,
		"to": player.pos + Vector2i(2, 0),
		"target_pos": player.pos + Vector2i(3, 0),
		"steps": 2,
	})
	assert(float(impact_timing.impact_time) > 0.0, "impact should have a visible windup and travel phase")
	assert(float(impact_timing.impact_time) < float(impact_timing.duration), "impact should retain recovery after contact")
	await create_timer(maxf(float(blast_timing.duration), float(arc_timing.duration)) + 0.1).timeout
	battle_scene.queue_free()
	await process_frame
	print("BATTLE_RENDERER_TIMING_TEST_PASS")
	quit()


func _scan_board_texture_content_rect(texture: Texture2D) -> Rect2:
	var image := texture.get_image()
	assert(image != null, "board texture must expose image data for its crop contract")
	if image.is_compressed():
		image.decompress()
	var min_pos := Vector2i(image.get_width(), image.get_height())
	var max_pos := Vector2i(-1, -1)
	var step := 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var color := image.get_pixel(x, y)
			if color.a < 0.04 or (color.r > 0.95 and color.g > 0.95 and color.b > 0.95):
				continue
			min_pos.x = mini(min_pos.x, x)
			min_pos.y = mini(min_pos.y, y)
			max_pos.x = maxi(max_pos.x, x)
			max_pos.y = maxi(max_pos.y, y)
	if max_pos.x < min_pos.x or max_pos.y < min_pos.y:
		return Rect2(Vector2.ZERO, texture.get_size())
	return Rect2(min_pos, max_pos - min_pos + Vector2i(step, step))
