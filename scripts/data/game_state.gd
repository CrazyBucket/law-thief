class_name GameState
extends RefCounted

var version: int = 1
var run_seed: int = 0
var turn_index: int = 1
var phase: String = Constants.PHASE_PLAYER
var board_size: Vector2i = Constants.BOARD_SIZE
var player_uid: String = ""
var units: Dictionary = {}
var gems: Dictionary = {}
var tiles: Dictionary = {}
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
