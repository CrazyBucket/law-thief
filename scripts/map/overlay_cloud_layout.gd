class_name OverlayCloudLayout
extends RefCounted

const ATLAS_COLUMNS := 5
const ATLAS_ROWS := 9
const ATLAS_PART_COUNT := ATLAS_COLUMNS * ATLAS_ROWS
const NOMINAL_CHARACTER_HEIGHT := 70.0
const CHARACTER_FOOT_OFFSET := 14.0


static func build(cell: Vector2i, effect_type: String) -> Dictionary:
	var config := _config(effect_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(cell, effect_type)
	var parts: Array[Dictionary] = []
	var part_count := int(config["part_count"])
	var band_count := int(config["band_count"])
	var direction_flip := -1.0 if rng.randi_range(0, 1) == 0 else 1.0
	for index in range(part_count):
		var band := index % band_count
		var vertical := clampf(
			(float(band) + 0.5 + rng.randf_range(-0.22, 0.22)) / float(band_count),
			0.06,
			0.94
		)
		var horizontal_extent := lerpf(
			float(config["top_extent"]),
			float(config["bottom_extent"]),
			vertical
		)
		var base_position := Vector2(
			rng.randf_range(-horizontal_extent, horizontal_extent),
			CHARACTER_FOOT_OFFSET - (1.0 - vertical) * NOMINAL_CHARACTER_HEIGHT
		)
		var direction := direction_flip if index % 2 == 0 else -direction_flip
		parts.append({
			"atlas_index": rng.randi_range(0, ATLAS_PART_COUNT - 1),
			"base_position": base_position,
			"direction": direction,
			"vertical_motion": bool(config["vertical_motion"]),
			"travel": rng.randf_range(float(config["travel_min"]), float(config["travel_max"])),
			"speed": rng.randf_range(float(config["speed_min"]), float(config["speed_max"])),
			"phase": rng.randf(),
			"bob": rng.randf_range(float(config["bob_min"]), float(config["bob_max"])),
			"width_ratio": rng.randf_range(float(config["width_min"]), float(config["width_max"])),
			"alpha": rng.randf_range(float(config["alpha_min"]), float(config["alpha_max"])),
			"front": vertical >= 0.55,
			"vertical": vertical,
		})
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["base_position"] as Vector2).y < (b["base_position"] as Vector2).y
	)

	var particles: Array[Dictionary] = []
	for index in range(int(config["particle_count"])):
		var from_index := rng.randi_range(0, parts.size() - 2)
		var to_index := mini(parts.size() - 1, from_index + rng.randi_range(1, 2))
		particles.append({
			"from_index": from_index,
			"to_index": to_index,
			"mix": rng.randf_range(0.28, 0.72),
			"phase": rng.randf(),
			"speed": rng.randf_range(float(config["particle_speed_min"]), float(config["particle_speed_max"])),
			"size": rng.randi_range(1, 2),
			"alpha": rng.randf_range(0.22, 0.42),
			"front": bool(parts[from_index]["front"]) and bool(parts[to_index]["front"]),
		})
	return {
		"parts": parts,
		"particles": particles,
	}


static func animated_offset(part: Dictionary, time_sec: float) -> Vector2:
	var cycle := fposmod(time_sec * float(part["speed"]) + float(part["phase"]), 1.0)
	if bool(part["vertical_motion"]):
		return Vector2(
			cos(cycle * TAU) * float(part["bob"]) * float(part["direction"]),
			sin(cycle * TAU) * float(part["travel"])
		)
	var horizontal := (cycle * 2.0 - 1.0) \
		* float(part["travel"]) \
		* float(part["direction"])
	var vertical := sin((cycle + float(part["phase"])) * TAU) * float(part["bob"])
	return Vector2(horizontal, vertical)


static func drift_alpha(part: Dictionary, time_sec: float) -> float:
	if bool(part["vertical_motion"]):
		return 1.0
	var cycle := fposmod(time_sec * float(part["speed"]) + float(part["phase"]), 1.0)
	var edge := clampf(sin(cycle * PI) / 0.42, 0.0, 1.0)
	return edge * edge * (3.0 - 2.0 * edge)


static func particle_life(particle: Dictionary, time_sec: float) -> float:
	var cycle := fposmod(time_sec * float(particle["speed"]) + float(particle["phase"]), 1.0)
	return sin(cycle * PI)


static func particle_rise(particle: Dictionary, time_sec: float) -> float:
	var cycle := fposmod(time_sec * float(particle["speed"]) + float(particle["phase"]), 1.0)
	return -4.0 * cycle


static func _config(effect_type: String) -> Dictionary:
	if effect_type == Constants.TILE_MOD_TOXIC_SMOKE:
		return {
			"part_count": 11,
			"band_count": 5,
			"vertical_motion": true,
			"top_extent": 13.0,
			"bottom_extent": 30.0,
			"travel_min": 6.0,
			"travel_max": 12.0,
			"speed_min": 0.20,
			"speed_max": 0.32,
			"bob_min": 0.6,
			"bob_max": 1.8,
			"width_min": 0.30,
			"width_max": 0.43,
			"alpha_min": 0.68,
			"alpha_max": 0.86,
			"particle_count": 9,
			"particle_speed_min": 0.12,
			"particle_speed_max": 0.22,
		}
	return {
		"part_count": 8,
		"band_count": 4,
		"vertical_motion": false,
		"top_extent": 35.0,
		"bottom_extent": 52.0,
		"travel_min": 5.0,
		"travel_max": 11.0,
		"speed_min": 0.13,
		"speed_max": 0.23,
		"bob_min": 0.55,
		"bob_max": 1.6,
		"width_min": 0.20,
		"width_max": 0.30,
		"alpha_min": 0.50,
		"alpha_max": 0.66,
		"particle_count": 5,
		"particle_speed_min": 0.22,
		"particle_speed_max": 0.38,
	}


static func _seed_for(cell: Vector2i, effect_type: String) -> int:
	var effect_seed := 0x45D9F3B if effect_type == Constants.TILE_MOD_TOXIC_SMOKE else 0x119DE1F3
	return (
		(effect_seed ^ (cell.x * 73856093) ^ (cell.y * 19349663))
		& 0x7FFFFFFF
	)
