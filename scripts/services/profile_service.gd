extends Node

## 局外永久存档：解锁 flags、图鉴、成就事实
## flag 命名约定（消费方按 prefix 过滤）：
##   "boss_<encounter_id>"       击败 Boss
##   "class_<class_id>"          职业解锁
##   "gem_unlocked_<gem_id>"     宝石解锁
##   "enemy_seen_<unit_def_id>"  怪物首次遭遇
##   "enemy_killed_<unit_def_id>"怪物首次击杀
##   "seen_relic_<relic_id>"     遗物首次见过（图鉴）
##   "achievement_<id>"          成就

const PROFILE_PATH := "user://profile.json"
const PROFILE_VERSION := 1

var _flags: Dictionary = {}   # flag_str → true
var _dirty: bool = false


func _ready() -> void:
	load_profile()


# ─── Flag 操作 ────────────────────────────────────────────────────────────────

func unlock_flag(flag: String) -> void:
	if _flags.has(flag):
		return
	_flags[flag] = true
	_dirty = true
	DebugService.log_info("ProfileService: unlock_flag %s" % flag)
	save_profile()


func is_flag_unlocked(flag: String) -> bool:
	return _flags.has(flag)


## 返回所有已解锁 flag 字符串列表（供 DataRegistry 池筛选使用）
func get_unlock_flags() -> Array[String]:
	var result: Array[String] = []
	for key in _flags.keys():
		result.append(str(key))
	return result


## 返回指定 prefix 开头的所有 flag（如 "boss_" 得到所有击败 Boss 记录）
func get_flags_with_prefix(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for key in _flags.keys():
		if str(key).begins_with(prefix):
			result.append(str(key))
	return result


# ─── 图鉴便捷接口 ──────────────────────────────────────────────────────────────

func mark_seen_relic(relic_id: String) -> void:
	unlock_flag("seen_relic_%s" % relic_id)


func has_seen_relic(relic_id: String) -> bool:
	return is_flag_unlocked("seen_relic_%s" % relic_id)


func mark_enemy_seen(unit_def_id: String) -> void:
	unlock_flag("enemy_seen_%s" % unit_def_id)


func mark_enemy_killed(unit_def_id: String) -> void:
	unlock_flag("enemy_killed_%s" % unit_def_id)


# ─── 存读档 ──────────────────────────────────────────────────────────────────

func save_profile() -> void:
	var data := {
		"version": PROFILE_VERSION,
		"flags": _flags.keys(),
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("ProfileService: cannot write %s" % PROFILE_PATH)
		return
	file.store_string(json_str)
	file.close()
	_dirty = false


func load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		push_warning("ProfileService: cannot read %s" % PROFILE_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("ProfileService: JSON parse error in %s" % PROFILE_PATH)
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return
	_flags.clear()
	var raw_flags: Variant = (data as Dictionary).get("flags", [])
	if raw_flags is Array:
		for flag in raw_flags:
			_flags[str(flag)] = true
	DebugService.log_info("ProfileService: loaded %d flags" % _flags.size())
