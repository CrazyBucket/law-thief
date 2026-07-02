extends SceneTree

const BattleEditorPanel = preload("res://scripts/ui/battle_editor_panel.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("DataRegistry")
	_require(registry.get_surface_overlay_ids().has("tile_grass_sprouts"), "surface overlay catalog must include grass sprouts")
	_require(registry.get_surface_overlay_ids().has("tile_grass_thicket"), "surface overlay catalog must include grass thicket")
	_require(registry.get_surface_overlay_ids().has("tile_bush_thicket"), "surface overlay catalog must include bush thicket")
	var panel := BattleEditorPanel.new()
	root.add_child(panel)
	await process_frame
	panel.setup(registry)
	var catalog: Dictionary = panel.get("_catalog")
	var overlays: Array = catalog.get("overlays", [])
	_require(_has_entry(overlays, "tile_grass_sprouts", "surface_overlay"), "Overlay tab must list grass sprouts as a surface overlay")
	_require(_has_entry(overlays, "tile_grass_patch", "surface_overlay"), "Overlay tab must list grass patch as a surface overlay")
	_require(_has_entry(overlays, "tile_grass_tall", "surface_overlay"), "Overlay tab must list tall grass as a surface overlay")
	_require(_has_entry(overlays, "tile_grass_thicket", "surface_overlay"), "Overlay tab must list grass thicket as a surface overlay")
	_require(_has_entry(overlays, "tile_bush_tall", "surface_overlay"), "Overlay tab must list tall bush as a surface overlay")
	_require(_has_entry(overlays, "tile_bush_thicket", "surface_overlay"), "Overlay tab must list bush thicket as a surface overlay")
	_require(_has_entry(overlays, Constants.TILE_MOD_FIRE, "overlay"), "Overlay tab must keep modifier overlays")
	_require(_entry_value(overlays, "tile_grass_sprouts", "tile_id") == Constants.TILE_GRASS, "grass sprouts must place a grass tile")
	_require(_entry_value(overlays, "tile_grass_sprouts", "surface_variant") == "sprouts", "grass sprouts must preserve the chosen variant")
	print("BATTLE_EDITOR_OVERLAY_CATALOG_TEST_PASS")
	quit(0)


func _has_entry(entries: Array, entry_id: String, kind: String) -> bool:
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if str(entry.get("id", "")) == entry_id and str(entry.get("kind", "")) == kind:
			return true
	return false


func _entry_value(entries: Array, entry_id: String, key: String) -> String:
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if str(entry.get("id", "")) == entry_id:
			return str(entry.get(key, ""))
	return ""


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
