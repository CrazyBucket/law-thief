extends SceneTree

const Codec = preload("res://scripts/debug/battle_editor_encounter_codec.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw := {
		"player_spawn": [1, 2],
		"enemies": [{"pos": [-3, 4]}],
		"entities": [{"pos": [5, 6]}],
		"tiles": [{"pos": [7, 8]}, {"pos": [9]}],
	}
	var parsed := Codec.parse_import(raw)
	_check(parsed.player_spawn == Vector2i(1, 2), "player spawn should decode to a board position")
	_check(parsed.enemies[0].pos == Vector2i(-3, 4), "negative enemy positions should decode exactly")
	_check(parsed.entities[0].pos == Vector2i(5, 6), "entity positions should decode")
	_check(parsed.tiles[0].pos == Vector2i(7, 8), "tile positions should decode")
	_check(parsed.tiles[1].pos == [9], "malformed short positions should remain undecoded for validation")
	_check(raw.player_spawn == [1, 2] and raw.enemies[0].pos == [-3, 4], "import parsing must not mutate caller data")

	var state := _codec_state()
	var encoded := Codec.export_from_state(state)
	_check(encoded.get("schema_version", 0) == 2, "exports should declare the current schema")
	_check(encoded.get("player_spawn") is Array, "exported positions should remain JSON-safe arrays")
	var round_trip := Codec.parse_import(encoded)
	_check(round_trip.get("player_spawn") == state.get_player().pos, "player position should survive export/import")
	for enemy in round_trip.get("enemies", []):
		_check(enemy.pos is Vector2i, "every exported enemy position should decode")
	for entity in round_trip.get("entities", []):
		_check(entity.pos is Vector2i, "every exported entity position should decode")
	for tile in round_trip.get("tiles", []):
		_check(tile.pos is Vector2i, "every exported tile position should decode")

	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_EDITOR_ENCOUNTER_CODEC_TEST_PASS")
	quit(0)


func _codec_state() -> GameState:
	var state := GameState.new()
	state.run_seed = 77
	var player := UnitState.new()
	player.uid = "codec_player"
	player.unit_def_id = "unit_player"
	player.team = Constants.TEAM_PLAYER
	player.pos = Vector2i(1, 2)
	player.alive = true
	state.player_uid = player.uid
	state.register_unit(player)
	var enemy := UnitState.new()
	enemy.uid = "codec_enemy"
	enemy.unit_def_id = "unit_patrol_guard"
	enemy.team = Constants.TEAM_ENEMY
	enemy.pos = Vector2i(-3, 4)
	enemy.alive = true
	state.register_unit(enemy)
	state.add_entity(EntityState.create("codec_barrel", Constants.ENTITY_BARREL, Vector2i(5, 6)))
	return state


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
