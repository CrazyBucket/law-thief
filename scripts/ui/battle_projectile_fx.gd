class_name BattleProjectileFx
extends Node2D

const _IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const _BoardFxTextures = preload("res://scripts/ui/board_fx_textures.gd")
const _GemProjectileFrames = preload("res://scripts/ui/gem_projectile_frames.gd")
const _Vpf = preload("res://scripts/ui/vfx_pack_frames.gd")
const PROJECTILE_TRAVEL_FRAMES := 6

signal finished()

var _grid_to_screen: Callable = Callable()
var _textures: RefCounted = null
var _projectiles: Array[Dictionary] = []
var _sprite_paths := PackedStringArray()


## 投射物层拥有自己的飞行状态和绘制；外层只提供网格投影与播放请求。
func configure(grid_to_screen: Callable, textures: RefCounted = null) -> void:
	_grid_to_screen = grid_to_screen
	_textures = textures if textures != null else _BoardFxTextures.new()
	_sprite_paths = _Vpf.frame_paths(_Vpf.EFFECT_PROJECTILE)


func play(shots: Array, speed_scale: float) -> void:
	if shots.is_empty():
		finished.emit()
		return
	_projectiles.clear()
	var max_duration := 0.0
	for shot in shots:
		var from_grid: Vector2i = shot.get("from", Vector2i.ZERO)
		var to_grid: Vector2i = shot.get("to", Vector2i.ZERO)
		var from_screen: Vector2 = shot.get("from_screen", _screen_anchor(from_grid))
		var to_screen := _screen_anchor(to_grid)
		var midpoint := (from_screen + to_screen) * 0.5
		var distance := from_screen.distance_to(to_screen)
		var control := midpoint + Vector2(0, -clampf(distance * 0.45, _IsoCoordinates.visual(28.0), _IsoCoordinates.visual(90.0)))
		var duration := clampf(distance / _IsoCoordinates.visual(520.0), 0.18, 0.38) / maxf(0.05, speed_scale)
		var element := str(shot.get("element", ""))
		var gem_paths := _GemProjectileFrames.frame_paths(element)
		var uses_gem_animation := not gem_paths.is_empty()
		var gem_level := clampi(int(shot.get("gem_level", 1)), 1, 3)
		max_duration = maxf(max_duration, duration)
		_projectiles.append({
			"from": from_screen,
			"to": to_screen,
			"control": control,
			"progress": 0.0,
			"duration": duration,
			"color": shot.get("color", Color(0.95, 0.92, 0.45)),
			"sprite_paths": gem_paths if uses_gem_animation else _sprite_paths,
			"loop_sprite": uses_gem_animation,
			"sprite_fps": 30.0 if uses_gem_animation else 38.0,
			"sprite_size": Vector2(42.0, 42.0) + Vector2(12.0, 12.0) * float(gem_level - 1) if uses_gem_animation else Vector2(50.0, 50.0),
			"sprite_tint": Color.WHITE if uses_gem_animation else Color.WHITE.lerp(shot.get("color", Color(0.95, 0.92, 0.45)), 0.5),
			"trail_scale": 1.0 + 0.2 * float(gem_level - 1) if uses_gem_animation else 1.0,
		})
	queue_redraw()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_progress, 0.0, 1.0, max_duration)
	tween.tween_callback(_finish)


func active_count() -> int:
	return _projectiles.size()


func sprite_frame_count() -> int:
	return _sprite_paths.size()


func gem_sprite_frame_count(element: String) -> int:
	return _GemProjectileFrames.frame_paths(element).size()


func _set_progress(progress: float) -> void:
	for projectile in _projectiles:
		projectile["progress"] = progress
	queue_redraw()


func _finish() -> void:
	_projectiles.clear()
	queue_redraw()
	finished.emit()


func _draw() -> void:
	for projectile in _projectiles:
		_draw_projectile(projectile)


func _draw_projectile(projectile: Dictionary) -> void:
	var progress: float = float(projectile["progress"])
	var from: Vector2 = projectile["from"]
	var to: Vector2 = projectile["to"]
	var control: Vector2 = projectile["control"]
	var color: Color = projectile["color"]
	var trail_scale := float(projectile.get("trail_scale", 1.0))
	var inverse := 1.0 - progress
	var position := inverse * inverse * from + 2.0 * inverse * progress * control + progress * progress * to
	var tangent := (2.0 * (1.0 - progress) * (control - from) + 2.0 * progress * (to - control)).normalized()

	const TRAIL_STEPS := 5
	for index in range(TRAIL_STEPS):
		var trail_ratio: float = float(index + 1) / float(TRAIL_STEPS)
		var alpha := (1.0 - trail_ratio) * 0.55
		var trail_progress := clampf(progress - trail_ratio * 0.06, 0.0, 1.0)
		var trail_inverse := 1.0 - trail_progress
		var trail_position := trail_inverse * trail_inverse * from + 2.0 * trail_inverse * trail_progress * control + trail_progress * trail_progress * to
		var trail_color := color
		trail_color.a = alpha
		draw_line(position, trail_position, trail_color, maxf(_IsoCoordinates.visual(3.0) - trail_ratio * _IsoCoordinates.visual(1.5), _IsoCoordinates.visual(0.5)) * trail_scale)

	if _draw_sprite_projectile(projectile, position, tangent, color):
		return
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var tip := position + tangent * _IsoCoordinates.visual(7.0)
	var tail := position - tangent * _IsoCoordinates.visual(5.0)
	var left := position + perpendicular * _IsoCoordinates.visual(3.5)
	var right := position - perpendicular * _IsoCoordinates.visual(3.5)
	var points := PackedVector2Array([tip, left, tail, right])
	draw_colored_polygon(points, color)
	var outline := color.darkened(0.3)
	outline.a = 0.85
	draw_polyline(PackedVector2Array([tip, left, tail, right, tip]), outline, _IsoCoordinates.visual(1.0))


func _draw_sprite_projectile(projectile: Dictionary, position: Vector2, tangent: Vector2, color: Color) -> bool:
	var sprite_paths: PackedStringArray = projectile.get("sprite_paths", _sprite_paths)
	if sprite_paths.is_empty():
		return false
	var duration := maxf(float(projectile.get("duration", 0.25)), 0.01)
	var progress := clampf(float(projectile.get("progress", 0.0)), 0.0, 1.0)
	# Wind 的后四帧是消散尾段；命中反馈由 damage 动画接手，飞行中只循环实体帧。
	var frame_index := 0
	if bool(projectile.get("loop_sprite", false)):
		frame_index = int(progress * duration * float(projectile.get("sprite_fps", 30.0))) % sprite_paths.size()
	else:
		var travel_frame_count := mini(PROJECTILE_TRAVEL_FRAMES, sprite_paths.size())
		frame_index = int(progress * duration * float(projectile.get("sprite_fps", 38.0))) % travel_frame_count
	var texture := _texture_at(sprite_paths[frame_index])
	if texture == null:
		return false
	var sprite_tint: Color = projectile.get("sprite_tint", Color.WHITE.lerp(color, 0.5))
	var draw_size: Vector2 = _IsoCoordinates.visual_vec(projectile.get("sprite_size", Vector2(50.0, 50.0)))
	draw_set_transform(position, tangent.angle(), Vector2.ONE)
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false, sprite_tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _texture_at(path: String) -> Texture2D:
	if _textures != null and _textures.has_method("texture_at"):
		return _textures.call("texture_at", path) as Texture2D
	return null


func _screen_anchor(grid: Vector2i) -> Vector2:
	if not _grid_to_screen.is_valid():
		return Vector2.ZERO
	return _grid_to_screen.call(grid) + _IsoCoordinates.visual_vec(Vector2(0, -20))
