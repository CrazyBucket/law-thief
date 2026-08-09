extends RefCounted

## 战后奖励视图只在战斗结束时加载；宿主继续持有流程状态和选择回调。


func build_dropped_gem_overlay(host, dropped_gems: Array[Dictionary], relic_offer: Array[String], battle_result: String) -> Node:
	var overlay_layout := DataRegistry.get_battle_reward_ui_layout("reward_overlay")
	var frame: Dictionary = host._battle_reward_overlay().begin_shell(overlay_layout, int(overlay_layout.get("canvas_layer", 0)))
	var vbox: VBoxContainer = frame["vbox"]
	var title := Label.new()
	title.text = "选择一颗掉落宝石嵌入"
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", int(overlay_layout.get("card_separation", 0)))
	var cards: Array[Control] = []
	for drop in dropped_gems:
		var card: Control = host._build_dropped_gem_card(drop, battle_result, relic_offer, frame["canvas"])
		cards_row.add_child(card)
		cards.append(card)
	var scroll_metrics: Dictionary = host._battle_reward_overlay().scroll_metrics(host, cards_row, overlay_layout)
	vbox.add_child(host._battle_reward_overlay().wrap_cards_scroll(cards_row, overlay_layout, scroll_metrics))
	host._battle_reward_overlay().animate_cards_in(host, cards, {"hover": true})
	var skip_width := float(scroll_metrics.get("width", 0.0))
	var on_skip := func() -> void:
		host._on_dropped_gem_insert_skipped(battle_result, relic_offer, frame["canvas"])
	vbox.add_child(host._battle_reward_overlay().build_action_button(overlay_layout, "不嵌入", on_skip, skip_width))
	return frame["canvas"]


func build_dropped_gem_card(host, drop: Dictionary, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	var gem_uid := str(drop.get("gem_uid", ""))
	var gem_id := str(drop.get("gem_id", ""))
	var rarity: String = DataRegistry.get_gem_rarity(gem_id)
	var rarity_color: Color = host._hud_presenter.rarity_color(rarity)
	return host._battle_reward_card_factory().dropped_gem_card(
		drop,
		rarity_color,
		host._data_registry(),
		UnitLooks,
		func() -> void: host._on_dropped_gem_selected_for_insert(gem_uid, battle_result, relic_offer, canvas)
	)


func build_dropped_gem_slot_overlay(host, gem_uid: String, battle_result: String, relic_offer: Array[String]) -> Node:
	var overlay_layout := DataRegistry.get_battle_reward_ui_layout("reward_overlay")
	var frame: Dictionary = host._battle_reward_overlay().begin_shell(overlay_layout, int(overlay_layout.get("canvas_layer", 0)))
	var vbox: VBoxContainer = frame["vbox"]
	var canvas: Node = frame["canvas"]
	var gem: GemState = host._controller.state.gems.get(gem_uid, null)
	var title := Label.new()
	title.text = "嵌入 %s" % (DataRegistry.get_gem_display_name(gem) if gem != null else "掉落宝石")
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", int(overlay_layout.get("card_separation", 0)))
	var player: UnitState = host._controller.state.get_player()
	if player != null:
		for slot_index in range(player.slots.size()):
			slots_row.add_child(host._build_player_slot_embed_card(gem_uid, slot_index, battle_result, relic_offer, canvas))
	var scroll_metrics: Dictionary = host._battle_reward_overlay().scroll_metrics(host, slots_row, overlay_layout)
	vbox.add_child(host._battle_reward_overlay().wrap_cards_scroll(slots_row, overlay_layout, scroll_metrics))
	var back_width := float(scroll_metrics.get("width", 0.0))
	var on_back := func() -> void:
		if canvas != null and is_instance_valid(canvas):
			canvas.queue_free()
		if host._settlement_overlay != null and is_instance_valid(host._settlement_overlay):
			host._open_settlement_gem()
		else:
			host._show_dropped_gem_reward(host._dropped_gem_offer(), relic_offer, battle_result)
	vbox.add_child(host._battle_reward_overlay().build_action_button(overlay_layout, "返回", on_back, back_width))
	return canvas


func build_player_slot_embed_card(host, gem_uid: String, slot_index: int, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	return host._battle_reward_card_factory().slot_embed_card(
		host._controller.state,
		slot_index,
		host._data_registry(),
		UnitLooks,
		func() -> void: host._on_dropped_gem_slot_chosen(gem_uid, slot_index, battle_result, relic_offer, canvas)
	)


func build_gem_overlay(host, gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> Node:
	var overlay_layout := DataRegistry.get_battle_reward_ui_layout("reward_overlay")
	var frame: Dictionary = host._battle_reward_overlay().begin_shell(overlay_layout, int(overlay_layout.get("canvas_layer", 0)))
	var vbox: VBoxContainer = frame["vbox"]
	var title := Label.new()
	title.text = "选择宝石"
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", int(overlay_layout.get("card_separation", 0)))
	var cards: Array[Control] = []
	for gem_id in gem_offer:
		if gem_id.is_empty():
			continue
		var card: Control = host._build_gem_card(gem_id, battle_result, relic_offer, frame["canvas"])
		cards_row.add_child(card)
		cards.append(card)
	var scroll_metrics: Dictionary = host._battle_reward_overlay().scroll_metrics(host, cards_row, overlay_layout)
	vbox.add_child(host._battle_reward_overlay().wrap_cards_scroll(cards_row, overlay_layout, scroll_metrics))
	var skip_width := float(scroll_metrics.get("width", 0.0))
	var on_skip := func() -> void:
		host._on_gem_chosen("", battle_result, relic_offer, frame["canvas"])
	vbox.add_child(host._battle_reward_overlay().build_action_button(overlay_layout, "跳过", on_skip, skip_width))
	host._battle_reward_overlay().animate_cards_in(host, cards, {"hover": true})
	return frame["canvas"]


func build_gem_card(host, gem_id: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	var rarity: String = DataRegistry.get_gem_rarity(gem_id)
	var rarity_color: Color = host._hud_presenter.rarity_color(rarity)
	return host._battle_reward_card_factory().gem_card(
		gem_id,
		rarity_color,
		host._data_registry(),
		UnitLooks,
		func() -> void: host._on_gem_chosen(gem_id, battle_result, relic_offer, canvas)
	)


func build_relic_overlay(host, offer: Array[String], battle_result: String) -> Node:
	var overlay_layout := DataRegistry.get_battle_reward_ui_layout("reward_overlay")
	var frame: Dictionary = host._battle_reward_overlay().begin_shell(overlay_layout, int(overlay_layout.get("canvas_layer", 0)))
	var vbox: VBoxContainer = frame["vbox"]
	var is_no_relics := offer.size() == 1 and offer[0] == "relic_placeholder"
	var accent: Color = BattleUiTheme.TEXT_MUTED if is_no_relics else BattleUiTheme.TEXT_GOLD
	var title := Label.new()
	title.text = "无可选遗物" if is_no_relics else "选择遗物"
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", int(overlay_layout.get("card_separation", 0)))
	var cards: Array[Control] = []
	for relic_id in offer:
		var def: Dictionary = DataRegistry.get_relic_def(relic_id)
		var rarity: String = DataRegistry.get_relic_rarity(relic_id)
		var card: Control = host._build_relic_card(relic_id, def, rarity, battle_result)
		cards_row.add_child(card)
		cards.append(card)
	var scroll_metrics: Dictionary = host._battle_reward_overlay().scroll_metrics(host, cards_row, overlay_layout)
	vbox.add_child(host._battle_reward_overlay().wrap_cards_scroll(cards_row, overlay_layout, scroll_metrics))
	var skip_width := float(scroll_metrics.get("width", 0.0))
	var on_skip := func() -> void:
		host._on_relic_overlay_dismissed(battle_result)
	vbox.add_child(host._battle_reward_overlay().build_action_button(overlay_layout, "跳过", on_skip, skip_width))
	host._battle_reward_overlay().animate_cards_in(host, cards, {"hover": true})
	return frame["canvas"]


func build_relic_card(host, relic_id: String, def: Dictionary, rarity: String, battle_result: String) -> Control:
	var is_placeholder := bool(def.get("placeholder", false))
	var rarity_color: Color = BattleUiTheme.TEXT_MUTED if is_placeholder else host._hud_presenter.rarity_color(rarity)
	return host._battle_reward_card_factory().relic_card(
		relic_id,
		def,
		rarity,
		rarity_color,
		host._hud_presenter.relic_desc_text(def),
		host._data_registry(),
		UnitLooks,
		func() -> void: host._on_relic_chosen("" if is_placeholder else relic_id, battle_result)
	)
