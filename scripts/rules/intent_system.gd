class_name IntentSystem
extends RefCounted

const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const EventValidator = preload("res://scripts/debug/event_validator.gd")
const IntentPreviewRules = preload("res://scripts/rules/intent_preview_rules.gd")
const _EnemyAI := preload("res://scripts/rules/enemy_ai.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _FightTicketRules = preload("res://scripts/rules/fight_ticket_rules.gd")
## 意图系统 —— 基于 Utility AI 的敌人决策
## 每回合开始时为所有敌人计算最优行动，生成 IntentState 供 UI 预览

const ATTACK_INTENT_TYPES := [
	"melee_attack",
	"ranged_attack",
	"explosion_attack",
	"charge_explode",
	"pull",
	"poison_attack",
	"arc_attack",
	"fire_attack",
	"ice_attack",
	"split_attack",
	"light_beam",
	"counter_attack",
	"echo_attack",
	"impact_attack",
	"rolling_uncontrolled",
	"trample",
	"slam_attack",
	"lawless_attack",
	"bomb_rat_plunder_steal",
	"broodmother_ranged_attack",
	"mage_spell",
	"mage_staff_attack",
	"mage_impact_charge",
]
## 敌人回合执行时按照预计算的意图行动


static func refresh_all_intents(state: GameState) -> void:
	var cell_blockers := build_cell_occupancy(state)
	var enemies := _sorted_enemies_for_planning(state)
	for enemy in enemies:
		if not enemy.alive:
			continue
		var start_pos: Vector2i = enemy.pos
		enemy.intent = _compute_intent_from_ai(state, enemy, cell_blockers)
		_apply_planned_occupancy(state, cell_blockers, enemy, start_pos, intent_end_pos(enemy, enemy.intent))


## 按当前棋盘重算单个敌人意图（敌方回合逐个行动前调用）
static func refresh_unit_intent(state: GameState, unit: UnitState) -> void:
	if not unit.alive or unit.team != Constants.TEAM_ENEMY:
		return
	unit.intent = _compute_intent_from_ai(state, unit, build_cell_occupancy(state))


static func build_cell_occupancy(state: GameState) -> Dictionary:
	var occupancy: Dictionary = {}
	for unit in state.units.values():
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			occupancy[state.tile_key(cell)] = unit.uid
	return occupancy


static func intent_end_pos(unit: UnitState, intent: IntentState) -> Vector2i:
	if intent == null:
		return unit.pos
	if not intent.path.is_empty():
		return intent.path[intent.path.size() - 1]
	if intent.target_pos.x >= 0 and intent.target_pos.y >= 0:
		return intent.target_pos
	return unit.pos


static func _apply_planned_occupancy(
	state: GameState,
	cell_blockers: Dictionary,
	unit: UnitState,
	old_anchor: Vector2i,
	new_anchor: Vector2i
) -> void:
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, old_anchor):
		var old_key := state.tile_key(cell)
		if str(cell_blockers.get(old_key, "")) == unit.uid:
			cell_blockers.erase(old_key)
	for cell in BoardUtils.footprint_cells_at(unit.footprint_size, new_anchor):
		cell_blockers[state.tile_key(cell)] = unit.uid


static func _sorted_enemies_for_planning(state: GameState) -> Array:
	var enemies: Array = []
	for unit in state.units.values():
		if unit.alive and unit.team == Constants.TEAM_ENEMY:
			enemies.append(unit)
	enemies.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var a_slug: bool = a.has_status(Constants.STATUS_SLUGGISH)
		var b_slug: bool = b.has_status(Constants.STATUS_SLUGGISH)
		if a_slug != b_slug:
			return not a_slug
		if a.speed == b.speed:
			return a.uid < b.uid
		return a.speed > b.speed
	)
	return enemies


static func _compute_intent_from_ai(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var behavior: GDScript = _behavior_for(unit)
	var retaliation_target: UnitState = _FightTicketRules.retaliation_target(state, unit)
	var intent: IntentState = null
	if retaliation_target != null:
		intent = behavior.build_priority_target_intent(state, unit, retaliation_target, cell_blockers)
	else:
		intent = behavior.compute_intent(state, unit, cell_blockers)
	if intent != null and not StatusRules.can_attack(unit) and is_attack_intent(intent.type):
		intent = _movement_only_intent(unit, intent)
	if intent != null:
		if not intent.target_uid.is_empty():
			if state.units.has(intent.target_uid):
				intent.plan_metadata["target_kind"] = "unit"
			elif state.gems.has(intent.target_uid):
				intent.plan_metadata["target_kind"] = "gem"
		IntentPreviewRules.populate(state, unit, intent)
		if retaliation_target != null:
			_FightTicketRules.tag_intent(intent, retaliation_target)
		intent.finalize_action_plan(state.turn_index, unit.pos)
	return intent


static func is_attack_intent(intent_type: String) -> bool:
	return intent_type in ATTACK_INTENT_TYPES


static func _movement_only_intent(unit: UnitState, planned: IntentState) -> IntentState:
	if planned.path.is_empty():
		return IntentState.wait(unit.uid)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.type = "move"
	intent.path = planned.path.duplicate()
	intent.target_pos = intent.path[-1]
	intent.target_uid = planned.target_uid
	intent.preview_text = "移动"
	return intent


static func _behavior_for(unit: UnitState) -> GDScript:
	return BehaviorRegistry.get_behavior(unit.behavior_id)


static func enemy_intent_from_decision(
	state: GameState,
	unit: UnitState,
	decision: Dictionary,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var action = decision.get("action", null)
	var move_path: Array[Vector2i] = decision.get("move_path", [] as Array[Vector2i])
	if action == null:
		return IntentState.wait(unit.uid)

	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.path = move_path

	match action.type:
		_EnemyAI.ActionType.RANGED_ATTACK:
			intent.type = "ranged_attack"
			intent.target_uid = action.action_target_uid
			intent.target_pos = action.move_target
			_behavior_for(unit).build_ranged_intent(state, unit, move_path, intent)

		_EnemyAI.ActionType.ATTACK:
			intent.type = "melee_attack"
			intent.target_uid = action.action_target_uid
			intent.target_pos = action.move_target
			_behavior_for(unit).build_melee_intent(state, unit, move_path, intent)

		_EnemyAI.ActionType.SKILL_RED:
			var red_slot := unit.get_slot(Constants.SLOT_RED)
			if red_slot != null and not red_slot.gem_uid.is_empty():
				var gem: GemState = state.gems.get(red_slot.gem_uid, null)
				if gem != null:
					intent = _build_skill_intent(state, unit, gem, action, move_path, cell_blockers)
				else:
					intent = IntentState.wait(unit.uid)
			else:
				intent = IntentState.wait(unit.uid)

		_EnemyAI.ActionType.EXTRACT:
			intent.type = "extract"
			intent.target_uid = action.action_target_uid
			intent.target_pos = action.move_target
			intent.preview_text = "窃取宝石"

		_EnemyAI.ActionType.MOVE:
			intent.type = "move"
			intent.target_pos = action.move_target
			intent.preview_text = "移动"
			intent.target_uid = action.action_target_uid

		_EnemyAI.ActionType.WAIT:
			return IntentState.wait(unit.uid)

	return intent


static func _build_skill_intent(
	state: GameState,
	unit: UnitState,
	gem: GemState,
	action,
	move_path: Array[Vector2i],
	cell_blockers: Dictionary = {}
) -> IntentState:
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = action.action_target_uid
	intent.path = move_path.duplicate()
	var base_damage := CombatRules.attack_damage(state, unit)
	intent.base_damage = base_damage
	var meta: Dictionary = GemEffects.get_enemy_red_intent_meta(gem, base_damage)
	intent.type = meta.get("type", "wait")
	intent.preview_text = meta.get("preview", "等待")
	intent.damage = int(meta.get("damage", 0))
	if intent.type == "wait":
		return IntentState.wait(unit.uid)
	if intent.type == "charge_explode":
		var target: UnitState = state.units.get(action.action_target_uid, null)
		if target != null:
			var dash_from: Vector2i = intent.path[-1] if not intent.path.is_empty() else unit.pos
			var charge_path := BoardUtils.path_toward(
				state, dash_from, target.pos, CombatConfig.charge_explode_dash_range(), unit.uid, {}, cell_blockers
			)
			for step in charge_path:
				intent.path.append(step)
			var end_pos: Vector2i = intent.path[-1] if not intent.path.is_empty() else unit.pos
			intent.affected_cells = BoardUtils.cells_in_radius(end_pos, CombatConfig.explosion_radius())
			intent.target_pos = end_pos
			intent.preview_text = "冲刺爆炸 (%d)" % CombatConfig.explosion_damage()
	return intent


## 执行意图并返回动画事件列表
## 每个事件: {type: "move_step"|"damage"|"explode"|"gem_flash", ...}
static func execute_intent(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var anim_events: Array[Dictionary] = []
	if not unit.alive:
		return anim_events
	if unit.team != Constants.TEAM_ENEMY:
		return anim_events
	if not StatusRules.can_act(unit):
		return anim_events
	if unit.intent.action_plan != null and not unit.intent.action_plan.is_applicable(state, unit):
		refresh_unit_intent(state, unit)
		if unit.intent == null:
			return anim_events
	var intent := unit.intent.execution_view(state.turn_index, unit.pos)
	if intent == null:
		return anim_events

	var move_start_pos: Vector2i = unit.pos
	if StatusRules.can_move(unit) and not intent.path.is_empty():
		var move_events := _execute_move(state, unit, intent)
		anim_events.append_array(move_events)
	if is_attack_intent(intent.type) and not StatusRules.can_attack(unit):
		return _validated_events(anim_events, "IntentSystem.execute_intent:%s" % intent.type)

	var custom_result: Dictionary = _behavior_for(unit).execute_custom_intent(state, unit, intent, move_start_pos)
	if bool(custom_result.get("handled", false)):
		anim_events.append_array(custom_result.get("events", [] as Array[Dictionary]))
		return _validated_events(anim_events, "IntentSystem.execute_intent:%s" % intent.type)

	match intent.type:
		"melee_attack":
			anim_events.append_array(_execute_melee(state, unit, intent, move_start_pos))
		"ranged_attack":
			anim_events.append_array(_execute_ranged(state, unit, intent, move_start_pos))
		"explosion_attack", "charge_explode", "pull", "poison_attack", "arc_attack", "fire_attack", "ice_attack", "split_attack", "light_beam", "counter_attack", "echo_attack", "impact_attack":
			anim_events.append_array(_behavior_for(unit).execute_red_action(state, unit, intent))
		"extract":
			_execute_extract(state, unit, intent)
			anim_events.append(_EventBuilder.gem_flash(intent.target_pos, {"color": Color(0.9, 0.2, 0.2)}))
		"move":
			pass # 纯移动，无行动

	return _validated_events(anim_events, "IntentSystem.execute_intent:%s" % intent.type)


static func _execute_melee(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	move_start_pos: Vector2i
) -> Array[Dictionary]:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var charge_bonus: int = int(_behavior_for(unit).melee_charge_bonus(
		state, unit, move_start_pos, intent.path, intent.target_uid
	))
	var result := CombatRules.melee_attack(state, unit, target, charge_bonus)
	if not result.get("ok", false):
		return [] as Array[Dictionary]
	return _events_from_result(result)


static func _execute_ranged(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	move_start_pos: Vector2i
) -> Array[Dictionary]:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var attack_ctx: Dictionary = _behavior_for(unit).ranged_attack_context(state, unit, move_start_pos, intent.path)
	var max_range: int = int(attack_ctx.get("max_range", CombatConfig.attack_range()))
	var payload_variant: Variant = attack_ctx.get("payload", {})
	var payload: Dictionary = payload_variant if payload_variant is Dictionary else {}
	var aim_cell: Vector2i = target.pos
	var raw_aim: Variant = payload.get("aim_cell", null)
	if raw_aim is Vector2i:
		aim_cell = raw_aim
	var result := CombatRules.ranged_attack(state, unit, aim_cell, max_range, payload)
	if not result.get("ok", false):
		return [] as Array[Dictionary]
	return _events_from_result(result)


static func _events_from_result(result: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event in result.get("events", []):
		if event is Dictionary:
			events.append(event as Dictionary)
	return events


static func _execute_move(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not StatusRules.can_move(unit):
		return events
	var previous := unit.pos
	var tx := _CombatTransaction.begin(state, events).bind_event_sink()
	for step in intent.path:
		if not BoardUtils.unit_footprint_passable(state, unit, step, unit.uid):
			state.log("%s 移动受阻：%s 无法落脚" % [unit.uid, step])
			break
		tx.move_unit(unit, step, {"reason": "intent_move"})
		TileRules.on_unit_moved_through(state, unit, step)
		if not unit.alive:
			break
	if unit.alive:
		TileRules.finish_voluntary_move(state, unit, previous)
	return tx.finish("IntentSystem._execute_move")


static func _execute_extract(state: GameState, unit: UnitState, intent: IntentState) -> void:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) > CombatConfig.extract_range():
		return
	for i in range(target.slots.size()):
		var slot: SlotState = target.slots[i]
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		_GemTransfer.detach(state, gem)
		_behavior_for(target).on_gem_extracted(state, target, slot.slot_type, gem.uid)
		state.log("%s 窃取了 %s 的宝石 %s" % [unit.uid, target.uid, _data_registry().get_gem_display_name(gem)])
		refresh_all_intents(state)
		break


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _validated_events(events: Array[Dictionary], context: String) -> Array[Dictionary]:
	if OS.is_debug_build():
		EventValidator.assert_valid(events, context)
	return events
