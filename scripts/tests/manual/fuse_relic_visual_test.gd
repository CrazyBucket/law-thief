extends SceneTree

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

const OUTPUT_PATH := "res://artifacts/verify/fuse-relic-visual.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AdventureService").start_new_run(20260813)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_fuse")
	root.get_node("GameService").pending_encounter_id = "tutorial_001"
	var packed: PackedScene = load("res://scenes/battle/battle_scene.tscn")
	var battle_scene := packed.instantiate()
	root.add_child(battle_scene)
	await process_frame
	await process_frame
	var controller: BattleController = battle_scene.get("_controller")
	var state: GameState = controller.state
	var player := state.get_player()
	var slot := _first_slot(player, Constants.SLOT_RED)
	if slot == null:
		slot = SlotState.create(Constants.SLOT_RED)
		player.slots.append(slot)
	if slot.gem_uid.is_empty():
		var blocker: GemState = root.get_node("DataRegistry").create_gem_instance(
			"fuse_visual_blocker", Constants.GEM_EXPLOSION, {}
		)
		state.gems[blocker.uid] = blocker
		_require(GemTransfer.to_unit_slot(state, blocker, player, slot), "visual probe should fill its red slot")
	var gem: GemState = root.get_node("DataRegistry").create_gem_instance(
		"fuse_visual_gem", Constants.GEM_EXPLOSION, {}
	)
	state.gems[gem.uid] = gem
	_require(GemTransfer.to_hand(state, gem, player.uid), "visual probe should hold the overload gem")
	var result := GemRules.insert(state, player, player, slot, true)
	_require(bool(result.get("mutation_deferred", false)), "visual probe should trip fuse")
	OverloadRules.record_insert(state, true)
	OverloadRules.activate_pending(state)
	battle_scene.call("_refresh")
	await process_frame
	var overload_chip: Control = battle_scene.get("_overload_chip")
	overload_chip.mouse_entered.emit()
	await process_frame
	await process_frame
	_require("过载 1" in str(overload_chip.get("text")), "visual probe should project one overload layer")
	_require(str(battle_scene.get("_hud_presenter").call("_relic_badge_state_text", "relic_fuse")) == "待", "visual probe should project the pending fuse badge")
	if DisplayServer.get_name() == "headless":
		print("FUSE_RELIC_VISUAL_TEST_PASS headless_state_verified=true")
	else:
		var image := root.get_viewport().get_texture().get_image()
		_require(image != null and not image.is_empty(), "visual probe should capture the battle HUD")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/verify"))
		_require(image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH)) == OK, "visual probe should save its PNG")
		print("FUSE_RELIC_VISUAL_TEST_PASS path=%s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	battle_scene.queue_free()
	await process_frame
	root.get_node("RunService").end_run()
	quit(0)


func _first_slot(unit: UnitState, slot_type: String) -> SlotState:
	for slot: SlotState in unit.slots:
		if slot.accepts_slot_type(slot_type):
			return slot
	return null


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
