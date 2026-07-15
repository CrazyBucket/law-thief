extends SceneTree

const _LightBeamFx = preload("res://scripts/ui/battle_light_beam_fx.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var fx := _LightBeamFx.new()
	fx.configure(Callable(self, "_grid_to_screen"))
	root.add_child(fx)
	var duration := fx.play([{
		"from": Vector2i(1, 1),
		"to": Vector2i(3, 2),
		"color": Color(0.8, 0.9, 1.0),
		"width": 1.0,
	}], {
		"duration": 0.02,
		"base_half_width": 10.0,
		"global_scale": 1.0,
		"global_power": 1.0,
		"plane_height": -20.0,
		"source_drop": 4.0,
	})
	assert(is_equal_approx(duration, 0.02))
	assert(fx.get_child_count() == 1)
	await create_timer(0.08).timeout
	await process_frame
	assert(fx.get_child_count() == 0)
	fx.free()
	print("BATTLE_LIGHT_BEAM_FX_TEST_PASS")
	quit()


func _grid_to_screen(grid: Vector2i) -> Vector2:
	return Vector2(grid.x * 48.0, grid.y * 24.0)
