class_name AttackPipeline
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")

# ─── 攻击标签集合 ────────────────────────────────────────────────────────────
const TAG_RANGED       := "ranged"
const TAG_MELEE        := "melee"
const TAG_EXPLOSIVE    := "explosive"
const TAG_KNOCKBACK    := "knockback"
const TAG_PULL         := "pull"
const TAG_DEFLECT      := "deflect"
const TAG_DEFLECT_DONE := "deflect_done"
const TAG_POISON       := "poison"
const TAG_POISON_FOG   := "poison_fog"
const TAG_ARC          := "arc"
const TAG_FIRE_ON_HIT  := "fire_on_hit"
const TAG_SLOW_ON_HIT  := "slow_on_hit"
const TAG_FORCED_MOVE  := "forced_move"
const TAG_PIERCING     := "piercing"
const TAG_NO_KILL_PROC := "no_kill_proc"
const TAG_SPLIT_SHOT   := "split_shot"


class AttackContext:
	var state: GameState
	var attacker: UnitState
	var aim_cell: Vector2i
	var target: UnitState = null

	var tags: Array[String] = []
	var base_damage: int = 0
	var final_damage: int = 0
	var events: Array[Dictionary] = []
	var payload: Dictionary = {}

	func _init(p_state: GameState, p_attacker: UnitState, p_aim_cell: Vector2i, p_target: UnitState = null) -> void:
		state = p_state
		attacker = p_attacker
		aim_cell = p_aim_cell
		target = p_target

	func add_tag(tag: String) -> void:
		if tag not in tags:
			tags.append(tag)

	func has_tag(tag: String) -> bool:
		return tag in tags

	func remove_tag(tag: String) -> void:
		tags.erase(tag)

	func push_event(ev: Dictionary) -> void:
		events.append(ev)

	func push_damage_event(pos: Vector2i, damage: int, is_crit: bool = false) -> void:
		events.append({
			"type": "damage",
			"pos": pos,
			"damage": damage,
			"is_crit": is_crit,
			"attacker_uid": attacker.uid,
		})

	func push_move_event(uid: String, from: Vector2i, to: Vector2i) -> void:
		events.append({"type": "move_step", "uid": uid, "from": from, "to": to})

	func push_explode_event(pos: Vector2i, radius: int) -> void:
		events.append({"type": "explode", "pos": pos, "radius": radius})


## 以瞄准格为唯一空间锚点执行攻击（空地 / 单位共用）
static func execute_aimed(
	state: GameState,
	attacker: UnitState,
	aim_cell: Vector2i,
	initial_tags: Array[String] = [],
	payload: Dictionary = {},
	max_range: int = Constants.ATTACK_RANGE
) -> Dictionary:
	if not attacker.alive:
		return _fail("攻击者无效")
	if not BoardUtils.can_unit_attack_cell(attacker, state, aim_cell, max_range):
		return _fail("目标超出射程")

	payload = payload.duplicate()
	payload["aim_cell"] = aim_cell

	var target := _resolve_unit_at_aim(state, attacker, aim_cell)
	if initial_tags.has(TAG_MELEE):
		if target == null:
			return _fail("近战需要单位目标")
		if not BoardUtils.are_units_adjacent(attacker, target):
			return _fail("近战目标不在相邻格")

	var ctx := AttackContext.new(state, attacker, aim_cell, target)
	ctx.payload = payload
	for tag in initial_tags:
		ctx.add_tag(tag)

	CombatRules.begin_deferred_death_hooks(ctx.events)

	var target_uid := ""
	if target != null:
		target_uid = target.uid
	state.on_attack_prepare.emit(attacker.uid, target_uid, ctx.tags.duplicate())
	_phase_prepare(ctx)
	if target != null and not ctx.target.alive:
		return _finish_execute(state, ctx, _ok(ctx.events))

	if ctx.has_tag(TAG_RANGED) and ctx.target != null:
		_try_deflect(ctx)
	if ctx.has_tag(TAG_DEFLECT_DONE):
		return _finish_execute(state, ctx, _ok(ctx.events))

	_phase_damage_calculate(ctx)
	_phase_hit(ctx)
	_phase_post_attack(ctx)
	_trigger_red_active(ctx)
	_reorder_split_shot_events(ctx)

	return _finish_execute(state, ctx, _ok(ctx.events))


## 兼容旧调用：目标单位锚点 = 其 pos，瞄准格可由 payload 覆盖
static func execute(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	initial_tags: Array[String] = [],
	payload: Dictionary = {}
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return _fail("目标或攻击者无效")
	var aim_cell := _resolve_aim_cell(payload, target.pos)
	return execute_aimed(state, attacker, aim_cell, initial_tags, payload)


static func _phase_prepare(ctx: AttackContext) -> void:
	_gem_hooks_prepare(ctx)


static func _phase_damage_calculate(ctx: AttackContext) -> void:
	ctx.base_damage = CombatRules.attack_damage(ctx.state, ctx.attacker)
	var charge_bonus: int = int(ctx.payload.get("charge_bonus", 0))
	if charge_bonus > 0:
		ctx.base_damage += charge_bonus
	var bonus_damage: int = int(ctx.payload.get("bonus_damage", 0))
	if bonus_damage > 0:
		ctx.base_damage += bonus_damage
	if ctx.has_tag(TAG_SPLIT_SHOT):
		ctx.base_damage = maxi(1, int(ctx.base_damage * Constants.SPLIT_ATTACK_DAMAGE_RATIO))
	if ctx.target == null:
		ctx.final_damage = 0
		return
	var armor := CombatRules.current_armor(ctx.state, ctx.target)
	if ctx.has_tag(TAG_PIERCING):
		armor = 0
	ctx.final_damage = maxi(0, ctx.base_damage - armor)


static func _phase_hit(ctx: AttackContext) -> void:
	if ctx.target != null and ctx.payload.get("force_miss", false):
		ctx.state.log("%s 的攻击未命中 %s" % [ctx.attacker.uid, ctx.target.uid])
		ctx.push_event({"type": "miss", "pos": ctx.target.pos, "attacker_uid": ctx.attacker.uid})
		return

	var reason: String = str(ctx.payload.get("damage_reason", ""))
	if reason.is_empty():
		if ctx.has_tag(TAG_RANGED):
			reason = "ranged_attack"
		elif ctx.has_tag(TAG_MELEE):
			reason = "melee_attack"
		else:
			reason = "attack"

	if ctx.has_tag(TAG_RANGED):
		_push_projectile_event(ctx, ctx.aim_cell)
	ctx.attacker.facing = UnitState.facing_from_unit_to_cell(ctx.attacker, ctx.aim_cell)

	var dealt := 0
	if ctx.target != null:
		dealt = CombatRules.apply_damage(ctx.state, ctx.target, ctx.base_damage, ctx.attacker.uid, reason)
		if dealt > 0:
			ctx.push_damage_event(ctx.aim_cell, dealt)
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, ctx.target.uid, dealt)

	if dealt > 0 and ctx.target != null:
		_ContactResolver.on_attack_contact(ctx.state, ctx.attacker, ctx.target)
		_gem_hooks_on_hit(ctx)
		if ctx.has_tag(TAG_KNOCKBACK) and not ctx.has_tag(TAG_EXPLOSIVE) and ctx.target.alive:
			_Displacement.knockback(ctx.state, ctx.target, ctx.attacker.pos, 1, ctx.attacker.uid, ctx.events)
		if ctx.has_tag(TAG_FIRE_ON_HIT) and ctx.target.alive:
			StatusRules.apply_burning(ctx.state, ctx.target, 1, ctx.attacker.uid)
		if ctx.has_tag(TAG_SLOW_ON_HIT) and ctx.target.alive:
			GemEffects.apply_ice_hit_effect(ctx.state, ctx.target, ctx.attacker.uid)

	if ctx.has_tag(TAG_EXPLOSIVE):
		_apply_cross_explosion(ctx)
	if ctx.has_tag(TAG_POISON_FOG):
		TileRules.create_poison_fog(ctx.state, ctx.aim_cell)
	if ctx.has_tag(TAG_ARC):
		var hit_tile := ctx.state.get_tile(ctx.aim_cell)
		if hit_tile != null and hit_tile.has_tile_tag(Constants.TAG_TILE_WATER):
			GemEffects.apply_water_conduction(ctx.state, ctx.aim_cell, ctx.attacker, ctx.events)
		elif ctx.target != null and ctx.target.alive:
			GemEffects.apply_arc_bounce_from_victim(
				ctx.state, ctx.target, ctx.attacker, ctx.base_damage, ctx.events
			)


static func _phase_post_attack(ctx: AttackContext) -> void:
	var killed := ctx.target != null and not ctx.target.alive

	if ctx.has_tag(TAG_PULL) and ctx.target != null and not killed:
		_Displacement.pull_toward(ctx.state, ctx.target, ctx.attacker.pos, 1, ctx.attacker.uid, ctx.events)

	if ctx.has_tag(TAG_SPLIT_SHOT):
		_apply_split_wings(ctx)

	if killed and not ctx.has_tag(TAG_NO_KILL_PROC):
		_gem_hooks_on_kill(ctx)


static func _gem_hooks_prepare(ctx: AttackContext) -> void:
	for slot in ctx.attacker.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match slot.slot_type:
			Constants.SLOT_RED:
				match _ability_profile(gem, GemEffects.ABILITY_UNIT_RED_ACTIVE):
					"explosion":
						ctx.add_tag(TAG_EXPLOSIVE)
					"gravity":
						ctx.add_tag(TAG_PULL)
					"poison":
						ctx.add_tag(TAG_POISON_FOG)
					"arc":
						ctx.add_tag(TAG_ARC)
					"fire_gem":
						ctx.add_tag(TAG_FIRE_ON_HIT)
					"ice":
						ctx.add_tag(TAG_SLOW_ON_HIT)
					"split":
						ctx.add_tag(TAG_SPLIT_SHOT)
	# 遗物 modifier：attack_split_count > 0 时自动附加分裂攻击
	if not ctx.has_tag(TAG_SPLIT_SHOT):
		var split_bonus: int = RelicEffectRegistry.query_modifier("attack_split_count", ctx.state)
		if split_bonus > 0:
			ctx.add_tag(TAG_SPLIT_SHOT)


static func _try_deflect(ctx: AttackContext) -> void:
	if ctx.target == null:
		return
	for slot in ctx.target.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if _ability_profile(gem, GemEffects.ABILITY_BLUE_DAMAGED) != "gravity":
			continue
		var candidates: Array[UnitState] = []
		for neighbor in BoardUtils.neighbors4(ctx.target.pos):
			var hit := ctx.state.get_unit_at(neighbor)
			if hit != null and hit.alive and hit.uid != ctx.attacker.uid:
				candidates.append(hit)
		if candidates.is_empty():
			var neighbors := BoardUtils.neighbors4(ctx.target.pos)
			var land: Vector2i = neighbors[RngService.roll_int("pipeline_gravity_land_%s" % ctx.target.uid, 0, neighbors.size() - 1)]
			ctx.state.log("%s 被引力偏转，投射物落地 %s" % [ctx.target.uid, land])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": land})
			ctx.add_tag(TAG_DEFLECT_DONE)
		else:
			var new_target: UnitState = candidates[RngService.roll_int("pipeline_gravity_redirect_%s" % ctx.target.uid, 0, candidates.size() - 1)]
			ctx.state.log("%s 被引力偏转，投射物转向 %s" % [ctx.target.uid, new_target.uid])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": new_target.pos})
			ctx.target = new_target
			ctx.aim_cell = new_target.pos
		break


static func _gem_hooks_on_hit(ctx: AttackContext) -> void:
	if ctx.has_tag(TAG_POISON) and ctx.target != null and ctx.target.alive:
		StatusRules.apply_poison(ctx.state, ctx.target, 1, 0, ctx.attacker.uid)


static func _gem_hooks_on_kill(ctx: AttackContext) -> void:
	pass


static func _trigger_red_active(ctx: AttackContext) -> void:
	if not ctx.has_tag(TAG_RANGED):
		return
	var slot := ctx.attacker.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return
	if GemEffects.unit_has_red_explosion(ctx.state, ctx.attacker):
		return
	var target_uid := ""
	if ctx.target != null:
		target_uid = ctx.target.uid
	GemEffects.trigger_gem(
		ctx.state,
		ctx.attacker.uid,
		slot,
		ctx.events,
		target_uid,
		ctx.aim_cell
	)


static func _apply_cross_explosion(ctx: AttackContext) -> void:
	var opts: Dictionary = {}
	if ctx.target != null:
		opts["exclude_unit_uid"] = ctx.target.uid
	var cross_events := GemEffects.explode_cross_at(
		ctx.state,
		ctx.aim_cell,
		ctx.attacker.uid,
		opts
	)
	for ev in cross_events:
		ctx.events.append(ev)


static func compute_split_wing_cells(attacker_pos: Vector2i, aim_pos: Vector2i) -> Array[Vector2i]:
	return SplitShotRules.wing_cells(attacker_pos, aim_pos)


static func _projectile_from_cell(attacker: UnitState, target_pos: Vector2i) -> Vector2i:
	if attacker.footprint_size == Vector2i(1, 1):
		return attacker.pos
	var best := attacker.pos
	var best_dist := 999999
	for cell in attacker.occupied_cells():
		var d := BoardUtils.chebyshev(cell, target_pos)
		if d < best_dist:
			best_dist = d
			best = cell
	return best


static func _push_projectile_event(ctx: AttackContext, to_pos: Vector2i) -> void:
	ctx.push_event({
		"type": "projectile",
		"from": _projectile_from_cell(ctx.attacker, to_pos),
		"to": to_pos,
	})


static func _apply_split_wings(ctx: AttackContext) -> void:
	var origin := SplitShotRules.attacker_origin(ctx.attacker, ctx.aim_cell)
	var forbidden := ctx.attacker.occupied_cells()
	var wing_cells := SplitShotRules.wing_cells(origin, ctx.aim_cell, forbidden)
	for wing_pos in wing_cells:
		if not BoardUtils.in_bounds(ctx.state, wing_pos):
			continue
		_push_projectile_event(ctx, wing_pos)
		var wing_target := ctx.state.get_unit_at(wing_pos)
		if wing_target == null or not wing_target.alive or wing_target.uid == ctx.attacker.uid:
			continue
		var dealt := CombatRules.apply_damage(ctx.state, wing_target, ctx.base_damage, ctx.attacker.uid, "split_wing")
		if dealt > 0:
			ctx.push_damage_event(wing_target.pos, dealt)
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, wing_target.uid, dealt)


static func _resolve_unit_at_aim(state: GameState, attacker: UnitState, aim_cell: Vector2i) -> UnitState:
	var unit := state.get_unit_at(aim_cell)
	if unit == null or not unit.alive or unit.uid == attacker.uid:
		return null
	return unit


static func _resolve_aim_cell(payload: Dictionary, fallback: Vector2i) -> Vector2i:
	var raw: Variant = payload.get("aim_cell", null)
	if raw is Vector2i:
		return raw
	return fallback


static func _ability_profile(gem: GemState, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem, ability_slot)


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _finish_execute(state: GameState, ctx: AttackContext, result: Dictionary) -> Dictionary:
	CombatRules.end_deferred_death_hooks(state)
	return result


static func _reorder_split_shot_events(ctx: AttackContext) -> void:
	if not ctx.has_tag(TAG_SPLIT_SHOT):
		return
	var projs: Array[Dictionary] = []
	var damages: Array[Dictionary] = []
	var other: Array[Dictionary] = []
	for ev in ctx.events:
		match str(ev.get("type", "")):
			"projectile", "projectile_deflect":
				projs.append(ev)
			"damage":
				damages.append(ev)
			_:
				other.append(ev)
	ctx.events.clear()
	ctx.events.append_array(projs)
	ctx.events.append_array(damages)
	ctx.events.append_array(other)


static func _ok(events: Array[Dictionary]) -> Dictionary:
	return {"ok": true, "events": events}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": [] as Array[Dictionary]}
