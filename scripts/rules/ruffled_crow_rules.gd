class_name RuffledCrowRules
extends RefCounted

const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")


static func on_turn_start(state: GameState, unit: UnitState) -> void:
	if StatusRules.is_lawless(unit):
		_add_feathers(state, unit, 1, unit.uid)


static func on_damage_taken(state: GameState, unit: UnitState, amount: int, source_uid: String = "") -> void:
	if amount > 0 and unit.alive and StatusRules.is_lawless(unit):
		_add_feathers(state, unit, 1, source_uid)


static func enter_disorder(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)


static func recover_order(unit: UnitState) -> void:
	StatusRules.clear_lawless(unit)
	unit.remove_status(Constants.STATUS_STARTLED_FEATHER)


static func normal_hit_chance(unit: UnitState) -> float:
	return clampf(float(_balance(unit, "hit_chance", 0.9)), 0.0, 1.0)


static func disorder_hit_chance(unit: UnitState) -> float:
	var penalty := float(_balance(unit, "feather_hit_penalty", 0.1)) * float(feathers(unit))
	return maxf(float(_balance(unit, "min_hit_chance", 0.2)), normal_hit_chance(unit) - penalty)


static func disorder_hit_count(unit: UnitState) -> int:
	return 1 + feathers(unit)


static func segment_damage(state: GameState, unit: UnitState) -> int:
	var percent := roundi(segment_damage_ratio(unit) * 100.0)
	return maxi(1, floori(float(CombatRules.attack_damage(state, unit) * percent) / 100.0))


static func segment_damage_ratio(unit: UnitState) -> float:
	return float(_balance(unit, "segment_damage_ratio", 0.4))


static func normal_preview(state: GameState, unit: UnitState) -> Dictionary:
	var base_damage := CombatRules.attack_damage(state, unit)
	var flurry_value := FlurryRules.red_flurry_value(state, unit) + FlurryRules.stored(unit)
	var count := 1 + flurry_value
	return {
		"count": count,
		"segment_damage": FlurryRules.segment_damage(base_damage, 1, flurry_value),
	}


static func feathers(unit: UnitState) -> int:
	var status: StatusInstance = unit.get_status(Constants.STATUS_STARTLED_FEATHER)
	return maxi(0, status.stacks) if status != null else 0


static func halve_feathers(unit: UnitState) -> void:
	var status: StatusInstance = unit.get_status(Constants.STATUS_STARTLED_FEATHER)
	if status == null:
		return
	status.stacks = int(status.stacks / 2)
	if status.stacks <= 0:
		unit.remove_status(Constants.STATUS_STARTLED_FEATHER)


static func _add_feathers(state: GameState, unit: UnitState, stacks: int, source_uid: String) -> void:
	StatusRules._apply(state, unit, Constants.STATUS_STARTLED_FEATHER, {
		"stacks": stacks,
		"source_uid": source_uid,
	})


static func _balance(unit: UnitState, key: String, fallback: Variant) -> Variant:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	if registry == null:
		return fallback
	return registry.get_unit_balance_value(unit.unit_def_id, key, fallback)
