class_name ShallowWaterOverlayRenderer
extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TEXTURE_PATH := "res://assets/overlays/effects/overlay_shallow_water_ripples.png"
static var _texture: Texture2D = null


static func draw_if_present(
	canvas: Control,
	center: Vector2,
	tile: TileState,
	stage: float = 1.0
) -> void:
	if not tile.has_modifier(Constants.TILE_MOD_SHALLOW_WATER):
		return
	if _texture == null:
		_texture = load(TEXTURE_PATH) as Texture2D
		if _texture == null:
			var image := Image.load_from_file(TEXTURE_PATH)
			if image != null and not image.is_empty():
				_texture = ImageTexture.create_from_image(image)
	if _texture == null:
		return
	var width := IsoCoordinates._tile_w() * 0.98
	var source_size := _texture.get_size()
	var height := width * source_size.y / maxf(source_size.x, 1.0)
	var time := float(Time.get_ticks_msec()) / 1000.0
	var seed := center.x * 0.017 + center.y * 0.031
	var wobble := Vector2(
		sin(time * 0.34 + seed) * IsoCoordinates.visual(0.35) * stage,
		cos(time * 0.24 + seed) * IsoCoordinates.visual(0.12) * stage
	)
	var rect := Rect2(center.x - width * 0.5, center.y - height * 0.5, width, height)
	rect.position += wobble + Vector2(0.0, IsoCoordinates.visual(2.0))
	var tint := Color(0.62, 0.90, 1.0, 0.42 + stage * 0.18)
	tint.a += sin(time * 0.68 + seed) * 0.035
	canvas.draw_texture_rect(_texture, rect, false, tint)
