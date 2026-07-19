class_name BattleProjectileFx
extends Node2D

const _IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")

signal finished()

var _grid_to_screen: Callable = Callable()
var _projectiles: Array[Dictionary] = []


## 投射物层拥有自己的飞行状态和绘制；外层只提供网格投影与播放请求。
func configure(grid_to_screen: Callable) -> void:
	_grid_to_screen = grid_to_screen


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
		max_duration = maxf(max_duration, duration)
		_projectiles.append({
			"from": from_screen,
			"to": to_screen,
			"control": control,
			"progress": 0.0,
			"color": shot.get("color", Color(0.95, 0.92, 0.45)),
		})
	queue_redraw()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_progress, 0.0, 1.0, max_duration)
	tween.tween_callback(_finish)


func active_count() -> int:
	return _projectiles.size()


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
		draw_line(position, trail_position, trail_color, maxf(_IsoCoordinates.visual(3.0) - trail_ratio * _IsoCoordinates.visual(1.5), _IsoCoordinates.visual(0.5)))

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


func _screen_anchor(grid: Vector2i) -> Vector2:
	if not _grid_to_screen.is_valid():
		return Vector2.ZERO
	return _grid_to_screen.call(grid) + _IsoCoordinates.visual_vec(Vector2(0, -20))
