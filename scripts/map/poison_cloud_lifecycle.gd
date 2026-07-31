class_name PoisonCloudLifecycle
extends RefCounted

const FADE_IN_SECONDS := 0.42
const FADE_OUT_SECONDS := 0.68
const EFFECT_TYPES := [
	Constants.TILE_MOD_POISON_FOG,
	Constants.TILE_MOD_TOXIC_SMOKE,
]

var _entries: Dictionary = {}


func clear() -> void:
	_entries.clear()


func prepare_state_change(previous: GameState, next: GameState) -> void:
	if previous == null or next == null or previous.encounter_id != next.encounter_id:
		clear()


func sync(state: GameState, delta: float) -> bool:
	var active := {}
	if state != null:
		for tile: TileState in state.tiles.values():
			if tile == null:
				continue
			for effect_type in EFFECT_TYPES:
				if not tile.has_modifier(effect_type):
					continue
				var key := _key(tile.pos, effect_type)
				active[key] = true
				var entry: Dictionary = _entries.get(key, {
					"cell": tile.pos,
					"effect_type": effect_type,
					"progress": 0.0,
					"stage": _stage(tile, effect_type),
				})
				entry["target"] = 1.0
				entry["stage"] = _stage(tile, effect_type)
				_entries[key] = entry
	var dirty := false
	for raw_key in _entries.keys():
		var key := str(raw_key)
		var entry: Dictionary = _entries[key]
		var current := float(entry["progress"])
		var target := 1.0 if active.has(key) else 0.0
		var duration := FADE_IN_SECONDS if target > current else FADE_OUT_SECONDS
		var next := move_toward(current, target, delta / duration)
		if not is_equal_approx(current, next):
			dirty = true
		entry["progress"] = next
		entry["target"] = target
		if next <= 0.0001 and target <= 0.0:
			_entries.erase(key)
		else:
			_entries[key] = entry
	return dirty


func visuals_for_cell(cell: Vector2i) -> Dictionary:
	var result := {}
	for effect_type in EFFECT_TYPES:
		var entry: Dictionary = _entries.get(_key(cell, effect_type), {})
		if entry.is_empty():
			continue
		result[effect_type] = {
			"alpha": _smoothstep01(float(entry["progress"])),
			"stage": float(entry["stage"]),
		}
	return result


func active_effects() -> Dictionary:
	var result := {}
	for entry_variant in _entries.values():
		var entry: Dictionary = entry_variant
		if float(entry["progress"]) > 0.0001:
			result[str(entry["effect_type"])] = true
	return result


func has_visuals() -> bool:
	return not _entries.is_empty()


static func _stage(tile: TileState, effect_type: String) -> float:
	var default_duration := (
		CombatConfig.poison_fog_duration()
		if effect_type == Constants.TILE_MOD_POISON_FOG
		else CombatConfig.toxic_smoke_duration()
	)
	var modifier := tile.get_modifier(effect_type)
	var duration := maxf(1.0, float(int(modifier.get("duration", default_duration))))
	var baseline := maxf(1.0, maxf(float(default_duration), duration))
	return clampf(duration / baseline, 0.25, 1.0)


static func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


static func _key(cell: Vector2i, effect_type: String) -> String:
	return "%s:%d:%d" % [effect_type, cell.x, cell.y]
