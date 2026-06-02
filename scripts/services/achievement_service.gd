extends Node

const _ACHIEVEMENTS := [
	{
		"id": "first_clear",
		"title": "初次破局",
		"desc": "完成任意一场遭遇战并获胜。",
		"target": 1,
	},
	{
		"id": "tutorial_master",
		"title": "教学毕业",
		"desc": "击败 tutorial_001。",
		"target": 1,
	},
	{
		"id": "route_runner",
		"title": "连战推进",
		"desc": "累计赢得 3 场遭遇战。",
		"target": 3,
	},
	{
		"id": "monster_manual",
		"title": "怪物档案员",
		"desc": "记录至少 4 种敌人。",
		"target": 4,
	},
	{
		"id": "relic_appraiser",
		"title": "遗物鉴定师",
		"desc": "见过至少 5 件遗物。",
		"target": 5,
	},
	{
		"id": "active_collector",
		"title": "现役收藏家",
		"desc": "单局持有 3 件遗物。",
		"target": 3,
	},
]

var _session_unlocked: Dictionary = {}


func notify_battle_win(encounter_id: String) -> void:
	_record("win_%s" % encounter_id)
	ProfileService.unlock_flag("boss_%s" % encounter_id)
	refresh_progress_flags()


func refresh_progress_flags() -> void:
	_sync_progress_flag("first_clear", RunHistoryService.get_total_wins(), 1)
	_sync_progress_flag("tutorial_master", RunHistoryService.get_encounter_win_count("tutorial_001"), 1)
	_sync_progress_flag("route_runner", RunHistoryService.get_total_wins(), 3)
	_sync_progress_flag("monster_manual", ProfileService.get_seen_enemy_ids().size(), 4)
	_sync_progress_flag("relic_appraiser", ProfileService.get_seen_relic_ids().size(), 5)
	_sync_progress_flag("active_collector", RunService.get_owned_relics().size(), 3)


func get_achievement_entries() -> Array[Dictionary]:
	refresh_progress_flags()
	var entries: Array[Dictionary] = []
	for definition in _ACHIEVEMENTS:
		var achievement_id := str(definition.get("id", ""))
		var progress := _progress_value(achievement_id)
		var target := int(definition.get("target", 1))
		var unlocked := progress >= target or ProfileService.is_flag_unlocked(_achievement_flag(achievement_id))
		entries.append({
			"id": achievement_id,
			"title": str(definition.get("title", achievement_id)),
			"desc": str(definition.get("desc", "")),
			"target": target,
			"progress": mini(progress, target),
			"progress_text": "%d / %d" % [mini(progress, target), target],
			"unlocked": unlocked,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("unlocked", false)) == bool(b.get("unlocked", false)):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return bool(a.get("unlocked", false)) and not bool(b.get("unlocked", false))
	)
	return entries


func get_all_achievement_flag_ids() -> Array[String]:
	var result: Array[String] = []
	for definition in _ACHIEVEMENTS:
		var achievement_id := str(definition.get("id", ""))
		if achievement_id.is_empty():
			continue
		result.append(_achievement_flag(achievement_id))
	return result


func get_summary() -> Dictionary:
	var entries := get_achievement_entries()
	var unlocked := 0
	for entry in entries:
		if bool(entry.get("unlocked", false)):
			unlocked += 1
	return {
		"unlocked": unlocked,
		"total": entries.size(),
	}


func is_unlocked(achievement_id: String) -> bool:
	return ProfileService.is_flag_unlocked(_achievement_flag(achievement_id)) or _session_unlocked.has(achievement_id)


func _record(achievement_id: String) -> void:
	if _session_unlocked.has(achievement_id):
		return
	_session_unlocked[achievement_id] = true
	DebugService.log_info("AchievementService: %s" % achievement_id)


func _sync_progress_flag(achievement_id: String, progress: int, target: int) -> void:
	if progress >= target:
		ProfileService.unlock_flag(_achievement_flag(achievement_id))


func _progress_value(achievement_id: String) -> int:
	match achievement_id:
		"first_clear":
			return RunHistoryService.get_total_wins()
		"tutorial_master":
			return RunHistoryService.get_encounter_win_count("tutorial_001")
		"route_runner":
			return RunHistoryService.get_total_wins()
		"monster_manual":
			return ProfileService.get_seen_enemy_ids().size()
		"relic_appraiser":
			return ProfileService.get_seen_relic_ids().size()
		"active_collector":
			return RunService.get_owned_relics().size()
	return 0


func _achievement_flag(achievement_id: String) -> String:
	return "achievement_%s" % achievement_id
