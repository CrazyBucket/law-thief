class_name OldMageHudPanel
extends RefCounted

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

const POOL_IDS := [
	"gem_explosion", "gem_conductive", "gem_fire", "gem_ice",
	"gem_poison", "gem_light", "gem_impact",
]


static func phase_summary(state: GameState, unit: UnitState) -> String:
	if unit.hp < 20:
		var next_slot := int(state.battle_temp_flags.get("old_mage:%s:next_black_slot" % unit.uid, _next_black_slot(unit)))
		return "终末：本回合黑化槽位 #%d" % (next_slot + 1) if next_slot >= 0 else "终末：全部槽位已黑化"
	var phase := str(state.battle_temp_flags.get("old_mage:%s:phase" % unit.uid, "cast"))
	if phase == "refill":
		for index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[index]
			if slot.slot_type != Constants.SLOT_BLACK and slot.gem_uid.is_empty():
				return "补充：槽位 #%d，%s" % [index + 1, _slot_name(slot.slot_type)]
		return "补充：寻找池内宝石"
	return "施法：施法后宝石销毁"


static func create_pool_chip(looks: Node) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(UiPalette.TEXT_GOLD.darkened(0.18)))
	panel.tooltip_text = "技能池：抢走这些宝石可拖慢补充；非池宝石可塞入待补槽换取安全回合。"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = "技能池"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiPalette.TEXT_GOLD.lightened(0.2))
	row.add_child(label)
	for gem_id in POOL_IDS:
		if looks == null:
			continue
		var texture: Texture2D = looks.get_gem_texture(gem_id)
		if texture == null:
			continue
		var icon := TextureRect.new()
		icon.texture = texture
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = looks.gem_sprite_modulate(gem_id)
		row.add_child(icon)
	panel.add_child(row)
	return panel


static func _next_black_slot(unit: UnitState) -> int:
	for prefer_loaded in [true, false]:
		for index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[index]
			if slot.slot_type != Constants.SLOT_BLACK and (not prefer_loaded or not slot.gem_uid.is_empty()):
				return index
	return -1


static func _slot_name(slot_type: String) -> String:
	if slot_type == Constants.SLOT_RED:
		return "红槽"
	if slot_type == Constants.SLOT_BLUE:
		return "蓝槽"
	return "黑槽"
