extends Node
const RUN_SAVE_FILE_NAME := "run_save.json"
const RUN_SAVE_VERSION := 1
const RUN_SAVE_SCHEMA_VERSION := 2
const RUN_RULESET_VERSION := 2
const RUN_MIN_SUPPORTED_SCHEMA_VERSION := 1
const RunPlayerHealth = preload("res://scripts/services/run_player_health.gd")
const RunRecordBuilder = preload("res://scripts/services/run_record_builder.gd")
var _run: RunState = null
var _progress_payload: Dictionary = {}
var _persistence_suspended: bool = false

func _ready() -> void:
	reload_for_active_slot()

func start_run(master_seed: int, map_seed: int) -> void:
	_persistence_suspended = false
	_run = RunState.create(master_seed, map_seed)
	_progress_payload = {}
	_run.run_phase = "MAP"
	_run.pending_decision = {}
	var economy_service: Node = get_node_or_null("/root/EconomyService")
	if economy_service != null and economy_service.has_method("get_starting_gold"):
		_run.resources["gold"] = int(economy_service.call("get_starting_gold"))
	RngService.start_run(master_seed)
	DebugService.log_info("RunService: new run master_seed=%d map_seed=%d" % [master_seed, map_seed])
	save_run()
func end_run() -> void:
	_clear_run_save()
	_run = null
	_progress_payload = {}
	SaveService.touch_active_slot({
		"has_run": false,
		"run_invalid_reason": "",
	})

func is_run_active() -> bool:
	return _run != null

func get_run() -> RunState:
	return _run

func snapshot_active_run() -> Dictionary:
	if _run == null:
		return {"active": false}
	return {
		"active": true,
		"run": _run.export_dict(),
		"progress_payload": _progress_payload.duplicate(true),
	}

## Creates an in-memory run for an editor session. Its mutations must never
## replace the player's saved run; restore_run_snapshot() ends this scope.
func begin_temporary_run(master_seed: int = 1, map_seed: int = 1) -> void:
	_run = RunState.create(master_seed, map_seed)
	_progress_payload = {}
	_run.run_phase = "MAP"
	_run.pending_decision = {}
	_persistence_suspended = true
	RngService.start_run(master_seed)

func restore_run_snapshot(snapshot: Dictionary) -> void:
	_persistence_suspended = false
	if not bool(snapshot.get("active", false)):
		_clear_run_save()
		_run = null
		_progress_payload = {}
		SaveService.touch_active_slot({
			"has_run": false,
			"run_invalid_reason": "",
		})
		return
	var raw_run: Variant = snapshot.get("run", {})
	if not raw_run is Dictionary:
		return
	_run = RunState.from_dict(raw_run as Dictionary)
	var raw_progress: Variant = snapshot.get("progress_payload", {})
	_progress_payload = (raw_progress as Dictionary).duplicate(true) if raw_progress is Dictionary else {}
	save_run(false)

func get_current_chapter() -> int:
	if _run == null:
		return 1
	return maxi(1, _run.current_chapter)

func get_progress_payload() -> Dictionary:
	return _progress_payload.duplicate(true)

func set_progress_payload(progress: Dictionary) -> void:
	_progress_payload = progress.duplicate(true)
	if _run != null:
		save_run()

func acquire_relic(relic_id: String) -> void:
	if _run == null:
		push_warning("RunService.acquire_relic: no active run")
		return
	_run.add_relic(relic_id)
	ProfileService.mark_seen_relic(relic_id)
	AchievementService.refresh_progress_flags()
	save_run()
	DebugService.log_info("RunService: acquired %s" % relic_id)


func acquire_gem(gem_id: String) -> Dictionary:
	if _run == null:
		push_warning("RunService.acquire_gem: no active run")
		return {"ok": false, "error": "no_active_run"}
	if gem_id.is_empty():
		return {"ok": false, "error": "empty_gem_id"}
	if not _run.carried_gem.is_empty():
		return {
			"ok": false,
			"error": "carried_gem_occupied",
			"carried_gem_id": str(_run.carried_gem.get("gem_id", "")),
		}
	_run.carried_gem = {"gem_id": gem_id}
	save_run()
	DebugService.log_info("RunService: acquired gem %s" % gem_id)
	return {
		"ok": true,
		"gem_id": gem_id,
	}


func remove_relic(relic_id: String) -> void:
	if _run == null:
		return
	_run.remove_relic(relic_id)
	AchievementService.refresh_progress_flags()
	save_run()


func get_resolved_room(room_id: String) -> Dictionary:
	if _run == null:
		return {}
	var raw: Variant = _run.resolved_rooms.get(room_id, _run.resolved_rooms.get(_legacy_room_id(room_id), {}))
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	var room_state := get_room_state(room_id)
	if not room_state.is_empty():
		var result: Variant = room_state.get("result", {})
		if result is Dictionary:
			return (result as Dictionary).duplicate(true)
	return {}


func is_room_resolved(room_id: String) -> bool:
	if _run == null:
		return false
	if _run.resolved_rooms.has(room_id) or _run.resolved_rooms.has(_legacy_room_id(room_id)):
		return true
	var room_state := get_room_state(room_id)
	return str(room_state.get("status", "")) == "RESOLVED"


func get_room_state(room_id: String) -> Dictionary:
	if _run == null:
		return {}
	var raw: Variant = _run.room_states.get(room_id, _run.room_states.get(_legacy_room_id(room_id), {}))
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func ensure_room_state(room_id: String, room_type: String) -> Dictionary:
	if _run == null:
		return {}
	var room_state := get_room_state(room_id)
	if room_state.is_empty():
		room_state = {
			"status": "UNENTERED",
			"room_type": room_type,
			"snapshot": {},
			"transactions": [],
			"result": {},
		}
	else:
		room_state["room_type"] = room_type if str(room_state.get("room_type", "")).is_empty() else room_state.get("room_type", room_type)
	set_room_state(room_id, room_state, false)
	return room_state


func set_room_state(room_id: String, room_state: Dictionary, persist: bool = true) -> void:
	if _run == null:
		return
	_run.room_states[room_id] = room_state.duplicate(true)
	if persist:
		save_run()


func get_player_run_snapshot() -> Dictionary:
	if _run == null:
		return {}
	var max_hp := _run.player_max_hp
	if max_hp <= 0:
		max_hp = int(DataRegistry.get_unit_def("unit_player")["max_hp"])
	var hp := _run.player_hp
	if hp < 0:
		hp = max_hp
	var carried_gem_id := str(_run.carried_gem.get("gem_id", ""))
	var carried_gem_name := ""
	if not carried_gem_id.is_empty():
		carried_gem_name = DataRegistry.get_gem_display_name(carried_gem_id)
	return {
		"hp": hp,
		"max_hp": max_hp,
		"owned_relic_count": _run.owned_relics.size(),
		"carried_gem_id": carried_gem_id,
		"carried_gem_name": carried_gem_name,
	}


func _player_default_max_hp() -> int:
	return int(DataRegistry.get_unit_def("unit_player")["max_hp"])


func mark_room_resolved(room_id: String, payload: Dictionary) -> void:
	if _run == null:
		return
	var existing_state := get_room_state(room_id)
	var snapshot := {}
	var transactions: Array = []
	if not existing_state.is_empty():
		var raw_snapshot: Variant = existing_state.get("snapshot", {})
		if raw_snapshot is Dictionary:
			snapshot = (raw_snapshot as Dictionary).duplicate(true)
		var raw_transactions: Variant = existing_state.get("transactions", [])
		if raw_transactions is Array:
			transactions = (raw_transactions as Array).duplicate(true)
	_run.resolved_rooms[room_id] = payload.duplicate(true)
	_run.room_states[room_id] = {
		"status": "RESOLVED",
		"room_type": str(payload.get("room_type", "")),
		"snapshot": snapshot,
		"transactions": transactions,
		"result": payload.duplicate(true),
	}
	save_run()


func append_room_transaction(room_id: String, transaction_id: String, result: Dictionary) -> void:
	if _run == null:
		return
	var room_state := ensure_room_state(room_id, str(result.get("room_type", "")))
	var transactions: Array = room_state.get("transactions", []).duplicate(true) if room_state.get("transactions", []) is Array else []
	for raw_tx in transactions:
		if raw_tx is Dictionary and str(raw_tx.get("transaction_id", "")) == transaction_id:
			return
	transactions.append({
		"transaction_id": transaction_id,
		"result": result.duplicate(true),
	})
	room_state["transactions"] = transactions
	room_state["result"] = result.duplicate(true)
	set_room_state(room_id, room_state)


func get_room_transaction(room_id: String, transaction_id: String) -> Dictionary:
	var room_state := get_room_state(room_id)
	var transactions: Variant = room_state.get("transactions", [])
	if not transactions is Array:
		return {}
	for raw_tx in transactions:
		if raw_tx is Dictionary and str(raw_tx.get("transaction_id", "")) == transaction_id:
			var result: Variant = raw_tx.get("result", {})
			return (result as Dictionary).duplicate(true) if result is Dictionary else {}
	return {}


func has_room_transaction(room_id: String, transaction_id: String) -> bool:
	return not get_room_transaction(room_id, transaction_id).is_empty()


func claim_battle_relic(room_id: String, relic_id: String, room_type: String = "") -> Dictionary:
	if _run == null or room_id.is_empty() or relic_id.is_empty():
		return {"ok": false, "reason": "invalid_claim"}
	var transaction_id := "%s:battle_relic" % room_id
	var existing := get_room_transaction(room_id, transaction_id)
	if not existing.is_empty():
		existing["ok"] = true
		existing["duplicate"] = true
		return existing
	_run.add_relic(relic_id)
	ProfileService.mark_seen_relic(relic_id)
	AchievementService.refresh_progress_flags()
	var result := {
		"ok": true,
		"relic_id": relic_id,
		"reward_kind": "relic",
		"room_type": room_type,
	}
	append_room_transaction(room_id, transaction_id, result)
	DebugService.log_info("RunService: claimed battle relic %s" % relic_id)
	return result


func claim_battle_gem(room_id: String, gem_id: String, room_type: String = "") -> Dictionary:
	if _run == null or room_id.is_empty() or gem_id.is_empty():
		return {"ok": false, "reason": "invalid_claim"}
	var transaction_id := "%s:battle_gem" % room_id
	var existing := get_room_transaction(room_id, transaction_id)
	if not existing.is_empty():
		existing["ok"] = true
		existing["duplicate"] = true
		return existing
	if not _run.carried_gem.is_empty():
		return {
			"ok": false,
			"error": "carried_gem_occupied",
			"carried_gem_id": str(_run.carried_gem.get("gem_id", "")),
		}
	_run.carried_gem = {"gem_id": gem_id}
	var result := {
		"ok": true,
		"gem_id": gem_id,
		"reward_kind": "gem",
		"room_type": room_type,
	}
	append_room_transaction(room_id, transaction_id, result)
	DebugService.log_info("RunService: claimed battle gem %s" % gem_id)
	return result


func heal_player_percent(ratio: float) -> Dictionary:
	if _run == null:
		return {}
	var result := RunPlayerHealth.heal_percent(_run, ratio, _player_default_max_hp())
	save_run()
	return result


func heal_player_amount(amount: int) -> Dictionary:
	if _run == null:
		return {}
	var result := RunPlayerHealth.heal_amount(_run, amount, _player_default_max_hp())
	save_run()
	return result


func damage_player_amount(amount: int) -> Dictionary:
	if _run == null:
		return {}
	var result := RunPlayerHealth.damage_amount(_run, amount, _player_default_max_hp())
	save_run()
	return result


func get_balance(resource_id: String = "gold") -> int:
	if _run == null:
		return 0
	return int(_run.resources.get(resource_id, 0))


func set_resource_balance(resource_id: String, amount: int, persist: bool = true) -> void:
	if _run == null:
		return
	_run.resources[resource_id] = amount
	if persist:
		save_run()


func get_resource_ledger() -> Array:
	if _run == null:
		return []
	return _run.resource_ledger.duplicate(true)


func append_ledger_entry(entry: Dictionary) -> void:
	if _run == null:
		return
	_run.resource_ledger.append(entry.duplicate(true))
	save_run()


func get_adventure_rules() -> Array:
	if _run == null:
		return []
	return _run.adventure_rules.duplicate(true)


func append_adventure_rule(rule: Dictionary) -> void:
	if _run == null:
		return
	_run.adventure_rules.append(rule.duplicate(true))
	save_run()


func remove_adventure_rule(rule_id: String, scope_filter: String = "") -> bool:
	if _run == null:
		return false
	for i in range(_run.adventure_rules.size()):
		var raw_rule: Variant = _run.adventure_rules[i]
		if not raw_rule is Dictionary:
			continue
		var rule := raw_rule as Dictionary
		if str(rule.get("rule_id", "")) != rule_id:
			continue
		if not scope_filter.is_empty() and str(rule.get("scope", "")) != scope_filter:
			continue
		_run.adventure_rules.remove_at(i)
		save_run()
		return true
	return false


func get_run_phase() -> String:
	if _run == null:
		return "MAP"
	return str(_run.run_phase)


func set_run_phase(phase: String) -> void:
	if _run == null:
		return
	_run.run_phase = phase
	save_run()


func get_pending_decision() -> Dictionary:
	if _run == null:
		return {}
	return _run.pending_decision.duplicate(true)


func set_pending_decision(decision: Dictionary) -> void:
	if _run == null:
		return
	_run.pending_decision = decision.duplicate(true)
	save_run()


func clear_pending_decision() -> void:
	if _run == null:
		return
	_run.pending_decision = {}
	save_run()


func complete_run(result: String) -> void:
	if _run == null:
		return
	RunHistoryService.record_run(build_run_record(result))


func build_run_record(result: String) -> Dictionary:
	return RunRecordBuilder.build(_run, result, int(Time.get_unix_time_from_system()))


func get_save_compat_meta() -> Dictionary:
	return {
		"save_schema_version": RUN_SAVE_SCHEMA_VERSION,
		"ruleset_version": RUN_RULESET_VERSION,
	}


func has_relic(relic_id: String) -> bool:
	return _run != null and _run.has_relic(relic_id)


func get_owned_relics() -> Array[String]:
	if _run == null:
		return []
	var result: Array[String] = []
	for relic_id in _run.owned_relics:
		result.append(str(relic_id))
	return result


func get_relic_runtime(relic_id: String) -> RelicRuntimeState:
	if _run == null:
		return null
	return _run.get_runtime(relic_id)


func get_or_roll_relic_offer(room_id: String, source: String, count: int) -> Array[String]:
	if _run == null:
		return []
	var snapshot := _run.get_offer_snapshot(room_id)
	if not snapshot.is_empty():
		for relic_id in snapshot:
			ProfileService.mark_seen_relic(relic_id)
		return snapshot
	var offer: Array[String] = DataRegistry.roll_relic_offer(
		"relic_offer_%s" % room_id,
		source,
		count,
		_run.owned_relics,
		ProfileService.get_unlock_flags(),
		get_weight_ctx()
	)
	_run.snapshot_offer(room_id, offer)
	for relic_id in offer:
		ProfileService.mark_seen_relic(relic_id)
	save_run()
	return offer


## 按房间来源抽宝石奖励，结果锁定快照保证 SL 安全（key 前缀 "gem_offer_"）
## source:  pool key（"normal_chest" / "elite_combat" / "boss_reward"）
## count:   奖励数量
func get_or_roll_gem_offer(room_id: String, source: String, count: int) -> Array[String]:
	if _run == null:
		return []
	var snapshot_key := "gem_offer_%s" % room_id
	var snapshot := _run.get_offer_snapshot(snapshot_key)
	if not snapshot.is_empty():
		return snapshot
	var chapter := get_current_chapter()
	var offer: Array[String] = DataRegistry.roll_gem_offer(
		"gem_offer_%s" % room_id,
		source,
		count,
		chapter
	)
	_run.snapshot_offer(snapshot_key, offer)
	save_run()
	return offer


func get_weight_ctx(state: GameState = null) -> Dictionary:
	if _run == null:
		return {}
	var owned_gem_ids: Array[String] = []
	var gem_colors: Array[String] = []
	var total_slots: int = 0
	var empty_slots: int = 0
	if state != null:
		_collect_weight_ctx_from_state(state, owned_gem_ids, gem_colors)
		var player := state.get_player()
		if player != null:
			total_slots = player.slots.size()
			for slot in player.slots:
				if slot.gem_uid.is_empty():
					empty_slots += 1
	else:
		total_slots = _run.player_slot_gems.size()
		for raw_slot in _run.player_slot_gems:
			if raw_slot is Dictionary and not (raw_slot as Dictionary).is_empty():
				var gem_id := str((raw_slot as Dictionary).get("gem_id", ""))
				if not gem_id.is_empty():
					owned_gem_ids.append(gem_id)
					var color := str((raw_slot as Dictionary).get("slot_type", ""))
					if not color.is_empty() and not color in gem_colors:
						gem_colors.append(color)
			else:
				empty_slots += 1
		var carried_gem_id := str(_run.carried_gem.get("gem_id", ""))
		if not carried_gem_id.is_empty():
			owned_gem_ids.append(carried_gem_id)
	return {
		"owned_gems": owned_gem_ids,
		"owned_relics": _run.owned_relics.duplicate(),
		"gem_colors": gem_colors,
		"total_slots": total_slots,
		"empty_slots": empty_slots,
	}



func save_run(capture_battle_state: bool = true) -> void:
	if _run == null or _persistence_suspended:
		return
	if capture_battle_state:
		capture_player_battle_state()
	var data := {
		"version": RUN_SAVE_VERSION,
		"save_schema_version": RUN_SAVE_SCHEMA_VERSION,
		"ruleset_version": RUN_RULESET_VERSION,
		"run": _run.export_dict(),
		"progress": _progress_payload,
	}
	if not SaveService.write_json_atomic(SaveService.slot_file_path(RUN_SAVE_FILE_NAME), data):
		push_warning("RunService: cannot write active slot run save")
		return
	SaveService.touch_active_slot({
		"has_run": true,
		"map_seed": _run.map_seed,
		"current_chapter": _run.current_chapter,
		"owned_relic_count": _run.owned_relics.size(),
		"run_invalid_reason": "",
	})


func load_run() -> bool:
	_clear_loaded_state()
	var path := SaveService.slot_file_path(RUN_SAVE_FILE_NAME)
	var dict := SaveService.read_json_file(path)
	if dict.is_empty():
		if FileAccess.file_exists(path):
			_invalidate_saved_run("进行中的这一局存档已损坏，已忽略。")
			push_warning("RunService: JSON parse error in active slot run save")
		return false
	var compat := inspect_run_save_compat(dict)
	if not compat.get("ok", false):
		_invalidate_saved_run(str(compat.get("reason", "进行中的这一局已不兼容。")))
		return false
	var run_raw: Variant = dict.get("run", null)
	if not run_raw is Dictionary:
		_invalidate_saved_run("进行中的这一局存档缺少核心数据，已忽略。")
		return false
	_run = RunState.from_dict(run_raw as Dictionary)
	var raw_progress: Variant = dict.get("progress", {})
	if raw_progress is Dictionary:
		_progress_payload = (raw_progress as Dictionary).duplicate(true)
	RngService.start_run(_run.master_seed)
	AchievementService.refresh_progress_flags()
	DebugService.log_info("RunService: restored run master_seed=%d" % _run.master_seed)
	return true


func has_saved_run() -> bool:
	return FileAccess.file_exists(SaveService.slot_file_path(RUN_SAVE_FILE_NAME))


func reload_for_active_slot() -> void:
	load_run()


func inspect_run_save_compat(data: Dictionary) -> Dictionary:
	var save_schema_version := int(data.get("save_schema_version", int(data.get("version", RUN_SAVE_SCHEMA_VERSION))))
	var ruleset_version := int(data.get("ruleset_version", RUN_RULESET_VERSION))
	if save_schema_version > RUN_SAVE_SCHEMA_VERSION:
		return {
			"ok": false,
			"reason": "该局来自更新的开发版本，当前代码无法继续。",
		}
	if save_schema_version < RUN_MIN_SUPPORTED_SCHEMA_VERSION:
		return {
			"ok": false,
			"reason": "该局来自过旧的开发版本，请重新开始这一局。",
		}
	if ruleset_version != RUN_RULESET_VERSION:
		return {
			"ok": false,
			"reason": "本地规则已更新，为避免开发期读档崩溃，请重新开始这一局。",
		}
	var run_raw: Variant = data.get("run", null)
	if not run_raw is Dictionary:
		return {
			"ok": false,
			"reason": "进行中的这一局存档缺少核心数据，已忽略。",
		}
	return {
		"ok": true,
		"save_schema_version": save_schema_version,
		"ruleset_version": ruleset_version,
	}


func _legacy_room_id(room_id: String) -> String:
	var idx := room_id.rfind(":")
	if idx >= 0:
		return room_id.substr(idx + 1)
	return room_id


func _invalidate_saved_run(reason: String) -> void:
	_clear_run_save()
	_clear_loaded_state()
	SaveService.touch_active_slot({
		"has_run": false,
		"run_invalid_reason": reason,
	})
	DebugService.log_info("RunService: invalidated run save - %s" % reason)


func _clear_run_save() -> void:
	var path := ProjectSettings.globalize_path(SaveService.slot_file_path(RUN_SAVE_FILE_NAME))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _clear_loaded_state() -> void:
	_run = null
	_progress_payload = {}


func capture_player_battle_state(state: GameState = null) -> void:
	if _run == null:
		return
	var source_state := state
	if source_state == null:
		source_state = _active_battle_state()
	if source_state == null:
		return
	var player := source_state.get_player()
	if player == null:
		return
	_run.player_hp = player.hp
	_run.player_max_hp = player.max_hp
	_run.player_slot_gems = []
	for slot in player.slots:
		if slot == null:
			_run.player_slot_gems.append({})
			continue
		if slot.gem_uid.is_empty():
			_run.player_slot_gems.append(_serialize_empty_slot_snapshot(slot))
			continue
		var gem: GemState = source_state.gems.get(slot.gem_uid, null)
		if gem == null:
			_run.player_slot_gems.append(_serialize_empty_slot_snapshot(slot))
			continue
		_run.player_slot_gems.append(_serialize_gem_snapshot(gem, slot.slot_type, slot.dual_type, slot.lock_type))
	_run.carried_gem = {}
	if not source_state.held_gem_uid.is_empty():
		var carried: GemState = source_state.gems.get(source_state.held_gem_uid, null)
		if carried != null:
			_run.carried_gem = _serialize_gem_snapshot(carried)
	_run.overload_active_mutations = source_state.overload_active_mutations.duplicate()


func _collect_weight_ctx_from_state(state: GameState, owned_gem_ids: Array[String], gem_colors: Array[String]) -> void:
	var player := state.get_player()
	if player != null:
		for slot in player.slots:
			if slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null and not gem.gem_id.is_empty():
				owned_gem_ids.append(gem.gem_id)
				var color := _slot_color(slot.slot_type)
				if not color.is_empty() and not color in gem_colors:
					gem_colors.append(color)
	if not state.held_gem_uid.is_empty():
		var held: GemState = state.gems.get(state.held_gem_uid, null)
		if held != null and not held.gem_id.is_empty():
			owned_gem_ids.append(held.gem_id)


func _serialize_gem_snapshot(gem: GemState, slot_type: String = "", dual_type: String = "", lock_type: String = "") -> Dictionary:
	return {
		"gem_id": gem.gem_id,
		"def_overrides": gem.def_overrides.duplicate(true),
		"slot_type": slot_type,
		"dual_type": dual_type,
		"lock_type": lock_type,
	}


func _serialize_empty_slot_snapshot(slot: SlotState) -> Dictionary:
	return {
		"slot_type": slot.slot_type,
		"dual_type": slot.dual_type,
		"lock_type": slot.lock_type,
	}


func _active_battle_state() -> GameState:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	if str(scene.scene_file_path) != "res://scenes/battle/battle_scene.tscn":
		return null
	var controller: Variant = scene.get("_controller")
	if controller != null and controller is BattleController:
		return controller.state
	return null


func _slot_color(slot_type: String) -> String:
	match slot_type:
		"red":
			return "red"
		"blue":
			return "blue"
		"black":
			return "black"
	return ""
