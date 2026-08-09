extends "res://scripts/ui/isometric_board_surface_renderer.gd"

func _ready() -> void:
	var ready_started_usec := Time.get_ticks_usec()
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_board_texture = get_node_or_null("Grids")
	_ensure_water_layers()
	_ensure_back_overlay_layer()
	_frozen_unit_visuals.configure(self)
	resized.connect(_update_origin)
	_update_origin()
	_knight_sprites = KNIGHT_SPRITES_SCRIPT.new()
	_player_sprites = PLAYER_SPRITES_SCRIPT.new()
	_slime_sprites = SLIME_SPRITES_SCRIPT.new("green")
	_slime_sprites_by_variant["green"] = _slime_sprites
	_gem_sprites = GEM_SPRITES_SCRIPT.new()
	_prop_sprites = PROP_SPRITES_SCRIPT.new()
	set_process(true)
	call_deferred("_sync_unit_orientations")
	_startup_ready_duration_usec = Time.get_ticks_usec() - ready_started_usec

func get_startup_ready_duration_ms() -> float:
	return float(_startup_ready_duration_usec) / 1000.0

func get_startup_first_draw_metrics() -> Dictionary:
	var metrics := _startup_first_draw_phases.duplicate()
	metrics["total_ms"] = float(_startup_first_draw_duration_usec) / 1000.0
	return metrics

func _update_origin() -> void:
	var board_sz := _board_size()
	IsoCoordinates.tile_scale = IsoCoordinates.compute_tile_scale(size, board_sz)
	_board_origin = IsoCoordinates.board_origin(size, board_sz)
	_update_board_texture_transform()
	_sync_water_visuals()
	_queue_back_layer_redraw()


## 把正方棋盘贴图映射到等距菱形上：四个角分别对到菱形上/右/下/左顶点
## （等价于旋转 45°＋纵向压扁 2:1，但用仿射矩阵一次性完成缩放与定位）

func _update_board_texture_transform() -> void:
	if _board_texture == null or _board_texture.texture == null:
		return
	# 只取非白底内容区域，裁掉四周白边，避免透明白边在菱形里占位导致格子内缩
	var region := _board_texture_content_rect()
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	_board_texture.region_enabled = true
	_board_texture.region_rect = region
	var board_sz := _board_size()
	var half_h := IsoCoordinates._half_h()
	var top := grid_to_screen(Vector2i(0, 0)) - Vector2(0, half_h)
	var bottom := grid_to_screen(Vector2i(board_sz.x - 1, board_sz.y - 1)) + Vector2(0, half_h)
	var center := (top + bottom) * 0.5
	var half_diag := IsoCoordinates.board_pixel_size(board_sz) * 0.5
	var x_axis := Vector2(half_diag.x, half_diag.y) / region.size.x
	var y_axis := Vector2(-half_diag.x, half_diag.y) / region.size.y
	_board_texture.transform = Transform2D(x_axis, y_axis, center)


## 底图内容范围由素材契约测试校验，避免每次入场扫描约 39 万个像素。
func _board_texture_content_rect() -> Rect2:
	var texture_size := _board_texture.texture.get_size()
	if not texture_size.is_equal_approx(_BOARD_TEXTURE_SOURCE_SIZE):
		return Rect2(Vector2.ZERO, texture_size)
	return _BOARD_TEXTURE_CONTENT_RECT

func _process(delta: float) -> void:
	_step_combat_fx_background_warmup()
	_anim.pulse_time += delta
	var scaled_dt := delta * _animation_speed_scale
	var back_layer_dirty := not overlay_specs.is_empty()
	var visuals_dirty := _update_overlay_fades(delta)
	var poison_dirty := _poison_cloud_lifecycle.sync(state, delta)
	visuals_dirty = poison_dirty or visuals_dirty
	back_layer_dirty = poison_dirty or back_layer_dirty
	if not active_turn_unit_uid.is_empty() and _active_aura_redraw_due():
		visuals_dirty = true
	for mv_uid in _anim.move_offsets.keys():
		if _anim.strike_elapsed.has(mv_uid):
			continue
		_anim.walk_phase[mv_uid] = _anim.walk_phase.get(mv_uid, 0.0) + scaled_dt
		visuals_dirty = true
	if state != null:
		visuals_dirty = _frozen_unit_visuals.sync_active_units(state) or visuals_dirty
		_update_overlay_shader_activity()
		if _update_gem_echo_shader_activity():
			visuals_dirty = true
		if _has_animated_tile_overlays():
			back_layer_dirty = true
		for unit: UnitState in state.units.values():
			if not unit.alive or not _uses_animated_idle(unit):
				continue
			if _anim.strike_elapsed.has(unit.uid) or _anim.move_offsets.has(unit.uid):
				continue
			visuals_dirty = _advance_unit_idle_phase(unit, scaled_dt) or visuals_dirty

	var strike_done: Array[String] = []
	for stk in _anim.strike_elapsed.keys():
		var next_t: float = float(_anim.strike_elapsed[stk]) + scaled_dt
		_anim.strike_elapsed[stk] = next_t
		visuals_dirty = true
		if next_t >= _strike_duration_for(stk):
			strike_done.append(str(stk))
	for stk_rem in strike_done:
		_anim.strike_elapsed.erase(stk_rem)
	var hit_done: Array[String] = []
	for hit_uid in _anim.hit_elapsed.keys():
		var next_hit_t := float(_anim.hit_elapsed[hit_uid]) + scaled_dt
		_anim.hit_elapsed[hit_uid] = next_hit_t
		visuals_dirty = true
		if next_hit_t >= _HIT_DURATION:
			hit_done.append(str(hit_uid))
	for hit_uid in hit_done:
		_anim.hit_elapsed.erase(hit_uid)

	var needs_redraw: bool = _particle_fx.step(delta) if _particle_fx != null else false
	var gem_dirty := _update_gem_visuals(scaled_dt)
	if (needs_redraw or visuals_dirty or gem_dirty) and _continuous_redraw_due():
		queue_redraw()
	if back_layer_dirty and _back_overlay_redraw_due():
		_queue_back_layer_redraw()

func _continuous_redraw_due() -> bool:
	var redraw_tick := floori(_anim.pulse_time * _CONTINUOUS_REDRAW_FPS)
	if redraw_tick == _last_continuous_redraw_tick:
		return false
	_last_continuous_redraw_tick = redraw_tick
	return true

func _back_overlay_redraw_due() -> bool:
	var redraw_tick := floori(_anim.pulse_time * _BACK_OVERLAY_REDRAW_FPS)
	if redraw_tick == _last_back_overlay_redraw_tick:
		return false
	_last_back_overlay_redraw_tick = redraw_tick
	return true

func _active_aura_redraw_due() -> bool:
	var redraw_tick := floori(_anim.pulse_time * _ACTIVE_AURA_REDRAW_FPS)
	if redraw_tick == _last_active_aura_redraw_tick:
		return false
	_last_active_aura_redraw_tick = redraw_tick
	return true

func _advance_unit_idle_phase(unit: UnitState, scaled_dt: float) -> bool:
	var previous_phase := float(_anim.idle_phase.get(unit.uid, 0.0))
	var next_phase := previous_phase + scaled_dt
	_anim.idle_phase[unit.uid] = next_phase
	var fps := _PLAYER_IDLE_FPS if _uses_player_sprite(unit) else _SLIME_IDLE_FPS
	return floori(previous_phase * fps) != floori(next_phase * fps)

func _ensure_back_overlay_layer() -> void:
	if _back_overlay_layer != null:
		return
	_back_overlay_layer = BattleBoardBackLayerScript.new()
	_back_overlay_layer.name = "BackOverlayLayer"
	add_child(_back_overlay_layer)
	_back_overlay_layer.configure(self)

func _has_animated_tile_overlays() -> bool:
	for tile: TileState in state.tiles.values():
		if tile != null and (
			not tile.modifiers.is_empty()
			or tile.tile_id == Constants.TILE_GRASS
			or tile.tile_id == Constants.TILE_BUSH
		):
			return true
	return _poison_cloud_lifecycle.has_visuals()

func _ensure_overlay_shader_textures() -> void:
	if not _overlay_shader_viewports.is_empty():
		return
	var specs := [
		{"path": TileRenderer.GRASS_SPROUTS_PATH, "sway": 20.0, "vertical": 0.0, "speed": 1.42, "tip_bias": 1.0, "tip_power": 1.7},
		{"path": TileRenderer.GRASS_PATCH_PATH, "sway": 19.0, "vertical": 0.0, "speed": 1.34, "tip_bias": 1.0, "tip_power": 1.65},
		{"path": TileRenderer.GRASS_TALL_PATH, "sway": 22.0, "vertical": 0.0, "speed": 1.28, "tip_bias": 1.0, "tip_power": 1.8},
		{"path": TileRenderer.GRASS_THICKET_PATH, "sway": 17.0, "vertical": 0.0, "speed": 1.18, "tip_bias": 1.0, "tip_power": 1.9},
	]
	specs.append_array(PoisonCloudRendererClass.shader_specs())
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var source := load(str(spec["path"])) as Texture2D
		if source == null:
			continue
		var viewport := SubViewport.new()
		viewport.name = "OverlayShaderViewport%d" % index
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cloud_parts := bool(spec.get("cloud_parts", false))
		var padding := 0 if cloud_parts else 64
		viewport.size = Vector2i(source.get_width() + padding, source.get_height() + padding)
		var overlay_key := str(spec.get("key", spec["path"]))
		viewport.set_meta("overlay_path", overlay_key)
		var sprite := Sprite2D.new()
		sprite.texture = source
		sprite.position = Vector2(viewport.size) * 0.5
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		if cloud_parts:
			PoisonCloudRendererClass.configure_shader_material(
				material, str(spec["effect_type"]), float(index) * 1.37
			)
		else:
			material.shader = _resources.load_resource(BattleBoardResourcesScript.OVERLAY_DRIFT_SHADER_PATH) as Shader
			material.set_shader_parameter("sway_px", float(spec["sway"]))
			material.set_shader_parameter("vertical_px", float(spec["vertical"]))
			material.set_shader_parameter("speed", float(spec["speed"]))
			material.set_shader_parameter("phase", float(index) * 1.37)
			material.set_shader_parameter("tip_bias", float(spec["tip_bias"]))
			material.set_shader_parameter("tip_power", float(spec["tip_power"]))
			material.set_shader_parameter("tint", spec.get("tint", Color.WHITE))
			material.set_shader_parameter("alpha_boost", float(spec.get("alpha_boost", 1.0)))
			material.set_shader_parameter("saturation_boost", float(spec.get("saturation_boost", 1.0)))
			material.set_shader_parameter("alpha_breathe", float(spec.get("alpha_breathe", 0.0)))
		sprite.material = material
		viewport.add_child(sprite)
		add_child(viewport)
		_overlay_shader_viewports.append(viewport)
		var source_rect: Rect2 = TileRenderer._overlay_texture_content_rect(source)
		var source_offset := (Vector2(viewport.size) - source.get_size()) * 0.5
		TileRenderer.register_animated_overlay_texture(
			overlay_key,
			viewport.get_texture(),
			Rect2(Vector2.ZERO, source.get_size())
			if cloud_parts
			else Rect2(source_offset + source_rect.position, source_rect.size)
		)

func _update_overlay_shader_activity() -> void:
	var active_paths := _active_overlay_shader_paths()
	if not active_paths.is_empty():
		_ensure_overlay_shader_textures()
	for viewport in _overlay_shader_viewports:
		var path := str(viewport.get_meta("overlay_path", ""))
		viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active_paths.has(path) else SubViewport.UPDATE_DISABLED
		)

func _active_overlay_shader_paths() -> Dictionary:
	var active := {}
	if state == null:
		return active
	for tile: TileState in state.tiles.values():
		if tile == null:
			continue
		if tile.tile_id == Constants.TILE_GRASS or tile.tile_id == Constants.TILE_BUSH:
			active[TileRenderer.GRASS_SPROUTS_PATH] = true
			active[TileRenderer.GRASS_PATCH_PATH] = true
			active[TileRenderer.GRASS_TALL_PATH] = true
			active[TileRenderer.GRASS_THICKET_PATH] = true
		if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
			active[TileRenderer.POISON_FOG_CLOUD_TEXTURE_KEY] = true
		if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
			active[TileRenderer.TOXIC_SMOKE_CLOUD_TEXTURE_KEY] = true
	for effect_type in _poison_cloud_lifecycle.active_effects():
		active[
			TileRenderer.TOXIC_SMOKE_CLOUD_TEXTURE_KEY
			if effect_type == Constants.TILE_MOD_TOXIC_SMOKE
			else TileRenderer.POISON_FOG_CLOUD_TEXTURE_KEY
		] = true
	return active

func _update_gem_echo_shader_activity() -> bool:
	var active_gem_ids := _active_gem_echo_ids()
	var active := not active_gem_ids.is_empty()
	if active:
		_ensure_gem_echo_shader_texture()
		for gem_id in active_gem_ids.keys():
			_ensure_gem_echo_icon_shader_texture(str(gem_id))
	if _gem_echo_shader_viewport != null:
		_gem_echo_shader_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)
	for gem_id in _gem_echo_icon_viewports.keys():
		var viewport: SubViewport = _gem_echo_icon_viewports[gem_id]
		viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active_gem_ids.has(gem_id) else SubViewport.UPDATE_DISABLED
		)
	return active

func _active_gem_echo_ids() -> Dictionary:
	var result := {}
	if state == null:
		return result
	for raw_uid in state.overload_echo_gems.keys():
		var gem: GemState = state.gems.get(str(raw_uid), null)
		if gem != null and not gem.gem_id.is_empty():
			result[gem.gem_id] = true
	return result

func _ensure_gem_echo_shader_texture() -> void:
	if _gem_echo_shader_viewport != null:
		return
	_gem_echo_shader_viewport = SubViewport.new()
	_gem_echo_shader_viewport.name = "GemEchoShaderViewport"
	_gem_echo_shader_viewport.disable_3d = true
	_gem_echo_shader_viewport.transparent_bg = true
	_gem_echo_shader_viewport.size = Vector2i(64, 64)
	_gem_echo_shader_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var smoke := ColorRect.new()
	smoke.size = Vector2(_gem_echo_shader_viewport.size)
	smoke.color = Color.WHITE
	smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = _resources.load_resource(BattleBoardResourcesScript.GEM_ECHO_SMOKE_SHADER_PATH) as Shader
	smoke.material = material
	_gem_echo_shader_viewport.add_child(smoke)
	add_child(_gem_echo_shader_viewport)
	_gem_echo_smoke_texture = _gem_echo_shader_viewport.get_texture()

func _ensure_gem_echo_icon_shader_texture(gem_id: String) -> void:
	if _gem_echo_icon_viewports.has(gem_id) or _gem_sprites == null:
		return
	var source: Texture2D = _gem_sprites.texture_for_gem_id(gem_id)
	if source == null:
		return
	var viewport := SubViewport.new()
	viewport.name = "GemEchoIconShaderViewport%d" % _gem_echo_icon_viewports.size()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(source.get_width(), source.get_height())
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.set_meta("gem_id", gem_id)
	var sprite := Sprite2D.new()
	sprite.texture = source
	sprite.position = Vector2(viewport.size) * 0.5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = _resources.load_resource(BattleBoardResourcesScript.GEM_ECHO_ICON_SHADER_PATH) as Shader
	sprite.material = material
	viewport.add_child(sprite)
	add_child(viewport)
	_gem_echo_icon_viewports[gem_id] = viewport
	_gem_echo_icon_textures[gem_id] = viewport.get_texture()

func _update_overlay_fades(delta: float) -> bool:
	var name_targets: Array[String] = []
	var hover_targets: Array[String] = []
	var selection_targets: Array[String] = []
	var active_targets: Array[String] = []
	if state != null:
		for unit: UnitState in state.units.values():
			if not unit.alive:
				continue
			var uid := unit.uid
			if uid == selected_unit_uid or uid == timeline_hover_unit_uid:
				name_targets.append(uid)
			if uid == timeline_hover_unit_uid:
				hover_targets.append(uid)
			if uid == selected_unit_uid:
				selection_targets.append(uid)
			if uid == active_turn_unit_uid:
				active_targets.append(uid)
	var dirty := false
	dirty = _step_unit_fade(_nameplate_alpha_by_uid, name_targets, delta) or dirty
	dirty = _step_unit_fade(_hover_outline_alpha_by_uid, hover_targets, delta) or dirty
	dirty = _step_unit_fade(_selection_outline_alpha_by_uid, selection_targets, delta) or dirty
	dirty = _step_unit_fade(_active_aura_alpha_by_uid, active_targets, delta) or dirty
	return dirty

func _step_unit_fade(store: Dictionary, target_uids: Array[String], delta: float) -> bool:
	var targets: Dictionary = {}
	for uid in target_uids:
		targets[uid] = true
	var tracked: Dictionary = {}
	for uid in store.keys():
		tracked[uid] = true
	for uid in targets.keys():
		tracked[uid] = true
	var dirty := false
	for uid_value in tracked.keys():
		var uid := str(uid_value)
		var current := float(store.get(uid, 0.0))
		var target := 1.0 if targets.has(uid) else 0.0
		var speed := 12.0 if target > current else 4.5
		var next := move_toward(current, target, delta * speed)
		if absf(next - current) > 0.0001:
			dirty = true
		if next <= 0.001 and target <= 0.0:
			store.erase(uid)
		else:
			store[uid] = next
	return dirty

func set_battle_state(new_state: GameState) -> void:
	state = new_state

func init_unit_orientations() -> void:
	_sync_unit_orientations()

func _sync_unit_orientations() -> void:
	if state == null:
		return
	var player_cells: Array[Vector2i] = []
	var enemy_cells: Array[Vector2i] = []
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var center := _get_unit_screen_center(unit)
		if unit.team == Constants.TEAM_PLAYER:
			player_cells.append(Vector2i(int(center.x), int(center.y)))
		else:
			enemy_cells.append(Vector2i(int(center.x), int(center.y)))
	if player_cells.is_empty() or enemy_cells.is_empty():
		return
	var player_centroid := _screen_centroid(player_cells)
	var enemy_centroid := _screen_centroid(enemy_cells)
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var from_screen := _get_unit_screen_center(unit)
		var target_screen := enemy_centroid if unit.team == Constants.TEAM_PLAYER else player_centroid
		unit.facing = _facing_from_screen_delta(from_screen, target_screen, unit.facing)

func _screen_centroid(screen_points: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO
	for p in screen_points:
		sum += Vector2(p)
	return sum / screen_points.size()

func set_overlays(new_overlays: Array, new_routes: Array = []) -> void:
	overlay_specs = new_overlays.duplicate(true)
	overlay_routes = new_routes.duplicate(true)
	_queue_back_layer_redraw()
	queue_redraw()

func clear_overlays() -> void:
	overlay_specs.clear()
	overlay_routes.clear()
	_queue_back_layer_redraw()
	queue_redraw()

func set_editor_preview(cells: Array[Vector2i], valid: bool, active: bool = true) -> void:
	editor_preview_cells = cells.duplicate()
	editor_preview_valid = valid
	editor_preview_active = active
	_queue_back_layer_redraw()

func clear_editor_preview() -> void:
	set_editor_preview([], false, false)

func set_timeline_hover_unit(uid: String) -> void:
	if timeline_hover_unit_uid == uid:
		return
	timeline_hover_unit_uid = uid
	queue_redraw()

func set_active_turn_unit(uid: String) -> void:
	if active_turn_unit_uid == uid:
		return
	active_turn_unit_uid = uid
	_last_active_aura_redraw_tick = -1
	queue_redraw()
