extends SceneTree

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const SwapRules = preload("res://scripts/rules/swap_rules.gd")

const OUTPUT_PATH := "res://artifacts/verify/swap-relic-visual.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AdventureService").start_new_run(20260813)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_swap")
	root.get_node("GameService").pending_encounter_id = "tutorial_001"
	var packed: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	var battle_scene := packed.instantiate()
	root.add_child(battle_scene)
	await process_frame
	await process_frame
	var controller: BattleController = battle_scene.get("_controller")
	var state: GameState = controller.state
	var player := state.get_player()
	var enemy := _first_enemy(state)
	_require(enemy != null, "visual probe needs one enemy")
	var player_index := _ensure_gem(state, player, Constants.SLOT_RED, "swap_visual_player", Constants.GEM_EXPLOSION)
	var enemy_index := _ensure_gem(state, enemy, Constants.SLOT_BLUE, "swap_visual_enemy", Constants.GEM_POISON)
	IntentSystem.refresh_all_intents(state)
	battle_scene.call("_refresh")
	await process_frame
	var button := _swap_button(battle_scene)
	_require(button != null and not button.disabled, "swap relic button should be available")
	button.pressed.emit()
	_require(controller.selected_action == Constants.ACTION_RELIC_SWAP, "button click should enter swap mode")
	battle_scene.call("_on_cell_clicked", player.pos)
	await process_frame
	var popup: Control = battle_scene.get("_slot_popup")
	_require(popup.visible, "clicking the first unit should open its slot panel")
	_require("第一颗" in str(popup.get("_title_label").text), "first panel should ask for the first gem")
	_require((popup.get("_context_label") as Label).visible, "swap should use its dedicated two-stage context panel")
	battle_scene.call("_on_popup_slot_selected", player.uid, player_index)
	_require(controller.has_swap_source() and not popup.visible, "first gem click should store the source and close the panel")
	battle_scene.call("_on_cell_clicked", enemy.pos)
	await process_frame
	_require(popup.visible, "clicking the second unit should open its slot panel")
	_require("第二颗" in str(popup.get("_title_label").text), "second panel should ask for the second gem")
	_require((popup.get("_context_label") as Label).text.contains("已选"), "second swap panel should show the first selected gem")
	if DisplayServer.get_name() != "headless":
		var image := root.get_viewport().get_texture().get_image()
		_require(image != null and not image.is_empty(), "visual probe should capture the second-gem panel")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/verify"))
		_require(image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH)) == OK, "visual probe should save its PNG")
	var first_uid := str(player.slots[player_index].gem_uid)
	var second_uid := str(enemy.slots[enemy_index].gem_uid)
	battle_scene.call("_on_popup_slot_selected", enemy.uid, enemy_index)
	await process_frame
	_require(player.slots[player_index].gem_uid == second_uid and enemy.slots[enemy_index].gem_uid == first_uid, "second gem click should immediately exchange both gems")
	_require(controller.selected_action == Constants.ACTION_NONE and SwapRules.was_used_this_turn(state), "completed swap should exit mode and consume the turn use")
	_require(button.disabled, "used swap relic button should be dimmed and disabled")
	if DisplayServer.get_name() == "headless":
		print("SWAP_RELIC_VISUAL_TEST_PASS headless_flow_verified=true")
	else:
		print("SWAP_RELIC_VISUAL_TEST_PASS path=%s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	battle_scene.queue_free()
	await process_frame
	root.get_node("RunService").end_run()
	quit(0)


func _first_enemy(state: GameState) -> UnitState:
	for unit: UnitState in state.units.values():
		if unit.alive and unit.team == Constants.TEAM_ENEMY:
			return unit
	return null


func _ensure_gem(state: GameState, unit: UnitState, slot_type: String, uid: String, gem_id: String) -> int:
	var slot: SlotState = null
	for candidate: SlotState in unit.slots:
		if candidate.accepts_slot_type(slot_type):
			slot = candidate
			break
	if slot == null:
		slot = SlotState.create(slot_type)
		unit.slots.append(slot)
	if not slot.gem_uid.is_empty():
		GemTransfer.remove(state, slot.gem_uid)
	var gem: GemState = root.get_node("DataRegistry").create_gem_instance(uid, gem_id, {})
	state.gems[gem.uid] = gem
	_require(GemTransfer.to_unit_slot(state, gem, unit, slot), "visual probe should mount a real gem")
	return unit.slots.find(slot)


func _swap_button(battle_scene: Node) -> Button:
	var grid: Container = battle_scene.get("_relic_bar_vbox")
	for child in grid.get_children():
		if str(child.get_meta("relic_id", "")) == "relic_swap":
			return child.get_node_or_null("RelicButton") as Button
	return null


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
