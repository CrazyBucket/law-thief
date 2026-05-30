extends Node

const RUN_SAVE_FILE_NAME := "run_save.json"
const RUN_SAVE_VERSION := 1

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


func is_run_active() -> bool:
	return _run != null


func get_run() -> RunState:
	return _run


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


func remove_relic(relic_id: String) -> void:
	if _run == null:
		return
	_run.remove_relic(relic_id)
	AchievementService.refresh_progress_flags()
	save_run()


func has_relic(relic_id: String) -> bool:
	return _run != null and _run.has_relic(relic_id)


func get_owned_relics() -> Array[String]:
	if _run == null:
		return []
	return _run.owned_relics.duplicate()


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


func get_weight_ctx(state: GameState = null) -> Dictionary:
	if _run == null:
		return {}
	var owned_gem_ids: Array[String] = []
	var gem_colors: Array[String] = []
	var total_slots: int = 0
	var empty_slots: int = 0
	if state != null:
		var player := state.get_player()
		if player != null:
			total_slots = player.slots.size()
			for slot in player.slots:
				if slot.gem_uid.is_empty():
					empty_slots += 1
				else:
					var gem: GemState = state.gems.get(slot.gem_uid, null)
					if gem != null and not gem.gem_id.is_empty():
						owned_gem_ids.append(gem.gem_id)
						var color := _slot_color(slot.slot_type)
						if not color.is_empty() and not color in gem_colors:
							gem_colors.append(color)
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
	var slot_dir := ProjectSettings.globalize_path(SaveService.get_slot_dir())
	DirAccess.make_dir_recursive_absolute(slot_dir)
	var data := {
		"version": RUN_SAVE_VERSION,
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
		"owned_relic_count": _run.owned_relics.size(),
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
		push_warning("RunService: JSON parse error in active slot run save")
		return false
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return false
	var dict := data as Dictionary
	var run_raw: Variant = dict.get("run", null)
	if not run_raw is Dictionary:
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


func _clear_run_save() -> void:
	var path := ProjectSettings.globalize_path(SaveService.slot_file_path(RUN_SAVE_FILE_NAME))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _clear_loaded_state() -> void:
	_run = null
	_progress_payload = {}


func _slot_color(slot_type: String) -> String:
	match slot_type:
		"red":
			return "red"
		"blue":
			return "blue"
		"black":
			return "black"
	return ""
