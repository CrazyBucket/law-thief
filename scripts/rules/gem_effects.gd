class_name GemEffects
extends RefCounted

const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")

const _Displacement = preload("res://scripts/rules/displacement.gd")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")

const TIMING_ACTIVE := "active"
const TIMING_TURN_START := "turn_start"
const TIMING_OWNER_DAMAGED := "owner_damaged"
const TIMING_ON_DEATH := "on_death"
const TIMING_MOVED_THROUGH := "moved_through"
const TIMING_FORCED_MOVE := "forced_move"   # 被强制位移时（击退、引力等）
const TIMING_ON_CONTACT := "on_contact"     # 接触时（碰撞、相邻、攻击）

const MODE_TRIGGER := "trigger"

const ABILITY_UNIT_RED_ACTIVE := "unit_red_active"
const ABILITY_ENEMY_RED_ACTION := "enemy_red_action"
const ABILITY_BLUE_TURN_START := "blue_turn_start"
const ABILITY_BLUE_DAMAGED := "blue_damaged"
const ABILITY_BLUE_MOVE_THROUGH := "blue_move_through"
const ABILITY_BLACK_DEATH := "black_death"
const ABILITY_TILE_TURN_START := "tile_turn_start"
const ABILITY_ATTACK_BONUS := "attack_bonus"
const ABILITY_ARMOR_BONUS := "armor_bonus"


static func run_unit_hooks(state: GameState, unit: UnitState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in unit.slots:
		if slot.slot_type != slot_type or slot.gem_uid.is_empty():
			continue
		_run_slot_hook(state, unit, slot, timing, ctx)


static func run_tile_hooks(state: GameState, tile: TileState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in tile.slots:
		if slot.slot_type != slot_type or slot.gem_uid.is_empty():
			continue
		_run_slot_hook(state, tile, slot, timing, ctx)


static func on_tile_gem_inserted(state: GameState, tile: TileState, slot: SlotState, gem: GemState) -> void:
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("机关柱激活！宝石 %s 产生光环" % gem_name)


static func trigger_tile_gem(state: GameState, tile: TileState, slot: SlotState, out_events: Array[Dictionary] = []) -> bool:
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("触发 %s 地块的 %s" % [tile.tile_id, _gem_id(state, slot)])
		return _run_slot_hook(state, tile, slot, TIMING_TURN_START, {"events": out_events})
	return false


static func trigger_gem(
	state: GameState,
	owner_uid: String,
	slot: SlotState,
	out_events: Array[Dictionary] = [],
	target_uid: String = "",
	target_pos: Vector2i = Vector2i(-1, -1)
) -> bool:
	if slot.slot_type != Constants.SLOT_RED:
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	var owner: UnitState = state.units.get(owner_uid, null)
	if owner == null:
		return false
	return _run_slot_hook(
		state,
		owner,
		slot,
		TIMING_ACTIVE,
		{"events": out_events, "target_uid": target_uid, "target_pos": target_pos}
	)


static func on_unit_death(state: GameState, unit: UnitState, out_events: Array[Dictionary] = []) -> void:
	_behavior_for(unit).on_unit_death(state, unit)
	_run_death_hooks_with_events(state, unit, out_events)


static func trigger_black_death_effects(state: GameState, unit: UnitState, out_events: Array[Dictionary] = []) -> void:
	_run_death_hooks_with_events(state, unit, out_events)


static func _behavior_for(unit: UnitState) -> GDScript:
	return BehaviorRegistry.get_behavior(unit.behavior_id)


static func get_slot_effect_description(gem_ref: Variant, slot_type: String, context: String) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, slot_type, context)


static func get_attack_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0


static func get_armor_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0


## 分裂宝石蓝槽伤害拦截：将部分伤害转移给周围 1 格内随机单位（多格单位按占格外圈计算）
## 无合法转移目标时不减伤
static func intercept_damage_for_split(state: GameState, unit: UnitState, source_uid: String, reason: String, damage: int) -> int:
	if damage <= 0:
		return damage
	var has_split_blue := false
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "split":
			has_split_blue = true
			break
	if not has_split_blue:
		return damage
	if not _behavior_for(unit).should_trigger_split_blue(unit, reason):
		return damage
	var redirect_amount := int(damage * Constants.SPLIT_DAMAGE_REDIRECT_RATIO)
	if redirect_amount <= 0:
		return damage
	var candidates: Array[UnitState] = []
	for other in state.units.values():
		if not other.alive or other.uid == unit.uid:
			continue
		if BoardUtils.is_within_surround(unit, other, Constants.SPLIT_SURROUND_RADIUS):
			candidates.append(other)
	if candidates.is_empty():
		return damage
	var rng := _rng_service()
	if rng == null:
		return damage
	var redirect_target: UnitState = candidates[int(rng.roll_int("gem_split_redirect_%s" % unit.uid, 0, candidates.size() - 1))]
	state.log("%s 分裂宝石将 %d 点伤害转移给 %s" % [unit.uid, redirect_amount, redirect_target.uid])
	CombatRules.apply_damage(state, redirect_target, redirect_amount, source_uid, "split_redirect")
	return damage - redirect_amount


static func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	return _data_registry().get_enemy_red_intent_meta(gem_ref, damage)


static func unit_has_red_arc(state: GameState, unit: UnitState) -> bool:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	return _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == "arc"


static func on_red_action(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	return _behavior_for(unit).execute_red_action(state, unit, intent)


static func cross_explosion_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [center]
	for neighbor in BoardUtils.neighbors4(center):
		cells.append(neighbor)
	return cells


static func resolve_blast_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	if aim_cell is Vector2i:
		return aim_cell
	return fallback


static func unit_has_red_explosion(state: GameState, unit: UnitState) -> bool:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	return _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == "explosion"


static func unit_has_red_split(state: GameState, unit: UnitState) -> bool:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	var player_profile: String = _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE)
	if player_profile == "split":
		return true
	return _ability_profile(gem, ABILITY_ENEMY_RED_ACTION) == "split"


## 红槽爆炸：以 center 为中心，十字四邻各结算一次（同一单位只结算一次）
static func explode_cross_at(
	state: GameState,
	center: Vector2i,
	source_uid: String,
	opts: Dictionary = {}
) -> Array[Dictionary]:
	var center_damage: int = int(opts.get("center_damage", 0))
	var cross_damage: int = int(opts.get("cross_damage", Constants.EXPLOSION_CROSS_DAMAGE))
	var knockback_center: bool = bool(opts.get("knockback_center", false))
	var exclude_unit_uid: String = str(opts.get("exclude_unit_uid", ""))
	var events: Array[Dictionary] = []
	var cells: Array[Vector2i] = cross_explosion_cells(center)
	events.append({"type": "explode", "pos": center, "pattern": "cross", "cells": cells})
	state.log("爆炸宝石十字爆炸于 %s" % center)
	if center_damage > 0:
		var center_unit := state.get_unit_at(center)
		if center_unit != null and center_unit.alive and center_unit.uid != source_uid:
			if exclude_unit_uid.is_empty() or center_unit.uid != exclude_unit_uid:
				var dealt_center := CombatRules.apply_damage(
					state, center_unit, center_damage, source_uid, "explosion_cross"
				)
				if dealt_center > 0:
					events.append(_explosion_damage_event(center_unit, dealt_center, source_uid))
				if knockback_center and center_unit.alive:
					_Displacement.knockback(
						state, center_unit, center, 1, source_uid, events, Constants.KNOCKBACK_COLLISION_DAMAGE, true
					)
	var splashed: Dictionary = {}
	var knockback_targets: Array[UnitState] = []
	for cell in BoardUtils.neighbors4(center):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_unit := state.get_unit_at(cell)
		if hit_unit == null or not hit_unit.alive:
			continue
		if hit_unit.uid == source_uid:
			continue
		if not exclude_unit_uid.is_empty() and hit_unit.uid == exclude_unit_uid:
			continue
		if splashed.has(hit_unit.uid):
			continue
		splashed[hit_unit.uid] = true
		var dealt := CombatRules.apply_damage(state, hit_unit, cross_damage, source_uid, "explosion_cross")
		if dealt > 0:
			events.append(_explosion_damage_event(hit_unit, dealt, source_uid))
		for gem_slot in hit_unit.slots:
			if gem_slot.locked and gem_slot.lock_type == Constants.LOCK_ARMOR:
				StatusRules.apply_exposed(state, hit_unit, gem_slot, state.turn_index)
		if hit_unit.alive:
			knockback_targets.append(hit_unit)
	# knockback 事件统一追加在所有 damage 之后，保证 UI 层可批量并行播放
	for kb_unit in knockback_targets:
		_Displacement.knockback(
			state, kb_unit, center, 1, source_uid, events, Constants.KNOCKBACK_COLLISION_DAMAGE, true
		)
	return events


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	return _explode_at(state, center, damage, source_uid)


static func _explosion_damage_event(unit: UnitState, dealt: int, source_uid: String) -> Dictionary:
	return {
		"type": "damage",
		"pos": unit.pos,
		"damage": dealt,
		"is_crit": false,
		"attacker_uid": source_uid,
	}


static func _explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var hit_uids: Dictionary = {}
	state.log("爆炸于 %s" % [center])
	for cell in BoardUtils.cells_in_radius(center, Constants.EXPLOSION_RADIUS):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_unit := state.get_unit_at(cell)
		if hit_unit == null or not hit_unit.alive:
			continue
		if hit_unit.uid == source_uid:
			continue
		if hit_uids.has(hit_unit.uid):
			continue
		hit_uids[hit_unit.uid] = true
		var dealt := CombatRules.apply_damage(state, hit_unit, damage, source_uid, "explosion")
		if dealt > 0:
			events.append(_explosion_damage_event(hit_unit, dealt, source_uid))
		for slot in hit_unit.slots:
			if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
				StatusRules.apply_exposed(state, hit_unit, slot, state.turn_index)
		if hit_unit.alive and hit_unit.pos != center:
			_Displacement.knockback(state, hit_unit, center, 1, source_uid, events, Constants.KNOCKBACK_COLLISION_DAMAGE, true)
	return events


## 强制位移钩子：携带爆炸宝石的单位被强制位移时自爆
static func on_forced_displacement(state: GameState, unit: UnitState, events: Array[Dictionary]) -> void:
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		# 蓝槽爆炸宝石：被强制位移时引发爆炸
		if slot.slot_type == Constants.SLOT_BLUE and _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "explosion":
			state.log("%s 被强制位移触发爆炸！" % unit.uid)
			events.append({"type": "explode", "pos": unit.pos, "radius": Constants.EXPLOSION_RADIUS})
			events.append_array(_explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid))
			break


static func pull_around(state: GameState, center: Vector2i, pull_range: int, steps: int, source_uid: String = "") -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.pos == center:
			continue
		if BoardUtils.chebyshev(center, unit.pos) > pull_range:
			continue
		pull_unit_toward_with_events(state, unit, center, steps, source_uid)


static func _pull_unit_toward(state: GameState, unit: UnitState, anchor: Vector2i, steps: int, source_uid: String = "") -> void:
	pull_unit_toward_with_events(state, unit, anchor, steps, source_uid)


static func pull_unit_toward_with_events(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String = ""
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not unit.alive or steps <= 0:
		return events
	var start_pos := unit.pos
	var current := unit.pos
	for _i in range(steps):
		if current == anchor:
			break
		var next := BoardUtils.step_toward(current, anchor)
		if next == current:
			break
		if not BoardUtils.in_bounds(state, next):
			break
		if not BoardUtils.unit_footprint_passable(state, unit, next, unit.uid):
			break
		var blocker: UnitState = state.get_unit_at(next)
		if blocker != null:
			events.append_array(_apply_gravity_collision(state, unit, blocker, source_uid))
			break
		var from_pos := unit.pos
		unit.facing = UnitState.facing_from_step(from_pos, next)
		state.move_unit(unit, next)
		TileRules.on_unit_moved_through(state, unit, next)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})
		current = next
	if unit.pos != start_pos:
		TileRules.on_unit_position_changed(state, unit, start_pos)
		var enter_opts := {"forced": true, "source_uid": source_uid}
		TileRules.on_unit_entered(state, unit, start_pos, enter_opts)
		GemEffects.on_forced_displacement(state, unit, events)
	return events


static func _apply_gravity_collision(
	state: GameState,
	mover: UnitState,
	blocker: UnitState,
	source_uid: String
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not mover.alive or not blocker.alive:
		return events
	state.log("%s 与 %s 引力碰撞" % [mover.uid, blocker.uid])
	var mover_dealt := CombatRules.apply_damage(
		state,
		mover,
		Constants.GRAVITY_COLLISION_DAMAGE,
		blocker.uid,
		"gravity_collision"
	)
	var blocker_dealt := CombatRules.apply_damage(
		state,
		blocker,
		Constants.GRAVITY_COLLISION_DAMAGE,
		source_uid if not source_uid.is_empty() else mover.uid,
		"gravity_collision"
	)
	if mover_dealt > 0:
		events.append({"type": "damage", "pos": mover.pos, "damage": mover_dealt, "is_crit": false})
	if blocker_dealt > 0:
		events.append({"type": "damage", "pos": blocker.pos, "damage": blocker_dealt, "is_crit": false})
	return events


static func _run_slot_hook(state: GameState, owner: Variant, slot: SlotState, timing: String, ctx: Dictionary) -> bool:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	if owner is TileState:
		return _run_tile_slot_hook(state, owner as TileState, slot, gem, timing, ctx)
	if owner is UnitState:
		return _run_unit_slot_hook(state, owner as UnitState, slot, gem, timing, ctx)
	return false


static func _run_unit_slot_hook(state: GameState, owner: UnitState, slot: SlotState, gem: GemState, timing: String, ctx: Dictionary) -> bool:
	match timing:
		TIMING_ACTIVE:
			if slot.slot_type != Constants.SLOT_RED:
				return false
			return _run_unit_active_effect(state, owner, slot, gem, ctx)
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_turn_start_effect(state, owner, gem)
		TIMING_OWNER_DAMAGED:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_damaged_effect(state, owner, gem, ctx)
		TIMING_ON_DEATH:
			if slot.slot_type != Constants.SLOT_BLACK:
				return false
			return _run_unit_death_effect(state, owner, gem)
		TIMING_MOVED_THROUGH:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_moved_through_effect(state, owner, gem, ctx)
		TIMING_ON_CONTACT:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_contact_effect(state, owner, gem, ctx)
	return false


static func _run_unit_active_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var out_events: Array[Dictionary] = _events_from_ctx(ctx)
	match _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE):
		"explosion":
			var blast_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var target_unit: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			var exclude_uid := ""
			if target_unit != null and target_unit.alive:
				blast_center = resolve_blast_center(target_unit.pos, ctx.get("target_pos", null))
				exclude_uid = target_unit.uid
			out_events.append_array(
				explode_cross_at(state, blast_center, owner.uid, {"exclude_unit_uid": exclude_uid})
			)
			return true
		"poison":
			var poison_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var poison_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if poison_target != null and poison_target.alive:
				poison_center = resolve_blast_center(poison_target.pos, ctx.get("target_pos", null))
			out_events.append({"type": "poison_burst", "pos": poison_center, "radius": 0})
			if BoardUtils.in_bounds(state, poison_center):
				TileRules.create_poison_fog(state, poison_center)
			if poison_target != null and poison_target.alive:
				StatusRules.apply_poison(state, poison_target, 1, 0, owner.uid)
			return true
		"gravity":
			out_events.append({"type": "gem_flash", "pos": owner.pos, "color": _data_registry().get_gem_color(gem)})
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) > 2:
					continue
				out_events.append_array(pull_unit_toward_with_events(state, unit, owner.pos, 1, owner.uid))
			return true
		"arc":
			var arc_target_uid: String = ctx.get("target_uid", "")
			var arc_anchor: Vector2i = owner.pos
			var arc_target: UnitState = state.units.get(arc_target_uid, null)
			if arc_target != null:
				arc_anchor = arc_target.pos
			var trigger_tile := state.get_tile(arc_anchor)
			if trigger_tile != null and trigger_tile.has_tile_tag(Constants.TAG_TILE_WATER):
				apply_water_conduction(state, arc_anchor, owner, out_events)
			elif arc_target != null and arc_target.alive:
				var arc_base := CombatRules.attack_damage(state, owner)
				_arc_to(state, arc_target, owner.uid, _calc_arc_damage(arc_base), out_events)
				apply_arc_bounce_from_victim(state, arc_target, owner, arc_base, out_events)
			return true
		"fire_gem":
			var fire_pos := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var fire_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if fire_target != null and fire_target.alive:
				fire_pos = resolve_blast_center(fire_target.pos, ctx.get("target_pos", null))
			out_events.append({"type": "fire_burst", "pos": fire_pos})
			TileRules.create_fire(state, fire_pos)
			return true
		"ice":
			out_events.append({"type": "frost_pulse", "pos": owner.pos})
			StatusRules.apply_slowed(state, owner, 1, owner.uid)
			return true
		"split":
			return true
	return false


static func _run_unit_turn_start_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_BLUE_TURN_START):
		"gravity":
			var nearest := _nearest_opponent(state, owner)
			if nearest != null and BoardUtils.chebyshev(owner.pos, nearest.pos) <= 3:
				_pull_unit_toward(state, nearest, owner.pos, 1, owner.uid)
			return true
		"explosion":
			for cell in BoardUtils.neighbors4(owner.pos):
				var target := state.get_unit_at(cell)
				if target != null and target.alive and target.team != owner.team:
					CombatRules.apply_damage(state, target, 1, owner.uid, "blue_explosion_aura")
					break
			return true
	return false


static func _run_unit_damaged_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var reason: String = ctx.get("reason", "")
	var source_uid: String = ctx.get("source_uid", "")
	var damage: int = ctx.get("damage", 0)
	var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"explosion":
			if reason == "burning" or reason == "tile_fire":
				state.log("%s 被火焰点燃引爆！" % owner.uid)
				var dummy_events: Array[Dictionary] = []
				dummy_events.append({"type": "explode", "pos": owner.pos, "radius": Constants.EXPLOSION_RADIUS})
				dummy_events.append_array(_explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid))
			return true
		"gravity":
			if source != null and source.alive and BoardUtils.manhattan(owner.pos, source.pos) > 1 and damage > 0:
				var deflect_target: UnitState = _random_neighbor_unit(state, owner, source.uid)
				if deflect_target != null:
					CombatRules.apply_damage(state, deflect_target, damage, owner.uid, "gravity_deflect")
				# 若无单位则弹到自身脚下地块（不造成单位伤害，仅标记事件）
			return true
		"arc":
			var rng := _rng_service()
			if source != null and source.alive and rng != null and bool(rng.chance("gem_arc_rebound_%s" % owner.uid, Constants.ARC_PARALYSIS_CHANCE)):
				var rebound_events: Array[Dictionary] = []
				_arc_to(state, source, owner.uid, CombatRules.attack_damage(state, owner), rebound_events)
			return true
		"split":
			# 实际伤害拦截在 CombatRules.apply_damage 层已完成，此处只声明响应
			return true
	return false


## 带事件输出的死亡钩子入口
static func _run_death_hooks_with_events(state: GameState, unit: UnitState, out_events: Array[Dictionary]) -> void:
	if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		if slot.locked and slot.lock_type == "split_disabled":
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		_run_unit_death_effect_with_events(state, unit, gem, out_events)


static func _run_unit_death_effect_with_events(state: GameState, owner: UnitState, gem: GemState, out_events: Array[Dictionary]) -> bool:
	match _ability_profile(gem, ABILITY_BLACK_DEATH):
		"explosion":
			var evs := explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid)
			out_events.append({"type": "explode", "pos": owner.pos, "radius": Constants.EXPLOSION_RADIUS})
			out_events.append_array(evs)
			return true
		"poison":
			out_events.append({"type": "poison_burst", "pos": owner.pos, "radius": 1})
			for cell in BoardUtils.cells_in_radius(owner.pos, 1):
				if not BoardUtils.in_bounds(state, cell):
					continue
				TileRules.create_poison_fog(state, cell)
			return true
		"gravity":
			# 死亡时将 3x3 范围内单位拉向自身（产生 move_step 事件）
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) > Constants.EXPLOSION_DEATH_RADIUS:
					continue
				_Displacement.pull_toward(state, unit, owner.pos, 1, owner.uid, out_events)
			return true
		"arc":
			# 黑槽导电：死亡落雷，3x3 范围内随机单位，固定 10 伤害，33% 概率麻痹
			var candidates: Array[UnitState] = []
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= Constants.ICE_DEATH_RADIUS:
					candidates.append(unit)
			var rng := _rng_service()
			if not candidates.is_empty() and rng != null:
				var strike_target: UnitState = candidates[int(rng.roll_int("gem_arc_death_strike_%s" % owner.uid, 0, candidates.size() - 1))]
				var dealt := CombatRules.apply_true_damage(
					state, strike_target, Constants.LIGHTNING_DEATH_DAMAGE, owner.uid, "lightning_death"
				)
				if dealt > 0:
					out_events.append({"type": "damage", "pos": strike_target.pos, "damage": dealt, "is_crit": false})
				if strike_target.alive and bool(rng.chance("gem_arc_death_paralyze_%s" % owner.uid, Constants.ARC_PARALYSIS_CHANCE)):
					StatusRules.apply_paralyzed(state, strike_target, 1, owner.uid)
				out_events.append({"type": "lightning", "pos": owner.pos, "target_pos": strike_target.pos})
			return true
		"fire_gem":
			# 黑槽燃烧：5x5 范围内随机选 5 个空地块创建火焰
			_scatter_fire_on_death(state, owner, out_events)
			return true
		"ice":
			# 黑槽冰冻：3x3 范围内所有单位下回合行动顺序垫底
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= Constants.ICE_DEATH_RADIUS:
					StatusRules.apply_sluggish(state, unit, owner.uid)
					out_events.append({"type": "frost_pulse", "pos": unit.pos})
			return true
		"split":
			_spawn_split_clones(state, owner, out_events)
			return true
	return false


static func _run_unit_death_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	var dummy: Array[Dictionary] = []
	return _run_unit_death_effect_with_events(state, owner, gem, dummy)


static func _run_unit_moved_through_effect(_state: GameState, _owner: UnitState, _gem: GemState, _ctx: Dictionary) -> bool:
	return false


## 蓝槽接触效果：接触到其他单位时触发
static func _run_unit_contact_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var other: UnitState = ctx.get("target", null)
	if other == null or not other.alive:
		return false
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			StatusRules.apply_poison(state, other, 1, 0, owner.uid)
			return true
		"fire_gem":
			StatusRules.apply_burning(state, other, 1, owner.uid)
			return true
		"ice":
			StatusRules.apply_slowed(state, other, 1, owner.uid)
			return true
	return false


static func _run_tile_slot_hook(state: GameState, tile: TileState, slot: SlotState, gem: GemState, timing: String, ctx: Dictionary = {}) -> bool:
	match timing:
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE or tile.tile_id != Constants.TILE_PILLAR:
				return false
			return _run_tile_turn_start_effect(state, tile, gem, ctx)
	return false


static func _run_tile_turn_start_effect(state: GameState, tile: TileState, gem: GemState, ctx: Dictionary = {}) -> bool:
	var out_events: Array[Dictionary] = _events_from_ctx(ctx)
	match _ability_profile(gem, ABILITY_TILE_TURN_START):
		"poison":
			out_events.append({"type": "poison_burst", "pos": tile.pos, "radius": 2})
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 2:
					StatusRules.apply_poison(state, unit, 1, 2, tile.tile_id)
			return true
		"explosion":
			out_events.append({"type": "explode", "pos": tile.pos, "radius": 1})
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 1:
					var dealt := CombatRules.apply_damage(state, unit, 1, "", "pillar_burn")
					if dealt > 0:
						out_events.append({"type": "damage", "pos": unit.pos, "damage": dealt, "is_crit": false})
			return true
		"gravity":
			out_events.append({"type": "gem_flash", "pos": tile.pos, "color": _data_registry().get_gem_color(gem)})
			for unit in state.units.values():
				if not unit.alive:
					continue
				if unit.pos == tile.pos:
					continue
				if BoardUtils.chebyshev(tile.pos, unit.pos) > 2:
					continue
				out_events.append_array(pull_unit_toward_with_events(state, unit, tile.pos, 1))
			return true
	return false



static func _gem_id(state: GameState, slot: SlotState) -> String:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return ""
	return _data_registry().get_gem_display_name(gem)


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _nearest_opponent(state: GameState, unit: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999
	for other in state.units.values():
		if not other.alive or other.team == unit.team:
			continue
		var dist := BoardUtils.manhattan(unit.pos, other.pos)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


static func _random_neighbor_unit(state: GameState, center: UnitState, exclude_uid: String = "") -> UnitState:
	var candidates: Array[UnitState] = []
	for cell in BoardUtils.cells_in_radius(center.pos, 1):
		if cell == center.pos:
			continue
		var unit := state.get_unit_at(cell)
		if unit != null and unit.alive and unit.uid != center.uid and unit.uid != exclude_uid:
			candidates.append(unit)
	if candidates.is_empty():
		return null
	var rng := _rng_service()
	if rng == null:
		return null
	return candidates[int(rng.roll_int("gem_gravity_deflect_%s" % center.uid, 0, candidates.size() - 1))]


static func _ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem_ref, ability_slot)


## ─── 电弧（arc）辅助 ──────────────────────────────────────────────────────

static func _calc_arc_damage(base_damage: int, state: GameState = null) -> int:
	var mult: float = 1.0
	if state != null:
		var registry := _relic_effect_registry()
		if registry != null:
			mult = float(registry.query_modifier("arc_damage_mult", state))
	return maxi(1, int(base_damage * Constants.ARC_CHAIN_DAMAGE_RATIO * mult))


static func _events_from_ctx(ctx: Dictionary) -> Array[Dictionary]:
	var raw: Variant = ctx.get("events", null)
	if raw is Array:
		return raw as Array[Dictionary]
	return [] as Array[Dictionary]


## 攻击水域：对相连水域及其边缘格上的所有潮湿单位各造成一次电弧伤害
static func apply_water_conduction(
	state: GameState,
	anchor_pos: Vector2i,
	attacker: UnitState,
	events: Array[Dictionary]
) -> void:
	var cluster := BoardUtils.water_cluster(state, anchor_pos)
	if cluster.is_empty():
		return
	var zone := BoardUtils.water_conduction_zone(cluster)
	var arc_damage := _calc_arc_damage(CombatRules.attack_damage(state, attacker), state)
	var hit_uids: Dictionary = {}
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not _unit_in_water_conduction_zone(state, unit, zone):
			continue
		if hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_arc_to(state, unit, attacker.uid, arc_damage, events)
	state.log("水域导电 %s，命中 %d 名单位" % [anchor_pos, hit_uids.size()])


## 水域导电目标：站在水域格上，或导电区边缘格且带潮湿
static func _unit_in_water_conduction_zone(state: GameState, unit: UnitState, zone: Dictionary) -> bool:
	if not zone.has(unit.pos):
		return false
	var tile := state.get_tile(unit.pos)
	if tile != null and tile.has_tile_tag(Constants.TAG_TILE_WATER):
		return true
	return StatusRules.is_wet(unit)


## 红槽攻击 TAG_ARC：以被击者为锚，向切比雪夫 2 格内另一敌方弹射 1 次（伤害为普攻 ARC_CHAIN_DAMAGE_RATIO）
static func apply_arc_bounce_from_victim(
	state: GameState,
	victim: UnitState,
	attacker: UnitState,
	base_damage: int,
	events: Array[Dictionary]
) -> void:
	if not victim.alive:
		return
	var arc_damage := _calc_arc_damage(base_damage, state)
	var candidates: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.uid == victim.uid or unit.uid == attacker.uid:
			continue
		if BoardUtils.chebyshev(victim.pos, unit.pos) <= Constants.ARC_CHAIN_RANGE:
			candidates.append(unit)
	if candidates.is_empty():
		return
	var rng := _rng_service()
	if rng == null:
		return
	var bounce_target: UnitState = candidates[int(rng.roll_int("gem_arc_bounce_%s" % attacker.uid, 0, candidates.size() - 1))]
	_arc_to(state, bounce_target, attacker.uid, arc_damage, events)


## 兼容旧调用名（攻击管线）
static func apply_arc_chain(
	state: GameState,
	victim: UnitState,
	attacker: UnitState,
	base_damage: int,
	events: Array[Dictionary]
) -> void:
	apply_arc_bounce_from_victim(state, victim, attacker, base_damage, events)


## 对单个目标施加电弧伤害；命中 6.6% 麻痹
static func _arc_to(
	state: GameState,
	target: UnitState,
	source_uid: String,
	damage: int,
	events: Array[Dictionary]
) -> void:
	if not target.alive:
		return
	var dealt := CombatRules.apply_damage(state, target, damage, source_uid, "arc")
	if dealt > 0:
		events.append({"type": "damage", "pos": target.pos, "damage": dealt, "is_crit": false})
	var rng := _rng_service()
	if target.alive and rng != null and bool(rng.chance("gem_arc_proc_%s" % source_uid, Constants.ARC_PROC_CHANCE)):
		StatusRules.apply_paralyzed(state, target, 1, source_uid)
	events.append({"type": "arc", "pos": target.pos})


## ─── 冰冻（ice）辅助 ──────────────────────────────────────────────────────

## 命中冰冻效果：潮湿单位直接冻结（麻痹+缓速），普通单位仅缓速
static func apply_ice_hit_effect(state: GameState, target: UnitState, source_uid: String) -> void:
	if not target.alive:
		return
	if StatusRules.is_wet(target):
		StatusRules.apply_paralyzed(state, target, 1, source_uid)
		StatusRules.apply_slowed(state, target, 2, source_uid)
		target.remove_status(Constants.STATUS_WET)
		state.log("%s 被冻结！" % target.uid)
	else:
		StatusRules.apply_slowed(state, target, 1, source_uid)


## ─── 燃烧（fire_gem）辅助 ────────────────────────────────────────────────

## 死亡散布火焰：5x5 范围内随机选 FIRE_DEATH_FIRE_COUNT 个格子创建火焰，优先空地
static func _scatter_fire_on_death(state: GameState, owner: UnitState, out_events: Array[Dictionary]) -> void:
	var all_cells: Array[Vector2i] = []
	for cell in BoardUtils.cells_in_radius(owner.pos, Constants.FIRE_DEATH_RADIUS):
		if BoardUtils.in_bounds(state, cell):
			all_cells.append(cell)
	# 优先选空格
	var empty_cells: Array[Vector2i] = []
	var occupied_cells: Array[Vector2i] = []
	for cell in all_cells:
		if state.get_unit_at(cell) == null:
			empty_cells.append(cell)
		else:
			occupied_cells.append(cell)
	# 打乱顺序后取前 N 个
	var rng := _rng_service()
	if rng == null:
		return
	rng.shuffle_in_place("gem_fire_death_scatter_%s" % owner.uid, empty_cells)
	rng.shuffle_in_place("gem_fire_death_scatter_occ_%s" % owner.uid, occupied_cells)
	var pool: Array[Vector2i] = empty_cells
	pool.append_array(occupied_cells)
	var count := mini(Constants.FIRE_DEATH_FIRE_COUNT, pool.size())
	for i in range(count):
		TileRules.create_fire(state, pool[i])
		out_events.append({"type": "fire_burst", "pos": pool[i]})


## 死亡转移负面：将 owner 身上所有负面状态随机转给 radius 内存活的敌方单位
static func _transfer_debuffs_to_random_units(state: GameState, owner: UnitState, radius: int) -> void:
	var debuffs: Array[StatusInstance] = []
	for s in owner.statuses:
		if StatusRegistry.status_type(s.status_id) == StatusRegistry.TYPE_DEBUFF:
			debuffs.append(s)
	if debuffs.is_empty():
		return
	var candidates: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		if BoardUtils.chebyshev(owner.pos, unit.pos) <= radius:
			candidates.append(unit)
	if candidates.is_empty():
		return
	var rng := _rng_service()
	if rng == null:
		return
	for debuff in debuffs:
		var target: UnitState = candidates[int(rng.roll_int("gem_death_spread_%s" % owner.uid, 0, candidates.size() - 1))]
		var copy := StatusInstance.create(debuff.status_id, debuff.stacks, debuff.duration, owner.uid, debuff.payload.duplicate(true))
		copy.value = debuff.value
		StatusRegistry.apply_to_unit(target, copy)
		state.log("%s 死亡将 %s 转给 %s" % [owner.uid, StatusRegistry.display_name(debuff.status_id), target.uid])


## ─── 分裂（split）黑槽：死亡生成两个分身 ────────────────────────────────────

## 优先在死亡单位刚腾出的 footprint 格生成分身，不足时再向外找空地
static func _find_split_spawn_cells(state: GameState, owner: UnitState, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in owner.occupied_cells():
		if not BoardUtils.in_bounds(state, cell):
			continue
		if not BoardUtils.is_passable(state, cell):
			continue
		if not result.has(cell):
			result.append(cell)
		if result.size() >= count:
			return result
	for cell in _find_empty_neighbor_cells(state, owner.pos, count):
		if result.has(cell):
			continue
		result.append(cell)
		if result.size() >= count:
			break
	return result


## 找 owner 周围（或更远）第一个空地
static func _find_empty_neighbor_cells(state: GameState, origin: Vector2i, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 按 chebyshev 距离从近到远搜索
	for radius in range(1, 5):
		for cell in BoardUtils.cells_in_radius(origin, radius):
			if not BoardUtils.in_bounds(state, cell):
				continue
			if not BoardUtils.is_passable(state, cell):
				continue
			if not result.has(cell):
				result.append(cell)
			if result.size() >= count:
				return result
	return result


## 槽位均匀分配：将 slots 按 slot_type 轮流分到两组
static func _partition_slots_for_clones(slots: Array) -> Array:
	# 返回 [slots_a, slots_b]，按槽位顺序逐个交替分配
	var group_a: Array = []
	var group_b: Array = []
	for i in range(slots.size()):
		if i % 2 == 0:
			group_a.append(slots[i])
		else:
			group_b.append(slots[i])
	return [group_a, group_b]


## 创建分身单位并注册到 state
static func _create_split_clone(state: GameState, owner: UnitState, spawn_pos: Vector2i, slot_group: Array) -> UnitState:
	var reg: Node = _data_registry()
	var clone_uid: String = str(reg.call("_next_uid", "split_clone"))
	var clone := UnitState.new()
	clone.uid = clone_uid
	clone.unit_def_id = owner.unit_def_id
	clone.team = owner.team
	clone.pos = spawn_pos
	clone.facing = owner.facing
	clone.alive = true
	clone.ai_profile_id = owner.ai_profile_id
	# 玩家分身继承 owner behavior（不走 AI 行动路径）；敌方分身用 generic_melee
	clone.behavior_id = owner.behavior_id if owner.team == Constants.TEAM_PLAYER else "generic_melee"
	clone.split_origin_uid = owner.uid
	clone.footprint_size = Vector2i(1, 1)
	clone.add_tag(Constants.TAG_UNIT_SPLIT_CLONE)
	var ratio: float = _behavior_for(owner).split_clone_ratio(owner)
	clone.base_attack = ceili(owner.base_attack * ratio)
	clone.armor = ceili(owner.armor * ratio)
	clone.move_points = ceili(owner.move_points * ratio)
	clone.speed = owner.speed  # speed 不降低（影响行动顺序）
	var clone_max_hp := ceili(owner.max_hp * ratio)
	clone.max_hp = clone_max_hp
	clone.hp = clone_max_hp

	# 复制槽位：按分配到的原槽复制槽类型和宝石（新宝石 uid）
	for slot_data in slot_group:
		var slot_type: String = slot_data.slot_type
		var new_slot := SlotState.create(slot_type)
		var orig_gem_uid: String = slot_data.gem_uid
		if not orig_gem_uid.is_empty():
			# 为分身复制宝石（新 uid，相同 gem_id 和 overrides）
			var orig_gem: GemState = state.gems.get(orig_gem_uid, null)
			if orig_gem != null:
				var new_gem_uid: String = str(reg.call("_next_uid", "gem"))
				var cloned_gem := GemState.create(new_gem_uid, orig_gem.gem_id, orig_gem.def_overrides.duplicate(true))
				cloned_gem.owner_uid = clone_uid
				state.gems[new_gem_uid] = cloned_gem
				new_slot.gem_uid = new_gem_uid
		clone.slots.append(new_slot)

	# 黑槽强制插入 [分裂] 宝石（Disabled & Locked）
	# 若此槽组中没有黑槽，则补一个黑槽并插入
	var has_black_slot := false
	for slot in clone.slots:
		if slot.slot_type == Constants.SLOT_BLACK:
			has_black_slot = true
			# 替换黑槽宝石为新 [分裂] 宝石
			var split_gem_uid: String = str(reg.call("_next_uid", "gem"))
			var split_gem := GemState.create(split_gem_uid, Constants.GEM_SPLIT, {})
			split_gem.owner_uid = clone_uid
			state.gems[split_gem_uid] = split_gem
			slot.gem_uid = split_gem_uid
			slot.locked = true
			slot.lock_type = "split_disabled"
			break
	if not has_black_slot:
		# 没有黑槽时补一个黑槽
		var split_gem_uid: String = str(reg.call("_next_uid", "gem"))
		var split_gem := GemState.create(split_gem_uid, Constants.GEM_SPLIT, {})
		split_gem.owner_uid = clone_uid
		state.gems[split_gem_uid] = split_gem
		var black_slot := SlotState.create(Constants.SLOT_BLACK, split_gem_uid, true, "split_disabled")
		clone.slots.append(black_slot)

	state.register_unit(clone)
	var intent_system := preload("res://scripts/rules/intent_system.gd")
	intent_system.refresh_unit_intent(state, clone)
	return clone


## 生成两个分身：找空地、分槽、创建单位，并推入可操控队列
static func _spawn_split_clones(state: GameState, owner: UnitState, out_events: Array[Dictionary]) -> void:
	var spawn_cells := _find_split_spawn_cells(state, owner, 2)
	if spawn_cells.is_empty():
		state.log("%s 分裂失败：周围没有空地" % owner.uid)
		return
	var slot_groups := _partition_slots_for_clones(owner.slots)
	var count := mini(2, spawn_cells.size())
	var clones: Array = []
	for i in range(count):
		var clone := _create_split_clone(state, owner, spawn_cells[i], slot_groups[i])
		clones.append(clone)
		out_events.append({"type": "split_spawn", "pos": spawn_cells[i], "uid": clone.uid})
		state.log("%s 分裂生成分身 %s 于 %s" % [owner.uid, clone.uid, spawn_cells[i]])
	if not clones.is_empty() and owner.team == Constants.TEAM_PLAYER:
		var uids: Array = clones.map(func(c: UnitState) -> String: return c.uid)
		state.push_controllable_batch(uids)
		state.log("分裂激活：操控 %s，队列 %s" % [state.player_uid, state.controllable_queue])



