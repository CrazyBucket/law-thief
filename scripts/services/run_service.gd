extends Node

const RUN_SAVE_FILE_NAME := "run_save.json"
const RUN_SAVE_VERSION := 1
const RUN_SAVE_SCHEMA_VERSION := 1
const RUN_RULESET_VERSION := 1
const RUN_MIN_SUPPORTED_SCHEMA_VERSION := 1

var _run: RunState = null
var _progress_payload: Dictionary = {}


func _ready() -> void:
	reload_for_active_slot()


func start_run(master_seed: int, map_seed: int) -> void:
	_run = RunState.create(master_seed, map_seed)
	_progress_payload = {}
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


func acquire_gem(gem_id: String) -> void:
	if _run == null:
		push_warning("RunService.acquire_gem: no active run")
		return
	_run.carried_gem = {"gem_id": gem_id}
	save_run()
	DebugService.log_info("RunService: acquired gem %s" % gem_id)


func remove_relic(relic_id: String) -> void:
	if _run == null:
		return
	_run.remove_relic(relic_id)
	AchievementService.refresh_progress_flags()
	save_run()


func get_resolved_room(room_id: String) -> Dictionary:
	if _run == null:
		return {}
	var raw: Variant = _run.resolved_rooms.get(room_id, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func is_room_resolved(room_id: String) -> bool:
	if _run == null:
		return false
	return _run.resolved_rooms.has(room_id)


func get_player_run_snapshot() -> Dictionary:
	if _run == null:
		return {}
	var max_hp := _run.player_max_hp
	if max_hp <= 0:
		max_hp = int(DataRegistry.get_unit_def("unit_player").get("max_hp", 1))
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


func mark_room_resolved(room_id: String, payload: Dictionary) -> void:
	if _run == null:
		return
	_run.resolved_rooms[room_id] = payload.duplicate(true)
	save_run()


func heal_player_percent(ratio: float) -> Dictionary:
	if _run == null:
		return {}
	var max_hp := _run.player_max_hp
	if max_hp <= 0:
		max_hp = int(DataRegistry.get_unit_def("unit_player").get("max_hp", 1))
	var current_hp := _run.player_hp
	if current_hp < 0:
		current_hp = max_hp
	var amount := maxi(1, int(ceil(float(max_hp) * ratio)))
	var next_hp := mini(max_hp, current_hp + amount)
	var actual := maxi(0, next_hp - current_hp)
	_run.player_max_hp = max_hp
	_run.player_hp = next_hp
	save_run()
	return {
		"amount": actual,
		"after_hp": next_hp,
		"max_hp": max_hp,
	}


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


func get_or_roll_relic_offer(room_id: String, source: String, count: int = 3) -> Array[String]:
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
func get_or_roll_gem_offer(room_id: String, source: String, count: int = 3) -> Array[String]:
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



func save_run() -> void:
	if _run == null:
		return
	capture_player_battle_state()
	var slot_dir := ProjectSettings.globalize_path(SaveService.get_slot_dir())
	DirAccess.make_dir_recursive_absolute(slot_dir)
	var data := {
		"version": RUN_SAVE_VERSION,
		"save_schema_version": RUN_SAVE_SCHEMA_VERSION,
		"ruleset_version": RUN_RULESET_VERSION,
		"run": _run.export_dict(),
		"progress": _progress_payload,
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(SaveService.slot_file_path(RUN_SAVE_FILE_NAME), FileAccess.WRITE)
	if file == null:
		push_warning("RunService: cannot write active slot run save")
		return
	file.store_string(json_str)
	file.close()
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
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_invalidate_saved_run("进行中的这一局存档已损坏，已忽略。")
		push_warning("RunService: JSON parse error in active slot run save")
		return false
	var data: Variant = json.get_data()
	if not data is Dictionary:
		_invalidate_saved_run("进行中的这一局存档已损坏，已忽略。")
		return false
	var dict := data as Dictionary
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
		if slot == null or slot.gem_uid.is_empty():
			_run.player_slot_gems.append({})
			continue
		var gem: GemState = source_state.gems.get(slot.gem_uid, null)
		if gem == null:
			_run.player_slot_gems.append({})
			continue
		_run.player_slot_gems.append(_serialize_gem_snapshot(gem, slot.slot_type, slot.dual_type))
	_run.carried_gem = {}
	if not source_state.held_gem_uid.is_empty():
		var carried: GemState = source_state.gems.get(source_state.held_gem_uid, null)
		if carried != null:
			_run.carried_gem = _serialize_gem_snapshot(carried)


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


func _serialize_gem_snapshot(gem: GemState, slot_type: String = "", dual_type: String = "") -> Dictionary:
	return {
		"gem_id": gem.gem_id,
		"def_overrides": gem.def_overrides.duplicate(true),
		"slot_type": slot_type,
		"dual_type": dual_type,
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
