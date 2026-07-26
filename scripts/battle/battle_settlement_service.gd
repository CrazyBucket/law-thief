class_name BattleSettlementService
extends RefCounted

const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _GemRules = preload("res://scripts/rules/gem_rules.gd")
const _OverloadRules = preload("res://scripts/rules/overload_rules.gd")
const _GemLocation = preload("res://scripts/data/gem_location.gd")
const _UnitRewardRules = preload("res://scripts/rules/unit_reward_rules.gd")

const DROPPED_GEM_REWARD_HANDLED := "dropped_gem_reward_handled"


static func dropped_gem_offer(state: GameState) -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	if state == null:
		return offer
	var uids := state.dropped_gems.keys()
	uids.sort()
	for raw_uid in uids:
		var uid := str(raw_uid)
		var drop: Dictionary = state.dropped_gems.get(uid, {})
		var gem_uid := str(drop.get("gem_uid", uid))
		var gem: GemState = state.gems.get(gem_uid, null)
		if gem == null:
			continue
		offer.append({
			"gem_uid": gem_uid,
			"gem_id": gem.gem_id,
			"def_overrides": gem.def_overrides.duplicate(true),
			"pos": drop.get("pos", Vector2i.ZERO),
			"source_unit_uid": str(drop.get("source_unit_uid", "")),
			"source_slot_type": str(drop.get("source_slot_type", "")),
			"source_kind": _GemLocation.GROUND,
		})
	var units: Array = state.units.values()
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	for unit: UnitState in units:
		if unit.alive or not _UnitRewardRules.can_drop_gems(unit):
			continue
		for slot_index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[slot_index]
			if slot == null or slot.gem_uid.is_empty() or state.dropped_gems.has(slot.gem_uid):
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null:
				continue
			offer.append({
				"gem_uid": gem.uid,
				"gem_id": gem.gem_id,
				"def_overrides": gem.def_overrides.duplicate(true),
				"pos": unit.pos,
				"source_unit_uid": unit.uid,
				"source_slot_type": slot.slot_type,
				"source_slot_index": slot_index,
				"source_kind": _GemLocation.UNIT_SLOT,
			})
	return offer


static func has_pending_dropped_gem_reward(state: GameState) -> bool:
	return state != null \
		and not bool(state.battle_temp_flags.get(DROPPED_GEM_REWARD_HANDLED, false)) \
		and not dropped_gem_offer(state).is_empty()


static func embed_dropped_gem(state: GameState, gem_uid: String, slot_index: int) -> Dictionary:
	if state == null:
		return _failure("战斗状态不存在。")
	var player := state.get_player()
	if player == null:
		return _failure("玩家不存在。")
	var slot := player.get_slot_by_index(slot_index)
	if slot == null:
		return _failure("槽位不存在。")
	var gem: GemState = state.gems.get(gem_uid, null)
	var reward_entry := _find_reward_entry(state, gem_uid)
	if gem == null or reward_entry.is_empty():
		return _failure("掉落宝石不存在。")

	var source_snapshot := {
		"kind": gem.location.kind,
		"owner_uid": gem.location.owner_uid,
		"slot_index": gem.location.slot_index,
		"pos": reward_entry.get("pos", player.pos),
		"drop": state.dropped_gems.get(gem_uid, {}).duplicate(true),
	}
	var previous_held: GemState = state.gems.get(state.held_gem_uid, null)
	if previous_held != null:
		_GemTransfer.detach(state, previous_held)
	if not _GemTransfer.to_hand(state, gem, player.uid):
		_restore_hand(state, previous_held, player.uid)
		return _failure("无法持有掉落宝石。")

	var insert_result := _GemRules.insert(state, player, player, slot)
	if not bool(insert_result.get("ok", false)):
		_restore_reward_source(state, gem, source_snapshot, player.pos)
		_restore_hand(state, previous_held, player.uid)
		return _failure(str(insert_result.get("reason", "未知错误")))
	if bool(insert_result.get("overload_armed", false)):
		_restore_reward_source(state, gem, source_snapshot, player.pos)
		_restore_hand(state, previous_held, player.uid)
		_OverloadRules.record_insert(state, false)
		return _failure("再次选择该槽位可触发过载")
	_restore_hand(state, previous_held, player.uid, gem_uid)
	if bool(insert_result.get("overload_forced", false)):
		_OverloadRules.sync_active_mutations_to_overload_slots(state, true)
	state.battle_temp_flags[DROPPED_GEM_REWARD_HANDLED] = true
	_persist_dropped_gem_claim(state, "embedded", {
		"gem_id": gem.gem_id,
		"slot_index": slot_index,
	})
	return {
		"ok": true,
		"gem": gem,
		"slot_index": slot_index,
		"overload_forced": bool(insert_result.get("overload_forced", false)),
	}


static func _find_reward_entry(state: GameState, gem_uid: String) -> Dictionary:
	for entry: Dictionary in dropped_gem_offer(state):
		if str(entry.get("gem_uid", "")) == gem_uid:
			return entry
	return {}


static func _restore_reward_source(
	state: GameState,
	gem: GemState,
	source: Dictionary,
	fallback_pos: Vector2i
) -> void:
	if str(source.get("kind", "")) == _GemLocation.UNIT_SLOT:
		var unit: UnitState = state.units.get(str(source.get("owner_uid", "")), null)
		var slot := unit.get_slot_by_index(int(source.get("slot_index", -1))) if unit != null else null
		if slot != null and slot.gem_uid.is_empty() and _GemTransfer.to_unit_slot(state, gem, unit, slot):
			return
	var drop: Dictionary = source.get("drop", {})
	_GemTransfer.to_ground(state, gem, source.get("pos", fallback_pos), drop)


static func skip_dropped_gem_reward(state: GameState) -> void:
	if state != null:
		state.battle_temp_flags[DROPPED_GEM_REWARD_HANDLED] = true
		_persist_dropped_gem_claim(state, "skipped")


static func grant_combat_gold(room_id: String, room_type: String, enabled: bool = true) -> Dictionary:
	if not enabled or room_id.is_empty():
		return {"ok": false, "amount": 0, "reason": "not_applicable"}
	var economy := _service("EconomyService")
	if economy == null:
		return {"ok": false, "amount": 0, "reason": "economy_unavailable"}
	var reward := int(economy.get_combat_reward(room_type, room_id))
	var grant_result: Dictionary = economy.grant("gold", reward, "combat_reward", {
		"transaction_id": "%s:battle_gold" % room_id,
		"room_id": room_id,
		"room_type": room_type,
	})
	if not bool(grant_result.get("ok", false)):
		return {"ok": false, "amount": 0, "reason": grant_result.get("reason", "grant_failed")}
	var entry: Dictionary = grant_result.get("entry", {})
	return {
		"ok": not entry.is_empty(),
		"amount": int(entry.get("final_amount", reward)) if not entry.is_empty() else 0,
		"entry": entry,
	}


static func acquire_run_gem(gem_id: String) -> Dictionary:
	var run_service := _service("RunService")
	if run_service == null:
		return {"ok": false, "reason": "run_service_unavailable"}
	var game_service := _service("GameService")
	var adventure_service := _service("AdventureService")
	var room_id := str(game_service.pending_room_id) if game_service != null else ""
	var room_type := str(adventure_service.pending_room_type) if adventure_service != null else ""
	return run_service.claim_battle_gem(room_id, gem_id, room_type)


static func acquire_run_relic(relic_id: String, state: GameState = null) -> bool:
	var run_service := _service("RunService")
	if run_service == null or relic_id.is_empty():
		return false
	var game_service := _service("GameService")
	var adventure_service := _service("AdventureService")
	var room_id := str(game_service.pending_room_id) if game_service != null else ""
	var room_type := str(adventure_service.pending_room_type) if adventure_service != null else ""
	var result: Dictionary = run_service.claim_battle_relic(room_id, relic_id, room_type)
	if not bool(result.get("ok", false)):
		return false
	if state != null and not bool(result.get("duplicate", false)):
		var registry := _service("RelicEffectRegistry")
		if registry != null:
			registry.apply_acquired_relic(relic_id, "battle_start", state)
		run_service.capture_player_battle_state(state)
		run_service.save_run()
	return true


static func mark_reward_pending(
	encounter_id: String,
	reward_kind: String,
	battle_result: String,
	has_followup_relic: bool,
	room_id: String,
	room_type: String,
	state: GameState = null
) -> void:
	var run_service := _service("RunService")
	if run_service == null or not run_service.is_run_active():
		return
	run_service.set_run_phase("BATTLE_REWARD")
	var pending := {
		"type": "battle_reward",
		"room_id": room_id,
		"room_type": room_type,
		"encounter_id": encounter_id,
		"battle_result": battle_result,
		"reward_kind": reward_kind,
		"has_followup_relic": has_followup_relic,
	}
	if state != null:
		pending["dropped_gems"] = _serialize_dropped_offer(dropped_gem_offer(state))
	run_service.set_pending_decision(pending)


static func restore_pending_dropped_gems(state: GameState) -> void:
	if state == null or not state.dropped_gems.is_empty():
		return
	var run_service := _service("RunService")
	if run_service == null or not run_service.is_run_active():
		return
	var pending: Dictionary = run_service.get_pending_decision()
	var room_id := str(pending.get("room_id", ""))
	if room_id.is_empty() or run_service.has_room_transaction(room_id, "%s:battle_dropped_gem" % room_id):
		return
	var snapshots: Variant = pending.get("dropped_gems", [])
	if not snapshots is Array:
		return
	for i in range((snapshots as Array).size()):
		var raw: Variant = (snapshots as Array)[i]
		if not raw is Dictionary:
			continue
		var snapshot := raw as Dictionary
		var gem_id := str(snapshot.get("gem_id", ""))
		if gem_id.is_empty():
			continue
		var uid := "reward_drop_%s_%d" % [_safe_uid_part(room_id), i]
		if state.gems.has(uid):
			continue
		var gem := GemState.create(uid, gem_id, snapshot.get("def_overrides", {}))
		state.gems[uid] = gem
		var raw_pos: Variant = snapshot.get("pos", [0, 0])
		var pos := Vector2i(int(raw_pos[0]), int(raw_pos[1])) if raw_pos is Array and raw_pos.size() >= 2 else Vector2i.ZERO
		_GemTransfer.to_ground(state, gem, pos, {
			"source_unit_uid": str(snapshot.get("source_unit_uid", "")),
			"source_slot_type": str(snapshot.get("source_slot_type", "")),
		})


static func _serialize_dropped_offer(offer: Array[Dictionary]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for entry in offer:
		var pos: Vector2i = entry.get("pos", Vector2i.ZERO)
		snapshots.append({
			"gem_id": str(entry.get("gem_id", "")),
			"def_overrides": entry.get("def_overrides", {}).duplicate(true),
			"pos": [pos.x, pos.y],
			"source_unit_uid": str(entry.get("source_unit_uid", "")),
			"source_slot_type": str(entry.get("source_slot_type", "")),
		})
	return snapshots


static func _persist_dropped_gem_claim(state: GameState, outcome: String, details: Dictionary = {}) -> void:
	var run_service := _service("RunService")
	var game_service := _service("GameService")
	var adventure_service := _service("AdventureService")
	if run_service == null or game_service == null or not run_service.is_run_active():
		return
	var room_id := str(game_service.pending_room_id)
	if room_id.is_empty():
		return
	run_service.capture_player_battle_state(state)
	var result := details.duplicate(true)
	result["ok"] = true
	result["outcome"] = outcome
	result["reward_kind"] = "dropped_gem"
	result["room_type"] = str(adventure_service.pending_room_type) if adventure_service != null else ""
	run_service.append_room_transaction(room_id, "%s:battle_dropped_gem" % room_id, result)


static func _safe_uid_part(value: String) -> String:
	var result := ""
	for code in value.to_ascii_buffer():
		var lower_code: int = code + 32 if code >= 65 and code <= 90 else code
		result += String.chr(lower_code) if (lower_code >= 97 and lower_code <= 122) or (lower_code >= 48 and lower_code <= 57) or lower_code == 95 else "_"
	return result


static func _restore_hand(state: GameState, gem: GemState, holder_uid: String, except_uid: String = "") -> void:
	if gem != null and gem.uid != except_uid:
		_GemTransfer.to_hand(state, gem, holder_uid)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _service(name: String) -> Node:
	return Engine.get_main_loop().root.get_node_or_null(name)
