class_name GemEffects
extends RefCounted

const TIMING_ACTIVE := "active"
const TIMING_TURN_START := "turn_start"
const TIMING_OWNER_DAMAGED := "owner_damaged"
const TIMING_ON_DEATH := "on_death"
const TIMING_MOVED_THROUGH := "moved_through"

const MODE_TRIGGER := "trigger"
const MODE_SKILL := "skill"
const MODE_ENEMY := "enemy"

const ABILITY_PLAYER_SKILL := "player_skill"
const ABILITY_UNIT_RED_ACTIVE := "unit_red_active"
const ABILITY_ENEMY_RED_ACTION := "enemy_red_action"
const ABILITY_BLUE_TURN_START := "blue_turn_start"
const ABILITY_BLUE_DAMAGED := "blue_damaged"
const ABILITY_BLUE_MOVE_THROUGH := "blue_move_through"
const ABILITY_BLACK_DEATH := "black_death"
const ABILITY_TILE_ACTIVE := "tile_active"
const ABILITY_TILE_TURN_START := "tile_turn_start"
const ABILITY_ATTACK_BONUS := "attack_bonus"
const ABILITY_ARMOR_BONUS := "armor_bonus"


static func run_unit_hooks(state: GameState, unit: UnitState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in unit.slots:
		if slot.slot_type != slot_type or slot.gem_uid.is_empty():
			continue
		_run_slot_hook(state, unit, slot, timing, ctx)


static func run_tile_hooks(state: GameState, tile: TileState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in tile.slots:
		if slot.slot_type != slot_type or slot.gem_uid.is_empty():
			continue
		_run_slot_hook(state, tile, slot, timing, ctx)


static func on_tile_gem_inserted(state: GameState, tile: TileState, slot: SlotState, gem: GemState) -> void:
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	if tile.tile_id == Constants.TILE_ALTAR and slot.slot_type == Constants.SLOT_RED:
		state.log("祭坛激活！宝石 %s 释放能量" % gem_name)
		_run_slot_hook(state, tile, slot, TIMING_ACTIVE, {})
	elif tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("机关柱激活！宝石 %s 产生光环" % gem_name)


static func trigger_tile_gem(state: GameState, tile: TileState, slot: SlotState) -> bool:
	if tile.tile_id == Constants.TILE_ALTAR and slot.slot_type == Constants.SLOT_RED:
		state.log("触发 %s 地块的 %s" % [tile.tile_id, _gem_id(state, slot)])
		return _run_slot_hook(state, tile, slot, TIMING_ACTIVE, {})
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("触发 %s 地块的 %s" % [tile.tile_id, _gem_id(state, slot)])
		return _run_slot_hook(state, tile, slot, TIMING_TURN_START, {})
	return false


static func trigger_gem(state: GameState, owner_uid: String, slot: SlotState) -> bool:
	if slot.slot_type != Constants.SLOT_RED:
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	var owner: UnitState = state.units.get(owner_uid, null)
	if owner == null:
		return false
	return _run_slot_hook(state, owner, slot, TIMING_ACTIVE, {})


static func on_unit_death(state: GameState, unit: UnitState) -> void:
	run_unit_hooks(state, unit, Constants.SLOT_BLACK, TIMING_ON_DEATH, {})


## 玩家使用红槽技能：对目标位置/单位施放，效果因宝石而异
## 返回动画事件列表
static func player_use_skill(state: GameState, player: UnitState, target_pos: Vector2i) -> Array[Dictionary]:
	var slot := player.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return [] as Array[Dictionary]
	if not _run_slot_hook(state, player, slot, TIMING_ACTIVE, {"mode": MODE_SKILL, "target_pos": target_pos}):
		return [] as Array[Dictionary]
	state.log("玩家使用技能: %s" % _data_registry().get_gem_display_name(gem))
	return _build_player_skill_events(gem, player, target_pos)


static func _build_player_skill_events(gem: GemState, player: UnitState, target_pos: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match _ability_profile(gem, ABILITY_PLAYER_SKILL):
		"explosion":
			events.append({"type": "explode", "pos": target_pos, "radius": Constants.EXPLOSION_RADIUS})
		"poison":
			events.append({"type": "poison_burst", "pos": target_pos, "radius": 1})
		"gravity", "heavy_armor":
			events.append({"type": "gem_flash", "pos": player.pos, "color": _data_registry().get_gem_color(gem)})
		"conductive":
			events.append({"type": "gem_flash", "pos": target_pos, "color": _data_registry().get_gem_color(gem)})
		"fragile":
			events.append({"type": "damage", "pos": target_pos, "damage": 3, "is_crit": true})
	return events


## 获取玩家红槽技能的描述
static func get_skill_description(gem_ref: Variant) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, Constants.SLOT_RED, "player_skill")


static func get_slot_effect_description(gem_ref: Variant, slot_type: String, context: String) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, slot_type, context)


static func get_attack_bonus(state: GameState, unit: UnitState) -> int:
	var bonus := 0
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if _ability_profile(gem, ABILITY_ATTACK_BONUS) == "fragile":
			bonus += 1
	return bonus


static func get_armor_bonus(state: GameState, unit: UnitState) -> int:
	var bonus := 0
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match _ability_profile(gem, ABILITY_ARMOR_BONUS):
			"heavy_armor":
				bonus += 2
			"conductive":
				var tile := state.get_tile(unit.pos)
				if tile.tile_id == Constants.TILE_WATER:
					bonus += 1
	return bonus


static func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	return _data_registry().get_enemy_red_intent_meta(gem_ref, damage)


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
	match _player_skill_target_mode(gem):
		"self":
			return target_pos == player.pos
		"water_tile":
			var tile := state.get_tile(target_pos)
			return tile.tile_id == Constants.TILE_WATER
		"enemy_unit":
			var target_unit := state.get_unit_at(target_pos)
			return target_unit != null and target_unit.uid != player.uid
		_:
			return true


static func on_red_action(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	return _run_enemy_red_action(state, unit, slot, intent.target_uid)


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	return _explode_at(state, center, damage, source_uid)


static func _explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.log("爆炸于 %s" % [center])
	for cell in BoardUtils.cells_in_radius(center, Constants.EXPLOSION_RADIUS):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_unit := state.get_unit_at(cell)
		if hit_unit == null:
			continue
		var dealt := CombatRules.apply_damage(state, hit_unit, damage, source_uid, "explosion")
		if dealt > 0:
			events.append({"type": "damage", "pos": hit_unit.pos, "damage": dealt, "is_crit": false})
		for slot in hit_unit.slots:
			if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
				StatusRules.apply_exposed(state, hit_unit, slot, state.turn_index)
	return events


static func pull_around(state: GameState, center: Vector2i, pull_range: int, steps: int, source_uid: String = "") -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.pos == center:
			continue
		if BoardUtils.chebyshev(center, unit.pos) > pull_range:
			continue
		pull_unit_toward_with_events(state, unit, center, steps, source_uid)


static func _execute_charge_explosion(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return events
	var path := BoardUtils.path_toward(state, unit.pos, target.pos, 2, unit.uid)
	var start_pos := unit.pos
	for step in path:
		var from_pos := unit.pos
		unit.pos = step
		TileRules.on_unit_moved_through(state, unit, step)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": step})
	if unit.pos != start_pos:
		TileRules.on_unit_entered(state, unit, start_pos)
	events.append({"type": "explode", "pos": unit.pos, "radius": Constants.EXPLOSION_RADIUS})
	events.append_array(_explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid))
	var self_dealt := CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "self_explosion")
	if self_dealt > 0:
		events.append({"type": "damage", "pos": unit.pos, "damage": self_dealt, "is_crit": false})
	return events


static func _run_enemy_red_action(state: GameState, unit: UnitState, slot: SlotState, target_uid: String) -> Array[Dictionary]:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return [] as Array[Dictionary]
	match _enemy_red_action_kind(gem):
		"charge_explode":
			return _execute_charge_explosion(state, unit, target_uid)
		"poison_attack":
			var poison_target: UnitState = state.units.get(target_uid, null)
			if poison_target == null or BoardUtils.manhattan(unit.pos, poison_target.pos) != 1:
				return [] as Array[Dictionary]
			var poison_events := _enemy_red_damage_events(state, unit, target_uid, CombatRules.attack_damage(state, unit), "poison_attack")
			if poison_target.alive:
				StatusRules.apply_poison(state, poison_target)
			return poison_events
		"pull":
			return _execute_pull_events(state, unit, target_uid)
		"shock":
			var shock_target: UnitState = state.units.get(target_uid, null)
			if shock_target == null or BoardUtils.manhattan(unit.pos, shock_target.pos) > 2:
				return [] as Array[Dictionary]
			return _enemy_red_damage_events(state, unit, target_uid, 1, "shock")
		"fragile_charge":
			return _execute_fragile_charge_events(state, unit, target_uid)
	return [] as Array[Dictionary]


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
	return [{"type": "damage", "pos": target.pos, "damage": dealt, "is_crit": is_crit}]


static func _execute_pull_events(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null or not target.alive:
		return [] as Array[Dictionary]
	var events := pull_unit_toward_with_events(state, target, unit.pos, 2, unit.uid)
	StatusRules.apply_rooted(state, target, 2)
	return events


static func _pull_unit_toward(state: GameState, unit: UnitState, anchor: Vector2i, steps: int, source_uid: String = "") -> void:
	pull_unit_toward_with_events(state, unit, anchor, steps, source_uid)


static func pull_unit_toward_with_events(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String = ""
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not unit.alive or steps <= 0:
		return events
	var start_pos := unit.pos
	var current := unit.pos
	for _i in range(steps):
		if current == anchor:
			break
		var next := BoardUtils.step_toward(current, anchor)
		if next == current:
			break
		if not BoardUtils.in_bounds(state, next):
			break
		var blocker: UnitState = state.get_unit_at(next)
		if blocker != null:
			events.append_array(_apply_gravity_collision(state, unit, blocker, source_uid))
			break
		var from_pos := unit.pos
		unit.pos = next
		TileRules.on_unit_moved_through(state, unit, next)
		events.append({"type": "move_step", "uid": unit.uid, "from": from_pos, "to": next})
		current = next
	if unit.pos != start_pos:
		TileRules.on_unit_entered(state, unit, start_pos)
	return events


static func _apply_gravity_collision(
	state: GameState,
	mover: UnitState,
	blocker: UnitState,
	source_uid: String
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not mover.alive or not blocker.alive:
		return events
	state.log("%s 与 %s 引力碰撞" % [mover.uid, blocker.uid])
	var mover_dealt := CombatRules.apply_damage(
		state,
		mover,
		Constants.GRAVITY_COLLISION_DAMAGE,
		blocker.uid,
		"gravity_collision"
	)
	var blocker_dealt := CombatRules.apply_damage(
		state,
		blocker,
		Constants.GRAVITY_COLLISION_DAMAGE,
		source_uid if not source_uid.is_empty() else mover.uid,
		"gravity_collision"
	)
	if mover_dealt > 0:
		events.append({"type": "damage", "pos": mover.pos, "damage": mover_dealt, "is_crit": false})
	if blocker_dealt > 0:
		events.append({"type": "damage", "pos": blocker.pos, "damage": blocker_dealt, "is_crit": false})
	return events


static func _run_slot_hook(state: GameState, owner: Variant, slot: SlotState, timing: String, ctx: Dictionary) -> bool:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	if owner is TileState:
		return _run_tile_slot_hook(state, owner as TileState, slot, gem, timing)
	if owner is UnitState:
		return _run_unit_slot_hook(state, owner as UnitState, slot, gem, timing, ctx)
	return false


static func _run_unit_slot_hook(state: GameState, owner: UnitState, slot: SlotState, gem: GemState, timing: String, ctx: Dictionary) -> bool:
	match timing:
		TIMING_ACTIVE:
			if slot.slot_type != Constants.SLOT_RED:
				return false
			return _run_unit_active_effect(state, owner, slot, gem, ctx)
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_turn_start_effect(state, owner, gem)
		TIMING_OWNER_DAMAGED:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_damaged_effect(state, owner, gem, ctx)
		TIMING_ON_DEATH:
			if slot.slot_type != Constants.SLOT_BLACK:
				return false
			return _run_unit_death_effect(state, owner, gem)
		TIMING_MOVED_THROUGH:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_moved_through_effect(state, owner, gem, ctx)
	return false


static func _run_unit_active_effect(state: GameState, owner: UnitState, slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var mode: String = ctx.get("mode", MODE_TRIGGER)
	var ability_slot := ABILITY_UNIT_RED_ACTIVE
	if mode == MODE_SKILL:
		ability_slot = ABILITY_PLAYER_SKILL
	elif mode == MODE_ENEMY:
		ability_slot = ABILITY_ENEMY_RED_ACTION
	match _ability_profile(gem, ability_slot):
		"explosion":
			match mode:
				MODE_TRIGGER:
					explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid)
				MODE_SKILL:
					explode_at(state, ctx.get("target_pos", owner.pos), Constants.EXPLOSION_DAMAGE, owner.uid)
				MODE_ENEMY:
					_execute_charge_explosion(state, owner, ctx.get("target_uid", ""))
			return true
		"poison":
			match mode:
				MODE_TRIGGER:
					TileRules.create_poison_fog(state, owner.pos)
				MODE_SKILL:
					var skill_anchor: Vector2i = ctx.get("target_pos", owner.pos)
					for cell in BoardUtils.cells_in_radius(skill_anchor, 1):
						TileRules.create_poison_fog(state, cell)
						var occ: UnitState = state.get_unit_at(cell)
						if occ != null and occ.alive and occ.team != owner.team:
							StatusRules.apply_poison(state, occ, 1, Constants.POISON_SKILL_DEBUFF_TURNS)
				MODE_ENEMY:
					_execute_poison_attack(state, owner, ctx.get("target_uid", ""))
			return true
		"gravity":
			match mode:
				MODE_TRIGGER:
					pull_around(state, owner.pos, 2, 1, owner.uid)
				MODE_SKILL:
					var target_unit := state.get_unit_at(ctx.get("target_pos", owner.pos))
					if target_unit != null and target_unit.uid != owner.uid:
						pull_unit_toward_with_events(state, target_unit, owner.pos, 2, owner.uid)
						StatusRules.apply_rooted(state, target_unit, 2)
				MODE_ENEMY:
					_execute_pull_events(state, owner, ctx.get("target_uid", ""))
			return true
		"heavy_armor":
			match mode:
				MODE_TRIGGER:
					StatusRules.apply_armor(state, owner, 2, 1)
				MODE_SKILL, MODE_ENEMY:
					StatusRules.apply_armor(state, owner, 3, 2)
			return true
		"conductive":
			match mode:
				MODE_TRIGGER:
					_activate_water_cluster(state, owner.pos)
				MODE_SKILL:
					_activate_water_cluster(state, ctx.get("target_pos", owner.pos))
				MODE_ENEMY:
					_execute_shock(state, owner, ctx.get("target_uid", ""))
			return true
		"fragile":
			match mode:
				MODE_TRIGGER:
					CombatRules.apply_damage(state, owner, owner.hp, owner.uid, "fragile_trigger")
				MODE_SKILL:
					var fragile_target := state.get_unit_at(ctx.get("target_pos", owner.pos))
					if fragile_target != null:
						CombatRules.apply_damage(state, fragile_target, 3, owner.uid, "fragile_skill")
					_destroy_unit_slot_gem(state, owner, slot, gem)
				MODE_ENEMY:
					_execute_fragile_charge(state, owner, ctx.get("target_uid", ""))
			return true
	return false


static func _run_unit_turn_start_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_BLUE_TURN_START):
		"gravity":
			var nearest := _nearest_opponent(state, owner)
			if nearest != null and BoardUtils.chebyshev(owner.pos, nearest.pos) <= 3:
				_pull_unit_toward(state, nearest, owner.pos, 1, owner.uid)
				StatusRules.apply_rooted(state, nearest, 2)
			return true
		"explosion":
			for cell in BoardUtils.neighbors4(owner.pos):
				var target := state.get_unit_at(cell)
				if target != null and target.alive and target.team != owner.team:
					CombatRules.apply_damage(state, target, 1, owner.uid, "blue_explosion_aura")
					break
			return true
		"conductive":
			var current_tile := state.get_tile(owner.pos)
			if current_tile.tile_id == Constants.TILE_WATER:
				for cell in BoardUtils.cells_in_radius(owner.pos, 1):
					var target := state.get_unit_at(cell)
					if target != null and target.alive and target.team != owner.team:
						CombatRules.apply_damage(state, target, 1, owner.uid, "blue_conductive_aura")
			return true
	return false


static func _run_unit_damaged_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var reason: String = ctx.get("reason", "")
	if reason == "blue_conductive_rebound":
		return false
	var source_uid: String = ctx.get("source_uid", "")
	if source_uid.is_empty():
		return false
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or not source.alive:
		return false
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			if BoardUtils.manhattan(owner.pos, source.pos) <= 1:
				StatusRules.apply_poison(state, source, 1, 2)
			return true
		"conductive":
			var owner_tile := state.get_tile(owner.pos)
			if owner_tile.tile_id == Constants.TILE_WATER and BoardUtils.manhattan(owner.pos, source.pos) <= 2:
				CombatRules.apply_damage(state, source, 1, owner.uid, "blue_conductive_rebound")
			return true
	return false


static func _run_unit_death_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_BLACK_DEATH):
		"explosion":
			explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid)
			return true
		"poison":
			for cell in BoardUtils.cells_in_radius(owner.pos, 1):
				TileRules.create_poison_fog(state, cell)
			return true
		"gravity":
			pull_around(state, owner.pos, 2, 1, owner.uid)
			return true
		"fragile":
			for neighbor in BoardUtils.neighbors4(owner.pos):
				var target := state.get_unit_at(neighbor)
				if target != null:
					CombatRules.apply_damage(state, target, 1, owner.uid, "fragile_shatter")
			return true
		"conductive":
			for cell in BoardUtils.cells_in_radius(owner.pos, 2):
				var tile := state.get_tile(cell)
				if tile.tile_id == Constants.TILE_WATER:
					_activate_water_cluster(state, cell)
			return true
		"heavy_armor":
			var ally := _nearest_alive_ally(state, owner)
			if ally != null:
				StatusRules.apply_armor(state, ally, 3, 2)
				state.log("%s 死亡后将重甲遗产传给 %s" % [owner.uid, ally.uid])
			return true
	return false


static func _run_unit_moved_through_effect(state: GameState, _owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var pass_pos: Vector2i = ctx.get("pos", _owner.pos)
	if _ability_profile(gem, ABILITY_BLUE_MOVE_THROUGH) == "poison":
		TileRules.create_poison_fog(state, pass_pos)
		return true
	return false


static func _destroy_unit_slot_gem(state: GameState, owner: UnitState, slot: SlotState, gem: GemState) -> void:
	slot.gem_uid = ""
	state.gems.erase(gem.uid)
	state.log("易碎宝石碎裂消失！")


static func _run_tile_slot_hook(state: GameState, tile: TileState, slot: SlotState, gem: GemState, timing: String) -> bool:
	match timing:
		TIMING_ACTIVE:
			if slot.slot_type != Constants.SLOT_RED or tile.tile_id != Constants.TILE_ALTAR:
				return false
			return _run_tile_active_effect(state, tile, slot, gem)
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE or tile.tile_id != Constants.TILE_PILLAR:
				return false
			return _run_tile_turn_start_effect(state, tile, gem)
	return false


static func _run_tile_active_effect(state: GameState, tile: TileState, slot: SlotState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_TILE_ACTIVE):
		"explosion":
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY:
					CombatRules.apply_damage(state, unit, 1, "", "altar_explosion")
			return true
		"poison":
			for cell in BoardUtils.cells_in_radius(tile.pos, 2):
				TileRules.create_poison_fog(state, cell)
			return true
		"gravity":
			pull_around(state, tile.pos, 4, 1)
			return true
		"heavy_armor":
			var player := state.get_player()
			if player != null:
				StatusRules.apply_armor(state, player, 4, 3)
			return true
		"conductive":
			for key in state.tiles.keys():
				var water_tile: TileState = state.tiles[key]
				if water_tile.tile_id != Constants.TILE_WATER:
					continue
				var unit := state.get_unit_at(water_tile.pos)
				if unit != null:
					CombatRules.apply_damage(state, unit, 2, "", "altar_emp")
			return true
		"fragile":
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY:
					CombatRules.apply_damage(state, unit, 2, "", "altar_shatter")
			_destroy_tile_slot_gem(state, tile, slot, gem)
			return true
	return false


static func _run_tile_turn_start_effect(state: GameState, tile: TileState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_TILE_TURN_START):
		"heavy_armor":
			var player := state.get_player()
			if player != null and BoardUtils.manhattan(player.pos, tile.pos) <= 2:
				StatusRules.apply_armor(state, player, 1, 1)
			return true
		"poison":
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 2:
					StatusRules.apply_poison(state, unit)
			return true
		"explosion":
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 1:
					CombatRules.apply_damage(state, unit, 1, "", "pillar_burn")
			return true
		"gravity":
			pull_around(state, tile.pos, 2, 1)
			return true
		"conductive":
			for key in state.tiles.keys():
				var water_tile: TileState = state.tiles[key]
				if water_tile.tile_id != Constants.TILE_WATER:
					continue
				if BoardUtils.manhattan(water_tile.pos, tile.pos) > 3:
					continue
				var unit := state.get_unit_at(water_tile.pos)
				if unit != null:
					CombatRules.apply_damage(state, unit, 1, "", "pillar_shock")
			return true
	return false


static func _destroy_tile_slot_gem(state: GameState, _tile: TileState, slot: SlotState, gem: GemState) -> void:
	slot.gem_uid = ""
	state.gems.erase(gem.uid)
	state.log("易碎宝石在祭坛中碎裂！")


static func _gem_id(state: GameState, slot: SlotState) -> String:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return ""
	return _data_registry().get_gem_display_name(gem)


static func _player_skill_target_mode(gem_ref: Variant) -> String:
	return _data_registry().get_player_skill_target_mode(gem_ref)


static func _enemy_red_action_kind(gem_ref: Variant) -> String:
	return str(_data_registry().get_enemy_red_intent_meta(gem_ref, 0).get("type", "wait"))


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


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


static func _ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem_ref, ability_slot)


static func _execute_fragile_charge_events(state: GameState, unit: UnitState, target_uid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return events
	var path := BoardUtils.path_toward(state, unit.pos, target.pos, 1, unit.uid)
	if path.is_empty():
		return events
	var previous := unit.pos
	unit.pos = path[0]
	TileRules.on_unit_entered(state, unit, previous)
	events.append({"type": "move_step", "uid": unit.uid, "from": previous, "to": unit.pos})
	var dealt := CombatRules.apply_damage(state, target, 1, unit.uid, "fragile_charge")
	if dealt > 0:
		events.append({"type": "damage", "pos": target.pos, "damage": dealt, "is_crit": false})
	var self_dealt := CombatRules.apply_damage(state, unit, unit.hp, unit.uid, "fragile_self")
	if self_dealt > 0:
		events.append({"type": "damage", "pos": unit.pos, "damage": self_dealt, "is_crit": false})
	return events


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
