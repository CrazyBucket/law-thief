class_name GemPoolValidator
extends RefCounted

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "boss"]
const CHAPTER_IDS := ["chapter_1", "chapter_2", "chapter_3"]


static func validate(config: Dictionary, known_tags: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if not config.has("global"):
		errors.append("gem_pools.global missing")
	if not config.has("teaching_boosts"):
		errors.append("gem_pools.teaching_boosts missing")
	for source_id in config.keys():
		if str(source_id) == "teaching_boosts":
			continue
		var prefix := "gem_pools.%s" % source_id
		var raw_pool: Variant = config[source_id]
		if not raw_pool is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var pool := raw_pool as Dictionary
		for field_id in pool.keys():
			if str(field_id) not in ["source_tier", "rarity_weights", "tag_weights"]:
				errors.append("%s.%s is unknown" % [prefix, field_id])
		if not _is_positive_integer(pool.get("source_tier", null)):
			errors.append("%s.source_tier should be a positive integer" % prefix)
		var rarity_weights: Variant = pool.get("rarity_weights", null)
		if not rarity_weights is Dictionary or (rarity_weights as Dictionary).is_empty():
			errors.append("%s.rarity_weights should be a non-empty object" % prefix)
		else:
			errors.append_array(_validate_weight_map("%s.rarity_weights" % prefix, rarity_weights as Dictionary, _id_set(RARITIES)))
		var tag_weights: Variant = pool.get("tag_weights", {})
		if not tag_weights is Dictionary:
			errors.append("%s.tag_weights should be object" % prefix)
		elif not (tag_weights as Dictionary).is_empty():
			errors.append_array(_validate_weight_map("%s.tag_weights" % prefix, tag_weights as Dictionary, known_tags))
	_validate_teaching_boosts(errors, config.get("teaching_boosts", null), known_tags)
	return errors


static func _validate_teaching_boosts(errors: Array[String], teaching_boosts: Variant, known_tags: Dictionary) -> void:
	if not teaching_boosts is Dictionary:
		errors.append("gem_pools.teaching_boosts should be object")
		return
	for chapter_id in CHAPTER_IDS:
		if not (teaching_boosts as Dictionary).has(chapter_id):
			errors.append("gem_pools.teaching_boosts.%s missing" % chapter_id)
	for chapter_id in (teaching_boosts as Dictionary).keys():
		if str(chapter_id) not in CHAPTER_IDS:
			errors.append("gem_pools.teaching_boosts.%s is unknown" % chapter_id)
			continue
		var boosts: Variant = (teaching_boosts as Dictionary)[chapter_id]
		if not boosts is Dictionary or (boosts as Dictionary).is_empty():
			errors.append("gem_pools.teaching_boosts.%s should be a non-empty object" % chapter_id)
			continue
		for tag in (boosts as Dictionary).keys():
			var value: Variant = (boosts as Dictionary)[tag]
			if not known_tags.is_empty() and not known_tags.has(str(tag)):
				errors.append("gem_pools.teaching_boosts.%s.%s references unknown tag" % [chapter_id, tag])
			elif not _is_number(value) or float(value) <= 0.0:
				errors.append("gem_pools.teaching_boosts.%s.%s should be positive" % [chapter_id, tag])


static func _validate_weight_map(prefix: String, weights: Dictionary, known_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var total_weight := 0.0
	for raw_id in weights.keys():
		var id := str(raw_id)
		var value: Variant = weights[raw_id]
		if not known_ids.is_empty() and not known_ids.has(id):
			errors.append("%s.%s is unknown" % [prefix, id])
		elif not _is_number(value):
			errors.append("%s.%s should be number" % [prefix, id])
		elif float(value) < 0.0:
			errors.append("%s.%s should be non-negative" % [prefix, id])
		else:
			total_weight += float(value)
	if total_weight <= 0.0:
		errors.append("%s should have positive total weight" % prefix)
	return errors


static func _id_set(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in ids:
		result[str(id)] = true
	return result


static func _is_positive_integer(value: Variant) -> bool:
	return _is_number(value) and int(value) == float(value) and int(value) > 0


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
