extends Node

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")

const _BODY_COLORS := {
	"unit_player": Color(0.2, 0.78, 0.45),
	"unit_bomber": Color(0.9, 0.28, 0.28),
	"unit_training_guard": Color(0.62, 0.68, 0.72),
	"unit_heavy_guard": Color(0.45, 0.52, 0.58),
	"unit_poison_bug": Color(0.62, 0.28, 0.78),
	"unit_gravity_eye": Color(0.28, 0.55, 0.92),
	"unit_grunt": Color(0.92, 0.55, 0.22),
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


func gem_color(gem_id: String) -> Color:
	match gem_id:
		"gem_explosion":
			return Color(1.0, 0.45, 0.2)
		"gem_poison":
			return Color(0.55, 0.9, 0.35)
		"gem_gravity":
			return Color(0.35, 0.65, 1.0)
		"gem_heavy_armor":
			return Color(0.7, 0.75, 0.85)
		"gem_conductive":
			return Color(0.95, 0.9, 0.3)
		"gem_fragile":
			return Color(0.85, 0.55, 0.95)
	return Color.WHITE


func slot_color(slot_type: String) -> Color:
	match slot_type:
		"red":
			return Color(0.95, 0.35, 0.35)
		"blue":
			return Color(0.35, 0.65, 0.95)
		"black":
			return Color(0.55, 0.55, 0.65)
	return Color.WHITE


func gem_symbol(gem_id: String) -> String:
	match gem_id:
		"gem_explosion":
			return "爆"
		"gem_poison":
			return "毒"
		"gem_gravity":
			return "引"
		"gem_heavy_armor":
			return "甲"
		"gem_conductive":
			return "电"
		"gem_fragile":
			return "碎"
	return "◆"
