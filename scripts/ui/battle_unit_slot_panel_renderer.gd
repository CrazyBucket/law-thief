extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const BattleSlotPanelLayout = preload("res://scripts/ui/battle_slot_panel_layout.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const GemEchoVisuals = preload("res://scripts/ui/gem_echo_visuals.gd")

var action: String = ""
var check_fn: Callable = Callable()
var range_check_fn: Callable = Callable()
var hover_unit_uid: String = ""
var hover_index: int = -1


func configure(
	new_action: String,
	new_check_fn: Callable = Callable(),
	new_range_check_fn: Callable = Callable()
) -> void:
	action = new_action
	check_fn = new_check_fn
	range_check_fn = new_range_check_fn
	hover_unit_uid = ""
	hover_index = -1


func set_hover(screen_pos: Vector2, state: GameState, panel_anchor: Callable) -> bool:
	var hit := pick(screen_pos, state, panel_anchor)
	var uid := str(hit.get("unit_uid", ""))
	var index := int(hit.get("slot_index", -1))
	if uid == hover_unit_uid and index == hover_index:
		return false
	hover_unit_uid = uid
	hover_index = index
	return true


func pick(screen_pos: Vector2, state: GameState, panel_anchor: Callable) -> Dictionary:
	if state == null or action.is_empty():
		return {}
	for unit: UnitState in state.units.values():
		if not _unit_is_eligible(state, unit):
			continue
		var panel := _panel_layout(unit, panel_anchor)
		for item in panel.get("items", []):
			var item_dict: Dictionary = item
			if not bool(item_dict.get("visible", true)) or not bool(item_dict.get("enabled", false)):
				continue
			if BattleSlotPanelLayout.contains_point(screen_pos, item_dict):
				return {
					"unit_uid": unit.uid,
					"slot_index": int(item_dict.get("slot_index", -1)),
				}
	return {}


func draw(
	canvas: Control,
	state: GameState,
	panel_anchor: Callable,
	draw_soft_backdrop: Callable,
	draw_text_with_shadow: Callable,
	draw_small_diamond: Callable,
	display_gem_texture: Callable,
	draw_echo_smoke: Callable,
	gem_texture: Callable,
	gem_modulate: Callable,
	gem_color: Callable
) -> void:
	if state == null or action.is_empty():
		return
	for unit: UnitState in state.units.values():
		if not _unit_is_eligible(state, unit):
			continue
		var panel := _panel_layout(unit, panel_anchor)
		var items: Array = panel.get("items", [])
		if items.is_empty():
			continue
		var has_visible := false
		for item in items:
			if bool((item as Dictionary).get("visible", true)):
				has_visible = true
				break
		if not has_visible:
			continue
		var center: Vector2 = panel.get("center", Vector2.ZERO)
		var radius: float = float(panel.get("radius", IsoCoordinates.visual(34.0)))
		draw_soft_backdrop.call(center, radius * 0.96, radius * 0.62, Color(0.02, 0.03, 0.05, 0.32))
		for item in items:
			_draw_sector(
				canvas,
				state,
				item as Dictionary,
				draw_text_with_shadow,
				draw_small_diamond,
				display_gem_texture,
				draw_echo_smoke,
				gem_texture,
				gem_modulate,
				gem_color
			)


func _unit_is_eligible(state: GameState, unit: UnitState) -> bool:
	if unit == null or unit.slots.is_empty():
		return false
	if not unit.alive and (action != Constants.ACTION_EXTRACT or not state.is_player_split_corpse(unit)):
		return false
	return _unit_in_range(unit)


func _panel_layout(unit: UnitState, panel_anchor: Callable) -> Dictionary:
	return BattleSlotPanelLayout.build(
		unit,
		panel_anchor.call(unit) as Vector2,
		action,
		check_fn,
		IsoCoordinates.visual(18.0),
		IsoCoordinates.visual(52.0)
	)


func _unit_in_range(unit: UnitState) -> bool:
	if unit == null or action.is_empty() or not range_check_fn.is_valid():
		return false
	return bool(range_check_fn.call(unit.uid))


func _draw_sector(
	canvas: Control,
	state: GameState,
	item: Dictionary,
	draw_text_with_shadow: Callable,
	draw_small_diamond: Callable,
	display_gem_texture: Callable,
	draw_echo_smoke: Callable,
	gem_texture: Callable,
	gem_modulate: Callable,
	gem_color: Callable
) -> void:
	if not bool(item.get("visible", true)):
		return
	var center: Vector2 = item.get("center", Vector2.ZERO)
	var inner_radius: float = float(item.get("inner_radius", 0.0))
	var outer_radius: float = float(item.get("outer_radius", 0.0))
	var start_angle: float = float(item.get("start_angle", 0.0))
	var end_angle: float = float(item.get("end_angle", 0.0))
	var enabled := bool(item.get("enabled", false))
	var slot: SlotState = item.get("slot", null)
	var hovered: bool = enabled \
		and str(item.get("unit_uid", "")) == hover_unit_uid \
		and int(item.get("slot_index", -1)) == hover_index
	var base := _slot_color(slot.slot_type if slot != null else "")
	var fill := base
	fill.a = 0.78 if enabled else 0.22
	if hovered:
		fill = base.lightened(0.18)
		fill.a = 0.92
	var points := PackedVector2Array()
	var steps := 10
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * outer_radius)
	for index in range(steps, -1, -1):
		var t := float(index) / float(steps)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * inner_radius)
	canvas.draw_colored_polygon(points, fill)
	canvas.draw_polyline(points, Color(UiPalette.EDGE_DARK, 0.9 if enabled else 0.4), IsoCoordinates.visual(2.2), true)
	var line := Color(UiPalette.TEXT_BRIGHT, 0.95) if hovered else Color(UiPalette.TEXT_BRIGHT, 0.6 if enabled else 0.22)
	canvas.draw_polyline(points, line, IsoCoordinates.visual(1.1), true)
	if slot != null and not slot.dual_type.is_empty():
		var mid_angle := (start_angle + end_angle) * 0.5
		var dual_color := _slot_color(slot.dual_type)
		dual_color.a = 0.46 if enabled else 0.16
		var dual_center := center + Vector2(cos(mid_angle), sin(mid_angle)) * ((inner_radius + outer_radius) * 0.56)
		canvas.draw_circle(dual_center, (outer_radius - inner_radius) * 0.42, dual_color)
	_draw_sector_content(
		canvas,
		state,
		item,
		draw_small_diamond,
		display_gem_texture,
		draw_echo_smoke,
		gem_texture,
		gem_modulate,
		gem_color
	)
	var label := _slot_label(slot)
	if not label.is_empty():
		var font := BattleUiTheme.pixel_font()
		var font_size := int(IsoCoordinates.visual(8.0))
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var mid := (start_angle + end_angle) * 0.5
		var text_pos := center + Vector2(cos(mid), sin(mid)) * (inner_radius + (outer_radius - inner_radius) * 0.28)
		var text_color := Color(UiPalette.TEXT_BRIGHT, 0.95 if enabled else 0.42)
		draw_text_with_shadow.call(
			font,
			text_pos + Vector2(-label_size.x * 0.5, label_size.y * 0.35),
			label,
			font_size,
			text_color,
			UiPalette.TEXT_OUTLINE
		)


func _draw_sector_content(
	canvas: Control,
	state: GameState,
	item: Dictionary,
	draw_small_diamond: Callable,
	display_gem_texture: Callable,
	draw_echo_smoke: Callable,
	gem_texture: Callable,
	gem_modulate: Callable,
	gem_color: Callable
) -> void:
	var slot: SlotState = item.get("slot", null)
	if slot == null or state == null:
		return
	var center: Vector2 = item.get("center", Vector2.ZERO)
	var inner_radius: float = float(item.get("inner_radius", 0.0))
	var outer_radius: float = float(item.get("outer_radius", 0.0))
	var mid := (float(item.get("start_angle", 0.0)) + float(item.get("end_angle", 0.0))) * 0.5
	var enabled := bool(item.get("enabled", false))
	var content_pos := center + Vector2(cos(mid), sin(mid)) * (inner_radius + (outer_radius - inner_radius) * 0.68)
	var alpha := 1.0 if enabled else 0.45
	if not slot.gem_uid.is_empty():
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			return
		var texture: Texture2D = gem_texture.call(gem) as Texture2D
		var icon_size := (outer_radius - inner_radius) * 0.52
		if texture != null:
			texture = display_gem_texture.call(gem, texture) as Texture2D
			var tint: Color = gem_modulate.call(gem)
			tint.a *= alpha
			canvas.draw_texture_rect(
				texture,
				Rect2(content_pos - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size),
				false,
				tint
			)
		else:
			var fallback_color := GemEchoVisuals.fallback_color(state, gem.uid, gem_color.call(gem), alpha)
			draw_small_diamond.call(content_pos, icon_size * 0.4, icon_size * 0.3, fallback_color)
		draw_echo_smoke.call(gem.uid, content_pos, icon_size, alpha * 0.95)
		return
	var hole := (outer_radius - inner_radius) * 0.16
	canvas.draw_arc(content_pos, hole, 0.0, TAU, 12, Color(UiPalette.TEXT_BRIGHT, 0.55 * alpha), IsoCoordinates.visual(1.0))


func _slot_color(slot_type: String) -> Color:
	match slot_type:
		Constants.SLOT_RED:
			return UiPalette.SLOT_RED
		Constants.SLOT_BLUE:
			return UiPalette.SLOT_BLUE
		Constants.SLOT_BLACK:
			return UiPalette.SLOT_BLACK_DEEP
	return UiPalette.INTENT_IDLE


func _slot_label(slot: SlotState) -> String:
	if slot == null:
		return ""
	var label := "?"
	match slot.slot_type:
		Constants.SLOT_RED:
			label = "红"
		Constants.SLOT_BLUE:
			label = "蓝"
		Constants.SLOT_BLACK:
			label = "黑"
	if slot.locked:
		label += "·锁"
	return label
