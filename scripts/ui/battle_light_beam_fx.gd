class_name BattleLightBeamFx
extends Node2D

const _IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")

var _grid_to_screen: Callable = Callable()
var _soft_texture: Texture2D = null
var _active_beams: Array[Node2D] = []


## 该层只管理光束节点与时间线；坐标投影和战斗事件解释由外层提供。
func configure(grid_to_screen: Callable) -> void:
	_grid_to_screen = grid_to_screen


func play(beams: Array, config: Dictionary) -> float:
	var duration := float(config.get("duration", 0.0))
	for spec in beams:
		var beam := _create_beam(
			spec.get("from", Vector2i.ZERO),
			spec.get("to", Vector2i.ZERO),
			spec.get("color", Color(1.0, 0.96, 0.58)),
			float(spec.get("width", 1.0)),
			spec.get("fx", spec),
			config,
			spec.get("from_screen", null)
		)
		if beam == null:
			continue
		var material := beam.material as ShaderMaterial
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(beam, "modulate:a", 0.0, duration * 0.72).set_delay(duration * 0.28)
		if material != null:
			tween.tween_method(func(value: float) -> void:
				material.set_shader_parameter("pulse", value)
			, 0.0, 1.0, duration)
		tween.finished.connect(_finish_beam.bind(beam), CONNECT_ONE_SHOT)
	return duration


func _create_beam(
	from_grid: Vector2i,
	to_grid: Vector2i,
	beam_color: Color,
	beam_width: float,
	fx: Dictionary,
	config: Dictionary,
	visual_from: Variant = null
) -> Node2D:
	var from_screen := _anchor(from_grid, config)
	if visual_from is Vector2:
		from_screen = visual_from + _IsoCoordinates.visual_vec(Vector2(0, float(config.get("plane_height", 0.0))))
	from_screen += _IsoCoordinates.visual_vec(Vector2(0, float(config.get("source_drop", 0.0))))
	var to_screen := _anchor(to_grid, config)
	var delta := to_screen - from_screen
	if delta.length() < 1.0:
		return null
	var direction := delta.normalized()
	var width := _IsoCoordinates.visual(
		float(config.get("base_half_width", 0.0))
		* maxf(0.1, beam_width)
		* float(config.get("global_scale", 1.0))
	)
	var beam := Node2D.new()
	var cursor := from_screen
	var active_color := beam_color
	var blend_half_length := _IsoCoordinates.visual(22.0)
	for transition_value in fx.get("dye_transitions", []):
		var transition: Dictionary = transition_value
		var transition_center := _axis_point(from_screen, to_screen, transition.get("cell", to_grid), config)
		var blend_from := transition_center - direction * blend_half_length
		var blend_to := transition_center + direction * blend_half_length
		if (blend_from - cursor).dot(direction) > 1.0:
			_add_line_stack(beam, cursor, blend_from, active_color, active_color, width, fx, config)
		var next_color: Color = transition.get("color", active_color)
		_add_line_stack(beam, blend_from, blend_to, active_color, next_color, width, fx, config)
		cursor = blend_to
		active_color = next_color
	if (to_screen - cursor).dot(direction) > 1.0:
		_add_line_stack(beam, cursor, to_screen, active_color, active_color, width, fx, config)
	_add_endpoint_fx(beam, from_screen, to_screen, beam_color, active_color, width, fx, config)
	for hit_value in fx.get("hit_effects", []):
		var hit: Dictionary = hit_value
		var hit_center := _axis_point(from_screen, to_screen, hit.get("cell", to_grid), config)
		_add_hit_fx(beam, hit_center, hit.get("color", active_color), width)
	add_child(beam)
	_active_beams.append(beam)
	return beam


func _finish_beam(beam: Node2D) -> void:
	if is_instance_valid(beam):
		beam.queue_free()
	_active_beams.erase(beam)


func _add_line_stack(parent: Node2D, from_screen: Vector2, to_screen: Vector2, from_color: Color, to_color: Color, width: float, fx: Dictionary, config: Dictionary) -> void:
	var power := float(fx.get("power", 1.0)) * float(config.get("global_power", 1.0))
	_add_line(parent, from_screen, to_screen, width * 2.0, from_color, to_color, 0.42 * power)
	_add_line(parent, from_screen, to_screen, width * 1.06, from_color, to_color, 0.58 * power)
	_add_line(parent, from_screen, to_screen, width * 0.2, from_color.lerp(Color.WHITE, 0.22), to_color.lerp(Color.WHITE, 0.22), 0.78 * power)


func _add_line(parent: Node2D, from_screen: Vector2, to_screen: Vector2, line_width: float, from_color: Color, to_color: Color, alpha: float) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from_screen, to_screen])
	line.width = line_width
	line.antialiased = true
	line.texture = _soft_line_texture()
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var gradient := Gradient.new()
	gradient.set_color(0, Color(from_color.r, from_color.g, from_color.b, alpha))
	gradient.set_color(1, Color(to_color.r, to_color.g, to_color.b, alpha))
	line.gradient = gradient
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = material
	parent.add_child(line)


func _soft_line_texture() -> Texture2D:
	if _soft_texture != null:
		return _soft_texture
	var image := Image.create(8, 64, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		var normalized := absf((float(y) + 0.5) / float(image.get_height()) - 0.5) * 2.0
		var alpha := pow(maxf(0.0, 1.0 - normalized), 1.65)
		for x in range(image.get_width()):
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_soft_texture = ImageTexture.create_from_image(image)
	return _soft_texture


func _anchor(grid: Vector2i, config: Dictionary) -> Vector2:
	if not _grid_to_screen.is_valid():
		return Vector2.ZERO
	return _grid_to_screen.call(grid) + _IsoCoordinates.visual_vec(Vector2(0, float(config.get("plane_height", 0.0))))


func _axis_point(from_screen: Vector2, to_screen: Vector2, grid: Vector2i, config: Dictionary) -> Vector2:
	var axis := to_screen - from_screen
	var length_squared := axis.length_squared()
	if length_squared < 1.0:
		return from_screen
	var raw := _anchor(grid, config)
	var ratio := clampf((raw - from_screen).dot(axis) / length_squared, 0.0, 1.0)
	return from_screen + axis * ratio


func _add_endpoint_fx(parent: Node2D, from_screen: Vector2, to_screen: Vector2, from_color: Color, to_color: Color, width: float, fx: Dictionary, config: Dictionary) -> void:
	var power := float(fx.get("power", 1.0)) * float(config.get("global_power", 1.0))
	_add_ring(parent, from_screen, width * 0.28, from_color, 0.42 * power)
	_add_ring(parent, to_screen, width * 0.38, to_color, 0.28 * power)
	var direction := (to_screen - from_screen).normalized()
	_add_line(parent, from_screen - direction * width * 0.5, from_screen + direction * width * 0.72, width * 0.34, from_color, from_color, 0.7 * power)
	_add_line(parent, to_screen - direction * width * 0.5, to_screen + direction * width * 0.28, width * 0.28, to_color, to_color, 0.42 * power)


func _add_hit_fx(parent: Node2D, center: Vector2, color: Color, width: float) -> void:
	_add_ring(parent, center, width * 0.48, color, 0.48)
	_add_ring(parent, center, width * 0.27, color.lerp(Color.WHITE, 0.25), 0.68)
	var flare_length := width * 0.58
	_add_line(parent, center - Vector2(flare_length, 0), center + Vector2(flare_length, 0), width * 0.08, color, color, 0.48)
	_add_line(parent, center - Vector2(0, flare_length), center + Vector2(0, flare_length), width * 0.08, color, color, 0.48)


func _add_ring(parent: Node2D, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for index in range(17):
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	ring.points = points
	ring.width = maxf(_IsoCoordinates.visual(1.5), radius * 0.12)
	ring.antialiased = true
	ring.default_color = Color(color.r, color.g, color.b, alpha)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = material
	parent.add_child(ring)
