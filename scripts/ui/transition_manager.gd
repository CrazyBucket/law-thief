extends Node

signal transition_started(style: int)
signal transition_midpoint(style: int)
signal transition_finished(style: int)

enum Style {
	CHECKERBOARD,
	SILHOUETTE,
}

enum MaskChannel {
	ALPHA,
	LUMINANCE,
	INVERSE_LUMINANCE,
}

enum Direction {
	OUT,
	IN,
}

const DEFAULT_DURATION := 0.42
const DEFAULT_COVER_COLOR := Color.BLACK
const DEFAULT_ACCENT_COLOR := Color.BLACK
const CHECKERBOARD_SHADER := preload("res://scenes/ui/transition_checkerboard.gdshader")
const SILHOUETTE_SHADER := preload("res://scenes/ui/transition_silhouette.gdshader")
const DEFAULT_SILHOUETTE_PATH := "res://assets/ui/transitions/star_silhouette.png"

@onready var _overlay: ColorRect = $TransitionLayer/Overlay

var _materials: Dictionary = {}
var _transitioning := false
var _covered := false
var _current_style := Style.CHECKERBOARD
var _active_tween: Tween = null
var _default_silhouette: Texture2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_default_silhouette = _load_default_silhouette()
	_materials[Style.CHECKERBOARD] = _create_material(CHECKERBOARD_SHADER)
	_materials[Style.SILHOUETTE] = _create_material(SILHOUETTE_SHADER)
	get_viewport().size_changed.connect(_sync_viewport_parameters)
	_reset_overlay()


func _input(_event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()


func is_transitioning() -> bool:
	return _transitioning


func is_covered() -> bool:
	return _covered


func current_style() -> int:
	return _current_style


func change_scene(
	scene_path: String,
	style: int = Style.CHECKERBOARD,
	duration: float = DEFAULT_DURATION,
	options: Dictionary = {},
	direction: int = Direction.OUT
) -> int:
	if _transitioning:
		return ERR_BUSY
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	if direction == Direction.IN:
		if not _hold_fully_covered(style, options):
			return ERR_INVALID_PARAMETER
		var in_error := get_tree().change_scene_to_file(scene_path)
		if in_error != OK:
			reset_immediately()
			return in_error
		await _wait_until_scene_rendered()
		transition_midpoint.emit(style)
		await reveal(duration)
		return OK
	if direction != Direction.OUT:
		return ERR_INVALID_PARAMETER
	if not await cover(style, duration, options):
		return ERR_INVALID_PARAMETER
	var out_error := get_tree().change_scene_to_file(scene_path)
	if out_error != OK:
		reset_immediately()
		return out_error
	await get_tree().process_frame
	var finished_style := _current_style
	_reset_overlay()
	transition_finished.emit(finished_style)
	return OK


func cover(
	style: int = Style.CHECKERBOARD,
	duration: float = DEFAULT_DURATION,
	options: Dictionary = {}
) -> bool:
	if _transitioning or not _materials.has(style):
		return false
	_transitioning = true
	_covered = false
	_current_style = style
	_configure_material(style, options)
	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_progress(0.0)
	transition_started.emit(style)
	await _animate_progress(1.0, duration)
	_covered = true
	transition_midpoint.emit(style)
	return true


func reveal(duration: float = DEFAULT_DURATION) -> bool:
	if not _transitioning or not _covered:
		return false
	await _animate_progress(0.0, duration)
	var finished_style := _current_style
	_reset_overlay()
	transition_finished.emit(finished_style)
	return true


func reset_immediately() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_reset_overlay()


func _hold_fully_covered(style: int, options: Dictionary) -> bool:
	if _transitioning or not _materials.has(style):
		return false
	_transitioning = true
	_covered = true
	_current_style = style
	_configure_material(style, options)
	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_progress(1.0)
	transition_started.emit(style)
	return true


func _create_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _configure_material(style: int, options: Dictionary) -> void:
	var material := _materials[style] as ShaderMaterial
	_overlay.material = material
	var cover_color := options.get("cover_color", DEFAULT_COVER_COLOR) as Color
	material.set_shader_parameter("cover_color", cover_color)
	match style:
		Style.CHECKERBOARD:
			material.set_shader_parameter("grid_size", _checkerboard_grid(options))
			material.set_shader_parameter("stagger", clampf(float(options.get("stagger", 0.16)), 0.0, 0.35))
			material.set_shader_parameter("edge_width", clampf(float(options.get("edge_width", 0.035)), 0.0, 0.12))
			material.set_shader_parameter("edge_color", options.get("accent_color", DEFAULT_ACCENT_COLOR) as Color)
		Style.SILHOUETTE:
			var mask_texture := options.get("mask_texture", _default_silhouette) as Texture2D
			if mask_texture == null:
				mask_texture = _default_silhouette
			material.set_shader_parameter("mask_texture", mask_texture)
			material.set_shader_parameter("mask_aspect", _texture_aspect(mask_texture))
			material.set_shader_parameter("center", _normalized_center(options.get("center", Vector2(0.5, 0.5))))
			material.set_shader_parameter("maximum_scale", clampf(float(options.get("maximum_scale", 1.15)), 0.1, 4.0))
			material.set_shader_parameter("fill_start", clampf(float(options.get("fill_start", 0.6)), 0.25, 0.9))
			material.set_shader_parameter("mask_channel", clampi(int(options.get("mask_channel", MaskChannel.INVERSE_LUMINANCE)), 0, 2))
	_sync_viewport_parameters()


func _checkerboard_grid(options: Dictionary) -> Vector2:
	var columns := clampi(int(options.get("columns", 10)), 2, 64)
	var rows_value: Variant = options.get("rows", 0)
	var rows := int(rows_value)
	if rows <= 0:
		var viewport_size := get_viewport().get_visible_rect().size
		rows = maxi(2, roundi(float(columns) * viewport_size.y / maxf(viewport_size.x, 1.0)))
	return Vector2(columns, clampi(rows, 2, 64))


func _texture_aspect(texture: Texture2D) -> float:
	var size := texture.get_size()
	return size.x / maxf(size.y, 1.0)


func _load_default_silhouette() -> Texture2D:
	var image := Image.new()
	var png_bytes := FileAccess.get_file_as_bytes(DEFAULT_SILHOUETTE_PATH)
	var error := image.load_png_from_buffer(png_bytes)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


func _normalized_center(value: Variant) -> Vector2:
	var center := value as Vector2
	return Vector2(clampf(center.x, 0.0, 1.0), clampf(center.y, 0.0, 1.0))


func _sync_viewport_parameters() -> void:
	var material := _materials.get(Style.SILHOUETTE) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)


func _wait_until_scene_rendered() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw


func _animate_progress(target: float, duration: float) -> void:
	if duration <= 0.0:
		_set_progress(target)
		await get_tree().process_frame
		return
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_trans(Tween.TRANS_CUBIC)
	_active_tween.set_ease(Tween.EASE_IN_OUT)
	var material := _overlay.material as ShaderMaterial
	var current := float(material.get_shader_parameter("progress"))
	_active_tween.tween_method(_set_progress, current, target, maxf(duration, 0.01))
	await _active_tween.finished
	_active_tween = null


func _set_progress(value: float) -> void:
	var material := _overlay.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func _reset_overlay() -> void:
	_transitioning = false
	_covered = false
	_active_tween = null
	if _overlay == null:
		return
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_progress(0.0)
