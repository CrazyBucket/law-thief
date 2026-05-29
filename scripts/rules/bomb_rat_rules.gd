class_name BombRatRules
extends RefCounted

const PLUNDER_PHASE_WAIT := 1
const PLUNDER_PHASE_STEAL := 2


static func black_slot_empty(unit: UnitState) -> bool:
	var black := unit.get_slot(Constants.SLOT_BLACK)
	return black == null or black.gem_uid.is_empty()


static func sync_plunder_state(state: GameState, unit: UnitState) -> void:
	if not unit.alive:
		return
	if black_slot_empty(unit):
		if StatusRules.get_bomb_rat_plunder_phase(unit) < 0:
			StatusRules.apply_bomb_rat_plunder(state, unit, PLUNDER_PHASE_WAIT)
	else:
		StatusRules.clear_bomb_rat_plunder(unit)


static func compute_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	sync_plunder_state(state, unit)
	var phase := StatusRules.get_bomb_rat_plunder_phase(unit)
	if phase == PLUNDER_PHASE_WAIT:
		return _plunder_wait_intent(unit)
	if phase == PLUNDER_PHASE_STEAL:
		return _plunder_steal_intent(state, unit, cell_blockers)
	return _chase_suicide_intent(state, unit, cell_blockers)


static func execute_black_suicide(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not unit.alive:
		return events
	GemEffects.trigger_black_death_effects(state, unit, events)
	var black := unit.get_slot(Constants.SLOT_BLACK)
	if black != null:
		black.gem_uid = ""
	StatusRules.clear_bomb_rat_plunder(unit)
	if unit.hp > 0:
		CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "black_suicide")
	return events


static func execute_plunder_wait(unit: UnitState) -> void:
	StatusRules.set_bomb_rat_plunder_phase(unit, PLUNDER_PHASE_STEAL)


static func execute_plunder_steal(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target != null and target.alive and BoardUtils.manhattan(unit.pos, target.pos) == 1:
		var dealt := CombatRules.apply_damage(state, target, intent.damage, unit.uid, "bomb_rat_plunder")
		if dealt > 0:
			events.append({
				"type": "damage",
				"pos": target.pos,
				"damage": dealt,
				"is_crit": false,
				"attacker_uid": unit.uid,
			})
		if target.alive:
			_force_steal_nearest_gem(state, unit, target, events)
	StatusRules.clear_bomb_rat_plunder(unit)
	sync_plunder_state(state, unit)
	return events


static func _chase_suicide_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary
) -> IntentState:
	var player := state.get_player()
	if player == null or not player.alive:
		return IntentState.wait(unit.uid)
	if BoardUtils.manhattan(unit.pos, player.pos) == 1:
		return _suicide_intent(unit, player.uid)
	var path := BoardUtils.path_toward(
		state,
		unit.pos,
		player.pos,
		unit.move_points,
		unit.uid,
		{},
		cell_blockers
	)
	var end_pos: Vector2i = path.back() if not path.is_empty() else unit.pos
	if BoardUtils.manhattan(end_pos, player.pos) == 1:
		var suicide := _suicide_intent(unit, player.uid)
		suicide.path = path
		return suicide
	var intent := IntentState.new()
	intent.type = "move"
	intent.source_uid = unit.uid
	intent.target_uid = player.uid
	intent.path = path
	intent.target_pos = end_pos
	intent.preview_text = "突进靠近"
	return intent


static func _suicide_intent(unit: UnitState, target_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "black_suicide"
	intent.source_uid = unit.uid
	intent.target_uid = target_uid
	intent.preview_text = "黑槽自爆"
	return intent


static func _plunder_wait_intent(unit: UnitState) -> IntentState:
	var intent := IntentState.new()
	intent.type = "bomb_rat_plunder_wait"
	intent.source_uid = unit.uid
	intent.preview_text = "无律发呆"
	return intent


static func _plunder_steal_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary
) -> IntentState:
	var victim := _nearest_gem_carrier(state, unit)
	if victim == null:
		return IntentState.wait(unit.uid)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = victim.uid
	intent.damage = CombatRules.attack_damage(state, unit)
	if BoardUtils.manhattan(unit.pos, victim.pos) == 1:
		intent.type = "bomb_rat_plunder_steal"
		intent.preview_text = "无律掠夺 (%d)" % intent.damage
		return intent
	intent.path = BoardUtils.path_toward(
		state,
		unit.pos,
		victim.pos,
		unit.move_points,
		unit.uid,
		{},
		cell_blockers
	)
	var end_pos: Vector2i = intent.path.back() if not intent.path.is_empty() else unit.pos
	if BoardUtils.manhattan(end_pos, victim.pos) == 1:
		intent.type = "bomb_rat_plunder_steal"
		intent.preview_text = "无律掠夺 (%d)" % intent.damage
	else:
		intent.type = "move"
		intent.preview_text = "无律追猎"
	intent.target_pos = end_pos
	return intent


static func _nearest_gem_carrier(state: GameState, rat: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999
	for unit in state.units.values():
		if not unit.alive or unit.uid == rat.uid:
			continue
		if not _has_stealable_gem(unit):
			continue
		var dist := BoardUtils.manhattan(rat.pos, unit.pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


static func _has_stealable_gem(unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		return true
	return false


static func _force_steal_nearest_gem(
	state: GameState,
	rat: UnitState,
	victim: UnitState,
	events: Array[Dictionary]
) -> void:
	var stolen_slot: SlotState = null
	for slot in victim.slots:
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		stolen_slot = slot
		break
	if stolen_slot == null:
		return
	var gem: GemState = state.gems.get(stolen_slot.gem_uid, null)
	if gem == null:
		return
	stolen_slot.gem_uid = ""
	if stolen_slot.slot_type == Constants.SLOT_RED and victim.team == Constants.TEAM_ENEMY:
		StatusRules.apply_lawless(state, victim, gem.uid)
	var host := rat.get_slot(Constants.SLOT_BLACK)
	if host == null or not host.gem_uid.is_empty():
		for slot in rat.slots:
			if slot.gem_uid.is_empty() and not slot.locked:
				host = slot
				break
	if host == null or not host.gem_uid.is_empty():
		return
	host.gem_uid = gem.uid
	gem.owner_uid = rat.uid
	gem.slot_index = rat.slots.find(host)
	state.log(
		"%s 无律掠夺：夺取 %s 的 %s 并嵌入 %s 槽"
		% [rat.uid, victim.uid, _data_registry().get_gem_display_name(gem), host.slot_type]
	)
	events.append({"type": "gem_flash", "pos": rat.pos, "color": Color(0.95, 0.25, 0.25)})


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
