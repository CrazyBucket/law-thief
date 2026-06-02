class_name RunState
extends RefCounted

var master_seed: int = 0
var map_seed: int = 0
var current_chapter: int = 1
## relic_id 有序列表，顺序等于获取顺序
var owned_relics: Array[String] = []
## room_id → Array[String]：已锁定的奖励候选快照，SL 安全
var relic_offer_snapshots: Dictionary = {}
## relic_id → RelicRuntimeState
var relic_runtime: Dictionary = {}
## 玩家遗物赋予的持久额外槽位：Array of {"slot_type": String}
var extra_slots: Array = []
## 玩家遗物赋予的持久槽位升级：Array of {"from_type": String, "to_dual_type": String}
var upgraded_slots: Array = []
var player_hp: int = -1
var player_max_hp: int = -1
## 与玩家槽位顺序一一对应；空字典代表该槽当前没有宝石
var player_slot_gems: Array = []
## 跨战斗携带的手持宝石快照
var carried_gem: Dictionary = {}
## room_id -> 结算结果快照，避免房间奖励在重进时重复结算
var resolved_rooms: Dictionary = {}


static func create(master_seed: int, map_seed: int) -> RunState:
	var s := RunState.new()
	s.master_seed = master_seed
	s.map_seed = map_seed
	return s


func has_relic(relic_id: String) -> bool:
	return relic_id in owned_relics


func get_runtime(relic_id: String) -> RelicRuntimeState:
	return relic_runtime.get(relic_id, null)


func add_relic(relic_id: String) -> void:
	if relic_id in owned_relics:
		return
	owned_relics.append(relic_id)
	relic_runtime[relic_id] = RelicRuntimeState.create(relic_id)


func remove_relic(relic_id: String) -> void:
	owned_relics.erase(relic_id)
	relic_runtime.erase(relic_id)


func snapshot_offer(room_id: String, offer: Array[String]) -> void:
	relic_offer_snapshots[room_id] = offer.duplicate()


func get_offer_snapshot(room_id: String) -> Array[String]:
	var raw: Variant = relic_offer_snapshots.get(room_id, null)
	if raw == null:
		return []
	var result: Array[String] = []
	for item in raw:
		result.append(str(item))
	return result


func add_extra_slot(slot_type: String) -> void:
	extra_slots.append({"slot_type": slot_type})


func add_slot_upgrade(from_type: String, to_dual_type: String) -> void:
	upgraded_slots.append({"from_type": from_type, "to_dual_type": to_dual_type})


func export_dict() -> Dictionary:
	var runtime_raw: Dictionary = {}
	for rid in relic_runtime.keys():
		var rs: RelicRuntimeState = relic_runtime[rid]
		runtime_raw[rid] = rs.export_dict()
	return {
		"master_seed": master_seed,
		"map_seed": map_seed,
		"current_chapter": current_chapter,
		"owned_relics": owned_relics.duplicate(),
		"relic_offer_snapshots": relic_offer_snapshots.duplicate(true),
		"relic_runtime": runtime_raw,
		"extra_slots": extra_slots.duplicate(true),
		"upgraded_slots": upgraded_slots.duplicate(true),
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"player_slot_gems": player_slot_gems.duplicate(true),
		"carried_gem": carried_gem.duplicate(true),
		"resolved_rooms": resolved_rooms.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.master_seed = int(d.get("master_seed", 0))
	s.map_seed = int(d.get("map_seed", 0))
	s.current_chapter = maxi(1, int(d.get("current_chapter", 1)))
	var raw_relics: Variant = d.get("owned_relics", [])
	if raw_relics is Array:
		for item in raw_relics:
			var relic_id := str(item)
			if not relic_id.is_empty():
				s.owned_relics.append(relic_id)
	var raw_snapshots: Variant = d.get("relic_offer_snapshots", {})
	if raw_snapshots is Dictionary:
		for key in raw_snapshots.keys():
			s.relic_offer_snapshots[str(key)] = raw_snapshots[key]
	var raw_runtime: Variant = d.get("relic_runtime", {})
	if raw_runtime is Dictionary:
		for rid in raw_runtime.keys():
			s.relic_runtime[str(rid)] = RelicRuntimeState.from_dict(raw_runtime[rid])
	var raw_extra: Variant = d.get("extra_slots", [])
	if raw_extra is Array:
		s.extra_slots = (raw_extra as Array).duplicate(true)
	var raw_upgraded: Variant = d.get("upgraded_slots", [])
	if raw_upgraded is Array:
		s.upgraded_slots = (raw_upgraded as Array).duplicate(true)
	s.player_hp = int(d.get("player_hp", -1))
	s.player_max_hp = int(d.get("player_max_hp", -1))
	var raw_player_slot_gems: Variant = d.get("player_slot_gems", [])
	if raw_player_slot_gems is Array:
		s.player_slot_gems = (raw_player_slot_gems as Array).duplicate(true)
	var raw_carried_gem: Variant = d.get("carried_gem", {})
	if raw_carried_gem is Dictionary:
		s.carried_gem = (raw_carried_gem as Dictionary).duplicate(true)
	var raw_resolved_rooms: Variant = d.get("resolved_rooms", {})
	if raw_resolved_rooms is Dictionary:
		s.resolved_rooms = (raw_resolved_rooms as Dictionary).duplicate(true)
	return s
