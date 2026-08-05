extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Battle Editor UI Test ===")
	var settings := root.get_node("SettingsService")
	var game_service := root.get_node("GameService")
	settings.set_value("battle_editor_enabled", true)
	game_service.start_editor_battle("tutorial_001")

	var packed := load("res://scenes/battle/battle_scene.tscn") as PackedScene
	assert(packed != null, "battle scene should load")
	var scene: Control = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var controller: BattleController = scene.get("_controller")
	assert(controller != null and controller.state != null, "editor battle should start")
	var status_panel: Control = scene.get("_status_panel")
	var queue_panel: Control = scene.get("_turn_queue_panel")
	var editor_panel: Control = scene.get("_editor_panel")
	var inspector: Control = scene.get("_editor_inspector")
	assert(editor_panel != null and editor_panel.visible, "editor catalog should be visible")
	assert(inspector != null and inspector.visible, "editor inspector should be visible")

	var status_height := status_panel.size.y
	controller.select_action(Constants.ACTION_ATTACK)
	scene.call("_refresh")
	await process_frame
	await process_frame
	assert(is_equal_approx(status_panel.size.y, status_height), "inspect card height must stay fixed during attack")
	assert(inspector.position.y >= queue_panel.position.y + queue_panel.size.y, "inspector must sit below turn order")
	assert(editor_panel.position.y >= 220.0, "editor dock must reserve the upper HUD lane")

	var player := controller.state.get_player()
	assert(player != null, "editor battle should have a player")
	var battle_end_count := 0
	controller.battle_ended.connect(func(_result: String) -> void: battle_end_count += 1)
	var hp_before := player.hp
	controller.set_editor_player_invincible(true)
	CombatRules.apply_damage(controller.state, player, 999, "editor_test", "editor_test")
	CombatRules.apply_true_damage(controller.state, player, 999, "editor_test", "editor_true_test")
	assert(player.alive and player.hp == hp_before, "player invincibility must block normal and true damage")
	controller.set_editor_player_invincible(false)

	var enemy := controller.state.get_alive_enemies()[0] as UnitState
	CombatRules.apply_true_damage(controller.state, enemy, enemy.hp + 999, "editor_test", "editor_enemy_death")
	controller._check_battle_end()
	assert(not enemy.alive, "editor enemy should be allowed to die")
	assert(controller.state.phase != Constants.PHASE_ENDED, "enemy death must not end editor battle")
	assert(controller.state.result.is_empty(), "enemy death must not create an editor result")

	var player_hp_before_death := player.hp
	CombatRules.apply_true_damage(controller.state, player, player_hp_before_death + 999, "editor_test", "editor_player_death")
	controller._check_battle_end()
	assert(not player.alive, "editor player should be allowed to die")
	assert(controller.state.phase != Constants.PHASE_ENDED, "player death must not end editor battle")
	assert(controller.state.result.is_empty(), "player death must not create an editor result")
	assert(battle_end_count == 0, "editor death must not emit battle_ended")
	assert(scene.is_inside_tree(), "editor scene must remain open after deaths")

	var clear_result: Dictionary = controller.run_editor_action("clear_enemies")
	assert(bool(clear_result.get("ok", false)), "clear enemies should succeed")
	assert(controller.state.get_alive_enemies().is_empty(), "clear enemies should remove all enemies")

	scene.call("_on_editor_encounter_requested", "rat_run")
	await process_frame
	await process_frame
	assert(controller.state.encounter_id == "rat_run", "editor should load the selected encounter")

	scene.queue_free()
	await process_frame
	print("BATTLE_EDITOR_UI_TEST_PASS")
	quit()
