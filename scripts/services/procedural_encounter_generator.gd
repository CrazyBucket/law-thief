class_name ProceduralEncounterGenerator
extends RefCounted

const EncounterCodec = preload("res://scripts/debug/battle_editor_encounter_codec.gd")

const ENCOUNTER_ID := "procedural_normal"
const GENERATOR_VERSION := 3
const BOARD_SIZE := Vector2i(8, 8)
const MAX_ATTEMPTS := 24

const _DIRS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]
const _LAYOUTS := ["open", "gate", "staggered", "arena"]
const _THEMES := ["flooded", "frozen", "overgrown", "powder_yard", "quarry"]
const _ENEMY_POOL := [
	{"def_id": "unit_bomb_rat", "cost": 1, "weight": 5, "min_chapter": 1, "footprint": Vector2i.ONE, "max_count": 3},
	{"def_id": "unit_patrol_guard", "cost": 2, "weight": 4, "min_chapter": 1, "footprint": Vector2i.ONE, "max_count": 2},
	{"def_id": "unit_stone_bow_guard", "cost": 2, "weight": 3, "min_chapter": 1, "footprint": Vector2i.ONE, "max_count": 2},
	{"def_id": "unit_fission_slime", "cost": 3, "weight": 2, "min_chapter": 2, "footprint": Vector2i(2, 2), "max_count": 1},
	{"def_id": "unit_law_worm", "cost": 1, "weight": 1, "min_chapter": 2, "footprint": Vector2i.ONE, "max_count": 1, "allow_empty_gems": true, "requires": "unit_broodmother"},
	{"def_id": "unit_broodmother", "cost": 3, "weight": 4, "min_chapter": 2, "footprint": Vector2i.ONE, "max_count": 1, "allow_empty_gems": true},
]


static func generate(seed_value: int, chapter: int, room_id: String = "") -> Dictionary:
	var normalized_chapter := clampi(chapter, 1, 3)
	for attempt in range(MAX_ATTEMPTS):
		var rng := RandomNumberGenerator.new()
		rng.seed = _attempt_seed(seed_value, room_id, attempt)
		var encounter := _generate_candidate(rng, seed_value, normalized_chapter, room_id, attempt)
		if validate(encounter).is_empty():
			return encounter
	return _fallback_encounter(seed_value, normalized_chapter, room_id)


static func validate(encounter: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var player_pos := _pos(encounter.get("player_spawn", Vector2i(-1, -1)))
	if not _in_bounds(player_pos):
		errors.append("player spawn is out of bounds")

	var generation: Variant = encounter.get("generation", {})
	if not generation is Dictionary or int((generation as Dictionary).get("version", 0)) != GENERATOR_VERSION:
		errors.append("generation metadata is missing or has the wrong version")

	var entity_cells: Dictionary = {}
	var blocker_cells: Dictionary = {}
	for raw_entity in encounter.get("entities", []):
		if not raw_entity is Dictionary:
			errors.append("entity entry is not an object")
			continue
		var entity: Dictionary = raw_entity
		var pos := _pos(entity.get("pos", Vector2i(-1, -1)))
		if not _in_bounds(pos):
			errors.append("entity is out of bounds: %s" % pos)
			continue
		var key := _key(pos)
		if entity_cells.has(key):
			errors.append("entities overlap at %s" % pos)
		entity_cells[key] = true
		if _entity_blocks(str(entity.get("entity_id", ""))):
			blocker_cells[key] = true

	var enemies: Array = encounter.get("enemies", [])
	if enemies.size() < 3 or enemies.size() > 5:
		errors.append("normal encounters must contain 3-5 enemies")
	var unit_cells: Dictionary = {_key(player_pos): true}
	var enemy_footprints: Array[Array] = []
	var unique_defs: Dictionary = {}
	var threat := 0
	for raw_enemy in enemies:
		if not raw_enemy is Dictionary:
			errors.append("enemy entry is not an object")
			continue
		var enemy: Dictionary = raw_enemy
		var def_id := str(enemy.get("def_id", ""))
		var profile := _enemy_profile(def_id)
		if profile.is_empty():
			errors.append("enemy is not in the procedural pool: %s" % def_id)
			continue
		unique_defs[def_id] = true
		threat += int(profile.get("cost", 0))
		var anchor := _pos(enemy.get("pos", Vector2i(-1, -1)))
		var footprint: Vector2i = profile.get("footprint", Vector2i.ONE)
		var occupied := _footprint_cells(anchor, footprint)
		enemy_footprints.append(occupied)
		if not _footprint_in_bounds(anchor, footprint):
			errors.append("enemy footprint is out of bounds: %s at %s" % [def_id, anchor])
			continue
		if _manhattan(player_pos, anchor) < 4:
			errors.append("enemy spawns too close to the player: %s" % def_id)
		if bool(profile.get("allow_empty_gems", false)) and not bool(enemy.get("allow_empty_gems", false)):
			errors.append("enemy must explicitly allow its designed empty slots: %s" % def_id)
		for cell in occupied:
			var key := _key(cell)
			if entity_cells.has(key) or unit_cells.has(key):
				errors.append("enemy overlaps another occupant at %s" % cell)
			unit_cells[key] = true

	var chapter := clampi(int((generation as Dictionary).get("chapter", 1)) if generation is Dictionary else 1, 1, 3)
	var budget := _threat_budget(chapter)
	if threat > budget:
		errors.append("enemy threat %d exceeds budget %d" % [threat, budget])
	if unique_defs.size() < 2:
		errors.append("normal encounters must combine at least two enemy types")
	if unique_defs.has("unit_law_worm") and not unique_defs.has("unit_broodmother"):
		errors.append("law worms may only enter a generated encounter with a broodmother")

	var tile_cells: Dictionary = {}
	for raw_tile in encounter.get("tiles", []):
		if not raw_tile is Dictionary:
			errors.append("tile entry is not an object")
			continue
		var tile_pos := _pos((raw_tile as Dictionary).get("pos", Vector2i(-1, -1)))
		if not _in_bounds(tile_pos):
			errors.append("tile is out of bounds: %s" % tile_pos)
			continue
		var tile_key := _key(tile_pos)
		if tile_cells.has(tile_key):
			errors.append("tiles overlap at %s" % tile_pos)
		tile_cells[tile_key] = true

	if _in_bounds(player_pos):
		var reachable := _reachable_cells(player_pos, blocker_cells)
		var open_neighbors := 0
		for dir in _DIRS:
			if reachable.has(_key(player_pos + dir)):
				open_neighbors += 1
		if open_neighbors < 2:
			errors.append("player spawn has fewer than two exits")
		for footprint in enemy_footprints:
			if not _has_reachable_approach(footprint, reachable):
				errors.append("an enemy has no reachable approach cell")
	return errors


static func freeze_initial_blueprint(state: GameState, encounter: Dictionary) -> void:
	state.generated_encounter_blueprint = EncounterCodec.export_from_state(state)
	state.generated_encounter_blueprint["generation"] = encounter.get("generation", {}).duplicate(true)


static func _generate_candidate(
	rng: RandomNumberGenerator,
	seed_value: int,
	chapter: int,
	room_id: String,
	attempt: int
) -> Dictionary:
	var player_pos := Vector2i(rng.randi_range(0, 1), rng.randi_range(2, 5))
	var layout := str(_LAYOUTS[rng.randi_range(0, _LAYOUTS.size() - 1)])
	var theme := str(_THEMES[rng.randi_range(0, _THEMES.size() - 1)])
	var entities: Array[Dictionary] = []
	var entity_cells: Dictionary = {}
	var blocker_cells: Dictionary = {}
	_apply_layout(rng, layout, player_pos, entities, entity_cells, blocker_cells)

	var tiles: Array[Dictionary] = []
	var tile_cells: Dictionary = {}
	_apply_theme(rng, theme, player_pos, tiles, tile_cells, entities, entity_cells, blocker_cells)

	var enemies := _generate_enemies(rng, chapter, player_pos, entity_cells)
	var threat := 0
	for enemy in enemies:
		threat += int(_enemy_profile(str(enemy.get("def_id", ""))).get("cost", 0))
	return {
		"catalog_visible": false,
		"player_spawn": player_pos,
		"floor_seed": seed_value,
		"enemies": enemies,
		"tiles": tiles,
		"entities": entities,
		"generation": {
			"version": GENERATOR_VERSION,
			"seed": seed_value,
			"room_id": room_id,
			"chapter": chapter,
			"layout": layout,
			"theme": theme,
			"attempt": attempt,
			"threat": threat,
			"threat_budget": _threat_budget(chapter),
			"fallback": false,
		},
	}


static func _apply_layout(
	rng: RandomNumberGenerator,
	layout: String,
	player_pos: Vector2i,
	entities: Array[Dictionary],
	entity_cells: Dictionary,
	blocker_cells: Dictionary
) -> void:
	match layout:
		"gate":
			var first_gate := rng.randi_range(1, 3)
			var second_gate := rng.randi_range(5, 6)
			for y in range(BOARD_SIZE.y):
				if y != first_gate and y != second_gate:
					_add_entity(Constants.ENTITY_ROCK, Vector2i(3, y), player_pos, entities, entity_cells, blocker_cells)
		"staggered":
			var shift := rng.randi_range(0, 1)
			for pos in [Vector2i(2, 0 + shift), Vector2i(2, 1 + shift), Vector2i(4, 4 + shift), Vector2i(4, 5 + shift)]:
				_add_entity(Constants.ENTITY_PROP, pos, player_pos, entities, entity_cells, blocker_cells)
		"arena":
			for pos in [Vector2i(2, 1), Vector2i(2, 6), Vector2i(4, 2), Vector2i(4, 5)]:
				_add_entity(Constants.ENTITY_ROCK, pos, player_pos, entities, entity_cells, blocker_cells)
		_:
			_place_random_entities(rng, Constants.ENTITY_PROP, 3, player_pos, entities, entity_cells, blocker_cells, 2, 5)


static func _apply_theme(
	rng: RandomNumberGenerator,
	theme: String,
	player_pos: Vector2i,
	tiles: Array[Dictionary],
	tile_cells: Dictionary,
	entities: Array[Dictionary],
	entity_cells: Dictionary,
	blocker_cells: Dictionary
) -> void:
	match theme:
		"flooded":
			_scatter_tiles(rng, Constants.TILE_WATER, 10, player_pos, tiles, tile_cells)
		"frozen":
			_scatter_tiles(rng, Constants.TILE_ICE, 10, player_pos, tiles, tile_cells)
		"overgrown":
			_scatter_tiles(rng, Constants.TILE_GRASS, 7, player_pos, tiles, tile_cells)
			_scatter_tiles(rng, Constants.TILE_BUSH, 3, player_pos, tiles, tile_cells)
			_place_random_entities(rng, Constants.ENTITY_SPIKE, 2, player_pos, entities, entity_cells, blocker_cells, 2, 6)
		"powder_yard":
			_scatter_tiles(rng, Constants.TILE_GRASS, 6, player_pos, tiles, tile_cells)
			_place_random_entities(rng, Constants.ENTITY_BARREL, 2, player_pos, entities, entity_cells, blocker_cells, 2, 5)
		"quarry":
			_place_random_entities(rng, Constants.ENTITY_ROCK, 2, player_pos, entities, entity_cells, blocker_cells, 2, 5)


static func _generate_enemies(
	rng: RandomNumberGenerator,
	chapter: int,
	player_pos: Vector2i,
	entity_cells: Dictionary
) -> Array[Dictionary]:
	var target_count := 3 + rng.randi_range(0, 1)
	if chapter >= 3 and rng.randf() < 0.45:
		target_count += 1
	var remaining_budget := _threat_budget(chapter)
	var counts: Dictionary = {}
	var used_cells: Dictionary = {_key(player_pos): true}
	var enemies: Array[Dictionary] = []
	for slot_index in range(target_count):
		var remaining_slots := target_count - slot_index - 1
		var eligible: Array[Dictionary] = []
		for raw_profile in _ENEMY_POOL:
			var profile: Dictionary = raw_profile
			var def_id := str(profile.get("def_id", ""))
			if chapter < int(profile.get("min_chapter", 1)):
				continue
			if int(counts.get(def_id, 0)) >= int(profile.get("max_count", 99)):
				continue
			var required_def := str(profile.get("requires", ""))
			if not required_def.is_empty() and int(counts.get(required_def, 0)) <= 0:
				continue
			if int(profile.get("cost", 1)) > remaining_budget - remaining_slots:
				continue
			eligible.append(profile)
		if eligible.is_empty():
			return []
		var profile := _weighted_profile(rng, eligible)
		var position := _find_enemy_position(rng, player_pos, profile.get("footprint", Vector2i.ONE), entity_cells, used_cells)
		if position.x < 0:
			return []
		var def_id := str(profile.get("def_id", ""))
		var enemy_entry := {"def_id": def_id, "pos": position}
		if bool(profile.get("allow_empty_gems", false)):
			enemy_entry["allow_empty_gems"] = true
		enemies.append(enemy_entry)
		counts[def_id] = int(counts.get(def_id, 0)) + 1
		remaining_budget -= int(profile.get("cost", 1))
		for cell in _footprint_cells(position, profile.get("footprint", Vector2i.ONE)):
			used_cells[_key(cell)] = true
	return enemies


static func _find_enemy_position(
	rng: RandomNumberGenerator,
	player_pos: Vector2i,
	footprint: Vector2i,
	entity_cells: Dictionary,
	used_cells: Dictionary
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(BOARD_SIZE.y - footprint.y + 1):
		for x in range(4, BOARD_SIZE.x - footprint.x + 1):
			candidates.append(Vector2i(x, y))
	_shuffle(rng, candidates)
	for anchor in candidates:
		if _manhattan(player_pos, anchor) < 4:
			continue
		var available := true
		for cell in _footprint_cells(anchor, footprint):
			if entity_cells.has(_key(cell)) or used_cells.has(_key(cell)):
				available = false
				break
		if available:
			return anchor
	return Vector2i(-1, -1)


static func _place_random_entities(
	rng: RandomNumberGenerator,
	entity_id: String,
	count: int,
	player_pos: Vector2i,
	entities: Array[Dictionary],
	entity_cells: Dictionary,
	blocker_cells: Dictionary,
	min_x: int,
	max_x: int
) -> void:
	var candidates: Array[Vector2i] = []
	for y in range(BOARD_SIZE.y):
		for x in range(min_x, max_x + 1):
			candidates.append(Vector2i(x, y))
	_shuffle(rng, candidates)
	for pos in candidates:
		if count <= 0:
			return
		if _add_entity(entity_id, pos, player_pos, entities, entity_cells, blocker_cells):
			count -= 1


static func _add_entity(
	entity_id: String,
	pos: Vector2i,
	player_pos: Vector2i,
	entities: Array[Dictionary],
	entity_cells: Dictionary,
	blocker_cells: Dictionary
) -> bool:
	if not _in_bounds(pos) or _manhattan(player_pos, pos) <= 2 or entity_cells.has(_key(pos)):
		return false
	entities.append({"entity_id": entity_id, "pos": pos})
	entity_cells[_key(pos)] = true
	if _entity_blocks(entity_id):
		blocker_cells[_key(pos)] = true
	return true


static func _scatter_tiles(
	rng: RandomNumberGenerator,
	tile_id: String,
	count: int,
	player_pos: Vector2i,
	tiles: Array[Dictionary],
	tile_cells: Dictionary
) -> void:
	var candidates: Array[Vector2i] = []
	for y in range(BOARD_SIZE.y):
		for x in range(1, 7):
			candidates.append(Vector2i(x, y))
	_shuffle(rng, candidates)
	for pos in candidates:
		if count <= 0:
			return
		if _manhattan(player_pos, pos) <= 1 or tile_cells.has(_key(pos)):
			continue
		tiles.append({"pos": pos, "tile_id": tile_id})
		tile_cells[_key(pos)] = true
		count -= 1


static func _weighted_profile(rng: RandomNumberGenerator, profiles: Array[Dictionary]) -> Dictionary:
	var total_weight := 0
	for profile in profiles:
		total_weight += int(profile.get("weight", 1))
	var roll := rng.randi_range(1, maxi(1, total_weight))
	for profile in profiles:
		roll -= int(profile.get("weight", 1))
		if roll <= 0:
			return profile
	return profiles[-1]


static func _fallback_encounter(seed_value: int, chapter: int, room_id: String) -> Dictionary:
	return {
		"catalog_visible": false,
		"player_spawn": Vector2i(1, 4),
		"floor_seed": seed_value,
		"enemies": [
			{"def_id": "unit_bomb_rat", "pos": Vector2i(5, 1)},
			{"def_id": "unit_patrol_guard", "pos": Vector2i(6, 4)},
			{"def_id": "unit_stone_bow_guard", "pos": Vector2i(5, 6)},
		],
		"tiles": [
			{"pos": Vector2i(2, 2), "tile_id": Constants.TILE_WATER},
			{"pos": Vector2i(2, 3), "tile_id": Constants.TILE_WATER},
			{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_WATER},
		],
		"entities": [
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 0)},
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 1)},
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 3)},
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 4)},
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 6)},
			{"entity_id": Constants.ENTITY_ROCK, "pos": Vector2i(3, 7)},
		],
		"generation": {
			"version": GENERATOR_VERSION,
			"seed": seed_value,
			"room_id": room_id,
			"chapter": chapter,
			"layout": "gate",
			"theme": "flooded",
			"attempt": MAX_ATTEMPTS,
			"threat": 5,
			"threat_budget": _threat_budget(chapter),
			"fallback": true,
		},
	}


static func _reachable_cells(start: Vector2i, blockers: Dictionary) -> Dictionary:
	var reached: Dictionary = {_key(start): true}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for dir in _DIRS:
			var next := current + dir
			var next_key := _key(next)
			if not _in_bounds(next) or blockers.has(next_key) or reached.has(next_key):
				continue
			reached[next_key] = true
			queue.append(next)
	return reached


static func _has_reachable_approach(footprint: Array, reachable: Dictionary) -> bool:
	var footprint_keys: Dictionary = {}
	for cell_variant in footprint:
		footprint_keys[_key(cell_variant as Vector2i)] = true
	for cell_variant in footprint:
		var cell: Vector2i = cell_variant
		for dir in _DIRS:
			var approach_key := _key(cell + dir)
			if not footprint_keys.has(approach_key) and reachable.has(approach_key):
				return true
	return false


static func _enemy_profile(def_id: String) -> Dictionary:
	for raw_profile in _ENEMY_POOL:
		var profile: Dictionary = raw_profile
		if str(profile.get("def_id", "")) == def_id:
			return profile
	return {}


static func _threat_budget(chapter: int) -> int:
	return 5 + clampi(chapter, 1, 3)


static func _entity_blocks(entity_id: String) -> bool:
	return entity_id in [Constants.ENTITY_ROCK, Constants.ENTITY_PROP, Constants.ENTITY_BARREL]


static func _footprint_cells(anchor: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(footprint.y):
		for x in range(footprint.x):
			cells.append(anchor + Vector2i(x, y))
	return cells


static func _footprint_in_bounds(anchor: Vector2i, footprint: Vector2i) -> bool:
	return _in_bounds(anchor) and _in_bounds(anchor + footprint - Vector2i.ONE)


static func _shuffle(rng: RandomNumberGenerator, values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


static func _attempt_seed(seed_value: int, room_id: String, attempt: int) -> int:
	var mixed := seed_value * 1103515245
	mixed += _stable_hash(room_id) * 97
	mixed += attempt * 2654435761
	mixed += GENERATOR_VERSION * 7919
	return mixed & 0x7fffffffffffffff


static func _stable_hash(value: String) -> int:
	var result := 2166136261
	for index in range(value.length()):
		result = ((result ^ value.unicode_at(index)) * 16777619) & 0x7fffffff
	return result


static func _pos(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


static func _key(pos: Vector2i) -> String:
	return "%d:%d" % [pos.x, pos.y]


static func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < BOARD_SIZE.x and pos.y < BOARD_SIZE.y


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
