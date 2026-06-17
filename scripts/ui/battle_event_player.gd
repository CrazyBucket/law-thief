class_name BattleEventPlayer
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")

var _host: Node = null
var _board = null
var _controller: BattleController = null
var _spawn_damage_text: Callable = Callable()
var _scale_anim_time: Callable = Callable()

var _display_state: GameState = null
var _is_playing: bool = false
var _pending_battle_end: String = ""


func setup(host: Node, board, controller: BattleController, spawn_damage_text: Callable, scale_anim_time: Callable) -> void:
	_host = host
	_board = board
	_controller = controller
	_spawn_damage_text = spawn_damage_text
	_scale_anim_time = scale_anim_time


func get_view_state(fallback: GameState) -> GameState:
	return _display_state if _display_state != null else fallback


func is_playing() -> bool:
	return _is_playing


func begin_presentation(state_before: GameState, inspect_uid: String, economy_source: GameState = null) -> void:
	_is_playing = true
	_display_state = state_before
	if economy_source != null and _display_state != null:
		_display_state.player_moved = economy_source.player_moved
		_display_state.player_acted = economy_source.player_acted
	if _board != null:
		_board.set_battle_state(_display_state)
		_board.selected_unit_uid = inspect_uid
		_board.queue_redraw()


func finish_presentation(final_state: GameState, inspect_uid: String) -> String:
	_display_state = null
	_is_playing = false
	if _board != null:
		_board.set_battle_state(final_state)
		_board.selected_unit_uid = inspect_uid
		_board.queue_redraw()
	var result := _pending_battle_end
	_pending_battle_end = ""
	return result


func queue_battle_end(result: String) -> void:
	_pending_battle_end = result


func play_sequence(
	state_before: GameState,
	inspect_uid: String,
	final_state: GameState,
	events: Array,
	economy_source: GameState = null
) -> String:
	begin_presentation(state_before, inspect_uid, economy_source)
	await play_events(events)
	return finish_presentation(final_state, inspect_uid)


func _host_ready() -> bool:
	return _host != null and is_instance_valid(_host) and _host.is_inside_tree()


func _await_anim_delay(seconds: float) -> void:
	if not _host_ready():
		return
	await _host.get_tree().create_timer(_scaled_anim_time(seconds)).timeout


func play_prefire_projectile(from_pos: Vector2i, to_pos: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	await _board.play_projectile_task(from_pos, to_pos, proj_color)
	await _await_anim_delay(0.08)


func play_events(events: Array) -> void:
	if OS.is_debug_build():
		EventValidator.assert_valid(events, "BattleEventPlayer.play_events")
	var i := 0
	while i < events.size():
		if not _host_ready():
			break
		var ev: Dictionary = events[i]
		var ev_type := str(ev.get("type", ""))
		if ev_type in ["projectile", "projectile_deflect"]:
			var projectile_batch := _collect_consecutive_events(events, i, ["projectile", "projectile_deflect"])
			i += projectile_batch.size()
			await _play_projectile_volley(projectile_batch)
			continue
		if ev_type == "explode":
			var blast_cluster := _collect_blast_cluster(events, i)
			i = int(blast_cluster.get("next_index", i))
			await _play_blast_cluster(blast_cluster)
			await _await_anim_delay(0.75)
			_board.queue_redraw()
			continue
		if ev_type == "damage":
			var damage_events := _collect_consecutive_events(events, i, ["damage"])
			i += damage_events.size()
			_play_damage_batch(damage_events)
			await _await_anim_delay(0.34)
			_board.queue_redraw()
			continue
		if ev_type == "light_beam":
			_prime_event_state(ev)
			await _board.play_light_beam_task(
				ev.get("from", Vector2i.ZERO),
				ev.get("to", Vector2i.ZERO),
				ev.get("color", Color(1.0, 0.96, 0.58)),
				float(ev.get("width", 1.0)),
				ev
			)
			_apply_event_state(ev)
			i += 1
			_board.queue_redraw()
			continue
		if ev_type == "move_step":
			var move_events := _collect_consecutive_events(events, i, ["move_step"])
			i += move_events.size()
			if _move_batch_is_parallel(move_events):
				await _play_parallel_move_batch(move_events)
			else:
				await _play_move_path_batch(move_events)
			_board.queue_redraw()
			continue
		if ev_type in ["poison_burst", "fire_burst", "frost_pulse"]:
			var fx_batch := _collect_consecutive_events(events, i, [ev_type])
			i += fx_batch.size()
			_play_area_fx_batch(fx_batch)
			await _await_anim_delay(0.42)
			_board.queue_redraw()
			continue
		if ev_type == "split_spawn":
			_apply_event_state(ev)
			i += 1
			_board.queue_redraw()
			continue
		_prime_event_state(ev)
		await _play_anim_event(ev)
		_apply_event_state(ev)
		i += 1
		_board.queue_redraw()


func _collect_consecutive_events(events: Array, start: int, types: Array) -> Array:
	var batch: Array = []
	var i := start
	while i < events.size() and str(events[i].get("type", "")) in types:
		batch.append(events[i])
		i += 1
	return batch


func _collect_blast_cluster(events: Array, start: int) -> Dictionary:
	var explode_batch: Array = []
	var damage_batch: Array = []
	var move_batch: Array = []
	var fx_batch: Array = []
	var split_spawn_batch: Array = []
	var i := start
	while i < events.size():
		var tail_type := str(events[i].get("type", ""))
		if tail_type == "explode":
			explode_batch.append(events[i])
		elif tail_type == "damage":
			damage_batch.append(events[i])
		elif tail_type == "move_step":
			move_batch.append(events[i])
		elif tail_type in ["poison_burst", "fire_burst", "frost_pulse"]:
			fx_batch.append(events[i])
		elif tail_type == "split_spawn":
			split_spawn_batch.append(events[i])
		else:
			break
		i += 1
	return {
		"explode": explode_batch,
		"damage": damage_batch,
		"move_step": move_batch,
		"area_fx": fx_batch,
		"split_spawn": split_spawn_batch,
		"next_index": i,
	}


func _play_blast_cluster(cluster: Dictionary) -> void:
	var explode_batch: Array = cluster.get("explode", [])
	var damage_batch: Array = cluster.get("damage", [])
	var move_batch: Array = cluster.get("move_step", [])
	var fx_batch: Array = cluster.get("area_fx", [])
	var split_spawn_batch: Array = cluster.get("split_spawn", [])
	for explode_event in explode_batch:
		_prime_event_state(explode_event)
	for explode_event in explode_batch:
		_board.play_explosion(explode_event.get("pos", Vector2i.ZERO))
	_apply_area_events_for_blast(fx_batch)
	_play_split_spawn_batch(split_spawn_batch)
	_board.queue_redraw()
	for explode_event in explode_batch:
		_apply_event_state(explode_event)
	_play_damage_batch(damage_batch)
	if not move_batch.is_empty():
		await _play_parallel_move_batch(move_batch)


func _play_damage_batch(batch: Array) -> void:
	for damage_event in batch:
		_prime_event_state(damage_event)
	for damage_event in batch:
		var damage_pos: Vector2i = damage_event.get("pos", Vector2i.ZERO)
		var damage_value: int = int(damage_event.get("damage", 1))
		var is_crit: bool = bool(damage_event.get("is_crit", false))
		_board.play_damage_effect(damage_pos, damage_value, is_crit)
		if _spawn_damage_text.is_valid():
			_spawn_damage_text.call(damage_pos, damage_value, is_crit, damage_event.get("reason", ""))
	for damage_event in batch:
		_apply_event_state(damage_event)


func _play_area_fx_batch(batch: Array) -> void:
	for fx_event in batch:
		_prime_event_state(fx_event)
	for fx_event in batch:
		match str(fx_event.get("type", "")):
			"poison_burst":
				_board.play_poison_burst(
					fx_event.get("pos", Vector2i.ZERO),
					int(fx_event.get("radius", 0)),
					str(fx_event.get("pattern", ""))
				)
			"fire_burst":
				_board.play_explosion(fx_event.get("pos", Vector2i.ZERO))
				_board.play_gem_flash(fx_event.get("pos", Vector2i.ZERO), Color(1.0, 0.45, 0.1))
			"frost_pulse":
				_board.play_heal_effect(fx_event.get("pos", Vector2i.ZERO))
	for fx_event in batch:
		_apply_event_state(fx_event)


func _apply_area_events_for_blast(batch: Array) -> void:
	if batch.is_empty():
		return
	_play_area_fx_batch(batch)


func _play_split_spawn_batch(batch: Array) -> void:
	for split_event in batch:
		_apply_event_state(split_event)
		_board.play_gem_flash(split_event.get("pos", Vector2i.ZERO), Color(0.35, 0.88, 0.55))


func _play_parallel_move_batch(batch: Array) -> void:
	for step_event in batch:
		_prime_event_state(step_event)
	await _board.animate_moves_parallel_task(batch)
	for step_event in batch:
		_apply_event_state(step_event)


func _play_move_path_batch(batch: Array) -> void:
	if batch.is_empty():
		return
	if batch.size() == 1 or not _board.has_method("animate_move_path"):
		for step_event in batch:
			_prime_event_state(step_event)
			await _board.animate_move_task(
				step_event.get("uid", ""),
				step_event.get("from", Vector2i.ZERO),
				step_event.get("to", Vector2i.ZERO)
			)
			_apply_event_state(step_event)
		return
	for step_event in batch:
		_prime_event_state(step_event)
	var path: Array = [batch[0].get("from", Vector2i.ZERO)]
	for step_event in batch:
		path.append(step_event.get("to", Vector2i.ZERO))
	await _board.animate_move_path_task(str(batch[0].get("uid", "")), path)
	for step_event in batch:
		_apply_event_state(step_event)


func _play_projectile_volley(batch: Array) -> void:
	if batch.is_empty():
		return
	if batch.size() == 1:
		var single: Dictionary = batch[0]
		var projectile_color: Color = single.get("color", Color(0.95, 0.92, 0.45))
		await _board.play_projectile_task(single.get("from", Vector2i.ZERO), single.get("to", Vector2i.ZERO), projectile_color)
	else:
		var shots: Array = []
		for projectile_event in batch:
			shots.append({
				"from": projectile_event.get("from", Vector2i.ZERO),
				"to": projectile_event.get("to", Vector2i.ZERO),
				"color": projectile_event.get("color", Color(0.95, 0.92, 0.45)),
			})
		await _board.play_projectiles_task(shots)
	await _await_anim_delay(0.08)


func _move_batch_is_parallel(batch: Array) -> bool:
	if batch.size() <= 1:
		return false
	var first_uid := str(batch[0].get("uid", ""))
	for event in batch:
		if str(event.get("uid", "")) != first_uid:
			return true
	return false


func _play_anim_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"move_step":
			await _board.animate_move_task(ev.get("uid", ""), ev.get("from", Vector2i.ZERO), ev.get("to", Vector2i.ZERO))
		"damage":
			var attacker_uid: String = str(ev.get("attacker_uid", ""))
			var damage_pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var damage_value: int = int(ev.get("damage", 1))
			var is_crit: bool = bool(ev.get("is_crit", false))
			if not attacker_uid.is_empty() and not bool(ev.get("keep_facing", false)):
				_board.start_strike_effect(attacker_uid, damage_pos)
				await _await_anim_delay(0.12)
			_board.play_damage_effect(damage_pos, damage_value, is_crit)
			if _spawn_damage_text.is_valid():
				_spawn_damage_text.call(damage_pos, damage_value, is_crit, ev.get("reason", ""))
			await _await_anim_delay(0.38)
		"explode":
			_board.play_explosion(ev.get("pos", Vector2i.ZERO))
			_board.queue_redraw()
			await _await_anim_delay(0.75)
		"poison_burst":
			_board.play_poison_burst(
				ev.get("pos", Vector2i.ZERO),
				int(ev.get("radius", 0)),
				str(ev.get("pattern", ""))
			)
			await _await_anim_delay(0.6)
			_board.queue_redraw()
		"gem_flash":
			var flash_color: Color = ev.get("color", Color.WHITE)
			if bool(ev.get("echo_followup", false)) and flash_color == Color.WHITE:
				flash_color = Color(0.62, 0.42, 1.0)
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), flash_color)
			await _await_anim_delay(0.32)
		"projectile", "projectile_deflect":
			var projectile_color: Color = ev.get("color", Color(0.95, 0.92, 0.45))
			await _board.play_projectile_task(ev.get("from", Vector2i.ZERO), ev.get("to", Vector2i.ZERO), projectile_color)
			await _await_anim_delay(0.08)
		"light_beam":
			await _board.play_light_beam_task(
				ev.get("from", Vector2i.ZERO),
				ev.get("to", Vector2i.ZERO),
				ev.get("color", Color(1.0, 0.96, 0.58)),
				float(ev.get("width", 1.0)),
				ev
			)
		"lightning", "arc":
			_board.play_damage_effect(ev.get("pos", Vector2i.ZERO), 1, true)
			await _await_anim_delay(0.22)
		"frost_pulse":
			_board.play_heal_effect(ev.get("pos", Vector2i.ZERO))
			await _await_anim_delay(0.28)
		"fire_burst":
			_board.play_explosion(ev.get("pos", Vector2i.ZERO))
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), Color(1.0, 0.45, 0.1))
			await _await_anim_delay(0.4)
		"miss":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), Color(0.7, 0.7, 0.7, 0.6))
			await _await_anim_delay(0.22)


func _prime_event_state(ev: Dictionary) -> void:
	if _display_state == null:
		return
	match str(ev.get("type", "")):
		"move_step":
			var uid := str(ev.get("uid", ""))
			var unit: UnitState = _display_state.units.get(uid, null)
			if unit != null:
				var from_pos: Vector2i = ev.get("from", unit.pos)
				var to_pos: Vector2i = ev.get("to", unit.pos)
				if unit.pos != to_pos:
					_display_state.move_unit(unit, to_pos)
				unit.facing = UnitState.facing_from_step(from_pos, to_pos)


func _apply_event_state(ev: Dictionary) -> void:
	if _display_state == null:
		return
	match str(ev.get("type", "")):
		"damage":
			var pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var victim_uid := str(ev.get("uid", ev.get("victim_uid", "")))
			var victim: UnitState = _display_state.units.get(victim_uid, null) if not victim_uid.is_empty() else null
			if victim == null:
				victim = _display_state.get_unit_at(pos)
			if victim == null:
				return
			victim.hp = maxi(0, victim.hp - int(ev.get("damage", 0)))
			if victim.hp <= 0:
				victim.alive = false
		"poison_burst":
			var poison_center: Vector2i = ev.get("pos", Vector2i.ZERO)
			var pattern := str(ev.get("pattern", ""))
			var poison_radius: int = int(ev.get("radius", 0))
			var cells: Array[Vector2i] = []
			if pattern == "cross":
				cells.append(poison_center)
				for neighbor in BoardUtils.neighbors4(poison_center):
					if BoardUtils.in_bounds(_display_state, neighbor):
						cells.append(neighbor)
			elif poison_radius <= 0:
				cells.append(poison_center)
			else:
				for cell in BoardUtils.cells_in_radius(poison_center, poison_radius):
					if BoardUtils.in_bounds(_display_state, cell):
						cells.append(cell)
			var duration := CombatConfig.poison_fog_duration()
			if int(ev.get("duration", 0)) > 0:
				duration = int(ev.get("duration", duration))
			for cell in cells:
				TileRules.create_poison_fog(_display_state, cell, duration)
		"fire_burst":
			TileRules.create_fire(_display_state, ev.get("pos", Vector2i.ZERO))
		"explode", "gem_flash", "projectile_deflect", "lightning", "frost_pulse", "arc", "light_beam":
			pass
		"split_spawn":
			var clone_uid := str(ev.get("uid", ""))
			var clone: UnitState = _controller.state.units.get(clone_uid, null)
			if clone != null and clone.alive:
				_display_state.register_unit(clone.clone())
				_display_state.rebuild_occupancy()


func _scaled_anim_time(base_duration: float) -> float:
	if _scale_anim_time.is_valid():
		return float(_scale_anim_time.call(base_duration))
	return base_duration
