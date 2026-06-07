extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 42)
	var victim := UnitState.new()
	victim.uid = "victim"
	victim.unit_def_id = "unit_patrol_guard"
	victim.team = Constants.TEAM_ENEMY
	victim.pos = Vector2i(3, 3)
	victim.hp = 1
	victim.max_hp = 20
	victim.alive = true
	for slot_type in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]:
		var slot := SlotState.new()
		slot.slot_type = slot_type
		victim.slots.append(slot)
	state.register_unit(victim)
	var gem := GemState.new()
	gem.uid = "explosion_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	victim.get_slot(Constants.SLOT_BLACK).gem_uid = gem.uid
	var events: Array[Dictionary] = []
	CombatRules.begin_deferred_death_hooks(events)
	CombatRules.apply_damage(state, victim, 10, "player", "test")
	CombatRules.end_deferred_death_hooks(state)
	var types: Array[String] = []
	for ev in events:
		types.append(str(ev.get("type", "")))
	print("DEFERRED_DEATH_SINK types=%s" % ", ".join(types))
	assert(types.has("explode"), "expected explode in deferred sink")
	print("DEFERRED_DEATH_SINK_TEST_PASS")
	quit()
