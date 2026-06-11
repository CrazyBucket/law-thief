extends Node

const CONFIG_PATH := "res://resources/adventure/shop_pools.json"
const _Validator = preload("res://scripts/services/adventure_config_validator.gd")

var _config: Dictionary = {}


func _ready() -> void:
	_load_config()


func reload_config() -> void:
	_load_config()


func get_shop_view(room_id: String) -> Dictionary:
	var shop_state := _ensure_shop_snapshot(room_id)
	var offers: Array = shop_state.get("offers", [])
	var view_offers: Array[Dictionary] = []
	for raw_offer in offers:
		if not raw_offer is Dictionary:
			continue
		var offer := (raw_offer as Dictionary).duplicate(true)
		var item_type := str(offer.get("item_type", "gem"))
		var item_id := str(offer.get("item_id", ""))
		var display_name := item_id
		var rarity := "common"
		if item_type == "relic":
			var relic_def := DataRegistry.get_relic_def(item_id)
			display_name = str(relic_def.get("name", item_id))
			rarity = DataRegistry.get_relic_rarity(item_id)
		else:
			display_name = DataRegistry.get_gem_display_name(item_id)
			rarity = DataRegistry.get_gem_rarity(item_id)
		var base_price := int(offer.get("base_price", 0))
		var quote := EconomyService.quote("gold", base_price, "shop_price", {
			"room_id": room_id,
			"offer_id": str(offer.get("offer_id", "")),
			"item_type": item_type,
		})
		var final_price := int(quote.get("final_amount", base_price))
		var sold_out := bool(offer.get("sold_out", false))
		var disabled_reason := ""
		if sold_out:
			disabled_reason = "已售罄"
		elif EconomyService.get_balance("gold") < final_price:
			disabled_reason = "金币不足"
		elif item_type == "gem" and not RunService.get_run().carried_gem.is_empty():
			disabled_reason = "手持已有宝石"
		view_offers.append({
			"offer_id": str(offer.get("offer_id", "")),
			"item_type": item_type,
			"item_id": item_id,
			"display_name": display_name,
			"rarity": rarity,
			"base_price": base_price,
			"final_price": final_price,
			"price_trace": quote,
			"sold_out": sold_out,
			"disabled_reason": disabled_reason,
		})
	return {
		"ok": true,
		"room_id": room_id,
		"gold": EconomyService.get_balance("gold"),
		"offers": view_offers,
	}


func purchase_offer(room_id: String, offer_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "SHOP")
	var snapshot: Dictionary = room_state.get("snapshot", {}).duplicate(true) if room_state.get("snapshot", {}) is Dictionary else {}
	var shop_state: Dictionary = snapshot.get("shop", {}).duplicate(true) if snapshot.get("shop", {}) is Dictionary else {}
	var offers: Array = shop_state.get("offers", []).duplicate(true) if shop_state.get("offers", []) is Array else []
	var transaction_id := "%s:shop:%s" % [room_id, offer_id]
	for raw_tx in room_state.get("transactions", []):
		if raw_tx is Dictionary and str(raw_tx.get("transaction_id", "")) == transaction_id:
			var existing: Variant = raw_tx.get("result", {})
			return {"ok": true, "result": (existing as Dictionary).duplicate(true) if existing is Dictionary else {}}
	var target_idx := -1
	var target_offer: Dictionary = {}
	for i in range(offers.size()):
		var raw_offer: Variant = offers[i]
		if raw_offer is Dictionary and str((raw_offer as Dictionary).get("offer_id", "")) == offer_id:
			target_idx = i
			target_offer = (raw_offer as Dictionary).duplicate(true)
			break
	if target_idx < 0:
		return {"ok": false, "error": "offer_not_found"}
	if bool(target_offer.get("sold_out", false)):
		return {"ok": false, "error": "sold_out"}
	var item_type := str(target_offer.get("item_type", "gem"))
	var item_id := str(target_offer.get("item_id", ""))
	var base_price := int(target_offer.get("base_price", 0))
	var quote := EconomyService.quote("gold", base_price, "shop_price", {
		"room_id": room_id,
		"offer_id": offer_id,
		"item_type": item_type,
	})
	var final_price := int(quote.get("final_amount", base_price))
	if item_type == "gem" and not RunService.get_run().carried_gem.is_empty():
		return {"ok": false, "error": "carried_gem_occupied"}
	if EconomyService.get_balance("gold") < final_price:
		return {"ok": false, "error": "insufficient_funds", "required": final_price}
	if item_type == "relic":
		RunService.acquire_relic(item_id)
	else:
		var acquire_result := RunService.acquire_gem(item_id)
		if not bool(acquire_result.get("ok", false)):
			return acquire_result
	var spend_result := EconomyService.spend("gold", final_price, "shop_purchase", {
		"transaction_id": transaction_id,
		"room_id": room_id,
		"offer_id": offer_id,
		"item_type": item_type,
		"item_id": item_id,
	})
	if not bool(spend_result.get("ok", false)):
		return spend_result
	target_offer["sold_out"] = true
	offers[target_idx] = target_offer
	shop_state["offers"] = offers
	snapshot["shop"] = shop_state
	room_state["snapshot"] = snapshot
	room_state["status"] = "AWAITING_DECISION"
	var result := {
		"room_id": room_id,
		"room_type": "SHOP",
		"offer_id": offer_id,
		"item_type": item_type,
		"item_id": item_id,
		"price": final_price,
		"summary": "购买成功：%s，花费 %d 金币。" % [_display_name(item_type, item_id), final_price],
	}
	RunService.set_room_state(room_id, room_state, false)
	RunService.append_room_transaction(room_id, transaction_id, result)
	return {"ok": true, "result": result}


func _ensure_shop_snapshot(room_id: String) -> Dictionary:
	var room_state := RunService.ensure_room_state(room_id, "SHOP")
	var snapshot: Dictionary = room_state.get("snapshot", {}).duplicate(true) if room_state.get("snapshot", {}) is Dictionary else {}
	var shop_state: Dictionary = snapshot.get("shop", {}).duplicate(true) if snapshot.get("shop", {}) is Dictionary else {}
	if shop_state.has("offers"):
		return shop_state
	var pool: Dictionary = (_config.get("default", {}) as Dictionary).duplicate(true) if _config.get("default", {}) is Dictionary else {}
	var gem_count := int(pool.get("gem_offer_count", 2))
	var relic_count := int(pool.get("relic_offer_count", 1))
	var gem_source := str(pool.get("gem_source", "shop"))
	var relic_source := str(pool.get("relic_source", "shop"))
	var gem_offer: Array[String] = RunService.get_or_roll_gem_offer("%s:shop_gems" % room_id, gem_source, gem_count)
	var relic_offer: Array[String] = RunService.get_or_roll_relic_offer("%s:shop_relics" % room_id, relic_source, relic_count)
	var offers: Array[Dictionary] = []
	for i in range(gem_offer.size()):
		var gem_id := str(gem_offer[i])
		if gem_id.is_empty():
			continue
		offers.append({
			"offer_id": "gem_%d" % i,
			"item_type": "gem",
			"item_id": gem_id,
			"base_price": EconomyService.get_base_price("gem"),
			"sold_out": false,
		})
	for i in range(relic_offer.size()):
		var relic_id := str(relic_offer[i])
		if relic_id.is_empty() or relic_id == "relic_placeholder":
			continue
		offers.append({
			"offer_id": "relic_%d" % i,
			"item_type": "relic",
			"item_id": relic_id,
			"base_price": EconomyService.get_base_price("relic"),
			"sold_out": false,
		})
	shop_state = {
		"offers": offers,
	}
	snapshot["shop"] = shop_state
	room_state["snapshot"] = snapshot
	RunService.set_room_state(room_id, room_state)
	return shop_state


func _display_name(item_type: String, item_id: String) -> String:
	if item_type == "relic":
		return str(DataRegistry.get_relic_def(item_id).get("name", item_id))
	return DataRegistry.get_gem_display_name(item_id)


func _load_config() -> void:
	_config = _load_json(CONFIG_PATH)
	_Validator.ensure_valid(CONFIG_PATH, _Validator.validate_shop_pools(_config))


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
