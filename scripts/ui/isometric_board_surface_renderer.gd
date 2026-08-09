extends "res://scripts/ui/isometric_board_unit_renderer.gd"

func _queue_back_layer_redraw() -> void:
	if _back_overlay_layer != null:
		_back_overlay_layer.queue_redraw()

func set_hover(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	_queue_back_layer_redraw()

func _sorted_cells() -> Array[Vector2i]:
	var size := _board_size()
	if _sorted_cells_cache.is_empty() or size != _sorted_cells_cache_size or invert_origin != _sorted_cells_cache_invert:
		_sorted_cells_cache = IsoCoordinates.sorted_cells(size, invert_origin)
		_sorted_cells_cache_size = size
		_sorted_cells_cache_invert = invert_origin
	return _sorted_cells_cache

func _draw() -> void:
	_draw_count += 1
	if state == null:
		_clear_water_visuals()
		return
	var startup_draw_started := Time.get_ticks_usec() if _startup_first_draw_duration_usec == 0 else 0
	var startup_phase_started := startup_draw_started
	var drawn_units: Dictionary = {}
	var unit_contexts: Dictionary = {}
	var drawn_entities: Dictionary = {}
	var drawn_entity_ui: Dictionary = {}
	for grid in _sorted_cells():
		_draw_entity_at_grid(grid, drawn_entities)
		if state.get_unit_at(grid) == null and state.get_entity_at(grid) != null:
			_draw_front_tile_overlay_at(grid, true)
		_draw_dropped_gems_at_grid(grid)
	BattleCorpseRenderer.draw(self, state, _unit_draw_context, _draw_gem_icons)
	_draw_unit_ground_outlines()
	_draw_gem_visuals(false)
	if startup_draw_started > 0:
		_startup_first_draw_phases["ground_ms"] = float(Time.get_ticks_usec() - startup_phase_started) / 1000.0
		startup_phase_started = Time.get_ticks_usec()
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive and not drawn_units.has(unit.uid):
			drawn_units[unit.uid] = true
			var unit_context := _unit_draw_context(unit)
			unit_contexts[unit.uid] = unit_context
			_draw_unit_body(unit, unit_context)
		if unit != null and unit.alive:
			_draw_front_tile_overlay_at(grid, true)
	_draw_overlay_routes(self, true)
	if startup_draw_started > 0:
		_startup_first_draw_phases["unit_body_ms"] = float(Time.get_ticks_usec() - startup_phase_started) / 1000.0
		startup_phase_started = Time.get_ticks_usec()
	for grid in _sorted_cells():
		var entity := state.get_entity_at(grid)
		if entity != null and entity.alive and not drawn_entity_ui.has(entity.uid):
			drawn_entity_ui[entity.uid] = true
			_draw_entity_ui(entity)
	if startup_draw_started > 0:
		_startup_first_draw_phases["entity_ui_ms"] = float(Time.get_ticks_usec() - startup_phase_started) / 1000.0
		startup_phase_started = Time.get_ticks_usec()
	var drawn_unit_ui: Dictionary = {}
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive and not drawn_unit_ui.has(unit.uid):
			drawn_unit_ui[unit.uid] = true
			_draw_unit_ui(unit, unit_contexts.get(unit.uid, {}))
	_draw_gem_visuals(true)
	_draw_unit_slot_panels()
	if startup_draw_started > 0:
		_startup_first_draw_phases["unit_ui_ms"] = float(Time.get_ticks_usec() - startup_phase_started) / 1000.0
		_startup_first_draw_duration_usec = Time.get_ticks_usec() - startup_draw_started

func get_draw_count() -> int:
	return _draw_count

func _step_combat_fx_background_warmup() -> void:
	if _combat_fx_warmup_stage < 0:
		_combat_fx_warmup_stage += 1
		return
	match _combat_fx_warmup_stage:
		0:
			_ensure_shader_fx_pool()
		1:
			_ensure_particle_fx()
		2:
			_ensure_projectile_fx()
		3:
			_ensure_light_beam_fx()
		_:
			return
	_combat_fx_warmup_stage += 1

func _ensure_beam_layer() -> void:
	if _beam_layer == null:
		_beam_layer = Control.new()
		_beam_layer.name = "BeamLayer"
		_beam_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_beam_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_beam_layer)

func _ensure_fx_textures() -> void:
	if _fx_textures != null:
		return
	var textures_script := _resources.board_fx_textures_script() as Script
	if textures_script != null:
		_fx_textures = textures_script.new()

func _ensure_shader_fx_pool() -> void:
	_ensure_beam_layer()
	if _shader_fx_pool == null:
		var pool_script := _resources.shader_fx_pool_script() as Script
		if pool_script != null:
			_shader_fx_pool = pool_script.new()
			_shader_fx_pool.configure(_beam_layer)
	if _shader_fx_warmup == null and _shader_fx_pool != null:
		var warmup_script := _resources.shader_fx_warmup_script() as Script
		if warmup_script != null:
			_shader_fx_warmup = warmup_script.new()
			add_child(_shader_fx_warmup)
			_shader_fx_warmup.configure(
				_shader_fx_pool,
				_resources,
				[_LIGHTNING_FX_POOL_SIZE, _RADIAL_FX_POOL_SIZE, _CLOUD_FX_POOL_SIZE]
			)

func _ensure_light_beam_fx() -> void:
	if _light_beam_fx != null:
		return
	_ensure_beam_layer()
	var light_beam_script := _resources.light_beam_fx_script() as Script
	if light_beam_script != null:
		_light_beam_fx = light_beam_script.new()
		_light_beam_fx.name = "LightBeamFx"
		_light_beam_fx.configure(Callable(self, "grid_to_screen"))
		_beam_layer.add_child(_light_beam_fx)

func _ensure_projectile_fx() -> void:
	if _projectile_fx != null:
		return
	_ensure_beam_layer()
	_ensure_fx_textures()
	var projectile_script := _resources.projectile_fx_script() as Script
	if projectile_script != null:
		_projectile_fx = projectile_script.new()
		_projectile_fx.name = "ProjectileFx"
		_projectile_fx.configure(Callable(self, "grid_to_screen"), _fx_textures)
		_projectile_fx.finished.connect(_on_projectile_fx_finished)
		_beam_layer.add_child(_projectile_fx)

func _ensure_particle_fx() -> void:
	if _particle_fx != null:
		return
	_ensure_beam_layer()
	_ensure_fx_textures()
	var particle_script := _resources.particle_fx_script() as Script
	if particle_script != null:
		_particle_fx = particle_script.new()
		_particle_fx.name = "ParticleFx"
		_particle_fx.configure(_fx_textures)
		_beam_layer.add_child(_particle_fx)

func _spawn_shader_rect_fx(
	shader: Shader,
	center: Vector2,
	fx_size: Vector2,
	duration: float,
	params: Dictionary = {},
	rotation: float = 0.0
) -> Control:
	_ensure_shader_fx_pool()
	if _beam_layer == null or shader == null:
		return null
	_shader_fx_seed += 1
	var shader_key: String = _shader_fx_pool.key_for(shader)
	var rect: ColorRect = _shader_fx_pool.acquire(shader)
	rect.size = fx_size
	rect.position = center - fx_size * 0.5
	rect.pivot_offset = fx_size * 0.5
	rect.rotation = rotation
	var material := rect.material as ShaderMaterial
	for old_key in rect.get_meta("shader_fx_param_keys", []):
		material.set_shader_parameter(str(old_key), null)
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("seed", float(_shader_fx_seed))
	for key in params.keys():
		material.set_shader_parameter(str(key), params[key])
	rect.set_meta("shader_fx_param_keys", params.keys())
	rect.visible = true
	_beam_layer.move_child(rect, _beam_layer.get_child_count() - 1)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		if not is_instance_valid(rect):
			return
		var live_material := rect.material as ShaderMaterial
		if live_material != null:
			live_material.set_shader_parameter("progress", v)
	, 0.0, 1.0, _scaled_duration(duration))
	tween.tween_callback(func() -> void:
		if is_instance_valid(rect):
			_shader_fx_pool.release(shader_key, rect)
	)
	return rect

func _ensure_water_layers() -> void:
	if _water_fill_layer != null:
		return
	_water_fill_layer = WaterLayerClass.new()
	_water_fill_layer.name = "WaterFillLayer"
	_water_fill_layer.layer_kind = WaterLayerClass.LayerKind.FILL
	_water_fill_layer.show_behind_parent = true
	_water_fill_layer.z_index = 0
	add_child(_water_fill_layer)
	_shallow_water_layer = ShallowWaterLayerClass.new()
	_shallow_water_layer.name = "ShallowWaterLayer"
	_shallow_water_layer.show_behind_parent = true
	_shallow_water_layer.z_index = 0
	add_child(_shallow_water_layer)
	_water_edge_layer = WaterLayerClass.new()
	_water_edge_layer.name = "WaterEdgeLayer"
	_water_edge_layer.layer_kind = WaterLayerClass.LayerKind.EDGE
	_water_edge_layer.show_behind_parent = true
	_water_edge_layer.z_index = 0
	add_child(_water_edge_layer)

func _ensure_water_resources() -> void:
	if _water_fill_layer.material is ShaderMaterial:
		return
	_water_fill_layer.fill_image_top = _load_generated_image("res://assets/tiles/waterMaskTop.generated.png")
	_water_fill_layer.fill_image_right = _load_generated_image("res://assets/tiles/waterMaskRight.generated.png")
	_water_edge_layer.edge_image_top = _load_generated_image("res://assets/tiles/waterEdgeTop.generated.png")
	_water_edge_layer.edge_image_right = _load_generated_image("res://assets/tiles/waterEdgeRight.generated.png")
	var fill_material := ShaderMaterial.new()
	fill_material.shader = _resources.load_resource(BattleBoardResourcesScript.WATER_TILE_SHADER_PATH) as Shader
	fill_material.set_shader_parameter("base_color", Color("95e9fa"))
	fill_material.set_shader_parameter("water_bottom", _resources.load_resource(BattleBoardResourcesScript.WATER_BOTTOM_TEXTURE_PATH) as Texture2D)
	fill_material.set_shader_parameter("water_top", _resources.load_resource(BattleBoardResourcesScript.WATER_TOP_TEXTURE_PATH) as Texture2D)
	_water_fill_layer.material = fill_material

func _load_generated_texture(path: String) -> Texture2D:
	var image := _load_generated_image(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

func _load_generated_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null

func _clear_water_visuals() -> void:
	_water_visual_signature = -1
	if _water_fill_layer != null:
		_water_fill_layer.set_cells([])
	if _water_edge_layer != null:
		_water_edge_layer.set_cells([])

func _sync_water_visuals() -> void:
	if state == null:
		_clear_water_visuals()
		return
	var water := _water_cell_set()
	if water.is_empty():
		_clear_water_visuals()
		return
	_ensure_water_layers()
	_ensure_water_resources()
	var signature := hash([
		state.get_instance_id(),
		IsoCoordinates.tile_scale,
		_board_origin,
		invert_origin,
		state.tiles.size(),
	])
	for tile in state.tiles.values():
		if tile == null or tile.tile_id != Constants.TILE_WATER:
			continue
		var edge_states := WaterAutotileClass.states(tile.pos, water)
		signature = hash(Vector4i(signature, hash(tile.pos), hash(edge_states), 0))
	if signature == _water_visual_signature:
		return

	var cells: Array = []
	for tile in state.tiles.values():
		if tile == null or tile.tile_id != Constants.TILE_WATER:
			continue
		var edge_states := WaterAutotileClass.states(tile.pos, water)
		var cell := {
			"center": grid_to_screen(tile.pos),
			"half_w": IsoCoordinates._half_w(),
			"half_h": IsoCoordinates._half_h(),
			"top": edge_states.x,
			"right": edge_states.y,
			"bottom": edge_states.z,
			"left": edge_states.w,
		}
		cells.append(cell)
	_water_visual_signature = signature
	_water_fill_layer.set_cells(cells)
	_water_edge_layer.set_cells(cells)

func _water_cell_set() -> Dictionary:
	var water := {}
	for tile in state.tiles.values():
		if tile != null and tile.tile_id == Constants.TILE_WATER:
			water[tile.pos] = true
	return water

func configure_unit_slot_panels(
	action: String,
	check_fn: Callable = Callable(),
	range_check_fn: Callable = Callable()
) -> void:
	if action.is_empty() and _slot_panel_renderer == null:
		return
	var renderer = _ensure_slot_panel_renderer()
	if renderer == null:
		return
	renderer.configure(action, check_fn, range_check_fn)
	queue_redraw()

func set_slot_hover(screen_pos: Vector2) -> void:
	if _slot_panel_renderer == null:
		return
	if _slot_panel_renderer.set_hover(screen_pos, state, Callable(self, "_unit_panel_anchor")):
		queue_redraw()

func clear_unit_slot_panels() -> void:
	configure_unit_slot_panels("")

func pick_unit_slot(screen_pos: Vector2) -> Dictionary:
	if _slot_panel_renderer == null:
		return {}
	return _slot_panel_renderer.pick(screen_pos, state, Callable(self, "_unit_panel_anchor"))

func _ensure_slot_panel_renderer():
	if _slot_panel_renderer != null:
		return _slot_panel_renderer
	var renderer_script := _resources.unit_slot_panel_renderer_script() as Script
	if renderer_script != null:
		_slot_panel_renderer = renderer_script.new()
	return _slot_panel_renderer

func _draw_entity_at_grid(grid: Vector2i, drawn_entities: Dictionary) -> void:
	var entity := state.get_entity_at(grid)
	if entity == null or not entity.alive or drawn_entities.has(entity.uid):
		return
	drawn_entities[entity.uid] = true
	var center := grid_to_screen(entity.pos)
	match entity.entity_id:
		Constants.ENTITY_SPIKE:
			TileRenderer.draw_entity_texture(self, center, _resources.load_resource(BattleBoardResourcesScript.ENTITY_SPIKE_TEXTURE_PATH) as Texture2D, 0.86)
		Constants.ENTITY_PROP:
			_draw_prop_entity(entity, center)
		Constants.ENTITY_ROCK:
			TileRenderer.draw_entity_texture(self, center, _resources.load_resource(BattleBoardResourcesScript.ENTITY_ROCK_TEXTURE_PATH) as Texture2D, 0.72)
		Constants.ENTITY_BARREL:
			TileRenderer.draw_entity_texture(self, center, _resources.load_resource(BattleBoardResourcesScript.ENTITY_BARREL_TEXTURE_PATH) as Texture2D, 0.78)
		_:
			TileRenderer.draw_prop_fallback(self, center)

func _draw_dropped_gems_at_grid(grid: Vector2i) -> void:
	if state == null or _gem_sprites == null:
		return
	var drops: Array[Dictionary] = []
	for raw_drop in state.dropped_gems.values():
		if not raw_drop is Dictionary:
			continue
		var drop := raw_drop as Dictionary
		if drop.get("pos", Vector2i(-999, -999)) == grid:
			drops.append(drop)
	if drops.is_empty():
		return
	drops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("gem_uid", "")) < str(b.get("gem_uid", ""))
	)
	var center := grid_to_screen(grid) + Vector2(0.0, IsoCoordinates.visual(4.0))
	var spacing := IsoCoordinates.visual(12.0)
	var size := IsoCoordinates.visual(13.0)
	var start_x := -spacing * float(drops.size() - 1) * 0.5
	for i in range(drops.size()):
		var gem_uid := str(drops[i].get("gem_uid", ""))
		var gem: GemState = state.gems.get(gem_uid, null)
		if gem == null:
			continue
		var pos := center + Vector2(start_x + spacing * float(i), 0.0)
		_draw_soft_backdrop(pos + Vector2(0.0, IsoCoordinates.visual(5.0)), size * 0.55, size * 0.24, Color(0.0, 0.0, 0.0, 0.42))
		var tex: Texture2D = _gem_sprites.texture_for_gem_id(gem.gem_id)
		var tint: Color = _gem_sprites.modulate_for_gem_id(gem.gem_id)
		if tex != null:
			draw_texture_rect(tex, Rect2(pos - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, tint)
		else:
			_draw_small_diamond(pos, size * 0.42, size * 0.32, tint)
		if bool(drops[i].get("old_mage_pool", false)):
			OldMageBoardVisuals.draw_pool_marker(self, pos, size)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("battle_editor_tool"):
		return false
	var cell := pick_cell(at_position)
	var has_cell := cell.x >= 0
	editor_tool_drag_hovered.emit(data.get("battle_editor_tool", {}), cell, has_cell)
	return has_cell

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary or not data.has("battle_editor_tool"):
		return
	var cell := pick_cell(at_position)
	editor_tool_dropped.emit(data.get("battle_editor_tool", {}), cell, cell.x >= 0)

func _draw_prop_entity(entity: EntityState, center: Vector2) -> void:
	if _prop_sprites == null or entity.prop_sprite.is_empty():
		TileRenderer.draw_prop_fallback(self, center)
		return
	var tex: Texture2D = _prop_sprites.texture_for_sprite_id(entity.prop_sprite)
	if tex == null:
		TileRenderer.draw_prop_fallback(self, center)
		return
	var foot_ratio: float = _prop_sprites.foot_ratio_for_sprite_id(entity.prop_sprite)
	TileRenderer.draw_prop_sprite(self, center, tex, foot_ratio)

func _draw_entity_ui(entity: EntityState) -> void:
	if entity.max_hp <= 0:
		return
	var center := grid_to_screen(entity.pos)
	var foot := center + IsoCoordinates.entity_foot_offset()
	var width := IsoCoordinates.visual(30.0)
	var height := IsoCoordinates.visual(4.0)
	var top := foot.y - IsoCoordinates.visual(65.0)
	BattleUiTheme.draw_combined_hp_bar(
		self,
		Rect2(foot.x - width * 0.5, top, width, height),
		entity.hp,
		entity.max_hp,
		0
	)

func _draw_editor_preview(canvas: Control) -> void:
	if not editor_preview_active or editor_preview_cells.is_empty():
		return
	var outline := Color(UiPalette.HILITE_REACH, 0.96) if editor_preview_valid else Color(UiPalette.HILITE_DANGER, 0.96)
	var fill := Color(UiPalette.HILITE_REACH, 0.22) if editor_preview_valid else Color(UiPalette.HILITE_DANGER, 0.2)
	for cell in editor_preview_cells:
		var corners := IsoCoordinates.diamond_corners(grid_to_screen(cell))
		canvas.draw_colored_polygon(corners, fill)
		var closed := corners.duplicate()
		closed.append(corners[0])
		canvas.draw_polyline(closed, outline, IsoCoordinates.visual(2.0), false)

func _draw_overlay_outlines(canvas: Control) -> void:
	if overlay_specs.is_empty():
		return
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	for raw_overlay in overlay_specs:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var kind := str(overlay.get("kind", ""))
		var cells: Array = overlay.get("cells", [])
		if cells.is_empty():
			continue
		var base_color := _overlay_outline_color(kind, pulse)
		var base_width := _overlay_line_width(kind)
		for raw_cell in cells:
			var cell: Vector2i = raw_cell
			var color := base_color
			var width := base_width
			if cell == hover_cell:
				color = color.lightened(0.18)
				color.a = minf(1.0, color.a + 0.12)
				width += IsoCoordinates.visual(0.6)
			_draw_cell_outline(canvas, cell, color, width)

func _draw_map_room_nameplates() -> void:
	if state == null or state.encounter_id != "adventure_map":
		return
	var cells: Dictionary = {}
	for raw_overlay in overlay_specs:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var kind := str(overlay.get("kind", ""))
		if kind not in ["map_current", "map_choice", "map_focus"]:
			continue
		var priority := 2 if kind == "map_current" else (1 if kind == "map_focus" else 0)
		for raw_cell in overlay.get("cells", []):
			var cell: Vector2i = raw_cell
			cells[cell] = maxi(int(cells.get(cell, -1)), priority)
	if state.get_tile(hover_cell) != null:
		cells[hover_cell] = 3
	for cell in cells.keys():
		var tile := state.get_tile(cell)
		if tile == null or not AdventureRoomDisplay.is_room_tile(tile.tile_id):
			continue
		var display: Dictionary = AdventureRoomDisplay.get_display(
			AdventureRoomDisplay.room_type_from_tile(tile.tile_id),
			AdventureService.get_current_chapter(),
			AdventureService.get_chapter_count()
		)
		var color: Color = display.get("color", UiPalette.ROOM_UNKNOWN)
		_draw_map_room_nameplate(cell, str(display.get("label", "")), color, int(cells[cell]))

func _draw_map_room_nameplate(cell: Vector2i, label: String, color: Color, priority: int) -> void:
	if label.is_empty():
		return
	var font := BattleUiTheme.pixel_font()
	var font_size := 11 if priority < 2 else 12
	var center := grid_to_screen(cell)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := IsoCoordinates.visual_vec(Vector2(5.0, 3.0))
	var rect := Rect2(
		center.x - text_size.x * 0.5 - pad.x,
		center.y + IsoCoordinates.visual(7.0),
		text_size.x + pad.x * 2.0,
		text_size.y + pad.y * 2.0
	)
	var bg_alpha := 0.72 if priority < 2 else 0.86
	draw_rect(rect, Color(UiPalette.BG_INSET, bg_alpha), true)
	draw_rect(rect, Color(color.lightened(0.08), 0.55 + float(priority) * 0.08), false, IsoCoordinates.visual(1.0))
	var text_pos := Vector2(rect.position.x + pad.x, rect.position.y + text_size.y + pad.y * 0.3)
	_draw_text_with_shadow(font, text_pos, label, font_size, UiPalette.TEXT_BRIGHT, UiPalette.TEXT_OUTLINE)

func _draw_overlay_routes(canvas: Control, arrow_only: bool = false) -> void:
	if overlay_routes.is_empty():
		return
	for raw_route in overlay_routes:
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var path: Array = route.get("path", [])
		if path.size() < 2:
			continue
		var points := PackedVector2Array()
		var route_unit: UnitState = null
		var route_uid := str(route.get("unit_uid", ""))
		if state != null and not route_uid.is_empty():
			route_unit = state.units.get(route_uid, null)
		for raw_cell in path:
			var cell: Vector2i = raw_cell
			points.append(_footprint_screen_center_at(route_unit, cell))
		if points.size() < 2:
			continue
		var kind := str(route.get("kind", ""))
		var color := _route_color(kind)
		var width := IsoCoordinates.visual(3.2 if kind == "move" else 3.0)
		if arrow_only:
			if bool(route.get("show_arrow", true)):
				_draw_route_arrow(canvas, points, color, width, bool(route.get("arrow_reverse", false)))
			continue
		var outline := Color(0.02, 0.04, 0.06, minf(0.5, color.a + 0.18))
		canvas.draw_polyline(points, outline, width + IsoCoordinates.visual(2.0), true)
		canvas.draw_polyline(points, color, width, true)

func _draw_route_arrow(canvas: Control, points: PackedVector2Array, color: Color, _width: float, reverse_direction: bool) -> void:
	if points.size() < 2:
		return
	var end_pos: Vector2 = points[0] if reverse_direction else points[points.size() - 1]
	var prev_pos: Vector2 = points[1] if reverse_direction else points[points.size() - 2]
	var direction: Vector2 = end_pos - prev_pos
	if direction.length() < 0.01:
		return
	var texture: Texture2D
	if direction.x >= 0.0:
		texture = _resources.load_resource(BattleBoardResourcesScript.ROUTE_ARROW_TEXTURE_PATHS[0] if direction.y < 0.0 else BattleBoardResourcesScript.ROUTE_ARROW_TEXTURE_PATHS[1]) as Texture2D
	else:
		texture = _resources.load_resource(BattleBoardResourcesScript.ROUTE_ARROW_TEXTURE_PATHS[3] if direction.y < 0.0 else BattleBoardResourcesScript.ROUTE_ARROW_TEXTURE_PATHS[2]) as Texture2D
	if texture == null:
		return
	var draw_size := Vector2(IsoCoordinates.visual(64.0), IsoCoordinates.visual(32.0))
	canvas.draw_texture_rect(texture, Rect2(end_pos - draw_size * 0.5, draw_size), false, Color(color.r, color.g, color.b, maxf(0.88, color.a)))

func _draw_tile(canvas: Control, grid: Vector2i) -> void:
	var center := grid_to_screen(grid)
	var tile := state.get_tile(grid)
	var highlight := _tile_highlight(grid)
	# 地砖底由 Grids 贴图统一绘制，这里只叠加高亮与特殊地块（水/柱/毒/火等）
	TileRenderer.draw_tile_overlays(
		canvas, center, tile, highlight, TileRenderer.PASS_BACK, false,
		_poison_cloud_lifecycle.visuals_for_cell(grid)
	)

func _draw_front_tile_overlay_at(grid: Vector2i, occupied: bool = false) -> void:
	if not occupied:
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive:
			occupied = true
		elif state.get_entity_at(grid) != null:
			occupied = true
	if not occupied:
		return
	var tile := state.get_tile(grid)
	if tile == null:
		return
	TileRenderer.draw_tile_overlays(
		self,
		grid_to_screen(grid),
		tile,
		Color.TRANSPARENT,
		TileRenderer.PASS_FRONT,
		true,
		_poison_cloud_lifecycle.visuals_for_cell(grid)
	)

func _tile_highlight(grid: Vector2i) -> Color:
	return _tile_overlay_highlight(grid, overlay_specs)

func _tile_overlay_highlight(grid: Vector2i, overlays: Array) -> Color:
	var best_kind := ""
	var best_priority := -999
	for raw_overlay in overlays:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var cells: Array = overlay.get("cells", [])
		if not grid in cells:
			continue
		var kind := str(overlay.get("kind", ""))
		var priority := _overlay_priority(kind)
		if priority >= best_priority:
			best_priority = priority
			best_kind = kind
	if best_kind.is_empty():
		return Color.TRANSPARENT
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	var base := _overlay_base_color(best_kind)
	var alpha := _overlay_fill_alpha(best_kind, pulse)
	if grid == hover_cell:
		alpha = minf(0.78, alpha + 0.14)
	return Color(base, alpha)

func _overlay_priority(kind: String) -> int:
	match kind:
		"critical":
			return 110
		"safe":
			return 100
		"danger":
			return 90
		"effect":
			return 80
		"target":
			return 70
		"map_focus":
			return 68
		"map_current":
			return 66
		"map_choice":
			return 60
		"map_future":
			return 24
		"intent_path":
			return 50
		"attack_range":
			return 40
		"move":
			return 30
		"map_resolved":
			return 10
	return 0

func _overlay_base_color(kind: String) -> Color:
	match kind:
		"critical":
			return UiPalette.HILITE_DANGER.lightened(0.1)
		"safe":
			return UiPalette.HILITE_REACH
		"move":
			return UiPalette.HILITE_MOVE
		"attack_range":
			return UiPalette.HILITE_RANGE.darkened(0.08)
		"target":
			return UiPalette.HILITE_TARGET
		"danger":
			return UiPalette.HILITE_DANGER
		"effect":
			return UiPalette.FIRE_ORANGE
		"intent_path":
			return UiPalette.INTENT_MOVE
		"map_focus":
			return UiPalette.TEXT_GOLD
		"map_current":
			return UiPalette.ROOM_START
		"map_choice":
			return UiPalette.ROOM_EXIT
		"map_future":
			return UiPalette.EDGE_BRIGHT
		"map_resolved":
			return UiPalette.EDGE_LIGHT
	return UiPalette.TEXT_BRIGHT

func _overlay_fill_alpha(kind: String, pulse: float) -> float:
	match kind:
		"critical":
			return 0.46 + pulse * 0.18
		"safe":
			return 0.28 + pulse * 0.12
		"danger":
			return 0.34 + pulse * 0.18
		"effect":
			return 0.32 + pulse * 0.16
		"target":
			return 0.32 + pulse * 0.18
		"map_focus":
			return 0.30 + pulse * 0.16
		"map_current":
			return 0.36 + pulse * 0.16
		"map_choice":
			return 0.26 + pulse * 0.14
		"map_future":
			return 0.14 + pulse * 0.06
		"intent_path":
			return 0.18 + pulse * 0.12
		"attack_range":
			return 0.20 + pulse * 0.10
		"move":
			return 0.22 + pulse * 0.10
		"map_resolved":
			return 0.10
	return 0.18

func _overlay_outline_color(kind: String, pulse: float) -> Color:
	var base := _overlay_base_color(kind)
	var alpha: float = 0.62 + pulse * 0.22
	match kind:
		"critical", "safe", "target", "danger", "effect", "map_current", "map_focus":
			alpha = 0.72 + pulse * 0.22
		"move":
			alpha = 0.58 + pulse * 0.18
		"attack_range", "intent_path":
			alpha = 0.48 + pulse * 0.18
		"map_future":
			alpha = 0.26 + pulse * 0.08
		"map_resolved":
			alpha = 0.28
	return Color(base, alpha)

func _overlay_line_width(kind: String) -> float:
	match kind:
		"critical", "safe", "target", "danger", "effect", "map_current", "map_focus":
			return IsoCoordinates.visual(2.0)
		"map_choice":
			return IsoCoordinates.visual(1.8)
		"map_future":
			return IsoCoordinates.visual(1.2)
		"move", "attack_range", "intent_path":
			return IsoCoordinates.visual(1.45)
	return IsoCoordinates.visual(1.3)

func _route_color(kind: String) -> Color:
	match kind:
		"move":
			return Color(0.72, 0.96, 1.0, 0.82)
		"intent":
			return Color(UiPalette.INTENT_ATTACK.lightened(0.08), 0.36)
		"impact":
			return Color(UiPalette.INTENT_ATTACK.lightened(0.18), 0.82)
		"map_focus":
			return Color(UiPalette.TEXT_GOLD.lightened(0.06), 0.82)
		"map_choice":
			return Color(UiPalette.ROOM_EXIT.lightened(0.14), 0.32)
		"map_future":
			return Color(UiPalette.EDGE_BRIGHT, 0.22)
		"map_travel":
			return Color(UiPalette.ROOM_START.lightened(0.12), 0.72)
	return Color(UiPalette.TEXT_BRIGHT, 0.34)



