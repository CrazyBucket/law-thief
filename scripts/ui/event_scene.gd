extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")
const RunGemEmbedDialog = preload("res://scripts/ui/run_gem_embed_dialog.gd")
const MISACCOUNTING_SCRIBE_ARTWORK: Texture2D = preload("res://assets/ui/events/event_misaccounting_scribe.png")
const SEALED_GEM_FURNACE_ARTWORK: Texture2D = preload("res://assets/ui/events/event_sealed_gem_furnace.png")
const INJURY_APPRAISAL_ARTWORK: Texture2D = preload("res://assets/ui/events/event_injury_appraisal.png")
const COUNTERFEIT_AUCTION_ARTWORK: Texture2D = preload("res://assets/ui/events/event_counterfeit_auction.png")

const EVENT_PANEL := Color("#181925")
const EVENT_INSET := Color("#0b0c13")
const EVENT_ACCENT := Color("#a585e8")
const EVENT_EDGE := Color("#655681")

@onready var _top_bar: PanelContainer = $SafeArea/Layout/TopBar
@onready var _header_title: Label = $SafeArea/Layout/TopBar/Row/HeaderTitle
@onready var _chapter_label: Label = $SafeArea/Layout/TopBar/Row/ChapterLabel
@onready var _art_frame: PanelContainer = $SafeArea/Layout/Main/ArtFrame
@onready var _artwork: TextureRect = $SafeArea/Layout/Main/ArtFrame/ArtStack/EventArtwork
@onready var _art_fallback: CenterContainer = $SafeArea/Layout/Main/ArtFrame/ArtStack/ArtFallback
@onready var _art_glyph: Label = $SafeArea/Layout/Main/ArtFrame/ArtStack/ArtFallback/Glyph
@onready var _story_panel: PanelContainer = $SafeArea/Layout/Main/StoryColumn/StoryPanel
@onready var _eyebrow: Label = $SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/Eyebrow
@onready var _event_title: Label = $SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/EventTitle
@onready var _event_body: RichTextLabel = $SafeArea/Layout/Main/StoryColumn/StoryPanel/StoryMargin/StoryVBox/EventBody
@onready var _choice_panel: PanelContainer = $SafeArea/Layout/Main/StoryColumn/ChoicePanel
@onready var _choice_heading: Label = $SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/ChoiceHeading
@onready var _option_list: VBoxContainer = $SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/OptionList
@onready var _feedback_label: Label = $SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/FeedbackLabel
@onready var _continue_button: Button = $SafeArea/Layout/Main/StoryColumn/ChoicePanel/ChoiceMargin/ChoiceVBox/ContinueButton

var _room_id := ""
var _choice_locked := false
var _node_tween: Tween = null
var _gem_embed_overlay: RunGemEmbedDialog = null
var _pending_embed_response: Dictionary = {}
var _event_reward_placement_active := false


func _ready() -> void:
	theme = BattleUiTheme.build_theme()
	_apply_theme()
	_apply_copy()
	_room_id = AdventureService.current_room_id()
	_refresh_room_view(RoomFlowService.enter_room(_room_id))


func _apply_theme() -> void:
	_top_bar.add_theme_stylebox_override("panel", _panel_style(EVENT_PANEL, EVENT_ACCENT, 12, 1))
	_art_frame.add_theme_stylebox_override("panel", _art_style())
	_story_panel.add_theme_stylebox_override("panel", _panel_style(EVENT_PANEL, EVENT_EDGE, 0, 2))
	_choice_panel.add_theme_stylebox_override("panel", _panel_style(EVENT_PANEL.darkened(0.03), EVENT_ACCENT.darkened(0.2), 0, 2))
	var body_style := _panel_style(EVENT_INSET.lightened(0.025), EVENT_EDGE.darkened(0.28), 18, 1)
	body_style.shadow_size = 0
	_event_body.add_theme_stylebox_override("normal", body_style)
	_event_body.add_theme_constant_override("line_separation", 8)
	_header_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_chapter_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_eyebrow.add_theme_color_override("font_color", EVENT_ACCENT.lightened(0.15))
	_event_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_event_body.add_theme_color_override("default_color", BattleUiTheme.TEXT)
	_choice_heading.add_theme_color_override("font_color", EVENT_ACCENT.lightened(0.18))
	_feedback_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_art_glyph.add_theme_color_override("font_color", Color(EVENT_ACCENT, 0.34))
	_artwork.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_apply_choice_button(_continue_button)


func _apply_copy() -> void:
	_header_title.text = _t("event.ui.header")
	_eyebrow.text = _t("event.ui.story")
	_choice_heading.text = _t("event.ui.choices")
	_continue_button.text = _t("event.ui.continue")
	_chapter_label.text = _t("event.ui.chapter", {
		"current": AdventureService.get_current_chapter(),
		"total": AdventureService.get_chapter_count(),
	})


func _refresh_room_view(room_view: Dictionary) -> void:
	_choice_locked = false
	_feedback_label.text = ""
	var payload: Dictionary = room_view.get("payload", {})
	var event_view: Dictionary = payload.get("event", {})
	if event_view.is_empty() or not bool(event_view.get("ok", false)):
		_render_error()
		return
	var resolved := str(room_view.get("state", "")) == "RESOLVED" or bool(event_view.get("resolved", false))
	_render_event_view(event_view, resolved)


func _render_event_view(event_view: Dictionary, resolved: bool) -> void:
	_event_title.text = str(event_view.get("title", _t("event.ui.error.title")))
	_event_body.text = str(event_view.get("body", ""))
	_artwork.texture = _artwork_for_event(str(event_view.get("event_id", "")))
	_clear_options()
	if not resolved and _show_event_reward_placement(event_view):
		_choice_panel.visible = false
		return
	_choice_panel.visible = true
	_choice_heading.text = _t("event.ui.resolved") if resolved else _t("event.ui.choices")
	_continue_button.visible = resolved
	if not resolved:
		for raw_option in event_view.get("options", []):
			if raw_option is Dictionary:
				_add_option_button(raw_option as Dictionary)
	_art_fallback.visible = _artwork.texture == null
	_play_node_transition()


func _artwork_for_event(event_id: String) -> Texture2D:
	match event_id:
		"event_misaccounting_scribe":
			return MISACCOUNTING_SCRIBE_ARTWORK
		"event_sealed_gem_furnace":
			return SEALED_GEM_FURNACE_ARTWORK
		"event_injury_appraisal":
			return INJURY_APPRAISAL_ARTWORK
		"event_counterfeit_auction":
			return COUNTERFEIT_AUCTION_ARTWORK
		_:
			return null


func _add_option_button(option: Dictionary) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 68)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var copy := _option_copy(option)
	var enabled := bool(option.get("enabled", true))
	var disabled_reason := _disabled_reason(option)
	button.text = ""
	button.disabled = not enabled
	button.set_meta("event_condition_disabled", not enabled)
	if button.disabled and not disabled_reason.is_empty():
		button.tooltip_text = disabled_reason
	_add_option_content(
		button,
		str(copy.get("choice", _t("event.ui.choices"))),
		str(copy.get("effect", "")),
		disabled_reason,
		enabled
	)
	_apply_choice_button(button)
	if not button.disabled:
		button.pressed.connect(_on_option_pressed.bind(str(option.get("id", ""))))
	_option_list.add_child(button)


func _add_option_content(button: Button, choice: String, effect_text: String, disabled_reason: String, enabled: bool) -> void:
	var content := Control.new()
	content.name = "OptionContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.name = "ChoiceTitle"
	title.set_meta("event_choice_title", true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = choice if enabled or disabled_reason.is_empty() else "%s  ·  %s" % [choice, disabled_reason]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 18.0
	title.offset_top = 10.0
	title.offset_right = -18.0
	title.offset_bottom = 28.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BattleUiTheme.pixel_font())
	title.add_theme_font_size_override("font_size", 14)
	var effect := Label.new()
	effect.name = "EffectText"
	effect.set_meta("event_effect_label", true)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.text = effect_text
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	effect.offset_left = 18.0
	effect.offset_top = -28.0
	effect.offset_right = -18.0
	effect.offset_bottom = -10.0
	effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect.add_theme_font_override("font", BattleUiTheme.pixel_font())
	effect.add_theme_font_size_override("font_size", 11)
	content.add_child(title)
	content.add_child(effect)
	button.add_child(content)


func _option_copy(option: Dictionary) -> Dictionary:
	var label := str(option.get("label", _t("event.ui.choices"))).strip_edges()
	var choice := str(option.get("choice_label", "")).strip_edges()
	var effect := str(option.get("effect_text", "")).strip_edges()
	if choice.is_empty():
		var colon_index := label.find("：")
		if colon_index < 0:
			colon_index = label.find(":")
		if colon_index >= 0:
			choice = label.substr(0, colon_index).strip_edges()
			effect = label.substr(colon_index + 1).strip_edges() if effect.is_empty() else effect
	if choice.is_empty():
		choice = _default_choice_label(str(option.get("id", "")), label)
	if effect.is_empty():
		effect = _default_effect_text(str(option.get("id", "")), label)
	return {"choice": choice, "effect": effect}


func _default_choice_label(option_id: String, fallback: String) -> String:
	if option_id.begins_with("toggle:"):
		return fallback
	if option_id.begins_with("reward:"):
		return fallback
	if option_id.begins_with("sacrifice:"):
		return fallback
	if option_id.begins_with("place:"):
		return fallback
	match option_id:
		"small": return _t("event.option.choice.small")
		"large": return _t("event.option.choice.large")
		"take": return _t("event.option.choice.take")
		"turn": return _t("event.option.choice.turn")
		"sell_blood": return _t("event.option.choice.sell_blood")
		"treatment": return _t("event.option.choice.treatment")
		"relief": return _t("event.option.choice.relief")
		"buy_safe": return _t("event.option.choice.buy_safe")
		"buy_risky": return _t("event.option.choice.buy_risky")
		"sign": return _t("event.option.choice.sign")
		"tear": return _t("event.option.choice.tear")
		"stable": return _t("event.option.choice.stable")
		"overpressure": return _t("event.option.choice.overpressure")
		"common": return _t("event.option.choice.common")
		"rare": return _t("event.option.choice.rare")
		"first": return _t("event.option.choice.first")
		"second": return _t("event.option.choice.second")
		"open_gray": return _t("event.option.choice.open_gray")
		"open_blue": return _t("event.option.choice.open_blue")
		"open_black": return _t("event.option.choice.open_black")
		"hold": return _t("event.option.choice.hold")
		"abandon": return _t("event.option.choice.abandon")
		"leave", "stop", "cancel": return fallback
	return fallback


func _default_effect_text(option_id: String, fallback: String) -> String:
	if option_id in ["leave", "stop", "cancel", "tear"]:
		return _t("event.option.effect.no_change")
	if option_id == "hold":
		return _t("event.option.effect.hold")
	if option_id == "abandon":
		return _t("event.option.effect.abandon")
	if option_id.begins_with("toggle:"):
		if fallback.begins_with("取消选择"):
			return _t("event.option.effect.toggle_remove")
		return _t("event.option.effect.toggle")
	if option_id == "confirm":
		return _t("event.option.effect.confirm")
	if option_id.begins_with("sacrifice:"):
		return _t("event.option.effect.sacrifice")
	if option_id.begins_with("reward:"):
		return _t("event.option.effect.reward")
	if option_id.begins_with("place:"):
		return _t("event.option.effect.place")
	return fallback


func _disabled_reason(option: Dictionary) -> String:
	match str(option.get("disabled_reason_code", "")):
		"resource_gte_failed":
			return _t("event.ui.condition.gold")
		"carried_gem_empty_failed":
			return _t("event.ui.condition.hand_full")
		"":
			return str(option.get("disabled_reason", ""))
		_:
			var reason := str(option.get("disabled_reason", "")).strip_edges()
			return reason if not reason.is_empty() else _t("event.ui.condition.unavailable")


func _on_option_pressed(option_id: String) -> void:
	if _choice_locked or option_id.is_empty():
		return
	_choice_locked = true
	_set_options_disabled(true)
	var carried_gem_before := _carried_gem_id()
	var response := RoomFlowService.submit_room_command(_room_id, {
		"action": "choose_option",
		"option_id": option_id,
	})
	if not bool(response.get("ok", false)):
		_choice_locked = false
		_feedback_label.text = _t("event.ui.error.action")
		_set_options_disabled(false)
		return
	var acquired_gem_now := carried_gem_before.is_empty() and not _carried_gem_id().is_empty()
	if acquired_gem_now and _show_gem_embed_choice(response):
		return
	_finish_option_response(response)


func _finish_option_response(response: Dictionary) -> void:
	if str(response.get("state", "")) == "RESOLVED":
		# A finishing choice already represents leaving the event; do not require
		# a second "continue" action from the resolved screen.
		AdventureService.finish_room_and_return()
		return
	_refresh_room_view(response)


func _carried_gem_id() -> String:
	var run := RunService.get_run()
	if run == null:
		return ""
	return str(run.carried_gem.get("gem_id", ""))


func _show_gem_embed_choice(response: Dictionary) -> bool:
	var run := RunService.get_run()
	if run == null or run.carried_gem.is_empty():
		return false
	var options := RunPlayerGemService.embed_options(run)
	if options.is_empty():
		return false
	_event_reward_placement_active = false
	_pending_embed_response = response.duplicate(true)
	_present_gem_embed_dialog(options)
	return true


func _show_event_reward_placement(event_view: Dictionary) -> bool:
	var raw_placement: Variant = event_view.get("gem_placement", {})
	if not raw_placement is Dictionary:
		return false
	var placement := raw_placement as Dictionary
	var gem_id := str(placement.get("gem_id", ""))
	var run := RunService.get_run()
	if gem_id.is_empty() or run == null:
		return false
	_event_reward_placement_active = true
	_pending_embed_response = {}
	_present_gem_embed_dialog(
		RunPlayerGemService.reward_embed_options(run, gem_id),
		_t("gem_embed.reward_title", {"gem": DataRegistry.get_gem_display_name(gem_id)}),
		bool(placement.get("allow_hold", false)),
		true
	)
	return true


func _present_gem_embed_dialog(options: Array[Dictionary], title_text: String = "", allow_hold: bool = true, allow_abandon: bool = false) -> void:
	if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
		_gem_embed_overlay.configure(options, title_text, allow_hold, allow_abandon)
		return
	_gem_embed_overlay = RunGemEmbedDialog.new()
	_gem_embed_overlay.embed_requested.connect(_on_gem_embed_slot_pressed)
	_gem_embed_overlay.postponed.connect(_on_gem_embed_later_pressed)
	_gem_embed_overlay.abandoned.connect(_on_gem_embed_abandoned)
	add_child(_gem_embed_overlay)
	_gem_embed_overlay.configure(options, title_text, allow_hold, allow_abandon)


func _on_gem_embed_slot_pressed(slot_index: int, force_overload: bool = false) -> void:
	if _event_reward_placement_active:
		_submit_event_reward_placement("place:%d:%d" % [slot_index, 1 if force_overload else 0])
		return
	var result := RunPlayerGemService.embed_carried_gem(RunService.get_run(), slot_index, force_overload)
	if not bool(result.get("ok", false)):
		_feedback_label.text = _t("gem_embed.unavailable")
		if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
			_gem_embed_overlay.unlock_after_failure()
		return
	RunService.save_run(false)
	var response := _pending_embed_response
	_close_gem_embed_overlay()
	_finish_option_response(response)


func _on_gem_embed_later_pressed() -> void:
	if _event_reward_placement_active:
		_submit_event_reward_placement("hold")
		return
	var response := _pending_embed_response
	_close_gem_embed_overlay()
	_finish_option_response(response)


func _on_gem_embed_abandoned() -> void:
	if _event_reward_placement_active:
		_submit_event_reward_placement("abandon")


func _submit_event_reward_placement(option_id: String) -> void:
	var response := RoomFlowService.submit_room_command(_room_id, {
		"action": "choose_option",
		"option_id": option_id,
	})
	if not bool(response.get("ok", false)):
		_feedback_label.text = _t("event.ui.error.action")
		if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
			_gem_embed_overlay.unlock_after_failure()
		return
	_close_gem_embed_overlay()
	_finish_option_response(response)


func _close_gem_embed_overlay() -> void:
	if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
		_gem_embed_overlay.dismiss()
	_gem_embed_overlay = null
	_pending_embed_response = {}
	_event_reward_placement_active = false


func _on_continue_pressed() -> void:
	if _choice_locked:
		return
	AdventureService.finish_room_and_return()


func _render_error() -> void:
	_event_title.text = _t("event.ui.error.title")
	_event_body.text = _t("event.ui.error.body")
	_choice_heading.text = _t("event.ui.resolved")
	_clear_options()
	_continue_button.visible = true
	_play_node_transition()


func _clear_options() -> void:
	for child in _option_list.get_children():
		_option_list.remove_child(child)
		child.queue_free()


func _set_options_disabled(disabled: bool) -> void:
	for child in _option_list.get_children():
		if child is Button:
			var button := child as Button
			button.disabled = disabled or bool(button.get_meta("event_condition_disabled", false))
			_apply_choice_button(button)


func _play_node_transition() -> void:
	if _node_tween != null and _node_tween.is_valid():
		_node_tween.kill()
	_story_panel.modulate.a = 0.0
	_story_panel.scale = Vector2(0.985, 0.985)
	_choice_panel.modulate.a = 0.0
	_node_tween = create_tween()
	_node_tween.set_parallel(true)
	_node_tween.set_trans(Tween.TRANS_QUAD)
	_node_tween.set_ease(Tween.EASE_OUT)
	_node_tween.tween_property(_story_panel, "modulate:a", 1.0, 0.2)
	_node_tween.tween_property(_story_panel, "scale", Vector2.ONE, 0.22)
	_node_tween.tween_property(_choice_panel, "modulate:a", 1.0, 0.18).set_delay(0.08)
	for i in range(_option_list.get_child_count()):
		var option := _option_list.get_child(i) as Control
		option.modulate.a = 0.0
		_node_tween.tween_property(option, "modulate:a", 1.0, 0.16).set_delay(0.1 + i * 0.04)


func _apply_choice_button(button: Button) -> void:
	var disabled := button.disabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := _choice_button_style(disabled)
		if state == "hover" and not disabled:
			style.bg_color = style.bg_color.lightened(0.08)
			style.border_color = EVENT_ACCENT.lightened(0.18)
		elif state == "pressed" and not disabled:
			style.bg_color = style.bg_color.darkened(0.1)
			style.shadow_size = 0
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_override("font", BattleUiTheme.pixel_font())
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", BattleUiTheme.TEXT if not disabled else BattleUiTheme.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var title := button.get_node_or_null("OptionContent/ChoiceTitle") as Label
	if title != null:
		title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED if disabled else BattleUiTheme.TEXT)
	var effect := button.get_node_or_null("OptionContent/EffectText") as Label
	if effect != null:
		effect.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED if disabled else BattleUiTheme.TEXT_GOLD)


func _choice_button_style(disabled: bool) -> StyleBoxFlat:
	var style := _panel_style(EVENT_INSET, EVENT_EDGE, 12, 1)
	style.shadow_size = 1
	if disabled:
		style.bg_color = EVENT_INSET.darkened(0.18)
		style.border_color = EVENT_EDGE.darkened(0.35)
		style.shadow_size = 0
	return style


func _art_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#0a0a10"), EVENT_EDGE.darkened(0.18), 5, 2)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _panel_style(bg: Color, edge: Color, margin: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style


func _t(key: String, values: Dictionary = {}) -> String:
	return tr(key).format(values)
