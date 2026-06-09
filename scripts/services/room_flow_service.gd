extends Node


func enter_room(room_id: String) -> Dictionary:
	if not RunService.is_run_active():
		return _response(false, room_id, "", {}, [], ["no_active_run"])
	var room_type := AdventureService.room_type_for_room_id(room_id)
	var room_state := RunService.ensure_room_state(room_id, room_type)
	var status := str(room_state.get("status", "UNENTERED"))
	if status == "UNENTERED":
		room_state["status"] = "ENTERED"
		RunService.set_room_state(room_id, room_state)
	elif status == "LEFT":
		room_state["status"] = "ENTERED"
		RunService.set_room_state(room_id, room_state)
	RunService.set_run_phase("ROOM")
	RunService.set_pending_decision({
		"type": "room",
		"room_id": room_id,
		"room_type": room_type,
	})
	return get_room_view(room_id)


func get_room_view(room_id: String) -> Dictionary:
	if not RunService.is_run_active():
		return _response(false, room_id, "", {}, [], ["no_active_run"])
	var room_type := AdventureService.room_type_for_room_id(room_id)
	var room_state := RunService.ensure_room_state(room_id, room_type)
	var status := str(room_state.get("status", "UNENTERED"))
	if status == "ENTERED":
		room_state["status"] = "AWAITING_DECISION"
		RunService.set_room_state(room_id, room_state)
		status = "AWAITING_DECISION"
	var result := {}
	var raw_result: Variant = room_state.get("result", {})
	if raw_result is Dictionary:
		result = (raw_result as Dictionary).duplicate(true)
	var payload := {}
	if room_type == "SHOP":
		payload["shop"] = ShopService.get_shop_view(room_id)
	elif room_type == "EVENT":
		payload["event"] = EventService.get_event_view(room_id)
	return _response(
		true,
		room_id,
		status,
		result,
		[],
		[],
		_build_room_summary(room_type, room_state, result, payload),
		payload,
	)


func submit_room_command(room_id: String, command: Dictionary) -> Dictionary:
	if not RunService.is_run_active():
		return _response(false, room_id, "", {}, [], ["no_active_run"])
	var room_type := AdventureService.room_type_for_room_id(room_id)
	var room_state := RunService.ensure_room_state(room_id, room_type)
	var status := str(room_state.get("status", "UNENTERED"))
	if room_type == "SHOP" and str(command.get("action", "")) == "purchase":
		var offer_id := str(command.get("offer_id", ""))
		var purchase_result := ShopService.purchase_offer(room_id, offer_id)
		if not bool(purchase_result.get("ok", false)):
			return _response(
				false,
				room_id,
				status,
				{},
				[],
				[str(purchase_result.get("error", "purchase_failed"))],
				_shop_error_summary(purchase_result),
				{"shop": ShopService.get_shop_view(room_id)},
			)
		var result: Dictionary = purchase_result.get("result", {})
		return _response(
			true,
			room_id,
			"AWAITING_DECISION",
			result,
			[],
			[],
			str(result.get("summary", "")),
			{"shop": ShopService.get_shop_view(room_id)},
		)
	if room_type == "EVENT" and str(command.get("action", "")) == "choose_option":
		var option_id := str(command.get("option_id", ""))
		var event_result := EventService.choose_option(room_id, option_id)
		if not bool(event_result.get("ok", false)):
			return _response(
				false,
				room_id,
				status,
				{},
				[],
				[str(event_result.get("error", "event_failed"))],
				"事件结算失败。",
				{"event": EventService.get_event_view(room_id)},
			)
		var result: Dictionary = event_result.get("result", {})
		return _response(
			true,
			room_id,
			"RESOLVED",
			result,
			[],
			[],
			str(result.get("summary", "")),
			{"event": EventService.get_event_view(room_id)},
		)
	if status == "RESOLVED":
		var existing: Variant = room_state.get("result", {})
		var existing_result := (existing as Dictionary).duplicate(true) if existing is Dictionary else {}
		return _response(true, room_id, status, existing_result, [], [], str(existing_result.get("summary", "")), {})
	var action := str(command.get("action", "resolve"))
	if action != "resolve":
		return _response(false, room_id, status, {}, [], ["unsupported_room_action"])
	var transaction_id := str(command.get("transaction_id", "%s:resolve" % room_id))
	var transactions: Array = room_state.get("transactions", []).duplicate(true) if room_state.get("transactions", []) is Array else []
	for raw_tx in transactions:
		if raw_tx is Dictionary and str(raw_tx.get("transaction_id", "")) == transaction_id:
			var raw_result: Variant = raw_tx.get("result", {})
			var cached_result := (raw_result as Dictionary).duplicate(true) if raw_result is Dictionary else {}
			return _response(true, room_id, "RESOLVED", cached_result, [], [], str(cached_result.get("summary", "")))
	var resolved := _resolve_room(room_id, room_type)
	if not bool(resolved.get("ok", false)):
		return resolved
	var result: Dictionary = resolved.get("result", {})
	room_state = RunService.ensure_room_state(room_id, room_type)
	room_state["status"] = "RESOLVED"
	room_state["result"] = result.duplicate(true)
	RunService.set_room_state(room_id, room_state, false)
	RunService.append_room_transaction(room_id, transaction_id, result)
	if not bool(result.get("chapter_advanced", false)):
		RunService.mark_room_resolved(room_id, result)
	RunService.clear_pending_decision()
	RunService.set_run_phase("ROOM")
	return _response(true, room_id, "RESOLVED", result, [], [], str(result.get("summary", "")), {})


func leave_room(room_id: String) -> Dictionary:
	if not RunService.is_run_active():
		return _response(false, room_id, "", {}, [], ["no_active_run"])
	var room_state := RunService.get_room_state(room_id)
	if room_state.is_empty():
		return _response(true, room_id, "LEFT", {}, [], [])
	var room_type := AdventureService.room_type_for_room_id(room_id)
	if room_type == "SHOP" and not RunService.is_room_resolved(room_id):
		RunService.mark_room_resolved(room_id, {
			"room_id": room_id,
			"room_type": "SHOP",
			"summary": "商店已访问。",
		})
		room_state = RunService.get_room_state(room_id)
	room_state["status"] = "LEFT"
	RunService.set_room_state(room_id, room_state)
	var pending := RunService.get_pending_decision()
	if str(pending.get("room_id", "")) == room_id:
		RunService.clear_pending_decision()
	RunService.set_run_phase("MAP")
	var result := {}
	var raw_result: Variant = room_state.get("result", {})
	if raw_result is Dictionary:
		result = (raw_result as Dictionary).duplicate(true)
	return _response(true, room_id, "LEFT", result, [], [], str(result.get("summary", "")))


func _resolve_room(room_id: String, room_type: String) -> Dictionary:
	var result := {
		"room_id": room_id,
		"room_type": room_type,
	}
	match room_type:
		"REST_SITE":
			var heal_result := RunService.heal_player_percent(0.2)
			result["heal"] = heal_result
			result["summary"] = "营地休整，恢复 %d 点生命，当前 %d/%d。" % [
				int(heal_result.get("amount", 0)),
				int(heal_result.get("after_hp", 0)),
				int(heal_result.get("max_hp", 0)),
			]
		"EVENT":
			result["summary"] = "事件等待选择。"
		"SHOP":
			RunService.get_or_roll_gem_offer(room_id, "shop", 3)
			result["summary"] = "商店节点先保留，占位等待后续接入商品与购买流程。"
		"END":
			var chapter := AdventureService.get_current_chapter()
			if chapter < AdventureService.get_chapter_count():
				var completed := chapter
				AdventureService._advance_to_next_chapter()
				result["chapter_advanced"] = true
				result["summary"] = "完成第 %d 关，进入第 %d 关。" % [completed, AdventureService.get_current_chapter()]
			else:
				result["run_complete"] = true
				result["summary"] = "三条线路全部打通，本局胜利。"
		_:
			result["summary"] = "房间已结算。"
	return {
		"ok": true,
		"result": result,
	}


func _build_room_summary(room_type: String, room_state: Dictionary, result: Dictionary, payload: Dictionary = {}) -> String:
	if not result.is_empty():
		return str(result.get("summary", ""))
	match room_type:
		"REST_SITE":
			return "营地可用于恢复生命，当前先实现固定回血。"
		"SHOP":
			var shop_view: Dictionary = payload.get("shop", {})
			return "当前金币 %d，可购买宝石或遗物。" % int(shop_view.get("gold", 0))
		"EVENT":
			var event_view: Dictionary = payload.get("event", {})
			return "%s\n%s" % [str(event_view.get("title", "事件")), str(event_view.get("body", ""))]
		"END":
			return "大关终点：确认后进入下一关或通关回主菜单。"
		_:
			return "房间场景占位，当前用于承接整体流程跳转。"


func _shop_error_summary(purchase_result: Dictionary) -> String:
	match str(purchase_result.get("error", "")):
		"insufficient_funds":
			return "金币不足，无法购买。"
		"carried_gem_occupied":
			return "手持已有宝石，无法再购买宝石。"
		"sold_out":
			return "该商品已售罄。"
		"offer_not_found":
			return "商品不存在。"
		_:
			return "购买失败。"


func _response(
	ok: bool,
	room_id: String,
	state: String,
	result: Dictionary,
	events: Array,
	errors: Array,
	summary: String = "",
	payload: Dictionary = {}
) -> Dictionary:
	return {
		"ok": ok,
		"room_id": room_id,
		"state": state,
		"result": result.duplicate(true),
		"events": events.duplicate(true),
		"summary": summary,
		"errors": errors.duplicate(true),
		"payload": payload.duplicate(true),
	}
