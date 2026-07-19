class_name DamageContext
extends RefCounted

const REASON_TAGS: Dictionary = {
	"arc": "arc",
	"lightning_death": "arc",
	"burning": "fire",
	"tile_fire": "fire",
	"pillar_burn": "fire",
	"poison": "poison",
	"poison_attack": "poison",
	"fire_attack": "fire",
	"ice_attack": "ice",
	"arc_attack": "arc",
	"split_attack": "split",
	"split_wing": "split",
	"split_redirect": "split",
	"explosion": "explosion",
	"explosion_cross": "explosion",
	"barrel_explosion": "explosion",
	"blue_explosion_aura": "explosion",
	"self_explosion": "explosion",
	"light_beam": "light",
	"light_reflect": "light",
	"light_judgement": "light",
	"gravity_collision": "gravity",
	"gravity_deflect": "gravity",
	"counter_red": "counter",
	"counter_blue": "counter",
	"counter_black": "counter",
}


static func create(
	source_uid: String,
	reason: String,
	damage_tags: Array = [],
	gem_tag_context: Dictionary = {},
	active_attack: bool = false
) -> Dictionary:
	var tags := _normalized_tags(damage_tags)
	if tags.is_empty() and not gem_tag_context.is_empty():
		tags = _normalized_tags(gem_tag_context.get("tags", []))
	if tags.is_empty() and REASON_TAGS.has(reason):
		tags.append(str(REASON_TAGS[reason]))
	return {
		"source_uid": source_uid,
		"reason": reason,
		"damage_tags": tags,
		"gem_tag_context": gem_tag_context.duplicate(true),
		"active_attack": active_attack,
	}


static func from_options(
	source_uid: String,
	reason: String,
	opts: Dictionary = {}
) -> Dictionary:
	var raw_context: Variant = opts.get("damage_context", {})
	if raw_context is Dictionary and not (raw_context as Dictionary).is_empty():
		var context: Dictionary = raw_context
		return create(
			source_uid,
			reason,
			context.get("damage_tags", []),
			context.get("gem_tag_context", {}),
			bool(context.get("active_attack", false))
		)
	return create(
		source_uid,
		reason,
		opts.get("damage_tags", []),
		opts.get("gem_tag_context", {}),
		bool(opts.get("active_attack", false))
	)


static func normalize(source_uid: String, reason: String, context: Dictionary = {}) -> Dictionary:
	return create(
		source_uid,
		reason,
		context.get("damage_tags", []),
		context.get("gem_tag_context", {}),
		bool(context.get("active_attack", false))
	)


static func with_actual_damage(context: Dictionary, actual_hp_loss: int) -> Dictionary:
	var result := context.duplicate(true)
	result["actual_hp_loss"] = maxi(0, actual_hp_loss)
	return result


static func tags(context: Dictionary) -> Array[String]:
	return _normalized_tags(context.get("damage_tags", []))


static func gem_context(context: Dictionary) -> Dictionary:
	var raw: Variant = context.get("gem_tag_context", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func is_active_attack(context: Dictionary) -> bool:
	return bool(context.get("active_attack", false))


static func _normalized_tags(raw_tags: Variant) -> Array[String]:
	var present: Dictionary = {}
	if raw_tags is Array:
		for raw_tag in raw_tags:
			var tag := str(raw_tag)
			if tag in GemTagResolver.TAG_ORDER:
				present[tag] = true
	var result: Array[String] = []
	for tag in GemTagResolver.TAG_ORDER:
		if present.has(tag):
			result.append(tag)
	return result
