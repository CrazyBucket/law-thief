class_name AttackSegmentRules
extends RefCounted

const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")


static func next_attack_event_id(state: GameState, attacker: UnitState) -> String:
	var serial := int(state.battle_temp_flags.get("attack_event_serial", 0)) + 1
	state.battle_temp_flags["attack_event_serial"] = serial
	return "%d:%s:%d" % [state.turn_index, attacker.uid, serial]


static func execute_segments(ctx: AttackContext, hit_callback: Callable, prepare_callback: Callable = Callable()) -> void:
	var plan := _prepare(ctx)
	for index in range(int(plan["count"])):
		# The segment plan belongs to the attack, not to the target's lifetime.
		# Later segments still resolve their visuals and cell-based effects after
		# a lethal hit, while the damage layer ignores the defeated unit.
		ctx.payload["attack_segment_index"] = index
		ctx.payload["attack_segment_count"] = int(plan["count"])
		ctx.payload["current_attack_event_id"] = _event_id(ctx, index)
		ctx.base_damage = int(plan["damage"])
		if prepare_callback.is_valid() and not bool(prepare_callback.call(ctx)):
			break
		hit_callback.call(ctx)


static func misses(ctx: AttackContext, rng: Node) -> bool:
	if bool(ctx.payload.get("force_miss", false)):
		return true
	var hit_chance := clampf(float(ctx.payload.get("hit_chance", 1.0)), 0.0, 1.0)
	if hit_chance >= 1.0 or rng == null:
		return false
	return not bool(rng.chance(
		"attack_hit_%s_%s_%d" % [ctx.attacker.uid, str(ctx.payload.get("attack_event_id", "")), int(ctx.payload.get("attack_segment_index", 0))],
		hit_chance
	))


static func miss_event(ctx: AttackContext) -> Dictionary:
	return {
		"type": "miss",
		"pos": ctx.target.pos,
		"attacker_uid": ctx.attacker.uid,
		"attack_event_id": str(ctx.payload.get("current_attack_event_id", "")),
		"segment_index": int(ctx.payload.get("attack_segment_index", 0)),
		"segment_count": int(ctx.payload.get("attack_segment_count", 1)),
	}


static func event_ids(ctx: AttackContext) -> Array[String]:
	var ids: Array[String] = []
	for index in range(maxi(1, int(ctx.payload.get("attack_segment_count", 1)))):
		var event_id := _event_id(ctx, index)
		if not event_id.is_empty() and event_id not in ids:
			ids.append(event_id)
	return ids


static func _prepare(ctx: AttackContext) -> Dictionary:
	var base_segments := maxi(1, int(ctx.payload.get("base_hit_count", 1)))
	if ctx.payload.has("forced_hit_count"):
		var count := maxi(1, int(ctx.payload.get("forced_hit_count", 1)))
		var damage := maxi(1, int(float(ctx.base_damage) / float(count)))
		if ctx.payload.has("forced_segment_damage"):
			damage = maxi(1, int(ctx.payload["forced_segment_damage"]))
		ctx.payload["flurry_value"] = 0
		return {"count": count, "damage": damage}
	var value := 0
	if not bool(ctx.payload.get("disable_flurry", false)):
		value = FlurryRules.red_flurry_value(ctx.state, ctx.attacker) + FlurryRules.consume_stored(ctx.attacker)
	var count := base_segments + value
	ctx.payload["flurry_value"] = value
	ctx.push_trace({
		"phase": "damage_calculate", "operation": "apply_flurry", "base_segments": base_segments,
		"flurry_value": value, "segment_count": count,
		"total_multiplier": FlurryRules.total_damage_multiplier(value),
		"rounding": "floor_then_min_1_per_segment",
	})
	return {"count": count, "damage": FlurryRules.segment_damage(ctx.base_damage, base_segments, value)}


static func _event_id(ctx: AttackContext, index: int) -> String:
	var base_id := str(ctx.payload.get("attack_event_id", ""))
	return "%s:segment:%d" % [base_id, index] if bool(ctx.payload.get("segments_are_attack_events", false)) else base_id
