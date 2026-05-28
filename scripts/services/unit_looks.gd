extends Node

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")

const _BODY_COLORS := {
	"unit_player": Color(0.2, 0.78, 0.45),
	"unit_bomb_rat": Color(0.95, 0.62, 0.18),
	"unit_patrol_guard": Color(0.55, 0.62, 0.78),
	"unit_stone_bow_guard": Color(0.48, 0.52, 0.55),
	"unit_fission_slime": Color(0.35, 0.88, 0.55),
}

var _face_texture_cache: Dictionary = {}
var _knight_sheet_inst = null


func _sheet_knight():
	if _knight_sheet_inst == null:
		_knight_sheet_inst = KNIGHT_SPRITES_SCRIPT.new()
	return _knight_sheet_inst


func get_unit_texture(_unit_def_id: String) -> Texture2D:
	if _face_texture_cache.has("doodle_face"):
		return _face_texture_cache["doodle_face"] as Texture2D
	var tex: Texture2D = _sheet_knight().portrait_texture()
	_face_texture_cache["doodle_face"] = tex
	return tex


func sprite_modulate_for_unit(team: String, unit_def_id: String) -> Color:
	if team == Constants.TEAM_PLAYER:
		return Color(0.98, 1.06, 1.02)
	var body: Color = _BODY_COLORS.get(unit_def_id, Color(0.74, 0.75, 0.82))
	return Color.WHITE.lerp(body.lightened(0.1), 0.52)


func gem_color(gem_ref: Variant) -> Color:
	return _data_registry().get_gem_color(gem_ref)


func slot_color(slot_type: String) -> Color:
	match slot_type:
		"red":
			return Color(0.95, 0.35, 0.35)
		"blue":
			return Color(0.35, 0.65, 0.95)
		"black":
			return Color(0.55, 0.55, 0.65)
	return Color.WHITE


func gem_symbol(gem_ref: Variant) -> String:
	return _data_registry().get_gem_symbol(gem_ref)


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
