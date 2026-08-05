class_name TileRenderer
extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const PoisonCloudRendererClass := preload("res://scripts/map/poison_cloud_renderer.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const _AdventureRoomIcons := preload("res://scripts/ui/adventure_room_icons.gd")
const GRASS_SPROUTS_PATH := "res://assets/overlays/vegetation/overlay_grass_sprouts.png"
const GRASS_PATCH_PATH := "res://assets/overlays/vegetation/overlay_grass_patch.png"
const GRASS_TALL_PATH := "res://assets/overlays/vegetation/overlay_grass_tall.png"
const GRASS_THICKET_PATH := "res://assets/overlays/vegetation/overlay_grass_thicket.png"
const POISON_WATER_GLINTS_PATH := "res://assets/overlays/effects/overlay_poison_water_glints.png"
const POISON_CLOUD_PARTS_PATH := PoisonCloudRendererClass.ATLAS_PATH
const POISON_FOG_CLOUD_TEXTURE_KEY := PoisonCloudRendererClass.FOG_TEXTURE_KEY
const TOXIC_SMOKE_CLOUD_TEXTURE_KEY := PoisonCloudRendererClass.SMOKE_TEXTURE_KEY
const FIRE_LOOP_PATH := "res://assets/overlays/effects/overlay_fire_loop.png"
const SIDE_DEPTH := 10.0
const PASS_BACK := "back"
const PASS_FRONT := "front"
static var _overlay_texture_cache: Dictionary = {}
static var _animated_overlay_textures: Dictionary = {}
static var _overlay_texture_content_rects: Dictionary = {}
static func _time_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

static func draw_tile(canvas: Control, center: Vector2, tile: TileState, highlight_color: Color = Color.TRANSPARENT) -> void:
	var palette: Dictionary = _palette(tile)
	var top_color: Color = palette["top"]
	if highlight_color.a > 0.0:
		top_color = top_color.lerp(highlight_color, highlight_color.a)
	_draw_block(canvas, center, top_color, palette["left"], palette["right"])
	_draw_tile_detail(canvas, center, tile)
	if tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
		_draw_poison_puddle(canvas, center)
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
		_draw_poison_fog(canvas, center, tile.pos, false)
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		_draw_toxic_smoke(canvas, center, tile.pos, false)
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		_draw_fire(canvas, center, false)


## 仅绘制叠加层（高亮、特殊地块、状态），不画地砖底块——底块改由贴图统一渲染
static func draw_tile_overlays(
	canvas: Control,
	center: Vector2,
	tile: TileState,
	highlight_color: Color = Color.TRANSPARENT,
	draw_pass: String = PASS_BACK,
	occupied: bool = false,
	modifier_visuals: Variant = null
) -> void:
	if draw_pass == PASS_BACK:
		if highlight_color.a > 0.0:
			draw_highlight_fill(canvas, center, highlight_color)
		if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
			_draw_room_label(canvas, center, tile.tile_id)
	_draw_surface_overlay(canvas, center, tile, draw_pass, occupied)
	_draw_modifier_overlays(canvas, center, tile, draw_pass, occupied, modifier_visuals)


static func draw_hover_outline(canvas: Control, center: Vector2, color: Color = Color(0.95, 0.95, 1.0, 0.95)) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	canvas.draw_polyline(closed, color, 2.5 * IsoCoordinates.tile_scale, false)


static func draw_highlight_fill(canvas: Control, center: Vector2, color: Color) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	canvas.draw_colored_polygon(corners, color)


static func _draw_block(canvas: Control, center: Vector2, top: Color, left: Color, right: Color) -> void:
	var half_w := IsoCoordinates._half_w()
	var half_h := IsoCoordinates._half_h()
	var depth := SIDE_DEPTH * IsoCoordinates.tile_scale
	var top_pts: PackedVector2Array = IsoCoordinates.diamond_corners(center)
	# top_pts: [0]=top, [1]=right, [2]=bottom, [3]=left
	var left_face := PackedVector2Array([
		top_pts[3],
		top_pts[2],
		top_pts[2] + Vector2(0, depth),
		top_pts[3] + Vector2(0, depth),
	])
	var right_face := PackedVector2Array([
		top_pts[2],
		top_pts[1],
		top_pts[1] + Vector2(0, depth),
		top_pts[2] + Vector2(0, depth),
	])
	canvas.draw_colored_polygon(left_face, left)
	canvas.draw_colored_polygon(right_face, right)
	canvas.draw_colored_polygon(top_pts, top)
	canvas.draw_polyline(top_pts, top.darkened(0.28), 1.2, true)


static func _draw_overlay(canvas: Control, center: Vector2, color: Color) -> void:
	var half_w := IsoCoordinates._half_w() * 0.7
	var half_h := IsoCoordinates._half_h() * 0.55
	var points := PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])
	canvas.draw_colored_polygon(points, color)


static func _overlay_phase_seed(center: Vector2) -> float:
	return center.x * 0.017 + center.y * 0.031


static func _draw_surface_overlay(
	canvas: Control,
	center: Vector2,
	tile: TileState,
	draw_pass: String,
	occupied: bool
) -> void:
	match tile.tile_id:
		Constants.TILE_GRASS:
			_draw_grass_overlay(canvas, center, tile, draw_pass, occupied, false)
		Constants.TILE_BUSH:
			_draw_grass_overlay(canvas, center, tile, draw_pass, occupied, true)


static func _draw_modifier_overlays(
	canvas: Control,
	center: Vector2,
	tile: TileState,
	draw_pass: String,
	occupied: bool,
	modifier_visuals: Variant
) -> void:
	if draw_pass == PASS_BACK:
		if tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
			_draw_poison_puddle(canvas, center, _modifier_stage(tile, Constants.TILE_MOD_POISON_PUDDLE, 2))
	var fog_visual := _modifier_visual(
		tile,
		Constants.TILE_MOD_POISON_FOG,
		CombatConfig.poison_fog_duration(),
		modifier_visuals
	)
	if float(fog_visual["alpha"]) > 0.001:
		if draw_pass == PASS_BACK:
			_draw_poison_fog(canvas, center, tile.pos, false, fog_visual["stage"], occupied, fog_visual["alpha"])
		elif occupied:
			_draw_poison_fog(canvas, center, tile.pos, true, fog_visual["stage"], occupied, fog_visual["alpha"])
	var smoke_visual := _modifier_visual(
		tile,
		Constants.TILE_MOD_TOXIC_SMOKE,
		CombatConfig.toxic_smoke_duration(),
		modifier_visuals
	)
	if float(smoke_visual["alpha"]) > 0.001:
		if draw_pass == PASS_BACK:
			_draw_toxic_smoke(canvas, center, tile.pos, false, smoke_visual["stage"], occupied, smoke_visual["alpha"])
		elif occupied:
			_draw_toxic_smoke(canvas, center, tile.pos, true, smoke_visual["stage"], occupied, smoke_visual["alpha"])
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		var fire_stage := _modifier_stage(tile, Constants.TILE_MOD_FIRE, CombatConfig.fire_duration())
		if draw_pass == PASS_BACK:
			_draw_fire(canvas, center, false, fire_stage)
		elif occupied:
			_draw_fire(canvas, center, true, fire_stage)


static func _modifier_visual(
	tile: TileState,
	effect_type: String,
	default_duration: int,
	provided: Variant
) -> Dictionary:
	if provided is Dictionary:
		if provided.has(effect_type):
			return provided[effect_type]
		return {"alpha": 0.0, "stage": 1.0}
	if tile.has_modifier(effect_type):
		return {
			"alpha": 1.0,
			"stage": _modifier_stage(tile, effect_type, default_duration),
		}
	return {"alpha": 0.0, "stage": 1.0}


static func _draw_tile_detail(canvas: Control, center: Vector2, tile: TileState) -> void:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		_draw_room_label(canvas, center, tile.tile_id)
		return
	match tile.tile_id:
		Constants.TILE_FLOOR:
			_draw_floor_noise(canvas, center, tile.floor_variant)


static func draw_spikes(canvas: Control, center: Vector2) -> void:
	var offsets := [Vector2(-10, 2), Vector2(0, -4), Vector2(10, 2)]
	for offset in offsets:
		var base: Vector2 = center + offset
		canvas.draw_line(base + Vector2(-4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)
		canvas.draw_line(base + Vector2(4, 4), base + Vector2(0, -10), Color(0.95, 0.55, 0.45), 2.0)


static func draw_entity_texture(canvas: Control, center: Vector2, texture: Texture2D, scale_factor: float = 1.0) -> void:
	if texture == null:
		return
	var target_h := IsoCoordinates.visual(76.0) * scale_factor
	var target_w := target_h * float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
	var foot := center + IsoCoordinates.entity_foot_offset()
	var rect := Rect2(foot.x - target_w * 0.5, foot.y - target_h, target_w, target_h)
	canvas.draw_texture_rect(texture, rect, false, Color.WHITE)


static func draw_prop_sprite(canvas: Control, center: Vector2, texture: Texture2D, foot_ratio: float = 1.0) -> void:
	if texture == null:
		return
	var rect := IsoCoordinates.prop_draw_rect(center, texture, foot_ratio)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	canvas.draw_texture_rect(texture, rect, false, Color.WHITE)


static func draw_prop_fallback(canvas: Control, center: Vector2) -> void:
	var foot := center + IsoCoordinates.entity_foot_offset()
	var half_w := IsoCoordinates._half_w() * 0.28
	var half_h := IsoCoordinates._half_h() * 0.32
	var rock := PackedVector2Array([
		foot + Vector2(-half_w, -half_h * 0.1),
		foot + Vector2(0.0, -half_h * 1.15),
		foot + Vector2(half_w, -half_h * 0.1),
		foot + Vector2(0.0, half_h * 0.02),
	])
	canvas.draw_colored_polygon(rock, Color(0.42, 0.44, 0.48, 0.95))
	canvas.draw_polyline(rock, Color(0.28, 0.3, 0.34, 0.9), IsoCoordinates.visual(1.2), true)


static func _draw_floor_noise(canvas: Control, center: Vector2, variant: int) -> void:
	var dot_color := Color(1, 1, 1, 0.04 + variant * 0.015)
	canvas.draw_circle(center + Vector2(-8, -2), 1.5, dot_color)
	canvas.draw_circle(center + Vector2(6, 4), 1.2, dot_color)


static func _draw_room_label(canvas: Control, center: Vector2, tile_id: String) -> void:
	var room_type: String = _AdventureRoomDisplay.room_type_from_tile(tile_id)
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	var room_color: Color = display.get("color", Color.WHITE)
	var icon_tex := _AdventureRoomIcons.get_icon(str(display.get("icon_id", "")))
	if icon_tex != null:
		var icon_size := IsoCoordinates.visual(34.0)
		var icon_center := center + Vector2(0.0, IsoCoordinates.visual(-12.0))
		var icon_rect := Rect2(icon_center - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size)
		var shadow_center := center + Vector2(0.0, IsoCoordinates.visual(5.0))
		canvas.draw_circle(shadow_center, IsoCoordinates.visual(11.0), Color(0.0, 0.0, 0.0, 0.26))
		canvas.draw_circle(icon_center, IsoCoordinates.visual(15.0), Color(room_color.darkened(0.42), 0.16))
		canvas.draw_texture_rect(icon_tex, icon_rect, false, Color.WHITE)
	else:
		var font: Font = ThemeDB.fallback_font
		var label: String = display["label"]
		var short_label := str(display.get("short", label.substr(0, 1)))
		var short_size := 18
		var short_dims := font.get_string_size(short_label, HORIZONTAL_ALIGNMENT_CENTER, -1, short_size)
		canvas.draw_string(
			font,
			Vector2(center.x - short_dims.x * 0.5, center.y + short_dims.y * 0.15),
			short_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			short_size,
			Color(1, 1, 1, 0.95)
		)


static func _room_palette(tile_id: String) -> Dictionary:
	var room_type: String = _AdventureRoomDisplay.room_type_from_tile(tile_id)
	var base: Color = _AdventureRoomDisplay.get_display(
		room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)["color"]
	return {
		"top": base.darkened(0.15),
		"left": base.darkened(0.35),
		"right": base.darkened(0.25),
	}


static func _palette(tile: TileState) -> Dictionary:
	if _AdventureRoomDisplay.is_room_tile(tile.tile_id):
		return _room_palette(tile.tile_id)
	match tile.tile_id:
		Constants.TILE_WATER:
			return {
				"top": Color(0.18, 0.34, 0.58),
				"left": Color(0.12, 0.24, 0.42),
				"right": Color(0.14, 0.28, 0.48),
			}
		_:
			var even := (tile.pos.x + tile.pos.y) % 2 == 0
			var variant := tile.floor_variant
			var base_color: Color = Color(0.26, 0.26, 0.32) if even else Color(0.22, 0.22, 0.28)
			base_color = base_color.lightened(variant * 0.015)
			return {
				"top": base_color,
				"left": base_color.darkened(0.18),
				"right": base_color.darkened(0.1),
			}


static func _draw_grass_overlay(
	canvas: Control,
	center: Vector2,
	tile: TileState,
	draw_pass: String,
	occupied: bool,
	dense: bool
) -> void:
	if draw_pass == PASS_FRONT and not occupied:
		return
	var texture := _grass_texture_for_tile(tile, dense)
	if texture == null:
		return
	var content_rect := _overlay_texture_content_rect(texture)
	var width_ratio := 0.46 if not dense else 0.52
	var bottom_anchor := center + Vector2(0.0, IsoCoordinates._half_h() * (0.62 if not dense else 0.66))
	var sway_px := IsoCoordinates.visual(3.0 if not dense else 2.2)
	var clip_from := 0.0
	var clip_to := 1.0
	var alpha := 0.78
	if draw_pass == PASS_FRONT:
		clip_from = 0.56 if not dense else 0.60
		alpha = 0.82
		sway_px *= 0.8
	_draw_swaying_texture(
		canvas,
		bottom_anchor,
		texture,
		content_rect,
		width_ratio,
		sway_px,
		_grass_phase_seed(tile),
		clip_from,
		clip_to,
		alpha
	)


static func _grass_texture_for_tile(tile: TileState, dense: bool) -> Texture2D:
	match str(tile.surface_variant):
		"sprouts":
			return _load_overlay_texture(GRASS_SPROUTS_PATH)
		"patch":
			return _load_overlay_texture(GRASS_PATCH_PATH)
		"tall":
			return _load_overlay_texture(GRASS_TALL_PATH)
		"thicket":
			return _load_overlay_texture(GRASS_THICKET_PATH)
	var variant: int = abs(tile.pos.x * 29 + tile.pos.y * 17 + tile.floor_variant * 7)
	if dense:
		return _load_overlay_texture(GRASS_THICKET_PATH) if variant % 3 != 0 else _load_overlay_texture(GRASS_TALL_PATH)
	if variant % 4 == 0:
		return _load_overlay_texture(GRASS_SPROUTS_PATH)
	if variant % 3 == 0:
		return _load_overlay_texture(GRASS_TALL_PATH)
	return _load_overlay_texture(GRASS_PATCH_PATH)


static func _grass_phase_seed(tile: TileState) -> float:
	return float(abs(tile.pos.x * 13 + tile.pos.y * 19 + tile.floor_variant * 11)) * 0.37


static func _load_overlay_texture(path: String) -> Texture2D:
	var animated := _animated_overlay_textures.get(path) as Texture2D
	if animated != null:
		return animated
	if _overlay_texture_cache.has(path):
		return _overlay_texture_cache[path]
	# Prefer imported project textures so overlay assets stay export-safe.
	var texture := load(path) as Texture2D
	if texture == null:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			return null
		texture = ImageTexture.create_from_image(image)
	_overlay_texture_content_rects[texture.get_instance_id()] = _texture_visible_rect(texture)
	_overlay_texture_cache[path] = texture
	return texture


static func register_animated_overlay_texture(path: String, texture: Texture2D, content_rect: Rect2 = Rect2()) -> void:
	if texture == null:
		_animated_overlay_textures.erase(path)
		return
	_animated_overlay_textures[path] = texture
	_overlay_texture_content_rects[texture.get_instance_id()] = content_rect if content_rect.size.x > 0.0 and content_rect.size.y > 0.0 else Rect2(Vector2.ZERO, texture.get_size())


static func _overlay_texture_content_size(texture: Texture2D, source_rect: Rect2 = Rect2()) -> Vector2:
	return _overlay_texture_content_rect(texture, source_rect).size


static func _overlay_texture_content_rect(texture: Texture2D, source_rect: Rect2 = Rect2()) -> Rect2:
	if texture == null:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	if source_rect.size.x > 0.0 and source_rect.size.y > 0.0:
		return source_rect
	var cached = _overlay_texture_content_rects.get(texture.get_instance_id(), Rect2())
	if cached is Rect2 and cached.size.x > 0.0 and cached.size.y > 0.0:
		return cached
	var visible := _texture_visible_rect(texture)
	_overlay_texture_content_rects[texture.get_instance_id()] = visible
	return visible


static func _texture_visible_rect(texture: Texture2D) -> Rect2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture.get_size())
	if image.is_compressed():
		image.decompress()
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var step := 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			if image.get_pixel(x, y).a <= 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2(Vector2.ZERO, texture.get_size())
	return Rect2(float(min_x), float(min_y), float(max_x - min_x + step), float(max_y - min_y + step))


static func _modifier_stage(tile: TileState, modifier_type: String, default_duration: int) -> float:
	if tile == null:
		return 1.0
	var modifier := tile.get_modifier(modifier_type)
	var duration := maxf(1.0, float(int(modifier.get("duration", default_duration))))
	var baseline := maxf(1.0, maxf(float(default_duration), duration))
	return clampf(duration / baseline, 0.25, 1.0)


static func _draw_swaying_texture(
	canvas: Control,
	center: Vector2,
	texture: Texture2D,
	content_rect: Rect2,
	width_ratio: float,
	sway_px: float,
	phase_seed: float,
	clip_from: float,
	clip_to: float,
	alpha: float
) -> void:
	if texture == null:
		return
	var width := IsoCoordinates._tile_w() * width_ratio
	var height := width * content_rect.size.y / maxf(content_rect.size.x, 1.0)
	var base_rect := Rect2(center.x - width * 0.5, center.y - height, width, height)
	var y0 := clampf(clip_from, 0.0, 1.0)
	var y1 := clampf(clip_to, 0.0, 1.0)
	if y1 <= y0:
		return
	var slice_count := maxi(6, int(round(width / maxf(IsoCoordinates.visual(8.0), 1.0))))
	for i in range(slice_count):
		var u0 := float(i) / float(slice_count)
		var u1 := float(i + 1) / float(slice_count)
		var src := Rect2(
			content_rect.position.x + content_rect.size.x * u0,
			content_rect.position.y + content_rect.size.y * y0,
			maxf(1.0, content_rect.size.x * (u1 - u0)),
			maxf(1.0, content_rect.size.y * (y1 - y0))
		)
		var dest := Rect2(
			base_rect.position.x + base_rect.size.x * u0,
			base_rect.position.y + base_rect.size.y * y0,
			maxf(1.0, base_rect.size.x * (u1 - u0)),
			maxf(1.0, base_rect.size.y * (y1 - y0))
		)
		var top_weight := 1.0 - ((dest.position.y + dest.size.y * 0.5) - base_rect.position.y) / maxf(base_rect.size.y, 1.0)
		top_weight = clampf(top_weight, 0.0, 1.0)
		var wave := sin(_time_sec() * 1.55 + phase_seed + float(i) * 0.43) * sway_px * top_weight
		dest.position.x += wave
		canvas.draw_texture_rect_region(texture, dest, src, Color(1.0, 1.0, 1.0, alpha), false)


static func _draw_fire(canvas: Control, center: Vector2, front: bool, stage: float = 1.0) -> void:
	var texture := _load_overlay_texture(FIRE_LOOP_PATH)
	if texture == null:
		return
	var frame_source := _fire_frame_source(texture, center)
	var clip_from := 0.0
	var clip_to := 1.0
	var alpha := lerpf(0.62, 0.88, stage)
	if front:
		clip_from = 0.76
		alpha *= 0.78
	_draw_overlay_body_texture(
		canvas,
		center + Vector2(0.0, IsoCoordinates.visual(4.0)),
		texture,
		_overlay_texture_content_size(texture, frame_source),
		lerpf(0.48, 0.68, stage),
		0.78,
		clip_from,
		clip_to,
		alpha,
		IsoCoordinates.visual(0.9) * lerpf(0.65, 1.0, stage),
		2.15,
		frame_source
	)


static func _fire_frame_source(texture: Texture2D, center: Vector2) -> Rect2:
	var frame_size := texture.get_size() * 0.5
	var frame := int(floor(_time_sec() * 7.0 + absf(_overlay_phase_seed(center)))) % 4
	return Rect2(Vector2(float(frame % 2), float(frame / 2)) * frame_size, frame_size)


static func _draw_poison_fog(
	canvas: Control,
	center: Vector2,
	cell: Vector2i,
	front: bool,
	stage: float = 1.0,
	occupied: bool = false,
	overall_alpha: float = 1.0
) -> void:
	_draw_poison_cloud_parts(
		canvas,
		center,
		cell,
		Constants.TILE_MOD_POISON_FOG,
		front,
		stage,
		occupied,
		overall_alpha
	)


static func _draw_toxic_smoke(
	canvas: Control,
	center: Vector2,
	cell: Vector2i,
	front: bool,
	stage: float = 1.0,
	occupied: bool = false,
	overall_alpha: float = 1.0
) -> void:
	_draw_poison_cloud_parts(
		canvas,
		center,
		cell,
		Constants.TILE_MOD_TOXIC_SMOKE,
		front,
		stage,
		occupied,
		overall_alpha
	)


static func _draw_poison_cloud_parts(
	canvas: Control,
	center: Vector2,
	cell: Vector2i,
	effect_type: String,
	front: bool,
	stage: float,
	occupied: bool,
	overall_alpha: float
) -> void:
	PoisonCloudRendererClass.draw(
		canvas,
		_cloud_parts_texture(effect_type),
		center,
		cell,
		effect_type,
		front,
		stage,
		occupied,
		_time_sec(),
		overall_alpha
	)


static func _cloud_parts_texture(effect_type: String) -> Texture2D:
	var key := (
		TOXIC_SMOKE_CLOUD_TEXTURE_KEY
		if effect_type == Constants.TILE_MOD_TOXIC_SMOKE
		else POISON_FOG_CLOUD_TEXTURE_KEY
	)
	var animated := _animated_overlay_textures.get(key) as Texture2D
	if animated != null:
		return animated
	return _load_overlay_texture(POISON_CLOUD_PARTS_PATH)


static func _draw_poison_puddle(canvas: Control, center: Vector2, stage: float = 1.0) -> void:
	_draw_poison_water_wash(canvas, center, stage)
	var texture := _load_overlay_texture(POISON_WATER_GLINTS_PATH)
	if texture != null:
		_draw_ground_overlay_texture(
			canvas,
			center + Vector2(0.0, IsoCoordinates.visual(3.0)),
			texture,
			_overlay_texture_content_size(texture),
			0.94,
			0.50,
			0.66 + stage * 0.20,
			IsoCoordinates.visual(0.55) * stage,
			0.42,
			Color(0.72, 1.0, 0.38)
		)
		_draw_poison_water_bubbles(canvas, center, stage)
		return
	var t := _time_sec()
	var seed := _overlay_phase_seed(center)
	var blobs := [
		{"offset": Vector2(-14, 6), "radius": 10.0},
		{"offset": Vector2(0, 10), "radius": 13.0},
		{"offset": Vector2(13, 6), "radius": 9.0},
	]
	for i in range(blobs.size()):
		var blob: Dictionary = blobs[i]
		var wobble := Vector2(sin(t * 0.8 + seed + float(i)) * 0.7, cos(t * 0.7 + seed + float(i) * 1.3) * 0.45)
		var offset: Vector2 = blob["offset"]
		canvas.draw_circle(
			center + offset + wobble,
			float(blob["radius"]),
			Color(0.34, 0.49, 0.42, 0.18 + stage * 0.1)
	)
	canvas.draw_circle(center + Vector2(-3.0, 7.0), 4.5, Color(0.52, 0.69, 0.60, 0.06 + stage * 0.06))
	_draw_poison_water_bubbles(canvas, center, stage)

static func _draw_poison_water_wash(canvas: Control, center: Vector2, stage: float) -> void:
	var corners := IsoCoordinates.diamond_corners(center)
	var t := _time_sec()
	var pulse := sin(t * 1.15 + _overlay_phase_seed(center)) * 0.5 + 0.5
	var alpha := lerpf(0.20, 0.34, stage) + pulse * 0.035
	canvas.draw_colored_polygon(corners, Color(0.26, 0.62, 0.22, alpha))
	var inner := PackedVector2Array()
	for p in corners:
		inner.append(center + (p - center) * 0.72)
	canvas.draw_colored_polygon(inner, Color(0.44, 0.86, 0.24, alpha * 0.55))


static func _draw_poison_water_bubbles(canvas: Control, center: Vector2, stage: float) -> void:
	var t := _time_sec()
	var seed := _overlay_phase_seed(center)
	var bubbles := [
		{"offset": Vector2(-17.0, 3.0), "radius": 2.2, "phase": 0.0},
		{"offset": Vector2(-3.0, 9.0), "radius": 2.8, "phase": 1.7},
		{"offset": Vector2(14.0, 1.0), "radius": 2.0, "phase": 3.1},
	]
	for bubble in bubbles:
		var phase := float(bubble["phase"])
		var rise := sin(t * 1.8 + seed + phase) * IsoCoordinates.visual(1.2)
		var radius := IsoCoordinates.visual(float(bubble["radius"]) * lerpf(0.75, 1.0, stage))
		var offset: Vector2 = bubble["offset"]
		var pos := center + offset + Vector2(0.0, rise)
		canvas.draw_circle(pos, radius, Color(0.76, 1.0, 0.48, 0.18 + stage * 0.12))
		canvas.draw_arc(pos, radius * 1.45, 0.0, TAU, 16, Color(0.88, 1.0, 0.58, 0.18 + stage * 0.10), IsoCoordinates.visual(0.9), true)


static func _draw_ground_overlay_texture(
	canvas: Control,
	center: Vector2,
	texture: Texture2D,
	content_size: Vector2,
	width_ratio: float,
	lift: float,
	alpha: float,
	drift_px: float,
	speed: float,
	tint: Color = Color.WHITE
) -> void:
	if texture == null:
		return
	var width := IsoCoordinates._tile_w() * width_ratio
	var height := width * content_size.y / maxf(content_size.x, 1.0)
	var t := _time_sec()
	var seed := _overlay_phase_seed(center)
	var wobble := Vector2(
		sin(t * speed + seed) * drift_px,
		cos(t * speed * 0.71 + seed) * drift_px * 0.35
	)
	var rect := Rect2(center.x - width * 0.5, center.y - height * lift, width, height)
	rect.position += wobble
	var shimmer := sin(t * speed * 2.0 + seed) * 0.035
	var draw_color := tint
	draw_color.a = clampf(alpha + shimmer, 0.0, 1.0)
	canvas.draw_texture_rect(texture, rect, false, draw_color)


static func _draw_overlay_body_texture(
	canvas: Control,
	center: Vector2,
	texture: Texture2D,
	content_size: Vector2,
	width_ratio: float,
	lift: float,
	clip_from: float,
	clip_to: float,
	alpha: float,
	drift_px: float,
	speed: float,
	source_rect: Rect2 = Rect2(),
	tint: Color = Color.WHITE
) -> void:
	if texture == null:
		return
	var width := IsoCoordinates._tile_w() * width_ratio
	var height := width * content_size.y / maxf(content_size.x, 1.0)
	var base_rect := Rect2(center.x - width * 0.5, center.y - height * lift, width, height)
	var source_origin := source_rect.position
	var tex_size := source_rect.size
	if tex_size == Vector2.ZERO:
		tex_size = texture.get_size()
	var y0 := clampf(clip_from, 0.0, 1.0)
	var y1 := clampf(clip_to, 0.0, 1.0)
	if y1 <= y0:
		return
	var seed := _overlay_phase_seed(center)
	var band_count := 7
	for i in range(band_count):
		var u0 := float(i) / float(band_count)
		var u1 := float(i + 1) / float(band_count)
		var src := Rect2(
			source_origin.x + tex_size.x * u0,
			source_origin.y + tex_size.y * y0,
			maxf(1.0, tex_size.x * (u1 - u0)),
			maxf(1.0, tex_size.y * (y1 - y0))
		)
		var dest := Rect2(
			base_rect.position.x + base_rect.size.x * u0,
			base_rect.position.y + base_rect.size.y * y0,
			maxf(1.0, base_rect.size.x * (u1 - u0)),
			maxf(1.0, base_rect.size.y * (y1 - y0))
		)
		var local_weight := 1.0 - ((dest.position.y + dest.size.y * 0.5) - base_rect.position.y) / maxf(base_rect.size.y, 1.0)
		local_weight = clampf(local_weight, 0.0, 1.0)
		var dx := sin(_time_sec() * speed + seed + float(i) * 0.61) * drift_px * local_weight
		var dy := cos(_time_sec() * speed * 0.63 + seed + float(i) * 0.37) * IsoCoordinates.visual(0.8) * local_weight
		dest.position += Vector2(dx, dy)
		var draw_color := tint
		draw_color.a = clampf(alpha * tint.a, 0.0, 1.0)
		canvas.draw_texture_rect_region(texture, dest, src, draw_color, false)
