class_name GemEchoRules
extends RefCounted

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")


static func resolve_echo_tags(state: GameState, gem_ctx: Dictionary, rng_key: String) -> Array[String]:
	if state == null or gem_ctx.is_empty():
		return []
	if int(gem_ctx.get("echo_depth", 0)) > 0:
		return []
	var candidates: Array[String] = []
	for tag in gem_ctx.get("tags", []):
		var tag_s := str(tag)
		if tag_s == "echo":
			continue
		if tag_s not in candidates:
			candidates.append(tag_s)
	if candidates.is_empty():
		return []
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	var scope := str(gem_ctx.get("effect_level_scope", ""))
	if registry == null:
		push_error("GemEchoRules: DataRegistry is required")
		return []
	var level_def: Dictionary = registry.get_gem_effect_level_def("echo", scope, echo_level)
	var count := int(level_def["echo_tag_count"])
	if count <= 0:
		return []
	var rng: Node = Engine.get_main_loop().root.get_node_or_null("RngService")
	if rng != null:
		rng.shuffle_in_place(rng_key, candidates)
	var picked: Array[String] = candidates.slice(0, mini(count, candidates.size()))
	var empowers_first_tag := (
		(level_def.has("first_tag_strength") and int(level_def["first_tag_strength"]) > 1)
		or (level_def.has("first_tag_repeat_count") and int(level_def["first_tag_repeat_count"]) > 1)
	)
	if empowers_first_tag and not picked.is_empty():
		var bonus_index := 0
		if picked.size() > 1 and rng != null:
			bonus_index = int(rng.roll_int("%s_bonus" % rng_key, 0, picked.size() - 1))
		var bonus_tag := picked[bonus_index]
		picked.remove_at(bonus_index)
		picked.insert(0, bonus_tag)
	return picked
