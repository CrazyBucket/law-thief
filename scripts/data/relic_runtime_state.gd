class_name RelicRuntimeState
extends RefCounted

var relic_id: String = ""
var charges: int = -1       # -1 = 无限次
var cooldown_turns: int = 0
var flags: Dictionary = {}  # 遗物自定义 kv，由各效果处理器读写


static func create(relic_id: String) -> RelicRuntimeState:
	var s := RelicRuntimeState.new()
	s.relic_id = relic_id
	return s


func clone() -> RelicRuntimeState:
	var s := RelicRuntimeState.new()
	s.relic_id = relic_id
	s.charges = charges
	s.cooldown_turns = cooldown_turns
	s.flags = flags.duplicate(true)
	return s


func export_dict() -> Dictionary:
	return {
		"relic_id": relic_id,
		"charges": charges,
		"cooldown_turns": cooldown_turns,
		"flags": flags.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RelicRuntimeState:
	var s := RelicRuntimeState.new()
	s.relic_id = str(d.get("relic_id", ""))
	s.charges = int(d.get("charges", -1))
	s.cooldown_turns = int(d.get("cooldown_turns", 0))
	var raw_flags: Variant = d.get("flags", {})
	s.flags = raw_flags if raw_flags is Dictionary else {}
	return s
