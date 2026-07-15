class_name ScenarioBuilder
extends RefCounted

const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

var state: GameState
var _registry: Node
var _serial := 0


func _init(encounter_id: String = "fission_slime_test", seed: int = 1, clear_enemies: bool = true) -> void:
	_registry = Engine.get_main_loop().root.get_node("DataRegistry")
	state = _registry.create_battle_state(encounter_id, seed)
	if clear_enemies:
		for unit: UnitState in state.units.values().duplicate():
			if unit.team == Constants.TEAM_ENEMY:
				for slot: SlotState in unit.slots:
					if slot != null and not slot.gem_uid.is_empty():
						_GemTransfer.remove(state, slot.gem_uid)
				state.unregister_unit(unit)


func player() -> UnitState:
	return state.get_player()


func add_unit(
	uid: String,
	unit_def_id: String,
	team: String,
	pos: Vector2i,
	overrides: Dictionary = {}
) -> UnitState:
	var unit_def: Dictionary = _registry.get_unit_def(unit_def_id)
	var unit := UnitState.from_def(uid, unit_def_id, team, pos, unit_def)
	for field in ["hp", "max_hp", "base_attack", "move_points", "speed", "armor", "alive"]:
		if overrides.has(field):
			unit.set(field, overrides[field])
	state.register_unit(unit)
	return unit


func move(unit: UnitState, pos: Vector2i) -> ScenarioBuilder:
	state.move_unit(unit, pos)
	return self


func set_stats(unit: UnitState, overrides: Dictionary) -> ScenarioBuilder:
	for field in ["hp", "max_hp", "base_attack", "move_points", "speed", "armor", "alive"]:
		if overrides.has(field):
			unit.set(field, overrides[field])
	return self


func clear_slots(unit: UnitState) -> ScenarioBuilder:
	for slot: SlotState in unit.slots:
		if not slot.gem_uid.is_empty():
			_GemTransfer.remove(state, slot.gem_uid)
	return self


func mount_gems(unit: UnitState, slot_type: String, gem_ids: Array) -> ScenarioBuilder:
	while unit.slots_accepting(slot_type).size() < gem_ids.size():
		unit.slots.append(SlotState.create(slot_type))
	var slots := unit.slots_accepting(slot_type)
	for i in range(gem_ids.size()):
		var slot: SlotState = slots[i]
		if not slot.gem_uid.is_empty():
			_GemTransfer.remove(state, slot.gem_uid)
		_serial += 1
		var gem_uid := "scenario_gem_%d" % _serial
		var gem: GemState = _registry.create_gem_instance(gem_uid, str(gem_ids[i]), {})
		state.gems[gem_uid] = gem
		assert(_GemTransfer.to_unit_slot(state, gem, unit, slot))
	return self


func finish() -> GameState:
	state.rebuild_occupancy()
	return state
