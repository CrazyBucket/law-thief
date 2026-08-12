class_name EnemyBehavior
extends RefCounted

const DamageContext = preload("res://scripts/rules/damage_context.gd")

const _EnemyAI := preload("res://scripts/rules/enemy_ai.gd")
const GemEffects = preload("res://scripts/rules/gem_effects.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
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


static func build_priority_target_intent(
	state: GameState,
	unit: UnitState,
	target: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var decision := _EnemyAI.decide_against_target(state, unit, target, cell_blockers)
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
	var damage := CombatRules.attack_damage(state, unit) + StatusConfig.int_value("lawless", "attack_bonus")
	var intent := IntentState.new()
	intent.base_damage = damage
	intent.source_uid = unit.uid
	intent.target_uid = target_uid
	if target_uid != "" and BoardUtils.manhattan(unit.pos, target_pos) <= CombatConfig.extract_range():
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


static func on_turn_start(_state: GameState, _unit: UnitState) -> void:
	pass


static func on_damage_taken(_state: GameState, _unit: UnitState, _amount: int, _source_uid: String = "") -> void:
	pass


static func build_melee_intent(state: GameState, unit: UnitState, _move_path: Array[Vector2i], intent: IntentState) -> void:
	var base_damage := CombatRules.attack_damage(state, unit)
	intent.base_damage = base_damage
	intent.damage = GemEffects.primary_attack_damage_preview(state, unit, base_damage)
	intent.preview_text = "近战攻击 (%d)" % intent.damage


static func build_ranged_intent(state: GameState, unit: UnitState, _move_path: Array[Vector2i], intent: IntentState) -> void:
	var base_damage := CombatRules.attack_damage(state, unit)
	intent.base_damage = base_damage
	intent.damage = GemEffects.primary_attack_damage_preview(state, unit, base_damage)
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
		"max_range": CombatConfig.attack_range(),
		"payload": {},
	}


static func split_clone_ratio(_unit: UnitState) -> float:
	return 0.0


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
		"impact_attack",
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
			return _events_from_result(boom_result)
		"charge_explode":
			return _execute_charge_explosion(state, unit, intent.target_uid)
		"poison_attack":
			var poison_target: UnitState = state.units.get(intent.target_uid, null)
			if poison_target == null or not poison_target.alive:
				return [] as Array[Dictionary]
			if not BoardUtils.are_units_adjacent(unit, poison_target):
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
			GemEffects.apply_arc_bounce_from_anchor(state, arc_target, unit, arc_events)
			return arc_events
		"split_attack":
			var split_target: UnitState = state.units.get(intent.target_uid, null)
			if split_target == null or not split_target.alive:
				return [] as Array[Dictionary]
			var split_result := CombatRules.split_melee_attack(state, unit, split_target)
			if not split_result.get("ok", false):
				return [] as Array[Dictionary]
			return _events_from_result(split_result)
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
			return _events_from_result(counter_result)
		"echo_attack":
			var echo_target: UnitState = state.units.get(intent.target_uid, null)
			if echo_target == null or not echo_target.alive:
				return [] as Array[Dictionary]
			var echo_result := CombatRules.ranged_attack(
					state,
					unit,
					echo_target.pos,
					GemEffects.red_attack_range(state, unit, CombatConfig.attack_range())
				)
			if not echo_result.get("ok", false):
				return [] as Array[Dictionary]
			return _events_from_result(echo_result)
		"impact_attack":
			var impact_target: UnitState = state.units.get(intent.target_uid, null)
			if impact_target == null or not impact_target.alive:
				return [] as Array[Dictionary]
			var impact_result := CombatRules.ranged_attack(
				state, unit, impact_target.pos, CombatConfig.attack_range()
			)
			if not impact_result.get("ok", false):
				return [] as Array[Dictionary]
			return _events_from_result(impact_result)
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
			return _events_from_result(result)
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
				var tx := _CombatTransaction.begin(state, events)
				tx.damage_unit(target, intent.damage, unit.uid, "lawless_attack", {
					"is_crit": true,
					"active_attack": true,
				})
			return {
				"handled": true,
				"events": events,
			}
		"lawless_extract":
			var extract_events: Array[Dictionary] = []
			if _execute_lawless_extract(state, unit, intent.target_uid):
				extract_events.append(_EventBuilder.gem_flash(unit.pos, {"color": Color(0.95, 0.25, 0.25)}))
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
	if BoardUtils.manhattan(unit.pos, target.pos) > CombatConfig.extract_range():
		return false
	var target_gem_uid := StatusRules.get_lawless_gem_uid(unit)
	var stolen_gem: GemState = state.gems.get(target_gem_uid, null)
	if stolen_gem == null:
		return false
	if target.uid == state.player_uid and state.held_gem_uid == target_gem_uid:
		if not _restore_lawless_gem(state, unit, stolen_gem):
			return false
		on_gem_inserted(state, unit, stolen_gem.uid)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	for slot in target.slots:
		if slot.gem_uid != target_gem_uid:
			continue
		if not _restore_lawless_gem(state, unit, stolen_gem):
			return false
		on_gem_inserted(state, unit, stolen_gem.uid)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	return false


static func _restore_lawless_gem(state: GameState, unit: UnitState, gem: GemState) -> bool:
	var red_slot := unit.get_slot(Constants.SLOT_RED)
	if red_slot != null and red_slot.gem_uid.is_empty():
		return _GemTransfer.to_unit_slot(state, gem, unit, red_slot)
	return false


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
	# The shared attack pipeline applies the gravity pull after the normal hit,
	# preserving both the unit's base damage and the authored range bonus. Enemy
	# gravity is target-locked like the player's normal attack, so scenery cannot
	# replace the intended victim during projectile presentation.
	var result := CombatRules.ranged_attack(
		state,
		unit,
		target.pos,
		CombatConfig.enemy_gravity_pull_range(),
		{"ignore_projectile_blockers": true}
	)
	if not bool(result.get("ok", false)):
		return [] as Array[Dictionary]
	var events: Array[Dictionary] = []
	for event in result.get("events", []):
		if event is Dictionary:
			events.append(event as Dictionary)
	return events


static func _events_from_result(result: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event in result.get("events", []):
		if event is Dictionary:
			events.append(event as Dictionary)
	return events


static func _execute_charge_explosion(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return events
	events.append(_EventBuilder.explode(unit.pos, CombatConfig.explosion_radius(), {"source_uid": unit.uid}))
	events.append_array(GemEffects.explode_at(state, unit.pos, CombatConfig.explosion_damage(), unit.uid))
	var tx := _CombatTransaction.begin(state, events)
	tx.damage_unit(unit, unit.hp, unit.uid, "self_explosion")
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
	var events: Array[Dictionary] = []
	var tx := _CombatTransaction.begin(state, events)
	tx.damage_unit(target, amount, unit.uid, reason, {
		"is_crit": is_crit,
		"active_attack": true,
	})
	return events
