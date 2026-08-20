class_name LawWormRules
extends RefCounted

const INCUBATION_SHIELD := 5
const BROODMOTHER_ATTACK_RANGE := 3
const BROOD_SIZE := 2
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _UnitSpawnService = preload("res://scripts/rules/unit_spawn_service.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")


static func compute_law_worm_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var ready_turn := StatusRules.law_worm_ready_turn(unit)
	if ready_turn >= 0:
		if state.turn_index >= ready_turn:
			var transform := IntentState.new()
			transform.type = "law_worm_transform"
			transform.source_uid = unit.uid
			transform.target_pos = unit.pos
			transform.preview_text = "进化为畸变蛆母"
			return transform
		var incubating := IntentState.wait(unit.uid)
		incubating.preview_text = "孵化中 · 下回合进化"
		return incubating

	var target := _nearest_reachable_drop(state, unit, cell_blockers)
	if target.is_empty():
		return _wander_intent(state, unit, cell_blockers)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = str(target.get("gem_uid", ""))
	intent.target_pos = target.get("pos", unit.pos)
	var full_path: Array[Vector2i] = target.get("path", [] as Array[Vector2i])
	intent.path = full_path.slice(0, mini(unit.move_points, full_path.size()))
	var reaches_drop := unit.pos == intent.target_pos \
		or (not intent.path.is_empty() and intent.path[-1] == intent.target_pos)
	intent.type = "law_worm_consume" if reaches_drop else "law_worm_seek"
	var gem: GemState = state.gems.get(intent.target_uid, null)
	var gem_name: String = _data_registry().get_gem_display_name(gem) if gem != null else "宝石"
	intent.preview_text = "吞噬%s" % gem_name if reaches_drop else "追逐%s" % gem_name
	return intent


static func execute_law_worm_intent(state: GameState, unit: UnitState, intent: IntentState) -> Dictionary:
	var events: Array[Dictionary] = []
	match intent.type:
		"law_worm_seek":
			return {"handled": true, "events": events}
		"law_worm_consume":
			if _consume_drop(state, unit, intent.target_uid):
				events.append(_EventBuilder.gem_flash(unit.pos, {"color": Color(0.74, 0.88, 0.28)}))
			return {"handled": true, "events": events}
		"law_worm_transform":
			events.append(_transform_to_broodmother(state, unit))
			return {"handled": true, "events": events}
	return {"handled": false, "events": events}


static func compute_broodmother_intent(
	state: GameState,
	unit: UnitState,
	_cell_blockers: Dictionary = {},
	priority_target: UnitState = null
) -> IntentState:
	var crisis := sync_broodmother_crisis(state, unit)
	if unit.get_status(Constants.STATUS_BROODMOTHER_CYCLE) == null:
		StatusRules.set_broodmother_next_split(state, unit, true)
	if StatusRules.broodmother_next_split(unit):
		var split := IntentState.new()
		split.type = "broodmother_split"
		split.source_uid = unit.uid
		split.target_pos = unit.pos
		var available_cells := _available_brood_cells(state, unit.pos)
		split.affected_cells = available_cells.slice(0, mini(BROOD_SIZE, available_cells.size()))
		split.preview_text = "危机繁殖 · 孵化2只" if crisis else "恶性分裂 · 孵化2只"
		return split
	var target := priority_target if priority_target != null else state.get_player()
	if target == null or not target.alive or target.uid == unit.uid:
		return IntentState.wait(unit.uid)
	var max_range := GemEffects.red_attack_range(state, unit, BROODMOTHER_ATTACK_RANGE)
	if not BoardUtils.can_unit_attack_cell(unit, state, target.pos, max_range):
		var wait := IntentState.new()
		wait.type = "broodmother_wait"
		wait.source_uid = unit.uid
		wait.target_pos = unit.pos
		wait.preview_text = "守巢等待"
		return wait
	var attack := IntentState.new()
	attack.type = "broodmother_ranged_attack"
	attack.source_uid = unit.uid
	attack.target_uid = target.uid
	attack.target_pos = target.pos
	attack.base_damage = CombatRules.attack_damage(state, unit)
	attack.damage = GemEffects.primary_attack_damage_preview(state, unit, attack.base_damage)
	attack.preview_text = "远程喷吐 (%d)" % attack.damage
	return attack


static func execute_broodmother_intent(state: GameState, unit: UnitState, intent: IntentState) -> Dictionary:
	var events: Array[Dictionary] = []
	match intent.type:
		"broodmother_split":
			events.append_array(_spawn_brood_at_cells(state, unit, intent.affected_cells))
			StatusRules.set_broodmother_next_split(state, unit, false)
			return {"handled": true, "events": events}
		"broodmother_ranged_attack":
			var player: UnitState = state.units.get(intent.target_uid, null)
			if player != null and player.alive:
				var max_range := GemEffects.red_attack_range(state, unit, BROODMOTHER_ATTACK_RANGE)
				var result := CombatRules.ranged_attack(state, unit, player.pos, max_range)
				if result.get("ok", false):
					events.append_array(result.get("events", [] as Array[Dictionary]))
			StatusRules.set_broodmother_next_split(state, unit, true)
			return {"handled": true, "events": events}
		"broodmother_wait":
			StatusRules.set_broodmother_next_split(state, unit, true)
			return {"handled": true, "events": events}
	return {"handled": false, "events": events}


static func sync_broodmother_crisis(state: GameState, unit: UnitState) -> bool:
	var crisis := not _unit_has_any_gem(unit)
	StatusRules.sync_broodmother_crisis(state, unit, crisis)
	return crisis


static func _nearest_reachable_drop(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var drop_uids := state.dropped_gems.keys()
	drop_uids.sort()
	var full_budget := maxi(1, state.board_size.x * state.board_size.y * 4)
	for raw_uid in drop_uids:
		var gem_uid := str(raw_uid)
		var raw_drop: Variant = state.dropped_gems.get(gem_uid, {})
		if not raw_drop is Dictionary or not state.gems.has(gem_uid):
			continue
		var drop := raw_drop as Dictionary
		var drop_pos: Vector2i = drop.get("pos", Vector2i(-1, -1))
		if not BoardUtils.in_bounds(state, drop_pos):
			continue
		var path := BoardUtils.path_toward(
			state,
			unit.pos,
			drop_pos,
			full_budget,
			unit.uid,
			{"allow_partial_path": false},
			cell_blockers,
			unit
		)
		if unit.pos != drop_pos and (path.is_empty() or path[-1] != drop_pos):
			continue
		if best.is_empty() \
		or path.size() < (best.get("path", []) as Array).size() \
		or (path.size() == (best.get("path", []) as Array).size() and gem_uid < str(best.get("gem_uid", ""))):
			best = {"gem_uid": gem_uid, "pos": drop_pos, "path": path}
	return best


static func _wander_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary) -> IntentState:
	var candidates: Array[Vector2i] = []
	for cell in BoardUtils.neighbors4(unit.pos):
		if BoardUtils.unit_footprint_passable(state, unit, cell, unit.uid, cell_blockers):
			candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	if candidates.is_empty():
		var wait := IntentState.wait(unit.uid)
		wait.preview_text = "蜷伏"
		return wait
	var index := 0
	var rng: Node = Engine.get_main_loop().root.get_node_or_null("RngService")
	if rng != null:
		index = int(rng.roll_int("law_worm_wander_%s_%d" % [unit.uid, state.turn_index], 0, candidates.size() - 1))
	var intent := IntentState.new()
	intent.type = "move"
	intent.source_uid = unit.uid
	intent.path = [candidates[index]]
	intent.target_pos = candidates[index]
	intent.preview_text = "无律游荡"
	return intent


static func _consume_drop(state: GameState, unit: UnitState, gem_uid: String) -> bool:
	var drop: Dictionary = state.dropped_gems.get(gem_uid, {})
	var gem: GemState = state.gems.get(gem_uid, null)
	if drop.is_empty() or gem == null or drop.get("pos", Vector2i(-1, -1)) != unit.pos:
		return false
	var source_slot_type := str(drop.get("source_slot_type", ""))
	var host: SlotState = unit.get_slot(source_slot_type) if source_slot_type in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK] else null
	if host == null or not host.gem_uid.is_empty():
		for slot in unit.slots:
			if slot != null and slot.gem_uid.is_empty() and not slot.locked:
				host = slot
				break
	if host == null or not host.gem_uid.is_empty():
		return false
	if not _GemTransfer.to_unit_slot(state, gem, unit, host):
		return false
	StatusRules.apply_law_worm_incubating(state, unit, state.turn_index + 1)
	StatusRules.apply_shield(state, unit, INCUBATION_SHIELD, 0, unit.uid)
	state.log("%s 吞噬宝石并开始孵化" % unit.uid)
	return true


static func _transform_to_broodmother(state: GameState, unit: UnitState) -> Dictionary:
	var from_unit_id := unit.unit_def_id
	var missing_hp := maxi(0, unit.max_hp - unit.hp)
	var mother_def: Dictionary = _data_registry().get_unit_def("unit_broodmother")
	unit.unit_def_id = "unit_broodmother"
	unit.max_hp = int(mother_def.get("max_hp", 20))
	unit.hp = maxi(1, unit.max_hp - missing_hp)
	unit.move_points = int(mother_def.get("move_points", 0))
	unit.speed = int(mother_def.get("speed", 6))
	unit.base_attack = int(mother_def.get("base_attack", 4))
	unit.armor = int(mother_def.get("armor", 0))
	unit.ai_profile_id = str(mother_def.get("ai_profile_id", "melee_chase"))
	unit.behavior_id = str(mother_def.get("behavior_id", "broodmother"))
	unit.tags.clear()
	for raw_tag in mother_def.get("tags", []):
		unit.add_tag(str(raw_tag))
	unit.footprint_size = Vector2i(1, 1)
	unit.remove_status(Constants.STATUS_LAW_WORM_INCUBATING)
	unit.remove_status(Constants.STATUS_ARMOR)
	StatusRules.set_broodmother_next_split(state, unit, true)
	sync_broodmother_crisis(state, unit)
	state.log("%s 进化为畸变蛆母" % unit.uid)
	return _EventBuilder.transform(unit, from_unit_id, {"reason": "law_worm_incubation"})


static func _available_brood_cells(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in BoardUtils.cells_in_radius(origin, 1):
		if cell == origin or not BoardUtils.in_bounds(state, cell):
			continue
		if BoardUtils.is_passable(state, cell):
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells


static func _spawn_brood(state: GameState, mother: UnitState, count: int) -> Array[Dictionary]:
	var cells := _available_brood_cells(state, mother.pos)
	return _spawn_brood_at_cells(state, mother, cells.slice(0, mini(count, cells.size())))


static func _spawn_brood_at_cells(state: GameState, mother: UnitState, planned_cells: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var spawn_count := 0
	for raw_cell in planned_cells:
		if not raw_cell is Vector2i:
			continue
		var cell := raw_cell as Vector2i
		if not BoardUtils.unit_footprint_passable(state, mother, cell, mother.uid):
			continue
		var uid := str(_data_registry().next_runtime_uid("law_worm"))
		var result := _UnitSpawnService.spawn_from_def(
			state,
			"unit_law_worm",
			Constants.TEAM_ENEMY,
			cell,
			events,
			{
				"uid": uid,
				"origin": mother,
				"grants_death_rewards": true,
				"temporary": false,
				"reason": "broodmother_split",
			}
		)
		if not bool(result.get("ok", false)):
			continue
		spawn_count += 1
	state.log("%s 分裂出 %d 只噬律蛆" % [mother.uid, spawn_count])
	return events


static func _unit_has_any_gem(unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot != null and not slot.gem_uid.is_empty():
			return true
	return false


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
