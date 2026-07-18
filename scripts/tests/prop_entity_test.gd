extends SceneTree

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Prop Entity Test ===")
	_test_prop_blocks_movement()
	_test_prop_blocks_projectile()
	_test_prop_indestructible()
	_test_barrel_blocks_movement_and_projectile()
	_test_barrel_has_hp_and_explodes_on_ranged_hit()
	_test_player_manual_attack_can_destroy_barrel()
	_test_red_explosion_can_destroy_barrel()
	_test_light_beam_can_destroy_barrel()
	if _failed:
		push_error("PROP_ENTITY_TEST_FAIL")
		quit(1)
		return
	print("PROP_ENTITY_TEST_PASS")
	quit(0)


func _test_prop_blocks_movement() -> void:
	var state := _mini_state()
	var prop := EntityState.create("prop_a", Constants.ENTITY_PROP, Vector2i(3, 3))
	prop.prop_sprite = "Post1_0"
	state.add_entity(prop)
	_expect(not BoardUtils.is_passable(state, prop.pos), "prop cell should block movement")
	print("  [OK] prop blocks movement")


func _test_prop_blocks_projectile() -> void:
	var state := _mini_state()
	var prop := EntityState.create("prop_b", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	var from := Vector2i(1, 2)
	var aim := Vector2i(5, 2)
	_expect(
		BoardUtils.projectile_blocked_before_aim(state, from, aim),
		"projectile should stop at prop before aim"
	)
	var impact := BoardUtils.resolve_projectile_impact(state, from, aim)
	_expect(impact == prop.pos, "impact should be prop cell, got %s" % impact)
	print("  [OK] prop blocks projectile")


func _test_prop_indestructible() -> void:
	var prop := EntityState.create("test_prop", Constants.ENTITY_PROP, Vector2i(0, 0))
	_expect(prop.take_damage(99) == 0, "prop should ignore damage")
	_expect(prop.alive, "prop should stay alive")
	print("  [OK] prop is indestructible")


func _test_barrel_blocks_movement_and_projectile() -> void:
	var state := _mini_state()
	var barrel := EntityState.create("barrel_a", Constants.ENTITY_BARREL, Vector2i(3, 3))
	state.add_entity(barrel)
	_expect(barrel.max_hp == CombatConfig.barrel_hp() and barrel.hp == CombatConfig.barrel_hp(), "barrel should start with hp")
	_expect(not BoardUtils.is_passable(state, barrel.pos), "barrel cell should block movement")
	_expect(
		BoardUtils.projectile_blocked_before_aim(state, Vector2i(1, 3), Vector2i(5, 3)),
		"barrel should block projectile before aim"
	)
	_expect(
		BoardUtils.resolve_projectile_impact(state, Vector2i(1, 3), Vector2i(5, 3)) == barrel.pos,
		"barrel should be projectile impact cell"
	)
	print("  [OK] barrel blocks movement and projectile")


func _test_barrel_has_hp_and_explodes_on_ranged_hit() -> void:
	var state := _mini_state()
	var attacker := UnitState.new()
	attacker.uid = "attacker"
	attacker.team = Constants.TEAM_PLAYER
	attacker.pos = Vector2i(1, 3)
	attacker.hp = 20
	attacker.max_hp = 20
	attacker.base_attack = CombatConfig.barrel_hp()
	attacker.alive = true
	state.register_unit(attacker)
	var victim := UnitState.new()
	victim.uid = "victim"
	victim.team = Constants.TEAM_ENEMY
	victim.pos = Vector2i(4, 3)
	victim.hp = 20
	victim.max_hp = 20
	victim.alive = true
	state.register_unit(victim)
	var barrel := EntityState.create("barrel_b", Constants.ENTITY_BARREL, Vector2i(3, 3))
	state.add_entity(barrel)
	var result := CombatRules.ranged_attack(state, attacker, victim.pos)
	_expect(result.get("ok", false), "ranged attack toward barrel lane should succeed")
	_expect(not barrel.alive and barrel.hp == 0, "barrel should be destroyed by the shot")
	_expect(victim.hp < 20, "barrel explosion should damage the unit behind it")
	_expect((result.get("events", []) as Array).any(func(ev): return str(ev.get("type", "")) == "explode"), "barrel hit should emit explode event")
	print("  [OK] barrel has hp and explodes on ranged hit")


func _test_player_manual_attack_can_destroy_barrel() -> void:
	var controller := BattleController.new()
	controller.start_encounter("burning_storehouse", 20260715)
	var barrel := controller.state.get_entity_at(Vector2i(2, 5))
	_expect(barrel != null and barrel.entity_id == Constants.ENTITY_BARREL, "manual attack fixture should contain the nearby barrel")
	controller.select_action(Constants.ACTION_ATTACK)
	var result := controller.try_attack_cell(barrel.pos)
	_expect(result.get("ok", false), "manual attack aimed at a barrel should succeed")
	_expect(not barrel.alive and barrel.hp == 0, "manual attack should destroy the aimed barrel")
	_expect((result.get("attack_events", []) as Array).any(func(ev): return str(ev.get("type", "")) == "explode"), "manual barrel destruction should emit an explosion")
	print("  [OK] player manual attack can destroy barrel")


func _test_red_explosion_can_destroy_barrel() -> void:
	var controller := BattleController.new()
	controller.start_encounter("burning_storehouse", 20260718)
	var state := controller.state
	var player := state.get_player()
	var barrel := state.get_entity_at(Vector2i(2, 5))
	var red_slot := player.get_slot(Constants.SLOT_RED)
	if not red_slot.gem_uid.is_empty():
		GemTransfer.remove(state, red_slot.gem_uid)
	var explosion_gem := GemState.create("barrel_explosion_gem", Constants.GEM_EXPLOSION)
	state.gems[explosion_gem.uid] = explosion_gem
	_expect(GemTransfer.to_unit_slot(state, explosion_gem, player, red_slot), "explosion barrel fixture should mount its red gem")
	controller.select_action(Constants.ACTION_ATTACK)
	var result := controller.try_attack_cell(barrel.pos)
	_expect(result.get("ok", false), "red explosion aimed at a barrel should succeed")
	_expect(not barrel.alive and barrel.hp == 0, "red explosion should damage and destroy the barrel")
	print("  [OK] red explosion can destroy barrel")


func _test_light_beam_can_destroy_barrel() -> void:
	var controller := BattleController.new()
	controller.start_encounter("burning_storehouse", 20260716)
	var state := controller.state
	var player := state.get_player()
	var barrel := state.get_entity_at(Vector2i(2, 5))
	var red_slot := player.get_slot(Constants.SLOT_RED)
	if not red_slot.gem_uid.is_empty():
		GemTransfer.remove(state, red_slot.gem_uid)
	var light_gem := GemState.create("barrel_light_gem", Constants.GEM_LIGHT)
	state.gems[light_gem.uid] = light_gem
	_expect(GemTransfer.to_unit_slot(state, light_gem, player, red_slot), "light barrel fixture should mount its red gem")
	controller.select_action(Constants.ACTION_ATTACK)
	var result := controller.try_attack_cell(barrel.pos)
	_expect(result.get("ok", false), "light beam aimed at a barrel should succeed")
	_expect(not barrel.alive and barrel.hp == 0, "light beam should damage and destroy a blocking barrel")
	_expect((result.get("attack_events", []) as Array).any(func(ev): return str(ev.get("type", "")) == "entity_destroyed" and str(ev.get("uid", "")) == barrel.uid), "barrel destruction should have an explicit presentation event")
	print("  [OK] light beam can destroy barrel")


func _mini_state() -> GameState:
	var state := GameState.new()
	state.board_size = Vector2i(8, 8)
	for y in range(8):
		for x in range(8):
			var pos := Vector2i(x, y)
			state.tiles[state.tile_key(pos)] = TileState.create(pos, Constants.TILE_FLOOR)
	return state


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
