extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Level Context Test ===")
	_test_effect_level_config_lookup()
	_test_blue_poison_contact_uses_level_config()
	_test_blue_pillar_poison_uses_level_config()
	_test_blue_pillar_explosion_uses_level_config()
	_test_blue_pillar_gravity_uses_level_config()
	_test_poison_red_level_two_cross_fog()
	_test_fire_poison_combo_creates_toxic_smoke()
	_test_ice_red_level_three_freezes_slowed_target()
	_test_gravity_black_level_three_roots_nearby_units()
	if _failed:
		push_error("GEM_LEVEL_CONTEXT_TEST_FAIL")
		quit(1)
		return
	print("GEM_LEVEL_CONTEXT_TEST_PASS")
	quit(0)


func _test_effect_level_config_lookup() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var explosion_l3: Dictionary = reg.get_gem_effect_level_def("explosion", Constants.SLOT_RED, 3)
	_expect(str(explosion_l3.get("blast_pattern", "")) == "square", "explosion level 3 should use square blast config")
	_expect(int(explosion_l3.get("damage_multiplier", 0)) == 2, "explosion level 3 should double damage in config")
	var light_l2: Dictionary = reg.get_gem_effect_level_def("light", Constants.SLOT_RED, 2)
	_expect(abs(float(light_l2.get("damage_ratio", 0.0)) - 0.75) < 0.001, "light level 2 damage ratio should come from config")
	var echo_l4: Dictionary = reg.get_gem_effect_level_def("echo", Constants.SLOT_RED, 4)
	_expect(abs(float(echo_l4.get("followup_ratio", 0.0)) - 0.5) < 0.001, "effect level lookup should fall back to highest defined tier")
	var blue_counter_l3: Dictionary = reg.get_gem_effect_level_def("counter", Constants.SLOT_BLUE, 3)
	_expect(bool(blue_counter_l3.get("grant_extra_move_on_kill", false)), "blue counter level 3 should grant extra move via config")
	var blue_poison_l1: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_BLUE, 1)
	_expect(int(blue_poison_l1.get("contact_poison_stacks", 0)) == 1, "blue poison should define contact poison stacks")
	_expect(int(blue_poison_l1.get("turn_end_poison_duration", 0)) == 2, "blue poison should define turn-end poison duration")
	_expect(int(blue_poison_l1.get("pillar_radius", 0)) == 2, "blue poison should define pillar radius")
	var red_poison_l1: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_RED, 1)
	_expect(int(red_poison_l1.get("hit_poison_stacks", 0)) == 1, "red poison should define hit poison stacks")
	_expect(int(red_poison_l1.get("hit_poison_duration", -1)) == 0, "red poison should define hit poison duration")
	var blue_explosion_l1: Dictionary = reg.get_gem_effect_level_def("explosion", Constants.SLOT_BLUE, 1)
	_expect(int(blue_explosion_l1.get("pillar_damage", 0)) == 1, "blue explosion should define pillar damage")
	var blue_gravity_l1: Dictionary = reg.get_gem_effect_level_def("gravity", Constants.SLOT_BLUE, 1)
	_expect(int(blue_gravity_l1.get("pillar_pull_radius", 0)) == 2, "blue gravity should define pillar pull radius")
	var black_split_l2: Dictionary = reg.get_gem_effect_level_def("split", Constants.SLOT_BLACK, 2)
	_expect(abs(float(black_split_l2.get("stat_ratio", 0.0)) - 0.5) < 0.001, "black split level 2 stat ratio should come from config")
	var black_poison_l3: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_BLACK, 3)
	_expect(int(black_poison_l3.get("debuff_spread_radius", 0)) == 1, "black poison should define debuff spread radius")
	var black_light_l3: Dictionary = reg.get_gem_effect_level_def("light", Constants.SLOT_BLACK, 3)
	_expect(bool(black_light_l3.get("blind_on_survive", false)), "black light level 3 should define blind-on-survive in config")
	print("  [OK] effect level config lookup")


func _test_blue_poison_contact_uses_level_config() -> void:
	var state := _create_state()
	var player := state.get_player()
	var target := _spawn_guard(state, Vector2i(5, 3), "blue_poison_contact_target")
	_mount_gems(state, player, Constants.SLOT_BLUE, [Constants.GEM_POISON])
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var level_def: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_BLUE, 1)
	ContactResolver.on_attack_contact(state, player, target)
	var poison := target.get_status(Constants.STATUS_POISON)
	_expect(poison != null, "blue poison contact should apply poison")
	_expect(poison.stacks == int(level_def.get("contact_poison_stacks", 1)), "blue poison contact stacks should come from config")
	_expect(poison.duration == int(level_def.get("contact_poison_duration", 0)), "blue poison contact duration should come from config")
	print("  [OK] blue poison contact uses level config")


func _test_blue_pillar_poison_uses_level_config() -> void:
	var state := _create_state("template_a")
	var pillar := state.get_tile(Vector2i(7, 5))
	_mount_tile_gem(state, pillar, Constants.GEM_POISON)
	var target := _spawn_guard(state, Vector2i(5, 5), "pillar_poison_target")
	var far_target := _spawn_guard(state, Vector2i(4, 5), "pillar_poison_far_target")
	var events: Array[Dictionary] = []
	var ok := GemEffects.trigger_tile_gem(state, pillar, pillar.slots[0], events)
	_expect(ok, "pillar poison trigger should succeed")
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var level_def: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_BLUE, 1)
	var poison := target.get_status(Constants.STATUS_POISON)
	_expect(poison != null, "pillar poison should affect target within configured radius")
	_expect(poison.stacks == int(level_def.get("pillar_poison_stacks", 1)), "pillar poison stacks should come from config")
	_expect(poison.duration == int(level_def.get("pillar_poison_duration", 2)), "pillar poison duration should come from config")
	_expect(far_target.get_status(Constants.STATUS_POISON) == null, "pillar poison should not affect target outside configured radius")
	var burst := _first_event(events, "poison_burst")
	_expect(int(burst.get("radius", -1)) == int(level_def.get("pillar_radius", 0)), "pillar poison event radius should come from config")
	print("  [OK] blue pillar poison uses level config")


func _test_blue_pillar_explosion_uses_level_config() -> void:
	var state := _create_state("template_a")
	var pillar := state.get_tile(Vector2i(7, 5))
	_mount_tile_gem(state, pillar, Constants.GEM_EXPLOSION)
	var target := _spawn_guard(state, Vector2i(6, 5), "pillar_explosion_target")
	var far_target := _spawn_guard(state, Vector2i(5, 5), "pillar_explosion_far_target")
	var hp_before := target.hp
	var far_hp_before := far_target.hp
	var events: Array[Dictionary] = []
	var ok := GemEffects.trigger_tile_gem(state, pillar, pillar.slots[0], events)
	_expect(ok, "pillar explosion trigger should succeed")
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var level_def: Dictionary = reg.get_gem_effect_level_def("explosion", Constants.SLOT_BLUE, 1)
	_expect(hp_before - target.hp == int(level_def.get("pillar_damage", 1)), "pillar explosion damage should come from config")
	_expect(far_target.hp == far_hp_before, "pillar explosion should not affect target outside configured radius")
	var explode := _first_event(events, "explode")
	_expect(int(explode.get("radius", -1)) == int(level_def.get("pillar_radius", 0)), "pillar explosion event radius should come from config")
	print("  [OK] blue pillar explosion uses level config")


func _test_blue_pillar_gravity_uses_level_config() -> void:
	var state := _create_state("template_a")
	var pillar := state.get_tile(Vector2i(7, 5))
	_mount_tile_gem(state, pillar, Constants.GEM_GRAVITY)
	var target := _spawn_guard(state, Vector2i(5, 5), "pillar_gravity_target")
	var far_target := _spawn_guard(state, Vector2i(4, 5), "pillar_gravity_far_target")
	var events: Array[Dictionary] = []
	var ok := GemEffects.trigger_tile_gem(state, pillar, pillar.slots[0], events)
	_expect(ok, "pillar gravity trigger should succeed")
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var level_def: Dictionary = reg.get_gem_effect_level_def("gravity", Constants.SLOT_BLUE, 1)
	_expect(target.pos == Vector2i(5, 5) + Vector2i(int(level_def.get("pillar_pull_steps", 1)), 0), "pillar gravity pull steps should come from config")
	_expect(far_target.pos == Vector2i(4, 5), "pillar gravity should not affect target outside configured radius")
	print("  [OK] blue pillar gravity uses level config")


func _test_poison_red_level_two_cross_fog() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_POISON, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3), "poison_cross_target")
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "poison level 2 attack should succeed")
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var level_def: Dictionary = reg.get_gem_effect_level_def("poison", Constants.SLOT_RED, 2)
	var poison := target.get_status(Constants.STATUS_POISON)
	_expect(poison != null, "poison level 2 attack should poison the target")
	_expect(poison.stacks >= int(level_def.get("hit_poison_stacks", 1)), "poison hit stacks should include the configured hit poison amount")
	_expect(poison.duration == int(level_def.get("hit_poison_duration", 0)), "poison hit duration should come from config")
	for cell in [target.pos, target.pos + Vector2i.LEFT, target.pos + Vector2i.RIGHT, target.pos + Vector2i.UP, target.pos + Vector2i.DOWN]:
		var tile := state.get_tile(cell)
		_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_POISON_FOG), "poison level 2 should fog %s" % [cell])
	print("  [OK] poison red level 2 cross fog")


func _test_fire_poison_combo_creates_toxic_smoke() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_FIRE, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3), "toxic_smoke_target")
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "fire + poison attack should succeed")
	var tile := state.get_tile(target.pos)
	_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE), "fire + poison should create toxic smoke")
	_expect(_count_events(result.get("events", []), "toxic_smoke") > 0, "fire + poison should emit toxic smoke event")
	print("  [OK] fire + poison creates toxic smoke")


func _test_ice_red_level_three_freezes_slowed_target() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_ICE, Constants.GEM_ICE, Constants.GEM_ICE])
	var target := _spawn_guard(state, Vector2i(5, 3), "ice_freeze_target")
	StatusRules.apply_slowed(state, target, 1, player.uid)
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "ice level 3 attack should succeed")
	_expect(target.has_status(Constants.STATUS_PARALYZED), "ice level 3 should freeze slowed target")
	print("  [OK] ice red level 3 freezes slowed target")


func _test_gravity_black_level_three_roots_nearby_units() -> void:
	var state := _create_state()
	var owner := _spawn_guard(state, Vector2i(4, 4), "gravity_black_owner")
	var victim := _spawn_guard(state, Vector2i(5, 4), "gravity_black_victim")
	_mount_gems(state, owner, Constants.SLOT_BLACK, [Constants.GEM_GRAVITY, Constants.GEM_GRAVITY, Constants.GEM_GRAVITY])
	var hp := owner.hp
	CombatRules.apply_damage(state, owner, hp, "", "test_kill")
	_expect(not owner.alive, "gravity black owner should die")
	_expect(victim.has_status(Constants.STATUS_ROOTED), "gravity black level 3 should root nearby units")
	print("  [OK] gravity black level 3 roots nearby units")


func _create_state(encounter_id: String = "fission_slime_test") -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state(encounter_id, 27182)
	for uid in state.units.keys():
		var unit: UnitState = state.units[uid]
		if unit.team == Constants.TEAM_ENEMY:
			state.unregister_unit(unit)
	var player := state.get_player()
	for slot in player.slots:
		slot.gem_uid = ""
	return state


func _mount_gems(state: GameState, unit: UnitState, slot_type: String, gem_ids: Array[String]) -> void:
	while unit.slots_accepting(slot_type).size() < gem_ids.size():
		unit.slots.append(SlotState.create(slot_type))
	var slots := unit.slots_accepting(slot_type)
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for i in range(gem_ids.size()):
		var slot: SlotState = slots[i]
		var gem_uid: String = reg.next_runtime_uid("level_gem")
		var gem := GemState.create(gem_uid, gem_ids[i], {})
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid


func _mount_tile_gem(state: GameState, tile: TileState, gem_id: String, slot_index: int = 0) -> void:
	var slot := tile.get_slot_by_index(slot_index)
	_expect(slot != null, "tile slot should exist for mounted gem")
	if slot == null:
		return
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("tile_gem")
	var gem := GemState.create(gem_uid, gem_id, {})
	gem.slot_index = slot_index
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid


func _spawn_guard(state: GameState, pos: Vector2i, uid: String) -> UnitState:
	var guard := UnitState.new()
	guard.uid = uid
	guard.unit_def_id = "unit_patrol_guard"
	guard.team = Constants.TEAM_ENEMY
	guard.pos = pos
	guard.hp = 50
	guard.max_hp = 50
	guard.speed = 5
	guard.base_attack = 4
	guard.alive = true
	state.register_unit(guard)
	return guard


func _count_events(events: Array, event_type: String) -> int:
	var total := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			total += 1
	return total


func _first_event(events: Array, event_type: String) -> Dictionary:
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			return ev
	return {}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
