extends Node

const CONFIG_PATH := "res://resources/adventure/event_defs.json"
const DEFAULT_EVENT_ID := "event_abandoned_cache"
const LEGACY_NODE_ID := "legacy"
const _Validator = preload("res://scripts/services/adventure_config_validator.gd")
const _TextResolver = preload("res://scripts/services/numeric_text_resolver.gd")
const _EventContentRuntime = preload("res://scripts/services/event_content_runtime.gd")

var _defs: Dictionary = {}


func _ready() -> void:
	_load_defs()


func reload_config() -> void:
	_load_defs()


func get_event_view(room_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	var event_state := _ensure_event_snapshot(room_id)
	var event_id := str(event_state.get("event_id", ""))
	if _EventContentRuntime.handles(event_id):
		var runtime_view := _EventContentRuntime.get_event_view(room_id, event_state)
		return _with_resolution_view(runtime_view, room_state)
	var event_def := get_event_def(event_id)
	var node_id := str(event_state.get("node_id", _entry_node_id(event_def)))
	var event_node := _get_event_node(event_def, node_id)
	if event_node.is_empty():
		return {
			"ok": false,
			"room_id": room_id,
			"event_id": event_id,
			"error": "event_node_not_found",
			"title": "事件配置错误",
			"body": "这场奇遇暂时无法继续。",
			"options": [],
		}
	var resolved := str(room_state.get("status", "")) == "RESOLVED"
	var options: Array[Dictionary] = []
	if not resolved:
		for raw_option in event_node.get("options", []):
			if not raw_option is Dictionary:
				continue
			var option := (raw_option as Dictionary).duplicate(true)
			var condition_result := RoomEffectExecutor.evaluate_conditions(option.get("conditions", []), {
				"room_id": room_id,
				"event_id": event_id,
				"node_id": node_id,
				"action_id": str(option.get("id", "")),
			})
			var condition_errors: Array = condition_result.get("errors", []) if condition_result.get("errors", []) is Array else []
			options.append({
				"id": str(option.get("id", "")),
				"label": _render_text(str(option.get("label", ""))),
				"effect_text": _render_text(str(option.get("description", ""))),
				"enabled": bool(condition_result.get("ok", false)),
				"disabled_reason": str(condition_result.get("disabled_reason", "")),
				"disabled_reason_code": str(condition_errors[0]) if not condition_errors.is_empty() else "",
			})
	return _with_resolution_view({
		"ok": true,
		"room_id": room_id,
		"event_id": event_id,
		"node_id": node_id,
		"resolved": resolved,
		"title": _render_text(str(event_node.get("title", event_id))),
		"body": _render_text(str(event_node.get("body", ""))),
		"options": options,
	}, room_state)


## A resolved event remains a readable outcome until the player explicitly
## leaves the room.  The room result is authoritative because a runtime event
## may have no separate result node after its last choice.
func _with_resolution_view(view: Dictionary, room_state: Dictionary) -> Dictionary:
	var result := (room_state.get("result", {}) as Dictionary).duplicate(true) if room_state.get("result", {}) is Dictionary else {}
	var resolved := str(room_state.get("status", "")) == "RESOLVED"
	view["resolved"] = resolved
	if not resolved:
		return view
	view["options"] = []
	view["result_summary"] = str(result.get("summary", ""))
	view["completion_title"] = "事件结算"
	view["completion_body"] = str(result.get("summary", ""))
	return view


func choose_option(room_id: String, option_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	if str(room_state.get("status", "")) == "RESOLVED":
		var resolved_result: Variant = room_state.get("result", {})
		return {
			"ok": true,
			"replayed": true,
			"result": (resolved_result as Dictionary).duplicate(true) if resolved_result is Dictionary else {},
		}
	var event_state := _ensure_event_snapshot(room_id)
	var event_id := str(event_state.get("event_id", ""))
	if _EventContentRuntime.handles(event_id):
		return _choose_runtime_option(room_id, event_state, option_id)
	var event_def := get_event_def(event_id)
	var node_id := str(event_state.get("node_id", _entry_node_id(event_def)))
	var event_node := _get_event_node(event_def, node_id)
	if event_node.is_empty():
		return {"ok": false, "error": "event_node_not_found"}
	var target_option := {}
	for raw_option in event_node.get("options", []):
		if raw_option is Dictionary and str((raw_option as Dictionary).get("id", "")) == option_id:
			target_option = (raw_option as Dictionary).duplicate(true)
			break
	if target_option.is_empty():
		return {"ok": false, "error": "option_not_found"}
	var condition_result := RoomEffectExecutor.evaluate_conditions(target_option.get("conditions", []), {
		"room_id": room_id,
		"event_id": event_id,
		"node_id": node_id,
		"action_id": option_id,
	})
	if not bool(condition_result.get("ok", false)):
		return {
			"ok": false,
			"error": "conditions_failed",
			"disabled_reason": str(condition_result.get("disabled_reason", "")),
		}
	var next_node_id := str(target_option.get("next", ""))
	var is_legacy_event := not event_def.has("nodes")
	var resolved := bool(target_option.get("finish", false)) or (is_legacy_event and next_node_id.is_empty())
	if not resolved and next_node_id.is_empty():
		return {"ok": false, "error": "missing_event_transition"}
	if not next_node_id.is_empty() and _get_event_node(event_def, next_node_id).is_empty():
		return {"ok": false, "error": "next_event_node_not_found"}
	var choice_count := int(event_state.get("choice_count", 0))
	var transaction_id := "%s:event:%d:%s:%s" % [room_id, choice_count, node_id, option_id]
	var call_result := _apply_option_calls(target_option, {
		"room_id": room_id,
		"room_type": "EVENT",
		"transaction_id": transaction_id,
		"event_id": event_id,
		"node_id": node_id,
		"action_id": option_id,
	})
	if not bool(call_result.get("ok", false)):
		return call_result
	var history: Array = event_state.get("history", []).duplicate(true) if event_state.get("history", []) is Array else []
	history.append({"node_id": node_id, "option_id": option_id})
	event_state["history"] = history
	event_state["choice_count"] = choice_count + 1
	if not next_node_id.is_empty():
		event_state["node_id"] = next_node_id
	_store_event_snapshot(room_id, event_state, "RESOLVED" if resolved else "AWAITING_DECISION")
	var applied: Array[String] = call_result.get("summaries", []).duplicate(true) if call_result.get("summaries", []) is Array else []
	var result := {
		"room_id": room_id,
		"room_type": "EVENT",
		"event_id": event_id,
		"node_id": node_id,
		"option_id": option_id,
		"next_node_id": next_node_id,
		"resolved": resolved,
		"summary": _choice_summary(event_def, event_node, next_node_id, applied),
		"call_results": call_result.get("results", []).duplicate(true),
	}
	RunService.append_room_transaction(room_id, transaction_id, result)
	if resolved:
		RunService.mark_room_resolved(room_id, result)
	return {"ok": true, "result": result}


func get_event_def(event_id: String) -> Dictionary:
	var raw: Variant = _defs.get(event_id, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _choose_runtime_option(room_id: String, event_state: Dictionary, option_id: String) -> Dictionary:
	var choice_count := int(event_state.get("choice_count", 0))
	var phase := str(event_state.get("phase", "start"))
	var transaction_id := "%s:event:%d:%s:%s" % [room_id, choice_count, phase, option_id]
	var call_result := _EventContentRuntime.choose_option(room_id, event_state, option_id, transaction_id)
	if not bool(call_result.get("ok", false)):
		return call_result
	var next_state: Dictionary = call_result.get("event_state", {}).duplicate(true)
	var history: Array = next_state.get("history", []).duplicate(true) if next_state.get("history", []) is Array else []
	history.append({"node_id": phase, "option_id": option_id})
	next_state["history"] = history
	next_state["choice_count"] = choice_count + 1
	var resolved := bool(call_result.get("resolved", false))
	_store_event_snapshot(room_id, next_state, "RESOLVED" if resolved else "AWAITING_DECISION")
	var result := {
		"room_id": room_id,
		"room_type": "EVENT",
		"event_id": str(next_state.get("event_id", "")),
		"node_id": phase,
		"option_id": option_id,
		"next_node_id": str(next_state.get("phase", phase)),
		"resolved": resolved,
		"summary": str(call_result.get("summary", "")),
	}
	RunService.append_room_transaction(room_id, transaction_id, result)
	if resolved:
		RunService.mark_room_resolved(room_id, result)
	return {"ok": true, "result": result}


func _apply_option_calls(option: Dictionary, ctx: Dictionary) -> Dictionary:
	if option.has("calls"):
		return RoomEffectExecutor.apply_calls(option.get("calls", []), ctx)
	return RoomEffectExecutor.apply_effects(option.get("effects", []), ctx)


func _choice_summary(event_def: Dictionary, current_node: Dictionary, next_node_id: String, applied: Array[String]) -> String:
	if not next_node_id.is_empty():
		var next_node := _get_event_node(event_def, next_node_id)
		return _render_text(str(next_node.get("body", "")))
	if not applied.is_empty():
		return "，".join(applied)
	return _render_text(str(current_node.get("body", "")))


func _ensure_event_snapshot(room_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	var snapshot: Dictionary = room_state.get("snapshot", {}).duplicate(true) if room_state.get("snapshot", {}) is Dictionary else {}
	var event_state: Dictionary = snapshot.get("event", {}).duplicate(true) if snapshot.get("event", {}) is Dictionary else {}
	if event_state.has("event_id"):
		var saved_event_def := get_event_def(str(event_state.get("event_id", "")))
		if not event_state.has("node_id"):
			event_state["node_id"] = _entry_node_id(saved_event_def)
			_store_event_snapshot(room_id, event_state, str(room_state.get("status", "AWAITING_DECISION")))
		return event_state
	var event_id := AdventureService.event_id_for_room(room_id)
	if event_id.is_empty() or get_event_def(event_id).is_empty():
		event_id = DEFAULT_EVENT_ID
	event_id = _EventContentRuntime.resolve_event_id(room_id, event_id)
	var event_def := get_event_def(event_id)
	event_state = {
		"event_id": event_id,
		"node_id": _entry_node_id(event_def),
		"choice_count": 0,
		"history": [],
	}
	var is_runtime_event := _EventContentRuntime.handles(event_id)
	if is_runtime_event:
		event_state = _EventContentRuntime.prepare(room_id, event_state)
	_store_event_snapshot(room_id, event_state, str(room_state.get("status", "AWAITING_DECISION")))
	if is_runtime_event:
		_EventContentRuntime.record_encounter(event_id)
	return event_state


func _store_event_snapshot(room_id: String, event_state: Dictionary, status: String) -> void:
	var room_state := RunService.ensure_room_state(room_id, "EVENT")
	var snapshot: Dictionary = room_state.get("snapshot", {}).duplicate(true) if room_state.get("snapshot", {}) is Dictionary else {}
	snapshot["event"] = event_state.duplicate(true)
	room_state["snapshot"] = snapshot
	room_state["status"] = status
	RunService.set_room_state(room_id, room_state)


func _entry_node_id(event_def: Dictionary) -> String:
	if event_def.has("nodes"):
		return str(event_def.get("entry", "start"))
	return LEGACY_NODE_ID


func _get_event_node(event_def: Dictionary, node_id: String) -> Dictionary:
	if not event_def.has("nodes"):
		return event_def.duplicate(true) if node_id == LEGACY_NODE_ID else {}
	var nodes: Variant = event_def.get("nodes", {})
	if not nodes is Dictionary:
		return {}
	var raw_node: Variant = (nodes as Dictionary).get(node_id, {})
	return (raw_node as Dictionary).duplicate(true) if raw_node is Dictionary else {}


func _load_defs() -> void:
	_defs = _load_json(CONFIG_PATH)
	_Validator.ensure_valid(CONFIG_PATH, _Validator.validate_event_defs(_defs, EconomyService.get_amount_refs()))


func _render_text(template: String) -> String:
	return _TextResolver.format_text(template, {
		"amount_refs": EconomyService.get_amount_refs(),
	})


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
