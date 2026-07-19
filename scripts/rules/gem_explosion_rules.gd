class_name GemExplosionRules
extends RefCounted

const BoardUtils = preload("res://scripts/rules/board_utils.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")
const EntityRules = preload("res://scripts/rules/entity_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")

static var _reaction_depth: int = 0
static var _triggered_blue_uids: Dictionary = {}


static func cross_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [center]
	for neighbor in BoardUtils.neighbors4(center):
		cells.append(neighbor)
	return cells


static func blast_pattern(level_def: Dictionary) -> String:
	return str(level_def.get("blast_pattern", "cross"))


static func uses_square_blast(level_def: Dictionary) -> bool:
	return blast_pattern(level_def) == "square"


static func center_damage_ratio(level_def: Dictionary) -> float:
	return float(level_def.get("center_damage_ratio", 0.0))


static func splash_base_attack_ratio(level_def: Dictionary) -> float:
	return float(level_def.get("splash_base_attack_ratio", 0.0))


static func blue_damage_ratio(level_def: Dictionary) -> float:
	return float(level_def.get("damage_ratio", 0.6))


static func black_damage_multiplier(level_def: Dictionary) -> float:
	return float(level_def.get("damage_multiplier", 1.0))


static func scaled_damage(base_damage: int, ratio: float) -> int:
	return maxi(1, roundi(float(base_damage) * ratio))


static func red_blast_cells(center: Vector2i, level_def: Dictionary) -> Array[Vector2i]:
	if uses_square_blast(level_def):
		return BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius())
	return cross_cells(center)


static func resolve_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	if aim_cell is Vector2i:
		return aim_cell
	return fallback


static func begin_reaction_chain() -> void:
	if _reaction_depth == 0:
		_triggered_blue_uids.clear()
	_reaction_depth += 1


static func end_reaction_chain() -> void:
	_reaction_depth = maxi(0, _reaction_depth - 1)
	if _reaction_depth == 0:
		_triggered_blue_uids.clear()


static func has_active_reaction_chain() -> bool:
	return _reaction_depth > 0


static func mark_blue_triggered(uid: String) -> bool:
	if _triggered_blue_uids.has(uid):
		return false
	_triggered_blue_uids[uid] = true
	return true


static func explode_cross_at(state: GameState, center: Vector2i, source_uid: String, opts: Dictionary = {}) -> Array[Dictionary]:
	begin_reaction_chain()
	var center_damage := int(opts.get("center_damage", 0))
	var splash_damage := int(opts.get("cross_damage", CombatConfig.explosion_cross_damage()))
	var exclude_uid := str(opts.get("exclude_unit_uid", ""))
	var gem_ctx: Dictionary = opts.get("gem_tag_context", {})
	var collision_context := DamageContext.create(source_uid, "explosion_collision", ["explosion"], gem_ctx)
	var cells := cross_cells(center)
	var events: Array[Dictionary] = [_EventBuilder.explode(center, 1, {
		"pattern": "cross", "cells": cells, "source_uid": source_uid,
	})]
	state.log("爆炸宝石十字爆炸于 %s" % center)
	var hit_entities: Dictionary = {}
	var center_entity := state.get_entity_at(center)
	if center_damage > 0 and center_entity != null and center_entity.alive and center_entity.max_hp > 0:
		hit_entities[center_entity.uid] = true
		EntityRules.damage_entity(state, center_entity, center_damage, source_uid, events)
	var hit_uids: Dictionary = {}
	var center_unit := state.get_unit_at(center)
	if center_damage > 0 and _can_hit_unit(center_unit, source_uid, exclude_uid):
		hit_uids[center_unit.uid] = true
		_damage_unit(state, center_unit, center_damage, source_uid, "explosion_cross", events, gem_ctx)
		if bool(opts.get("knockback_center", false)) and center_unit.alive:
			_Displacement.knockback(state, center_unit, center, 1, source_uid, events,
				CombatConfig.knockback_collision_damage(), true, collision_context)
	var knockback_targets: Array[UnitState] = []
	for cell in BoardUtils.neighbors4(center):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.max_hp > 0 and not hit_entities.has(entity.uid):
			hit_entities[entity.uid] = true
			EntityRules.damage_entity(state, entity, splash_damage, source_uid, events)
		var unit := state.get_unit_at(cell)
		if not _can_hit_unit(unit, source_uid, exclude_uid) or hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_damage_unit(state, unit, splash_damage, source_uid, "explosion_cross", events, gem_ctx)
		_expose_armor_slots(state, unit)
		if unit.alive:
			knockback_targets.append(unit)
	for unit in knockback_targets:
		_Displacement.knockback(state, unit, center, 1, source_uid, events,
			CombatConfig.knockback_collision_damage(), true, collision_context)
	GemComboResolver.apply_after_explosion(state, cells, gem_ctx, events)
	end_reaction_chain()
	return events


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String, gem_ctx: Dictionary = {}) -> Array[Dictionary]:
	begin_reaction_chain()
	var events := _explode_square_damage(state, center, damage, source_uid, gem_ctx, damage, "")
	end_reaction_chain()
	return events


static func explode_square_at(state: GameState, center: Vector2i, source_uid: String, damage: int,
		gem_ctx: Dictionary = {}, opts: Dictionary = {}) -> Array[Dictionary]:
	begin_reaction_chain()
	var cells := BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius())
	var events: Array[Dictionary] = [_EventBuilder.explode(center, CombatConfig.explosion_radius(), {
		"pattern": "square", "cells": cells, "source_uid": source_uid,
	})]
	events.append_array(_explode_square_damage(state, center, damage, source_uid, gem_ctx,
		int(opts.get("center_damage", damage)), str(opts.get("exclude_unit_uid", ""))))
	GemComboResolver.apply_after_explosion(state, cells, gem_ctx, events)
	end_reaction_chain()
	return events


static func _explode_square_damage(state: GameState, center: Vector2i, damage: int, source_uid: String,
		gem_ctx: Dictionary, center_damage: int, exclude_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var hit_uids: Dictionary = {}
	var knockback_targets: Array[UnitState] = []
	var center_unit := state.get_unit_at(center)
	var center_unit_uid := center_unit.uid if center_unit != null else ""
	var center_entity := state.get_entity_at(center)
	var center_entity_uid := center_entity.uid if center_entity != null else ""
	var collision_context := DamageContext.create(source_uid, "explosion_collision", ["explosion"], gem_ctx)
	state.log("爆炸于 %s" % [center])
	for cell in BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius()):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.max_hp > 0:
			EntityRules.damage_entity(state, entity,
				center_damage if entity.uid == center_entity_uid else damage, source_uid, events)
		var unit := state.get_unit_at(cell)
		if not _can_hit_unit(unit, source_uid, exclude_uid) or hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_damage_unit(state, unit, center_damage if unit.uid == center_unit_uid else damage,
			source_uid, "explosion", events, gem_ctx)
		_expose_armor_slots(state, unit)
		if unit.alive and unit.pos != center:
			knockback_targets.append(unit)
	for unit in knockback_targets:
		_Displacement.knockback(state, unit, center, 1, source_uid, events,
			CombatConfig.knockback_collision_damage(), true, collision_context)
	return events


static func _damage_unit(state: GameState, unit: UnitState, amount: int, source_uid: String,
		reason: String, events: Array[Dictionary], gem_ctx: Dictionary) -> void:
	var tx := _CombatTransaction.begin(state, events)
	tx.damage_unit(unit, amount, source_uid, reason, {"gem_tag_context": gem_ctx})


static func _can_hit_unit(unit: UnitState, source_uid: String, exclude_uid: String) -> bool:
	return unit != null and unit.alive and unit.uid != source_uid \
		and (exclude_uid.is_empty() or unit.uid != exclude_uid)


static func _expose_armor_slots(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)
