class_name RunState
extends RefCounted

var master_seed: int = 0
var map_seed: int = 0
## relic_id 有序列表，顺序等于获取顺序
var owned_relics: Array[String] = []
## room_id → Array[String]：已锁定的奖励候选快照，SL 安全
var relic_offer_snapshots: Dictionary = {}
## relic_id → RelicRuntimeState
var relic_runtime: Dictionary = {}


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


func export_dict() -> Dictionary:
	var runtime_raw: Dictionary = {}
	for rid in relic_runtime.keys():
		var rs: RelicRuntimeState = relic_runtime[rid]
		runtime_raw[rid] = rs.export_dict()
	return {
		"master_seed": master_seed,
		"map_seed": map_seed,
		"owned_relics": owned_relics.duplicate(),
		"relic_offer_snapshots": relic_offer_snapshots.duplicate(true),
		"relic_runtime": runtime_raw,
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.master_seed = int(d.get("master_seed", 0))
	s.map_seed = int(d.get("map_seed", 0))
	var raw_relics: Variant = d.get("owned_relics", [])
	if raw_relics is Array:
		for item in raw_relics:
			s.owned_relics.append(str(item))
	var raw_snapshots: Variant = d.get("relic_offer_snapshots", {})
	if raw_snapshots is Dictionary:
		for key in raw_snapshots.keys():
			s.relic_offer_snapshots[str(key)] = raw_snapshots[key]
	var raw_runtime: Variant = d.get("relic_runtime", {})
	if raw_runtime is Dictionary:
		for rid in raw_runtime.keys():
			s.relic_runtime[str(rid)] = RelicRuntimeState.from_dict(raw_runtime[rid])
	return s
