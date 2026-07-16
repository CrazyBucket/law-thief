class_name GameState
extends RefCounted

# ─── 战斗生命周期信号 ─────────────────────────────────────────────────────────
signal on_battle_start
signal on_battle_end(result: String)
signal on_turn_start(turn_index: int)
signal on_turn_end(turn_index: int)

# ─── 攻击流程信号 ─────────────────────────────────────────────────────────────
signal on_attack_prepare(attacker_uid: String, target_uid: String, tags: Array)
signal on_attack_hit(attacker_uid: String, target_uid: String, damage: int)

# ─── 单位状态信号 ─────────────────────────────────────────────────────────────
signal on_damage_taken(unit_uid: String, amount: int, reason: String)
signal on_unit_die(unit_uid: String, killer_uid: String, reason: String)
signal on_unit_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i)
signal on_forced_displacement(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i, source_uid: String)

var version: int = 1
## Runtime-only monotonic mutation version used by read-model caches.
var revision: int = 0
var run_seed: int = 0
var turn_index: int = 1
var phase: String = Constants.PHASE_PLAYER
var board_size: Vector2i = Constants.BOARD_SIZE
var player_uid: String = ""
var units: Dictionary = {}
var gems: Dictionary = {}
## gem_uid -> {"gem_uid": String, "pos": Vector2i}
var dropped_gems: Dictionary = {}
var tiles: Dictionary = {}
var entities: Dictionary = {}  # uid → EntityState
var held_gem_uid: String = ""
var player_moved: bool = false
var player_acted: bool = false
## 当前回合仍待操控的友方单位队列（首个已成为 player_uid，后续依次激活）
var controllable_queue: Array[String] = []
var combat_log: Array[String] = []
## Runtime-only mutation evidence captured by StateSnapshot for debugging/replay.
var transaction_trace: Array[Dictionary] = []
## Runtime-only authoring diagnostics; never used to decide combat behavior.
var content_warnings: Array[Dictionary] = []
var encounter_id: String = ""
var result: String = ""
var overload_pending: bool = false
var overload_pending_turn: int = 0
var overload_last_action: String = ""
var overload_last_insert_turn: int = 0
var overload_active_mutations: Array[String] = []
var overload_echo_gems: Dictionary = {}
## 单场战斗临时 flags，战斗结束即丢弃，不参与 clone/序列化
## key: String（如 "first_hit_absorbed"）→ Variant
var battle_temp_flags: Dictionary = {}
## 战斗事件收集绑定点；bind 期间蓝槽 reactive 伤害效果写入此数组
var _combat_event_sink: Variant = null
# O(1) 占格索引：tile_key → UnitState；单位移动/生成/死亡时通过封装方法同步
var _cell_occupancy: Dictionary = {}


func log(message: String) -> void:
	combat_log.append(message)
	print("[COMBAT] ", message)


func bump_revision() -> void:
	revision += 1


func record_transaction(operation: String, details: Dictionary = {}) -> void:
	var entry := details.duplicate(true)
	entry["sequence"] = transaction_trace.size() + 1
	entry["operation"] = operation
	entry["revision"] = revision
	transaction_trace.append(entry)


func bind_combat_events(sink: Array) -> void:
	_combat_event_sink = sink


func unbind_combat_events() -> void:
	_combat_event_sink = null


func get_combat_event_sink() -> Array:
	if _combat_event_sink is Array:
		return _combat_event_sink
	return []


func has_combat_event_sink() -> bool:
	return _combat_event_sink is Array


func get_player() -> UnitState:
	return units.get(player_uid, null)


# ─── 友方可操控队列 ───────────────────────────────────────────────────────────

## 把一批单位按顺序推入队列，并立即激活第一个（设为 player_uid）
## 若 activate_first 为 false 则仅入队，不切换 player_uid
func push_controllable_batch(uids: Array, activate_first: bool = true) -> void:
	controllable_queue.clear()
	if uids.is_empty():
		return
	var start := 1 if activate_first else 0
	for i in range(start, uids.size()):
		controllable_queue.append(uids[i])
	if activate_first:
		player_uid = uids[0]
		player_moved = false
		player_acted = false


## 弹出队列头部的下一个存活单位并激活；返回激活的 uid，失败返回空串
func activate_next_controllable() -> String:
	while not controllable_queue.is_empty():
		var next_uid: String = controllable_queue[0]
		var next_unit: UnitState = units.get(next_uid, null)
		if next_unit != null and next_unit.alive:
			controllable_queue.pop_front()
			player_uid = next_uid
			player_moved = false
			player_acted = false
			return next_uid
		controllable_queue.pop_front()
	return ""


## 清除队列中已死亡的单位（不激活）
func purge_dead_controllable() -> void:
	controllable_queue = controllable_queue.filter(
		func(uid: String) -> bool:
			var u: UnitState = units.get(uid, null)
			return u != null and u.alive
	)


## 收集同一原体下的存活玩家死亡分身；蓝槽临时分身不进入接班/合并流程。
func get_alive_split_clones(origin_uid: String) -> Array[UnitState]:
	var clones: Array[UnitState] = []
	for unit in units.values():
		if not unit.alive or unit.team != Constants.TEAM_PLAYER:
			continue
		if not unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			continue
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE):
			continue
		if unit.split_origin_uid != origin_uid:
			continue
		clones.append(unit)
	clones.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	return clones


## 玩家回合开始时重建分身操控队列（每回合依次操控所有存活分身）
func bootstrap_split_controllable_turn() -> void:
	var player := get_player()
	if player == null or not player.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return
	var clones := get_alive_split_clones(player.split_origin_uid)
	if clones.is_empty():
		return
	if clones.size() == 1:
		player_uid = clones[0].uid
		controllable_queue.clear()
		player_moved = false
		player_acted = false
		return
	var uids: Array = clones.map(func(c: UnitState) -> String: return c.uid)
	push_controllable_batch(uids, true)


# ─── 占格索引维护 ─────────────────────────────────────────────────────────────

## 重建占格索引（初始化或批量操作后调用）
func rebuild_occupancy() -> void:
	_cell_occupancy.clear()
	for unit in units.values():
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			_cell_occupancy[tile_key(cell)] = unit


func _remove_unit_from_occupancy(unit: UnitState) -> void:
	for cell in unit.occupied_cells():
		var key := tile_key(cell)
		if _cell_occupancy.get(key) == unit:
			_cell_occupancy.erase(key)


func _add_unit_to_occupancy(unit: UnitState) -> void:
	for cell in unit.occupied_cells():
		_cell_occupancy[tile_key(cell)] = unit


## 封装单位移动，同步占格索引
func move_unit(unit: UnitState, new_pos: Vector2i) -> void:
	_remove_unit_from_occupancy(unit)
	unit.pos = new_pos
	_add_unit_to_occupancy(unit)
	bump_revision()


## 注册新单位到占格索引（单位生成时调用，替代直接写 units[uid] = unit）
func register_unit(unit: UnitState) -> void:
	units[unit.uid] = unit
	_add_unit_to_occupancy(unit)
	bump_revision()


## 标记单位死亡并撤销占格索引
func kill_unit(unit: UnitState) -> void:
	_remove_unit_from_occupancy(unit)
	unit.alive = false
	bump_revision()


## 从战场移除单位（编辑器删除等，非战斗击杀）
func unregister_unit(unit: UnitState) -> void:
	_remove_unit_from_occupancy(unit)
	units.erase(unit.uid)
	bump_revision()


# ─── 查询接口 ─────────────────────────────────────────────────────────────────

func get_unit_at(pos: Vector2i) -> UnitState:
	if not _cell_occupancy.is_empty():
		return _cell_occupancy.get(tile_key(pos), null)
	# 索引未建立时（clone 快照）回退到遍历
	for unit in units.values():
		if not unit.alive:
			continue
		for cell in unit.occupied_cells():
			if cell == pos:
				return unit
	return null


func get_alive_enemies() -> Array:
	var enemies: Array = []
	for unit in units.values():
		if unit.alive and unit.team == Constants.TEAM_ENEMY:
			enemies.append(unit)
	return enemies


func get_tile(pos: Vector2i) -> TileState:
	var key := "%d,%d" % [pos.x, pos.y]
	if tiles.has(key):
		return tiles[key]
	var tile := TileState.create(pos)
	tiles[key] = tile
	return tile


func tile_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func get_entity_at(pos: Vector2i) -> EntityState:
	for entity in entities.values():
		if entity.alive and entity.pos == pos:
			return entity
	return null


func get_dropped_gem_uids_at(pos: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for raw_uid in dropped_gems.keys():
		var uid := str(raw_uid)
		var drop: Variant = dropped_gems.get(uid, {})
		if drop is Dictionary and (drop as Dictionary).get("pos", Vector2i(-1, -1)) == pos:
			result.append(uid)
	result.sort()
	return result


func add_entity(entity: EntityState) -> void:
	entities[entity.uid] = entity
	bump_revision()


func remove_entity(uid: String) -> void:
	if entities.erase(uid):
		bump_revision()


func clone() -> GameState:
	var snapshot := GameState.new()
	snapshot.version = version
	snapshot.revision = revision
	snapshot.run_seed = run_seed
	snapshot.turn_index = turn_index
	snapshot.phase = phase
	snapshot.board_size = board_size
	snapshot.player_uid = player_uid
	snapshot.held_gem_uid = held_gem_uid
	snapshot.player_moved = player_moved
	snapshot.player_acted = player_acted
	snapshot.controllable_queue = controllable_queue.duplicate()
	snapshot.combat_log = combat_log.duplicate(true)
	snapshot.transaction_trace = transaction_trace.duplicate(true)
	snapshot.content_warnings = content_warnings.duplicate(true)
	snapshot.encounter_id = encounter_id
	snapshot.result = result
	snapshot.overload_pending = overload_pending
	snapshot.overload_pending_turn = overload_pending_turn
	snapshot.overload_last_action = overload_last_action
	snapshot.overload_last_insert_turn = overload_last_insert_turn
	snapshot.overload_active_mutations = overload_active_mutations.duplicate()
	snapshot.overload_echo_gems = overload_echo_gems.duplicate(true)
	for uid in units.keys():
		snapshot.units[uid] = units[uid].clone()
	for uid in gems.keys():
		snapshot.gems[uid] = gems[uid].clone()
	snapshot.dropped_gems = dropped_gems.duplicate(true)
	for key in tiles.keys():
		snapshot.tiles[key] = tiles[key].clone()
	for uid in entities.keys():
		snapshot.entities[uid] = entities[uid].clone()
	snapshot.rebuild_occupancy()
	return snapshot
