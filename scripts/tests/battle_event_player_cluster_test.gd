extends SceneTree


class DummyBoard:
	var explosions: Array = []
	var flashes: Array = []
	var light_beam_batches: Array = []
	var projectile_batches: Array = []
	var lightning_bolts: Array = []
	var damage_effects: Array = []
	var parallel_moves: Array = []
	var impact_charges: Array = []
	var hit_units: Array[String] = []
	var operations: Array[String] = []
	var redraw_count: int = 0
	var electrical_timing := {"duration": 0.0, "impact_time": 0.0}

	func play_explosion(pos: Vector2i) -> void:
		explosions.append(pos)
		operations.append("explode")

	func play_explosion_batch(events: Array) -> Dictionary:
		for event in events:
			play_explosion(event.get("pos", Vector2i.ZERO))
		return {"duration": 0.0, "impact_time": 0.0}

	func play_gem_flash(pos: Vector2i, _gem_color: Color) -> void:
		flashes.append(pos)

	func play_light_beams(beams: Array) -> float:
		light_beam_batches.append(beams.duplicate(true))
		operations.append("light_beam")
		return 0.0

	func play_projectiles_task(shots: Array) -> void:
		projectile_batches.append(shots.duplicate(true))
		operations.append("projectile_volley")

	func play_lightning_bolt(from_pos: Vector2i, to_pos: Vector2i) -> void:
		lightning_bolts.append({"from": from_pos, "to": to_pos})
		operations.append("arc")

	func play_lightning_strike(pos: Vector2i) -> void:
		lightning_bolts.append({"from": pos, "to": pos})
		operations.append("arc")

	func play_electrical_batch(events: Array) -> Dictionary:
		for event in events:
			var from_pos: Vector2i = event.get("from", event.get("pos", Vector2i.ZERO))
			var to_pos: Vector2i = event.get("target_pos", event.get("pos", from_pos))
			if from_pos == to_pos:
				play_lightning_strike(to_pos)
			else:
				play_lightning_bolt(from_pos, to_pos)
		return electrical_timing.duplicate()

	func play_damage_effect(pos: Vector2i, damage: int, _is_crit: bool) -> void:
		damage_effects.append({"pos": pos, "damage": damage})
		operations.append("damage")

	func animate_unit_motions_parallel(moves: Array) -> float:
		parallel_moves.append(moves.duplicate(true))
		operations.append("move")
		return 0.0

	func play_impact_charge(event: Dictionary, motions: Array) -> Dictionary:
		impact_charges.append({"event": event.duplicate(true), "motions": motions.duplicate(true)})
		operations.append("impact_charge")
		return {"duration": 0.0, "impact_time": 0.0}

	func play_unit_hit(uid: String) -> void:
		hit_units.append(uid)

	func queue_redraw() -> void:
		redraw_count += 1


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Battle Event Player Cluster Test ===")
	var host := Node.new()
	root.add_child(host)
	var board := DummyBoard.new()
	var player := BattleEventPlayer.new()
	var requested_anim_delays: Array[float] = []
	player.setup(host, board, null, Callable(), func(seconds: float) -> float:
		requested_anim_delays.append(seconds)
		return 0.0
	)
	await player.play_events([
		{"type": "explode", "pos": Vector2i(4, 4)},
		{"type": "damage", "pos": Vector2i(4, 5), "damage": 3, "uid": "missing_target", "victim_uid": "missing_target", "is_crit": false},
		{"type": "move_step", "uid": "missing_target", "from": Vector2i(4, 5), "to": Vector2i(4, 6)},
		{"type": "displacement_impact", "uid": "missing_target", "from": Vector2i(4, 6), "contact": Vector2i(4, 7)},
		{"type": "split_spawn", "pos": Vector2i(4, 5), "uid": "missing_clone"},
	])
	assert(board.explosions.size() == 1, "blast cluster should play the explosion")
	assert(board.flashes.size() == 1, "split spawn should be presented inside the blast cluster")
	assert(board.flashes[0] == Vector2i(4, 5), "split spawn flash should use the clone position")
	assert(board.parallel_moves.size() == 1, "blast knockback should start as one parallel impact motion")
	assert(board.parallel_moves[0].size() == 2, "movement and blocked contact should use one motion sequence")
	assert(board.hit_units == ["missing_target"], "every damage event should trigger the unit hit presentation")
	assert(board.operations == ["explode", "damage", "move"], "blast damage and knockback must start together at impact")
	board.operations.clear()
	await player.play_events([
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(5, 1)},
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(4, 0)},
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(4, 2)},
		{"type": "damage", "pos": Vector2i(5, 1), "damage": 3, "uid": "missing_a", "victim_uid": "missing_a", "is_crit": false},
	])
	assert(board.projectile_batches.size() == 1, "split projectiles should use one volley task")
	assert(board.projectile_batches[0].size() == 3, "the volley should start all three projectiles together")
	assert(board.operations == ["projectile_volley", "damage"], "projectile damage must wait for the volley impact")
	board.operations.clear()
	await player.play_events([
		{"type": "impact_charge", "uid": "roller", "from": Vector2i(1, 3), "to": Vector2i(3, 3), "target_pos": Vector2i(4, 3)},
		{"type": "move_step", "uid": "roller", "from": Vector2i(1, 3), "to": Vector2i(2, 3)},
		{"type": "move_step", "uid": "roller", "from": Vector2i(2, 3), "to": Vector2i(3, 3)},
		{"type": "damage", "pos": Vector2i(4, 3), "damage": 6, "uid": "impact_target", "victim_uid": "impact_target", "is_crit": false},
		{"type": "move_step", "uid": "impact_target", "from": Vector2i(4, 3), "to": Vector2i(5, 3)},
	])
	assert(board.impact_charges.size() == 1 and board.impact_charges[0].motions.size() == 2)
	assert(board.operations == ["impact_charge", "damage", "move"], "impact damage and knockback must start at the charge impact frame")
	board.operations.clear()
	await player.play_events([
		{"type": "impact_charge", "uid": "roller", "from": Vector2i(2, 3), "to": Vector2i(4, 3), "target_pos": Vector2i(5, 3)},
		{"type": "move_step", "uid": "roller", "from": Vector2i(2, 3), "to": Vector2i(3, 3)},
		{"type": "move_step", "uid": "roller", "from": Vector2i(3, 3), "to": Vector2i(4, 3)},
		{"type": "damage", "pos": Vector2i(5, 3), "damage": 4, "uid": "impact_target", "victim_uid": "impact_target", "is_crit": false},
		{"type": "move_step", "uid": "impact_target", "from": Vector2i(5, 3), "to": Vector2i(6, 3)},
	])
	assert(board.operations == ["impact_charge", "damage", "move"], "a follow-up impact must replay charge before its own damage and knockback")
	board.operations.clear()
	await player.play_events([
		{"type": "arc", "from": Vector2i(3, 3), "pos": Vector2i(3, 3), "target_pos": Vector2i(5, 1)},
		{"type": "arc", "from": Vector2i(3, 3), "pos": Vector2i(3, 3), "target_pos": Vector2i(5, 3)},
		{"type": "damage", "pos": Vector2i(5, 1), "damage": 2, "uid": "missing_arc_a", "victim_uid": "missing_arc_a", "is_crit": false},
		{"type": "damage", "pos": Vector2i(5, 3), "damage": 2, "uid": "missing_arc_b", "victim_uid": "missing_arc_b", "is_crit": false},
	])
	assert(board.lightning_bolts.size() == 2, "same-hop arcs should start as one parallel beat")
	assert(board.operations == ["arc", "arc", "damage", "damage"], "arc visuals must precede their impact damage")
	board.electrical_timing = {"duration": 1.0, "impact_time": 0.01}
	var electrical_started := Time.get_ticks_msec()
	await player.play_events([
		{"type": "arc", "from": Vector2i(3, 3), "pos": Vector2i(3, 3), "target_pos": Vector2i(5, 1)},
		{"type": "damage", "pos": Vector2i(5, 1), "damage": 2, "uid": "missing_arc_tail", "victim_uid": "missing_arc_tail", "is_crit": false},
		{"type": "gem_flash", "pos": Vector2i(2, 2)},
	])
	var electrical_elapsed := float(Time.get_ticks_msec() - electrical_started) / 1000.0
	assert(electrical_elapsed < 0.5, "electrical recovery is a visual tail and must not block the next beat")
	board.electrical_timing = {"duration": 0.0, "impact_time": 0.0}
	board.operations.clear()
	board.damage_effects.clear()
	await player.play_events([
		{"type": "light_beam", "from": Vector2i(1, 1), "to": Vector2i(5, 1)},
		{"type": "light_beam", "from": Vector2i(1, 1), "to": Vector2i(5, 2)},
		{"type": "damage", "pos": Vector2i(5, 1), "damage": 3, "uid": "missing_a", "victim_uid": "missing_a", "is_crit": false},
		{"type": "damage", "pos": Vector2i(5, 2), "damage": 3, "uid": "missing_b", "victim_uid": "missing_b", "is_crit": false},
	])
	assert(board.light_beam_batches.size() == 1, "split light beams should be presented as one volley")
	assert(board.light_beam_batches[0].size() == 2, "light volley should contain every beam")
	assert(board.damage_effects.size() == 2, "light volley damage should present at impact")
	assert(requested_anim_delays.is_empty(), "damage, flashes, and visual tails must not add cosmetic settlement delays")
	host.queue_free()
	print("BATTLE_EVENT_PLAYER_CLUSTER_TEST_PASS")
	quit()
