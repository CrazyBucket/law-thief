extends Node

const CONFIG_PATH := "res://resources/adventure/event_defs.json"

var _defs: Dictionary = {}


func _ready() -> void:
	_load_defs()


func reload_config() -> void:
	_load_defs()


func get_event_view(room_id: String) -> Dictionary:
	var event_state := _ensure_event_snapshot(room_id)
	var event_id := str(event_state.get("event_id", ""))
	var def := get_event_def(event_id)
	var options: Array[Dictionary] = []
	for raw_option in def.get("options", []):
		if not raw_option is Dictionary:
			continue
		var option := (raw_option as Dictionary).duplicate(true)
		options.append({
			"id": str(option.get("id", "")),
			"label": str(option.get("label", "")),
		})
	return {
		"ok": true,
		"room_id": room_id,
		"event_id": event_id,
		"title": str(def.get("title", event_id)),
		"body": str(def.get("body", "")),
		"options": options,
	}


func choose_option(room_id: String, option_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	var transaction_id := "%s:event:%s" % [room_id, option_id]
	for raw_tx in room_state.get("transactions", []):
		if raw_tx is Dictionary and str(raw_tx.get("transaction_id", "")) == transaction_id:
			var raw_result: Variant = raw_tx.get("result", {})
			return {"ok": true, "result": (raw_result as Dictionary).duplicate(true) if raw_result is Dictionary else {}}
	var event_state := _ensure_event_snapshot(room_id)
	var event_id := str(event_state.get("event_id", ""))
	var def := get_event_def(event_id)
	var target_option := {}
	for raw_option in def.get("options", []):
		if raw_option is Dictionary and str((raw_option as Dictionary).get("id", "")) == option_id:
			target_option = (raw_option as Dictionary).duplicate(true)
			break
	if target_option.is_empty():
		return {"ok": false, "error": "option_not_found"}
	var applied: Array[String] = []
	for raw_effect in target_option.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect := raw_effect as Dictionary
		var effect_result := _apply_effect(effect, room_id, transaction_id)
		if not bool(effect_result.get("ok", false)):
			return effect_result
		applied.append(str(effect_result.get("summary", "")))
	var result := {
		"room_id": room_id,
		"room_type": "EVENT",
		"event_id": event_id,
		"option_id": option_id,
		"summary": "事件完成：%s。" % "，".join(applied),
	}
	room_state = RunService.ensure_room_state(room_id, "EVENT")
	room_state["result"] = result.duplicate(true)
	RunService.set_room_state(room_id, room_state, false)
	RunService.append_room_transaction(room_id, transaction_id, result)
	RunService.mark_room_resolved(room_id, result)
	return {"ok": true, "result": result}


func get_event_def(event_id: String) -> Dictionary:
	var raw: Variant = _defs.get(event_id, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _ensure_event_snapshot(room_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	var snapshot: Dictionary = room_state.get("snapshot", {}).duplicate(true) if room_state.get("snapshot", {}) is Dictionary else {}
	var event_state: Dictionary = snapshot.get("event", {}).duplicate(true) if snapshot.get("event", {}) is Dictionary else {}
	if event_state.has("event_id"):
		return event_state
	var event_id := AdventureService.event_id_for_room(room_id)
	if event_id.is_empty():
		event_id = "event_debug_cache"
	event_state = {"event_id": event_id}
	snapshot["event"] = event_state
	room_state["snapshot"] = snapshot
	RunService.set_room_state(room_id, room_state)
	return event_state


func _apply_effect(effect: Dictionary, room_id: String, transaction_id: String) -> Dictionary:
	match str(effect.get("action", "")):
		"grant_resource":
			var amount := int(effect.get("amount", 0))
			var grant_result := EconomyService.grant(
				str(effect.get("resource_id", "gold")),
				amount,
				"event_reward",
				{"transaction_id": transaction_id, "room_id": room_id}
			)
			if not bool(grant_result.get("ok", false)):
				return grant_result
			var entry: Dictionary = grant_result.get("entry", {})
			return {"ok": true, "summary": EconomyService.format_entry(entry)}
		"add_adventure_rule":
			var rule_id := str(effect.get("rule_id", ""))
			var rule_result := AdventureRuleRegistry.add_rule(rule_id, "run", room_id, {"room_id": room_id})
			if not bool(rule_result.get("ok", false)):
				return rule_result
			var display := AdventureRuleRegistry.get_rule_display(rule_id)
			return {"ok": true, "summary": "获得规则 %s" % str(display.get("name", rule_id))}
		"heal_player":
			var amount := int(effect.get("amount", 0))
			var heal_result := RunService.heal_player_amount(amount)
			return {
				"ok": true,
				"summary": "恢复 %d 点生命" % int(heal_result.get("amount", 0)),
			}
		_:
			return {"ok": false, "error": "unknown_effect"}


func _load_defs() -> void:
	_defs = _load_json(CONFIG_PATH)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var data: Variant = json.get_data()
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}
