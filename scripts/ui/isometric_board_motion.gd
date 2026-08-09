extends "res://scripts/ui/isometric_board_fx_base.gd"

func _facing_from_grid_pos(from_grid: Vector2i, to_grid: Vector2i) -> String:
	_ensure_facing_screen_refs()
	var screen_delta := grid_to_screen(to_grid) - grid_to_screen(from_grid)
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return "DR"
	var dir := screen_delta.normalized()
	var best_name := "DR"
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name

func _facing_from_unit_to_cell(unit: UnitState, to_grid: Vector2i) -> String:
	_ensure_facing_screen_refs()
	var from_screen := _get_unit_screen_center(unit)
	var to_screen := grid_to_screen(to_grid)
	var screen_delta := to_screen - from_screen
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return unit.facing
	var dir := screen_delta.normalized()
	var best_name := "DR"
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name

func _ensure_facing_screen_refs() -> void:
	if not _facing_screen_refs.is_empty():
		return
	var origin_screen := grid_to_screen(Vector2i(0, 0))
	for facing_name in _FACING_GRID_STEPS.keys():
		var step: Vector2i = _FACING_GRID_STEPS[facing_name]
		var v := grid_to_screen(step) - origin_screen
		if v.length_squared() > 0.01:
			_facing_screen_refs[facing_name] = v.normalized()

func start_strike_effect(attacker_uid: String, victim_cell: Vector2i) -> void:
	if state == null:
		return
	var attacker: UnitState = state.units.get(attacker_uid, null)
	if attacker == null:
		return
	attacker.facing = _facing_from_unit_to_cell(attacker, victim_cell)
	_anim.strike_elapsed[attacker_uid] = 0.0
	queue_redraw()

func play_unit_hit(unit_uid: String) -> void:
	if state == null or not state.units.has(unit_uid):
		return
	_anim.hit_elapsed[unit_uid] = 0.0
	queue_redraw()


## 播放移动动画：单位从 from_pos 滑动到 to_pos

func animate_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i, emit_finished: bool = true) -> void:
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			mover.facing = _facing_from_grid_pos(from_pos, to_pos)
	var from_screen: Vector2 = grid_to_screen(from_pos)
	var to_screen: Vector2 = grid_to_screen(to_pos)
	var logical_pos: Vector2i = to_pos
	if state != null:
		var unit: UnitState = state.units.get(unit_uid, null)
		if unit != null:
			logical_pos = unit.pos
	var logical_screen: Vector2 = grid_to_screen(logical_pos)
	var from_offset: Vector2 = from_screen - logical_screen
	var to_offset: Vector2 = to_screen - logical_screen
	_anim.move_offsets[unit_uid] = from_offset
	_anim.walk_phase[unit_uid] = 0.0
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_move_offset.bind(unit_uid), from_offset, to_offset, _scaled_duration(_MOVE_DURATION))
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, to_offset, emit_finished))

func animate_move_task(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	animate_move(unit_uid, from_pos, to_pos)
	await move_animation_finished


## 播放一整条路径。逻辑位置已提前写到终点，视觉 offset 沿路径连续归零。

func animate_move_path(unit_uid: String, path: Array, emit_finished: bool = true) -> void:
	if path.size() < 2:
		if emit_finished:
			animation_finished.emit()
		return
	var fallback_facing := "DR"
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			fallback_facing = mover.facing
	var segment_facings := _build_path_segment_facings(path, fallback_facing)
	_anim.move_path_segment_facings[unit_uid] = segment_facings
	_anim.move_path_segments[unit_uid] = -1
	if not segment_facings.is_empty():
		_apply_move_path_segment_facing(unit_uid, 0, segment_facings)
	var logical_pos: Vector2i = path[path.size() - 1]
	if state != null:
		var unit: UnitState = state.units.get(unit_uid, null)
		if unit != null:
			logical_pos = unit.pos
	var logical_screen := grid_to_screen(logical_pos)
	var offset_path: Array[Vector2] = []
	for cell in path:
		offset_path.append(grid_to_screen(cell) - logical_screen)
	_anim.move_offsets[unit_uid] = offset_path[0]
	_anim.walk_phase[unit_uid] = 0.0
	var segment_count := maxi(1, offset_path.size() - 1)
	var duration := _scaled_duration(0.26 * float(segment_count))
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(
		_set_move_path_progress.bind(unit_uid, offset_path, segment_facings),
		0.0,
		float(segment_count),
		duration
	)
	tween.tween_callback(_on_move_path_anim_done.bind(unit_uid, segment_facings, emit_finished))

func animate_move_path_task(unit_uid: String, path: Array) -> void:
	if path.size() < 2:
		return
	animate_move_path(unit_uid, path)
	await move_animation_finished


## 多单位同时位移（爆炸击退等）

func animate_moves_parallel(moves: Array) -> float:
	return animate_unit_motions_parallel(moves)

func animate_unit_motions_parallel(motions: Array) -> float:
	if motions.is_empty():
		animation_finished.emit()
		move_animation_finished.emit()
		return 0.0
	var sequences: Dictionary = {}
	for motion in motions:
		var uid := str(motion.get("uid", ""))
		if uid.is_empty():
			continue
		if not sequences.has(uid):
			sequences[uid] = []
		(sequences[uid] as Array).append(motion)
	if sequences.is_empty():
		animation_finished.emit()
		move_animation_finished.emit()
		return 0.0
	_anim.parallel_move_remaining = sequences.size()
	var max_duration := 0.0
	for uid in sequences.keys():
		max_duration = maxf(max_duration, _animate_unit_motion_sequence(str(uid), sequences[uid]))
	return max_duration

func _animate_unit_motion_sequence(unit_uid: String, motions: Array) -> float:
	var unit: UnitState = state.units.get(unit_uid, null) if state != null else null
	var final_motion: Dictionary = motions[-1]
	var logical_pos: Vector2i = unit.pos if unit != null else final_motion.get("to", final_motion.get("from", Vector2i.ZERO))
	var logical_screen := grid_to_screen(logical_pos)
	var first_from: Vector2i = motions[0].get("from", logical_pos)
	var current_offset := grid_to_screen(first_from) - logical_screen
	_anim.move_offsets[unit_uid] = current_offset
	_anim.walk_phase[unit_uid] = 0.0
	var tween := create_tween()
	var total_duration := 0.0
	for motion in motions:
		match str(motion.get("type", "move_step")):
			"displacement_impact":
				var motion_from: Vector2i = motion.get("from", logical_pos)
				var contact: Vector2i = motion.get("contact", motion_from)
				var contact_offset := current_offset + (
					grid_to_screen(contact) - grid_to_screen(motion_from)
				) * _COLLISION_CONTACT_RATIO
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					current_offset,
					contact_offset,
					_scaled_duration(_COLLISION_LUNGE_DURATION)
				).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					contact_offset,
					current_offset,
					_scaled_duration(_COLLISION_RECOIL_DURATION)
				).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				total_duration += _scaled_duration(_COLLISION_LUNGE_DURATION + _COLLISION_RECOIL_DURATION)
			_:
				var to_pos: Vector2i = motion.get("to", motion.get("from", logical_pos))
				var to_offset := grid_to_screen(to_pos) - logical_screen
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					current_offset,
					to_offset,
					_scaled_duration(_MOVE_DURATION)
				).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				current_offset = to_offset
				total_duration += _scaled_duration(_MOVE_DURATION)
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, current_offset, false))
	return total_duration

func animate_unit_motions_parallel_task(motions: Array) -> void:
	if motions.is_empty():
		return
	animate_unit_motions_parallel(motions)
	await move_animation_finished

func animate_moves_parallel_task(moves: Array) -> void:
	if moves.is_empty():
		return
	animate_moves_parallel(moves)
	await move_animation_finished

func clear_gem_visuals() -> void:
	_anim.clear_gem_visuals()
	queue_redraw()

func has_active_held_gem_visual() -> bool:
	return not _anim.held_gem_visual.is_empty()

func gem_insert_anim_duration() -> float:
	return _scaled_duration(_GEM_INSERT_DURATION)

func start_held_gem_extract(source_grid: Vector2i, gem: GemState) -> void:
	if gem == null:
		return
	var source_pos := _consume_inserting_gem_position(gem.uid, _gem_grid_anchor(source_grid))
	_anim.held_gem_visual = _make_gem_visual(gem, source_pos)
	_anim.held_gem_visual["phase"] = "extract"
	_anim.held_gem_visual["from_pos"] = source_pos
	_anim.held_gem_visual["current_pos"] = source_pos
	_anim.held_gem_visual["elapsed"] = 0.0
	_anim.held_gem_visual["duration"] = _scaled_duration(_GEM_LIFT_DURATION)
	_anim.held_gem_visual["arc_height"] = IsoCoordinates.visual(54.0)
	_anim.held_gem_visual["orbit_angle"] = _orbit_angle_from_position(source_pos)
	_anim.held_gem_visual["bob_time"] = randf() * TAU
	queue_redraw()

func show_held_gem_orbit(gem: GemState) -> void:
	if gem == null:
		return
	var visual := _make_gem_visual(gem, _current_player_orbit_position({"orbit_angle": 0.0, "bob_time": 0.0}))
	if visual.is_empty():
		return
	visual["phase"] = "orbit"
	visual["orbit_angle"] = 0.0
	visual["bob_time"] = 0.0
	_anim.held_gem_visual = visual
	queue_redraw()

func start_held_gem_insert(target_grid: Vector2i, gem: GemState) -> void:
	var visual: Dictionary = {}
	if not _anim.held_gem_visual.is_empty():
		visual = _anim.held_gem_visual.duplicate(true)
		_anim.held_gem_visual.clear()
	elif gem != null:
		var fallback := {
			"orbit_angle": 0.0,
			"bob_time": _anim.pulse_time * _GEM_BOB_SPEED,
		}
		visual = _make_gem_visual(gem, _current_player_orbit_position(fallback))
	if visual.is_empty():
		return
	var start_pos: Vector2 = visual.get("current_pos", _gem_grid_anchor(target_grid))
	visual["phase"] = "insert"
	visual["from_pos"] = start_pos
	visual["current_pos"] = start_pos
	visual["target_grid"] = target_grid
	visual["elapsed"] = 0.0
	visual["duration"] = _scaled_duration(_GEM_INSERT_DURATION)
	visual["arc_height"] = IsoCoordinates.visual(36.0)
	var gem_uid := str(visual.get("uid", ""))
	if not gem_uid.is_empty():
		_anim.masked_embedded_gems[gem_uid] = true
	_anim.inserting_gem_visuals.append(visual)
	queue_redraw()

func set_animation_speed_scale(speed_scale: float) -> void:
	_animation_speed_scale = maxf(speed_scale, 0.05)

func _scaled_duration(base_duration: float) -> float:
	return base_duration / _animation_speed_scale

func _set_move_offset(offset: Vector2, uid: String) -> void:
	_anim.move_offsets[uid] = offset
	queue_redraw()

func _build_path_segment_facings(path: Array, fallback_facing: String) -> Array[String]:
	var facings: Array[String] = []
	var last_facing := fallback_facing
	for i in range(path.size() - 1):
		var from_cell: Vector2i = path[i]
		var to_cell: Vector2i = path[i + 1]
		if from_cell == to_cell:
			facings.append(last_facing)
		else:
			last_facing = _facing_from_grid_pos(from_cell, to_cell)
			facings.append(last_facing)
	return facings

func _apply_move_path_segment_facing(uid: String, seg: int, segment_facings: Array[String]) -> void:
	if seg < 0 or seg >= segment_facings.size():
		return
	if int(_anim.move_path_segments.get(uid, -1)) == seg:
		return
	_anim.move_path_segments[uid] = seg
	if state == null:
		return
	var mover: UnitState = state.units.get(uid, null)
	if mover != null:
		mover.facing = segment_facings[seg]

func _set_move_path_progress(
	progress: float,
	uid: String,
	offset_path: Array[Vector2],
	segment_facings: Array[String]
) -> void:
	if offset_path.is_empty():
		return
	var max_segment := offset_path.size() - 1
	var seg := clampi(int(floor(progress)), 0, max_segment)
	if seg >= max_segment:
		_anim.move_offsets[uid] = offset_path[max_segment]
		if max_segment > 0:
			_apply_move_path_segment_facing(uid, max_segment - 1, segment_facings)
	else:
		var local_t := clampf(progress - float(seg), 0.0, 1.0)
		_anim.move_offsets[uid] = offset_path[seg].lerp(offset_path[seg + 1], local_t)
		_apply_move_path_segment_facing(uid, seg, segment_facings)
	queue_redraw()

func _on_move_path_anim_done(uid: String, segment_facings: Array[String], emit_finished: bool) -> void:
	if state != null and not segment_facings.is_empty():
		var mover: UnitState = state.units.get(uid, null)
		if mover != null:
			mover.facing = segment_facings[segment_facings.size() - 1]
	_on_move_anim_done(uid, Vector2.ZERO, emit_finished)

func _on_move_anim_done(uid: String, _final_offset: Vector2, emit_finished: bool = true) -> void:
	_anim.walk_phase.erase(uid)
	_anim.move_offsets.erase(uid)
	_anim.move_path_segments.erase(uid)
	_anim.move_path_segment_facings.erase(uid)
	queue_redraw()
	if not emit_finished:
		_anim.parallel_move_remaining = maxi(0, _anim.parallel_move_remaining - 1)
		if _anim.parallel_move_remaining <= 0:
			animation_finished.emit()
			move_animation_finished.emit()
		return
	animation_finished.emit()
	move_animation_finished.emit()

func _update_gem_visuals(scaled_dt: float) -> bool:
	var dirty := false
	if not _anim.held_gem_visual.is_empty():
		dirty = _update_held_gem_visual(scaled_dt) or dirty
	if not _anim.inserting_gem_visuals.is_empty():
		var idx := _anim.inserting_gem_visuals.size() - 1
		while idx >= 0:
			var visual: Dictionary = _anim.inserting_gem_visuals[idx]
			dirty = true
			if _step_inserting_gem_visual(visual, scaled_dt):
				_anim.inserting_gem_visuals[idx] = visual
			else:
				var gem_uid := str(visual.get("uid", ""))
				if not gem_uid.is_empty():
					_anim.masked_embedded_gems.erase(gem_uid)
				play_gem_flash(visual.get("target_grid", Vector2i.ZERO), visual.get("tint", Color.WHITE))
				_anim.inserting_gem_visuals.remove_at(idx)
				queue_redraw()
			idx -= 1
	return dirty

func _update_held_gem_visual(scaled_dt: float) -> bool:
	var phase := str(_anim.held_gem_visual.get("phase", "orbit"))
	if phase == "extract":
		var duration := maxf(float(_anim.held_gem_visual.get("duration", 0.01)), 0.01)
		var elapsed := minf(float(_anim.held_gem_visual.get("elapsed", 0.0)) + scaled_dt, duration)
		_anim.held_gem_visual["elapsed"] = elapsed
		_anim.held_gem_visual["bob_time"] = float(_anim.held_gem_visual.get("bob_time", 0.0)) + scaled_dt * _GEM_BOB_SPEED
		var from_pos: Vector2 = _anim.held_gem_visual.get("from_pos", _anim.held_gem_visual.get("current_pos", Vector2.ZERO))
		var to_pos := _current_player_orbit_position(_anim.held_gem_visual)
		var ctrl := (from_pos + to_pos) * 0.5 + Vector2(0.0, -float(_anim.held_gem_visual.get("arc_height", IsoCoordinates.visual(54.0))))
		var pos := _quadratic_bezier(from_pos, ctrl, to_pos, _ease_out_cubic(elapsed / duration))
		_anim.held_gem_visual["current_pos"] = pos
		if elapsed >= duration:
			_anim.held_gem_visual["phase"] = "orbit"
			_anim.held_gem_visual["orbit_angle"] = _orbit_angle_from_position(pos)
	else:
		_anim.held_gem_visual["orbit_angle"] = float(_anim.held_gem_visual.get("orbit_angle", 0.0)) + scaled_dt * _GEM_ORBIT_SPEED
		_anim.held_gem_visual["bob_time"] = float(_anim.held_gem_visual.get("bob_time", 0.0)) + scaled_dt * _GEM_BOB_SPEED
		_anim.held_gem_visual["current_pos"] = _current_player_orbit_position(_anim.held_gem_visual)
	return true

func _step_inserting_gem_visual(visual: Dictionary, scaled_dt: float) -> bool:
	var duration := maxf(float(visual.get("duration", 0.01)), 0.01)
	var elapsed := minf(float(visual.get("elapsed", 0.0)) + scaled_dt, duration)
	visual["elapsed"] = elapsed
	var from_pos: Vector2 = visual.get("from_pos", visual.get("current_pos", Vector2.ZERO))
	var to_pos := _gem_grid_anchor(visual.get("target_grid", Vector2.ZERO))
	var ctrl := (from_pos + to_pos) * 0.5 + Vector2(0.0, -float(visual.get("arc_height", IsoCoordinates.visual(36.0))))
	visual["current_pos"] = _quadratic_bezier(from_pos, ctrl, to_pos, _ease_in_out_cubic(elapsed / duration))
	return elapsed < duration

func _make_gem_visual(gem: GemState, start_pos: Vector2) -> Dictionary:
	if gem == null:
		return {}
	return {
		"uid": gem.uid,
		"gem_id": gem.gem_id,
		"texture": UnitLooks.get_gem_texture(gem),
		"tint": UnitLooks.gem_sprite_modulate(gem),
		"current_pos": start_pos,
		"phase": "orbit",
		"orbit_angle": randf() * TAU,
		"bob_time": randf() * TAU,
	}

func _consume_inserting_gem_position(gem_uid: String, fallback: Vector2) -> Vector2:
	for idx in range(_anim.inserting_gem_visuals.size() - 1, -1, -1):
		var visual: Dictionary = _anim.inserting_gem_visuals[idx]
		if str(visual.get("uid", "")) != gem_uid:
			continue
		_anim.masked_embedded_gems.erase(gem_uid)
		_anim.inserting_gem_visuals.remove_at(idx)
		return visual.get("current_pos", fallback)
	return fallback

func _gem_grid_anchor(grid: Vector2i) -> Vector2:
	return grid_to_screen(grid) + IsoCoordinates.visual_vec(_GEM_SLOT_SOURCE_OFFSET)

func _player_gem_anchor() -> Vector2:
	if state == null:
		return Vector2.ZERO
	var player := state.get_player()
	if player == null or not player.alive:
		return Vector2.ZERO
	var fp := player.footprint_size
	var visual_anchor_grid := player.pos + fp - Vector2i(1, 1)
	var center := grid_to_screen(visual_anchor_grid)
	if fp != Vector2i(1, 1):
		var anchor_left := grid_to_screen(player.pos)
		center.x = (anchor_left.x + center.x) * 0.5
	return center + _anim.move_offsets.get(player.uid, Vector2.ZERO)

func _current_player_orbit_position(visual: Dictionary) -> Vector2:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return visual.get("current_pos", Vector2.ZERO)
	var angle := float(visual.get("orbit_angle", 0.0))
	var bob_time := float(visual.get("bob_time", 0.0))
	var radius_x := IsoCoordinates.visual(_GEM_ORBIT_RADIUS_X)
	var radius_y := IsoCoordinates.visual(_GEM_ORBIT_RADIUS_Y)
	return anchor + Vector2(
		cos(angle) * radius_x,
		sin(angle) * radius_y + sin(bob_time) * IsoCoordinates.visual(_GEM_BOB_AMPLITUDE)
	)

func _orbit_angle_from_position(pos: Vector2) -> float:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return 0.0
	var rel := pos - anchor
	if rel.length_squared() <= 0.0001:
		return 0.0
	var radius_x := maxf(IsoCoordinates.visual(_GEM_ORBIT_RADIUS_X), 0.001)
	var radius_y := maxf(IsoCoordinates.visual(_GEM_ORBIT_RADIUS_Y), 0.001)
	return atan2(rel.y / radius_y, rel.x / radius_x)

func _quadratic_bezier(from_pos: Vector2, ctrl: Vector2, to_pos: Vector2, t: float) -> Vector2:
	var clamped_t := clampf(t, 0.0, 1.0)
	var inv := 1.0 - clamped_t
	return inv * inv * from_pos + 2.0 * inv * clamped_t * ctrl + clamped_t * clamped_t * to_pos

func _ease_out_cubic(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped_t, 3.0)

func _ease_in_out_cubic(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	if clamped_t < 0.5:
		return 4.0 * clamped_t * clamped_t * clamped_t
	return 1.0 - pow(-2.0 * clamped_t + 2.0, 3.0) * 0.5

func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")

func _add_particle(spec: Dictionary) -> void:
	_ensure_particle_fx()
	if _particle_fx != null:
		_particle_fx.add(spec)

func _push_sprite_sequence(cfg: Dictionary) -> bool:
	_ensure_particle_fx()
	return _particle_fx.push_sprite_sequence(cfg) if _particle_fx != null else false


## 播放伤害/爆炸特效



