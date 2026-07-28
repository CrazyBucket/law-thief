extends SceneTree

const _BoardFxTextures = preload("res://scripts/ui/board_fx_textures.gd")
const _ProjectileFx = preload("res://scripts/ui/battle_projectile_fx.gd")

var _completed: bool = false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var fx := _ProjectileFx.new()
	fx.configure(Callable(self, "_grid_to_screen"), _BoardFxTextures.new())
	root.add_child(fx)
	assert(fx.sprite_frame_count() == 10, "Foozle Wind projectile sequence should be available")
	var fire_frames := fx.gem_sprite_frame_count("fire")
	assert(fire_frames == 0 or fire_frames == 30, "optional Mini Fires sequence must either be absent or contain all 30 frames")
	fx.finished.connect(func() -> void: _completed = true)
	fx.play([
		{"from": Vector2i(1, 1), "to": Vector2i(5, 1), "element": "fire", "gem_level": 3},
		{"from": Vector2i(1, 1), "to": Vector2i(4, 2)},
	], 10.0)
	assert(fx.active_count() == 2)
	await create_timer(0.1).timeout
	await process_frame
	assert(_completed)
	assert(fx.active_count() == 0)
	fx.free()
	print("BATTLE_PROJECTILE_FX_TEST_PASS")
	quit()


func _grid_to_screen(grid: Vector2i) -> Vector2:
	return Vector2(grid.x * 48.0, grid.y * 24.0)
