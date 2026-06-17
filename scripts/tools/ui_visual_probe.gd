extends SceneTree

const OUTPUT_DIR := "artifacts/verify"
const CAPTURES: Array[Dictionary] = [
	{"scene": "res://scenes/battle/battle_scene.tscn", "file": "ui_battle_probe.png"},
	{"scene": "res://scenes/map/adventure_map.tscn", "file": "ui_map_probe.png"},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://%s" % OUTPUT_DIR))
	for capture in CAPTURES:
		await _capture_scene(str(capture.get("scene", "")), str(capture.get("file", "")))
	print("UI_VISUAL_PROBE_PASS")
	quit()


func _capture_scene(scene_path: String, file_name: String) -> void:
	var packed := load(scene_path) as PackedScene
	assert(packed != null, "scene should load: %s" % scene_path)
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture %s: headless renderer has no readable screenshot" % scene_path)
		node.queue_free()
		await process_frame
		return
	var texture := root.get_texture()
	if texture == null:
		print("  [SKIP] capture %s: renderer has no readable root texture" % scene_path)
		node.queue_free()
		await process_frame
		return
	var image := texture.get_image()
	if image == null:
		print("  [SKIP] capture %s: renderer returned no image" % scene_path)
		node.queue_free()
		await process_frame
		return
	var output_path := ProjectSettings.globalize_path("res://%s/%s" % [OUTPUT_DIR, file_name])
	var err := image.save_png(output_path)
	assert(err == OK, "screenshot should save: %s err=%d" % [output_path, err])
	print("  [OK] capture %s" % output_path)
	node.queue_free()
	await process_frame
