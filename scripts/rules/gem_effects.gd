class_name GemEffects
extends RefCounted


static func trigger_gem(state: GameState, owner_uid: String, slot: SlotState) -> bool:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	if slot.slot_type == Constants.SLOT_BLUE:
		return false
	if slot.slot_type == Constants.SLOT_BLACK:
		return false
	match gem.gem_id:
		Constants.GEM_EXPLOSION:
			explode_at(state, _get_owner_pos(state, owner_uid), Constants.EXPLOSION_DAMAGE, owner_uid)
			return true
		Constants.GEM_POISON:
			TileRules.create_poison_fog(state, _get_owner_pos(state, owner_uid))
			return true
		Constants.GEM_GRAVITY:
			pull_around(state, _get_owner_pos(state, owner_uid), 2, 1)
			return true
		Constants.GEM_HEAVY_ARMOR:
			var unit: UnitState = state.units.get(owner_uid, null)
			if unit != null:
				StatusRules.apply_armor(state, unit, 2, 1)
			return true
		Constants.GEM_CONDUCTIVE:
			_activate_water_cluster(state, _get_owner_pos(state, owner_uid))
			return true
		Constants.GEM_FRAGILE:
			var fragile_unit: UnitState = state.units.get(owner_uid, null)
			if fragile_unit != null:
				CombatRules.apply_damage(state, fragile_unit, fragile_unit.hp, owner_uid, "fragile_trigger")
			return true
	return false


static func on_unit_death(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if gem.gem_id == Constants.GEM_EXPLOSION and slot.slot_type == Constants.SLOT_BLACK:
			explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid)
		elif gem.gem_id == Constants.GEM_POISON and slot.slot_type == Constants.SLOT_BLACK:
			for cell in BoardUtils.cells_in_radius(unit.pos, 1):
				TileRules.create_poison_fog(state, cell)
		elif gem.gem_id == Constants.GEM_GRAVITY and slot.slot_type == Constants.SLOT_BLACK:
			pull_around(state, unit.pos, 2, 1)
		elif gem.gem_id == Constants.GEM_FRAGILE and slot.slot_type == Constants.SLOT_BLACK:
			for neighbor in BoardUtils.neighbors4(unit.pos):
				var target := state.get_unit_at(neighbor)
				if target != null:
					CombatRules.apply_damage(state, target, 1, unit.uid, "fragile_shatter")
		elif gem.gem_id == Constants.GEM_CONDUCTIVE and slot.slot_type == Constants.SLOT_BLACK:
			for cell in BoardUtils.cells_in_radius(unit.pos, 2):
				var tile := state.get_tile(cell)
				if tile.tile_id == Constants.TILE_WATER:
					_activate_water_cluster(state, cell)
		elif gem.gem_id == Constants.GEM_HEAVY_ARMOR and slot.slot_type == Constants.SLOT_BLACK:
			var ally := _nearest_alive_ally(state, unit)
			if ally != null:
				StatusRules.apply_armor(state, ally, 3, 2)
				state.log("%s 死亡后将重甲遗产传给 %s" % [unit.uid, ally.uid])


## 玩家使用红槽技能：对目标位置/单位施放，效果因宝石而异
## 返回动画事件列表
static func player_use_skill(state: GameState, player: UnitState, target_pos: Vector2i) -> Array[Dictionary]:
	var slot := player.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return [] as Array[Dictionary]
	var events: Array[Dictionary] = []
	match gem.gem_id:
		Constants.GEM_EXPLOSION:
			# 对目标位置引爆（不伤害自己，除非自己在范围内）
			explode_at(state, target_pos, Constants.EXPLOSION_DAMAGE, player.uid)
			events.append({"type": "explode", "pos": target_pos, "radius": Constants.EXPLOSION_RADIUS})
		Constants.GEM_POISON:
			# 在目标位置制造毒雾
			for cell in BoardUtils.cells_in_radius(target_pos, 1):
				TileRules.create_poison_fog(state, cell)
			events.append({"type": "gem_flash", "pos": target_pos, "color": Color(0.4, 0.9, 0.2)})
		Constants.GEM_GRAVITY:
			# 拉扯目标单位到施法者身边并束缚（红槽主动）
			var target_unit := state.get_unit_at(target_pos)
			if target_unit != null and target_unit.uid != player.uid:
				var pull_events := pull_unit_toward_with_events(state, target_unit, player.pos, 2)
				events.append_array(pull_events)
				StatusRules.apply_rooted(state, target_unit, 2)
			events.append({"type": "gem_flash", "pos": player.pos, "color": Color(0.6, 0.3, 1.0)})
		Constants.GEM_HEAVY_ARMOR:
			# 给自己加护甲值（持续 2 回合）
			StatusRules.apply_armor(state, player, 3, 2)
			events.append({"type": "gem_flash", "pos": player.pos, "color": Color(0.8, 0.8, 0.2)})
		Constants.GEM_CONDUCTIVE:
			# 电击目标位置的水洼连通区域
			_activate_water_cluster(state, target_pos)
			events.append({"type": "gem_flash", "pos": target_pos, "color": Color(0.3, 0.8, 1.0)})
		Constants.GEM_FRAGILE:
			# 对目标造成 3 点伤害（玻璃炮：高伤但宝石碎裂消失）
			var target_unit := state.get_unit_at(target_pos)
			if target_unit != null:
				CombatRules.apply_damage(state, target_unit, 3, player.uid, "fragile_skill")
			# 宝石碎裂
			slot.gem_uid = ""
			state.gems.erase(gem.uid)
			state.log("易碎宝石碎裂消失！")
			events.append({"type": "damage", "pos": target_pos, "damage": 3, "is_crit": true})
	state.log("玩家使用技能: %s" % gem.gem_id)
	return events


## 获取玩家红槽技能的描述
static func get_skill_description(gem_id: String) -> String:
	match gem_id:
		Constants.GEM_EXPLOSION:
			return "引爆：对目标格及周围造成 %d 伤害" % Constants.EXPLOSION_DAMAGE
		Constants.GEM_POISON:
			return "毒雾：在目标周围制造毒雾区域"
		Constants.GEM_GRAVITY:
			return "引力：将目标拉向自己并束缚 1 回合"
		Constants.GEM_HEAVY_ARMOR:
			return "重甲：给自己加 3 点护甲（2回合）"
		Constants.GEM_CONDUCTIVE:
			return "导电：电击目标水洼连通区域所有单位"
		Constants.GEM_FRAGILE:
			return "碎击：对目标造成 3 伤害，但宝石碎裂消失"
	return ""


## 检查玩家是否能对目标使用技能
static func can_use_skill_at(state: GameState, player: UnitState, target_pos: Vector2i) -> bool:
	var slot := player.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	if BoardUtils.manhattan(player.pos, target_pos) > Constants.SKILL_RANGE:
		return false
	match gem.gem_id:
		Constants.GEM_HEAVY_ARMOR:
			return true  # 自我施放，不需要目标
		Constants.GEM_CONDUCTIVE:
			var tile := state.get_tile(target_pos)
			return tile.tile_id == Constants.TILE_WATER  # 必须点水洼
		Constants.GEM_GRAVITY:
			var target_unit := state.get_unit_at(target_pos)
			return target_unit != null and target_unit.uid != player.uid
		_:
			return true  # 其他技能对任何范围内格子有效


static func on_red_action(state: GameState, unit: UnitState, intent: IntentState) -> void:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return
	match gem.gem_id:
		Constants.GEM_EXPLOSION:
			_execute_charge_explosion(state, unit, intent.target_uid)
		Constants.GEM_GRAVITY:
			_execute_pull(state, unit, intent.target_uid)
		Constants.GEM_POISON:
			_execute_poison_attack(state, unit, intent.target_uid)
		Constants.GEM_CONDUCTIVE:
			_execute_shock(state, unit, intent.target_uid)
		Constants.GEM_FRAGILE:
			_execute_fragile_charge(state, unit, intent.target_uid)


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> void:
	state.log("爆炸于 %s" % [center])
	for cell in BoardUtils.cells_in_radius(center, Constants.EXPLOSION_RADIUS):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var unit := state.get_unit_at(cell)
		if unit != null:
			CombatRules.apply_damage(state, unit, damage, source_uid, "explosion")
			for slot in unit.slots:
				if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
					StatusRules.apply_exposed(state, unit, slot, state.turn_index)


static func pull_around(state: GameState, center: Vector2i, pull_range: int, steps: int) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		if BoardUtils.chebyshev(center, unit.pos) > pull_range:
			continue
		_pull_unit_toward(state, unit, center, steps)


static func _execute_charge_explosion(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	var path := BoardUtils.path_toward(state, unit.pos, target.pos, 2, unit.uid)
	var previous := unit.pos
	for step in path:
		unit.pos = step
		TileRules.on_unit_moved_through(state, unit, step)
		TileRules.on_unit_entered(state, unit, previous)
		previous = step
	if BoardUtils.manhattan(unit.pos, target.pos) <= 1:
		explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid)
		CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "self_explosion")


static func _execute_pull(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	_pull_unit_toward(state, target, unit.pos, 2)
	StatusRules.apply_rooted(state, target, 2)


static func _pull_unit_toward(state: GameState, unit: UnitState, anchor: Vector2i, steps: int) -> void:
	var previous := unit.pos
	var current := unit.pos
	for _i in range(steps):
		var next := BoardUtils.step_toward(current, anchor)
		if next == current or not BoardUtils.is_passable(state, next, unit.uid):
			break
		current = next
	if current == unit.pos:
		return
	unit.pos = current
	TileRules.on_unit_moved_through(state, unit, current)
	TileRules.on_unit_entered(state, unit, previous)


static func pull_unit_toward_with_events(state: GameState, unit: UnitState, anchor: Vector2i, steps: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var current := unit.pos
	for _i in range(steps):
		var next := BoardUtils.step_toward(current, anchor)
		if next == current or not BoardUtils.is_passable(state, next, unit.uid):
			break
		var from_pos := unit.pos
		unit.pos = next
		TileRules.on_unit_moved_through(state, unit, next)
		TileRules.on_unit_entered(state, unit, from_pos)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})
		current = next
	return events


static func on_unit_turn_start(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match gem.gem_id:
			Constants.GEM_GRAVITY:
				var nearest := _nearest_opponent(state, unit)
				if nearest != null and BoardUtils.manhattan(unit.pos, nearest.pos) <= 3:
					_pull_unit_toward(state, nearest, unit.pos, 1)
					StatusRules.apply_rooted(state, nearest, 2)
			Constants.GEM_EXPLOSION:
				for cell in BoardUtils.neighbors4(unit.pos):
					var target := state.get_unit_at(cell)
					if target != null and target.alive and target.team != unit.team:
						CombatRules.apply_damage(state, target, 1, unit.uid, "blue_explosion_aura")
						break
			Constants.GEM_CONDUCTIVE:
				var current_tile := state.get_tile(unit.pos)
				if current_tile.tile_id == Constants.TILE_WATER:
					for cell in BoardUtils.cells_in_radius(unit.pos, 1):
						var target := state.get_unit_at(cell)
						if target != null and target.alive and target.team != unit.team:
							CombatRules.apply_damage(state, target, 1, unit.uid, "blue_conductive_aura")


static func on_owner_damaged(state: GameState, owner: UnitState, source_uid: String, _damage: int, reason: String) -> void:
	if reason == "blue_conductive_rebound":
		return
	if source_uid.is_empty():
		return
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or not source.alive:
		return
	for slot in owner.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match gem.gem_id:
			Constants.GEM_POISON:
				if BoardUtils.manhattan(owner.pos, source.pos) <= 1:
					StatusRules.apply_poison(state, source, 1, 2)
			Constants.GEM_CONDUCTIVE:
				var owner_tile := state.get_tile(owner.pos)
				if owner_tile.tile_id == Constants.TILE_WATER and BoardUtils.manhattan(owner.pos, source.pos) <= 2:
					CombatRules.apply_damage(state, source, 1, owner.uid, "blue_conductive_rebound")


static func _nearest_opponent(state: GameState, unit: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999
	for other in state.units.values():
		if not other.alive or other.team == unit.team:
			continue
		var dist := BoardUtils.manhattan(unit.pos, other.pos)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


static func _nearest_alive_ally(state: GameState, unit: UnitState) -> UnitState:
	var best: UnitState = null
	var best_dist := 999
	for other in state.units.values():
		if not other.alive or other.uid == unit.uid or other.team != unit.team:
			continue
		var dist := BoardUtils.manhattan(unit.pos, other.pos)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


static func _execute_poison_attack(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) == 1:
		CombatRules.apply_damage(state, target, CombatRules.attack_damage(state, unit), unit.uid, "poison_attack")
		StatusRules.apply_poison(state, target)


static func _execute_shock(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) <= 2:
		CombatRules.apply_damage(state, target, 1, unit.uid, "shock")


static func _execute_fragile_charge(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	var path := BoardUtils.path_toward(state, unit.pos, target.pos, 1, unit.uid)
	if path.is_empty():
		return
	var previous := unit.pos
	unit.pos = path[0]
	TileRules.on_unit_entered(state, unit, previous)
	CombatRules.apply_damage(state, target, 1, unit.uid, "fragile_charge")
	CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "fragile_self")


static func _activate_water_cluster(state: GameState, origin: Vector2i) -> void:
	var cluster := _connected_water(state, origin)
	for pos in cluster:
		var unit := state.get_unit_at(pos)
		if unit != null:
			CombatRules.apply_damage(state, unit, 1, "", "conductive")


static func _connected_water(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	var start_tile := state.get_tile(origin)
	if start_tile.tile_id != Constants.TILE_WATER:
		return [origin]
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
			if not visited.has(neighbor):
				queue.append(neighbor)
	return result


static func _get_owner_pos(state: GameState, owner_uid: String) -> Vector2i:
	var unit: UnitState = state.units.get(owner_uid, null)
	if unit != null:
		return unit.pos
	return Vector2i.ZERO
