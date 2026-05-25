extends Node


func _ready() -> void:
	pass


func tr_key(key: String, params: Dictionary = {}) -> String:
	var text := tr(key)
	if params.is_empty():
		return text
	return text.format(params)
