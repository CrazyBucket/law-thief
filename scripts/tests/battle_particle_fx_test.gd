extends SceneTree

const _ParticleFx = preload("res://scripts/ui/battle_particle_fx.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var fx := _ParticleFx.new()
	root.add_child(fx)
	fx.add({
		"type": "spark",
		"pos": Vector2.ZERO,
		"life": 0.5,
		"max_life": 0.5,
		"velocity": Vector2.ZERO,
	})
	assert(fx.push_sprite_sequence({
		"paths": ["res://missing_a.png", "res://missing_b.png"],
		"fps": 20.0,
		"draw_size": Vector2(16.0, 12.0),
	}))
	assert(fx.particle_count() == 2)
	assert(fx.step(0.1))
	assert(fx.particle_count() == 2)
	assert(fx.step(1.0))
	assert(fx.particle_count() == 0)
	assert(not fx.push_sprite_sequence({"paths": []}))
	fx.free()
	print("BATTLE_PARTICLE_FX_TEST_PASS")
	quit()
