extends Button

## 以单侧像素纹样为原型绘制菜单按钮；纹样只在选中时显现。

@export var ornament_texture: Texture2D
@export var prominent: bool = false

const FRAME_TIME := 0.055
const ORNAMENT_SIZE := Vector2(64, 33)
const ORNAMENT_COLOR := Color("#c9dce7")
const PALETTE_FLASH := Color("#fffdf7")
const TEXT_DEFAULT := Color("#c5c9cf")
const TEXT_HOVER := Color("#e8ebef")
const TEXT_ACTIVE := Color("#fffdf7")
const TEXT_DISABLED := Color("#59636d")
const GlowShader = preload("res://scenes/main/pixel_menu_button_glow.gdshader")

var _frame_accumulator := 0.0
var _spawn_clock := 0.0
var _hover_progress := 0.0
var _press_step := 0
var _flash_frames := 0
var _particle_serial := 0
var _particles: Array[Dictionary] = []
var _glow_material: ShaderMaterial


func _ready() -> void:
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_entered.connect(_wake_animation)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GlowShader
	material = _glow_material
	set_process(false)


func _process(delta: float) -> void:
	var hover_target := 1.0 if is_hovered() and not disabled else 0.0
	_hover_progress = move_toward(_hover_progress, hover_target, delta / 0.26)
	var glow := _hover_progress * 0.42
	if button_pressed or _flash_frames > 0:
		glow = 0.72
	_glow_material.set_shader_parameter("glow_strength", glow)
	_frame_accumulator += delta
	_spawn_clock += delta
	while _frame_accumulator >= FRAME_TIME:
		_frame_accumulator -= FRAME_TIME
		_step_animation()
	_update_particles(delta)
	queue_redraw()
	if _hover_progress <= 0.0 and _particles.is_empty() and _press_step <= 0 and _flash_frames <= 0:
		set_process(false)


func _step_animation() -> void:
	if _press_step > 0 and not button_pressed:
		_press_step -= 1
	if _flash_frames > 0:
		_flash_frames -= 1

	var interval := 0.14
	if _hover_progress > 0.05 and _spawn_clock >= interval:
		_spawn_clock = 0.0
		_spawn_stardust(true)


func _draw() -> void:
	if ornament_texture == null:
		return
	var center := Vector2(floor(size.x * 0.5), floor(size.y * 0.5))
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var gap := 22.0
	var inward := float(_press_step)
	var outward := _hover_progress * 18.0
	var left_x: float = floor(center.x - text_size.x * 0.5 - gap - ORNAMENT_SIZE.x - outward + inward)
	var top: float = floor(center.y - ORNAMENT_SIZE.y * 0.5)
	var tint := _ornament_color()

	if _hover_progress > 0.01 or _press_step > 0:
		draw_texture_rect(ornament_texture, Rect2(Vector2(left_x, top), ORNAMENT_SIZE), false, tint)
		draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(ornament_texture, Rect2(Vector2(left_x, top), ORNAMENT_SIZE), false, tint)
		draw_set_transform(Vector2.ZERO)

		_draw_extension_segments(left_x, top, tint)
		_draw_star_pulses(left_x, top)
		_draw_particles()
	_draw_pixel_text(center, font, font_size, text_size)


func _draw_extension_segments(left_x: float, top: float, color: Color) -> void:
	if _hover_progress <= 0.01:
		return
	var line_y: float = floor(top + 16.0)
	var extension: float = maxf(1.0, floor(_hover_progress * 24.0))
	draw_rect(Rect2(Vector2(left_x - extension, line_y), Vector2(extension + 10.0, 1)), color)
	draw_rect(Rect2(Vector2(size.x - left_x - 10.0, line_y), Vector2(extension + 10.0, 1)), color)


func _draw_star_pulses(left_x: float, top: float) -> void:
	if _hover_progress < 0.35 and _flash_frames <= 0:
		return
	var color := PALETTE_FLASH if _flash_frames > 0 else Color(ORNAMENT_COLOR, 0.58)
	var reach := 1 + int(_hover_progress > 0.92) + int(_flash_frames > 0)
	var left_star := Vector2(left_x + 50.0, top + 16.0)
	var right_star := Vector2(size.x - left_star.x, left_star.y)
	for star in [left_star, right_star]:
		draw_rect(Rect2(star + Vector2(-1, -reach - 4), Vector2(1, reach)), color)
		draw_rect(Rect2(star + Vector2(-1, 5), Vector2(1, reach)), color)
		draw_rect(Rect2(star + Vector2(-reach - 4, 0), Vector2(reach, 1)), color)
		draw_rect(Rect2(star + Vector2(5, 0), Vector2(reach, 1)), color)


func _draw_pixel_text(center: Vector2, font: Font, font_size: int, text_size: Vector2) -> void:
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(
		floor(center.x - text_size.x * 0.5),
		floor(center.y + (ascent - descent) * 0.5)
	)
	var color := TEXT_DISABLED if disabled else TEXT_DEFAULT.lerp(TEXT_HOVER, _hover_progress * 0.72)
	if button_pressed or _flash_frames > 0:
		color = TEXT_ACTIVE
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _ornament_color() -> Color:
	if disabled:
		return Color.TRANSPARENT
	var color := ORNAMENT_COLOR
	color.a = smoothstep(0.0, 0.75, _hover_progress) * 0.88
	return PALETTE_FLASH if _flash_frames > 0 else color


func _spawn_stardust(active: bool) -> void:
	_particle_serial += 1
	var side := -1.0 if _particle_serial % 2 == 0 else 1.0
	var center_x := size.x * 0.5 + side * (90.0 + _hover_progress * 18.0)
	var y_offset := float((_particle_serial * 7) % 17 - 8)
	var drift := side * (6.0 if active else 2.0)
	_particles.append({
		"pos": Vector2(round(center_x), round(size.y * 0.5 + y_offset)),
		"velocity": Vector2(drift, -2.0 if active else 0.0),
		"life": 0.55 if active else 0.28,
		"max_life": 0.55 if active else 0.28,
		"size": 2 if active and _particle_serial % 3 == 0 else 1,
	})


func _update_particles(delta: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[i]
		particle.life = float(particle.life) - delta
		if float(particle.life) <= 0.0:
			_particles.remove_at(i)
			continue
		particle.pos = Vector2(particle.pos) + Vector2(particle.velocity) * delta
		_particles[i] = particle


func _draw_particles() -> void:
	for particle in _particles:
		var alpha: float = clamp(float(particle.life) / float(particle.max_life), 0.0, 1.0)
		var pixel_size := int(particle.size)
		var pos := Vector2(round(Vector2(particle.pos).x), round(Vector2(particle.pos).y))
		draw_rect(Rect2(pos, Vector2(pixel_size, pixel_size)), Color(ORNAMENT_COLOR, alpha * 0.7))


func _on_button_down() -> void:
	_wake_animation()
	_press_step = 2
	_flash_frames = 3
	for i in 4:
		_spawn_stardust(true)
	queue_redraw()


func _on_button_up() -> void:
	_wake_animation()
	_press_step = 1
	queue_redraw()


func _wake_animation() -> void:
	set_process(true)
