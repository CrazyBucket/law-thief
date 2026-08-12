class_name GemDefValidator
extends RefCounted

const FIELDS := {
	"display_name_key": true, "symbol_key": true, "symbol": true, "color": true,
	"tag": true, "element": true, "pool_tier": true, "max_stack_level": true,
	"combos": true, "rarity": true, "allow_random_pool": true, "ability_profiles": true,
}
const REQUIRED_FIELDS := ["display_name_key", "symbol_key", "symbol", "color", "tag", "element", "pool_tier", "max_stack_level", "combos", "rarity", "ability_profiles"]
const ABILITY_PROFILE_KEYS := ["player_skill", "unit_red_active", "enemy_red_action", "blue_turn_start", "blue_damaged", "blue_move_through", "black_death", "attack_bonus", "armor_bonus"]
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "boss"]


static func validate(defs: Dictionary, known_profiles: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if defs.is_empty():
		errors.append("gem_defs should not be empty")
		return errors
	var known_tags: Dictionary = {}
	for gem_id in defs.keys():
		var raw_def: Variant = defs[gem_id]
		if raw_def is Dictionary:
			var tag := str((raw_def as Dictionary).get("tag", ""))
			if not tag.is_empty():
				if known_tags.has(tag):
					errors.append("gem_defs.%s.tag duplicates %s" % [gem_id, known_tags[tag]])
				else:
					known_tags[tag] = str(gem_id)
	for gem_id in defs.keys():
		var prefix := "gem_defs.%s" % gem_id
		var raw_def: Variant = defs[gem_id]
		if not raw_def is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var gem_def := raw_def as Dictionary
		for field_id in gem_def.keys():
			if not FIELDS.has(str(field_id)):
				errors.append("%s.%s is unknown" % [prefix, field_id])
		for field_id in REQUIRED_FIELDS:
			if not gem_def.has(field_id):
				errors.append("%s.%s missing" % [prefix, field_id])
		for field_id in ["display_name_key", "symbol_key", "symbol", "tag", "element"]:
			if gem_def.has(field_id) and (not gem_def[field_id] is String or str(gem_def[field_id]).is_empty()):
				errors.append("%s.%s should be a non-empty string" % [prefix, field_id])
		var color: Variant = gem_def.get("color", null)
		if not color is Array or (color as Array).size() not in [3, 4]:
			errors.append("%s.color should contain 3 or 4 numbers" % prefix)
		else:
			for component in color as Array:
				if not _is_number(component) or float(component) < 0.0 or float(component) > 1.0:
					errors.append("%s.color components should be numbers in [0, 1]" % prefix)
					break
		for field_id in ["pool_tier", "max_stack_level"]:
			if not _is_positive_integer(gem_def.get(field_id, null)):
				errors.append("%s.%s should be a positive integer" % [prefix, field_id])
		var rarity := str(gem_def.get("rarity", ""))
		if rarity not in RARITIES:
			errors.append("%s.rarity unknown: %s" % [prefix, rarity])
		if gem_def.has("allow_random_pool") and not gem_def["allow_random_pool"] is bool:
			errors.append("%s.allow_random_pool should be bool" % prefix)
		_validate_combos(errors, prefix, gem_def.get("combos", null), known_tags)
		_validate_profiles(
			errors,
			prefix,
			gem_def.get("ability_profiles", null),
			known_profiles,
			not bool(gem_def.get("allow_random_pool", true))
		)
	return errors


static func _validate_combos(errors: Array[String], prefix: String, combos: Variant, known_tags: Dictionary) -> void:
	if not combos is Array:
		errors.append("%s.combos should be array" % prefix)
		return
	var seen: Dictionary = {}
	for combo in combos as Array:
		var combo_id := str(combo)
		if not combo is String or combo_id.is_empty():
			errors.append("%s.combos should contain non-empty strings" % prefix)
		elif not known_tags.has(combo_id):
			errors.append("%s.combos references unknown tag: %s" % [prefix, combo_id])
		elif seen.has(combo_id):
			errors.append("%s.combos contains duplicate tag: %s" % [prefix, combo_id])
		seen[combo_id] = true


static func _validate_profiles(
	errors: Array[String],
	prefix: String,
	profiles: Variant,
	known_profiles: Dictionary,
	allow_empty: bool = false
) -> void:
	if not profiles is Dictionary:
		errors.append("%s.ability_profiles should be a non-empty object" % prefix)
		return
	if (profiles as Dictionary).is_empty():
		if not allow_empty:
			errors.append("%s.ability_profiles should be a non-empty object" % prefix)
		return
	for ability_slot in (profiles as Dictionary).keys():
		var slot_id := str(ability_slot)
		var profile_id := str((profiles as Dictionary)[ability_slot])
		if slot_id not in ABILITY_PROFILE_KEYS:
			errors.append("%s.ability_profiles.%s is unknown" % [prefix, slot_id])
		elif profile_id.is_empty():
			errors.append("%s.ability_profiles.%s should be a non-empty string" % [prefix, slot_id])
		elif not known_profiles.is_empty() and not known_profiles.has(profile_id):
			errors.append("%s.ability_profiles.%s references unknown profile: %s" % [prefix, slot_id, profile_id])


static func _is_positive_integer(value: Variant) -> bool:
	return _is_number(value) and int(value) == float(value) and int(value) > 0


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
