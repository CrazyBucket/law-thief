class_name OldMageEncounterSetup
extends RefCounted

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

static func _rng() -> Node:
	return Engine.get_main_loop().root.get_node("RngService")


static func configure_loadout(registry, state: GameState, enemy: UnitState) -> void:
	if enemy == null or enemy.behavior_id != "old_mage":
		return
	var pool_ids: Array = ["gem_explosion", "gem_conductive", "gem_fire", "gem_ice", "gem_poison", "gem_light", "gem_impact"]
	_rng().shuffle_in_place("old_mage_initial_gems_%s" % enemy.uid, pool_ids)
	var colors: Array = [Constants.SLOT_RED, Constants.SLOT_RED, Constants.SLOT_BLUE]
	_rng().shuffle_in_place("old_mage_initial_colors_%s" % enemy.uid, colors)
	for index in range(mini(3, enemy.slots.size())):
		var slot: SlotState = enemy.slots[index]
		slot.slot_type = str(colors[index])
		slot.dual_type = ""
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		var gem_uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(gem_uid, str(pool_ids[index]))
		state.gems[gem_uid] = gem
		GemTransfer.to_unit_slot(state, gem, enemy, slot)
		state.battle_temp_flags["old_mage:%s:gem_loaded_turn:%s" % [enemy.uid, gem_uid]] = state.turn_index
	state.battle_temp_flags["old_mage:%s:phase" % enemy.uid] = "cast"


static func spawn_gem_field(registry, state: GameState, encounter: Dictionary) -> void:
	var raw_field: Variant = encounter.get("boss_gem_field", {})
	if not raw_field is Dictionary:
		return
	var field: Dictionary = raw_field
	var anchors: Array[Vector2i] = []
	for raw_anchor in field.get("anchors", []):
		var anchor := _vector(raw_anchor)
		if BoardUtils.in_bounds(state, anchor):
			anchors.append(anchor)
	var pool_ids: Array = field.get("pool_gems", []).duplicate()
	if anchors.is_empty() or pool_ids.is_empty():
		return
	var count := mini(int(field.get("count", pool_ids.size() + 1)), anchors.size())
	_rng().shuffle_in_place("old_mage_field_gems_%s" % state.encounter_id, pool_ids)
	anchors = _select_connected_anchors(state, anchors, count)
	if anchors.size() < count:
		return
	var selected_ids: Array = pool_ids.slice(0, mini(pool_ids.size(), count))
	while selected_ids.size() < count:
		selected_ids.append(pool_ids[int(_rng().roll_int(
			"old_mage_field_duplicate_%s_%d" % [state.encounter_id, selected_ids.size()], 0, pool_ids.size() - 1
		))])
	for index in range(selected_ids.size()):
		var gem_uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(gem_uid, str(selected_ids[index]))
		state.gems[gem_uid] = gem
		GemTransfer.to_ground(state, gem, anchors[index], {"source": "old_mage_pool", "old_mage_pool": true})


static func _select_connected_anchors(state: GameState, anchors: Array[Vector2i], count: int) -> Array[Vector2i]:
	# The field is randomised, but never allowed to fragment.  Every chosen point
	# joins the existing fuel chain within one normal refill move (3 steps).
	var remaining := anchors.duplicate()
	_rng().shuffle_in_place("old_mage_field_anchors_%s" % state.encounter_id, remaining)
	var selected: Array[Vector2i] = []
	var mage: UnitState = null
	for enemy in state.get_alive_enemies():
		if enemy.behavior_id == "old_mage":
			mage = enemy
			break
	if mage == null:
		return selected
	while selected.size() < count:
		var next_index := -1
		for index in range(remaining.size()):
			var candidate: Vector2i = remaining[index]
			var eligible := selected.is_empty() and BoardUtils.path_distance_to_cell(
				state, mage.pos, candidate, mage.uid, {}, mage
			) <= 3
			if not selected.is_empty():
				for linked in selected:
					if BoardUtils.path_distance_to_cell(state, linked, candidate, mage.uid, {}, mage) <= 3:
						eligible = true
						break
			if eligible:
				next_index = index
				break
		if next_index < 0:
			break
		selected.append(remaining[next_index])
		remaining.remove_at(next_index)
	return selected


static func _vector(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)
