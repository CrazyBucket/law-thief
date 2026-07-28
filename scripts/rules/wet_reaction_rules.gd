class_name WetReactionRules
extends RefCounted

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")


static func consume_for_fire(
	state: GameState,
	unit: UnitState,
	burning_stacks: int,
	source_uid: String
) -> int:
	if not unit.has_status(Constants.STATUS_WET):
		return burning_stacks
	unit.remove_status(Constants.STATUS_WET)
	_record_consumption(state, unit, source_uid, "fire")
	state.log("%s 的潮湿抵消了 1 层着火" % unit.uid)
	return maxi(0, burning_stacks - 1)


static func apply_arc(
	state: GameState,
	anchor: UnitState,
	attacker: UnitState,
	events: Array[Dictionary],
	gem_ctx: Dictionary
) -> void:
	if state == null or anchor == null or attacker == null:
		return
	var arc_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	var level_def: Dictionary = registry.get_gem_effect_level_def("arc", Constants.SLOT_RED, arc_level)
	var arc_range := int(level_def.get("range", 2)) + 1
	var arc_damage := GemEffects.arc_reaction_damage(attacker, state)
	GemEffects.arc_reaction_hit(state, attacker.pos, anchor, attacker.uid, arc_damage, events, gem_ctx)
	if anchor.has_status(Constants.STATUS_WET):
		anchor.remove_status(Constants.STATUS_WET)
		_record_consumption(state, anchor, attacker.uid, "arc")
	var targets: Array[UnitState] = []
	for unit: UnitState in state.units.values():
		if not unit.alive or unit.uid == anchor.uid:
			continue
		if BoardUtils.chebyshev(anchor.pos, unit.pos) > arc_range:
			continue
		if not unit.has_status(Constants.STATUS_WET) \
				and not TileRules.unit_occupies_modifier(state, unit, Constants.TILE_MOD_SHALLOW_WATER):
			continue
		targets.append(unit)
	targets.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	for target in targets:
		GemEffects.arc_reaction_hit(state, anchor.pos, target, attacker.uid, arc_damage, events, gem_ctx)
		if target.has_status(Constants.STATUS_WET):
			target.remove_status(Constants.STATUS_WET)
			_record_consumption(state, target, attacker.uid, "arc_conduction")


static func _record_consumption(
	state: GameState,
	unit: UnitState,
	source_uid: String,
	reaction: String
) -> void:
	state.bump_revision()
	state.record_transaction("consume_wet", {
		"uid": unit.uid,
		"source_uid": source_uid,
		"reaction": reaction,
	})
