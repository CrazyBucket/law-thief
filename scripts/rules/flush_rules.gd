class_name FlushRules
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")


static func apply(
	state: GameState,
	target: UnitState,
	count: int,
	remove_all_from_one_status: bool,
	source_uid: String,
	rng_domain: String
) -> Array[String]:
	var removed_status_ids: Array[String] = []
	if state == null or target == null or not target.alive:
		return removed_status_ids

	# Extinguishing is a water prerequisite, not one of the configured flushes.
	if target.has_status(Constants.STATUS_BURNING):
		target.remove_status(Constants.STATUS_BURNING)
		_record_mutation(state, target, Constants.STATUS_BURNING, source_uid, "extinguish")

	if remove_all_from_one_status:
		var picked := _pick_status(target, "%s_all" % rng_domain)
		if picked != null:
			var status_id := picked.status_id
			target.remove_status(status_id)
			_record_mutation(state, target, status_id, source_uid, "remove_all")
			removed_status_ids.append(status_id)
		return removed_status_ids

	for index in range(maxi(0, count)):
		var picked := _pick_status(target, "%s_%d" % [rng_domain, index])
		if picked == null:
			break
		var status_id := picked.status_id
		if _StatusRegistry.flush_measure(status_id) == "value":
			picked.value -= 1
			if picked.value <= 0:
				target.remove_status(status_id)
		else:
			picked.stacks -= 1
			if picked.stacks <= 0:
				target.remove_status(status_id)
		_record_mutation(state, target, status_id, source_uid, "remove_one")
		removed_status_ids.append(status_id)
	return removed_status_ids


static func _pick_status(target: UnitState, rng_domain: String) -> StatusInstance:
	var candidates: Array[StatusInstance] = []
	for status: StatusInstance in target.statuses:
		if not _StatusRegistry.is_flushable(status.status_id):
			continue
		if _StatusRegistry.flush_measure(status.status_id) == "value" and status.value <= 0:
			continue
		if _StatusRegistry.flush_measure(status.status_id) != "value" and status.stacks <= 0:
			continue
		candidates.append(status)
	candidates.sort_custom(func(a: StatusInstance, b: StatusInstance) -> bool:
		return a.status_id < b.status_id
	)
	if candidates.is_empty():
		return null
	var rng: Node = Engine.get_main_loop().root.get_node_or_null("RngService")
	if rng == null:
		return candidates[0]
	var index := int(rng.roll_int(rng_domain, 0, candidates.size() - 1))
	return candidates[index]


static func _record_mutation(
	state: GameState,
	target: UnitState,
	status_id: String,
	source_uid: String,
	mode: String
) -> void:
	state.bump_revision()
	state.record_transaction("flush_status", {
		"uid": target.uid,
		"status_id": status_id,
		"source_uid": source_uid,
		"mode": mode,
	})
	state.log("%s 的 %s 被冲洗" % [target.uid, _StatusRegistry.display_name(status_id)])
