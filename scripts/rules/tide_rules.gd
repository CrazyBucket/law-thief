class_name TideRules
extends RefCounted

const DamageContext = preload("res://scripts/rules/damage_context.gd")
const FlushRules = preload("res://scripts/rules/flush_rules.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")


static func apply_red_hit(
	state: GameState,
	target: UnitState,
	hit_cell: Vector2i,
	source_uid: String,
	gem_ctx: Dictionary
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "tide"))
	_apply_package(
		state,
		target,
		hit_cell,
		source_uid,
		_level_def(Constants.SLOT_RED, level),
		"tide_red_%s_%d_%d" % [source_uid, state.turn_index, state.revision]
	)


static func apply_blue_damaged(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	ctx: Dictionary,
	gem_ctx: Dictionary
) -> bool:
	var damage_context: Dictionary = ctx.get("damage_context", {})
	if not DamageContext.is_active_attack(damage_context) or source == null:
		return false
	var attack_event_id := str(damage_context.get("attack_event_id", ""))
	if not attack_event_id.is_empty():
		var seen_key := "tide_blue_seen:%s:%s" % [owner.uid, attack_event_id]
		if bool(state.battle_temp_flags.get(seen_key, false)):
			return false
		state.battle_temp_flags[seen_key] = true

	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "tide"))
	var level_def := _level_def(Constants.SLOT_BLUE, level)
	var trigger_limit := int(level_def.get("trigger_limit", 0))
	var count_key := "tide_blue_count:%s:%d" % [owner.uid, state.turn_index]
	var trigger_count := int(state.battle_temp_flags.get(count_key, 0))
	if trigger_limit > 0 and trigger_count >= trigger_limit:
		return false
	state.battle_temp_flags[count_key] = trigger_count + 1
	_apply_package(
		state,
		source,
		owner.pos,
		owner.uid,
		level_def,
		"tide_blue_%s_%d_%d" % [owner.uid, state.turn_index, trigger_count]
	)
	return true


static func apply_blue_damaged_from_hook(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	ctx: Dictionary,
	slot: SlotState
) -> bool:
	var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(
			state,
			owner,
			Constants.SLOT_BLUE,
			"owner_damaged",
			slot
		)
	return apply_blue_damaged(state, owner, source, ctx, gem_ctx)


static func apply_black_death(
	state: GameState,
	owner: UnitState,
	gem_ctx: Dictionary
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "tide"))
	var level_def := _level_def(Constants.SLOT_BLACK, level)
	var radius := int(level_def.get("death_radius", 1))
	var targets: Array[UnitState] = []
	for unit: UnitState in state.units.values():
		if unit.alive and BoardUtils.chebyshev(owner.pos, unit.pos) <= radius:
			targets.append(unit)
	targets.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		return a.uid < b.uid
	)
	for index in range(targets.size()):
		var target := targets[index]
		_apply_package(
			state,
			target,
			target.pos,
			owner.uid,
			level_def,
			"tide_black_%s_%d_%d" % [owner.uid, state.turn_index, index]
		)


static func apply_black_death_from_hook(
	state: GameState,
	owner: UnitState,
	gem_ctx: Dictionary
) -> bool:
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(
			state,
			owner,
			Constants.SLOT_BLACK,
			"on_death"
		)
	apply_black_death(state, owner, gem_ctx)
	return true


static func apply_attack_hit(
	ctx,
	hit_cell: Vector2i,
	hit_unit: UnitState,
	gem_ctx: Dictionary
) -> void:
	apply_red_hit(ctx.state, hit_unit, hit_cell, ctx.attacker.uid, gem_ctx)


static func add_level_summary_params(
	params: Dictionary,
	level_def: Dictionary,
	translator: Callable
) -> void:
	if not level_def.has("flush_count"):
		return
	if bool(level_def.get("flush_all_one_status", false)):
		params["flush_effect"] = translator.call(
			"gem.level.tide.flush_all",
			{},
			"remove every layer of one flushable status"
		)
	else:
		params["flush_effect"] = translator.call(
			"gem.level.tide.flush_count",
			{"count": int(level_def.get("flush_count", 0))},
			"flush {count} time(s)"
		)
	if level_def.has("trigger_limit"):
		var limit := int(level_def.get("trigger_limit", 0))
		params["trigger_window"] = translator.call(
			"gem.level.tide.trigger_all" if limit <= 0 else "gem.level.tide.trigger_limited",
			{} if limit <= 0 else {"count": limit},
			"after every active attack" if limit <= 0 else "after the first {count} active attack(s) each round"
		)


static func _apply_package(
	state: GameState,
	target: UnitState,
	cell: Vector2i,
	source_uid: String,
	level_def: Dictionary,
	rng_domain: String
) -> void:
	FlushRules.apply(
		state,
		target,
		int(level_def.get("flush_count", 0)),
		bool(level_def.get("flush_all_one_status", false)),
		source_uid,
		rng_domain
	)
	TileRules.create_shallow_water(state, cell, 2)


static func _level_def(slot_type: String, level: int) -> Dictionary:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	if registry == null:
		return {}
	return registry.get_gem_effect_level_def("tide", slot_type, level)
