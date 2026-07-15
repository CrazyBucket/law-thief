class_name BattleRewardOverlay
extends RefCounted

const _UiTheme = preload("res://scripts/ui/battle_ui_theme.gd")


## 奖励弹窗的结构、横向滚动和卡片入场效果在此统一，避免各类奖励流程复制布局细节。
## 业务层仍负责提供卡片内容并处理选择结果。
static func scroll_metrics(host: Control, cards_row: HBoxContainer, layout: Dictionary) -> Dictionary:
	var row := _cards_row_metrics(cards_row, layout)
	var content_w: float = row.get("content_width", 0.0)
	var content_h: float = row.get("content_height", 0.0)
	var viewport_cap := _viewport_cap(host, layout)
	var edge_pad := float(layout.get("scroll_edge_pad", 0))
	var padded_w := content_w + edge_pad * 2.0
	var needs_h_scroll := padded_w > viewport_cap + 0.5
	var scroll_w := viewport_cap if needs_h_scroll else padded_w
	var hover_pad := float(layout.get("scroll_hover_pad", 0))
	var bar_reserve := float(layout.get("scroll_bar_reserve", 0))
	var scroll_h := content_h + hover_pad + (bar_reserve if needs_h_scroll else 0.0)
	return {
		"size": Vector2(scroll_w, scroll_h),
		"width": scroll_w,
		"needs_horizontal_scroll": needs_h_scroll,
	}


static func wrap_cards_scroll(cards_row: HBoxContainer, layout: Dictionary, metrics: Dictionary) -> ScrollContainer:
	var edge_pad := int(layout.get("scroll_edge_pad", 0))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = metrics.get("size", Vector2.ZERO)
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if bool(metrics.get("needs_horizontal_scroll", false)) else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", edge_pad)
	margin.add_theme_constant_override("margin_right", edge_pad)
	margin.add_child(cards_row)
	scroll.add_child(margin)
	return scroll


static func build_action_button(layout: Dictionary, text: String, pressed_cb: Callable, scroll_width: float) -> Control:
	var action_wrap := CenterContainer.new()
	action_wrap.custom_minimum_size = Vector2(scroll_width, 0)
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(
		float(layout.get("action_button_width", 0)),
		float(layout.get("action_button_height", 0))
	)
	_UiTheme.apply_button(btn, "ghost")
	btn.pressed.connect(pressed_cb)
	action_wrap.add_child(btn)
	return action_wrap


static func begin_shell(layout: Dictionary, layer: int) -> Dictionary:
	var canvas := CanvasLayer.new()
	canvas.layer = layer

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.theme = _UiTheme.build_theme()
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(_UiTheme.BG_DEEP, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(layout.get("content_separation", 0)))
	center.add_child(vbox)

	return {
		"canvas": canvas,
		"root_ctrl": root_ctrl,
		"vbox": vbox,
	}


## 卡片/行入场在包裹节点内做位移，避开 HBox/VBox 对 position 的接管。
## 可选键：stagger、hover、from、tilt。
static func animate_cards_in(host: Node, cards: Array, config: Dictionary = {}) -> void:
	var stagger := float(config.get("stagger", 0.045))
	var hover := bool(config.get("hover", false))
	var from_offset: Vector2 = config.get("from", Vector2(54.0, 10.0))
	var tilt := float(config.get("tilt", 0.035))
	for i in range(cards.size()):
		var card := cards[i] as Control
		if card == null:
			continue
		var direction := 1.0 if i % 2 == 0 else -1.0
		var start := Vector2(from_offset.x * direction, from_offset.y)
		_deal_card_in(host, card, i, stagger, start, tilt * direction)
		if hover:
			card.mouse_entered.connect(func() -> void: _on_card_hover(host, card, true))
			card.mouse_exited.connect(func() -> void: _on_card_hover(host, card, false))


static func _cards_row_metrics(cards_row: HBoxContainer, layout: Dictionary) -> Dictionary:
	var separation := float(layout.get("card_separation", 0))
	var content_w := 0.0
	var content_h := 0.0
	var count := cards_row.get_child_count()
	for i in range(count):
		var ctrl := cards_row.get_child(i) as Control
		if ctrl == null:
			continue
		var card_size := ctrl.custom_minimum_size
		if card_size.x <= 0.0 or card_size.y <= 0.0:
			card_size = ctrl.get_combined_minimum_size()
		content_w += card_size.x
		content_h = maxf(content_h, card_size.y)
	if count > 1:
		content_w += separation * float(count - 1)
	return {
		"content_width": content_w,
		"content_height": content_h,
	}


static func _viewport_cap(host: Control, layout: Dictionary) -> float:
	var viewport_w := float(layout.get("fallback_viewport_width", 0))
	if host != null and host.is_inside_tree():
		viewport_w = host.get_viewport_rect().size.x
	var ratio := float(layout.get("scroll_viewport_ratio", 0))
	var max_w := float(layout.get("scroll_max_width", 0))
	return minf(viewport_w * ratio, max_w)


static func _deal_card_in(host: Node, card: Control, index: int, stagger: float, start_offset: Vector2, tilt: float) -> void:
	var parent := card.get_parent()
	if parent == null:
		return
	var slot_index := card.get_index()
	var wrapper := Control.new()
	wrapper.custom_minimum_size = card.custom_minimum_size
	wrapper.size_flags_horizontal = card.size_flags_horizontal
	wrapper.size_flags_vertical = card.size_flags_vertical
	parent.add_child(wrapper)
	parent.move_child(wrapper, slot_index)
	parent.remove_child(card)
	wrapper.add_child(card)
	var card_size := card.custom_minimum_size
	if card_size.x <= 0.0 or card_size.y <= 0.0:
		card_size = card.get_combined_minimum_size()
	card.size = card_size
	wrapper.custom_minimum_size = card_size
	card.pivot_offset = card_size * 0.5
	card.position = start_offset
	card.scale = Vector2(0.94, 0.94)
	card.rotation = tilt
	card.modulate.a = 0.0
	var delay := float(index) * stagger
	var move := host.create_tween().set_parallel(true)
	move.tween_property(card, "position", Vector2.ZERO, 0.22).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move.tween_property(card, "scale", Vector2.ONE, 0.2).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move.tween_property(card, "rotation", 0.0, 0.18).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move.tween_property(card, "modulate:a", 1.0, 0.12).set_delay(delay)


static func _on_card_hover(host: Node, card: Control, entered: bool) -> void:
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var target := Vector2(1.06, 1.06) if entered else Vector2.ONE
	var lift := -6.0 if entered else 0.0
	var tween := host.create_tween().set_parallel(true)
	tween.tween_property(card, "scale", target, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position:y", lift, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
