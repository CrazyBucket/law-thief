extends Node

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const PLAYER_SPRITES_SCRIPT := preload("res://scripts/ui/female_adventurer_sprites.gd")
const SLIME_SPRITES_SCRIPT := preload("res://scripts/ui/slime_sprites.gd")
const GEM_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_gem_sprites.gd")

const _BODY_COLORS := {
	"unit_player": Color(0.2, 0.78, 0.45),
	"unit_bomb_rat": Color(0.95, 0.62, 0.18),
	"unit_patrol_guard": Color(0.55, 0.62, 0.78),
	"unit_stone_bow_guard": Color(0.48, 0.52, 0.55),
	"unit_fission_slime": Color(0.35, 0.88, 0.55),
	"unit_law_worm": Color(0.72, 0.82, 0.32),
	"unit_broodmother": Color(0.58, 0.34, 0.66),
}

var _face_texture_cache: Dictionary = {}
var _knight_sheet_inst = null
var _player_sheet_inst = null
var _slime_sheet_inst = null
var _gem_sheet_inst = null


func _sheet_knight():
	if _knight_sheet_inst == null:
		_knight_sheet_inst = KNIGHT_SPRITES_SCRIPT.new()
	return _knight_sheet_inst


func _sheet_player():
	if _player_sheet_inst == null:
		_player_sheet_inst = PLAYER_SPRITES_SCRIPT.new()
	return _player_sheet_inst


func _sheet_slime():
	if _slime_sheet_inst == null:
		_slime_sheet_inst = SLIME_SPRITES_SCRIPT.new("green")
	return _slime_sheet_inst


func _sheet_gem():
	if _gem_sheet_inst == null:
		_gem_sheet_inst = GEM_SPRITES_SCRIPT.new()
	return _gem_sheet_inst


func get_unit_texture(unit_def_id: String = "") -> Texture2D:
	if unit_def_id == "unit_player":
		var cache_key := "player_face"
		if _face_texture_cache.has(cache_key):
			return _face_texture_cache[cache_key] as Texture2D
		var player_tex: Texture2D = _sheet_player().portrait_texture()
		_face_texture_cache[cache_key] = player_tex
		return player_tex
	if unit_def_id == "unit_fission_slime":
		var slime_key := "slime_face"
		if _face_texture_cache.has(slime_key):
			return _face_texture_cache[slime_key] as Texture2D
		var slime_tex: Texture2D = _sheet_slime().portrait_texture()
		_face_texture_cache[slime_key] = slime_tex
		return slime_tex
	if _face_texture_cache.has("doodle_face"):
		return _face_texture_cache["doodle_face"] as Texture2D
	var tex: Texture2D = _sheet_knight().portrait_texture()
	_face_texture_cache["doodle_face"] = tex
	return tex


func sprite_modulate_for_unit(team: String, unit_def_id: String) -> Color:
	if team == Constants.TEAM_PLAYER:
		return Color.WHITE
	if unit_def_id == "unit_fission_slime":
		return Color.WHITE
	var body: Color = _BODY_COLORS.get(unit_def_id, Color(0.74, 0.75, 0.82))
	return Color.WHITE.lerp(body.lightened(0.1), 0.52)


func get_relic_texture(relic_id: String) -> Texture2D:
	return _sheet_gem().texture_for_relic_id(relic_id)


func gem_color(gem_ref: Variant) -> Color:
	return _data_registry().get_gem_color(gem_ref)


func slot_color(slot_type: String) -> Color:
	return UiPalette.slot_color(slot_type)


func gem_symbol(gem_ref: Variant) -> String:
	return _data_registry().get_gem_symbol(gem_ref)


func get_gem_texture(gem_ref: Variant) -> Texture2D:
	var gem_id := _resolve_gem_id(gem_ref)
	if gem_id.is_empty():
		return null
	return _sheet_gem().texture_for_gem_id(gem_id)


func gem_sprite_modulate(gem_ref: Variant) -> Color:
	var gem_id := _resolve_gem_id(gem_ref)
	if gem_id.is_empty():
		return Color.WHITE
	return _sheet_gem().modulate_for_gem_id(gem_id)


func _resolve_gem_id(gem_ref: Variant) -> String:
	if gem_ref is GemState:
		return (gem_ref as GemState).gem_id
	if gem_ref is String:
		return gem_ref as String
	if gem_ref is Dictionary:
		return str(gem_ref.get("gem_id", ""))
	return ""


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
