class_name ImpactRules
extends RefCounted

const DamageContext = preload("res://scripts/rules/damage_context.gd")
const Displacement = preload("res://scripts/rules/displacement.gd")
const FootprintRules = preload("res://scripts/rules/footprint_rules.gd")
const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")


static func _level_def(tag: String, slot_type: String, level: int) -> Dictionary:
	return _data_registry().get_gem_effect_level_def(tag, slot_type, level)


static func red_range_bonus(state: GameState, unit: UnitState) -> int:
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_RED, "active")
	var bonus := 0
	for tag in ["gravity", "impact"]:
		var level := GemTagResolver.tag_level(gem_ctx, tag)
		if level > 0:
			bonus += int(_level_def(tag, Constants.SLOT_RED, level)["range_bonus"])
	return bonus


static func is_valid_aim(attacker: UnitState, target_pos: Vector2i) -> bool:
	if attacker == null:
		return false
	var origin := BoardUtils.projectile_origin_cell(attacker, target_pos)
	var delta := target_pos - origin
	return delta != Vector2i.ZERO and (delta.x == 0 or delta.y == 0)


static func preview_path(
	state: GameState,
	attacker: UnitState,
	aim_cell: Vector2i,
	max_range: int
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if state == null or not is_valid_aim(attacker, aim_cell):
		return path
	path.append(attacker.pos)
	var origin := BoardUtils.projectile_origin_cell(attacker, aim_cell)
	var step := _direction_step(origin, aim_cell)
	for distance in range(1, max_range + 1):
		var cell := origin + step * distance
		if not BoardUtils.in_bounds(state, cell):
			break
		path.append(cell)
		if BoardUtils.blocking_entity_at(state, cell) != null:
			break
		var unit := state.get_unit_at(cell)
		if unit != null and unit.alive and unit.uid != attacker.uid:
			break
	return path


static func target_in_direction(
	state: GameState,
	attacker: UnitState,
	aim_cell: Vector2i,
	max_range: int
) -> UnitState:
	for cell in preview_path(state, attacker, aim_cell, max_range).slice(1):
		if BoardUtils.blocking_entity_at(state, cell) != null:
			return null
		var unit := state.get_unit_at(cell)
		if unit != null and unit.alive and unit.uid != attacker.uid:
			return unit
	return null


static func prepare_attack(ctx: Variant) -> bool:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	if not GemTagResolver.has_tag(gem_ctx, "impact"):
		return true
	if not is_valid_aim(ctx.attacker, ctx.aim_cell):
		return false
	ctx.remove_tag("ranged")
	ctx.remove_tag("melee")
	# 冲击是完整攻击形态；弹道分裂与光束形态不能叠在同一次冲击上。
	ctx.remove_tag("split_shot")
	ctx.remove_tag("light_beam")
	ctx.payload["damage_reason"] = "impact_attack"
	var max_range := int(ctx.payload.get("resolved_attack_range", CombatConfig.attack_range()))
	ctx.target = target_in_direction(ctx.state, ctx.attacker, ctx.aim_cell, max_range)
	if ctx.target == null:
		_charge_empty_direction(ctx, max_range)
		return true
	return _charge_segment(ctx, true)


static func prepare_segment(ctx: Variant) -> bool:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	if not GemTagResolver.has_tag(gem_ctx, "impact"):
		return true
	if int(ctx.payload.get("attack_segment_index", 0)) == 0:
		return true
	return _charge_segment(ctx, false)


static func _charge_segment(ctx: Variant, grants_damage_bonus: bool) -> bool:
	if ctx.target == null:
		return false
	if not ctx.target.alive:
		return ctx.effect_anchor_at(ctx.aim_cell) != null
	var start_pos: Vector2i = ctx.attacker.pos
	var event_start: int = ctx.events.size()
	var target_cell := FootprintRules.nearest_cell_to(ctx.target, ctx.attacker.pos, ctx.target.pos)
	if not is_valid_aim(ctx.attacker, target_cell):
		return false
	ctx.aim_cell = target_cell
	var travel_steps := maxi(0, BoardUtils.distance_between_units(ctx.attacker, ctx.target) - 1)
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	Displacement.dash_toward(
		ctx.state, ctx.attacker, target_cell, travel_steps, ctx.attacker.uid, ctx.events, -1, false,
		DamageContext.create(ctx.attacker.uid, "impact_dash_collision", ["impact"], gem_ctx)
	)
	var moved_steps := BoardUtils.manhattan(start_pos, ctx.attacker.pos)
	ctx.events.insert(event_start, EventBuilder.impact_charge(
		ctx.attacker.uid, start_pos, ctx.attacker.pos, target_cell, {
			"source_uid": ctx.attacker.uid,
			"target_uid": ctx.target.uid,
			"steps": moved_steps,
		}
	))
	ctx.payload["impact_dash_steps"] = moved_steps
	if grants_damage_bonus:
		ctx.payload["bonus_damage"] = int(ctx.payload.get("bonus_damage", 0)) + moved_steps
	ctx.payload["impact_blocked"] = not BoardUtils.are_units_adjacent(ctx.attacker, ctx.target)
	return not bool(ctx.payload["impact_blocked"])


static func _charge_empty_direction(ctx: Variant, max_range: int) -> void:
	var path := preview_path(ctx.state, ctx.attacker, ctx.aim_cell, max_range)
	var start_pos: Vector2i = ctx.attacker.pos
	var endpoint: Vector2i = path[-1] if path.size() > 1 else ctx.aim_cell
	var event_start: int = ctx.events.size()
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	Displacement.dash_toward(
		ctx.state, ctx.attacker, endpoint, max_range, ctx.attacker.uid, ctx.events, -1, false,
		DamageContext.create(ctx.attacker.uid, "impact_dash_collision", ["impact"], gem_ctx)
	)
	ctx.events.insert(event_start, EventBuilder.impact_charge(
		ctx.attacker.uid, start_pos, ctx.attacker.pos, endpoint, {
			"source_uid": ctx.attacker.uid,
			"steps": BoardUtils.manhattan(start_pos, ctx.attacker.pos),
		}
	))
	ctx.payload["impact_finished_without_target"] = true


static func _direction_step(origin: Vector2i, aim_cell: Vector2i) -> Vector2i:
	return Vector2i(signi(aim_cell.x - origin.x), signi(aim_cell.y - origin.y))


static func apply_hit(ctx: Variant, target: UnitState) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	if target == null or not target.alive or not GemTagResolver.has_tag(gem_ctx, "impact"):
		return
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "impact"))
	var steps := maxi(0, int(ctx.payload.get("impact_dash_steps", 0)) + int(_level_def("impact", Constants.SLOT_RED, level)["knockback_offset"]))
	if steps <= 0:
		return
	var origin := FootprintRules.nearest_cell_to(ctx.attacker, target.pos, ctx.attacker.pos)
	Displacement.knockback(
		ctx.state, target, origin, steps, ctx.attacker.uid, ctx.events, -1, false,
		ctx.build_damage_context("impact_collision", {"damage_tags": ["impact"]})
	)


static func run_blue_after_damage(
	state: GameState,
	owner: UnitState,
	source_uid: String,
	damage: int,
	damage_context: Dictionary
) -> void:
	if owner == null or not owner.alive or owner.hp <= 0 or damage <= 0 \
			or not DamageContext.is_active_attack(damage_context):
		return
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or not source.alive or source.uid == owner.uid:
		return
	var gem_ctx := GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, "owner_damaged")
	var level := GemTagResolver.tag_level(gem_ctx, "impact")
	if level < 1:
		return
	var out_events: Array[Dictionary] = state.get_combat_event_sink() if state.has_combat_event_sink() else []
	var origin := FootprintRules.nearest_cell_to(source, owner.pos, source.pos)
	var collision_ctx := DamageContext.create(owner.uid, "impact_collision", ["impact"], gem_ctx)
	collision_ctx["suppress_mover_collision_damage"] = true
	Displacement.knockback(
		state, owner, origin, int(_level_def("impact", Constants.SLOT_BLUE, level)["knockback_steps"]),
		owner.uid, out_events, -1, false, collision_ctx
	)


static func resolve_black_death(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary
) -> void:
	var impact_level := GemTagResolver.tag_level(gem_ctx, "impact")
	var impact_steps := 0
	if impact_level > 0:
		impact_steps = FlurryRules.scaled_repeat_int(int(_level_def("impact", Constants.SLOT_BLACK, impact_level)["knockback_steps"]), gem_ctx, 1)
	var touching: Dictionary = {}
	for unit in FootprintRules.adjacent_units(state, owner):
		touching[unit.uid] = true
	var gravity_level := GemTagResolver.tag_level(gem_ctx, "gravity")
	var gravity_steps := 0
	var gravity_def: Dictionary = {}
	if gravity_level > 0:
		gravity_def = _level_def("gravity", Constants.SLOT_BLACK, gravity_level)
		gravity_steps = FlurryRules.scaled_repeat_int(int(gravity_def["pull_steps"]), gem_ctx, 1)
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		var gravity_applies := gravity_level > 0 and BoardUtils.chebyshev_between_units(owner, unit) <= CombatConfig.explosion_death_radius()
		var impact_applies := touching.has(unit.uid) and impact_level > 0
		if not gravity_applies and not impact_applies:
			continue
		var net_steps := (impact_steps if impact_applies else 0) - (gravity_steps if gravity_applies else 0)
		var anchor := FootprintRules.nearest_cell_to(owner, unit.pos, owner.pos)
		var collision_ctx := DamageContext.create(owner.uid, "impact_collision", gem_ctx.get("tags", []), gem_ctx)
		if net_steps > 0:
			Displacement.knockback(state, unit, anchor, net_steps, owner.uid, out_events, -1, false, collision_ctx)
		elif net_steps < 0:
			Displacement.pull_toward(state, unit, anchor, -net_steps, owner.uid, out_events, -1, false, false, collision_ctx)
		if gravity_applies and bool(gravity_def["apply_slow"]):
			StatusRules.apply_slowed(state, unit, 1, owner.uid)
		if gravity_applies and bool(gravity_def["apply_root"]):
			StatusRules.apply_rooted(state, unit, 1, owner.uid)
