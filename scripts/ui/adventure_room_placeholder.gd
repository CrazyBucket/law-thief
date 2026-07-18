extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

@onready var _title: Label = $Content/VBox/Title
@onready var _body: Label = $Content/VBox/Body
@onready var _continue_btn: Button = $Content/VBox/ContinueBtn
@onready var _back_btn: Button = $BackBtn
@onready var _vbox: VBoxContainer = $Content/VBox

var _room_id: String = ""
var _dynamic_nodes: Array[Node] = []


func _ready() -> void:
	theme = BattleUiTheme.build_theme()
	_apply_theme()
	_room_id = AdventureService.current_room_id()
	_title.text = "%s · %s" % [SaveService.get_active_slot_label(), AdventureService.pending_room_label]
	BattleUiTheme.apply_button(_continue_btn, "end")
	BattleUiTheme.apply_button(_back_btn, "ghost")
	_refresh_room_view(RoomFlowService.enter_room(_room_id))


func _apply_theme() -> void:
	$Content.add_theme_stylebox_override("panel", BattleUiTheme.panel_style())
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_body.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)


func _refresh_room_view(room_view: Dictionary) -> void:
	_clear_dynamic_nodes()
	var summary := str(room_view.get("summary", ""))
	_body.text = summary
	var state := str(room_view.get("state", "AWAITING_DECISION"))
	var payload: Dictionary = room_view.get("payload", {})
	var is_event := payload.has("event")
	if payload.has("shop"):
		_render_shop_view(payload.get("shop", {}), summary)
	elif is_event:
		_render_event_view(payload.get("event", {}), summary, state == "RESOLVED")
	_back_btn.visible = not is_event
	_continue_btn.visible = not is_event or state == "RESOLVED"
	if state == "RESOLVED":
		_continue_btn.text = "继续"
	else:
		_continue_btn.text = "离开商店" if payload.has("shop") else "确认"


func _on_continue_pressed() -> void:
	var room_view := RoomFlowService.get_room_view(_room_id)
	var payload: Dictionary = room_view.get("payload", {})
	if payload.has("event") and str(room_view.get("state", "")) != "RESOLVED":
		return
	if str(room_view.get("state", "")) == "RESOLVED" or payload.has("shop") or payload.has("event"):
		AdventureService.finish_room_and_return()
		return
	_refresh_room_view(RoomFlowService.submit_room_command(_room_id, {}))


func _on_back_pressed() -> void:
	AdventureService.finish_room_and_return()


func _render_shop_view(shop_view: Dictionary, summary: String) -> void:
	_body.text = "当前金币：%d\n%s" % [int(shop_view.get("gold", 0)), summary]
	for offer in shop_view.get("offers", []):
		if not offer is Dictionary:
			continue
		var offer_dict := offer as Dictionary
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.custom_minimum_size = Vector2(320, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s · %s · %d金%s" % [
			str(offer_dict.get("display_name", "")),
			_rarity_name(str(offer_dict.get("rarity", "common"))),
			int(offer_dict.get("final_price", 0)),
			" · 已售罄" if bool(offer_dict.get("sold_out", false)) else ""
		]
		row.add_child(label)
		var btn := Button.new()
		btn.text = "购买"
		btn.disabled = bool(offer_dict.get("sold_out", false)) or not str(offer_dict.get("disabled_reason", "")).is_empty()
		if btn.disabled:
			btn.text = str(offer_dict.get("disabled_reason", "购买"))
		else:
			BattleUiTheme.apply_button(btn, "end")
		btn.pressed.connect(func() -> void:
			_refresh_room_view(RoomFlowService.submit_room_command(_room_id, {
				"action": "purchase",
				"offer_id": str(offer_dict.get("offer_id", "")),
			}))
		)
		row.add_child(btn)
		_vbox.add_child(row)
		_dynamic_nodes.append(row)


func _render_event_view(event_view: Dictionary, summary: String, resolved: bool) -> void:
	_body.text = "%s\n%s" % [str(event_view.get("title", "事件")), str(event_view.get("body", summary))]
	if resolved:
		return
	for option in event_view.get("options", []):
		if not option is Dictionary:
			continue
		var option_dict := option as Dictionary
		var btn := Button.new()
		btn.text = str(option_dict.get("label", "选择"))
		btn.custom_minimum_size = Vector2(0, 46)
		btn.disabled = not bool(option_dict.get("enabled", true))
		var disabled_reason := str(option_dict.get("disabled_reason", ""))
		if btn.disabled and not disabled_reason.is_empty():
			btn.text = "%s（%s）" % [btn.text, disabled_reason]
			btn.tooltip_text = disabled_reason
		BattleUiTheme.apply_button(btn, "end")
		if not btn.disabled:
			btn.pressed.connect(func() -> void:
				_refresh_room_view(RoomFlowService.submit_room_command(_room_id, {
					"action": "choose_option",
					"option_id": str(option_dict.get("id", "")),
				}))
			)
		_vbox.add_child(btn)
		_dynamic_nodes.append(btn)


func _clear_dynamic_nodes() -> void:
	for node in _dynamic_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_dynamic_nodes.clear()


func _rarity_name(rarity: String) -> String:
	match rarity:
		"common":
			return "普通"
		"uncommon":
			return "罕见"
		"rare":
			return "稀有"
		"epic":
			return "史诗"
		"legendary":
			return "传说"
		"boss":
			return "首领"
		_:
			return rarity
