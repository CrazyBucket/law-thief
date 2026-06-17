class_name EnemyBehavior
extends RefCounted

const _EnemyAI := preload("res://scripts/rules/enemy_ai.gd")
const GemEffects = preload("res://scripts/rules/gem_effects.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	if StatusRules.is_lawless(unit):
		return build_lawless_intent(state, unit, cell_blockers)
	return build_normal_intent(state, unit, cell_blockers)


static func run_ai_decide(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> Dictionary:
	return _EnemyAI.decide(state, unit, cell_blockers)


static func build_normal_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var decision := run_ai_decide(state, unit, cell_blockers)
	return IntentSystem.enemy_intent_from_decision(state, unit, decision, cell_blockers)


static func build_lawless_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var gem: GemState = state.gems.get(StatusRules.get_lawless_gem_uid(unit), null)
	var target_pos := unit.pos
	var target_uid := ""
	if gem != null:
		var carrier := _find_gem_carrier(state, gem)
		if carrier != null:
			target_pos = carrier.pos
			target_uid = carrier.uid
	var damage := CombatRules.attack_damage(state, unit) + 1
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = target_uid
	if target_uid != "" and BoardUtils.manhattan(unit.pos, target_pos) <= Constants.EXTRACT_RANGE:
		intent.type = "lawless_extract"
		intent.target_pos = unit.pos
		intent.preview_text = "失律夺回宝石"
		return intent
	intent.path = BoardUtils.path_toward(
		state, unit.pos, target_pos, unit.move_points, unit.uid, {}, cell_blockers, unit
	)
	intent.target_pos = intent.path.back() if not intent.path.is_empty() else unit.pos
	if target_uid != "" and BoardUtils.manhattan(intent.target_pos, target_pos) == 1:
		intent.type = "lawless_attack"
		intent.damage = damage
		intent.preview_text = "失律狂袭 (%d)" % damage
	else:
		intent.type = "lawless_move"
		intent.preview_text = "失律追逐宝石"
	return intent


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	if unit.team != Constants.TEAM_ENEMY:
		return
	if unit_has_any_gem(unit):
		return
	on_red_gem_stolen(state, unit, gem_uid)


static func unit_has_any_gem(unit: UnitState) -> bool:
	for slot in unit.slots:
		if not slot.gem_uid.is_empty():
			return true
	return false


static func on_gem_inserted(_state: GameState, unit: UnitState, gem_uid: String) -> void:
	if StatusRules.is_lawless(unit) and StatusRules.get_lawless_gem_uid(unit) == gem_uid:
		on_lawless_recovered(unit)
		StatusRules.clear_lawless(unit)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StatusRules.apply_lawless(state, unit, gem_uid)


static func on_lawless_recovered(_unit: UnitState) -> void:
	pass


static func on_unit_death(_state: GameState, _unit: UnitState) -> void:
	pass


static func build_melee_intent(state: GameState, unit: UnitState, _move_path: Array[Vector2i], intent: IntentState) -> void:
	intent.damage = CombatRules.attack_damage(state, unit)
	intent.preview_text = "近战攻击 (%d)" % intent.damage


static func build_ranged_intent(state: GameState, unit: UnitState, _move_path: Array[Vector2i], intent: IntentState) -> void:
	intent.damage = CombatRules.attack_damage(state, unit)
	intent.preview_text = "远程射击 (%d)" % intent.damage


static func melee_charge_bonus(
	_state: GameState,
	_unit: UnitState,
	_move_start_pos: Vector2i,
	_intent_path: Array[Vector2i],
	_target_uid: String = ""
) -> int:
	return 0


static func ranged_attack_context(
	_state: GameState,
	_unit: UnitState,
	_move_start_pos: Vector2i,
	_intent_path: Array[Vector2i]
) -> Dictionary:
	return {
		"max_range": Constants.ATTACK_RANGE,
		"payload": {},
	}


static func split_clone_ratio(_unit: UnitState) -> float:
	return Constants.SPLIT_STAT_RATIO


static func should_trigger_split_blue(_unit: UnitState, reason: String) -> bool:
	return is_single_target_damage_reason(reason)


static func is_single_target_damage_reason(reason: String) -> bool:
	const SINGLE_TARGET_REASONS: Array[String] = [
		"melee_attack",
		"ranged_attack",
		"lawless_attack",
		"bomb_rat_plunder",
		"poison_attack",
		"arc_attack",
		"fire_attack",
		"ice_attack",
		"split_attack",
		"split_wing",
		Constants.DAMAGE_REASON_SLAM,
	]
	return reason in SINGLE_TARGET_REASONS


static func execute_red_action(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	match intent.type:
		"explosion_attack":
			var boom_target: UnitState = state.units.get(intent.target_uid, null)
			if boom_target == null or not boom_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, boom_target):
				return [] as Array[Dictionary]
			var boom_result := CombatRules.melee_attack(state, unit, boom_target)
			if not boom_result.get("ok", false):
				return [] as Array[Dictionary]
			return boom_result.get("events", [] as Array[Dictionary])
		"charge_explode":
			return _execute_charge_explosion(state, unit, intent.target_uid)
		"poison_attack":
			var poison_target: UnitState = state.units.get(intent.target_uid, null)
			if poison_target == null or not poison_target.alive:
				return [] as Array[Dictionary]
			if BoardUtils.manhattan(unit.pos, poison_target.pos) != 1:
				return [] as Array[Dictionary]
			var poison_events := _enemy_red_damage_events(
				state, unit, intent.target_uid, CombatRules.attack_damage(state, unit), "poison_attack"
			)
			if poison_target.alive:
				StatusRules.apply_poison(state, poison_target)
			return poison_events
		"pull":
			return _execute_pull_events(state, unit, intent.target_uid)
		"arc_attack":
			var arc_target: UnitState = state.units.get(intent.target_uid, null)
			if arc_target == null or not arc_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, arc_target):
				return [] as Array[Dictionary]
			var arc_base := CombatRules.attack_damage(state, unit)
			var arc_events := _enemy_red_damage_events(state, unit, intent.target_uid, arc_base, "arc_attack")
			if arc_target.alive:
				GemEffects.apply_arc_bounce_from_victim(state, arc_target, unit, arc_base, arc_events)
			return arc_events
		"split_attack":
			var split_target: UnitState = state.units.get(intent.target_uid, null)
			if split_target == null or not split_target.alive:
				return [] as Array[Dictionary]
			var split_result := CombatRules.split_melee_attack(state, unit, split_target)
			if not split_result.get("ok", false):
				return [] as Array[Dictionary]
			return split_result.get("events", [] as Array[Dictionary])
		"fire_attack":
			var fire_target: UnitState = state.units.get(intent.target_uid, null)
			if fire_target == null or not fire_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, fire_target):
				return [] as Array[Dictionary]
			var fire_events := _enemy_red_damage_events(
				state, unit, intent.target_uid, CombatRules.attack_damage(state, unit), "fire_attack"
			)
			if fire_target.alive:
				StatusRules.apply_burning(state, fire_target, 1, unit.uid)
			return fire_events
		"ice_attack":
			var ice_target: UnitState = state.units.get(intent.target_uid, null)
			if ice_target == null or not ice_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, ice_target):
				return [] as Array[Dictionary]
			var ice_events := _enemy_red_damage_events(
				state, unit, intent.target_uid, CombatRules.attack_damage(state, unit), "ice_attack"
			)
			if ice_target.alive:
				GemEffects.apply_ice_hit_effect(state, ice_target, unit.uid)
			return ice_events
		"counter_attack":
			var counter_target: UnitState = state.units.get(intent.target_uid, null)
			if counter_target == null or not counter_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, counter_target):
				return [] as Array[Dictionary]
			var counter_result := CombatRules.melee_attack(state, unit, counter_target)
			if not counter_result.get("ok", false):
				return [] as Array[Dictionary]
			return counter_result.get("events", [] as Array[Dictionary])
		"echo_attack":
			var echo_target: UnitState = state.units.get(intent.target_uid, null)
			if echo_target == null or not echo_target.alive:
				return [] as Array[Dictionary]
			var echo_result := CombatRules.ranged_attack(
				state,
				unit,
				echo_target.pos,
				GemEffects.red_attack_range(state, unit, Constants.ATTACK_RANGE)
			)
			if not echo_result.get("ok", false):
				return [] as Array[Dictionary]
			return echo_result.get("events", [] as Array[Dictionary])
		"light_beam":
			var light_target: UnitState = state.units.get(intent.target_uid, null)
			if light_target == null or not light_target.alive:
				return [] as Array[Dictionary]
			var result := CombatRules.ranged_attack(
				state,
				unit,
				light_target.pos,
				Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
			)
			if not result.get("ok", false):
				return [] as Array[Dictionary]
			return result.get("events", [] as Array[Dictionary])
		_:
			return [] as Array[Dictionary]


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	match intent.type:
		"lawless_move":
			return {
				"handled": true,
				"events": [] as Array[Dictionary],
			}
		"lawless_attack":
			var events: Array[Dictionary] = []
			var target: UnitState = state.units.get(intent.target_uid, null)
			if target != null and target.alive and BoardUtils.manhattan(unit.pos, target.pos) == 1:
				var dealt := CombatRules.apply_damage(state, target, intent.damage, unit.uid, "lawless_attack")
				if dealt > 0:
					events.append(_EventBuilder.damage(target, dealt, {
						"is_crit": true,
						"attacker_uid": unit.uid,
						"source_uid": unit.uid,
						"reason": "lawless_attack",
						"lethal": not target.alive,
						"remaining_hp": target.hp,
					}))
			return {
				"handled": true,
				"events": events,
			}
		"lawless_extract":
			var extract_events: Array[Dictionary] = []
			if _execute_lawless_extract(state, unit, intent.target_uid):
				extract_events.append({"type": "gem_flash", "pos": unit.pos, "color": Color(0.95, 0.25, 0.25)})
			return {
				"handled": true,
				"events": extract_events,
			}
		_:
			return {
				"handled": false,
				"events": [] as Array[Dictionary],
			}


static func _execute_lawless_extract(state: GameState, unit: UnitState, target_uid: String) -> bool:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return false
	if BoardUtils.manhattan(unit.pos, target.pos) > Constants.EXTRACT_RANGE:
		return false
	var target_gem_uid := StatusRules.get_lawless_gem_uid(unit)
	var stolen_gem: GemState = state.gems.get(target_gem_uid, null)
	if stolen_gem == null:
		return false
	if target.uid == state.player_uid and state.held_gem_uid == target_gem_uid:
		state.held_gem_uid = ""
		_restore_lawless_gem(unit, stolen_gem)
		on_gem_inserted(state, unit, stolen_gem.uid)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	for slot in target.slots:
		if slot.gem_uid != target_gem_uid:
			continue
		slot.gem_uid = ""
		_restore_lawless_gem(unit, stolen_gem)
		on_gem_inserted(state, unit, stolen_gem.uid)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	return false


static func _restore_lawless_gem(unit: UnitState, gem: GemState) -> void:
	var red_slot := unit.get_slot(Constants.SLOT_RED)
	if red_slot != null and red_slot.gem_uid.is_empty():
		red_slot.gem_uid = gem.uid
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(red_slot)
		return
	gem.owner_uid = unit.uid
	gem.slot_index = -1


static func _find_gem_carrier(state: GameState, gem: GemState) -> UnitState:
	if state.held_gem_uid == gem.uid:
		return state.get_player()
	for current in state.units.values():
		if not current.alive:
			continue
		for slot in current.slots:
			if slot.gem_uid == gem.uid:
				return current
	return null


static func _execute_pull_events(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var max_range := GemEffects.gravity_pull_range(state, unit, CombatConfig.enemy_gravity_pull_range())
	if BoardUtils.manhattan(unit.pos, target.pos) > max_range:
		return [] as Array[Dictionary]
	var pull_steps := maxi(1, GemTagResolver.tag_level(
		GemTagResolver.build_context(state, unit, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE),
		"gravity"
	))
	return GemEffects.pull_unit_toward_with_events(state, target, unit.pos, pull_steps, unit.uid)


static func _execute_charge_explosion(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return events
	events.append({"type": "explode", "pos": unit.pos, "radius": Constants.EXPLOSION_RADIUS})
	events.append_array(GemEffects.explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid))
	var self_dealt := CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "self_explosion")
	if self_dealt > 0:
		events.append(_EventBuilder.damage(unit, self_dealt, {
			"attacker_uid": unit.uid,
			"source_uid": unit.uid,
			"reason": "self_explosion",
			"lethal": not unit.alive,
			"remaining_hp": unit.hp,
		}))
	return events


static func _enemy_red_damage_events(
	state: GameState,
	unit: UnitState,
	target_uid: String,
	amount: int,
	reason: String,
	is_crit: bool = false
) -> Array[Dictionary]:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var dealt := CombatRules.apply_damage(state, target, amount, unit.uid, reason)
	if dealt <= 0:
		return [] as Array[Dictionary]
	return [_EventBuilder.damage(target, dealt, {
		"is_crit": is_crit,
		"attacker_uid": unit.uid,
		"source_uid": unit.uid,
		"reason": reason,
		"lethal": not target.alive,
		"remaining_hp": target.hp,
	})]
