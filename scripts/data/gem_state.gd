class_name GemState
extends RefCounted

var uid: String = ""
var gem_id: String = ""
var owner_uid: String = ""
var slot_index: int = -1


static func create(uid: String, gem_id: String) -> GemState:
	var gem := GemState.new()
	gem.uid = uid
	gem.gem_id = gem_id
	return gem
