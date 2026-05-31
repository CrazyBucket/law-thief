class_name EntityRules
extends RefCounted

## 单位步入实体格
static func on_unit_entered(state: GameState, unit: UnitState, opts: Dictionary = {}) -> void:
	var entity := state.get_entity_at(unit.pos)
	if entity == null or not entity.alive:
		return
	var forced: bool = opts.get("forced", false)
	var source_uid: String = opts.get("source_uid", "")
	match entity.entity_id:
		Constants.ENTITY_SPIKE:
			if forced:
				StatusRules.apply_vulnerable(state, unit, 1, source_uid)
				CombatRules.apply_damage(state, unit, Constants.SPIKE_COLLISION_DAMAGE, source_uid, "spike_collision")
			else:
				CombatRules.apply_damage(state, unit, Constants.SPIKE_DAMAGE, "", "spike_enter")
			_unlock_armor_locks(state, unit)


## 单位被强制位移撞上阻挡实体（石块、油桶）
## 返回是否真正发生了碰撞（用于 Displacement 决定是否停止位移）
static func on_unit_collide_entity(
	state: GameState,
	unit: UnitState,
	entity: EntityState,
	source_uid: String,
	events: Array[Dictionary]
) -> bool:
	if not entity.alive:
		return false
	match entity.entity_id:
		Constants.ENTITY_ROCK, Constants.ENTITY_PROP:
			CombatRules.apply_damage(state, unit, Constants.KNOCKBACK_COLLISION_DAMAGE, source_uid, "rock_collision")
			if events != null:
				events.append({"type": "damage", "pos": unit.pos, "damage": Constants.KNOCKBACK_COLLISION_DAMAGE, "is_crit": false})
			return true
		Constants.ENTITY_BARREL:
			_damage_barrel(state, entity, Constants.KNOCKBACK_COLLISION_DAMAGE, source_uid, events)
			CombatRules.apply_damage(state, unit, Constants.KNOCKBACK_COLLISION_DAMAGE, source_uid, "barrel_collision")
			return true
	return false


## 对油桶造成伤害，归零时触发爆炸
static func damage_barrel(
	state: GameState,
	entity: EntityState,
	amount: int,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	_damage_barrel(state, entity, amount, source_uid, events)


## 检查指定格子的油桶是否处于火焰中，是则触发爆炸（回合结算时调用）
static func tick_barrels_in_fire(state: GameState) -> void:
	for entity in state.entities.values():
		if not entity.alive or entity.entity_id != Constants.ENTITY_BARREL:
			continue
		var tile := state.get_tile(entity.pos)
		if tile.has_modifier(Constants.TILE_MOD_FIRE):
			var events: Array[Dictionary] = []
			_explode_barrel(state, entity, "", events)


static func _damage_barrel(
	state: GameState,
	entity: EntityState,
	amount: int,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	if not entity.alive or amount <= 0:
		return
	entity.take_damage(amount)
	state.log("油桶 %s 受到 %d 伤害，剩余 HP: %d" % [entity.uid, amount, entity.hp])
	if not entity.alive:
		_explode_barrel(state, entity, source_uid, events)


static func _unlock_armor_locks(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.locked and slot.lock_type == Constants.LOCK_ARMOR:
			StatusRules.apply_exposed(state, unit, slot, state.turn_index)


static func _explode_barrel(
	state: GameState,
	entity: EntityState,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	if not entity.alive and entity.hp > 0:
		return
	entity.alive = false
	state.log("油桶 %s 爆炸！" % entity.uid)
	events.append({"type": "explode", "pos": entity.pos, "radius": Constants.BARREL_EXPLOSION_RADIUS})
	var hit_uids: Dictionary = {}
	for cell in BoardUtils.cells_in_radius(entity.pos, Constants.BARREL_EXPLOSION_RADIUS):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_unit := state.get_unit_at(cell)
		if hit_unit != null and hit_unit.alive and not hit_uids.has(hit_unit.uid):
			hit_uids[hit_unit.uid] = true
			var dealt := CombatRules.apply_damage(state, hit_unit, Constants.BARREL_EXPLOSION_DAMAGE, source_uid, "barrel_explosion")
			if dealt > 0:
				events.append({"type": "damage", "pos": hit_unit.pos, "damage": dealt, "is_crit": false})
		TileRules.create_fire(state, cell)
