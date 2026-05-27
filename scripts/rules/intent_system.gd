class_name IntentSystem
extends RefCounted
## 意图系统 —— 基于 Utility AI 的敌人决策
## 每回合开始时为所有敌人计算最优行动，生成 IntentState 供 UI 预览
## 敌人回合执行时按照预计算的意图行动


static func refresh_all_intents(state: GameState) -> void:
	var cell_blockers := build_cell_occupancy(state)
	var enemies := _sorted_enemies_for_planning(state)
	for enemy in enemies:
		if not enemy.alive:
			continue
		var start_pos: Vector2i = enemy.pos
		enemy.intent = _compute_intent_from_ai(state, enemy, cell_blockers)
		_apply_planned_occupancy(state, cell_blockers, enemy.uid, start_pos, intent_end_pos(enemy, enemy.intent))


## 按当前棋盘重算单个敌人意图（敌方回合逐个行动前调用）
static func refresh_unit_intent(state: GameState, unit: UnitState) -> void:
	if not unit.alive or unit.team != Constants.TEAM_ENEMY:
		return
	unit.intent = _compute_intent_from_ai(state, unit, build_cell_occupancy(state))


static func build_cell_occupancy(state: GameState) -> Dictionary:
	var occupancy: Dictionary = {}
	for unit in state.units.values():
		if unit.alive:
			occupancy[state.tile_key(unit.pos)] = unit.uid
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
	uid: String,
	old_pos: Vector2i,
	new_pos: Vector2i
) -> void:
	var old_key := state.tile_key(old_pos)
	if str(cell_blockers.get(old_key, "")) == uid:
		cell_blockers.erase(old_key)
	cell_blockers[state.tile_key(new_pos)] = uid


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
	# 失律状态特殊处理（被偷红宝石后的混乱行为）
	if StatusRules.is_lawless(unit):
		return _lawless_intent(state, unit)

	# 使用 Utility AI 决策
	var decision := EnemyAI.decide(state, unit, cell_blockers)
	var action: EnemyAI.ActionCandidate = decision.get("action", null)
	var move_path: Array[Vector2i] = decision.get("move_path", [] as Array[Vector2i])

	if action == null:
		return IntentState.wait(unit.uid)

	# 将 AI 决策转化为 IntentState（供 UI 预览）
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.path = move_path

	match action.type:
		EnemyAI.ActionType.ATTACK:
			intent.type = "melee_attack"
			intent.target_uid = action.action_target_uid
			intent.target_pos = action.move_target
			intent.damage = CombatRules.attack_damage(state, unit)
			intent.preview_text = "近战攻击 (%d)" % intent.damage

		EnemyAI.ActionType.SKILL_RED:
			var red_slot := unit.get_slot(Constants.SLOT_RED)
			if red_slot != null and not red_slot.gem_uid.is_empty():
				var gem: GemState = state.gems.get(red_slot.gem_uid, null)
				if gem != null:
					intent = _build_skill_intent(state, unit, gem, action, move_path, cell_blockers)
				else:
					intent = IntentState.wait(unit.uid)
			else:
				intent = IntentState.wait(unit.uid)

		EnemyAI.ActionType.EXTRACT:
			intent.type = "extract"
			intent.target_uid = action.action_target_uid
			intent.target_pos = action.move_target
			intent.preview_text = "窃取宝石"

		EnemyAI.ActionType.MOVE:
			intent.type = "move"
			intent.target_pos = action.move_target
			intent.preview_text = "移动"
			var player := state.get_player()
			if player != null:
				intent.target_uid = player.uid

		EnemyAI.ActionType.WAIT:
			return IntentState.wait(unit.uid)

	return intent


static func _build_skill_intent(
	state: GameState,
	unit: UnitState,
	gem: GemState,
	action: EnemyAI.ActionCandidate,
	move_path: Array[Vector2i],
	cell_blockers: Dictionary = {}
) -> IntentState:
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = action.action_target_uid
	intent.path = move_path.duplicate()
	var base_damage := CombatRules.attack_damage(state, unit)
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
				state, dash_from, target.pos, 2, unit.uid, {}, cell_blockers
			)
			for step in charge_path:
				intent.path.append(step)
			var end_pos: Vector2i = intent.path[-1] if not intent.path.is_empty() else unit.pos
			intent.affected_cells = BoardUtils.cells_in_radius(end_pos, Constants.EXPLOSION_RADIUS)
			intent.target_pos = end_pos
			intent.preview_text = "冲刺爆炸 (%d)" % Constants.EXPLOSION_DAMAGE

	return intent


## 执行意图并返回动画事件列表
## 每个事件: {type: "move_step"|"damage"|"explode"|"gem_flash", ...}
static func execute_intent(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var anim_events: Array[Dictionary] = []
	if not unit.alive:
		return anim_events
	var intent := unit.intent
	if intent == null:
		return anim_events

	# 第一步：执行移动（逐格记录动画事件）
	if not intent.path.is_empty():
		var move_events := _execute_move(state, unit, intent)
		anim_events.append_array(move_events)

	# 第二步：执行行动
	match intent.type:
		"melee_attack":
			anim_events.append_array(_execute_melee(state, unit, intent))
		"charge_explode", "pull", "poison_attack", "arc_attack", "fire_attack", "ice_attack":
			anim_events.append_array(GemEffects.on_red_action(state, unit, intent))
		"extract":
			_execute_extract(state, unit, intent)
			anim_events.append({"type": "gem_flash", "pos": intent.target_pos, "color": Color(0.9, 0.2, 0.2)})
		"lawless_move":
			pass  # 移动已在上面执行
		"lawless_attack":
			var lawless_target: UnitState = state.units.get(intent.target_uid, null)
			if lawless_target != null and lawless_target.alive and BoardUtils.manhattan(unit.pos, lawless_target.pos) == 1:
				var dealt := CombatRules.apply_damage(state, lawless_target, intent.damage, unit.uid, "lawless_attack")
				if dealt > 0:
					anim_events.append({
						"type": "damage",
						"pos": lawless_target.pos,
						"damage": dealt,
						"is_crit": true,
						"attacker_uid": unit.uid,
					})
		"lawless_extract":
			var extracted := _execute_lawless_extract(state, unit, intent.target_uid)
			if extracted:
				anim_events.append({"type": "gem_flash", "pos": unit.pos, "color": Color(0.95, 0.25, 0.25)})
		"move":
			pass  # 纯移动，无行动

	return anim_events


static func _execute_melee(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var result := CombatRules.melee_attack(state, unit, target)
	if not result.get("ok", false):
		return [] as Array[Dictionary]
	return result.get("events", [] as Array[Dictionary])


static func _execute_move(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not StatusRules.can_move(unit):
		return events
	var previous := unit.pos
	for step in intent.path:
		var blocker := state.get_unit_at(step)
		if blocker != null and blocker.uid != unit.uid:
			state.log("%s 移动受阻：%s 已被占据" % [unit.uid, step])
			break
		var from_pos := unit.pos
		unit.pos = step
		TileRules.on_unit_moved_through(state, unit, step)
		state.on_unit_move.emit(unit.uid, from_pos, step)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": step})
	TileRules.on_unit_entered(state, unit, previous)
	return events


static func _execute_extract(state: GameState, unit: UnitState, intent: IntentState) -> void:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) > Constants.EXTRACT_RANGE:
		return
	for i in range(target.slots.size()):
		var slot: SlotState = target.slots[i]
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		gem.owner_uid = ""
		gem.slot_index = -1
		slot.gem_uid = ""
		if slot.slot_type == Constants.SLOT_RED and target.team == Constants.TEAM_ENEMY:
			StatusRules.apply_lawless(state, target, gem.uid)
		state.log("%s 窃取了 %s 的宝石 %s" % [unit.uid, target.uid, _data_registry().get_gem_display_name(gem)])
		refresh_all_intents(state)
		break


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
		_restore_lawless_gem(state, unit, stolen_gem)
		StatusRules.clear_lawless(unit)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	for slot in target.slots:
		if slot.gem_uid != target_gem_uid:
			continue
		slot.gem_uid = ""
		_restore_lawless_gem(state, unit, stolen_gem)
		StatusRules.clear_lawless(unit)
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	return false


static func _restore_lawless_gem(state: GameState, unit: UnitState, gem: GemState) -> void:
	var red_slot := unit.get_slot(Constants.SLOT_RED)
	if red_slot != null and red_slot.gem_uid.is_empty():
		red_slot.gem_uid = gem.uid
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(red_slot)
		return
	gem.owner_uid = unit.uid
	gem.slot_index = -1


# ─── 失律意图（被偷红宝石后的混乱行为） ─────────────────────────────────────
static func _lawless_intent(state: GameState, unit: UnitState) -> IntentState:
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
	intent.path = BoardUtils.path_toward(state, unit.pos, target_pos, unit.move_points, unit.uid)
	intent.target_pos = intent.path.back() if not intent.path.is_empty() else unit.pos
	if target_uid != "" and BoardUtils.manhattan(intent.target_pos, target_pos) == 1:
		intent.type = "lawless_attack"
		intent.damage = damage
		intent.preview_text = "失律狂袭 (%d)" % damage
	else:
		intent.type = "lawless_move"
		intent.preview_text = "失律追逐宝石"
	return intent


static func _find_gem_carrier(state: GameState, gem: GemState) -> UnitState:
	if state.held_gem_uid == gem.uid:
		return state.get_player()
	for unit in state.units.values():
		if not unit.alive:
			continue
		for slot in unit.slots:
			if slot.gem_uid == gem.uid:
				return unit
	return null


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _get_water_cluster(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	return BoardUtils.water_cluster(state, origin)
