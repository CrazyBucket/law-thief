class_name AttackPipeline
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")

# ─── 攻击标签集合 ────────────────────────────────────────────────────────────
const TAG_RANGED       := "ranged"
const TAG_MELEE        := "melee"
const TAG_EXPLOSIVE    := "explosive"
const TAG_KNOCKBACK    := "knockback"
const TAG_DEFLECT      := "deflect"
const TAG_DEFLECT_DONE := "deflect_done"
const TAG_POISON       := "poison"
const TAG_ARC          := "arc"
const TAG_FIRE_ON_HIT  := "fire_on_hit"
const TAG_FIRE_TILE    := "fire_tile"
const TAG_SLOW_ON_HIT  := "slow_on_hit"
const TAG_SLOW_SELF    := "slow_self"
const TAG_GRAVITY_AURA := "gravity_aura"
const TAG_FORCED_MOVE  := "forced_move"
const TAG_PIERCING     := "piercing"
const TAG_NO_KILL_PROC := "no_kill_proc"
const TAG_SPLIT_SHOT   := "split_shot"
const TAG_LIGHT_BEAM   := "light_beam"
const TAG_COUNTER      := "counter"
const TAG_ECHO         := "echo"


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
	if GemEffects.unit_has_red_light(state, attacker):
		max_range = Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
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
	state.bind_combat_events(ctx.events)

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
		if ctx.has_tag(TAG_SPLIT_SHOT):
			_apply_split_wings(ctx)
			_reorder_split_shot_events(ctx)
		return _finish_execute(state, ctx, _ok(ctx.events))

	_phase_damage_calculate(ctx)
	_phase_hit(ctx)
	_phase_post_attack(ctx)
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
	if ctx.attacker.uid == ctx.state.player_uid:
		var registry := _relic_effect_registry()
		if registry != null:
			var miss_chance: float = float(registry.query_modifier("attack_miss_chance", ctx.state))
			if miss_chance > 0.0:
				var rng := _rng_service()
				if rng != null and bool(rng.chance("goggles_miss_%d" % ctx.state.turn_index, miss_chance)):
					ctx.payload["force_miss"] = true


static func _phase_damage_calculate(ctx: AttackContext) -> void:
	ctx.base_damage = CombatRules.attack_damage(ctx.state, ctx.attacker)
	var charge_bonus: int = int(ctx.payload.get("charge_bonus", 0))
	if charge_bonus > 0:
		ctx.base_damage += charge_bonus
	var bonus_damage: int = int(ctx.payload.get("bonus_damage", 0))
	if bonus_damage > 0:
		ctx.base_damage += bonus_damage
	if ctx.has_tag(TAG_SPLIT_SHOT):
		var _split_registry := _relic_effect_registry()
		var split_red_ratio := _split_red_damage_ratio(ctx)
		if _split_registry != null:
			split_red_ratio = _split_registry.query_override_modifier("split_red_damage_ratio", ctx.state, split_red_ratio)
		ctx.base_damage = maxi(1, int(ctx.base_damage * split_red_ratio))
	if ctx.target == null:
		ctx.final_damage = 0
		return
	var armor := CombatRules.current_shield(ctx.state, ctx.target)
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

	if ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_light_beam(ctx, reason)
		return

	if ctx.has_tag(TAG_RANGED):
		var from_cell := BoardUtils.projectile_origin_cell(ctx.attacker, ctx.aim_cell)
		_push_projectile_event(ctx, from_cell, ctx.aim_cell)
	ctx.attacker.facing = UnitState.facing_from_unit_to_cell(ctx.attacker, ctx.aim_cell)

	_apply_tags_at_cell(ctx, ctx.aim_cell, ctx.target, reason)


static func _phase_post_attack(ctx: AttackContext) -> void:
	var killed := ctx.target != null and not ctx.target.alive

	if ctx.has_tag(TAG_SPLIT_SHOT):
		_apply_split_wings(ctx)

	if ctx.has_tag(TAG_GRAVITY_AURA):
		_apply_gravity_aura(ctx)

	if ctx.has_tag(TAG_SLOW_SELF):
		_apply_ice_self_slow(ctx)

	if ctx.has_tag(TAG_COUNTER):
		_apply_red_counter(ctx)

	if killed and not ctx.has_tag(TAG_NO_KILL_PROC):
		_gem_hooks_on_kill(ctx)


## 单格命中：直伤、十字爆炸、元素 tag 均在此结算（主弹与分裂翼弹共用）
static func _apply_tags_at_cell(
	ctx: AttackContext,
	hit_cell: Vector2i,
	target: UnitState,
	reason: String
) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var dealt := 0
	if target != null and target.alive and not ctx.has_tag(TAG_EXPLOSIVE):
		dealt = CombatRules.apply_damage(ctx.state, target, ctx.base_damage, ctx.attacker.uid, reason)
		if dealt > 0:
			ctx.push_damage_event(hit_cell, dealt)
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, target.uid, dealt)
			_apply_direct_hit_extras(ctx, target)

	if ctx.has_tag(TAG_EXPLOSIVE):
		_apply_cross_explosion_at(ctx, hit_cell)

	var hit_unit := _resolve_unit_at_aim(ctx.state, ctx.attacker, hit_cell)
	var had_burning_before := hit_unit != null and hit_unit.has_status(Constants.STATUS_BURNING)

	if ctx.has_tag(TAG_POISON):
		_apply_poison_at_cell(ctx, hit_cell, hit_unit, gem_ctx)

	if ctx.has_tag(TAG_FIRE_TILE):
		_apply_fire_tile_at_cell(ctx, hit_cell, hit_unit, gem_ctx, had_burning_before)

	if hit_unit != null and hit_unit.alive:
		if ctx.has_tag(TAG_FIRE_ON_HIT):
			StatusRules.apply_burning(ctx.state, hit_unit, 1, ctx.attacker.uid)
		if ctx.has_tag(TAG_SLOW_ON_HIT):
			GemEffects.apply_ice_hit_effect(
				ctx.state,
				hit_unit,
				ctx.attacker.uid,
				GemTagResolver.tag_level(gem_ctx, "ice")
			)

	if ctx.has_tag(TAG_POISON) and ctx.has_tag(TAG_FIRE_TILE):
		GemComboResolver.apply_after_attack_hit(ctx.state, hit_cell, gem_ctx, ctx.events)

	if ctx.has_tag(TAG_ARC):
		var hit_tile := ctx.state.get_tile(hit_cell)
		if hit_tile != null and hit_tile.has_tile_tag(Constants.TAG_TILE_WATER):
			GemEffects.apply_water_conduction(ctx.state, hit_cell, ctx.attacker, ctx.events)
		elif hit_unit != null and hit_unit.alive:
			GemEffects.apply_arc_bounce_from_victim(
				ctx.state,
				hit_unit,
				ctx.attacker,
				ctx.base_damage,
				ctx.events,
				ctx.payload.get("gem_tag_context", {})
			)

	_try_apply_chaos_launcher_at_cell(ctx, hit_cell, hit_unit)


static func _apply_direct_hit_extras(ctx: AttackContext, target: UnitState) -> void:
	if target == null or not target.alive:
		return
	_ContactResolver.on_attack_contact(ctx.state, ctx.attacker, target)
	if ctx.has_tag(TAG_KNOCKBACK) and target.alive:
		_Displacement.knockback(ctx.state, target, ctx.attacker.pos, 1, ctx.attacker.uid, ctx.events)
	if ctx.attacker.uid == ctx.state.player_uid and target.alive:
		var _registry := _relic_effect_registry()
		if _registry != null:
			var break_bonus: int = int(_registry.query_modifier("armor_lock_break_bonus", ctx.state))
			if break_bonus > 0:
				_apply_crowbar_break(ctx, target, break_bonus)


static func _apply_poison_at_cell(
	ctx: AttackContext,
	cell: Vector2i,
	unit: UnitState,
	gem_ctx: Dictionary = {}
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var radius := 0
	var duration := Constants.POISON_FOG_DURATION
	if level >= 2:
		radius = 1
	if level >= 3:
		duration += 1
	ctx.push_event({"type": "poison_burst", "pos": cell, "radius": radius})
	if BoardUtils.in_bounds(ctx.state, cell):
		TileRules.create_poison_fog(ctx.state, cell, duration)
		if level >= 2:
			for neighbor in BoardUtils.neighbors4(cell):
				if BoardUtils.in_bounds(ctx.state, neighbor):
					TileRules.create_poison_fog(ctx.state, neighbor, duration)
	if unit != null and unit.alive:
		StatusRules.apply_poison(ctx.state, unit, 1, 0, ctx.attacker.uid)


static func _apply_fire_tile_at_cell(
	ctx: AttackContext,
	cell: Vector2i,
	_unit: UnitState = null,
	gem_ctx: Dictionary = {},
	had_burning_before: bool = false
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "fire"))
	ctx.push_event({"type": "fire_burst", "pos": cell})
	TileRules.create_fire(ctx.state, cell)
	var spread_count := 0
	if level >= 2:
		spread_count += 1
	if level >= 3 and had_burning_before:
		spread_count += 1
	if spread_count <= 0:
		return
	for spread_cell in _random_adjacent_cells(ctx.state, cell, spread_count, "fire_spread_%d_%d" % [cell.x, cell.y]):
		TileRules.create_fire(ctx.state, spread_cell)
		ctx.push_event({"type": "fire_burst", "pos": spread_cell, "spread": true})


static func _apply_cross_explosion_at(ctx: AttackContext, center: Vector2i) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var explosion_level := GemTagResolver.tag_level(gem_ctx, "explosion")
	if explosion_level >= 2:
		var damage := Constants.EXPLOSION_CROSS_DAMAGE
		if explosion_level >= 3:
			damage *= 2
		var square_events := GemEffects.explode_square_at(ctx.state, center, ctx.attacker.uid, damage, gem_ctx)
		for ev in square_events:
			ctx.events.append(ev)
		return
	var opts: Dictionary = {
		"center_damage": Constants.EXPLOSION_CROSS_DAMAGE,
		"gem_tag_context": gem_ctx,
	}
	var cross_events := GemEffects.explode_cross_at(
		ctx.state,
		center,
		ctx.attacker.uid,
		opts
	)
	for ev in cross_events:
		ctx.events.append(ev)


static func _apply_gravity_aura(ctx: AttackContext) -> void:
	var gravity_gem := GemEffects.find_red_active_gem(ctx.state, ctx.attacker, "gravity")
	if gravity_gem != null:
		ctx.push_event({
			"type": "gem_flash",
			"pos": ctx.attacker.pos,
			"color": _data_registry().get_gem_color(gravity_gem),
		})
	var level := maxi(1, GemTagResolver.tag_level(ctx.payload.get("gem_tag_context", {}), "gravity"))
	for unit in ctx.state.units.values():
		if not unit.alive or unit.uid == ctx.attacker.uid:
			continue
		if BoardUtils.chebyshev(ctx.attacker.pos, unit.pos) > 2:
			continue
		ctx.events.append_array(
			GemEffects.pull_unit_toward_with_events(ctx.state, unit, ctx.attacker.pos, level, ctx.attacker.uid)
		)


static func _apply_light_beam(ctx: AttackContext, reason: String) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "light"))
	var from_cell := BoardUtils.projectile_origin_cell(ctx.attacker, ctx.aim_cell)
	var cells := _light_beam_cells(ctx.state, from_cell, ctx.aim_cell, level >= 3)
	if cells.is_empty():
		return
	var beam_color := _light_beam_color(gem_ctx)
	var beam_width := 1 if level < 2 else 2
	ctx.push_event({
		"type": "light_beam",
		"from": from_cell,
		"to": cells[cells.size() - 1],
		"cells": cells,
		"color": beam_color,
		"width": beam_width,
	})
	var damage_ratio := 0.5
	if level >= 3:
		damage_ratio = 1.0
	elif level >= 2:
		damage_ratio = 0.75
	var damage := maxi(1, int(float(ctx.base_damage) * damage_ratio))
	var hit_uids: Dictionary = {}
	for cell in cells:
		var target := ctx.state.get_unit_at(cell)
		if target == null or not target.alive or target.uid == ctx.attacker.uid or hit_uids.has(target.uid):
			continue
		hit_uids[target.uid] = true
		var dealt := CombatRules.apply_damage(ctx.state, target, damage, ctx.attacker.uid, "light_beam" if reason.is_empty() else reason)
		if dealt > 0:
			ctx.push_damage_event(target.pos, dealt)
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, target.uid, dealt)
			StatusRules.apply_light_exposed(ctx.state, target, 2 if level >= 3 else 1, ctx.attacker.uid)
			_apply_light_colored_status(ctx, target, gem_ctx)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		var end_cell: Vector2i = cells[cells.size() - 1]
		var blast := GemEffects.explode_cross_at(ctx.state, end_cell, ctx.attacker.uid, {
			"center_damage": Constants.EXPLOSION_CROSS_DAMAGE,
			"gem_tag_context": gem_ctx,
		})
		ctx.events.append_array(blast)


static func _light_beam_cells(state: GameState, from_cell: Vector2i, aim_cell: Vector2i, pierce_blockers: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx := signi(aim_cell.x - from_cell.x)
	var dy := signi(aim_cell.y - from_cell.y)
	if dx == 0 and dy == 0:
		return cells
	var current := from_cell + Vector2i(dx, dy)
	while BoardUtils.in_bounds(state, current):
		cells.append(current)
		var entity := state.get_entity_at(current)
		if not pierce_blockers and entity != null and entity.alive and entity.blocks_projectile():
			break
		current += Vector2i(dx, dy)
	return cells


static func _light_beam_color(gem_ctx: Dictionary) -> Color:
	if GemTagResolver.has_tag(gem_ctx, "fire"):
		return Color(1.0, 0.24, 0.12, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "poison"):
		return Color(0.32, 1.0, 0.34, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		return Color(1.0, 0.92, 0.22, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "ice"):
		return Color(0.55, 0.9, 1.0, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		return Color(1.0, 0.58, 0.18, 1.0)
	return Color(1.0, 0.96, 0.58, 1.0)


static func _apply_light_colored_status(ctx: AttackContext, target: UnitState, gem_ctx: Dictionary) -> void:
	if GemTagResolver.has_tag(gem_ctx, "poison"):
		StatusRules.apply_poison(ctx.state, target, 1, 0, ctx.attacker.uid)
	if GemTagResolver.has_tag(gem_ctx, "fire"):
		StatusRules.apply_burning(ctx.state, target, 1, ctx.attacker.uid)
	if GemTagResolver.has_tag(gem_ctx, "ice"):
		GemEffects.apply_ice_hit_effect(ctx.state, target, ctx.attacker.uid, GemTagResolver.tag_level(gem_ctx, "ice"))
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		GemEffects.apply_arc_bounce_from_victim(ctx.state, target, ctx.attacker, ctx.base_damage, ctx.events, gem_ctx)


static func _apply_red_counter(ctx: AttackContext) -> void:
	if ctx.target == null or not ctx.target.alive:
		return
	var key := "damaged_by:%s:%s:%d" % [ctx.attacker.uid, ctx.target.uid, ctx.state.turn_index]
	if not bool(ctx.state.battle_temp_flags.get(key, false)):
		return
	var once_key := "counter_red_used:%s:%s:%d" % [ctx.attacker.uid, ctx.target.uid, ctx.state.turn_index]
	if bool(ctx.state.battle_temp_flags.get(once_key, false)):
		return
	ctx.state.battle_temp_flags[once_key] = true
	var dealt := CombatRules.apply_damage(ctx.state, ctx.target, ctx.base_damage, ctx.attacker.uid, "counter_red")
	if dealt > 0:
		ctx.push_damage_event(ctx.target.pos, dealt)


static func _add_attack_tags_from_red_profile(ctx: AttackContext, profile: String) -> void:
	match profile:
		"explosion":
			ctx.add_tag(TAG_EXPLOSIVE)
		"poison":
			ctx.add_tag(TAG_POISON)
		"gravity":
			ctx.add_tag(TAG_GRAVITY_AURA)
		"arc":
			ctx.add_tag(TAG_ARC)
		"fire_gem":
			ctx.add_tag(TAG_FIRE_ON_HIT)
			ctx.add_tag(TAG_FIRE_TILE)
		"ice":
			ctx.add_tag(TAG_SLOW_ON_HIT)
			ctx.add_tag(TAG_SLOW_SELF)
		"split":
			ctx.add_tag(TAG_SPLIT_SHOT)
		"light":
			ctx.add_tag(TAG_LIGHT_BEAM)
		"counter":
			ctx.add_tag(TAG_COUNTER)
		"echo":
			ctx.add_tag(TAG_ECHO)


static func _gem_hooks_prepare(ctx: AttackContext) -> void:
	var gem_ctx := GemTagResolver.build_context(
		ctx.state,
		ctx.attacker,
		Constants.SLOT_RED,
		GemEffects.TIMING_ACTIVE
	)
	ctx.payload["gem_tag_context"] = gem_ctx
	for slot in ctx.attacker.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		_add_attack_tags_from_red_profile(
			ctx,
			_ability_profile(gem, GemEffects.ABILITY_UNIT_RED_ACTIVE)
		)
	_apply_red_echo(ctx, gem_ctx)
	if not ctx.has_tag(TAG_SPLIT_SHOT):
		var registry := _relic_effect_registry()
		var split_bonus: int = int(registry.query_modifier("attack_split_count", ctx.state)) if registry != null else 0
		if split_bonus > 0:
			ctx.add_tag(TAG_SPLIT_SHOT)


static func _apply_red_echo(ctx: AttackContext, gem_ctx: Dictionary) -> void:
	if not GemTagResolver.has_tag(gem_ctx, "echo"):
		return
	var once_key := "echo_red_used:%s:%d" % [ctx.attacker.uid, ctx.state.turn_index]
	if bool(ctx.state.battle_temp_flags.get(once_key, false)):
		return
	ctx.state.battle_temp_flags[once_key] = true
	for tag in GemEchoRules.resolve_echo_tags(ctx.state, gem_ctx, "echo_red_%s_%d" % [ctx.attacker.uid, ctx.state.turn_index]):
		_add_attack_tags_from_tag(ctx, tag)
	ctx.push_event({"type": "gem_flash", "pos": ctx.attacker.pos, "color": Color(0.7, 0.55, 1.0)})


static func _add_attack_tags_from_tag(ctx: AttackContext, tag: String) -> void:
	match tag:
		"explosion":
			ctx.add_tag(TAG_EXPLOSIVE)
		"poison":
			ctx.add_tag(TAG_POISON)
		"gravity":
			ctx.add_tag(TAG_GRAVITY_AURA)
		"arc":
			ctx.add_tag(TAG_ARC)
		"fire":
			ctx.add_tag(TAG_FIRE_ON_HIT)
			ctx.add_tag(TAG_FIRE_TILE)
		"ice":
			ctx.add_tag(TAG_SLOW_ON_HIT)
			ctx.add_tag(TAG_SLOW_SELF)
		"split":
			ctx.add_tag(TAG_SPLIT_SHOT)
		"light":
			ctx.add_tag(TAG_LIGHT_BEAM)
		"counter":
			ctx.add_tag(TAG_COUNTER)


static func _apply_ice_self_slow(ctx: AttackContext) -> void:
	ctx.push_event({"type": "frost_pulse", "pos": ctx.attacker.pos})
	StatusRules.apply_slowed(ctx.state, ctx.attacker, 1, ctx.attacker.uid)


static func _try_deflect(ctx: AttackContext) -> void:
	if ctx.target == null:
		return
	for slot in ctx.target.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLUE) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if _ability_profile(gem, GemEffects.ABILITY_BLUE_DAMAGED) != "gravity":
			continue
		var gem_ctx := GemTagResolver.build_context(
			ctx.state,
			ctx.target,
			Constants.SLOT_BLUE,
			GemEffects.TIMING_OWNER_DAMAGED,
			slot
		)
		var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "gravity"))
		var chance := 0.5
		if level >= 3:
			chance = 1.0
		elif level >= 2:
			chance = 0.75
		var rng := _rng_service()
		if rng == null or not bool(rng.chance("pipeline_gravity_deflect_%s" % ctx.target.uid, chance)):
			break
		var candidates: Array[UnitState] = []
		for neighbor in BoardUtils.neighbors4(ctx.target.pos):
			var hit := ctx.state.get_unit_at(neighbor)
			if hit != null and hit.alive and hit.uid != ctx.attacker.uid:
				if level >= 2 and hit.team == ctx.target.team:
					continue
				candidates.append(hit)
		if candidates.is_empty():
			var neighbors := BoardUtils.neighbors4(ctx.target.pos)
			var land: Vector2i = neighbors[int(rng.roll_int("pipeline_gravity_land_%s" % ctx.target.uid, 0, neighbors.size() - 1))]
			ctx.state.log("%s 被引力偏转，投射物落地 %s" % [ctx.target.uid, land])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": land})
			ctx.add_tag(TAG_DEFLECT_DONE)
		else:
			var new_target: UnitState = candidates[int(rng.roll_int("pipeline_gravity_redirect_%s" % ctx.target.uid, 0, candidates.size() - 1))]
			ctx.state.log("%s 被引力偏转，投射物转向 %s" % [ctx.target.uid, new_target.uid])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": new_target.pos})
			ctx.target = new_target
			ctx.aim_cell = new_target.pos
		break


static func _random_adjacent_cells(
	state: GameState,
	center: Vector2i,
	count: int,
	rng_key: String
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in BoardUtils.neighbors4(center):
		if BoardUtils.in_bounds(state, cell):
			cells.append(cell)
	if cells.is_empty() or count <= 0:
		return []
	var rng := _rng_service()
	if rng == null:
		return cells.slice(0, mini(count, cells.size()))
	rng.shuffle_in_place(rng_key, cells)
	return cells.slice(0, mini(count, cells.size()))


static func _gem_hooks_on_kill(ctx: AttackContext) -> void:
	pass


static func _try_apply_chaos_launcher_at_cell(
	ctx: AttackContext,
	hit_cell: Vector2i,
	hit_unit: UnitState
) -> void:
	if ctx.attacker.uid != ctx.state.player_uid:
		return
	var registry := _relic_effect_registry()
	if registry == null or not bool(registry.query_modifier("chaos_launcher_active", ctx.state)):
		return
	_apply_chaos_launcher_effect(ctx, hit_cell, hit_unit)


static func _apply_chaos_launcher_effect(
	ctx: AttackContext,
	hit_cell: Vector2i,
	hit_unit: UnitState
) -> void:
	var rng := _rng_service()
	if rng == null:
		return
	var effects: Array[String] = ["poison", "burning", "arc_proc", "fire_on_hit", "slow"]
	if hit_unit == null or not hit_unit.alive:
		effects = ["poison", "fire_on_hit"]
	var roll_key := "chaos_launcher_%d_%d_%d" % [ctx.state.turn_index, hit_cell.x, hit_cell.y]
	var pick: int = int(rng.roll_int(roll_key, 0, effects.size() - 1))
	var picked: String = effects[pick]
	var applied: bool = false
	match picked:
		"poison":
			_apply_poison_at_cell(ctx, hit_cell, hit_unit)
			applied = true
		"burning":
			if hit_unit != null and hit_unit.alive:
				StatusRules.apply_burning(ctx.state, hit_unit, 1, ctx.attacker.uid)
				applied = true
		"arc_proc":
			if hit_unit != null and hit_unit.alive:
				GemEffects.apply_arc_bounce_from_victim(
					ctx.state, hit_unit, ctx.attacker, ctx.base_damage, ctx.events
				)
				applied = true
		"fire_on_hit":
			_apply_fire_tile_at_cell(ctx, hit_cell)
			applied = true
		"slow":
			if hit_unit != null and hit_unit.alive:
				GemEffects.apply_ice_hit_effect(ctx.state, hit_unit, ctx.attacker.uid)
				applied = true
	if not applied:
		return
	var log_target: String = hit_unit.uid if hit_unit != null else str(hit_cell)
	ctx.state.log("[Relic] relic_chaos_launcher -> %s 附加 %s" % [log_target, picked])


static func _apply_crowbar_break(ctx: AttackContext, target: UnitState, break_damage: int) -> void:
	if target == null or not target.alive:
		return
	for slot in target.slots:
		if not slot.locked or slot.lock_type != Constants.LOCK_ARMOR:
			continue
		var dealt := CombatRules.apply_damage(ctx.state, target, break_damage, ctx.attacker.uid, "crowbar_break")
		if dealt > 0:
			ctx.push_damage_event(target.pos, dealt)
		StatusRules.apply_exposed(ctx.state, target, slot, ctx.state.turn_index)


static func compute_split_wing_cells(attacker_pos: Vector2i, aim_pos: Vector2i) -> Array[Vector2i]:
	return SplitShotRules.wing_cells(attacker_pos, aim_pos)


static func _push_projectile_event(ctx: AttackContext, from_pos: Vector2i, to_pos: Vector2i) -> void:
	ctx.push_event({
		"type": "projectile",
		"from": from_pos,
		"to": to_pos,
	})


static func _apply_split_wings(ctx: AttackContext) -> void:
	var origin := SplitShotRules.attacker_origin(ctx.attacker, ctx.aim_cell)
	var forbidden := ctx.attacker.occupied_cells()
	var wing_cells := SplitShotRules.wing_cells(origin, ctx.aim_cell, forbidden, _split_level(ctx))
	for wing_pos in wing_cells:
		if not BoardUtils.in_bounds(ctx.state, wing_pos):
			continue
		var wing_from := BoardUtils.projectile_origin_cell(ctx.attacker, wing_pos)
		_push_projectile_event(ctx, wing_from, wing_pos)
		var wing_target := ctx.state.get_unit_at(wing_pos)
		if wing_target != null and (not wing_target.alive or wing_target.uid == ctx.attacker.uid):
			wing_target = null
		_apply_tags_at_cell(ctx, wing_pos, wing_target, "split_wing")


static func _split_level(ctx: AttackContext) -> int:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	return maxi(1, GemTagResolver.tag_level(gem_ctx, "split"))


static func _split_red_damage_ratio(ctx: AttackContext) -> float:
	var level := _split_level(ctx)
	if level >= 3:
		return 0.3
	if level >= 2:
		return 0.5
	return Constants.SPLIT_ATTACK_DAMAGE_RATIO


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
	state.unbind_combat_events()
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
