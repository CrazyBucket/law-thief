class_name EncounterEnemyResolver
extends RefCounted


## The caller supplies the combat-scoped random picker so this resolver has no global run dependency.
static func resolve(encounter: Dictionary, encounter_id: String, weighted_pick: Callable) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	for raw_enemy in encounter.get("enemies", []):
		if raw_enemy is Dictionary:
			resolved.append((raw_enemy as Dictionary).duplicate(true))

	var groups: Array = encounter.get("enemy_groups", [])
	if not groups.is_empty():
		var valid_groups: Array = []
		var weights: Array = []
		for raw_group in groups:
			if not raw_group is Dictionary:
				continue
			var group := raw_group as Dictionary
			if (group.get("enemies", []) as Array).is_empty():
				continue
			valid_groups.append(group)
			weights.append(maxf(0.0, float(group.get("weight", 1.0))))
		var selected_group: Variant = _pick(weighted_pick, "encounter_group_%s" % encounter_id, valid_groups, weights)
		if selected_group is Dictionary:
			for raw_enemy in (selected_group as Dictionary).get("enemies", []):
				if raw_enemy is Dictionary:
					resolved.append((raw_enemy as Dictionary).duplicate(true))

	var random_slots: Array = encounter.get("random_enemies", [])
	for slot_index in range(random_slots.size()):
		var raw_slot: Variant = random_slots[slot_index]
		if not raw_slot is Dictionary:
			continue
		var slot := raw_slot as Dictionary
		var candidates: Array = slot.get("candidates", [])
		var candidate_defs: Array = []
		var candidate_weights: Array = []
		for raw_candidate in candidates:
			if raw_candidate is String:
				candidate_defs.append({"def_id": str(raw_candidate)})
				candidate_weights.append(1.0)
			elif raw_candidate is Dictionary:
				var candidate := (raw_candidate as Dictionary).duplicate(true)
				candidate_defs.append(candidate)
				candidate_weights.append(maxf(0.0, float(candidate.get("weight", 1.0))))
		var selected: Variant = _pick(
			weighted_pick,
			"encounter_random_enemy_%s_%d" % [encounter_id, slot_index],
			candidate_defs,
			candidate_weights
		)
		if not selected is Dictionary:
			continue
		var enemy := (selected as Dictionary).duplicate(true)
		enemy.erase("weight")
		enemy["pos"] = slot.get("pos", Vector2i.ZERO)
		resolved.append(enemy)
	return resolved


static func _pick(weighted_pick: Callable, domain: String, candidates: Array, weights: Array) -> Variant:
	if candidates.is_empty() or not weighted_pick.is_valid():
		return null
	return weighted_pick.call(domain, candidates, weights)
