class_name BattleParticleFx
extends Node2D

const _IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")

var _textures: RefCounted = null
var _particles: Array[Dictionary] = []
var _puff_paths := PackedStringArray()


## 粒子层只消费表现数据；纹理缓存由外层注入，战斗状态不进入该组件。
func configure(textures: RefCounted) -> void:
	_textures = textures


func add(spec: Dictionary) -> void:
	_particles.append(spec)
	queue_redraw()


func particle_count() -> int:
	return _particles.size()


func push_sprite_sequence(cfg: Dictionary) -> bool:
	var paths_value: Variant = cfg.get("paths", PackedStringArray())
	var paths := PackedStringArray()
	if paths_value is PackedStringArray:
		paths = paths_value as PackedStringArray
	elif paths_value is Array:
		for path_value in paths_value as Array:
			paths.append(str(path_value))
	else:
		return false
	if paths.is_empty():
		return false
	var fps := float(cfg.get("fps", 26.0))
	var draw_size_value: Variant = cfg.get("draw_size", Vector2(88.0, 88.0))
	var draw_size: Vector2 = draw_size_value if draw_size_value is Vector2 else Vector2(88.0, 88.0)
	var velocity_value: Variant = cfg.get("velocity", Vector2.ZERO)
	var velocity: Vector2 = velocity_value if velocity_value is Vector2 else Vector2.ZERO
	var duration := float(paths.size()) / maxf(fps, 0.01) + float(cfg.get("life_pad", 0.05))
	add({
		"type": "sprite_seq", "pos": cfg.get("pos", Vector2.ZERO),
		"life": duration,
		"max_life": duration,
		"velocity": _IsoCoordinates.visual_vec(velocity),
		"frame_time": 0.0, "fps": fps, "paths": paths,
		"draw_size": _IsoCoordinates.visual_vec(draw_size),
		"tint": cfg.get("tint", Color.WHITE),
	})
	return true


func step(delta: float) -> bool:
	var dirty := false
	for index in range(_particles.size() - 1, -1, -1):
		var particle := _particles[index]
		particle["life"] = float(particle.get("life", 0.0)) - delta
		if float(particle["life"]) <= 0.0:
			_particles.remove_at(index)
			dirty = true
			continue
		var sprite_sequence := str(particle.get("type", "")) == "sprite_seq"
		particle["frame_time"] = float(particle.get("frame_time", 0.0)) + delta if sprite_sequence else float(particle.get("frame_time", 0.0))
		particle["pos"] = particle.get("pos", Vector2.ZERO) + particle.get("velocity", Vector2.ZERO) * delta
		particle["velocity"] = particle.get("velocity", Vector2.ZERO) + Vector2(0, 40.0 if sprite_sequence else 120.0) * delta
		dirty = true
	if dirty:
		queue_redraw()
	return dirty


func puff_paths() -> PackedStringArray:
	if _puff_paths.is_empty():
		for index in range(7):
			_puff_paths.append("res://assets/demo/doodle-rpg/ALL SPRITES/Particles/Puff_%d.png" % index)
	return _puff_paths


func _draw() -> void:
	for particle in _particles:
		_draw_particle(particle)


func _draw_particle(particle: Dictionary) -> void:
	var alpha := clampf(float(particle.get("life", 0.0)) / maxf(float(particle.get("max_life", 1.0)), 0.001), 0.0, 1.0)
	var color: Color = particle.get("color", Color.WHITE)
	color.a *= alpha
	var pos: Vector2 = particle.get("pos", Vector2.ZERO)
	match str(particle.get("type", "spark")):
		"spark": draw_rect(Rect2(pos - Vector2.ONE * (3.0 * alpha + 1.0) * 0.5, Vector2.ONE * (3.0 * alpha + 1.0)), color)
		"heal": draw_circle(pos, 4.0 * alpha, color)
		"gem": _diamond(pos, 6.0 * alpha + 2.0, 4.0 * alpha + 1.0, color)
		"smoke": draw_circle(pos, 8.0 * (1.0 - alpha * 0.5), color)
		"ring":
			var ring_color := color
			ring_color.a = alpha * 0.7
			draw_arc(pos, 20.0 + (1.0 - alpha) * 60.0, 0, TAU, 24, ring_color, 2.5 * alpha + 0.5)
		"hit_mark": _hit_mark(pos, color, alpha, float(particle.get("scale", 1.0)))
		"sprite_seq": _sprite_sequence(particle, pos, alpha)


func _diamond(pos: Vector2, width: float, height: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -height), pos + Vector2(width, 0), pos + Vector2(0, height), pos + Vector2(-width, 0)]), color)


func _hit_mark(pos: Vector2, color: Color, alpha: float, scale: float) -> void:
	var length := (20.0 + (1.0 - alpha) * 10.0) * scale
	var thickness := (3.0 * alpha + 1.0) * scale
	draw_line(pos + Vector2(-length, -length), pos + Vector2(length, length), color, thickness)
	draw_line(pos + Vector2(-length, length), pos + Vector2(length, -length), color, thickness)
	draw_line(pos + Vector2(-length * 1.2, 0), pos + Vector2(length * 1.2, 0), color, thickness * 0.6)
	draw_line(pos + Vector2(0, -length * 1.2), pos + Vector2(0, length * 1.2), color, thickness * 0.6)


func _sprite_sequence(particle: Dictionary, pos: Vector2, alpha: float) -> void:
	if _textures == null:
		return
	var paths: PackedStringArray = particle.get("paths", PackedStringArray())
	if paths.is_empty():
		return
	var index := clampi(int(float(particle.get("frame_time", 0.0)) * float(particle.get("fps", 14.0))), 0, paths.size() - 1)
	var texture: Texture2D = _textures.texture_at(str(paths[index]))
	if texture == null:
		return
	var size: Vector2 = particle.get("draw_size", Vector2(40, 40))
	var tint: Color = particle.get("tint", Color.WHITE)
	tint.a *= alpha
	draw_texture_rect(texture, Rect2(pos - size * 0.5, size), false, tint)
