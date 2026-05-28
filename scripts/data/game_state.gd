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

var version: int = 1
var run_seed: int = 0
var turn_index: int = 1
var phase: String = Constants.PHASE_PLAYER
var board_size: Vector2i = Constants.BOARD_SIZE
var player_uid: String = ""
var units: Dictionary = {}
var gems: Dictionary = {}
var tiles: Dictionary = {}
var entities: Dictionary = {}  # uid → EntityState
var held_gem_uid: String = ""
var player_moved: bool = false
var player_acted: bool = false
var combat_log: Array[String] = []
var encounter_id: String = ""
var result: String = ""


func log(message: String) -> void:
	combat_log.append(message)
	print("[COMBAT] ", message)


func get_player() -> UnitState:
	return units.get(player_uid, null)


func get_unit_at(pos: Vector2i) -> UnitState:
	for unit in units.values():
		if unit.alive and unit.pos == pos:
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


func add_entity(entity: EntityState) -> void:
	entities[entity.uid] = entity


func remove_entity(uid: String) -> void:
	entities.erase(uid)


func clone() -> GameState:
	var snapshot := GameState.new()
	snapshot.version = version
	snapshot.run_seed = run_seed
	snapshot.turn_index = turn_index
	snapshot.phase = phase
	snapshot.board_size = board_size
	snapshot.player_uid = player_uid
	snapshot.held_gem_uid = held_gem_uid
	snapshot.player_moved = player_moved
	snapshot.player_acted = player_acted
	snapshot.combat_log = combat_log.duplicate(true)
	snapshot.encounter_id = encounter_id
	snapshot.result = result
	for uid in units.keys():
		snapshot.units[uid] = units[uid].clone()
	for uid in gems.keys():
		snapshot.gems[uid] = gems[uid].clone()
	for key in tiles.keys():
		snapshot.tiles[key] = tiles[key].clone()
	for uid in entities.keys():
		snapshot.entities[uid] = entities[uid].clone()
	return snapshot
