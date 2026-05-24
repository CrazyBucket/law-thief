class_name IntentSystem
extends RefCounted
## 意图系统 —— 基于 Utility AI 的敌人决策
## 每回合开始时为所有敌人计算最优行动，生成 IntentState 供 UI 预览
## 敌人回合执行时按照预计算的意图行动


static func refresh_all_intents(state: GameState) -> void:
	for unit in state.units.values():
		if unit.alive and unit.team == Constants.TEAM_ENEMY:
			unit.intent = _compute_intent_from_ai(state, unit)


static func _compute_intent_from_ai(state: GameState, unit: UnitState) -> IntentState:
	# 失律状态特殊处理（被偷红宝石后的混乱行为）
	if unit.lawless:
		return _lawless_intent(state, unit)

	# 使用 Utility AI 决策
	var decision := EnemyAI.decide(state, unit)
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
					intent = _build_skill_intent(state, unit, gem, action, move_path)
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


static func _build_skill_intent(state: GameState, unit: UnitState, gem: GemState, action: EnemyAI.ActionCandidate, move_path: Array[Vector2i]) -> IntentState:
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = action.action_target_uid
	intent.path = move_path

	match gem.gem_id:
		Constants.GEM_EXPLOSION:
			intent.type = "charge_explode"
			intent.affected_cells = BoardUtils.cells_in_radius(action.move_target, Constants.EXPLOSION_RADIUS)
			intent.damage = Constants.EXPLOSION_DAMAGE
			intent.preview_text = "冲刺爆炸 (%d)" % Constants.EXPLOSION_DAMAGE

		Constants.GEM_GRAVITY:
			intent.type = "pull"
			intent.preview_text = "引力拉近+束缚"

		Constants.GEM_POISON:
			intent.type = "poison_attack"
			intent.damage = CombatRules.attack_damage(state, unit)
			intent.preview_text = "毒攻击 (%d+毒)" % intent.damage

		Constants.GEM_CONDUCTIVE:
			intent.type = "shock"
			intent.damage = 1
			intent.preview_text = "电击 (1)"
			# 标记水域连锁区域
			var player := state.get_player()
			if player != null:
				var player_tile := state.get_tile(player.pos)
				if player_tile.tile_id == Constants.TILE_WATER:
					intent.affected_cells = _get_water_cluster(state, player.pos)

		Constants.GEM_FRAGILE:
			intent.type = "fragile_charge"
			intent.damage = 1
			intent.preview_text = "冲撞自毁 (1)"

		_:
			return IntentState.wait(unit.uid)

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
			var attacked: bool = _execute_melee(state, unit, intent)
			if attacked:
				anim_events.append({"type": "damage", "pos": intent.target_pos, "damage": intent.damage, "is_crit": false})
		"charge_explode":
			GemEffects.on_red_action(state, unit, intent)
			anim_events.append({"type": "explode", "pos": unit.pos, "radius": Constants.EXPLOSION_RADIUS})
		"pull", "poison_attack", "shock", "fragile_charge":
			GemEffects.on_red_action(state, unit, intent)
			if intent.type == "poison_attack":
				anim_events.append({"type": "damage", "pos": intent.target_pos, "damage": intent.damage, "is_crit": false})
			elif intent.type == "shock":
				anim_events.append({"type": "damage", "pos": intent.target_pos, "damage": 1, "is_crit": false})
		"extract":
			_execute_extract(state, unit, intent)
			anim_events.append({"type": "gem_flash", "pos": intent.target_pos, "color": Color(0.9, 0.2, 0.2)})
		"lawless_move":
			pass  # 移动已在上面执行
		"lawless_attack":
			var lawless_target: UnitState = state.units.get(intent.target_uid, null)
			if lawless_target != null and lawless_target.alive and BoardUtils.manhattan(unit.pos, lawless_target.pos) == 1:
				CombatRules.apply_damage(state, lawless_target, intent.damage, unit.uid, "lawless_attack")
				anim_events.append({"type": "damage", "pos": lawless_target.pos, "damage": intent.damage, "is_crit": true})
		"lawless_extract":
			var extracted := _execute_lawless_extract(state, unit, intent.target_uid)
			if extracted:
				anim_events.append({"type": "gem_flash", "pos": unit.pos, "color": Color(0.95, 0.25, 0.25)})
		"move":
			pass  # 纯移动，无行动

	return anim_events


static func _execute_melee(state: GameState, unit: UnitState, intent: IntentState) -> bool:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return false
	if BoardUtils.manhattan(unit.pos, target.pos) != 1:
		return false
	CombatRules.attack(state, unit, target)
	return true


static func _execute_move(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var previous := unit.pos
	for step in intent.path:
		var from_pos := unit.pos
		unit.pos = step
		TileRules.on_unit_moved_through(state, unit, step)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": step})
	TileRules.on_unit_entered(state, unit, previous)
	return events


static func _execute_extract(state: GameState, unit: UnitState, intent: IntentState) -> void:
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) > Constants.EXTRACT_RANGE:
		return
	# 找到第一个可拔出的槽位
	for i in range(target.slots.size()):
		var slot: SlotState = target.slots[i]
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		# 执行拔出（怪物拔出不需要 held_gem 机制，直接销毁/持有）
		slot.gem_uid = ""
		state.log("%s 窃取了 %s 的宝石 %s" % [unit.uid, target.uid, gem.gem_id])
		break


static func _execute_lawless_extract(state: GameState, unit: UnitState, target_uid: String) -> bool:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return false
	if BoardUtils.manhattan(unit.pos, target.pos) > Constants.EXTRACT_RANGE:
		return false
	var target_gem_uid := unit.lawless_target_gem_uid
	for slot in target.slots:
		if slot.gem_uid != target_gem_uid:
			continue
		var stolen_gem: GemState = state.gems.get(target_gem_uid, null)
		slot.gem_uid = ""
		if stolen_gem != null:
			var red_slot := unit.get_slot(Constants.SLOT_RED)
			if red_slot != null and red_slot.gem_uid.is_empty():
				red_slot.gem_uid = stolen_gem.uid
				stolen_gem.owner_uid = unit.uid
				stolen_gem.slot_index = unit.slots.find(red_slot)
			else:
				stolen_gem.owner_uid = unit.uid
				stolen_gem.slot_index = -1
		unit.lawless = false
		unit.lawless_target_gem_uid = ""
		unit.remove_status("lawless")
		state.log("%s 夺回了失去的宝石" % unit.uid)
		return true
	return false


# ─── 失律意图（被偷红宝石后的混乱行为） ─────────────────────────────────────
static func _lawless_intent(state: GameState, unit: UnitState) -> IntentState:
	var gem: GemState = state.gems.get(unit.lawless_target_gem_uid, null)
	var target_pos := unit.pos
	var target_uid := ""
	if gem != null:
		if gem.owner_uid == state.player_uid and not state.held_gem_uid.is_empty():
			var player := state.get_player()
			if player != null:
				target_pos = player.pos
				target_uid = player.uid
		elif gem.owner_uid != "":
			var owner: UnitState = state.units.get(gem.owner_uid, null)
			if owner != null:
				target_pos = owner.pos
				target_uid = owner.uid
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


static func _get_water_cluster(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array = [origin]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		var tile := state.get_tile(current)
		if tile.tile_id != Constants.TILE_WATER:
			continue
		result.append(current)
		for neighbor in BoardUtils.neighbors4(current):
			if not visited.has(neighbor) and BoardUtils.in_bounds(state, neighbor):
				queue.append(neighbor)
	return result
