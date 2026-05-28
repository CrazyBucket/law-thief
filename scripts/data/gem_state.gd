class_name GemState
extends RefCounted

var uid: String = ""
var gem_id: String = ""
var owner_uid: String = ""
var slot_index: int = -1
var def_overrides: Dictionary = {}


static func create(uid: String, gem_id: String, def_overrides: Dictionary = {}) -> GemState:
	var gem := GemState.new()
	gem.uid = uid
	gem.gem_id = gem_id
	gem.def_overrides = def_overrides.duplicate(true)
	return gem


func clone() -> GemState:
	var gem := GemState.new()
	gem.uid = uid
	gem.gem_id = gem_id
	gem.owner_uid = owner_uid
	gem.slot_index = slot_index
	gem.def_overrides = def_overrides.duplicate(true)
	return gem
