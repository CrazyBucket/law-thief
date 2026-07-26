class_name RunPlayerGemService
extends RefCounted

const PLAYER_UNIT_DEFS_PATH := "res://resources/units/unit_defs.json"

static var _base_slots_cache: Array = []


static func slot_snapshots(run: RunState) -> Array:
	if run == null:
		return []
	_ensure_slot_snapshots(run)
	return run.player_slot_gems.duplicate(true)


static func embed_options(run: RunState) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if run == null or run.carried_gem.is_empty():
		return options
	var slots := slot_snapshots(run)
	for index in range(slots.size()):
		var raw_slot: Variant = slots[index]
		if not raw_slot is Dictionary:
			continue
		var slot := raw_slot as Dictionary
		var gem_id := str(slot.get("gem_id", ""))
		var lock_type := str(slot.get("lock_type", ""))
		if gem_id.is_empty() and not lock_type.is_empty():
			continue
		if lock_type == Constants.LOCK_SPLIT_DISABLED:
			continue
		options.append({
			"index": index,
			"slot": slot.duplicate(true),
			"overload": not gem_id.is_empty(),
		})
	return options


static func embed_carried_gem(run: RunState, slot_index: int, force_overload: bool = false) -> Dictionary:
	if run == null:
		return {"ok": false, "error": "no_active_run"}
	if run.carried_gem.is_empty():
		return {"ok": false, "error": "no_carried_gem"}
	_ensure_slot_snapshots(run)
	if slot_index < 0 or slot_index >= run.player_slot_gems.size():
		return {"ok": false, "error": "slot_not_found"}
	var target: Variant = run.player_slot_gems[slot_index]
	if not target is Dictionary:
		return {"ok": false, "error": "slot_not_found"}
	var slot_snapshot := (target as Dictionary).duplicate(true)
	var occupied := not str(slot_snapshot.get("gem_id", "")).is_empty()
	var lock_type := str(slot_snapshot.get("lock_type", ""))
	if lock_type == Constants.LOCK_SPLIT_DISABLED:
		return {"ok": false, "error": "slot_unavailable"}
	if occupied and not force_overload:
		return {"ok": false, "error": "overload_required"}
	if not occupied and not lock_type.is_empty():
		return {"ok": false, "error": "slot_unavailable"}
	var embedded := run.carried_gem.duplicate(true)
	embedded["slot_type"] = str(slot_snapshot.get("slot_type", ""))
	embedded["dual_type"] = str(slot_snapshot.get("dual_type", ""))
	if occupied:
		embedded["lock_type"] = Constants.LOCK_OVERLOAD_SLOT
		embedded["overload_slot"] = true
		run.player_slot_gems.append(embedded)
	else:
		embedded["lock_type"] = lock_type
		embedded["overload_slot"] = bool(
			slot_snapshot.get("overload_slot", lock_type == Constants.LOCK_OVERLOAD_SLOT)
		)
		run.player_slot_gems[slot_index] = embedded
	run.carried_gem = {}
	return {
		"ok": true,
		"slot_index": run.player_slot_gems.size() - 1 if occupied else slot_index,
		"source_slot_index": slot_index,
		"gem_id": str(embedded.get("gem_id", "")),
		"overload_forced": occupied,
	}


static func _ensure_slot_snapshots(run: RunState) -> void:
	if not run.player_slot_gems.is_empty():
		return
	for raw_slot in _base_player_slots():
		if raw_slot is Dictionary:
			var slot: Dictionary = raw_slot
			var lock_type := str(slot.get("lock_type", ""))
			run.player_slot_gems.append({
				"slot_type": str(slot.get("slot_type", Constants.SLOT_RED)),
				"dual_type": str(slot.get("dual_type", "")),
				"lock_type": lock_type,
				"overload_slot": bool(slot.get("overload_slot", lock_type == Constants.LOCK_OVERLOAD_SLOT)),
			})
	for extra in run.extra_slots:
		if extra is Dictionary:
			run.player_slot_gems.append({"slot_type": str((extra as Dictionary).get("slot_type", Constants.SLOT_RED))})
	for upgrade in run.upgraded_slots:
		if not upgrade is Dictionary:
			continue
		for i in range(run.player_slot_gems.size()):
			var raw_slot: Variant = run.player_slot_gems[i]
			if raw_slot is Dictionary and str((raw_slot as Dictionary).get("slot_type", "")) == str((upgrade as Dictionary).get("from_type", "")) and str((raw_slot as Dictionary).get("dual_type", "")).is_empty():
				var snapshot := (raw_slot as Dictionary).duplicate(true)
				snapshot["dual_type"] = str((upgrade as Dictionary).get("to_dual_type", ""))
				run.player_slot_gems[i] = snapshot
				break


static func _base_player_slots() -> Array:
	if not _base_slots_cache.is_empty():
		return _base_slots_cache
	var file := FileAccess.open(PLAYER_UNIT_DEFS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return []
	var player_def: Variant = (parsed as Dictionary).get("unit_player", {})
	if not player_def is Dictionary:
		return []
	var slots: Variant = (player_def as Dictionary).get("slots", [])
	if slots is Array:
		_base_slots_cache = (slots as Array).duplicate(true)
	return _base_slots_cache
