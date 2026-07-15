class_name GemLightVisuals
extends RefCounted

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const BoardUtils = preload("res://scripts/rules/board_utils.gd")


static func color_for_context(gem_ctx: Dictionary) -> Color:
	var dye := str(gem_ctx.get("light_dye_element", ""))
	if dye == "fire" or GemTagResolver.has_tag(gem_ctx, "fire"):
		return Color(1.0, 0.24, 0.12)
	if dye == "poison" or GemTagResolver.has_tag(gem_ctx, "poison"):
		return Color(0.05, 0.95, 0.18)
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		return Color(1.0, 0.92, 0.22)
	if GemTagResolver.has_tag(gem_ctx, "ice"):
		return Color(0.55, 0.9, 1.0)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		return Color(1.0, 0.58, 0.18)
	return Color(1.0, 0.96, 0.58)


static func element_for_context(gem_ctx: Dictionary) -> String:
	var dye := str(gem_ctx.get("light_dye_element", ""))
	if not dye.is_empty():
		return dye
	for element in ["fire", "poison", "arc", "ice", "explosion"]:
		if GemTagResolver.has_tag(gem_ctx, element):
			return element
	return "light"


static func is_valid_aim(attacker: UnitState, target_pos: Vector2i) -> bool:
	if attacker == null:
		return false
	var origin := BoardUtils.projectile_origin_cell(attacker, target_pos)
	var delta := target_pos - origin
	return delta != Vector2i.ZERO and (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y))


static func context_with_path_dye(state: GameState, cells: Array[Vector2i], gem_ctx: Dictionary) -> Dictionary:
	var result := gem_ctx.duplicate(true)
	for cell in cells:
		var dye := dye_element_at(state, cell)
		if not dye.is_empty():
			result = context_with_dye(result, dye)
	return result


static func dye_element_at(state: GameState, cell: Vector2i) -> String:
	if state == null:
		return ""
	var tile := state.get_tile(cell)
	if tile == null:
		return ""
	if tile.has_modifier(Constants.TILE_MOD_FIRE):
		return "fire"
	if tile.has_modifier(Constants.TILE_MOD_POISON_FOG) or tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE) or tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
		return "poison"
	return ""


static func context_with_dye(gem_ctx: Dictionary, dye: String) -> Dictionary:
	var result := gem_ctx.duplicate(true)
	if dye.is_empty():
		return result
	result["light_dye_element"] = dye
	var levels: Dictionary = result.get("tag_levels", {}).duplicate()
	levels[dye] = maxi(1, int(levels.get(dye, 0)))
	result["tag_levels"] = levels
	return result


static func dye_transitions(state: GameState, cells: Array[Vector2i]) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var current := ""
	for cell in cells:
		var dye := dye_element_at(state, cell)
		if dye.is_empty() or dye == current:
			continue
		current = dye
		transitions.append({"cell": cell, "element": dye, "color": color_for_context(context_with_dye({}, dye))})
	return transitions


static func build_beam_event(from_cell: Vector2i, to_cell: Vector2i, gem_ctx: Dictionary = {}, width: float = 1.0, overrides: Dictionary = {}) -> Dictionary:
	var element := element_for_context(gem_ctx)
	var event := {"type": "light_beam", "from": from_cell, "to": to_cell, "color": color_for_context(gem_ctx), "element": element, "width": width, "power": 1.0, "core": 0.16, "halo": 0.68, "noise": 0.2 if element == "light" else 0.42, "speed": 1.0, "impact_size": width, "show_impact": false}
	for key in overrides:
		event[key] = overrides[key]
	return event
