class_name RollingArmadilloRules
extends RefCounted

const DamageContext = preload("res://scripts/rules/damage_context.gd")
const Displacement = preload("res://scripts/rules/displacement.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")

const IMPACT_RANGE := 4
const LAWLESS_ATTACK_BONUS := 2
const LAWLESS_MOVE_BONUS := 1
const IDEAL_MIN_DISTANCE := 3


static func compute_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var targets := _hostile_targets(state, unit)
	if targets.is_empty():
		return IntentState.wait(unit.uid)
	var anchors := _reachable_anchors(state, unit, cell_blockers)
	if StatusRules.is_lawless(unit):
		return _lawless_intent(state, unit, targets, anchors, cell_blockers)
	return _normal_intent(state, unit, targets, anchors, cell_blockers)


static func enter_lawless(state: GameState, unit: UnitState, gem_uid: String) -> void:
	if StatusRules.is_lawless(unit):
		return
	StatusRules.apply_lawless(state, unit, gem_uid)
	unit.base_attack += LAWLESS_ATTACK_BONUS
	unit.move_points += LAWLESS_MOVE_BONUS


static func recover_order(unit: UnitState) -> void:
	if not StatusRules.is_lawless(unit):
		return
	StatusRules.clear_lawless(unit)
	unit.base_attack = maxi(0, unit.base_attack - LAWLESS_ATTACK_BONUS)
	unit.move_points = maxi(0, unit.move_points - LAWLESS_MOVE_BONUS)


static func execute_uncontrolled_roll(
	state: GameState,
	unit: UnitState,
	intent: IntentState
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive or not _aligned(unit.pos, target.pos):
		return events
	var distance := BoardUtils.manhattan(unit.pos, target.pos)
	if distance <= 0 or distance > IMPACT_RANGE:
		return events
	var roll_start := unit.pos
	var event_start := events.size()
	Displacement.dash_toward(
		state,
		unit,
		target.pos,
		mini(IMPACT_RANGE, distance),
		unit.uid,
		events,
		-1,
		false,
		DamageContext.create(unit.uid, "uncontrolled_roll_collision")
	)
	events.insert(event_start, EventBuilder.impact_charge(
		unit.uid, roll_start, unit.pos, target.pos, {
			"source_uid": unit.uid,
			"target_uid": target.uid,
			"steps": BoardUtils.manhattan(roll_start, unit.pos),
		}
	))
	_drop_gems_from_collisions(state, unit, events)
	if not unit.alive:
		return events
	var adjacent := _adjacent_hostile(state, unit)
	if adjacent != null:
		var result := CombatRules.melee_attack(state, unit, adjacent)
		for event in result.get("events", []):
			if event is Dictionary:
				events.append(event as Dictionary)
	return events


static func _normal_intent(
	state: GameState,
	unit: UnitState,
	targets: Array[UnitState],
	anchors: Array[Vector2i],
	cell_blockers: Dictionary
) -> IntentState:
	var high_value: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for anchor in anchors:
		for target in targets:
			var distance := BoardUtils.manhattan(anchor, target.pos)
			if distance < 1 or distance > IMPACT_RANGE or not _aligned(anchor, target.pos):
				continue
			if not _clear_line(state, unit, anchor, target.pos, cell_blockers):
				continue
			var candidate := {
				"anchor": anchor,
				"target": target,
				"distance": distance,
				"score": _impact_score(state, unit, anchor, target, distance),
			}
			if distance >= IDEAL_MIN_DISTANCE \
			or target.hp <= CombatRules.attack_damage(state, unit) + distance - 1:
				high_value.append(candidate)
			else:
				fallback.append(candidate)
	var current_high := high_value.filter(func(candidate: Dictionary) -> bool:
		return candidate["anchor"] == unit.pos
	)
	var chosen := _best_candidate(current_high)
	if chosen.is_empty():
		chosen = _best_candidate(high_value)
	if chosen.is_empty():
		chosen = _best_candidate(fallback)
	if not chosen.is_empty():
		return _impact_intent(state, unit, chosen, cell_blockers)
	return _reposition_intent(state, unit, targets[0], anchors, cell_blockers, false)


static func _lawless_intent(
	state: GameState,
	unit: UnitState,
	targets: Array[UnitState],
	anchors: Array[Vector2i],
	cell_blockers: Dictionary
) -> IntentState:
	var target := _nearest_target(unit, targets)
	var candidates: Array[Dictionary] = []
	for anchor in anchors:
		var distance := BoardUtils.manhattan(anchor, target.pos)
		if distance < 1 or distance > IMPACT_RANGE or not _aligned(anchor, target.pos):
			continue
		var score := float(distance) + _landing_safety(state, anchor, true)
		score += _lawless_collision_value(state, unit, anchor, target.pos)
		candidates.append({
			"anchor": anchor,
			"target": target,
			"distance": distance,
			"score": score,
		})
	var chosen := _best_candidate(candidates)
	if chosen.is_empty():
		return _reposition_intent(state, unit, target, anchors, cell_blockers, true)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = target.uid
	intent.type = "rolling_uncontrolled"
	intent.path = _path_to(state, unit, chosen["anchor"], cell_blockers)
	intent.target_pos = chosen["anchor"]
	intent.base_damage = CombatRules.attack_damage(state, unit)
	intent.damage = intent.base_damage
	intent.affected_cells = _line_cells(chosen["anchor"], target.pos, IMPACT_RANGE)
	intent.preview_text = "失控撞击 · 最多4格"
	return intent


static func _impact_intent(
	state: GameState,
	unit: UnitState,
	candidate: Dictionary,
	cell_blockers: Dictionary
) -> IntentState:
	var target: UnitState = candidate["target"]
	var distance := int(candidate["distance"])
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = target.uid
	intent.type = "impact_attack"
	intent.path = _path_to(state, unit, candidate["anchor"], cell_blockers)
	intent.target_pos = candidate["anchor"]
	intent.base_damage = CombatRules.attack_damage(state, unit)
	intent.damage = intent.base_damage + distance - 1
	intent.preview_text = "定向滚冲 (%d)" % intent.damage
	return intent


static func _reposition_intent(
	state: GameState,
	unit: UnitState,
	target: UnitState,
	anchors: Array[Vector2i],
	cell_blockers: Dictionary,
	lawless: bool
) -> IntentState:
	var best_anchor := unit.pos
	var best_score := _position_score(state, unit, unit.pos, target, cell_blockers, lawless)
	for anchor in anchors:
		var score := _position_score(state, unit, anchor, target, cell_blockers, lawless)
		if score > best_score or (is_equal_approx(score, best_score) and _anchor_before(anchor, best_anchor)):
			best_score = score
			best_anchor = anchor
	if best_anchor == unit.pos:
		return IntentState.wait(unit.uid)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = target.uid
	intent.type = "move"
	intent.path = _path_to(state, unit, best_anchor, cell_blockers)
	intent.target_pos = best_anchor
	intent.preview_text = "蓄势选位" if not lawless else "失控找线"
	return intent


static func _impact_score(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	target: UnitState,
	distance: int
) -> float:
	var score := float(distance - 1) + _landing_safety(state, anchor, false)
	if target.uid == state.player_uid:
		score += 3.0
	if target.hp <= CombatRules.attack_damage(state, unit) + distance - 1:
		score += 8.0
	score -= float(BoardUtils.manhattan(unit.pos, anchor)) * 0.1
	return score


static func _position_score(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	target: UnitState,
	cell_blockers: Dictionary,
	lawless: bool
) -> float:
	var distance := BoardUtils.manhattan(anchor, target.pos)
	var aligned := _aligned(anchor, target.pos)
	var in_impact_range := aligned and distance <= IMPACT_RANGE
	var blocked_impact_line := in_impact_range and not lawless \
		and not _clear_line(state, unit, anchor, target.pos, cell_blockers)
	var score := _landing_safety(state, anchor, lawless) - float(distance) * 0.1
	if aligned and not blocked_impact_line:
		score += 5.0
	if not blocked_impact_line:
		match distance:
			4: score += 4.0
			3: score += 3.0
			2: score += 1.0
			1: score -= 2.0
	if in_impact_range:
		if not blocked_impact_line:
			score += 4.0
		else:
			score -= 3.0
	if not lawless:
		var setup_distance := _nearest_clear_impact_anchor_distance(
			state, unit, anchor, target, cell_blockers
		)
		score -= 20.0 if setup_distance < 0 else float(setup_distance) * 5.0
	for other in _hostile_targets(state, unit):
		if BoardUtils.manhattan(anchor, other.pos) == 1:
			score -= 1.0 if lawless else 2.0
	return score


static func _nearest_clear_impact_anchor_distance(
	state: GameState,
	unit: UnitState,
	from_pos: Vector2i,
	target: UnitState,
	cell_blockers: Dictionary
) -> int:
	var best := -1
	for x in range(state.board_size.x):
		for y in range(state.board_size.y):
			var anchor := Vector2i(x, y)
			var distance := BoardUtils.manhattan(anchor, target.pos)
			if distance < 1 or distance > IMPACT_RANGE or not _aligned(anchor, target.pos):
				continue
			if not BoardUtils.unit_footprint_passable(state, unit, anchor, unit.uid, cell_blockers):
				continue
			if not _clear_line(state, unit, anchor, target.pos, cell_blockers):
				continue
			var path_distance := BoardUtils.path_distance_to_cell(
				state, from_pos, anchor, unit.uid, cell_blockers, unit
			)
			if path_distance >= 0 and (best < 0 or path_distance < best):
				best = path_distance
	return best


static func _landing_safety(state: GameState, anchor: Vector2i, lawless: bool) -> float:
	var danger := 0.0
	if BoardUtils.spike_entity_at(state, anchor) != null:
		danger += 1.0
	var tile := state.get_tile(anchor)
	if tile != null and (
		tile.has_modifier(Constants.TILE_MOD_POISON_FOG)
		or tile.has_modifier(Constants.TILE_MOD_FIRE)
		or tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE)
	):
		danger += 1.0
	return danger * (-1.0 if lawless else -4.0)


static func _lawless_collision_value(
	state: GameState,
	unit: UnitState,
	from_pos: Vector2i,
	target_pos: Vector2i
) -> float:
	for cell in _line_cells(from_pos, target_pos, IMPACT_RANGE):
		var blocker := state.get_unit_at(cell)
		if blocker != null and blocker.uid != unit.uid:
			return 1.0 if blocker.team == unit.team else 3.0
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.blocks_movement():
			return 3.0 if entity.entity_id == Constants.ENTITY_BARREL else 0.0
	return 0.0


static func _clear_line(
	state: GameState,
	unit: UnitState,
	from_pos: Vector2i,
	target_pos: Vector2i,
	cell_blockers: Dictionary
) -> bool:
	var cells := _line_cells(from_pos, target_pos, IMPACT_RANGE)
	for i in range(maxi(0, cells.size() - 1)):
		if not BoardUtils.is_passable(state, cells[i], unit.uid, cell_blockers):
			return false
	return true


static func _line_cells(from_pos: Vector2i, target_pos: Vector2i, max_steps: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _aligned(from_pos, target_pos):
		return cells
	var direction := Vector2i(signi(target_pos.x - from_pos.x), signi(target_pos.y - from_pos.y))
	var current := from_pos
	for _i in range(max_steps):
		current += direction
		cells.append(current)
		if current == target_pos:
			break
	return cells


static func _reachable_anchors(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = [unit.pos]
	if StatusRules.can_move(unit):
		anchors.append_array(BoardUtils.reachable_cells(
			state, unit.pos, unit.move_points, unit.uid, {}, cell_blockers, unit
		))
	return anchors


static func _path_to(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	cell_blockers: Dictionary
) -> Array[Vector2i]:
	if anchor == unit.pos:
		return [] as Array[Vector2i]
	return BoardUtils.path_toward(
		state, unit.pos, anchor, unit.move_points, unit.uid, {}, cell_blockers, unit
	)


static func _hostile_targets(state: GameState, unit: UnitState) -> Array[UnitState]:
	var targets: Array[UnitState] = []
	for candidate: UnitState in state.units.values():
		if candidate.alive and candidate.team != unit.team:
			targets.append(candidate)
	targets.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		if a.hp == b.hp:
			return a.uid < b.uid
		return a.hp < b.hp
	)
	return targets


static func _nearest_target(unit: UnitState, targets: Array[UnitState]) -> UnitState:
	var best := targets[0]
	var best_distance := BoardUtils.distance_between_units(unit, best)
	for target in targets:
		var distance := BoardUtils.distance_between_units(unit, target)
		if distance < best_distance or (distance == best_distance and target.uid < best.uid):
			best = target
			best_distance = distance
	return best


static func _best_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if best.is_empty() or float(candidate["score"]) > float(best["score"]):
			best = candidate
		elif is_equal_approx(float(candidate["score"]), float(best["score"])):
			var anchor: Vector2i = candidate["anchor"]
			var best_anchor: Vector2i = best["anchor"]
			if _anchor_before(anchor, best_anchor):
				best = candidate
	return best


static func _adjacent_hostile(state: GameState, unit: UnitState) -> UnitState:
	var targets := _hostile_targets(state, unit)
	for target in targets:
		if BoardUtils.are_units_adjacent(unit, target):
			return target
	return null


static func _drop_gems_from_collisions(
	state: GameState,
	roller: UnitState,
	events: Array[Dictionary]
) -> void:
	var handled: Dictionary = {}
	for event in events.duplicate():
		if str(event.get("type", "")) != "displacement_impact" \
		or str(event.get("uid", "")) != roller.uid \
		or str(event.get("blocker_kind", "")) != "unit":
			continue
		var victim_uid := str(event.get("blocker_uid", ""))
		if victim_uid.is_empty() or handled.has(victim_uid):
			continue
		handled[victim_uid] = true
		var victim: UnitState = state.units.get(victim_uid, null)
		if victim == null:
			continue
		var occupied_slots: Array[SlotState] = []
		for slot: SlotState in victim.slots:
			if not slot.gem_uid.is_empty():
				occupied_slots.append(slot)
		if occupied_slots.is_empty():
			continue
		occupied_slots.sort_custom(func(a: SlotState, b: SlotState) -> bool: return a.gem_uid < b.gem_uid)
		var index := 0
		var rng: Node = Engine.get_main_loop().root.get_node_or_null("RngService")
		if rng != null:
			index = int(rng.roll_int(
				"rolling_armadillo_drop_%s_%s_%d" % [roller.uid, victim.uid, state.turn_index],
				0,
				occupied_slots.size() - 1
			))
		var chosen := occupied_slots[index]
		var gem: GemState = state.gems.get(chosen.gem_uid, null)
		if gem == null:
			continue
		var slot_type := chosen.slot_type
		var contact: Vector2i = event.get("contact", victim.pos)
		if GemTransfer.to_ground(state, gem, contact, {
			"source_unit_uid": victim.uid,
			"source_slot_type": slot_type,
			"knocked_loose_by_uid": roller.uid,
		}):
			BehaviorRegistry.get_behavior(victim.behavior_id).on_gem_extracted(
				state, victim, slot_type, gem.uid
			)
			events.append(EventBuilder.gem_flash(contact, {"color": Color(0.95, 0.72, 0.2)}))


static func _aligned(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.y == b.y


static func _anchor_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
