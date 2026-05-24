extends Node

var _enabled := OS.is_debug_build()


func _ready() -> void:
	pass


func log_info(message: String) -> void:
	if _enabled:
		print("[INFO] ", message)


func log_warn(message: String) -> void:
	if _enabled:
		push_warning(message)


func log_error(message: String) -> void:
	push_error(message)
