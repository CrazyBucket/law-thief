extends SceneTree

const OUTPUT_DIR := "res://artifacts/verify"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("TRANSITION_VISUAL_PROBE_SKIP headless renderer has no readable screenshot")
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_build_backdrop()
	await process_frame
	await process_frame
	var manager := root.get_node("TransitionManager")
	var overlay := manager.get_node("TransitionLayer/Overlay") as ColorRect
	await manager.cover(manager.Style.CHECKERBOARD, 0.0, {"columns": 10})
	(overlay.material as ShaderMaterial).set_shader_parameter("progress", 0.52)
	await process_frame
	var checker_error := _save_viewport("transition_checkerboard_probe.png")
	await manager.reveal(0.0)
	await manager.cover(manager.Style.SILHOUETTE, 0.0)
	(overlay.material as ShaderMaterial).set_shader_parameter("progress", 0.54)
	await process_frame
	var silhouette_error := _save_viewport("transition_silhouette_probe.png")
	manager.reset_immediately()
	print("TRANSITION_VISUAL_PROBE checker=%s silhouette=%s" % [checker_error, silhouette_error])
	quit(0 if checker_error == OK and silhouette_error == OK else 1)


func _build_backdrop() -> void:
	var backdrop := Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	root.move_child(backdrop, 0)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("182830")
	backdrop.add_child(background)
	for index in range(8):
		var card := ColorRect.new()
		card.position = Vector2(90 + (index % 4) * 290, 100 + (index / 4) * 300)
		card.size = Vector2(230, 220)
		card.color = Color("35505a") if index % 2 == 0 else Color("8a6944")
		backdrop.add_child(card)


func _save_viewport(file_name: String) -> Error:
	var texture := root.get_viewport().get_texture()
	if texture == null:
		return ERR_UNAVAILABLE
	var image := texture.get_image()
	if image == null:
		return ERR_UNAVAILABLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	return image.save_png(ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name]))
