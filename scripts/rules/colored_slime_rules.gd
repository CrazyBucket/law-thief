class_name ColoredSlimeRules
extends RefCounted

const CHILD_UNIT_IDS: Array[String] = [
	"unit_small_slime_blue",
	"unit_small_slime_dark",
	"unit_small_slime_green",
	"unit_small_slime_pink",
	"unit_small_slime_white",
	"unit_small_slime_yellow",
]


static func child_unit_ids(owner: UnitState, count: int, reason: String) -> Array[String]:
	var result: Array[String] = []
	if owner.unit_def_id != "unit_fission_slime" or count <= 0:
		return result
	var start := absi(owner.uid.hash()) % CHILD_UNIT_IDS.size()
	var rng: Node = Engine.get_main_loop().root.get_node_or_null("RngService")
	if rng != null:
		start = int(rng.roll_int("fission_slime_color_%s_%s" % [owner.uid, reason], 0, CHILD_UNIT_IDS.size() - 1))
	for i in range(count):
		result.append(CHILD_UNIT_IDS[(start + i) % CHILD_UNIT_IDS.size()])
	return result


static func configure_child_clone(clone: UnitState, owner: UnitState, requested_def_id: String, registry: Node) -> void:
	clone.unit_def_id = owner.unit_def_id
	clone.ai_profile_id = owner.ai_profile_id
	clone.behavior_id = owner.behavior_id if owner.team == Constants.TEAM_PLAYER else "generic_melee"
	if requested_def_id == owner.unit_def_id or not registry.has_unit_def(requested_def_id):
		return
	var child_def: Dictionary = registry.get_unit_def(requested_def_id)
	clone.unit_def_id = requested_def_id
	clone.ai_profile_id = str(child_def.get("ai_profile_id", owner.ai_profile_id))
	clone.behavior_id = str(child_def.get("behavior_id", "generic_melee"))
	for raw_tag in child_def.get("tags", []):
		clone.add_tag(str(raw_tag))
