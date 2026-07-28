class_name StatusUi
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const _StatusIcons = preload("res://scripts/ui/status_icons.gd")


static func build_status_row(unit: UnitState, compact: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 if compact else 6)
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		row.add_child(build_status_chip(status, compact))
	return row


static func populate_status_row(
	container: HBoxContainer,
	unit: UnitState,
	compact: bool = false,
	exclude_status_ids: Array[String] = [],
	rich_tooltip: Control = null
) -> void:
	while container.get_child_count() > 0:
		container.get_child(0).free()
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		if status.status_id in exclude_status_ids:
			continue
		container.add_child(build_status_chip(status, compact, rich_tooltip))


static func build_status_chip(status: StatusInstance, compact: bool = false, rich_tooltip: Control = null) -> Control:
	var chip := PanelContainer.new()
	var color := _StatusRegistry.status_color(status.status_id)
	chip.add_theme_stylebox_override("panel", _chip_style(color))
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	if rich_tooltip != null and rich_tooltip.has_method("attach"):
		chip.tooltip_text = ""
		rich_tooltip.call("attach", chip, build_status_tooltip_spec(status))
	else:
		chip.tooltip_text = _StatusRegistry.tooltip(status)
	var icon_tex := _StatusIcons.get_icon(status.status_id)
	if icon_tex != null:
		var icon_size: float = 16.0 if compact else 20.0
		var icon_wrap := Control.new()
		icon_wrap.custom_minimum_size = Vector2(icon_size, icon_size)
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_wrap.add_child(tex_rect)
		var badge_text: String = _StatusRegistry.icon_badge(status)
		if not badge_text.is_empty():
			var badge := Label.new()
			badge.text = badge_text
			badge.add_theme_font_override("font", BattleUiTheme.pixel_font())
			badge.add_theme_font_size_override("font_size", 8 if compact else 9)
			badge.add_theme_color_override("font_color", UiPalette.TEXT_BRIGHT)
			badge.add_theme_color_override("font_outline_color", UiPalette.TEXT_OUTLINE)
			badge.add_theme_constant_override("outline_size", 2)
			badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.offset_left = -14.0
			badge.offset_top = -11.0
			icon_wrap.add_child(badge)
		chip.add_child(icon_wrap)
		chip.custom_minimum_size = Vector2(icon_size + 6, icon_size + 4)
	else:
		var label := Label.new()
		label.text = _StatusRegistry.short_label(status)
		label.add_theme_font_override("font", BattleUiTheme.pixel_font())
		label.add_theme_font_size_override("font_size", 10 if compact else 11)
		label.add_theme_color_override("font_color", UiPalette.TEXT_BRIGHT)
		chip.add_child(label)
		chip.custom_minimum_size = Vector2(34 if compact else 40, 18 if compact else 22)
	return chip


static func build_status_tooltip_spec(status: StatusInstance) -> Dictionary:
	var color := _StatusRegistry.status_color(status.status_id)
	var stats: Array = []
	if status.stacks > 0:
		stats.append({"label": "层数", "value": str(status.stacks), "color": color.lightened(0.25)})
	if status.duration > 0:
		stats.append({"label": "持续", "value": "%d 回合" % status.duration})
	if status.value > 0:
		stats.append({"label": "数值", "value": str(status.value), "color": color.lightened(0.25)})
	return {
		"title": _StatusRegistry.display_name(status.status_id),
		"subtitle": _status_type_label(status.status_id),
		"icon": _StatusIcons.get_icon(status.status_id),
		"accent": color,
		"stats": stats,
		"sections": [
			{"title": "效果", "body": _StatusRegistry.tooltip(status)},
		],
		"terms": terms_for_status(status.status_id),
	}


static func terms_for_text(text: String) -> Array[Dictionary]:
	var terms: Array[Dictionary] = []
	var seen := {}
	var checks := {
		Constants.STATUS_BURNING: ["燃烧", "着火", "火焰"],
		Constants.STATUS_POISON: ["中毒", "毒雾", "毒烟"],
		Constants.STATUS_SLOWED: ["缓速"],
		Constants.STATUS_PARALYZED: ["麻痹"],
		Constants.STATUS_FROZEN: ["冻结"],
		Constants.STATUS_WET: ["潮湿", "水洼"],
		Constants.STATUS_ARMOR: ["护盾"],
		Constants.STATUS_ROOTED: ["束缚"],
		Constants.STATUS_LIGHT_EXPOSED: ["曝光"],
		Constants.STATUS_BLINDED: ["致盲"],
		Constants.STATUS_VULNERABLE: ["易伤"],
		Constants.STATUS_WEAK: ["虚弱"],
	}
	for status_id in checks.keys():
		for keyword in checks[status_id]:
			if text.find(str(keyword)) >= 0 and not seen.has(status_id):
				terms.append(glossary_term_for_status(status_id))
				seen[status_id] = true
	if text.find("真实伤害") >= 0:
		terms.append(glossary_term_for_key("true_damage"))
	return terms


static func terms_for_status(status_id: String) -> Array[Dictionary]:
	var terms: Array[Dictionary] = []
	terms.append(glossary_term_for_status(status_id))
	match status_id:
		Constants.STATUS_BURNING, Constants.STATUS_POISON:
			terms.append(glossary_term_for_key("true_damage"))
	return terms


static func glossary_term_for_status(status_id: String) -> Dictionary:
	var color := _StatusRegistry.status_color(status_id)
	var term := {
		"label": _status_term_label(status_id),
		"title": _status_term_label(status_id),
		"subtitle": _status_type_label(status_id),
		"icon": _StatusIcons.get_icon(status_id),
		"accent": color,
		"body": _status_glossary_body(status_id),
	}
	if status_id in [Constants.STATUS_POISON, Constants.STATUS_BURNING, Constants.STATUS_ARMOR]:
		term["terms"] = [glossary_term_for_key("true_damage")]
	return term


static func glossary_term_for_key(term_id: String) -> Dictionary:
	match term_id:
		"true_damage":
			return {
				"label": "真实伤害",
				"title": "真实伤害",
				"subtitle": "伤害类型",
				"accent": UiPalette.TEXT_GOLD,
				"body": "直接扣除生命，不会被护盾抵挡。",
			}
	return {
		"label": term_id,
		"title": term_id,
		"body": "",
	}


static func _status_type_label(status_id: String) -> String:
	match _StatusRegistry.status_type(status_id):
		_StatusRegistry.TYPE_BUFF:
			return "增益状态"
		_StatusRegistry.TYPE_SYSTEM:
			return "特殊状态"
	return "负面状态"


static func _status_term_label(status_id: String) -> String:
	match status_id:
		Constants.STATUS_BURNING:
			return "燃烧"
	return _StatusRegistry.display_name(status_id)


static func _status_glossary_body(status_id: String) -> String:
	match status_id:
		Constants.STATUS_POISON:
			return "回合结束时造成真实伤害，结算后层数减少。"
		Constants.STATUS_BURNING:
			return "回合结束时造成真实伤害；处在火焰或毒烟中时会加剧。"
		Constants.STATUS_PARALYZED:
			return "无法行动，持续时间按回合减少。"
		Constants.STATUS_FROZEN:
			return "跳过下次行动，受到的普通伤害提高；冻结会消耗潮湿。"
		Constants.STATUS_SLOWED:
			return "降低移动力，但不会低于 1 格。"
		Constants.STATUS_LIGHT_EXPOSED:
			return "被光束标记，可被黑槽光清算。"
		Constants.STATUS_BLINDED:
			return "攻击更容易落空。"
		Constants.STATUS_WET:
			return "与冰、电等元素互动时会产生额外效果。"
		Constants.STATUS_SLUGGISH:
			return "下一次行动顺序延后。"
		Constants.STATUS_ARMOR:
			return "先抵挡普通伤害；真实伤害会直接扣除生命。"
		Constants.STATUS_ROOTED:
			return "无法移动，但仍可行动。"
		Constants.STATUS_EXPOSED:
			return "重甲槽位被破开。"
		Constants.STATUS_LAWLESS:
			return "目标正在追回被盗宝石。"
		Constants.STATUS_OVERLOAD_AI_CONTROL:
			return "过载暂时接管角色，会自动执行可用的攻击、移动或宝石操作。"
		Constants.STATUS_BOMB_RAT_PLUNDER:
			return "黑槽为空，准备夺取宝石。"
		Constants.STATUS_VULNERABLE:
			return "受到的普通伤害提高。"
		Constants.STATUS_WEAK:
			return "普通攻击伤害降低到原先的 75%。"
	return _StatusRegistry.display_name(status_id)


static func format_status_bbcode(status: StatusInstance) -> String:
	var color: Color = _StatusRegistry.status_color(status.status_id)
	var hex := color.to_html(false)
	var type_label := "增益" if _StatusRegistry.status_type(status.status_id) == _StatusRegistry.TYPE_BUFF else "减益"
	if _StatusRegistry.status_type(status.status_id) == _StatusRegistry.TYPE_SYSTEM:
		type_label = "特殊"
	return "[color=#%s][%s] %s[/color] [color=#%s]%s[/color]" % [
		hex,
		type_label,
		_StatusRegistry.display_name(status.status_id),
		UiPalette.TEXT_MUTED.to_html(false),
		_StatusRegistry.tooltip(status),
	]


static func format_all_bbcode(unit: UnitState) -> String:
	if unit.statuses.is_empty():
		return "[color=#%s]无状态[/color]" % UiPalette.TEXT_FAINT.to_html(false)
	var lines: Array[String] = []
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		lines.append(format_status_bbcode(status))
	return "\n".join(lines)


static func preview_lines(unit: UnitState) -> Array[String]:
	var lines: Array[String] = []
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		lines.append("%s：%s" % [_StatusRegistry.display_name(status.status_id), _StatusRegistry.tooltip(status)])
	return lines


static func _chip_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.6)
	box.border_color = color.lightened(0.08)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box
