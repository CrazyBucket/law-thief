class_name AttackPipeline
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const EntityRules = preload("res://scripts/rules/entity_rules.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const LightBeamRules = preload("res://scripts/rules/light_beam_rules.gd")
const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")
const AttackContext = preload("res://scripts/rules/attack_context.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")
const ShieldRules = preload("res://scripts/rules/shield_rules.gd")
const FootprintRules = preload("res://scripts/rules/footprint_rules.gd")


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
const TAG_NO_KILL_PROC := "no_kill_proc"
const TAG_SPLIT_SHOT   := "split_shot"
const TAG_LIGHT_BEAM   := "light_beam"
const TAG_COUNTER      := "counter"
const TAG_ECHO         := "echo"

const PROFILE_TAG_ALIASES: Dictionary = {
	"fire_gem": "fire",
}

const ATTACK_TAGS_BY_GEM_TAG: Dictionary = {
	"explosion": [TAG_EXPLOSIVE],
	"poison": [TAG_POISON],
	"gravity": [TAG_GRAVITY_AURA],
	"arc": [TAG_ARC],
	"fire": [TAG_FIRE_ON_HIT, TAG_FIRE_TILE],
	"ice": [TAG_SLOW_ON_HIT, TAG_SLOW_SELF],
	"split": [TAG_SPLIT_SHOT],
	"light": [TAG_LIGHT_BEAM],
	"counter": [TAG_COUNTER],
	"echo": [TAG_ECHO],
}

const HIT_TAG_HANDLERS: Array[Dictionary] = [
	{"tag": TAG_EXPLOSIVE, "handler": "_apply_explosion_hit_tag"},
	{"tag": TAG_POISON, "handler": "_apply_poison_hit_tag"},
	{"tag": TAG_FIRE_TILE, "handler": "_apply_fire_tile_hit_tag"},
	{"tag": TAG_FIRE_ON_HIT, "handler": "_apply_fire_on_hit_tag"},
	{"tag": TAG_SLOW_ON_HIT, "handler": "_apply_slow_on_hit_tag"},
	{"tag": TAG_ARC, "handler": "_apply_arc_hit_tag"},
]


## 以瞄准格为唯一空间锚点执行攻击（空地 / 单位共用）
static func execute_aimed(
	state: GameState,
	attacker: UnitState,
	aim_cell: Vector2i,
	initial_tags: Array[String] = [],
	payload: Dictionary = {},
	max_range: int = -1
) -> Dictionary:
	if not attacker.alive:
		return _fail("攻击者无效")
	if not bool(payload.get("ignore_attack_block", false)) and not StatusRules.can_attack(attacker):
		return _fail(StatusRules.attack_block_reason(attacker))
	if max_range < 0:
		max_range = CombatConfig.attack_range()
	max_range = GemEffects.red_attack_range(state, attacker, max_range)
	if GemEffects.unit_has_red_light(state, attacker) and not GemEffects.is_valid_light_aim(attacker, aim_cell):
		return _fail("光束只能朝八个方向发射")
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
	GemEffects.begin_explosion_reaction_chain()
	state.bind_combat_events(ctx.events)

	var target_uid := ""
	if target != null:
		target_uid = target.uid
	state.on_attack_prepare.emit(attacker.uid, target_uid, ctx.tags.duplicate())
	_phase_prepare(ctx)
	if target != null and not ctx.target.alive:
		return _finish_execute(state, ctx, _ok(ctx.events))
	# 光束不是可偏转投射物；它只受墙和边界截断。
	if ctx.has_tag(TAG_RANGED) and ctx.target != null and not ctx.has_tag(TAG_LIGHT_BEAM):
		_try_deflect(ctx)
	if ctx.has_tag(TAG_DEFLECT_DONE):
		if ctx.has_tag(TAG_SPLIT_SHOT) and not ctx.has_tag(TAG_LIGHT_BEAM):
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
	ctx.push_trace({
		"phase": "damage_calculate",
		"operation": "attack_damage",
		"base_attack": ctx.attacker.base_attack,
		"result": ctx.base_damage,
	})
	var charge_bonus: int = int(ctx.payload.get("charge_bonus", 0))
	if charge_bonus > 0:
		ctx.base_damage += charge_bonus
		ctx.push_trace({"phase": "damage_calculate", "operation": "add_charge_bonus", "value": charge_bonus, "result": ctx.base_damage})
	var bonus_damage: int = int(ctx.payload.get("bonus_damage", 0))
	if bonus_damage > 0:
		ctx.base_damage += bonus_damage
		ctx.push_trace({"phase": "damage_calculate", "operation": "add_bonus_damage", "value": bonus_damage, "result": ctx.base_damage})
	if ctx.has_tag(TAG_SPLIT_SHOT):
		var split_red_ratio := GemEffects.split_red_damage_ratio(
			ctx.state,
			ctx.attacker,
			ctx.payload.get("gem_tag_context", {})
		)
		ctx.base_damage = GemEffects.red_split_damage(ctx.state, ctx.attacker, ctx.base_damage, ctx.payload.get("gem_tag_context", {}))
		ctx.push_trace({
			"phase": "damage_calculate",
			"operation": "multiply_split_red_ratio",
			"gem_level": _split_level(ctx),
			"value": split_red_ratio,
			"rounding": "floor_then_min_1",
			"result": ctx.base_damage,
		})

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

	var hit_cell := ctx.aim_cell
	if ctx.has_tag(TAG_RANGED):
		var from_cell := BoardUtils.projectile_origin_cell(ctx.attacker, ctx.aim_cell)
		var ignore_projectile_blockers := bool(ctx.payload.get("ignore_projectile_blockers", false))
		if not ctx.has_tag(TAG_SPLIT_SHOT) and not ignore_projectile_blockers:
			hit_cell = BoardUtils.resolve_projectile_impact(ctx.state, from_cell, ctx.aim_cell)
		_push_projectile_event(ctx, from_cell, hit_cell)
		ctx.target = _resolve_unit_at_aim(ctx.state, ctx.attacker, hit_cell)
	ctx.attacker.facing = UnitState.facing_from_unit_to_cell(ctx.attacker, hit_cell)

	_apply_tags_at_cell(ctx, hit_cell, ctx.target, reason)

static func _phase_post_attack(ctx: AttackContext) -> void:
	var killed := ctx.target != null and not ctx.target.alive

	if ctx.has_tag(TAG_SPLIT_SHOT) and not ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_split_wings(ctx)

	if ctx.has_tag(TAG_GRAVITY_AURA) and not ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_gravity_aura(ctx)

	if ctx.has_tag(TAG_SLOW_SELF) and not ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_ice_self_slow(ctx)

	if ctx.has_tag(TAG_COUNTER) and not ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_red_counter(ctx)

	if ctx.has_tag(TAG_ECHO) and not ctx.has_tag(TAG_LIGHT_BEAM):
		_apply_red_echo_followup(ctx)

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
	if not gem_ctx.is_empty():
		ctx.push_trace({
			"phase": "hit",
			"operation": "resolve_gem_context",
			"hit_cell": hit_cell,
			"tag_counts": gem_ctx.get("tag_counts", {}),
			"tag_levels": gem_ctx.get("tag_levels", {}),
			"combos": gem_ctx.get("combos", []),
		})
		if ctx.has_tag(TAG_EXPLOSIVE):
			ctx.push_trace({
				"phase": "hit",
				"operation": "resolve_explosion_damage",
				"attack_damage": ctx.base_damage,
				"base_attack": ctx.attacker.base_attack,
				"center_damage": GemEffects.red_explosion_center_damage(ctx.base_damage, gem_ctx),
				"splash_damage": GemEffects.red_explosion_splash_damage(ctx.attacker.base_attack, gem_ctx),
			})
	var dealt := 0
	if target != null and target.alive:
		dealt = ctx.damage_unit(target, ctx.base_damage, reason, {"pos": hit_cell, "active_attack": true})
		if dealt > 0:
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, target.uid, dealt)
			_apply_direct_hit_extras(ctx, target)
	else:
		var entity := ctx.state.get_entity_at(hit_cell)
		if entity != null and entity.alive and entity.max_hp > 0:
			EntityRules.damage_entity(ctx.state, entity, ctx.base_damage, ctx.attacker.uid, ctx.events)

	var hit_unit := _resolve_unit_at_aim(ctx.state, ctx.attacker, hit_cell)
	var had_burning_before := hit_unit != null and hit_unit.has_status(Constants.STATUS_BURNING)

	for entry in HIT_TAG_HANDLERS:
		var tag := str(entry.get("tag", ""))
		if tag.is_empty() or not ctx.has_tag(tag):
			continue
		var handler := str(entry.get("handler", ""))
		_apply_hit_tag_handler(ctx, handler, hit_cell, hit_unit, gem_ctx, had_burning_before)
		hit_unit = _resolve_unit_at_aim(ctx.state, ctx.attacker, hit_cell)

	if ctx.has_tag(TAG_POISON) and ctx.has_tag(TAG_FIRE_TILE):
		GemComboResolver.apply_after_attack_hit(ctx.state, hit_cell, gem_ctx, ctx.events)

	_try_apply_chaos_launcher_at_cell(ctx, hit_cell, hit_unit)

static func _apply_hit_tag_handler(
	ctx: AttackContext,
	handler: String,
	hit_cell: Vector2i,
	hit_unit: UnitState,
	gem_ctx: Dictionary,
	had_burning_before: bool
) -> void:
	match handler:
		"_apply_explosion_hit_tag":
			_apply_cross_explosion_at(ctx, hit_cell)
		"_apply_poison_hit_tag":
			_apply_poison_at_cell(ctx, hit_cell, hit_unit, gem_ctx)
		"_apply_fire_tile_hit_tag":
			_apply_fire_tile_at_cell(ctx, hit_cell, hit_unit, gem_ctx, had_burning_before)
		"_apply_fire_on_hit_tag":
			if hit_unit != null and hit_unit.alive:
				StatusRules.apply_burning(ctx.state, hit_unit, 1, ctx.attacker.uid)
		"_apply_slow_on_hit_tag":
			if hit_unit != null and hit_unit.alive:
				GemEffects.apply_ice_hit_effect(
					ctx.state,
					hit_unit,
					ctx.attacker.uid,
					GemTagResolver.tag_level(gem_ctx, "ice")
				)
		"_apply_arc_hit_tag":
			_apply_arc_at_cell(ctx, hit_cell, hit_unit, gem_ctx)

static func _apply_arc_at_cell(
	ctx: AttackContext,
	hit_cell: Vector2i,
	hit_unit: UnitState,
	gem_ctx: Dictionary
) -> void:
	var hit_tile := ctx.state.get_tile(hit_cell)
	if hit_tile != null and hit_tile.has_tile_tag(Constants.TAG_TILE_WATER):
		GemEffects.apply_water_conduction(ctx.state, hit_cell, ctx.attacker, ctx.events, gem_ctx)
	elif hit_unit != null and hit_unit.alive:
		GemEffects.apply_arc_bounce_from_victim(
			ctx.state,
			hit_unit,
			ctx.attacker,
			ctx.base_damage,
			ctx.events,
			gem_ctx
		)

static func _apply_direct_hit_extras(ctx: AttackContext, target: UnitState) -> void:
	if target == null or not target.alive:
		return
	_ContactResolver.on_attack_contact(ctx.state, ctx.attacker, target)
	if ctx.has_tag(TAG_KNOCKBACK) and target.alive:
		var knockback_origin := FootprintRules.nearest_cell_to(ctx.attacker, target.pos, ctx.attacker.pos)
		_Displacement.knockback(
			ctx.state,
			target,
			knockback_origin,
			1,
			ctx.attacker.uid,
			ctx.events,
			-1,
			false,
			ctx.build_damage_context("knockback_collision")
		)
	if ctx.attacker.uid == ctx.state.player_uid and target.alive:
		var _registry := _relic_effect_registry()
		if _registry != null:
			var break_bonus: int = int(_registry.query_modifier("armor_break_bonus", ctx.state))
			if break_bonus > 0:
				_apply_crowbar_break(ctx, target, break_bonus)

static func _apply_poison_at_cell(
	ctx: AttackContext,
	cell: Vector2i,
	unit: UnitState,
	gem_ctx: Dictionary = {}
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var level_def := _effect_level_def("poison", Constants.SLOT_RED, level)
	var fog_pattern := str(level_def["fog_pattern"])
	var duration := CombatConfig.poison_fog_duration() + int(level_def["duration_bonus"])
	var burst := {"type": "poison_burst", "pos": cell, "radius": 0, "duration": duration}
	if fog_pattern == "cross":
		burst["pattern"] = "cross"
	ctx.push_event(burst)
	if BoardUtils.in_bounds(ctx.state, cell):
		TileRules.begin_overlay_batch(ctx.state)
		TileRules.create_poison_fog(ctx.state, cell, duration)
		if fog_pattern == "cross":
			for neighbor in BoardUtils.neighbors4(cell):
				if BoardUtils.in_bounds(ctx.state, neighbor):
					TileRules.create_poison_fog(ctx.state, neighbor, duration)
		TileRules.end_overlay_batch(ctx.state)
	if unit != null and unit.alive:
		StatusRules.apply_poison(
			ctx.state,
			unit,
			int(level_def["hit_poison_stacks"]),
			int(level_def["hit_poison_duration"]),
			ctx.attacker.uid
		)

static func _apply_fire_tile_at_cell(
	ctx: AttackContext,
	cell: Vector2i,
	_unit: UnitState = null,
	gem_ctx: Dictionary = {},
	had_burning_before: bool = false
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "fire"))
	var level_def := _effect_level_def("fire", Constants.SLOT_RED, level)
	ctx.push_event({"type": "fire_burst", "pos": cell})
	TileRules.begin_overlay_batch(ctx.state)
	TileRules.create_fire(ctx.state, cell)
	var spread_count := int(level_def["spread_count"])
	if had_burning_before:
		spread_count += int(level_def["burning_bonus_spread_count"])
	if spread_count > 0:
		for spread_cell in _random_adjacent_cells(ctx.state, cell, spread_count, "fire_spread_%d_%d" % [cell.x, cell.y]):
			TileRules.create_fire(ctx.state, spread_cell)
			ctx.push_event({"type": "fire_burst", "pos": spread_cell, "spread": true})
	TileRules.end_overlay_batch(ctx.state)

static func _apply_cross_explosion_at(ctx: AttackContext, center: Vector2i) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var blast_pattern := GemEffects.explosion_blast_pattern(gem_ctx)
	var center_damage := GemEffects.red_explosion_center_damage(ctx.base_damage, gem_ctx)
	var splash_damage := GemEffects.red_explosion_splash_damage(ctx.attacker.base_attack, gem_ctx)
	if blast_pattern == "square":
		var square_events := GemEffects.explode_square_at(
			ctx.state,
			center,
			ctx.attacker.uid,
			splash_damage,
			gem_ctx,
			{"center_damage": center_damage}
		)
		for ev in square_events:
			ctx.events.append(ev)
		return
	var opts: Dictionary = {
		"center_damage": center_damage,
		"cross_damage": splash_damage,
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
	if ctx.target == null or not ctx.target.alive or ctx.target.uid == ctx.attacker.uid:
		return
	var level := maxi(1, GemTagResolver.tag_level(ctx.payload.get("gem_tag_context", {}), "gravity"))
	var level_def := _effect_level_def("gravity", Constants.SLOT_RED, level)
	ctx.events.append_array(
		GemEffects.pull_unit_toward_with_events(
			ctx.state,
			ctx.target,
			FootprintRules.nearest_cell_to(ctx.attacker, ctx.target.pos, ctx.attacker.pos),
			int(level_def["pull_steps"]),
			ctx.attacker.uid,
			DamageContext.create(
				ctx.attacker.uid,
				"gravity_collision",
				["gravity"],
				ctx.payload.get("gem_tag_context", {})
			)
		)
	)


static func _apply_light_beam(ctx: AttackContext, reason: String) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "light"))
	var hit_entity_uids: Dictionary = {}
	for path in LightBeamRules.compute_paths(
		ctx.state,
		ctx.attacker,
		ctx.attacker.pos,
		ctx.aim_cell,
		gem_ctx,
		ctx.has_tag(TAG_SPLIT_SHOT)
	):
		_apply_single_light_beam(
			ctx,
			reason,
			gem_ctx,
			level,
			path.get("from", ctx.attacker.pos),
			path.get("cells", [] as Array[Vector2i]),
			hit_entity_uids
		)
static func _apply_single_light_beam(
	ctx: AttackContext,
	reason: String,
	gem_ctx: Dictionary,
	level: int,
	from_cell: Vector2i,
	cells: Array[Vector2i],
	hit_entity_uids: Dictionary = {}
) -> void:
	var level_def := _effect_level_def("light", Constants.SLOT_RED, level)
	if cells.is_empty():
		return
	var hit_effects: Array[Dictionary] = []
	var preview_ctx := gem_ctx.duplicate(true)
	var preview_hit_uids: Dictionary = {}
	for cell in cells:
		var preview_dye := GemEffects.light_dye_element_at(ctx.state, cell)
		if not preview_dye.is_empty():
			preview_ctx = GemEffects.light_context_with_dye(preview_ctx, preview_dye)
		var preview_target := ctx.state.get_unit_at(cell)
		if preview_target == null or not preview_target.alive or preview_target.uid == ctx.attacker.uid or preview_hit_uids.has(preview_target.uid):
			continue
		preview_hit_uids[preview_target.uid] = true
		hit_effects.append({
			"cell": preview_target.pos,
			"color": GemEffects.light_color_for_context(preview_ctx),
		})
	var beam_width := GemEffects.light_beam_width_for_level(level)
	var beam_event := GemEffects.build_light_beam_event(
		from_cell,
		cells[cells.size() - 1],
		gem_ctx,
		beam_width,
		{
			"cells": cells,
			"dye_transitions": GemEffects.light_dye_transitions(ctx.state, cells),
			"hit_effects": hit_effects,
			"end_color": GemEffects.light_color_for_context(preview_ctx),
			"power": float(level_def["beam_power"]),
			"source_uid": ctx.attacker.uid,
		}
	)
	ctx.push_event(beam_event)
	var beam_hit_event_start := ctx.events.size()
	var exposed_stacks := int(level_def["exposed_stacks"])
	var damage := GemEffects.red_light_damage(ctx.state, ctx.attacker, ctx.base_damage, gem_ctx)
	var hit_uids: Dictionary = {}
	var traveled_ctx := gem_ctx.duplicate(true)
	for cell in cells:
		var dye := GemEffects.light_dye_element_at(ctx.state, cell)
		if not dye.is_empty():
			traveled_ctx = GemEffects.light_context_with_dye(traveled_ctx, dye)
		var hit_entity := ctx.state.get_entity_at(cell)
		if hit_entity != null and hit_entity.alive and hit_entity.max_hp > 0 and not hit_entity_uids.has(hit_entity.uid):
			hit_entity_uids[hit_entity.uid] = true
			EntityRules.damage_entity(ctx.state, hit_entity, damage, ctx.attacker.uid, ctx.events)
		var target := ctx.state.get_unit_at(cell)
		if target == null or not target.alive or target.uid == ctx.attacker.uid or hit_uids.has(target.uid):
			continue
		hit_uids[target.uid] = true
		var dealt := ctx.damage_unit(target, damage, "light_beam" if reason.is_empty() else reason, {
			"pos": target.pos,
			"gem_tag_context": traveled_ctx,
			"active_attack": true,
		})
		if dealt > 0:
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, target.uid, dealt)
			StatusRules.apply_light_exposed(ctx.state, target, exposed_stacks, ctx.attacker.uid)
		GemEffects.apply_light_colored_status(
			ctx.state,
			target,
			ctx.attacker,
			traveled_ctx,
			ctx.events,
			ctx.base_damage
		)
	for event_index in range(beam_hit_event_start, ctx.events.size()):
		var hit_event: Dictionary = ctx.events[event_index]
		if str(hit_event.get("type", "")) == "damage":
			hit_event["visual_group"] = "light_beam"
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		var end_cell: Vector2i = cells[cells.size() - 1]
		var blast := GemEffects.explode_cross_at(ctx.state, end_cell, ctx.attacker.uid, {
			"center_damage": GemEffects.red_explosion_center_damage(ctx.base_damage, gem_ctx),
			"cross_damage": GemEffects.red_explosion_splash_damage(ctx.attacker.base_attack, gem_ctx),
			"gem_tag_context": gem_ctx,
		})
		ctx.events.append_array(blast)


static func _apply_red_counter(ctx: AttackContext) -> void:
	if ctx.target == null or not ctx.target.alive:
		return
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "counter"))
	var level_def := _effect_level_def("counter", Constants.SLOT_RED, level)
	StatusRules.apply_counter_mark(
		ctx.state,
		ctx.target,
		ctx.attacker.uid,
		level_def,
		ctx.attacker.uid
	)


static func _apply_red_echo_followup(ctx: AttackContext) -> void:
	var gem_ctx: Dictionary = ctx.payload.get("gem_tag_context", {})
	if gem_ctx.is_empty() or not GemTagResolver.has_tag(gem_ctx, "echo"):
		return
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	if echo_level < 3 or ctx.target == null or not ctx.target.alive:
		return
	var once_key := "echo_red_followup:%s:%s:%d" % [ctx.attacker.uid, ctx.target.uid, ctx.state.turn_index]
	if bool(ctx.state.battle_temp_flags.get(once_key, false)):
		return
	ctx.state.battle_temp_flags[once_key] = true
	var level_def := _effect_level_def("echo", Constants.SLOT_RED, echo_level)
	var followup_ratio := float(level_def["followup_ratio"])
	var dealt := ctx.damage_unit(
		ctx.target,
		maxi(1, int(ceil(float(ctx.base_damage) * followup_ratio))),
		"echo_red"
	)
	if dealt > 0:
		ctx.push_event({"type": "gem_flash", "pos": ctx.attacker.pos, "echo_followup": true})


static func _add_attack_tags_from_profile(ctx: AttackContext, profile: String) -> void:
	_add_attack_tags_from_tag(ctx, _gem_tag_from_profile(profile))


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
		_add_attack_tags_from_profile(
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
	for attack_tag in ATTACK_TAGS_BY_GEM_TAG.get(tag, []):
		ctx.add_tag(str(attack_tag))


static func _gem_tag_from_profile(profile: String) -> String:
	return str(PROFILE_TAG_ALIASES.get(profile, profile))


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
		var level_def := _effect_level_def("gravity", Constants.SLOT_BLUE, level)
		var chance := float(level_def["deflect_chance"])
		var redirect_enemy_only := bool(level_def["redirect_enemy_only"])
		var rng := _rng_service()
		if rng == null or not bool(rng.chance("pipeline_gravity_deflect_%s" % ctx.target.uid, chance)):
			break
		var candidates: Array[UnitState] = []
		for neighbor in BoardUtils.neighbors4(ctx.target.pos):
			var hit := ctx.state.get_unit_at(neighbor)
			if hit != null and hit.alive and hit.uid != ctx.attacker.uid:
				if redirect_enemy_only and hit.team == ctx.target.team:
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
			ctx.push_event({"type": "projectile_deflect",
				"from": BoardUtils.projectile_origin_cell(ctx.target, new_target.pos), "to": new_target.pos,
				"source_uid": ctx.target.uid})
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
	ShieldRules.damage(ctx.state, target, break_damage)


static func compute_split_wing_cells(attacker_pos: Vector2i, aim_pos: Vector2i) -> Array[Vector2i]:
	return SplitShotRules.wing_cells(attacker_pos, aim_pos)


static func _push_projectile_event(ctx: AttackContext, from_pos: Vector2i, to_pos: Vector2i) -> void:
	ctx.push_event({"type": "projectile", "from": from_pos, "to": to_pos,
		"source_uid": ctx.attacker.uid})


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


static func _effect_level_def(tag: String, slot_type: String, level: int) -> Dictionary:
	return _data_registry().get_gem_effect_level_def(tag, slot_type, level)


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _finish_execute(state: GameState, ctx: AttackContext, result: Dictionary) -> Dictionary:
	state.unbind_combat_events()
	CombatRules.end_deferred_death_hooks(state)
	GemEffects.end_explosion_reaction_chain()
	if ctx.payload.get("debug_trace", false):
		result["trace"] = ctx.trace
	return result


static func _reorder_split_shot_events(ctx: AttackContext) -> void:
	if not ctx.has_tag(TAG_SPLIT_SHOT):
		return
	if ctx.has_tag(TAG_LIGHT_BEAM):
		var beams: Array[Dictionary] = []
		var beam_damages: Array[Dictionary] = []
		var beam_other: Array[Dictionary] = []
		for ev in ctx.events:
			match str(ev.get("type", "")):
				"light_beam":
					beams.append(ev)
				"damage":
					if str(ev.get("visual_group", "")) == "light_beam":
						beam_damages.append(ev)
					else:
						beam_other.append(ev)
				_:
					beam_other.append(ev)
		ctx.events.clear()
		ctx.events.append_array(beams)
		ctx.events.append_array(beam_damages)
		ctx.events.append_array(beam_other)
		return
	var projs: Array[Dictionary] = []
	var resolution: Array[Dictionary] = []
	for ev in ctx.events:
		match str(ev.get("type", "")):
			"projectile", "projectile_deflect":
				projs.append(ev)
			_:
				resolution.append(ev)
	ctx.events.clear()
	ctx.events.append_array(projs)
	# 只把弹道提升为同一轮齐射；命中后的爆炸、电弧和伤害必须保留原始因果顺序。
	ctx.events.append_array(resolution)


static func _ok(events: Array[Dictionary]) -> Dictionary:
	return {"ok": true, "events": events}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": [] as Array[Dictionary]}
