extends Node

## 单局运行状态管理
## 持有当前 RunState，负责遗物获取、奖励候选快照、存读档、权重上下文构建

const RUN_SAVE_PATH := "user://run_save.json"
const RUN_SAVE_VERSION := 1

var _run: RunState = null


func _ready() -> void:
	pass


# ─── 局的生命周期 ─────────────────────────────────────────────────────────────

func start_run(master_seed: int, map_seed: int) -> void:
	_run = RunState.create(master_seed, map_seed)
	RngService.start_run(master_seed)
	DebugService.log_info("RunService: new run master_seed=%d map_seed=%d" % [master_seed, map_seed])


func end_run() -> void:
	_clear_run_save()
	_run = null


func is_run_active() -> bool:
	return _run != null


func get_run() -> RunState:
	return _run


# ─── 遗物持有 ────────────────────────────────────────────────────────────────

func acquire_relic(relic_id: String) -> void:
	if _run == null:
		push_warning("RunService.acquire_relic: no active run")
		return
	_run.add_relic(relic_id)
	ProfileService.mark_seen_relic(relic_id)
	save_run()
	DebugService.log_info("RunService: acquired %s" % relic_id)


func remove_relic(relic_id: String) -> void:
	if _run == null:
		return
	_run.remove_relic(relic_id)
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


# ─── 奖励候选快照（SL 安全）────────────────────────────────────────────────────

## 获取已锁定的候选快照；若无则 roll 并锁定
## source: "normal_chest" / "elite_combat" / "large_chest" / "shop"
func get_or_roll_relic_offer(
	room_id: String,
	source: String,
	count: int = 3
) -> Array[String]:
	if _run == null:
		return []
	var snapshot := _run.get_offer_snapshot(room_id)
	if not snapshot.is_empty():
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
	save_run()
	return offer


# ─── 动态权重上下文构建 ────────────────────────────────────────────────────────

## 从当前 RunState 拼出 DataRegistry.roll_relic_* 所需的 weight_ctx
## state: 可选传入当前 GameState（获取精确槽位信息）
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


# ─── 存读档 ──────────────────────────────────────────────────────────────────

func save_run() -> void:
	if _run == null:
		return
	var data := {
		"version": RUN_SAVE_VERSION,
		"run": _run.export_dict(),
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("RunService: cannot write %s" % RUN_SAVE_PATH)
		return
	file.store_string(json_str)
	file.close()


func load_run() -> bool:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return false
	var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("RunService: JSON parse error in %s" % RUN_SAVE_PATH)
		return false
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return false
	var run_raw: Variant = (data as Dictionary).get("run", null)
	if not run_raw is Dictionary:
		return false
	_run = RunState.from_dict(run_raw as Dictionary)
	RngService.start_run(_run.master_seed)
	DebugService.log_info("RunService: restored run master_seed=%d" % _run.master_seed)
	return true


func has_saved_run() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)


func _clear_run_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)


# ─── 内部工具 ─────────────────────────────────────────────────────────────────

func _slot_color(slot_type: String) -> String:
	match slot_type:
		"red":   return "red"
		"blue":  return "blue"
		"black": return "black"
	return ""
