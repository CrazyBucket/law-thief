class_name FrozenUnitVisuals
extends RefCounted

const FrozenUnitShader := preload("res://scenes/battle/frozen_unit.gdshader")

var _host: Node = null
var _entries: Dictionary = {}
var _next_index := 0


func configure(host: Node) -> void:
	_host = host


func sync_active_units(state: GameState) -> bool:
	var active_uids: Dictionary = {}
	if state != null:
		for unit: UnitState in state.units.values():
			if unit.alive and unit.has_status(Constants.STATUS_FROZEN):
				active_uids[unit.uid] = true
	for unit_uid in _entries.keys():
		if active_uids.has(unit_uid):
			continue
		var viewport: SubViewport = _entries[unit_uid]["viewport"]
		if is_instance_valid(viewport):
			viewport.queue_free()
		_entries.erase(unit_uid)
	return not active_uids.is_empty()


func draw_unit(
	canvas: CanvasItem,
	unit: UnitState,
	source: Texture2D,
	rect: Rect2,
	unit_tint: Color
) -> void:
	if not unit.has_status(Constants.STATUS_FROZEN):
		canvas.draw_texture_rect(source, rect, false, unit_tint)
		return
	canvas.draw_texture_rect(
		source,
		rect,
		false,
		unit_tint.lerp(Color(0.42, 0.82, 1.0, unit_tint.a), 0.62)
	)
	var frozen_texture := texture_for(unit.uid, source, unit_tint)
	if frozen_texture != null:
		canvas.draw_texture_rect(frozen_texture, rect, false, Color.WHITE)


func texture_for(unit_uid: String, source: Texture2D, unit_tint: Color) -> Texture2D:
	if _host == null or source == null:
		return null
	if not _entries.has(unit_uid):
		_entries[unit_uid] = _create_entry(unit_uid)
	var entry: Dictionary = _entries[unit_uid]
	var viewport := entry["viewport"] as SubViewport
	var sprite := entry["sprite"] as Sprite2D
	var material := entry["material"] as ShaderMaterial
	var source_size := Vector2i(maxi(1, source.get_width()), maxi(1, source.get_height()))
	if viewport.size != source_size:
		viewport.size = source_size
	sprite.texture = source
	material.set_shader_parameter("unit_tint", unit_tint)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport.get_texture()


func _create_entry(unit_uid: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "FrozenUnitShaderViewport%d" % _next_index
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.set_meta("frozen_unit_uid", unit_uid)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = FrozenUnitShader
	material.set_shader_parameter("phase", float(absi(unit_uid.hash()) % 1000) / 1000.0)
	sprite.material = material
	viewport.add_child(sprite)
	_host.add_child(viewport)
	_next_index += 1
	return {"viewport": viewport, "sprite": sprite, "material": material}
