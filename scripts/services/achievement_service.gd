extends Node

## 成就触发入口
## 成就事实持久化统一委托给 ProfileService.unlock_flag

var _session_unlocked: Dictionary = {}


func notify_battle_win(encounter_id: String) -> void:
	_record("win_%s" % encounter_id)
	ProfileService.unlock_flag("boss_%s" % encounter_id)


## 记录本次会话内已触发的成就（内存级，不持久化）
func _record(achievement_id: String) -> void:
	if _session_unlocked.has(achievement_id):
		return
	_session_unlocked[achievement_id] = true
	DebugService.log_info("AchievementService: %s" % achievement_id)


## 检查本次会话是否触发过某成就
func is_unlocked(achievement_id: String) -> bool:
	return _session_unlocked.has(achievement_id) or ProfileService.is_flag_unlocked(achievement_id)
