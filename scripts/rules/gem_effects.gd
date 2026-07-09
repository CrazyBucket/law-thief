class_name GemEffects
extends RefCounted

const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const EntityRules = preload("res://scripts/rules/entity_rules.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")

const _Displacement = preload("res://scripts/rules/displacement.gd")


static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")

const TIMING_ACTIVE := "active"
const TIMING_TURN_START := "turn_start"
const TIMING_TURN_END := "turn_end"
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

const BLACK_DEATH_PROFILE_ORDER: Array[String] = [
	"arc",
	"gravity",
	"ice",
	"poison",
	"fire_gem",
	"explosion",
	"split",
	"light",
	"counter",
	"echo",
]

const TAG_SPLIT_BLUE_TEMP_CLONE := "unit:split_blue_temp_clone"


static func run_unit_hooks(state: GameState, unit: UnitState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	var gem_ctx := GemTagResolver.build_context(state, unit, slot_type, timing)
	var triggered_tags: Dictionary = {}
	for slot in unit.slots:
		if not slot.accepts_slot_type(slot_type) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if triggered_tags.has(tag):
			continue
		triggered_tags[tag] = true
		var hook_ctx := ctx.duplicate()
		hook_ctx["gem_tag_context"] = gem_ctx
		_run_slot_hook(state, unit, slot, timing, hook_ctx)


static func tick_turn_start(state: GameState) -> void:
	var to_remove: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.has_tag(TAG_SPLIT_BLUE_TEMP_CLONE):
			continue
		var expire_turn := int(state.battle_temp_flags.get("split_blue_temp_expire:%s" % unit.uid, state.turn_index))
		if expire_turn <= state.turn_index:
			to_remove.append(unit)
	for unit in to_remove:
		state.log("%s 的蓝槽分裂临时分身消失" % unit.uid)
		state.unregister_unit(unit)
		state.battle_temp_flags.erase("split_blue_temp_expire:%s" % unit.uid)
	state.purge_dead_controllable()


static func run_blue_poison_turn_end_spreads(state: GameState, acting_unit_uid: String) -> void:
	if state == null or acting_unit_uid.is_empty():
		return
	var acting: UnitState = state.units.get(acting_unit_uid, null)
	if acting == null or not acting.alive:
		return
	var gem_ctx := GemTagResolver.build_context(state, acting, Constants.SLOT_BLUE, TIMING_TURN_END)
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
	if not bool(poison_level_def.get("turn_end_spread", false)):
		return
	_spread_blue_poison_from_unit(state, acting, poison_level_def)


static func capture_blue_poison_turn_end_sources(state: GameState) -> Dictionary:
	var snapshot: Dictionary = {}
	if state == null:
		return snapshot
	for unit in state.units.values():
		if not unit.alive:
			continue
		var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
		if poison == null:
			continue
		var source_uid := str(poison.source_uid)
		if source_uid.is_empty():
			continue
		var source_uids: Array = snapshot.get(source_uid, [])
		if not unit.uid in source_uids:
			source_uids.append(unit.uid)
		snapshot[source_uid] = source_uids
	return snapshot


static func run_tile_hooks(state: GameState, tile: TileState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in tile.slots:
		if not slot.accepts_slot_type(slot_type) or slot.gem_uid.is_empty():
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


static func on_unit_death(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary] = [],
	ctx: Dictionary = {}
) -> void:
	_behavior_for(unit).on_unit_death(state, unit)
	_run_death_hooks_with_events(state, unit, out_events, ctx)


static func trigger_black_death_effects(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary] = [],
	ctx: Dictionary = {}
) -> void:
	_run_death_hooks_with_events(state, unit, out_events, ctx)


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
	for slot in unit.slots_accepting(Constants.SLOT_BLUE):
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "split":
			has_split_blue = true
			break
	if not has_split_blue:
		return damage
	if not _behavior_for(unit).should_trigger_split_blue(unit, reason):
		return damage
	var _split_blue_registry := _relic_effect_registry()
	var split_blue_ratio: float = CombatConfig.split_damage_redirect_ratio()
	if _split_blue_registry != null:
		split_blue_ratio = _split_blue_registry.query_override_modifier("split_blue_redirect_ratio", state, split_blue_ratio)
	var redirect_amount := int(damage * split_blue_ratio)
	if redirect_amount <= 0:
		return damage
	var candidates: Array[UnitState] = []
	for other in state.units.values():
		if not other.alive or other.uid == unit.uid:
			continue
		if BoardUtils.is_within_surround(unit, other, CombatConfig.split_surround_radius()):
			candidates.append(other)
	if candidates.is_empty():
		return damage
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED)
	var split_level := GemTagResolver.tag_level(gem_ctx, "split")
	var split_level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), split_level)
	if bool(split_level_def.get("even_redirect_distribution", false)):
		var participant_count := candidates.size() + 1
		var owner_damage := ceili(float(damage) / float(participant_count))
		var redirected := damage - owner_damage
		if redirected <= 0:
			return owner_damage
		var base_share := int(redirected / candidates.size())
		var remainder := redirected % candidates.size()
		for i in range(candidates.size()):
			var share := base_share + (1 if i < remainder else 0)
			if share <= 0:
				continue
			_damage_from_state_sink(state, candidates[i], share, source_uid, "split_redirect")
		state.log("%s 分裂宝石将 %d 点伤害均分给 %d 名周围单位" % [unit.uid, redirected, candidates.size()])
		return owner_damage
	var rng := _rng_service()
	if rng == null:
		return damage
	var redirect_target: UnitState = candidates[int(rng.roll_int("gem_split_redirect_%s" % unit.uid, 0, candidates.size() - 1))]
	state.log("%s 分裂宝石将 %d 点伤害转移给 %s" % [unit.uid, redirect_amount, redirect_target.uid])
	_damage_from_state_sink(state, redirect_target, redirect_amount, source_uid, "split_redirect")
	return damage - redirect_amount


static func _damage_from_state_sink(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin_from_state(state)
	var dealt := tx.damage_unit(unit, amount, source_uid, reason, opts)
	tx.finish("GemEffects.%s" % reason)
	return dealt


static func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	return _data_registry().get_enemy_red_intent_meta(gem_ref, damage)


static func unit_has_red_arc(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "arc")


static func unit_has_red_light(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "light")


static func red_attack_range_bonus(state: GameState, unit: UnitState) -> int:
	if state == null or unit == null:
		return 0
	if not _unit_has_red_active_profile(state, unit, "gravity"):
		return 0
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_RED, TIMING_ACTIVE)
	var gravity_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "gravity"))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def("gravity", Constants.SLOT_RED, gravity_level)
	return int(level_def.get("range_bonus", gravity_level))


static func red_attack_range(state: GameState, unit: UnitState, base_range: int = -1) -> int:
	if base_range < 0:
		base_range = CombatConfig.attack_range()
	if unit_has_red_light(state, unit):
		return Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	return base_range + red_attack_range_bonus(state, unit)


static func gravity_pull_range(state: GameState, unit: UnitState, base_range: int = -1) -> int:
	if base_range < 0:
		base_range = CombatConfig.enemy_gravity_pull_range()
	return base_range + red_attack_range_bonus(state, unit)


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


static func explosion_tag_count(gem_ctx: Dictionary) -> int:
	return int((gem_ctx.get("tag_counts", {}) as Dictionary).get("explosion", 0))


static func explosion_uses_square_blast(gem_ctx: Dictionary) -> bool:
	return GemTagResolver.tag_level(gem_ctx, "explosion") >= 2


static func explosion_stack_multiplier(gem_ctx: Dictionary) -> int:
	var count := explosion_tag_count(gem_ctx)
	if count >= 3:
		return count - 1
	return 1


static func explosion_scaled_damage(base_damage: int, gem_ctx: Dictionary) -> int:
	return base_damage * explosion_stack_multiplier(gem_ctx)


static func red_explosion_blast_cells(center: Vector2i, gem_ctx: Dictionary) -> Array[Vector2i]:
	if explosion_uses_square_blast(gem_ctx):
		return BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius())
	return cross_explosion_cells(center)


static func resolve_blast_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	if aim_cell is Vector2i:
		return aim_cell
	return fallback


static func unit_has_red_explosion(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "explosion")


static func unit_has_red_split(state: GameState, unit: UnitState) -> bool:
	if _unit_has_red_active_profile(state, unit, "split"):
		return true
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_ENEMY_RED_ACTION) == "split":
			return true
	return false


static func _unit_has_red_active_profile(state: GameState, unit: UnitState, profile: String) -> bool:
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == profile:
			return true
	return false


static func find_red_active_gem(state: GameState, unit: UnitState, profile: String) -> GemState:
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == profile:
			return gem
	return null


## 红槽爆炸：以 center 为中心，十字四邻各结算一次（同一单位只结算一次）
static func explode_cross_at(
	state: GameState,
	center: Vector2i,
	source_uid: String,
	opts: Dictionary = {}
) -> Array[Dictionary]:
	var center_damage: int = int(opts.get("center_damage", 0))
	var cross_damage: int = int(opts.get("cross_damage", CombatConfig.explosion_cross_damage()))
	var knockback_center: bool = bool(opts.get("knockback_center", false))
	var exclude_unit_uid: String = str(opts.get("exclude_unit_uid", ""))
	var gem_ctx: Dictionary = opts.get("gem_tag_context", {})
	var events: Array[Dictionary] = []
	var cells: Array[Vector2i] = cross_explosion_cells(center)
	events.append({"type": "explode", "pos": center, "pattern": "cross", "cells": cells})
	state.log("爆炸宝石十字爆炸于 %s" % center)
	if center_damage > 0:
		var center_unit := state.get_unit_at(center)
		if center_unit != null and center_unit.alive and center_unit.uid != source_uid:
			if exclude_unit_uid.is_empty() or center_unit.uid != exclude_unit_uid:
				_damage_unit_event(
					state, center_unit, center_damage, source_uid, "explosion_cross", events
				)
				if knockback_center and center_unit.alive:
					_Displacement.knockback(
						state, center_unit, center, 1, source_uid, events, CombatConfig.knockback_collision_damage(), true
					)
	var splashed: Dictionary = {}
	if center_damage > 0:
		var center_unit_check := state.get_unit_at(center)
		if center_unit_check != null and center_unit_check.alive \
				and center_unit_check.uid != source_uid \
				and (exclude_unit_uid.is_empty() or center_unit_check.uid != exclude_unit_uid):
			splashed[center_unit_check.uid] = true
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
		_damage_unit_event(state, hit_unit, cross_damage, source_uid, "explosion_cross", events)
		for gem_slot in hit_unit.slots:
			if gem_slot.locked and gem_slot.lock_type == Constants.LOCK_ARMOR:
				StatusRules.apply_exposed(state, hit_unit, gem_slot, state.turn_index)
		if hit_unit.alive:
			knockback_targets.append(hit_unit)
	# knockback 事件统一追加在所有 damage 之后，保证 UI 层可批量并行播放
	for kb_unit in knockback_targets:
		_Displacement.knockback(
			state, kb_unit, center, 1, source_uid, events, CombatConfig.knockback_collision_damage(), true
		)
	GemComboResolver.apply_after_explosion(state, cells, gem_ctx, events)
	return events


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	return _explode_at(state, center, damage, source_uid)


static func explode_square_at(
	state: GameState,
	center: Vector2i,
	source_uid: String,
	damage: int,
	gem_ctx: Dictionary = {}
) -> Array[Dictionary]:
	var cells := BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius())
	var events: Array[Dictionary] = [{
		"type": "explode",
		"pos": center,
			"radius": CombatConfig.explosion_radius(),
		"pattern": "square",
		"cells": cells,
	}]
	events.append_array(_explode_at(state, center, damage, source_uid))
	GemComboResolver.apply_after_explosion(state, cells, gem_ctx, events)
	return events


static func _damage_unit_event(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	events: Array[Dictionary],
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin(state, events)
	return tx.damage_unit(unit, amount, source_uid, reason, opts)


static func _true_damage_unit_event(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	events: Array[Dictionary],
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin(state, events)
	return tx.true_damage_unit(unit, amount, source_uid, reason, opts)


static func _explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var hit_uids: Dictionary = {}
	var knockback_targets: Array[UnitState] = []
	state.log("爆炸于 %s" % [center])
	for cell in BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius()):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_entity := state.get_entity_at(cell)
		if hit_entity != null and hit_entity.alive and hit_entity.max_hp > 0:
			EntityRules.damage_entity(state, hit_entity, damage, source_uid, events)
		var hit_unit := state.get_unit_at(cell)
		if hit_unit == null or not hit_unit.alive:
			continue
		if hit_unit.uid == source_uid:
			continue
		if hit_uids.has(hit_unit.uid):
			continue
		hit_uids[hit_unit.uid] = true
		_damage_unit_event(state, hit_unit, damage, source_uid, "explosion", events)
		for slot in hit_unit.slots:
			if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
				StatusRules.apply_exposed(state, hit_unit, slot, state.turn_index)
		if hit_unit.alive and hit_unit.pos != center:
			knockback_targets.append(hit_unit)
	for kb_unit in knockback_targets:
		_Displacement.knockback(state, kb_unit, center, 1, source_uid, events, CombatConfig.knockback_collision_damage(), true)
	return events


## 强制位移钩子：携带爆炸宝石的单位被强制位移时自爆
static func on_forced_displacement(state: GameState, unit: UnitState, events: Array[Dictionary]) -> void:
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLUE, TIMING_FORCED_MOVE)
	var triggered_tags: Dictionary = {}
	for slot in unit.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLUE) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if triggered_tags.has(tag):
			continue
			triggered_tags[tag] = true
			if _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "explosion":
				state.log("%s 被强制位移触发爆炸！" % unit.uid)
				var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
				var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
				if str(level_def.get("blast_pattern", "cross")) == "square":
					events.append_array(explode_square_at(state, unit.pos, unit.uid, CombatConfig.explosion_damage(), gem_ctx))
				else:
					events.append({"type": "explode", "pos": unit.pos, "radius": CombatConfig.explosion_radius()})
					events.append_array(_explode_at(state, unit.pos, CombatConfig.explosion_damage(), unit.uid))
					GemComboResolver.apply_after_explosion(
						state,
						BoardUtils.cells_in_radius(unit.pos, CombatConfig.explosion_radius()),
						gem_ctx,
						events
					)


static func pull_around(state: GameState, center: Vector2i, pull_range: int, steps: int, source_uid: String = "") -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.pos == center:
			continue
		if BoardUtils.chebyshev(center, unit.pos) > pull_range:
			continue
		pull_unit_toward_with_events(state, unit, center, steps, source_uid)


static func pull_unit_toward_with_events(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String = ""
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_Displacement.pull_toward(
		state, unit, anchor, steps, source_uid, events,
		-1,
		false,
		false
	)
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
			if not slot.accepts_slot_type(Constants.SLOT_RED):
				return false
			return _run_unit_active_effect(state, owner, slot, gem, ctx)
		TIMING_TURN_START:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_turn_start_effect(state, owner, gem)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_TURN_END:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_turn_end_effect(state, owner, slot, gem, ctx)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_OWNER_DAMAGED:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_damaged_effect(state, owner, slot, gem, ctx)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_ON_DEATH:
			if not slot.accepts_slot_type(Constants.SLOT_BLACK):
				return false
			return _run_unit_death_effect(state, owner, gem)
		TIMING_MOVED_THROUGH:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			return _run_unit_moved_through_effect(state, owner, gem, ctx)
		TIMING_ON_CONTACT:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			return _run_unit_contact_effect(state, owner, gem, ctx)
	return false


static func _run_unit_active_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var out_events: Array[Dictionary] = _events_from_ctx(ctx)
	match _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE):
		"explosion":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var blast_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var target_unit: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			var exclude_uid := ""
			if target_unit != null and target_unit.alive:
				blast_center = resolve_blast_center(target_unit.pos, ctx.get("target_pos", null))
				exclude_uid = target_unit.uid
			if explosion_uses_square_blast(gem_ctx):
				var damage := explosion_scaled_damage(CombatConfig.explosion_cross_damage(), gem_ctx)
				out_events.append_array(explode_square_at(state, blast_center, owner.uid, damage, gem_ctx))
			else:
				out_events.append_array(
					explode_cross_at(state, blast_center, owner.uid, {
						"center_damage": CombatConfig.explosion_cross_damage(),
						"exclude_unit_uid": exclude_uid,
						"gem_tag_context": gem_ctx,
					})
				)
			return true
		"poison":
			var poison_level := 1
			var poison_duration := CombatConfig.poison_fog_duration()
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			poison_level = maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def(
				"poison",
				_effect_level_scope(gem_ctx, Constants.SLOT_RED),
				poison_level
			)
			poison_duration += int(poison_level_def.get("duration_bonus", 0))
			var poison_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var poison_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if poison_target != null and poison_target.alive:
				poison_center = resolve_blast_center(poison_target.pos, ctx.get("target_pos", null))
			var poison_pattern := str(poison_level_def.get("fog_pattern", "single"))
			var burst := {
				"type": "poison_burst",
				"pos": poison_center,
				"radius": 0,
				"duration": poison_duration,
			}
			if poison_pattern == "cross":
				burst["pattern"] = "cross"
			out_events.append(burst)
			if BoardUtils.in_bounds(state, poison_center):
				TileRules.begin_overlay_batch(state)
				TileRules.create_poison_fog(state, poison_center, poison_duration)
				if poison_pattern == "cross":
					for neighbor in BoardUtils.neighbors4(poison_center):
						if BoardUtils.in_bounds(state, neighbor):
							TileRules.create_poison_fog(state, neighbor, poison_duration)
				TileRules.end_overlay_batch(state)
			if poison_target != null and poison_target.alive:
				StatusRules.apply_poison(
					state,
					poison_target,
					int(poison_level_def.get("hit_poison_stacks", 1)),
					int(poison_level_def.get("hit_poison_duration", 0)),
					owner.uid
				)
			return true
		"gravity":
			var gravity_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gravity_ctx.is_empty():
				gravity_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var gravity_level := maxi(1, GemTagResolver.tag_level(gravity_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def(
				"gravity",
				_effect_level_scope(gravity_ctx, Constants.SLOT_RED),
				gravity_level
			)
			var pull_steps := int(gravity_level_def.get("pull_steps", gravity_level))
			out_events.append({"type": "gem_flash", "pos": owner.pos, "color": _data_registry().get_gem_color(gem)})
			var pull_target: UnitState = state.units.get(str(ctx.get("target_uid", "")), null)
			if pull_target != null and pull_target.alive and pull_target.uid != owner.uid:
				out_events.append_array(
					pull_unit_toward_with_events(state, pull_target, owner.pos, pull_steps, owner.uid)
				)
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
				var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
				var arc_base := CombatRules.attack_damage(state, owner)
				_arc_to(state, owner.pos, arc_target, owner.uid, _calc_arc_damage(arc_base), out_events)
				apply_arc_bounce_from_victim(state, arc_target, owner, arc_base, out_events, gem_ctx)
			return true
		"fire_gem":
			var fire_pos := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var fire_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			var fire_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if fire_ctx.is_empty():
				fire_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var fire_level := maxi(1, GemTagResolver.tag_level(fire_ctx, "fire"))
			var fire_level_def: Dictionary = _effect_level_def(
				"fire",
				_effect_level_scope(fire_ctx, Constants.SLOT_RED),
				fire_level
			)
			var spread_count := 0
			if fire_target != null and fire_target.alive:
				fire_pos = resolve_blast_center(fire_target.pos, ctx.get("target_pos", null))
				spread_count += int(fire_level_def.get("spread_count", 0))
				if fire_target.has_status(Constants.STATUS_BURNING):
					spread_count += int(fire_level_def.get("burning_bonus_spread_count", 0))
			out_events.append({"type": "fire_burst", "pos": fire_pos})
			TileRules.begin_overlay_batch(state)
			TileRules.create_fire(state, fire_pos)
			for cell in _random_adjacent_cells(state, fire_pos, spread_count, "gem_fire_red_spread_%s_%s" % [owner.uid, str(fire_pos)]):
				TileRules.create_fire(state, cell)
				out_events.append({"type": "fire_burst", "pos": cell, "spread": true})
			TileRules.end_overlay_batch(state)
			return true
		"ice":
			var ice_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if ice_target == null or not ice_target.alive:
				return true
			var ice_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if ice_ctx.is_empty():
				ice_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			out_events.append({"type": "frost_pulse", "pos": ice_target.pos})
			apply_ice_hit_effect(state, ice_target, owner.uid, GemTagResolver.tag_level(ice_ctx, "ice"))
			return true
		"split":
			return true
	return false


static func _run_unit_turn_start_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_BLUE_TURN_START):
		"explosion":
			for cell in BoardUtils.neighbors4(owner.pos):
				var target := state.get_unit_at(cell)
				if target != null and target.alive and target.team != owner.team:
					_damage_from_state_sink(state, target, 1, owner.uid, "blue_explosion_aura")
					break
			return true
	return false


static func _run_unit_turn_end_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_TURN_END, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			if not bool(level_def.get("turn_end_spread", false)):
				return false
			var snapshot_variant: Variant = ctx.get("poison_turn_end_sources", {})
			var snapshot: Dictionary = snapshot_variant if snapshot_variant is Dictionary else {}
			return _spread_blue_poison_turn_end(state, owner, snapshot, str(ctx.get("acting_unit_uid", "")))
	return false


static func _run_unit_damaged_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var reason: String = ctx.get("reason", "")
	var source_uid: String = ctx.get("source_uid", "")
	var damage: int = ctx.get("damage", 0)
	var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var poison_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if poison_ctx.is_empty():
				poison_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var poison_level := maxi(1, GemTagResolver.tag_level(poison_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(poison_ctx, Constants.SLOT_BLUE), poison_level)
			if bool(poison_level_def.get("copy_debuff_on_damaged", false)) and source != null and source.alive:
				if BoardUtils.chebyshev(owner.pos, source.pos) <= 1:
					_copy_one_debuff_to_nearest_unit(state, source, owner.uid)
			return false
		"explosion":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			var detonate_on_any_damage := bool(level_def.get("detonate_on_any_damage", false))
			var detonate_on_burning := bool(level_def.get("detonate_on_burning", true))
			var blast_pattern := str(level_def.get("blast_pattern", "cross"))
			if detonate_on_any_damage or (detonate_on_burning and (reason == "burning" or reason == "tile_fire")):
				state.log("%s 被火焰点燃引爆！" % owner.uid)
				var out_events: Array[Dictionary] = _events_from_ctx(ctx)
				if blast_pattern == "square":
					out_events.append_array(explode_square_at(state, owner.pos, owner.uid, CombatConfig.explosion_damage(), gem_ctx))
				else:
					out_events.append({"type": "explode", "pos": owner.pos, "radius": CombatConfig.explosion_radius()})
					out_events.append_array(_explode_at(state, owner.pos, CombatConfig.explosion_damage(), owner.uid))
					GemComboResolver.apply_after_explosion(
						state,
						BoardUtils.cells_in_radius(owner.pos, CombatConfig.explosion_radius()),
						gem_ctx,
						out_events
					)
			return true
		"gravity":
			var gravity_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gravity_ctx.is_empty():
				gravity_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var gravity_level := maxi(1, GemTagResolver.tag_level(gravity_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def("gravity", _effect_level_scope(gravity_ctx, Constants.SLOT_BLUE), gravity_level)
			if source != null and source.alive and BoardUtils.manhattan(owner.pos, source.pos) > 1 and damage > 0:
				var deflect_target: UnitState = _random_neighbor_unit(state, owner, source.uid)
				if deflect_target != null:
					_damage_from_state_sink(state, deflect_target, damage, owner.uid, "gravity_deflect")
				if bool(gravity_level_def.get("slow_on_damaged", false)):
					StatusRules.apply_slowed(state, source, 1, owner.uid)
				if bool(gravity_level_def.get("root_on_damaged", false)):
					StatusRules.apply_rooted(state, source, 1, owner.uid)
			return true
		"arc":
			var rng := _rng_service()
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
			var level_def: Dictionary = _effect_level_def("arc", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			var chance := float(level_def.get("rebound_chance", CombatConfig.arc_paralysis_chance()))
			if source != null and source.alive and rng != null and bool(rng.chance("gem_arc_rebound_%s" % owner.uid, chance)):
				_arc_to(state, owner.pos, source, owner.uid, CombatRules.attack_damage(state, owner), _events_from_ctx(ctx))
			return true
		"split":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var split_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "split"))
			var split_level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), split_level)
			if bool(split_level_def.get("spawn_temp_clone", false)) and damage > 0 and owner.hp > damage:
				_try_spawn_split_blue_temp_clone(state, owner, _events_from_ctx(ctx))
			return true
		"light":
			if source != null and source.alive and reason == "ranged_attack":
				var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
				_reflect_light_on_damage(state, owner, source, gem_ctx, _events_from_ctx(ctx))
			return true
		"counter":
			if source != null and source.alive and damage > 0:
				var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
				var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "counter"))
				var level_def: Dictionary = _effect_level_def("counter", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
				if bool(level_def.get("use_ranged_counter", false)):
					var result := AttackPipeline.execute_aimed(
						state,
						owner,
						source.pos,
						[AttackPipeline.TAG_RANGED],
						{"damage_reason": "counter_blue"},
						Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
					)
					_events_from_ctx(ctx).append_array(result.get("events", []))
					if bool(level_def.get("grant_extra_move_on_kill", false)) and not source.alive and owner.uid == state.player_uid:
						StatusRules.grant_extra_move(state, owner, 1, owner.uid)
				else:
					_damage_unit_event(
						state,
						source,
						CombatRules.attack_damage(state, owner),
						owner.uid,
						"counter_blue",
						_events_from_ctx(ctx)
					)
			return true
		"echo":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			_apply_blue_echo(state, owner, source, gem_ctx, ctx)
			return true
	return false


## 带事件输出的死亡钩子入口
static func _run_death_hooks_with_events(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary],
	ctx: Dictionary = {}
) -> void:
	if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return
	var death_gems: Array[GemState] = []
	var seen_tags: Dictionary = {}
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLACK, TIMING_ON_DEATH, null, ctx)
	if ctx.has("death_chain_id"):
		gem_ctx["death_chain_id"] = int(ctx.get("death_chain_id", 0))
	if ctx.has("source_uid"):
		gem_ctx["source_uid"] = str(ctx.get("source_uid", ""))
	if ctx.has("damage"):
		gem_ctx["damage"] = int(ctx.get("damage", 0))
	for slot in unit.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLACK) or slot.gem_uid.is_empty():
			continue
		if slot.locked and slot.lock_type == Constants.LOCK_SPLIT_DISABLED:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if seen_tags.has(tag):
			continue
		seen_tags[tag] = true
		death_gems.append(gem)
	death_gems.sort_custom(func(a: GemState, b: GemState) -> bool:
		return _black_death_order_index(a) < _black_death_order_index(b)
	)
	for gem in death_gems:
		_run_unit_death_effect_with_events(state, unit, gem, out_events, gem_ctx)


static func _black_death_order_index(gem: GemState) -> int:
	var profile := _ability_profile(gem, ABILITY_BLACK_DEATH)
	var idx := BLACK_DEATH_PROFILE_ORDER.find(profile)
	if idx < 0:
		return BLACK_DEATH_PROFILE_ORDER.size()
	return idx


static func _run_unit_death_effect_with_events(
	state: GameState,
	owner: UnitState,
	gem: GemState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> bool:
	var tag := str(_data_registry().get_gem_tag(gem))
	if _should_skip_black_death_tag(state, owner, tag, gem_ctx):
		return false
	match _ability_profile(gem, ABILITY_BLACK_DEATH):
		"explosion":
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLACK, TIMING_ON_DEATH)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
			var damage := explosion_scaled_damage(CombatConfig.explosion_damage(), gem_ctx)
			var evs := explode_at(state, owner.pos, damage, owner.uid)
			out_events.append({"type": "explode", "pos": owner.pos, "radius": CombatConfig.explosion_radius()})
			out_events.append_array(evs)
			GemComboResolver.apply_after_explosion(
				state,
				BoardUtils.cells_in_radius(owner.pos, CombatConfig.explosion_radius()),
				gem_ctx,
				out_events
			)
			if bool(level_def.get("chain_followup", false)):
				_append_black_explosion_chain(state, owner, evs, out_events)
			return true
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), poison_level)
			if bool(poison_level_def.get("spawn_fog", false)):
				var fog_radius := int(poison_level_def.get("fog_radius", 1))
				out_events.append({"type": "poison_burst", "pos": owner.pos, "radius": fog_radius})
				TileRules.begin_overlay_batch(state)
				for cell in BoardUtils.cells_in_radius(owner.pos, fog_radius):
					if not BoardUtils.in_bounds(state, cell):
						continue
					TileRules.create_poison_fog(state, cell)
				TileRules.end_overlay_batch(state)
			_transfer_debuffs_to_random_units(
				state,
				owner,
				int(poison_level_def.get("debuff_spread_radius", 1)),
				int(poison_level_def.get("debuff_copies", 1))
			)
			return true
		"gravity":
			# 死亡时将 3x3 范围内单位拉向自身（产生 move_step 事件）
			var gravity_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def("gravity", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), gravity_level)
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) > CombatConfig.explosion_death_radius():
					continue
				_Displacement.pull_toward(state, unit, owner.pos, int(gravity_level_def.get("pull_steps", 1)), owner.uid, out_events)
				if bool(gravity_level_def.get("apply_slow", false)):
					StatusRules.apply_slowed(state, unit, 1, owner.uid)
				if bool(gravity_level_def.get("apply_root", false)):
					StatusRules.apply_rooted(state, unit, 1, owner.uid)
			return true
		"arc":
			# 黑槽导电：死亡落雷，按同 tag 数量扩展命中目标数量。
			var candidates: Array[UnitState] = []
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= CombatConfig.ice_death_radius():
					candidates.append(unit)
			var rng := _rng_service()
			if not candidates.is_empty() and rng != null:
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLACK, TIMING_ON_DEATH)
				var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
				var level_def: Dictionary = _effect_level_def("arc", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
				if bool(level_def.get("strike_all_targets", false)):
					for strike_target in candidates:
						_apply_lightning_death_strike(state, owner, strike_target, out_events)
				else:
					var strikes := int(level_def.get("strike_count", 1))
					for i in range(mini(strikes, candidates.size())):
						var pick := int(rng.roll_int("gem_arc_death_strike_%s_%d" % [owner.uid, i], 0, candidates.size() - 1))
						var strike_target: UnitState = candidates[pick]
						candidates.remove_at(pick)
						_apply_lightning_death_strike(state, owner, strike_target, out_events)
			return true
		"fire_gem":
			# 黑槽燃烧：5x5 范围内随机选 5 个空地块创建火焰
			_scatter_fire_on_death(
				state,
				owner,
				out_events,
				maxi(1, GemTagResolver.tag_level(gem_ctx, "fire")),
				gem_ctx
			)
			return true
		"ice":
			# 黑槽冰冻：3x3 范围内所有单位下回合行动顺序垫底
			var ice_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "ice"))
			var ice_level_def: Dictionary = _effect_level_def("ice", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), ice_level)
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= CombatConfig.ice_death_radius():
					StatusRules.apply_sluggish(state, unit, owner.uid)
					if bool(ice_level_def.get("apply_slowed", false)):
						StatusRules.apply_slowed(state, unit, 1, owner.uid)
					if bool(ice_level_def.get("apply_paralyzed", false)):
						StatusRules.apply_paralyzed(state, unit, 1, owner.uid)
					out_events.append({"type": "frost_pulse", "pos": unit.pos})
			return true
		"split":
			_spawn_split_clones(state, owner, out_events, gem_ctx)
			return true
		"light":
			_resolve_black_light(state, owner, out_events, maxi(1, GemTagResolver.tag_level(gem_ctx, "light")))
			return true
		"counter":
			var source_uid := str(gem_ctx.get("source_uid", ""))
			var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
			if source != null and source.alive:
				var amount := maxi(1, int(gem_ctx.get("damage", owner.max_hp)))
				_damage_unit_event(state, source, amount, owner.uid, "counter_black", out_events)
			return true
		"echo":
			_apply_black_echo(state, owner, out_events, gem_ctx)
			return true
	return false


static func _run_unit_death_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	var dummy: Array[Dictionary] = []
	return _run_unit_death_effect_with_events(state, owner, gem, dummy)


static func _append_black_explosion_chain(
	state: GameState,
	owner: UnitState,
	main_events: Array[Dictionary],
	out_events: Array[Dictionary]
) -> void:
	var nearest: UnitState = null
	var nearest_dist := 999999
	for ev in main_events:
		if str(ev.get("type", "")) != "damage":
			continue
		var uid := str(ev.get("uid", ""))
		if uid.is_empty() or uid == owner.uid:
			continue
		var unit: UnitState = state.units.get(uid, null)
		if unit == null or unit.alive:
			continue
		var dist := BoardUtils.chebyshev(owner.pos, unit.pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = unit
	if nearest == null:
		return
	var chain_events := explode_cross_at(
		state,
		nearest.pos,
		owner.uid,
		{"center_damage": CombatConfig.explosion_damage(), "cross_damage": CombatConfig.explosion_damage()}
	)
	out_events.append_array(chain_events)


static func _apply_lightning_death_strike(
	state: GameState,
	owner: UnitState,
	strike_target: UnitState,
	out_events: Array[Dictionary]
) -> void:
	var impact_events: Array[Dictionary] = []
	_true_damage_unit_event(
		state,
		strike_target,
		CombatConfig.lightning_death_damage(),
		owner.uid,
		"lightning_death",
		impact_events
	)
	var rng := _rng_service()
	if strike_target.alive and rng != null and bool(rng.chance("gem_arc_death_paralyze_%s_%s" % [owner.uid, strike_target.uid], CombatConfig.arc_paralysis_chance())):
		StatusRules.apply_paralyzed(state, strike_target, 1, owner.uid)
	out_events.append({"type": "lightning", "pos": owner.pos, "target_pos": strike_target.pos})
	out_events.append_array(impact_events)


static func _reflect_light_on_damage(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	out_events: Array[Dictionary]
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "light"))
	var level_def: Dictionary = _effect_level_def("light", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
	var beams := int(level_def.get("reflect_beams", 1))
	var candidates: Array[UnitState] = [source]
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid or unit.uid == source.uid:
			continue
		if unit.team != owner.team:
			candidates.append(unit)
	var damage_ratio := float(level_def.get("reflect_damage_ratio", 0.2))
	var damage := maxi(1, int(float(CombatRules.attack_damage(state, owner)) * damage_ratio))
	var exposed_stacks := int(level_def.get("reflect_exposed_stacks", 1))
	var reflect_power := float(level_def.get("reflect_power", 0.72))
	var reflect_impact_size := float(level_def.get("reflect_impact_size", 0.72))
	var count := mini(beams, candidates.size())
	for i in range(count):
		var target := candidates[i]
		out_events.append(build_light_beam_event(
			owner.pos,
			target.pos,
			gem_ctx,
			reflect_impact_size,
			{"power": reflect_power, "impact_size": reflect_impact_size, "source_uid": owner.uid}
			))
		var dealt := _damage_unit_event(state, target, damage, owner.uid, "light_reflect", out_events)
		if dealt > 0:
			StatusRules.apply_light_exposed(state, target, exposed_stacks, owner.uid)
		apply_light_colored_status(state, target, owner, gem_ctx, out_events, damage)


static func _resolve_black_light(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	level: int
) -> void:
	var level_def: Dictionary = _effect_level_def("light", Constants.SLOT_BLACK, level)
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		var exposed: StatusInstance = unit.get_status(Constants.STATUS_LIGHT_EXPOSED)
		if exposed == null:
			continue
		var damage := maxi(1, exposed.stacks * CombatRules.attack_damage(state, owner))
		out_events.append(build_light_beam_event(
			owner.pos,
			unit.pos,
			{},
			float(level_def.get("beam_width", 1.35 + float(level) * 0.18)),
			{
				"power": float(level_def.get("beam_power", 1.25)),
				"impact_size": float(level_def.get("impact_size", 1.3)),
				"source_uid": owner.uid
			}
			))
		_damage_unit_event(state, unit, damage, owner.uid, "light_judgement", out_events)
		unit.remove_status(Constants.STATUS_LIGHT_EXPOSED)
		if bool(level_def.get("blind_on_survive", false)) and unit.alive:
			StatusRules.apply_blinded(state, unit, 1, owner.uid)


static func _apply_blue_echo(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	ctx: Dictionary
) -> void:
	var once_key := "echo_blue_used:%s:%d" % [owner.uid, state.turn_index]
	if bool(state.battle_temp_flags.get(once_key, false)):
		return
	state.battle_temp_flags[once_key] = true
	var out_events := _events_from_ctx(ctx)
	var tags := GemEchoRules.resolve_echo_tags(state, gem_ctx, "echo_blue_%s_%d" % [owner.uid, state.turn_index])
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	var echo_level_def: Dictionary = _effect_level_def("echo", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), echo_level)
	for i in range(tags.size()):
		var tag := tags[i]
		var strength := int(echo_level_def.get("first_tag_strength", 1)) if i == 0 else 1
		match tag:
			"arc":
				if source != null and source.alive:
					for _repeat in range(strength):
						_arc_to(state, owner.pos, source, owner.uid, CombatRules.attack_damage(state, owner), out_events)
			"fire":
				if source != null and source.alive:
					StatusRules.apply_burning(state, source, strength, owner.uid)
			"poison":
				if source != null and source.alive:
					StatusRules.apply_poison(state, source, strength, 0, owner.uid)
			"ice":
				if source != null and source.alive:
					apply_ice_hit_effect(state, source, owner.uid, GemTagResolver.tag_level(gem_ctx, "ice") + strength - 1)
			"light":
				if source != null and source.alive:
					for _repeat in range(strength):
						_reflect_light_on_damage(state, owner, source, gem_ctx, out_events)


static func _apply_black_echo(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary
) -> void:
	if int(gem_ctx.get("echo_depth", 0)) > 0:
		return
	var echo_ctx := gem_ctx.duplicate(true)
	echo_ctx["echo_depth"] = int(gem_ctx.get("echo_depth", 0)) + 1
	var tags := GemEchoRules.resolve_echo_tags(state, gem_ctx, "echo_black_%s" % owner.uid)
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	var echo_level_def: Dictionary = _effect_level_def("echo", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), echo_level)
	for i in range(tags.size()):
		var tag := tags[i]
		var gem := _find_gem_by_tag(state, owner, Constants.SLOT_BLACK, tag)
		if gem == null:
			continue
		var repeat_count := int(echo_level_def.get("first_tag_repeat_count", 1)) if i == 0 else 1
		for _repeat in range(repeat_count):
			_run_unit_death_effect_with_events(state, owner, gem, out_events, echo_ctx)


static func _find_gem_by_tag(state: GameState, owner: UnitState, slot_type: String, tag: String) -> GemState:
	for slot in owner.slots_accepting(slot_type):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and str(_data_registry().get_gem_tag(gem)) == tag:
			return gem
	return null


static func light_color_for_context(gem_ctx: Dictionary) -> Color:
	var dye := str(gem_ctx.get("light_dye_element", ""))
	if dye == "fire":
		return Color(1.0, 0.24, 0.12)
	if dye == "poison":
		return Color(0.05, 0.95, 0.18)
	if GemTagResolver.has_tag(gem_ctx, "fire"):
		return Color(1.0, 0.24, 0.12)
	if GemTagResolver.has_tag(gem_ctx, "poison"):
		return Color(0.05, 0.95, 0.18)
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		return Color(1.0, 0.92, 0.22)
	if GemTagResolver.has_tag(gem_ctx, "ice"):
		return Color(0.55, 0.9, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		return Color(1.0, 0.58, 0.18)
	return Color(1.0, 0.96, 0.58)


static func light_element_for_context(gem_ctx: Dictionary) -> String:
	var dye := str(gem_ctx.get("light_dye_element", ""))
	if not dye.is_empty():
		return dye
	for element in ["fire", "poison", "arc", "ice", "explosion"]:
		if GemTagResolver.has_tag(gem_ctx, element):
			return element
	return "light"


static func light_beam_width_for_level(level: int) -> float:
	var level_def: Dictionary = _effect_level_def("light", Constants.SLOT_RED, maxi(1, level))
	return float(level_def.get("beam_width", 1.0))


static func is_valid_light_aim(attacker: UnitState, target_pos: Vector2i) -> bool:
	if attacker == null:
		return false
	var origin := BoardUtils.projectile_origin_cell(attacker, target_pos)
	var delta := target_pos - origin
	return delta != Vector2i.ZERO and (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y))


static func light_context_with_path_dye(state: GameState, cells: Array[Vector2i], gem_ctx: Dictionary) -> Dictionary:
	var result := gem_ctx.duplicate(true)
	for cell in cells:
		var dye := light_dye_element_at(state, cell)
		if not dye.is_empty():
			result = light_context_with_dye(result, dye)
	return result


static func light_dye_element_at(state: GameState, cell: Vector2i) -> String:
	if state == null:
		return ""
	var tile := state.get_tile(cell)
	if tile == null:
		return ""
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		return "fire"
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG) or tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE):
		return "poison"
	if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		return "poison"
	return ""


static func light_context_with_dye(gem_ctx: Dictionary, dye: String) -> Dictionary:
	var result := gem_ctx.duplicate(true)
	if dye.is_empty():
		return result
	result["light_dye_element"] = dye
	var levels: Dictionary = result.get("tag_levels", {}).duplicate()
	levels[dye] = maxi(1, int(levels.get(dye, 0)))
	result["tag_levels"] = levels
	return result


static func light_dye_transitions(state: GameState, cells: Array[Vector2i]) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var current := ""
	for cell in cells:
		var dye := light_dye_element_at(state, cell)
		if dye.is_empty() or dye == current:
			continue
		current = dye
		var dye_ctx := light_context_with_dye({}, dye)
		transitions.append({
			"cell": cell,
			"element": dye,
			"color": light_color_for_context(dye_ctx),
		})
	return transitions


static func apply_light_colored_status(
	state: GameState,
	target: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	out_events: Array[Dictionary],
	base_damage: int
) -> void:
	if state == null or target == null or source == null or not target.alive:
		return
	if GemTagResolver.has_tag(gem_ctx, "poison"):
		var poison_level_def := red_poison_hit_config(gem_ctx)
		StatusRules.apply_poison(
			state,
			target,
			int(poison_level_def.get("hit_poison_stacks", 1)),
			int(poison_level_def.get("hit_poison_duration", 0)),
			source.uid
		)
	if GemTagResolver.has_tag(gem_ctx, "fire"):
		StatusRules.apply_burning(state, target, 1, source.uid)
	if GemTagResolver.has_tag(gem_ctx, "ice"):
		apply_ice_hit_effect(state, target, source.uid, GemTagResolver.tag_level(gem_ctx, "ice"))
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		apply_arc_bounce_from_victim(state, target, source, base_damage, out_events, gem_ctx)


static func build_light_beam_event(
	from_cell: Vector2i,
	to_cell: Vector2i,
	gem_ctx: Dictionary = {},
	width: float = 1.0,
	overrides: Dictionary = {}
) -> Dictionary:
	var element := light_element_for_context(gem_ctx)
	var event := {
		"type": "light_beam",
		"from": from_cell,
		"to": to_cell,
		"color": light_color_for_context(gem_ctx),
		"element": element,
		"width": width,
		"power": 1.0,
		"core": 0.16,
		"halo": 0.68,
		"noise": 0.2 if element == "light" else 0.42,
		"speed": 1.0,
		"impact_size": width,
		"show_impact": false,
	}
	for key in overrides:
		event[key] = overrides[key]
	return event


static func _run_unit_moved_through_effect(_state: GameState, _owner: UnitState, _gem: GemState, _ctx: Dictionary) -> bool:
	return false


## 蓝槽接触效果：接触到其他单位时触发
static func _run_unit_contact_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var other: UnitState = ctx.get("target", null)
	if other == null or not other.alive:
		return false
	var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_ON_CONTACT)
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
			StatusRules.apply_poison(
				state,
				other,
				int(poison_level_def.get("contact_poison_stacks", 1)),
				int(poison_level_def.get("contact_poison_duration", 0)),
				owner.uid
			)
			if bool(poison_level_def.get("copy_debuff_on_contact", false)):
				_copy_one_debuff_to_nearest_unit(state, other, owner.uid)
			return true
		"fire_gem":
			var fire_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "fire"))
			var fire_level_def: Dictionary = _effect_level_def("fire", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), fire_level)
			var had_burning := other.has_status(Constants.STATUS_BURNING)
			StatusRules.apply_burning(state, other, int(fire_level_def.get("contact_burning_stacks", 1)), owner.uid)
			if bool(fire_level_def.get("create_fire_on_contact", false)):
				TileRules.create_fire(state, other.pos)
			if bool(fire_level_def.get("double_burning_on_already_burning", false)) and had_burning:
				var once_key := "fire_blue_double:%s:%s:%d" % [owner.uid, other.uid, state.turn_index]
				if not bool(state.battle_temp_flags.get(once_key, false)):
					state.battle_temp_flags[once_key] = true
					var burning := other.get_status(Constants.STATUS_BURNING)
					if burning != null and burning.stacks > 0:
						StatusRules.apply_burning(state, other, burning.stacks, owner.uid)
			return true
		"ice":
			var ice_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "ice"))
			var ice_level_def: Dictionary = _effect_level_def("ice", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), ice_level)
			var had_slowed := other.has_status(Constants.STATUS_SLOWED)
			StatusRules.apply_slowed(state, other, int(ice_level_def.get("contact_slowed_stacks", 1)), owner.uid)
			if bool(ice_level_def.get("upgrade_slowed_to_sluggish", false)) and had_slowed:
				StatusRules.apply_sluggish(state, other, owner.uid)
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
	var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(state, tile, Constants.SLOT_BLUE, TIMING_TURN_START)
	match _ability_profile(gem, ABILITY_TILE_TURN_START):
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
			var pillar_radius := int(poison_level_def.get("pillar_radius", 2))
			var pillar_stacks := int(poison_level_def.get("pillar_poison_stacks", 1))
			var pillar_duration := int(poison_level_def.get("pillar_poison_duration", 2))
			out_events.append({"type": "poison_burst", "pos": tile.pos, "radius": pillar_radius})
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= pillar_radius:
					StatusRules.apply_poison(state, unit, pillar_stacks, pillar_duration, tile.tile_id)
			return true
		"explosion":
			var explosion_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var explosion_level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), explosion_level)
			var pillar_radius := int(explosion_level_def.get("pillar_radius", 1))
			var pillar_damage := int(explosion_level_def.get("pillar_damage", 1))
			out_events.append({"type": "explode", "pos": tile.pos, "radius": pillar_radius})
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= pillar_radius:
					_damage_unit_event(state, unit, pillar_damage, "", "pillar_burn", out_events)
			return true
		"gravity":
			var gravity_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def("gravity", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), gravity_level)
			var pillar_pull_radius := int(gravity_level_def.get("pillar_pull_radius", 2))
			var pillar_pull_steps := int(gravity_level_def.get("pillar_pull_steps", 1))
			out_events.append({"type": "gem_flash", "pos": tile.pos, "color": _data_registry().get_gem_color(gem)})
			for unit in state.units.values():
				if not unit.alive:
					continue
				if unit.pos == tile.pos:
					continue
				if BoardUtils.chebyshev(tile.pos, unit.pos) > pillar_pull_radius:
					continue
				out_events.append_array(pull_unit_toward_with_events(state, unit, tile.pos, pillar_pull_steps))
			return true
	return false



static func _gem_id(state: GameState, slot: SlotState) -> String:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return ""
	return _data_registry().get_gem_display_name(gem)


static func _effect_level_scope(gem_ctx: Dictionary, fallback_scope: String) -> String:
	return str(gem_ctx.get("effect_level_scope", fallback_scope))


static func _effect_level_def(tag: String, scope: String, level: int) -> Dictionary:
	return _data_registry().get_gem_effect_level_def(tag, scope, level)


static func red_poison_hit_config(gem_ctx: Dictionary = {}) -> Dictionary:
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	return _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_RED), poison_level)


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


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


static func _random_adjacent_cells(state: GameState, center: Vector2i, count: int, rng_key: String) -> Array[Vector2i]:
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


static func _copy_one_debuff_to_nearest_unit(state: GameState, source: UnitState, source_uid: String) -> void:
	var debuffs: Array[StatusInstance] = []
	for status in source.statuses:
		if StatusRegistry.status_type(status.status_id) == StatusRegistry.TYPE_DEBUFF:
			debuffs.append(status)
	if debuffs.is_empty():
		return
	var nearest: UnitState = null
	var nearest_dist := 999999
	for unit in state.units.values():
		if not unit.alive or unit.uid == source.uid:
			continue
		var dist := BoardUtils.chebyshev(source.pos, unit.pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = unit
	if nearest == null:
		return
	var debuff := debuffs[0]
	var copy := StatusInstance.create(debuff.status_id, debuff.stacks, debuff.duration, source_uid, debuff.payload.duplicate(true))
	copy.value = debuff.value
	StatusRegistry.apply_to_unit(nearest, copy)


static func _spread_blue_poison_from_unit(state: GameState, carrier: UnitState, poison_level_def: Dictionary = {}) -> bool:
	var best_target: UnitState = null
	var best_dist := 999999
	for unit in state.units.values():
		if not unit.alive or unit.uid == carrier.uid:
			continue
		if unit.has_status(Constants.STATUS_POISON):
			continue
		var dist := BoardUtils.chebyshev(carrier.pos, unit.pos)
		if dist < best_dist:
			best_dist = dist
			best_target = unit
	if best_target == null:
		return false
	StatusRules.apply_poison(
		state,
		best_target,
		int(poison_level_def.get("turn_end_poison_stacks", 1)),
		int(poison_level_def.get("turn_end_poison_duration", 2)),
		carrier.uid
	)
	state.log("%s 的剧毒在回合结束传给 %s" % [carrier.uid, best_target.uid])
	return true


static func _spread_blue_poison_turn_end(
	state: GameState,
	owner: UnitState,
	_snapshot: Dictionary,
	acting_unit_uid: String = ""
) -> bool:
	if not acting_unit_uid.is_empty() and acting_unit_uid != owner.uid:
		return false
	var gem_ctx := GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_TURN_END)
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
	if not bool(poison_level_def.get("turn_end_spread", false)):
		return false
	return _spread_blue_poison_from_unit(state, owner, poison_level_def)


static func _poison_turn_end_source_uids(snapshot: Dictionary, owner_uid: String) -> Array[String]:
	var result: Array[String] = []
	for raw in snapshot.get(owner_uid, []):
		var uid := str(raw)
		if not uid.is_empty() and not uid in result:
			result.append(uid)
	return result


static func _should_skip_black_death_tag(state: GameState, owner: UnitState, tag: String, gem_ctx: Dictionary) -> bool:
	var death_chain_id := int(gem_ctx.get("death_chain_id", 0))
	if death_chain_id <= 0 or tag.is_empty():
		return false
	var key := "death_chain:%d:%s:%s" % [death_chain_id, owner.uid, tag]
	if bool(state.battle_temp_flags.get(key, false)):
		return true
	state.battle_temp_flags[key] = true
	return false


static func _ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem_ref, ability_slot)


## ─── 电弧（arc）辅助 ──────────────────────────────────────────────────────

static func _calc_arc_damage(base_damage: int, state: GameState = null) -> int:
	var mult: float = 1.0
	if state != null:
		var registry := _relic_effect_registry()
		if registry != null:
			mult = float(registry.query_modifier("arc_damage_mult", state))
	return maxi(1, int(base_damage * CombatConfig.arc_chain_damage_ratio() * mult))


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
	var conduction_events: Array[Dictionary] = []
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not _unit_in_water_conduction_zone(state, unit, zone):
			continue
		if hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_arc_to(state, anchor_pos, unit, attacker.uid, arc_damage, conduction_events)
	for event in conduction_events:
		if str(event.get("type", "")) == "arc":
			events.append(event)
	for event in conduction_events:
		if str(event.get("type", "")) != "arc":
			events.append(event)
	state.log("水域导电 %s，命中 %d 名单位" % [anchor_pos, hit_uids.size()])


## 水域导电目标：站在水域格上，或导电区边缘格且带潮湿
static func _unit_in_water_conduction_zone(state: GameState, unit: UnitState, zone: Dictionary) -> bool:
	if not zone.has(unit.pos):
		return false
	var tile := state.get_tile(unit.pos)
	if tile != null and tile.has_tile_tag(Constants.TAG_TILE_WATER):
		return true
	return StatusRules.is_wet(unit)


## 红槽 TAG_ARC：被击者锚点 2 格内敌方各弹一次；遗物 arc_bounce_count_bonus 增加向外扩的跳数。
static func apply_arc_bounce_from_victim(
	state: GameState,
	victim: UnitState,
	attacker: UnitState,
	base_damage: int,
	events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	if not victim.alive:
		return
	var arc_damage := _calc_arc_damage(base_damage, state)
	var registry := _relic_effect_registry()
	var arc_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def("arc", Constants.SLOT_RED, arc_level)
	var bounce_hops := int(level_def.get("bounce_hops", 1))
	if registry != null:
		bounce_hops += int(registry.query_modifier("arc_bounce_count_bonus", state))
	var arc_range := int(level_def.get("range", CombatConfig.arc_chain_range()))
	var hit_uids: Dictionary = {victim.uid: true, attacker.uid: true}
	var anchors: Array[UnitState] = [victim]
	var hop := 0
	while hop < bounce_hops:
		var next_anchors: Array[UnitState] = []
		var hop_events: Array[Dictionary] = []
		for anchor in anchors:
			for unit in state.units.values():
				if not unit.alive:
					continue
				if hit_uids.has(unit.uid):
					continue
				if unit.team == attacker.team:
					continue
				if BoardUtils.chebyshev(anchor.pos, unit.pos) > arc_range:
					continue
				_arc_to(state, anchor.pos, unit, attacker.uid, arc_damage, hop_events)
				hit_uids[unit.uid] = true
				next_anchors.append(unit)
		# 同一跳的电弧并发出现，随后在统一命中点结算这一跳的伤害。
		for event in hop_events:
			if str(event.get("type", "")) == "arc":
				events.append(event)
		for event in hop_events:
			if str(event.get("type", "")) != "arc":
				events.append(event)
		if next_anchors.is_empty():
			break
		anchors = next_anchors
		hop += 1


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
	from_pos: Vector2i,
	target: UnitState,
	source_uid: String,
	damage: int,
	events: Array[Dictionary]
) -> void:
	if not target.alive:
		return
	events.append({"type": "arc", "from": from_pos, "pos": from_pos, "target_pos": target.pos})
	_damage_unit_event(state, target, damage, source_uid, "arc", events)
	var rng := _rng_service()
	if target.alive and rng != null and bool(rng.chance("gem_arc_proc_%s" % source_uid, CombatConfig.arc_proc_chance())):
		StatusRules.apply_paralyzed(state, target, 1, source_uid)


## ─── 冰冻（ice）辅助 ──────────────────────────────────────────────────────

## 命中冰冻效果：潮湿单位直接冻结（麻痹+缓速），普通单位仅缓速
static func apply_ice_hit_effect(state: GameState, target: UnitState, source_uid: String, level: int = 1) -> void:
	if not target.alive:
		return
	var level_def: Dictionary = _effect_level_def("ice", Constants.SLOT_RED, maxi(1, level))
	if bool(level_def.get("freeze_if_target_slowed", false)) and target.has_status(Constants.STATUS_SLOWED):
		_freeze_target(state, target, source_uid)
		return
	if StatusRules.is_wet(target):
		_freeze_target(state, target, source_uid)
		return
	StatusRules.apply_slowed(state, target, int(level_def.get("hit_slowed_stacks", 1)), source_uid)


static func _freeze_target(state: GameState, target: UnitState, source_uid: String) -> void:
	StatusRules.apply_paralyzed(state, target, 1, source_uid)
	StatusRules.apply_slowed(state, target, 2, source_uid)
	target.remove_status(Constants.STATUS_WET)
	state.log("%s 被冻结！" % target.uid)


## ─── 燃烧（fire_gem）辅助 ────────────────────────────────────────────────

## 死亡散布火焰：5x5 范围内随机选 FIRE_DEATH_FIRE_COUNT 个格子创建火焰，优先空地
static func _scatter_fire_on_death(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	level: int = 1,
	gem_ctx: Dictionary = {}
) -> void:
	var level_scope := str(gem_ctx.get("effect_level_scope", Constants.SLOT_BLACK))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def("fire", level_scope, level)
	var all_cells: Array[Vector2i] = []
	for cell in BoardUtils.cells_in_radius(owner.pos, CombatConfig.fire_death_radius()):
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
	var prefer_occupied := bool(level_def.get("prefer_occupied_cells", false))
	var pool: Array[Vector2i] = occupied_cells if prefer_occupied else empty_cells
	pool.append_array(empty_cells if prefer_occupied else occupied_cells)
	var count := CombatConfig.fire_death_fire_count() + int(level_def.get("death_fire_count_bonus", 0))
	var duration := CombatConfig.fire_duration() + int(level_def.get("death_duration_bonus", 0))
	count = mini(count, pool.size())
	TileRules.begin_overlay_batch(state)
	for i in range(count):
		TileRules.create_fire(state, pool[i], duration)
		out_events.append({"type": "fire_burst", "pos": pool[i]})
	TileRules.end_overlay_batch(state)


## 死亡转移负面：将 owner 身上所有负面状态随机转给 radius 内存活的敌方单位
static func _transfer_debuffs_to_random_units(state: GameState, owner: UnitState, radius: int, copies_per_debuff: int = 1) -> void:
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
		var remaining := candidates.duplicate()
		var copies := mini(maxi(1, copies_per_debuff), remaining.size())
		for i in range(copies):
			var pick := int(rng.roll_int("gem_death_spread_%s_%d" % [owner.uid, i], 0, remaining.size() - 1))
			var target: UnitState = remaining[pick]
			remaining.remove_at(pick)
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


static func _split_black_ratio_for_context(gem_ctx: Dictionary) -> float:
	var level := GemTagResolver.tag_level(gem_ctx, "split")
	if level < 1:
		return -1.0
	var level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
	return float(level_def.get("stat_ratio", CombatConfig.split_black_stat_ratio()))


static func _try_spawn_split_blue_temp_clone(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary]
) -> void:
	var used_key := "split_blue_temp_used:%s:%d" % [owner.uid, state.turn_index]
	if bool(state.battle_temp_flags.get(used_key, false)):
		return
	var spawn_cells := _find_empty_neighbor_cells(state, owner.pos, 1)
	if spawn_cells.is_empty():
		return
	state.battle_temp_flags[used_key] = true
	var clone := _create_split_clone(state, owner, spawn_cells[0], [], CombatConfig.split_black_stat_ratio())
	clone.max_hp = 1
	clone.hp = 1
	clone.add_tag(TAG_SPLIT_BLUE_TEMP_CLONE)
	state.battle_temp_flags["split_blue_temp_expire:%s" % clone.uid] = state.turn_index + 1
	out_events.append({"type": "split_spawn", "pos": clone.pos, "uid": clone.uid, "temporary": true})
	state.log("%s 蓝槽分裂生成临时分身 %s 于 %s" % [owner.uid, clone.uid, clone.pos])


## 创建分身单位并注册到 state
static func _create_split_clone(
	state: GameState,
	owner: UnitState,
	spawn_pos: Vector2i,
	slot_group: Array,
	ratio_override: float = -1.0
) -> UnitState:
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
	var ratio: float = ratio_override if ratio_override > 0.0 else _behavior_for(owner).split_clone_ratio(owner)
	var _split_black_registry := _relic_effect_registry()
	if _split_black_registry != null and owner.team == Constants.TEAM_PLAYER:
		ratio = _split_black_registry.query_override_modifier("split_black_stat_ratio", state, ratio)
	clone.base_attack = ceili(owner.base_attack * ratio)
	clone.armor = ceili(owner.armor * ratio)
	clone.move_points = ceili(owner.move_points * ratio)
	clone.speed = owner.speed  # speed 不降低（影响行动顺序）
	var clone_max_hp := ceili(owner.max_hp * ratio)
	clone.max_hp = clone_max_hp
	clone.hp = clone_max_hp

	# 分身保留完整槽位轮廓；只有分配到的原槽继承宝石，未分配槽显示为空。
	var first_black_slot: SlotState = null
	for slot_data in owner.slots:
		if slot_data == null:
			continue
		var new_slot := SlotState.create(slot_data.slot_type, "", slot_data.locked, slot_data.lock_type)
		new_slot.dual_type = slot_data.dual_type
		new_slot.unlock_until_turn = slot_data.unlock_until_turn
		clone.slots.append(new_slot)
		if first_black_slot == null and new_slot.slot_type == Constants.SLOT_BLACK:
			first_black_slot = new_slot
		if not slot_group.has(slot_data):
			continue
		var orig_gem_uid: String = slot_data.gem_uid
		if orig_gem_uid.is_empty():
			continue
		var orig_gem: GemState = state.gems.get(orig_gem_uid, null)
		if orig_gem == null:
			continue
		var new_gem_uid: String = str(reg.call("_next_uid", "gem"))
		var cloned_gem := GemState.create(new_gem_uid, orig_gem.gem_id, orig_gem.def_overrides.duplicate(true))
		cloned_gem.owner_uid = clone_uid
		cloned_gem.slot_index = clone.slots.find(new_slot)
		state.gems[new_gem_uid] = cloned_gem
		new_slot.gem_uid = new_gem_uid

	var split_slot := first_black_slot
	if split_slot == null:
		split_slot = SlotState.create(Constants.SLOT_BLACK)
		clone.slots.append(split_slot)
	if not split_slot.gem_uid.is_empty():
		state.gems.erase(split_slot.gem_uid)
	var split_gem_uid: String = str(reg.call("_next_uid", "gem"))
	var split_gem := GemState.create(split_gem_uid, Constants.GEM_SPLIT, {})
	split_gem.owner_uid = clone_uid
	split_gem.slot_index = clone.slots.find(split_slot)
	state.gems[split_gem_uid] = split_gem
	split_slot.gem_uid = split_gem_uid
	split_slot.locked = true
	split_slot.lock_type = Constants.LOCK_SPLIT_DISABLED
	split_slot.unlock_until_turn = -1

	state.register_unit(clone)
	var intent_system := preload("res://scripts/rules/intent_system.gd")
	intent_system.refresh_unit_intent(state, clone)
	return clone


## 生成两个分身：找空地、分槽、创建单位，并推入可操控队列
static func _spawn_split_clones(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	var spawn_cells := _find_split_spawn_cells(state, owner, 2)
	if spawn_cells.is_empty():
		state.log("%s 分裂失败：周围没有空地" % owner.uid)
		return
	var slot_groups := _partition_slots_for_clones(owner.slots)
	var count := mini(2, spawn_cells.size())
	var ratio := _split_black_ratio_for_context(gem_ctx)
	var clones: Array = []
	for i in range(count):
		var clone := _create_split_clone(state, owner, spawn_cells[i], slot_groups[i], ratio)
		clones.append(clone)
		out_events.append({"type": "split_spawn", "pos": spawn_cells[i], "uid": clone.uid})
		state.log("%s 分裂生成分身 %s 于 %s" % [owner.uid, clone.uid, spawn_cells[i]])
	if not clones.is_empty() and owner.team == Constants.TEAM_PLAYER:
		var uids: Array = clones.map(func(c: UnitState) -> String: return c.uid)
		state.push_controllable_batch(uids)
		state.log("分裂激活：操控 %s，队列 %s" % [state.player_uid, state.controllable_queue])
