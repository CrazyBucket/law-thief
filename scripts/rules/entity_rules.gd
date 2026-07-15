class_name EntityRules
extends RefCounted

const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")

const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")

## 单位步入实体格
static func on_unit_entered(state: GameState, unit: UnitState, opts: Dictionary = {}) -> void:
	if unit == null or not unit.alive:
		return
	var entity := _hazard_entity_under_unit(state, unit)
	if entity == null or not entity.alive:
		return
	var forced: bool = opts.get("forced", false)
	var source_uid: String = opts.get("source_uid", "")
	match entity.entity_id:
		Constants.ENTITY_SPIKE:
			var tx := _CombatTransaction.begin_from_state(state)
			if forced:
				tx.damage_unit(
					unit,
					CombatConfig.spike_collision_damage(),
					source_uid,
					"spike_collision",
					{"damage_context": opts.get("damage_context", {})}
				)
				if unit.alive:
					StatusRules.apply_vulnerable(state, unit, 1, source_uid)
			else:
				tx.damage_unit(unit, CombatConfig.spike_damage(), "", "spike_enter")
			_unlock_armor_locks(state, unit)
			tx.finish("EntityRules.on_unit_entered")


## 单位被强制位移撞上阻挡实体（石块、油桶等）
## collision_damage = max(1, 实际位移格数)
## 有血量实体（max_hp > 0）：碰撞者与实体双方同伤
## 无血量实体（max_hp <= 0，如石柱）：仅碰撞者受伤
## 返回是否真正发生了碰撞（用于 Displacement 决定是否停止位移）
static func on_unit_collide_entity(
	state: GameState,
	unit: UnitState,
	entity: EntityState,
	source_uid: String,
	events: Array[Dictionary],
	actual_steps: int = 1,
	damage_context: Dictionary = {}
) -> bool:
	if not entity.alive:
		return false
	if not entity.blocks_movement():
		return false
	var collision_damage := maxi(1, actual_steps)
	var tx := _CombatTransaction.begin(state, events)
	tx.damage_unit(
		unit,
		collision_damage,
		source_uid,
		"entity_collision",
		{"damage_context": damage_context}
	)
	if entity.max_hp > 0:
		_damage_entity(state, entity, collision_damage, source_uid, events)
	return true


## 对油桶造成伤害，归零时触发爆炸（保留旧接口兼容）
static func damage_barrel(
	state: GameState,
	entity: EntityState,
	amount: int,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	_damage_barrel(state, entity, amount, source_uid, events)


static func damage_entity(
	state: GameState,
	entity: EntityState,
	amount: int,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	_damage_entity(state, entity, amount, source_uid, events)


## 有血量实体通用伤害派发（碰撞伤结算入口）
static func _damage_entity(
	state: GameState,
	entity: EntityState,
	amount: int,
	source_uid: String,
	events: Array[Dictionary]
) -> void:
	if not entity.alive or amount <= 0:
		return
	match entity.entity_id:
		Constants.ENTITY_BARREL:
			_damage_barrel(state, entity, amount, source_uid, events)
		_:
			entity.take_damage(amount)
			state.log("实体 %s 受到 %d 伤害，剩余 HP: %d" % [entity.uid, amount, entity.hp])
			if not entity.alive:
				events.append(_EventBuilder.entity_destroyed(entity.pos, entity.entity_id, {"uid": entity.uid}))


## 检查指定格子的油桶是否处于火焰中，是则触发爆炸（回合结算时调用）
static func tick_barrels_in_fire(
	state: GameState,
	events: Array[Dictionary] = []
) -> void:
	for entity in state.entities.values():
		if not entity.alive or entity.entity_id != Constants.ENTITY_BARREL:
			continue
		var tile := state.get_tile(entity.pos)
		if tile.has_modifier(Constants.TILE_MOD_FIRE) or tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
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


static func _hazard_entity_under_unit(state: GameState, unit: UnitState) -> EntityState:
	for cell in unit.occupied_cells():
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.has_tag("hazard"):
			return entity
	return null


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
	var explosion_radius := CombatConfig.barrel_explosion_radius()
	events.append(_EventBuilder.explode(entity.pos, explosion_radius, {"source_uid": entity.uid}))
	var hit_uids: Dictionary = {}
	var tx := _CombatTransaction.begin(state, events)
	TileRules.begin_overlay_batch(state)
	for cell in BoardUtils.cells_in_radius(entity.pos, explosion_radius):
		if not BoardUtils.in_bounds(state, cell):
			continue
		var hit_unit := state.get_unit_at(cell)
		if hit_unit != null and hit_unit.alive and not hit_uids.has(hit_unit.uid):
			hit_uids[hit_unit.uid] = true
			tx.damage_unit(hit_unit, CombatConfig.barrel_explosion_damage(), source_uid, "barrel_explosion")
		TileRules.create_fire(state, cell)
	TileRules.end_overlay_batch(state)
	events.append(_EventBuilder.entity_destroyed(entity.pos, entity.entity_id, {"uid": entity.uid}))
