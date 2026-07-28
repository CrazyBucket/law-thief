class_name GemTagResolver
extends RefCounted

const TAG_ORDER: Array[String] = [
	"explosion",
	"fire",
	"poison",
	"arc",
	"tide",
	"gravity",
	"impact",
	"ice",
	"split",
	"light",
	"counter",
	"echo",
	"flurry",
]


static func build_context(
	state: GameState,
	owner: Variant,
	slot_type: String,
	timing: String,
	primary_slot: SlotState = null,
	extra: Dictionary = {}
) -> Dictionary:
	var context := {
		"owner_uid": _owner_uid(owner),
		"slot_type": slot_type,
		"effect_level_scope": slot_type,
		"timing": timing,
		"primary_tag": "",
		"tag_levels": {},
		"tag_counts": {},
		"tags": [] as Array[String],
		"combos": [] as Array[String],
		"combo_levels": {},
		"source_gem_uids": [] as Array[String],
		"echo_depth": int(extra.get("echo_depth", 0)),
	}
	if state == null or owner == null:
		return context
	var registry := _data_registry()
	if registry == null:
		return context
	var state_tag_metadata := _state_tag_metadata(state, registry)
	var slots := _slots_accepting(owner, slot_type)
	for slot in slots:
		if not _slot_can_contribute(slot, state.turn_index):
			continue
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(registry.get_gem_tag(gem))
		if tag.is_empty():
			continue
		var tag_counts: Dictionary = context["tag_counts"]
		tag_counts[tag] = int(tag_counts.get(tag, 0)) + 1
		var source_gem_uids: Array[String] = context["source_gem_uids"]
		source_gem_uids.append(gem.uid)
		if primary_slot != null and slot == primary_slot:
			context["primary_tag"] = tag
	_resolve_levels(context, state_tag_metadata)
	_resolve_combos(context, state_tag_metadata)
	if str(context.get("primary_tag", "")).is_empty():
		var tags: Array[String] = context["tags"]
		if not tags.is_empty():
			context["primary_tag"] = tags[0]
	return context


static func tag_level(context: Dictionary, tag: String) -> int:
	return int((context.get("tag_levels", {}) as Dictionary).get(tag, 0))


static func has_tag(context: Dictionary, tag: String) -> bool:
	return tag_level(context, tag) > 0


static func combo_level(context: Dictionary, combo_id: String) -> int:
	return int((context.get("combo_levels", {}) as Dictionary).get(combo_id, 0))


static func has_combo(context: Dictionary, combo_id: String) -> bool:
	return combo_level(context, combo_id) > 0


static func _resolve_levels(context: Dictionary, state_tag_metadata: Dictionary) -> void:
	var tag_counts: Dictionary = context["tag_counts"]
	var tag_levels: Dictionary = context["tag_levels"]
	var tags: Array[String] = context["tags"]
	var max_stack_by_tag: Dictionary = state_tag_metadata.get("max_stack_by_tag", {})
	for tag in _sorted_tags(tag_counts.keys()):
		var max_stack := int(max_stack_by_tag.get(tag, 3))
		tag_levels[tag] = clampi(int(tag_counts.get(tag, 0)), 0, max_stack)
		tags.append(tag)


static func _resolve_combos(context: Dictionary, state_tag_metadata: Dictionary) -> void:
	var tags: Array[String] = context["tags"]
	var tag_levels: Dictionary = context["tag_levels"]
	var combos: Array[String] = context["combos"]
	var combo_levels: Dictionary = context["combo_levels"]
	var combo_tags_by_tag: Dictionary = state_tag_metadata.get("combo_tags_by_tag", {})
	for i in range(tags.size()):
		for j in range(i + 1, tags.size()):
			var a := tags[i]
			var b := tags[j]
			if not _tags_can_combo(a, b, combo_tags_by_tag):
				continue
			var combo_id := _combo_id(a, b)
			combos.append(combo_id)
			combo_levels[combo_id] = mini(int(tag_levels.get(a, 0)), int(tag_levels.get(b, 0)))


static func _tags_can_combo(a: String, b: String, combo_tags_by_tag: Dictionary) -> bool:
	var a_combos: Dictionary = combo_tags_by_tag.get(a, {})
	var b_combos: Dictionary = combo_tags_by_tag.get(b, {})
	return a_combos.has(b) or b_combos.has(a)


static func _state_tag_metadata(state: GameState, registry: Node) -> Dictionary:
	var max_stack_by_tag := {}
	var combo_tags_by_tag := {}
	for gem in state.gems.values():
		var tag := str(registry.get_gem_tag(gem))
		if tag.is_empty():
			continue
		max_stack_by_tag[tag] = maxi(
			int(max_stack_by_tag.get(tag, 3)), int(registry.get_gem_max_stack_level(gem))
		)
		var combo_tags: Dictionary = combo_tags_by_tag.get(tag, {})
		for combo_tag in registry.get_gem_combo_tags(gem):
			combo_tags[str(combo_tag)] = true
		combo_tags_by_tag[tag] = combo_tags
	return {
		"max_stack_by_tag": max_stack_by_tag,
		"combo_tags_by_tag": combo_tags_by_tag,
	}


static func _slots_accepting(owner: Variant, slot_type: String) -> Array:
	if owner is UnitState:
		return (owner as UnitState).slots_accepting(slot_type)
	if owner is TileState:
		var results: Array = []
		for slot in (owner as TileState).slots:
			if slot != null and slot.accepts_slot_type(slot_type):
				results.append(slot)
		return results
	return []


static func _slot_can_contribute(slot: SlotState, turn_index: int) -> bool:
	if slot == null:
		return false
	if slot.is_split_disabled():
		return false
	if not slot.locked:
		return true
	if slot.unlock_until_turn < 0:
		return false
	return slot.unlock_until_turn < turn_index


static func _owner_uid(owner: Variant) -> String:
	if owner is UnitState:
		return (owner as UnitState).uid
	if owner is TileState:
		return "%s:%s" % [(owner as TileState).tile_id, str((owner as TileState).pos)]
	return ""


static func _sorted_tags(raw_tags: Array) -> Array[String]:
	var tags: Array[String] = []
	for raw in raw_tags:
		tags.append(str(raw))
	tags.sort_custom(func(a: String, b: String): return _tag_rank(a) < _tag_rank(b))
	return tags


static func _tag_rank(tag: String) -> int:
	var index := TAG_ORDER.find(tag)
	return index if index >= 0 else TAG_ORDER.size() + tag.hash()


static func _combo_id(a: String, b: String) -> String:
	var ordered := _sorted_tags([a, b])
	return "%s_%s" % [ordered[0], ordered[1]]


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")
