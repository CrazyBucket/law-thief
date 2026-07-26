class_name BattleEventPlayer
extends RefCounted

const PresentationPlanner = preload("res://scripts/ui/battle_presentation_planner.gd")
const PresentationStateApplierScript = preload("res://scripts/ui/presentation_state_applier.gd")
const ImpactPresenter = preload("res://scripts/ui/impact_animation_presenter.gd")

const BLAST_IMPACT_DELAY := 0.12
const ELECTRICAL_IMPACT_DELAY := 0.14

var _host: Node = null
var _board = null
var _controller: BattleController = null
var _spawn_damage_text: Callable = Callable()
var _scale_anim_time: Callable = Callable()

var _display_state: GameState = null
var _state_applier = PresentationStateApplierScript.new()
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
	_sync_state_applier()
	if economy_source != null and _display_state != null:
		_display_state.player_moved = economy_source.player_moved
		_display_state.player_acted = economy_source.player_acted
	if _board != null:
		_board.set_battle_state(_display_state)
		_board.selected_unit_uid = inspect_uid
		_board.queue_redraw()


func finish_presentation(final_state: GameState, inspect_uid: String) -> String:
	_display_state = null
	_sync_state_applier()
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


func take_pending_battle_end() -> String:
	var result := _pending_battle_end
	_pending_battle_end = ""
	return result


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


func _await_real_delay(seconds: float) -> void:
	if not _host_ready() or seconds <= 0.0:
		return
	await _host.get_tree().create_timer(seconds).timeout


func play_prefire_projectile(from_pos: Vector2i, to_pos: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	await _board.play_projectile_task(from_pos, to_pos, proj_color)
	await _await_anim_delay(0.08)


func play_events(events: Array) -> void:
	if OS.is_debug_build():
		EventValidator.assert_valid(events, "BattleEventPlayer.play_events")
	var plan := PresentationPlanner.build(events)
	var violations: Array = plan.get("violations", [])
	if not violations.is_empty():
		for violation in violations:
			push_error("[BattlePresentationPlanner] %s" % str(violation))
		assert(false, "Battle presentation contains events without an explicit playback policy")
	for beat in plan.get("beats", []):
		if not _host_ready():
			break
		await _play_beat(beat)
		_board.queue_redraw()


func _play_beat(beat: Dictionary) -> void:
	var kind := str(beat.get("kind", "single"))
	var barrier := str(beat.get("barrier", PresentationPlanner.BARRIER_COMPLETE))
	var visuals: Array = beat.get("visuals", [])
	var impacts: Array = beat.get("impacts", [])
	match kind:
		"impact":
			await _play_impact_beat(beat)
		"projectile":
			await _play_projectile_volley(visuals)
			if not impacts.is_empty():
				_play_damage_batch(impacts)
		"blast":
			await _play_blast_cluster(beat)
		"light_beam":
			await _play_light_beam_cluster({"beams": visuals, "damage": impacts}, barrier)
		"electrical":
			await _play_electrical_beat(visuals, impacts, barrier)
		"damage":
			_play_damage_batch(impacts)
		"move":
			if _contains_displacement_impact(visuals) \
					or str(beat.get("mode", PresentationPlanner.MODE_SERIAL)) == PresentationPlanner.MODE_PARALLEL:
				await _play_parallel_motion_batch(visuals)
			else:
				await _play_move_path_batch(visuals)
		"area_fx":
			_play_area_fx_batch(visuals)
		"split_spawn":
			_play_split_spawn_batch(visuals)
		_:
			for event in visuals:
				_prime_event_state(event)
				if barrier == PresentationPlanner.BARRIER_IMPACT:
					push_error("Single presentation events cannot use an impact barrier: %s" % str(event))
				await _play_anim_event(event)
				_apply_event_state(event)


func _play_impact_beat(beat: Dictionary) -> void:
	var visuals: Array = beat.get("visuals", [])
	if visuals.is_empty():
		return
	var charge: Dictionary = visuals[0]
	var charge_motions: Array = beat.get("charge_motions", [])
	for motion in charge_motions:
		_prime_event_state(motion)
	var timing: Dictionary = {}
	if _board.has_method("play_impact_charge"):
		timing = _board.play_impact_charge(charge, charge_motions)
	else:
		timing = ImpactPresenter.play(_board, charge, charge_motions)
	if timing.is_empty():
		timing = {"duration": _scaled_anim_time(0.42), "impact_time": _scaled_anim_time(0.24)}
	await _await_real_delay(float(timing.get("impact_time", 0.0)))
	for motion in charge_motions:
		_apply_event_state(motion)
	var impacts: Array = beat.get("impacts", [])
	if not impacts.is_empty():
		_play_damage_batch(impacts)
		_board.queue_redraw()
	var impact_motions: Array = beat.get("impact_motions", [])
	var move_duration := _start_parallel_motion_batch(impact_motions)
	var recovery := maxf(0.0, float(timing.get("duration", 0.0)) - float(timing.get("impact_time", 0.0)))
	await _await_real_delay(maxf(recovery, move_duration))
	for motion in impact_motions:
		_apply_event_state(motion)
	_apply_event_state(charge)


func _play_light_beam_cluster(cluster: Dictionary, barrier: String) -> void:
	var beams: Array = cluster.get("beams", [])
	var damages: Array = cluster.get("damage", [])
	if beams.is_empty():
		return
	for beam_event in beams:
		_prime_event_state(beam_event)
	var specs: Array = []
	for beam_event in beams:
		specs.append({
			"from": beam_event.get("from", Vector2i.ZERO),
			"to": beam_event.get("to", Vector2i.ZERO),
			"color": beam_event.get("color", Color(1.0, 0.96, 0.58)),
			"width": float(beam_event.get("width", 1.0)),
			"fx": beam_event,
			"source_uid": str(beam_event.get("source_uid", "")),
		})
	var duration := 0.0
	if _board.has_method("play_light_beams"):
		duration = float(_board.play_light_beams(specs))
	else:
		for spec in specs:
			await _board.play_light_beam_task(
				spec.get("from", Vector2i.ZERO),
				spec.get("to", Vector2i.ZERO),
				spec.get("color", Color(1.0, 0.96, 0.58)),
				float(spec.get("width", 1.0)),
				spec.get("fx", {})
			)
	if duration > 0.0:
		await _await_real_delay(duration * 0.28)
	if not damages.is_empty():
		_play_damage_batch(damages)
		_board.queue_redraw()
	for beam_event in beams:
		_apply_event_state(beam_event)
	if barrier == PresentationPlanner.BARRIER_COMPLETE and duration > 0.0:
		await _await_real_delay(duration * 0.72)


func _play_blast_cluster(cluster: Dictionary) -> void:
	var explode_batch: Array = cluster.get("visuals", [])
	var damage_batch: Array = cluster.get("impacts", [])
	var move_batch: Array = cluster.get("impact_motions", [])
	var aftermath: Array = cluster.get("aftermath", [])
	var fx_batch: Array = []
	var split_spawn_batch: Array = []
	for event in aftermath:
		match str(event.get("type", "")):
			"poison_burst", "fire_burst", "frost_pulse":
				fx_batch.append(event)
			"split_spawn":
				split_spawn_batch.append(event)
	for explode_event in explode_batch:
		_prime_event_state(explode_event)
	var timing: Dictionary = {}
	if _board.has_method("play_explosion_batch"):
		timing = _board.play_explosion_batch(explode_batch)
	else:
		for explode_event in explode_batch:
			_board.play_explosion(explode_event.get("pos", Vector2i.ZERO))
	_board.queue_redraw()
	if timing.is_empty():
		await _await_anim_delay(BLAST_IMPACT_DELAY)
	else:
		await _await_real_delay(float(timing.get("impact_time", 0.0)))
	for explode_event in explode_batch:
		_apply_event_state(explode_event)
	_play_damage_batch(damage_batch)
	var move_duration := _start_parallel_motion_batch(move_batch)
	_apply_area_events_for_blast(fx_batch)
	_play_split_spawn_batch(split_spawn_batch)
	# Explosion smoke and shader decay are visual tails. Only spatial motion remains a
	# causal barrier because the next beat may depend on the displaced positions.
	var barrier := str(cluster.get("barrier", PresentationPlanner.BARRIER_IMPACT))
	if not move_batch.is_empty() and barrier != PresentationPlanner.BARRIER_COMPLETE:
		push_error("Blast motion requires a complete presentation barrier")
	if barrier == PresentationPlanner.BARRIER_COMPLETE or not move_batch.is_empty():
		await _await_real_delay(move_duration)
	for motion in move_batch:
		_apply_event_state(motion)


func _play_electrical_beat(visuals: Array, impacts: Array, barrier: String) -> void:
	var timing: Dictionary = {}
	if _board.has_method("play_electrical_batch"):
		timing = _board.play_electrical_batch(visuals)
	else:
		for event in visuals:
			var from_cell: Vector2i = event.get("from", event.get("pos", Vector2i.ZERO))
			var target_cell: Vector2i = event.get("target_pos", event.get("pos", from_cell))
			if target_cell != from_cell and _board.has_method("play_lightning_bolt"):
				_board.play_lightning_bolt(from_cell, target_cell)
			elif _board.has_method("play_lightning_strike"):
				_board.play_lightning_strike(target_cell)
	if timing.is_empty():
		await _await_anim_delay(ELECTRICAL_IMPACT_DELAY)
	else:
		await _await_real_delay(float(timing.get("impact_time", 0.0)))
	if not impacts.is_empty():
		_play_damage_batch(impacts)
		_board.queue_redraw()
	if barrier == PresentationPlanner.BARRIER_COMPLETE:
		if timing.is_empty():
			await _await_anim_delay(0.20)
		else:
			var recovery := maxf(
				0.0,
				float(timing.get("duration", 0.0)) - float(timing.get("impact_time", 0.0))
			)
			await _await_real_delay(recovery)


func _play_damage_batch(batch: Array) -> void:
	for damage_event in batch:
		_prime_event_state(damage_event)
	for damage_event in batch:
		_play_damage_feedback(damage_event)
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
				_board.play_fire_burst(fx_event.get("pos", Vector2i.ZERO))
			"frost_pulse":
				_board.play_frost_pulse(fx_event.get("pos", Vector2i.ZERO))
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


func _play_parallel_motion_batch(batch: Array) -> void:
	for step_event in batch:
		_prime_event_state(step_event)
	await _board.animate_unit_motions_parallel_task(batch)
	for step_event in batch:
		_apply_event_state(step_event)


func _start_parallel_motion_batch(batch: Array) -> float:
	if batch.is_empty():
		return 0.0
	for step_event in batch:
		_prime_event_state(step_event)
	return float(_board.animate_unit_motions_parallel(batch))


func _contains_displacement_impact(batch: Array) -> bool:
	for event in batch:
		if str(event.get("type", "")) == "displacement_impact":
			return true
	return false


func _play_damage_feedback(ev: Dictionary) -> void:
	var victim_uid := str(ev.get("uid", ev.get("victim_uid", "")))
	if not victim_uid.is_empty() and _board.has_method("play_unit_hit"):
		_board.play_unit_hit(victim_uid)
	var damage_pos: Vector2i = ev.get("pos", Vector2i.ZERO)
	var damage_value: int = int(ev.get("damage", 1))
	var is_crit: bool = bool(ev.get("is_crit", false))
	_board.play_damage_effect(damage_pos, damage_value, is_crit)
	if _spawn_damage_text.is_valid():
		_spawn_damage_text.call(damage_pos, damage_value, is_crit, ev.get("reason", ""))


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
		await _board.play_projectile_task(
			single.get("from", Vector2i.ZERO),
			single.get("to", Vector2i.ZERO),
			projectile_color,
			str(single.get("source_uid", ""))
		)
	else:
		var shots: Array = []
		for projectile_event in batch:
			shots.append({
				"from": projectile_event.get("from", Vector2i.ZERO),
				"to": projectile_event.get("to", Vector2i.ZERO),
				"color": projectile_event.get("color", Color(0.95, 0.92, 0.45)),
				"source_uid": str(projectile_event.get("source_uid", "")),
			})
		await _board.play_projectiles_task(shots)


func _play_anim_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"knockback":
			await _board.animate_move_task(
				ev.get("uid", ""),
				ev.get("from", Vector2i.ZERO),
				ev.get("to", Vector2i.ZERO)
			)
		"gem_flash":
			var flash_color: Color = ev.get("color", Color.WHITE)
			if bool(ev.get("echo_followup", false)) and flash_color == Color.WHITE:
				flash_color = Color(0.62, 0.42, 1.0)
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), flash_color)
		"spawn":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), Color(0.72, 0.82, 0.32))
		"transform":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), Color(0.58, 0.34, 0.66))
		"miss":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), Color(0.7, 0.7, 0.7, 0.6))
		"die":
			if _board.has_method("play_unit_death"):
				await _board.play_unit_death(str(ev.get("uid", "")))
			else:
				await _await_anim_delay(0.38)


func _prime_event_state(ev: Dictionary) -> void:
	_sync_state_applier()
	_state_applier.prime(ev)


func _apply_event_state(ev: Dictionary) -> void:
	_sync_state_applier()
	_state_applier.apply(ev)


func _sync_state_applier() -> void:
	var runtime_state: GameState = null
	if _controller != null:
		runtime_state = _controller.state
	_state_applier.set_states(_display_state, runtime_state)


func _scaled_anim_time(base_duration: float) -> float:
	if _scale_anim_time.is_valid():
		return float(_scale_anim_time.call(base_duration))
	return base_duration
