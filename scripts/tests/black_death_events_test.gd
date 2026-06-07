extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 12345)
	var state := ctrl.state
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "missing guard")
	var gem := GemState.new()
	gem.uid = "black_death_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	guard.get_slot(Constants.SLOT_BLACK).gem_uid = gem.uid
	guard.hp = 1
	ctrl.select_action(Constants.ACTION_ATTACK)
	var res := ctrl.try_attack_cell(guard.pos)
	assert(res.get("ok", false), "attack should succeed")
	var events: Array = res.get("attack_events", [])
	var explode_count := 0
	var damage_count := 0
	for ev in events:
		match str(ev.get("type", "")):
			"explode":
				explode_count += 1
			"damage":
				damage_count += 1
	assert(explode_count >= 1, "black death should emit explode, got %d events: %s" % [explode_count, _summarize(events)])
	assert(damage_count >= 1, "black death should emit damage, got %d" % damage_count)
	print("BLACK_DEATH_EVENTS_TEST_PASS explode=%d damage=%d" % [explode_count, damage_count])
	quit()


func _summarize(events: Array) -> String:
	var parts: Array[String] = []
	for ev in events:
		parts.append(str(ev.get("type", "")))
	return ", ".join(parts)
