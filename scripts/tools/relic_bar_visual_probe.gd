extends SceneTree

const OUTPUT_PATH := "res://artifacts/verify/relic-bar.png"
const CONSTRAINED_OUTPUT_PATH := "res://artifacts/verify/relic-bar-constrained.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var run_service: Node = root.get_node("RunService")
	run_service.start_run(8801, 8802)
	for relic_id in [
		"relic_adrenaline",
		"relic_autopsy_log",
		"relic_broken_rib",
		"relic_chaos_launcher",
		"relic_copper_wire",
		"relic_cracked_amulet",
		"relic_cracked_goggles",
		"relic_crowbar",
	]:
		run_service.acquire_relic(relic_id)

	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.06, 0.08)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(backdrop)
	var relic_root := Control.new()
	relic_root.position = Vector2(24, 24)
	canvas.add_child(relic_root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	relic_root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1
	scroll.add_child(grid)

	var presenter := BattleHudPresenter.new()
	presenter.setup({
		"relic_bar_root": relic_root,
		"relic_bar_scroll": scroll,
		"relic_bar_vbox": grid,
	})
	presenter._refresh_relic_bar(520.0)
	_apply_relic_root_size(relic_root, scroll)
	await process_frame
	await process_frame
	_assert_badges_do_not_overlap(grid)
	grid.get_child(0).mouse_entered.emit()
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		quit(1)
		return

	grid.get_child(0).mouse_exited.emit()
	presenter._refresh_relic_bar(144.0)
	_apply_relic_root_size(relic_root, scroll)
	await process_frame
	assert(grid.columns == 2, "constrained relic rail should use two separated columns")
	_assert_badges_do_not_overlap(grid)
	for child in grid.get_children():
		var hover_texture: TextureRect = child.get_node("HoverTextureOutline")
		assert(not hover_texture.visible, "constrained probe should render non-hovered relic textures")
	var constrained_image := root.get_viewport().get_texture().get_image()
	var constrained_error := constrained_image.save_png(CONSTRAINED_OUTPUT_PATH)
	print("RELIC_BAR_VISUAL_PROBE %s %s %s" % [error, OUTPUT_PATH, CONSTRAINED_OUTPUT_PATH])
	quit(0 if constrained_error == OK else 1)


func _apply_relic_root_size(relic_root: Control, scroll: ScrollContainer) -> void:
	var viewport_size := scroll.custom_minimum_size
	relic_root.size = viewport_size
	scroll.size = viewport_size


func _assert_badges_do_not_overlap(grid: GridContainer) -> void:
	var rects: Array[Rect2] = []
	for child in grid.get_children():
		assert(child.size.x >= 30.0 and child.size.y >= 30.0, "relic badge must remain readable")
		var rect := Rect2(child.position, child.size)
		for existing in rects:
			assert(not rect.intersects(existing), "relic badges must not overlap")
		rects.append(rect)
