extends SceneTree

const OUTPUT_PATH := "/tmp/law_thief_editor_overlay_catalog_probe.png"
const BattleEditorPanel = preload("res://scripts/ui/battle_editor_panel.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel := BattleEditorPanel.new()
	panel.position = Vector2(24, 16)
	panel.size = Vector2(600, 740)
	root.add_child(panel)
	await process_frame
	panel.setup(root.get_node("DataRegistry"))
	panel.set("_selected_category", "overlays")
	panel.call("_refresh_category_buttons")
	panel.call("_refresh_tool_list")
	await create_timer(0.2).timeout
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		print("EDITOR_OVERLAY_CATALOG_PROBE skipped screenshot: viewport texture unavailable")
		quit(0)
		return
	var error := image.save_png(OUTPUT_PATH)
	print("EDITOR_OVERLAY_CATALOG_PROBE %s %s" % [error, OUTPUT_PATH])
	quit(0 if error == OK else 1)
