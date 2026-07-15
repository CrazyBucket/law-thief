class_name BattleRewardCardFactory
extends RefCounted

const _UiTheme = preload("res://scripts/ui/battle_ui_theme.gd")


## 奖励卡片只负责把内容数据渲染为控件；领取、跳过和结算状态转换必须由调用方通过回调处理。
static func dropped_gem_card(drop: Dictionary, rarity_color: Color, catalog: Node, looks: Node, selected: Callable) -> Control:
	var card_layout: Dictionary = catalog.get_battle_reward_card_layout("dropped_gem")
	var gem_uid := str(drop.get("gem_uid", ""))
	var gem_id := str(drop.get("gem_id", ""))
	var panel := _card_panel(card_layout, rarity_color)
	var content := _card_content(panel)

	var gem := GemState.new()
	gem.gem_id = gem_id
	gem.uid = gem_uid
	if drop.get("def_overrides", {}) is Dictionary:
		gem.def_overrides = (drop.get("def_overrides", {}) as Dictionary).duplicate(true)
	_add_gem_icon(content, gem, card_layout, looks)
	_add_card_name(content, catalog.get_gem_display_name(gem), rarity_color, 15)

	var pos: Vector2i = drop.get("pos", Vector2i.ZERO)
	var pos_label := Label.new()
	pos_label.text = "掉落于 (%d, %d)" % [pos.x, pos.y]
	pos_label.add_theme_font_size_override("font_size", 11)
	pos_label.add_theme_color_override("font_color", _UiTheme.TEXT_MUTED)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(pos_label)
	_add_pick_button(content, "选择", card_layout, "end", selected)
	return panel


static func slot_embed_card(state: GameState, slot_index: int, catalog: Node, looks: Node, inserted: Callable) -> Control:
	var card_layout: Dictionary = catalog.get_battle_reward_card_layout("slot_embed")
	var player := state.get_player() if state != null else null
	var slot: SlotState = player.get_slot_by_index(slot_index) if player != null else null
	var slot_type := slot.slot_type if slot != null else ""
	var color: Color = looks.slot_color(slot_type)
	var panel := _card_panel(card_layout, color)
	var content := _card_content(panel)

	var title := Label.new()
	title.text = "#%d %s" % [slot_index + 1, slot_display_name(slot_type)]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", color.lightened(0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var current := Label.new()
	current.add_theme_font_size_override("font_size", 11)
	current.add_theme_color_override("font_color", _UiTheme.TEXT_MUTED)
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if slot == null:
		current.text = "无效槽位"
	elif slot.gem_uid.is_empty():
		current.text = "空槽"
	else:
		var current_gem: GemState = state.gems.get(slot.gem_uid, null)
		current.text = "已有 %s" % (catalog.get_gem_display_name(current_gem) if current_gem != null else "宝石")
	content.add_child(current)

	var button := _add_pick_button(content, "嵌入", card_layout, "end", inserted)
	button.disabled = slot == null
	_UiTheme.apply_button(button, "end")
	return panel


static func gem_card(gem_id: String, rarity_color: Color, catalog: Node, looks: Node, selected: Callable) -> Control:
	var card_layout: Dictionary = catalog.get_battle_reward_card_layout("gem")
	var panel := _card_panel(card_layout, rarity_color)
	var content := _card_content(panel)

	var gem := GemState.new()
	gem.gem_id = gem_id
	gem.uid = "_preview_%s" % gem_id
	_add_gem_icon(content, gem, card_layout, looks)
	_add_card_name(content, catalog.get_gem_display_name(gem), rarity_color, 15)

	var tag := str(catalog.get_gem_tag(gem_id))
	var tag_key := "gem.%s.symbol" % tag
	var tag_symbol: String = TranslationServer.translate(tag_key)
	if tag_symbol == tag_key:
		tag_symbol = tag
	var meta := Label.new()
	meta.text = "[%s] %s  T%d" % [rarity_display_name(catalog.get_gem_rarity(gem_id)), tag_symbol, catalog.get_gem_pool_tier(gem_id)]
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", rarity_color.darkened(0.15))
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(meta)
	_add_pick_button(content, "选择", card_layout, "end", selected)
	return panel


static func relic_card(
	relic_id: String,
	def: Dictionary,
	rarity: String,
	rarity_color: Color,
	description: String,
	catalog: Node,
	looks: Node,
	selected: Callable
) -> Control:
	var card_layout: Dictionary = catalog.get_battle_reward_card_layout("relic")
	var is_placeholder := bool(def.get("placeholder", false))
	var panel := _card_panel(card_layout, rarity_color)
	var content := _card_content(panel)

	var icon_tex: Texture2D = looks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var icon_size := float(card_layout.get("icon_size", 0))
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(icon)
	_add_card_name(content, str(def.get("name", relic_id)), rarity_color, 16)

	var rarity_label := Label.new()
	rarity_label.text = "[%s]" % rarity_display_name(rarity)
	rarity_label.add_theme_font_size_override("font_size", 11)
	rarity_label.add_theme_color_override("font_color", rarity_color.darkened(0.15))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(rarity_label)

	var description_label := RichTextLabel.new()
	description_label.bbcode_enabled = false
	description_label.text = description
	description_label.add_theme_font_size_override("normal_font_size", 12)
	description_label.add_theme_color_override("default_color", _UiTheme.TEXT_HINT)
	description_label.custom_minimum_size = Vector2(
		float(card_layout.get("desc_width", 0)),
		float(card_layout.get("desc_height", 0))
	)
	description_label.scroll_active = false
	content.add_child(description_label)
	_add_pick_button(content, "收下" if is_placeholder else "选择", card_layout, "ghost" if is_placeholder else "end", selected)
	return panel


static func slot_display_name(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED:
			return "红槽"
		Constants.SLOT_BLUE:
			return "蓝槽"
		Constants.SLOT_BLACK:
			return "黑槽"
	return slot_type


static func rarity_display_name(rarity: String) -> String:
	match rarity:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		"boss": return "首领"
		_: return rarity


static func _card_panel(card_layout: Dictionary, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _UiTheme.panel_style(accent))
	panel.custom_minimum_size = Vector2(
		float(card_layout.get("width", 0)),
		float(card_layout.get("height", 0))
	)
	return panel


static func _card_content(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	return content


static func _add_gem_icon(content: VBoxContainer, gem: GemState, card_layout: Dictionary, looks: Node) -> void:
	var icon_tex: Texture2D = looks.get_gem_texture(gem)
	if icon_tex == null:
		return
	var icon := TextureRect.new()
	icon.texture = icon_tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.self_modulate = looks.gem_sprite_modulate(gem)
	var icon_size := float(card_layout.get("icon_size", 0))
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)


static func _add_card_name(content: VBoxContainer, text: String, color: Color, font_size: int) -> void:
	var name_label := Label.new()
	name_label.text = text
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(name_label)


static func _add_pick_button(content: VBoxContainer, text: String, card_layout: Dictionary, kind: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, float(card_layout.get("pick_button_height", 0)))
	_UiTheme.apply_button(button, kind)
	button.pressed.connect(pressed)
	content.add_child(button)
	return button
