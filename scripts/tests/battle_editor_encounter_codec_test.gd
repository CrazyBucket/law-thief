extends SceneTree

const Codec = preload("res://scripts/debug/battle_editor_encounter_codec.gd")


func _initialize() -> void:
	var parsed := Codec.parse_import({
		"player_spawn": [1, 2],
		"enemies": [{"pos": [3, 4]}],
		"entities": [{"pos": [5, 6]}],
		"tiles": [{"pos": [7, 8]}],
	})
	assert(parsed.player_spawn == Vector2i(1, 2), "player spawn should decode to a board position")
	assert(parsed.enemies[0].pos == Vector2i(3, 4), "enemy positions should decode")
	assert(parsed.entities[0].pos == Vector2i(5, 6), "entity positions should decode")
	assert(parsed.tiles[0].pos == Vector2i(7, 8), "tile positions should decode")
	print("BATTLE_EDITOR_ENCOUNTER_CODEC_TEST_PASS")
	quit()
