class_name GemEffects
extends RefCounted

const _Displacement = preload("res://scripts/rules/displacement.gd")

const TIMING_ACTIVE := "active"
const TIMING_TURN_START := "turn_start"
const TIMING_OWNER_DAMAGED := "owner_damaged"
const TIMING_ON_DEATH := "on_death"
const TIMING_MOVED_THROUGH := "moved_through"
const TIMING_FORCED_MOVE := "forced_move"   # 被强制位移时（击退、引力等）
const TIMING_ON_CONTACT := "on_contact"     # 接触时（碰撞、相邻、攻击）

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
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("机关柱激活！宝石 %s 产生光环" % gem_name)


static func trigger_tile_gem(state: GameState, tile: TileState, slot: SlotState) -> bool:
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


static func on_unit_death(state: GameState, unit: UnitState, out_events: Array[Dictionary] = []) -> void:
	_run_death_hooks_with_events(state, unit, out_events)


## 玩家使用红槽技能：对目标位置/单位施放，效果因宝石而异
## 返回动画事件列表
static func player_use_skill(state: GameState, player: UnitState, target_pos: Vector2i) -> Array[Dictionary]:
	var slot := player.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return [] as Array[Dictionary]
	var skill_events: Array[Dictionary] = []
	var hook_ctx := {
		"mode": MODE_SKILL,
		"target_pos": target_pos,
		"events": skill_events,
	}
	if not _run_slot_hook(state, player, slot, TIMING_ACTIVE, hook_ctx):
		return [] as Array[Dictionary]
	state.log("玩家使用技能: %s" % _data_registry().get_gem_display_name(gem))
	skill_events.append_array(_build_player_skill_events(gem, player, target_pos))
	return skill_events


static func _build_player_skill_events(gem: GemState, player: UnitState, target_pos: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match _ability_profile(gem, ABILITY_PLAYER_SKILL):
		"explosion":
			events.append({"type": "explode", "pos": target_pos, "radius": Constants.EXPLOSION_RADIUS})
		"poison":
			events.append({"type": "poison_burst", "pos": target_pos, "radius": 1})
		"gravity":
			events.append({"type": "gem_flash", "pos": player.pos, "color": _data_registry().get_gem_color(gem)})
		"arc", "fire_gem", "ice":
			events.append({"type": "gem_flash", "pos": target_pos, "color": _data_registry().get_gem_color(gem)})
	return events


## 获取玩家红槽技能的描述
static func get_skill_description(gem_ref: Variant) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, Constants.SLOT_RED, "player_skill")


static func get_slot_effect_description(gem_ref: Variant, slot_type: String, context: String) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, slot_type, context)


static func get_attack_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0


static func get_armor_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0


static func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	return _data_registry().get_enemy_red_intent_meta(gem_ref, damage)


static func unit_has_red_arc(state: GameState, unit: UnitState) -> bool:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	return _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == "arc"


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
			return tile.has_tile_tag(Constants.TAG_TILE_CONDUCTIVE)
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
		# 爆炸冲击波：将命中单位推离爆炸中心（skip_gem_hooks=true 防止链式触发）
		if hit_unit.alive and hit_unit.pos != center:
			_Displacement.knockback(state, hit_unit, center, 1, source_uid, events, Constants.KNOCKBACK_COLLISION_DAMAGE, true)
	return events


## 强制位移钩子：携带爆炸宝石的单位被强制位移时自爆
static func on_forced_displacement(state: GameState, unit: UnitState, events: Array[Dictionary]) -> void:
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		# 蓝槽爆炸宝石：被强制位移时引发爆炸
		if slot.slot_type == Constants.SLOT_BLUE and _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "explosion":
			state.log("%s 被强制位移触发爆炸！" % unit.uid)
			events.append({"type": "explode", "pos": unit.pos, "radius": Constants.EXPLOSION_RADIUS})
			events.append_array(_explode_at(state, unit.pos, Constants.EXPLOSION_DAMAGE, unit.uid))
			break


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
		"arc_attack":
			var arc_target: UnitState = state.units.get(target_uid, null)
			if arc_target == null or not arc_target.alive:
				return [] as Array[Dictionary]
			if BoardUtils.manhattan(unit.pos, arc_target.pos) > Constants.ATTACK_RANGE:
				return [] as Array[Dictionary]
			var arc_base := CombatRules.attack_damage(state, unit)
			var arc_events := _enemy_red_damage_events(state, unit, target_uid, arc_base, "arc_attack")
			if arc_target.alive:
				apply_arc_bounce_from_victim(state, arc_target, unit, arc_base, arc_events)
			return arc_events
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
		TileRules.on_unit_position_changed(state, unit, start_pos)
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
		TIMING_ON_CONTACT:
			if slot.slot_type != Constants.SLOT_BLUE:
				return false
			return _run_unit_contact_effect(state, owner, gem, ctx)
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
		"arc":
			var out_events: Array[Dictionary] = _events_from_ctx(ctx)
			var arc_anchor: Vector2i = ctx.get("target_pos", owner.pos)
			match mode:
				MODE_TRIGGER, MODE_ENEMY:
					var trigger_tile := state.get_tile(arc_anchor)
					if trigger_tile != null and trigger_tile.has_tile_tag(Constants.TAG_TILE_WATER):
						apply_water_conduction(state, arc_anchor, owner, out_events)
					else:
						var arc_target: UnitState = state.get_unit_at(arc_anchor)
						if arc_target == null:
							arc_target = state.units.get(ctx.get("target_uid", ""), null)
						if arc_target != null and arc_target.alive:
							var arc_base := CombatRules.attack_damage(state, owner)
							_arc_to(state, arc_target, owner.uid, _calc_arc_damage(arc_base), out_events)
							apply_arc_bounce_from_victim(state, arc_target, owner, arc_base, out_events)
				MODE_SKILL:
					var skill_tile := state.get_tile(arc_anchor)
					if skill_tile != null and skill_tile.has_tile_tag(Constants.TAG_TILE_WATER):
						apply_water_conduction(state, arc_anchor, owner, out_events)
					else:
						var skill_victim := state.get_unit_at(arc_anchor)
						if skill_victim != null and skill_victim.alive and skill_victim.uid != owner.uid:
							var skill_base := CombatRules.attack_damage(state, owner)
							_arc_to(state, skill_victim, owner.uid, _calc_arc_damage(skill_base), out_events)
							apply_arc_bounce_from_victim(state, skill_victim, owner, skill_base, out_events)
			return true
		"fire_gem":
			match mode:
				MODE_TRIGGER:
					TileRules.create_fire(state, owner.pos)
				MODE_SKILL:
					var fire_target_pos: Vector2i = ctx.get("target_pos", owner.pos)
					TileRules.create_fire(state, fire_target_pos)
					var fire_occ := state.get_unit_at(fire_target_pos)
					if fire_occ != null and fire_occ.alive and fire_occ.team != owner.team:
						StatusRules.apply_burning(state, fire_occ, 1, owner.uid)
				MODE_ENEMY:
					var fire_t: UnitState = state.units.get(ctx.get("target_uid", ""), null)
					if fire_t != null and fire_t.alive:
						StatusRules.apply_burning(state, fire_t, 1, owner.uid)
			return true
		"ice":
			match mode:
				MODE_TRIGGER:
					StatusRules.apply_slowed(state, owner, 1, owner.uid)
				MODE_SKILL:
					var ice_target := state.get_unit_at(ctx.get("target_pos", owner.pos))
					if ice_target != null and ice_target.uid != owner.uid:
						apply_ice_hit_effect(state, ice_target, owner.uid)
				MODE_ENEMY:
					var ice_t: UnitState = state.units.get(ctx.get("target_uid", ""), null)
					if ice_t != null and ice_t.alive:
						apply_ice_hit_effect(state, ice_t, owner.uid)
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
	return false


static func _run_unit_damaged_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var reason: String = ctx.get("reason", "")
	var source_uid: String = ctx.get("source_uid", "")
	var damage: int = ctx.get("damage", 0)
	var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"explosion":
			if reason == "burning" or reason == "tile_fire":
				state.log("%s 被火焰点燃引爆！" % owner.uid)
				var dummy_events: Array[Dictionary] = []
				dummy_events.append({"type": "explode", "pos": owner.pos, "radius": Constants.EXPLOSION_RADIUS})
				dummy_events.append_array(_explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid))
			return true
		"gravity":
			if source != null and source.alive and BoardUtils.manhattan(owner.pos, source.pos) > 1 and damage > 0:
				var deflect_target: UnitState = _random_neighbor_unit(state, owner, source.uid)
				if deflect_target != null:
					CombatRules.apply_damage(state, deflect_target, damage, owner.uid, "gravity_deflect")
				# 若无单位则弹到自身脚下地块（不造成单位伤害，仅标记事件）
			return true
		"arc":
			if source != null and source.alive and randf() < Constants.ARC_PARALYSIS_CHANCE:
				var rebound_events: Array[Dictionary] = []
				_arc_to(state, source, owner.uid, CombatRules.attack_damage(state, owner), rebound_events)
			return true
	return false


## 带事件输出的死亡钩子入口
static func _run_death_hooks_with_events(state: GameState, unit: UnitState, out_events: Array[Dictionary]) -> void:
	for slot in unit.slots:
		if slot.slot_type != Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		_run_unit_death_effect_with_events(state, unit, gem, out_events)


static func _run_unit_death_effect_with_events(state: GameState, owner: UnitState, gem: GemState, out_events: Array[Dictionary]) -> bool:
	match _ability_profile(gem, ABILITY_BLACK_DEATH):
		"explosion":
			var evs := explode_at(state, owner.pos, Constants.EXPLOSION_DAMAGE, owner.uid)
			out_events.append({"type": "explode", "pos": owner.pos, "radius": Constants.EXPLOSION_RADIUS})
			out_events.append_array(evs)
			return true
		"poison":
			_transfer_debuffs_to_random_units(state, owner, 1)
			return true
		"gravity":
			# 死亡时将 3x3 范围内单位拉向自身（产生 move_step 事件）
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) > Constants.EXPLOSION_DEATH_RADIUS:
					continue
				_Displacement.pull_toward(state, unit, owner.pos, 1, owner.uid, out_events)
			return true
		"arc":
			# 黑槽导电：死亡落雷，3x3 范围内随机单位，固定 10 伤害，33% 概率麻痹
			var candidates: Array[UnitState] = []
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= Constants.ICE_DEATH_RADIUS:
					candidates.append(unit)
			if not candidates.is_empty():
				var strike_target: UnitState = candidates[randi() % candidates.size()]
				var dealt := CombatRules.apply_true_damage(
					state, strike_target, Constants.LIGHTNING_DEATH_DAMAGE, owner.uid, "lightning_death"
				)
				if dealt > 0:
					out_events.append({"type": "damage", "pos": strike_target.pos, "damage": dealt, "is_crit": false})
				if strike_target.alive and randf() < Constants.ARC_PARALYSIS_CHANCE:
					StatusRules.apply_paralyzed(state, strike_target, 1, owner.uid)
				out_events.append({"type": "lightning", "pos": owner.pos, "target_pos": strike_target.pos})
			return true
		"fire_gem":
			# 黑槽燃烧：5x5 范围内随机选 5 个空地块创建火焰
			_scatter_fire_on_death(state, owner, out_events)
			return true
		"ice":
			# 黑槽冰冻：3x3 范围内所有单位下回合行动顺序垫底
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= Constants.ICE_DEATH_RADIUS:
					StatusRules.apply_sluggish(state, unit, owner.uid)
					out_events.append({"type": "frost_pulse", "pos": unit.pos})
			return true
	return false


static func _run_unit_death_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	var dummy: Array[Dictionary] = []
	return _run_unit_death_effect_with_events(state, owner, gem, dummy)


static func _run_unit_moved_through_effect(_state: GameState, _owner: UnitState, _gem: GemState, _ctx: Dictionary) -> bool:
	return false


## 蓝槽接触效果：接触到其他单位时触发
static func _run_unit_contact_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var other: UnitState = ctx.get("target", null)
	if other == null or not other.alive:
		return false
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			StatusRules.apply_poison(state, other, 1, 0, owner.uid)
			return true
		"fire_gem":
			StatusRules.apply_burning(state, other, 1, owner.uid)
			return true
		"ice":
			StatusRules.apply_slowed(state, other, 1, owner.uid)
			return true
	return false


static func _run_tile_slot_hook(state: GameState, tile: TileState, slot: SlotState, gem: GemState, timing: String) -> bool:
	match timing:
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE or tile.tile_id != Constants.TILE_PILLAR:
				return false
			return _run_tile_turn_start_effect(state, tile, gem)
	return false


static func _run_tile_turn_start_effect(state: GameState, tile: TileState, gem: GemState) -> bool:
	match _ability_profile(gem, ABILITY_TILE_TURN_START):
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
	return false



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


static func _random_neighbor_unit(state: GameState, center: UnitState, exclude_uid: String = "") -> UnitState:
	var candidates: Array[UnitState] = []
	for cell in BoardUtils.cells_in_radius(center.pos, 1):
		if cell == center.pos:
			continue
		var unit := state.get_unit_at(cell)
		if unit != null and unit.alive and unit.uid != center.uid and unit.uid != exclude_uid:
			candidates.append(unit)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]



static func _execute_poison_attack(state: GameState, unit: UnitState, target_uid: String) -> void:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return
	if BoardUtils.manhattan(unit.pos, target.pos) == 1:
		CombatRules.apply_damage(state, target, CombatRules.attack_damage(state, unit), unit.uid, "poison_attack")
		StatusRules.apply_poison(state, target)


static func _ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem_ref, ability_slot)


## ─── 电弧（arc）辅助 ──────────────────────────────────────────────────────

static func _calc_arc_damage(base_damage: int) -> int:
	return maxi(1, int(base_damage * Constants.ARC_CHAIN_DAMAGE_RATIO))


static func _events_from_ctx(ctx: Dictionary) -> Array[Dictionary]:
	var raw: Variant = ctx.get("events", null)
	if raw is Array:
		return raw as Array[Dictionary]
	return [] as Array[Dictionary]


## 攻击水域：对相连水域及其边缘格上的所有潮湿单位各造成一次电弧伤害
static func apply_water_conduction(
	state: GameState,
	anchor_pos: Vector2i,
	attacker: UnitState,
	events: Array[Dictionary]
) -> void:
	var cluster := BoardUtils.water_cluster(state, anchor_pos)
	if cluster.is_empty():
		return
	var zone := BoardUtils.water_conduction_zone(cluster)
	var arc_damage := _calc_arc_damage(CombatRules.attack_damage(state, attacker))
	var hit_uids: Dictionary = {}
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not _unit_in_water_conduction_zone(state, unit, zone):
			continue
		if hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_arc_to(state, unit, attacker.uid, arc_damage, events)
	state.log("水域导电 %s，命中 %d 名单位" % [anchor_pos, hit_uids.size()])


## 水域导电目标：站在水域格上，或导电区边缘格且带潮湿
static func _unit_in_water_conduction_zone(state: GameState, unit: UnitState, zone: Dictionary) -> bool:
	if not zone.has(unit.pos):
		return false
	var tile := state.get_tile(unit.pos)
	if tile != null and tile.has_tile_tag(Constants.TAG_TILE_WATER):
		return true
	return StatusRules.is_wet(unit)


## 红槽攻击 TAG_ARC：以被击者为锚，向切比雪夫 2 格内另一敌方弹射 1 次（伤害为普攻 ARC_CHAIN_DAMAGE_RATIO）
static func apply_arc_bounce_from_victim(
	state: GameState,
	victim: UnitState,
	attacker: UnitState,
	base_damage: int,
	events: Array[Dictionary]
) -> void:
	if not victim.alive:
		return
	var arc_damage := _calc_arc_damage(base_damage)
	var candidates: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.uid == victim.uid or unit.uid == attacker.uid:
			continue
		if BoardUtils.chebyshev(victim.pos, unit.pos) <= Constants.ARC_CHAIN_RANGE:
			candidates.append(unit)
	if candidates.is_empty():
		return
	var bounce_target: UnitState = candidates[randi() % candidates.size()]
	_arc_to(state, bounce_target, attacker.uid, arc_damage, events)


## 兼容旧调用名（攻击管线）
static func apply_arc_chain(
	state: GameState,
	victim: UnitState,
	attacker: UnitState,
	base_damage: int,
	events: Array[Dictionary]
) -> void:
	apply_arc_bounce_from_victim(state, victim, attacker, base_damage, events)


## 对单个目标施加电弧伤害；命中 6.6% 麻痹
static func _arc_to(
	state: GameState,
	target: UnitState,
	source_uid: String,
	damage: int,
	events: Array[Dictionary]
) -> void:
	if not target.alive:
		return
	var dealt := CombatRules.apply_damage(state, target, damage, source_uid, "arc")
	if dealt > 0:
		events.append({"type": "damage", "pos": target.pos, "damage": dealt, "is_crit": false})
	if target.alive and randf() < Constants.ARC_PROC_CHANCE:
		StatusRules.apply_paralyzed(state, target, 1, source_uid)
	events.append({"type": "arc", "pos": target.pos})


## ─── 冰冻（ice）辅助 ──────────────────────────────────────────────────────

## 命中冰冻效果：潮湿单位直接冻结（麻痹+缓速），普通单位仅缓速
static func apply_ice_hit_effect(state: GameState, target: UnitState, source_uid: String) -> void:
	if not target.alive:
		return
	if StatusRules.is_wet(target):
		StatusRules.apply_paralyzed(state, target, 1, source_uid)
		StatusRules.apply_slowed(state, target, 2, source_uid)
		target.remove_status(Constants.STATUS_WET)
		state.log("%s 被冻结！" % target.uid)
	else:
		StatusRules.apply_slowed(state, target, 1, source_uid)


## ─── 燃烧（fire_gem）辅助 ────────────────────────────────────────────────

## 死亡散布火焰：5x5 范围内随机选 FIRE_DEATH_FIRE_COUNT 个格子创建火焰，优先空地
static func _scatter_fire_on_death(state: GameState, owner: UnitState, out_events: Array[Dictionary]) -> void:
	var all_cells: Array[Vector2i] = []
	for cell in BoardUtils.cells_in_radius(owner.pos, Constants.FIRE_DEATH_RADIUS):
		if BoardUtils.in_bounds(state, cell):
			all_cells.append(cell)
	# 优先选空格
	var empty_cells: Array[Vector2i] = []
	var occupied_cells: Array[Vector2i] = []
	for cell in all_cells:
		if state.get_unit_at(cell) == null:
			empty_cells.append(cell)
		else:
			occupied_cells.append(cell)
	# 打乱顺序后取前 N 个
	empty_cells.shuffle()
	occupied_cells.shuffle()
	var pool: Array[Vector2i] = empty_cells
	pool.append_array(occupied_cells)
	var count := mini(Constants.FIRE_DEATH_FIRE_COUNT, pool.size())
	for i in range(count):
		TileRules.create_fire(state, pool[i])
		out_events.append({"type": "fire_burst", "pos": pool[i]})


## 死亡转移负面：将 owner 身上所有负面状态随机转给 radius 内存活的敌方单位
static func _transfer_debuffs_to_random_units(state: GameState, owner: UnitState, radius: int) -> void:
	var debuffs: Array[StatusInstance] = []
	for s in owner.statuses:
		if StatusRegistry.status_type(s.status_id) == StatusRegistry.TYPE_DEBUFF:
			debuffs.append(s)
	if debuffs.is_empty():
		return
	var candidates: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		if BoardUtils.chebyshev(owner.pos, unit.pos) <= radius:
			candidates.append(unit)
	if candidates.is_empty():
		return
	for debuff in debuffs:
		var target: UnitState = candidates[randi() % candidates.size()]
		var copy := StatusInstance.create(debuff.status_id, debuff.stacks, debuff.duration, owner.uid, debuff.payload.duplicate(true))
		copy.value = debuff.value
		StatusRegistry.apply_to_unit(target, copy)
		state.log("%s 死亡将 %s 转给 %s" % [owner.uid, StatusRegistry.display_name(debuff.status_id), target.uid])



