class_name MapNode extends RefCounted

var grid_pos: Vector2i
var layer: int
var room_type: String = ""

var parents: Array[Vector2i] = []
var children: Array[Vector2i] = []
var properties: Dictionary = {}


func _init(x: int, y: int) -> void:
	grid_pos = Vector2i(x, y)
	layer = x + y


func clear() -> void:
	parents.clear()
	children.clear()
	properties.clear()
	room_type = ""
