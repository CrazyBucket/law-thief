extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== UI Overlay Contract Test ===")
	_test_move_hover_route()
	_test_enemy_intent_route()
	await _test_old_mage_ui_contract()
	_test_relic_bar_layout_compacts_before_scroll()
	await _test_battle_scene_click_inspect()
	await _test_scavenger_hook_slot_panel_flow()
	await _test_battle_scene_consumes_queued_battle_end()
	await _test_rich_tooltip_has_body_height()
	_test_battle_end_queue_take()
	print("UI_OVERLAY_CONTRACT_TEST_PASS")
	quit()


func _test_move_hover_route() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 7)
	var player := ctrl.state.get_player()
	assert(player != null, "player should exist")
	ctrl.select_action(Constants.ACTION_MOVE)
	var initial := ctrl.get_highlights()
	var target := _first_cell_after(initial.get("reachable", []), player.pos)
	assert(target.x >= 0, "move highlights should include at least one destination")
	var highlights := ctrl.get_highlights(target)
	assert(_has_overlay_cell(highlights, "move", target), "move overlay should include hovered destination")
	var route := _find_route(highlights, "move")
	assert(not route.is_empty(), "move hover should expose route data")
	var path: Array = route.get("path", [])
	assert(path.size() >= 2, "move route should contain start and destination")
	assert(path[0] == player.pos, "move route should start at player position")
	assert(path[path.size() - 1] == target, "move route should end at hovered destination")
	assert(not bool(route.get("arrow_reverse", false)), "move route arrow should point along the movement direction")
	print("  [OK] move hover route overlay")


func _test_enemy_intent_route() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "bow/player should exist")
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	var prop := EntityState.create("ui_overlay_block_prop", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent != null and not bow.intent.path.is_empty(), "blocked bow should preview a movement path")
	ctrl.selected_unit_uid = bow.uid
	var highlights := ctrl.get_highlights()
	var route := _find_route(highlights, "intent")
	assert(not route.is_empty(), "selected enemy intent should expose route data")
	var path: Array = route.get("path", [])
	assert(path[0] == bow.pos, "intent route should start at enemy position")
	assert(path[path.size() - 1] == bow.intent.path[bow.intent.path.size() - 1], "intent route should end at preview path destination")
	assert(_has_overlay_cell(highlights, "intent_path", bow.intent.path[0]), "intent path should be drawn by unified overlays")
	var final_pos: Vector2i = bow.intent.path[bow.intent.path.size() - 1]
	state.move_unit(bow, final_pos)
	var completed_highlights := ctrl.get_highlights()
	assert(_find_route(completed_highlights, "intent").is_empty(), "completed selected intent must not draw a route back to its old path")
	assert(not _has_overlay_cell(completed_highlights, "intent_path", final_pos), "completed selected intent must not retain its destination as a movement overlay")
	print("  [OK] selected enemy intent route overlay")


func _test_old_mage_ui_contract() -> void:
	var game_service: Node = root.get_node("GameService")
	var settings: Node = root.get_node("SettingsService")
	var previous_encounter := str(game_service.pending_encounter_id)
	var previous_room := str(game_service.pending_room_id)
	var previous_mode := str(game_service.pending_battle_mode)
	var previous_show_tutorial := bool(settings.get_value("show_tutorial"))
	settings.set_value("show_tutorial", false)
	game_service.pending_encounter_id = "boss_chapter_1"
	game_service.pending_room_id = "ui_old_mage_contract"
	game_service.pending_battle_mode = "normal"
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ctrl: BattleController = scene.get("_controller")
	var state: GameState = ctrl.state
	var mage := _find_old_mage(state)
	assert(mage != null, "boss UI contract should start with an old mage")
	assert(ctrl.get_tutorial_hint() != "", "boss encounter should expose a localized guidance hint")
	IntentSystem.refresh_unit_intent(state, mage)
	ctrl.selected_unit_uid = mage.uid
	var spell_highlights := ctrl.get_highlights()
	assert(_has_overlay_kind(spell_highlights, "danger"), "spell intent should expose a damage danger overlay")
	assert(mage.intent.preview_text.find("施法后销毁") >= 0, "spell warning should state that the cast gem is destroyed")
	IntentSystem.execute_intent(state, mage)
	IntentSystem.refresh_unit_intent(state, mage)
	var refill_highlights := ctrl.get_highlights()
	assert(_has_overlay_kind(refill_highlights, "intent_path"), "refill should expose pool candidate cells")
	assert(_has_overlay_kind(refill_highlights, "target"), "refill should expose the locked pool gem")
	mage.hp = 19
	assert(ctrl.get_tutorial_hint().find("终局") >= 0, "low HP phase should replace generic guidance")
	scene.call("_on_cell_clicked", mage.pos)
	await process_frame
	var stats: Label = scene.get("_inspect_stats")
	assert(stats.text.find("施法") >= 0 or stats.text.find("终末") >= 0, "old mage inspect panel should show phase state")
	var slot_box: Container = scene.get("_slot_box")
	var pool_chip_found := false
	for child in slot_box.get_children():
		if child is PanelContainer and str((child as Control).tooltip_text).find("技能池") >= 0:
			pool_chip_found = true
			break
	assert(pool_chip_found, "old mage inspect panel should show the seven-gem skill pool chip")
	var child_count_before := scene.get_child_count()
	scene.call("_show_old_mage_tutorial_intro")
	await process_frame
	assert(scene.get_child_count() == child_count_before + 1, "old mage encounter should open its tutorial overlay")
	var overlay := scene.get_child(scene.get_child_count() - 1) as ColorRect
	assert(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "old mage tutorial overlay should block battle input")
	overlay.queue_free()
	scene.queue_free()
	await process_frame
	game_service.pending_encounter_id = previous_encounter
	game_service.pending_room_id = previous_room
	game_service.pending_battle_mode = previous_mode
	settings.set_value("show_tutorial", previous_show_tutorial)
	print("  [OK] old mage guidance, warning, and inspect UI contract")


func _test_relic_bar_layout_compacts_before_scroll() -> void:
	var presenter := BattleHudPresenter.new()
	var medium := presenter._relic_bar_layout(5, 320.0)
	var medium_viewport: Vector2 = medium.get("viewport_size", Vector2.ZERO)
	assert(int(medium.get("columns", 0)) == 1, "medium relic count should stay vertical")
	assert(float(medium.get("icon_size", 0.0)) == 30.0, "readable relics should retain normal icon size")
	assert(medium_viewport.y <= 320.0, "medium relic layout should fit available rail height")
	var many := presenter._relic_bar_layout(8, 320.0)
	var many_viewport: Vector2 = many.get("viewport_size", Vector2.ZERO)
	assert(int(many.get("columns", 0)) == 1, "eight relics should stay vertical when screen height permits")
	assert(float(many.get("icon_size", 0.0)) >= 24.0, "relic icons must never collapse below readable size")
	assert(not bool(many.get("scroll", true)), "eight relics should fit without scrollbar at normal battle height")
	assert(many_viewport.y <= 320.0, "many relic layout should fit available rail height")
	var constrained := presenter._relic_bar_layout(8, 144.0)
	assert(int(constrained.get("columns", 0)) == 2, "short viewports should use multiple readable columns")
	assert(float(constrained.get("icon_size", 0.0)) == 24.0, "short viewports should stop shrinking at readable minimum")
	var constrained_content: Vector2 = constrained.get("content_size", Vector2.ZERO)
	assert(constrained_content.x >= 72.0, "multiple relic columns need enough separation to remain distinct")
	var overflow := presenter._relic_bar_layout(40, 144.0)
	assert(bool(overflow.get("scroll", false)), "scrolling should begin only after minimum-size columns overflow")
	var badge := presenter._create_relic_badge("relic_prism", 24.0)
	var icon: TextureRect = badge.get_node("RelicIcon")
	var hover_icon: TextureRect = badge.get_node("HoverTextureOutline")
	assert(icon.stretch_mode == TextureRect.STRETCH_SCALE, "relic textures must scale inside their fixed cell instead of overflowing")
	assert(icon.texture.get_size() == hover_icon.texture.get_size(), "normal and hovered relics must use the same padded canvas")
	assert(icon.position == hover_icon.position and icon.size == hover_icon.size, "normal and hovered relics must occupy the same rect")
	badge.free()
	print("  [OK] relic bar compacts before scroll")


func _test_battle_scene_click_inspect() -> void:
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	assert(packed != null, "battle scene should load")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ctrl: BattleController = scene.get("_controller")
	assert(ctrl != null and ctrl.state != null, "battle scene should start a controller")
	var guard := _find_unit_by_def(ctrl.state, "unit_patrol_guard")
	assert(guard != null, "guard should exist for click inspect")
	scene.call("_on_cell_clicked", guard.pos)
	await process_frame
	assert(str(scene.get("_inspect_uid")) == guard.uid, "clicking a unit should inspect that unit")
	var registry: Node = root.get_node("DataRegistry")
	var ground_gem: GemState = registry.create_gem_instance("ui_ground_extract", Constants.GEM_IMPACT, {})
	ctrl.state.gems[ground_gem.uid] = ground_gem
	assert(GemTransfer.to_ground(ctrl.state, ground_gem, guard.pos, {"source_unit_uid": guard.uid}))
	ctrl.select_action(Constants.ACTION_EXTRACT)
	scene.call("_on_cell_clicked", guard.pos)
	await process_frame
	var slot_popup: Control = scene.get("_slot_popup")
	assert(slot_popup.visible and bool(slot_popup.get("_is_dropped_mode")), "a ground gem under a living unit should open the ground picker")
	scene.call("_on_popup_dropped_gem_selected", ground_gem.uid)
	assert(ctrl.state.held_gem_uid == ground_gem.uid, "the ground picker should extract the selected gem into hand")
	var entity_cell := _first_empty_cell(ctrl.state)
	assert(entity_cell.x >= 0, "empty cell should exist for entity inspect")
	ctrl.state.add_entity(EntityState.create("ui_click_entity", Constants.ENTITY_BARREL, entity_cell))
	scene.call("_on_cell_clicked", entity_cell)
	await process_frame
	assert(str(scene.get("_inspect_uid")).is_empty(), "clicking an entity cell should clear unit inspect")
	assert(scene.get("_inspect_cell") == entity_cell, "clicking an entity cell should inspect the cell")
	var status_panel: Control = scene.get("_status_panel")
	var toggle_button: Control = scene.get("_toggle_panel_btn")
	var relic_root: Control = scene.get("_relic_bar_root")
	scene.set("_panel_visible", false)
	status_panel.visible = false
	scene.call("_layout_editor_ui")
	assert(
		relic_root.position.y >= toggle_button.position.y + toggle_button.size.y + 5.0,
		"folded status toggle must not overlap relic rail"
	)
	scene.queue_free()
	await process_frame
	print("  [OK] battle scene click inspect")


func _test_scavenger_hook_slot_panel_flow() -> void:
	root.get_node("GameService").set("pending_encounter_id", "tutorial_001")
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	assert(packed != null, "battle scene should load for scavenger hook UI")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ctrl: BattleController = scene.get("_controller")
	var state: GameState = ctrl.state
	var player := state.get_player()
	assert(player != null, "player should exist for scavenger hook UI")
	var target_slot := SlotState.create(Constants.SLOT_RED)
	player.slots.append(target_slot)
	var registry: Node = root.get_node("DataRegistry")
	var held: GemState = registry.create_gem_instance("hook_ui_held", Constants.GEM_POISON, {})
	var hooked: GemState = registry.create_gem_instance("hook_ui_hooked", Constants.GEM_EXPLOSION, {})
	state.gems[held.uid] = held
	state.gems[hooked.uid] = hooked
	assert(GemTransfer.to_hand(state, held, player.uid), "ordinary hand setup should succeed")
	assert(GemTransfer.to_hooked(state, hooked, player.uid), "hooked gem setup should coexist with the ordinary hand")
	ctrl.select_action(Constants.ACTION_INSERT_HOOKED)
	scene.call("_on_cell_clicked", player.pos)
	await process_frame
	var board: Control = scene.get("_board")
	var renderer: RefCounted = board.get("_slot_panel_renderer")
	assert(renderer != null, "clicking the unit in hook mode should create the slot panel renderer")
	var panel: Dictionary = renderer.call("_panel_layout", player, Callable(board, "_unit_panel_anchor"))
	var target_index := player.slots.find(target_slot)
	var target_item: Dictionary = panel.get("items", [])[target_index]
	assert(bool(target_item.get("visible", false)), "hook insert target slot should be visible in the unit panel")
	assert(bool(target_item.get("enabled", false)), "matching empty slot should be enabled for the hooked gem")
	scene.call("_on_board_unit_slot_selected", player.uid, target_index)
	assert(target_slot.gem_uid == hooked.uid, "slot-panel selection should embed the hooked gem")
	assert(state.relic_battle.hooked_gem_uid.is_empty(), "successful slot-panel insert should clear the hook")
	assert(state.held_gem_uid == held.uid, "hook insert should preserve the ordinary held gem")
	scene.queue_free()
	await process_frame
	print("  [OK] scavenger hook unit panel embeds while the ordinary hand is occupied")


func _test_battle_scene_consumes_queued_battle_end() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var game_service: Node = root.get_node("GameService")
	adventure_service.start_new_run(20260617)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	game_service.pending_encounter_id = "tutorial_001"
	game_service.pending_room_id = "ui_battle_end_room"
	game_service.adventure_return = true
	game_service.pending_battle_mode = "normal"
	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set("_enemy_phase_running", true)
	scene.call("_on_battle_ended", "win")
	assert(not bool(scene.get("_battle_end_applied")), "battle end should wait while enemy phase is running")
	scene.set("_enemy_phase_running", false)
	assert(bool(scene.call("_consume_pending_battle_end_if_any")), "queued battle end should be consumed after enemy phase")
	assert(bool(scene.get("_battle_end_applied")), "queued battle end should enter settlement")
	scene.queue_free()
	await process_frame
	run_service.end_run()
	game_service.reset_session_state()
	print("  [OK] battle scene consumes queued battle end")


func _test_rich_tooltip_has_body_height() -> void:
	var owner := Control.new()
	root.add_child(owner)
	var tooltip := RichTooltip.new()
	root.add_child(tooltip)
	await process_frame
	tooltip.show_for_control(owner, {
		"title": "行动",
		"subtitle": "回合资源",
		"sections": [{"title": "状态", "body": "本回合是否还能攻击、拔取或嵌入。"}],
	})
	await process_frame
	await process_frame
	var panel := tooltip.get_child(0) as PanelContainer
	var scroll := panel.get_child(0) as ScrollContainer
	assert(panel != null and panel.size.y > 40.0, "rich tooltip panel should not collapse to an empty frame")
	assert(scroll != null and scroll.custom_minimum_size.y > 0.0, "rich tooltip scroll should reserve content height")
	tooltip.queue_free()
	owner.queue_free()
	await process_frame
	print("  [OK] rich tooltip reserves body height")


func _test_battle_end_queue_take() -> void:
	var event_player := BattleEventPlayer.new()
	event_player.queue_battle_end("win")
	assert(event_player.take_pending_battle_end() == "win", "queued battle end should be consumable")
	assert(event_player.take_pending_battle_end().is_empty(), "queued battle end should be consumed only once")
	print("  [OK] battle end queue is consumable")


func _first_cell_after(cells: Array, origin: Vector2i) -> Vector2i:
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if cell != origin:
			return cell
	return Vector2i(-1, -1)


func _first_empty_cell(state: GameState) -> Vector2i:
	for y in range(state.board_size.y):
		for x in range(state.board_size.x):
			var cell := Vector2i(x, y)
			if state.get_unit_at(cell) == null and state.get_entity_at(cell) == null:
				return cell
	return Vector2i(-1, -1)


func _has_overlay_cell(highlights: Dictionary, kind: String, cell: Vector2i) -> bool:
	for raw_overlay in highlights.get("overlays", []):
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		if str(overlay.get("kind", "")) == kind and cell in overlay.get("cells", []):
			return true
	return false


func _find_route(highlights: Dictionary, kind: String) -> Dictionary:
	for raw_route in highlights.get("routes", []):
		if raw_route is Dictionary and str(raw_route.get("kind", "")) == kind:
			return raw_route
	return {}


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _find_old_mage(state: GameState) -> UnitState:
	for unit in state.get_alive_enemies():
		if unit.behavior_id == "old_mage":
			return unit
	return null


func _has_overlay_kind(highlights: Dictionary, kind: String) -> bool:
	for raw_overlay in highlights.get("overlays", []):
		if raw_overlay is Dictionary and str((raw_overlay as Dictionary).get("kind", "")) == kind:
			return true
	return false
