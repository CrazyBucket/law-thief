extends "res://scripts/ui/isometric_board_motion.gd"

func _display_gem_texture(gem: GemState, fallback: Texture2D) -> Texture2D:
	if gem != null and GemEchoVisuals.is_echo(state, gem.uid):
		return _gem_echo_icon_textures.get(gem.gem_id, fallback) as Texture2D
	return fallback

func _draw_echo_smoke(gem_uid: String, pos: Vector2, icon_size: float, alpha: float = 1.0) -> void:
	if not GemEchoVisuals.is_echo(state, gem_uid) or _gem_echo_smoke_texture == null:
		return
	var gem: GemState = state.gems.get(gem_uid, null)
	if gem == null:
		return
	var content_bounds := _gem_content_bounds(gem.gem_id)
	var pulse := 0.99 + sin(_anim.pulse_time * 1.10 + float(gem_uid.hash() % 17)) * 0.01
	var content_center := content_bounds.get_center()
	var smoke_center := pos + (content_center - Vector2(0.5, 0.5)) * icon_size
	var smoke_size := Vector2(icon_size, icon_size) * content_bounds.size
	# Leave enough room for two readable wisps at gameplay scale without turning them into a halo.
	smoke_size += Vector2.ONE * icon_size * 0.64
	smoke_size *= pulse
	draw_texture_rect(
		_gem_echo_smoke_texture,
		Rect2(smoke_center - smoke_size * 0.5, smoke_size),
		false,
		Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	)

func _gem_content_bounds(gem_id: String) -> Rect2:
	if _gem_texture_content_bounds.has(gem_id):
		return _gem_texture_content_bounds[gem_id]
	var fallback := Rect2(Vector2(0.18, 0.18), Vector2(0.64, 0.64))
	if _gem_sprites == null:
		return fallback
	var texture: Texture2D = _gem_sprites.texture_for_gem_id(gem_id)
	var image := texture.get_image() if texture != null else null
	if image == null:
		return fallback
	if image.is_compressed():
		image.decompress()
	var min_pos := Vector2i(image.get_width(), image.get_height())
	var max_pos := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.05:
				continue
			min_pos.x = mini(min_pos.x, x)
			min_pos.y = mini(min_pos.y, y)
			max_pos.x = maxi(max_pos.x, x)
			max_pos.y = maxi(max_pos.y, y)
	var bounds := fallback
	if max_pos.x >= min_pos.x and max_pos.y >= min_pos.y:
		var image_size := Vector2(image.get_width(), image.get_height())
		bounds = Rect2(Vector2(min_pos) / image_size, Vector2(max_pos - min_pos + Vector2i.ONE) / image_size)
	_gem_texture_content_bounds[gem_id] = bounds
	return bounds

func _facing_from_screen_delta(from_screen: Vector2, to_screen: Vector2, fallback: String) -> String:
	_ensure_facing_screen_refs()
	var screen_delta := to_screen - from_screen
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return fallback
	var dir := screen_delta.normalized()
	var best_name := fallback
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name

func _unit_draw_context(unit: UnitState) -> Dictionary:
	# 坑2：多格单位的视觉中心（及 Y-Sort 锚点）必须是 footprint 右下角格的屏幕坐标
	# 而非左上角锚点，否则站在大单位右下方的小单位会被错误遮挡
	var fp := unit.footprint_size
	var visual_anchor_grid := unit.pos + fp - Vector2i(1, 1) # footprint 右下角格
	var center := grid_to_screen(visual_anchor_grid)
	# 多格时水平中心取 footprint 宽度的屏幕跨度中点
	if fp != Vector2i(1, 1):
		var anchor_left := grid_to_screen(unit.pos)
		center.x = (anchor_left.x + center.x) * 0.5
	var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var facing := unit.facing
	var tint := UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	if _anim.hit_elapsed.has(unit.uid):
		var hit_progress := clampf(
			float(_anim.hit_elapsed[unit.uid]) / _HIT_DURATION,
			0.0,
			1.0
		)
		tint = tint.lerp(Color(1.0, 0.58, 0.58, 1.0), (1.0 - hit_progress) * 0.72)
	var pose: Dictionary = _resolve_unit_pose(unit, facing)
	var pose_tex: Texture2D = pose.get("texture", null)
	var sprite_size: Vector2 = pose.get("sprite_size", Vector2.ZERO)
	var layout := _unit_sprite_layout(unit, center, sprite_size)
	return {
		"center": center,
		"offset": offset,
		"tint": tint,
		"pose_tex": pose_tex,
		"sprite_size": sprite_size,
		"top_left": layout["top_left"],
		"ground_nudge": layout["ground_nudge"],
	}

func _draw_unit_body(unit: UnitState, ctx: Dictionary = {}) -> void:
	if ctx.is_empty(): ctx = _unit_draw_context(unit)
	var center: Vector2 = ctx["center"]
	var offset: Vector2 = ctx["offset"]
	var tint: Color = ctx["tint"]
	var pose_tex: Texture2D = ctx["pose_tex"]
	var sprite_size: Vector2 = ctx["sprite_size"]
	var top_left: Vector2 = ctx["top_left"]
	var ground_nudge: Vector2 = ctx["ground_nudge"]
	_draw_unit_shadow(unit, center, ground_nudge, sprite_size)

	var aura_alpha := float(_active_aura_alpha_by_uid.get(unit.uid, 0.0))
	if aura_alpha > 0.01 and not _uses_player_sprite(unit) and not _uses_slime_sprite(unit):
		var aura_center := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(2.0))
		_draw_active_turn_aura(unit, aura_center, aura_alpha)
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	var hover_alpha := float(_hover_outline_alpha_by_uid.get(unit.uid, 0.0))
	if pose_tex != null:
		if hover_alpha > 0.01:
			_draw_unit_texture_outline(pose_tex, Rect2(top_left, sprite_size), hover_alpha)
		_frozen_unit_visuals.draw_unit(self, unit, pose_tex, Rect2(top_left, sprite_size), tint)
	elif hover_alpha > 0.01:
		_draw_unit_focus_outline(unit, Color(UiPalette.TEXT_BRIGHT, 0.92), IsoCoordinates.visual(1.8), offset, 0.0, hover_alpha)

func _draw_unit_ui(unit: UnitState, ctx: Dictionary = {}) -> void:
	if ctx.is_empty(): ctx = _unit_draw_context(unit)
	var center: Vector2 = ctx["center"]
	var sprite_size: Vector2 = ctx["sprite_size"]
	var ground_nudge: Vector2 = ctx["ground_nudge"]
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	if name_alpha > 0.01:
		_draw_unit_nameplate(unit, Vector2(hp_bar_pos.x + IsoCoordinates.visual(18.0), hp_bar_pos.y - IsoCoordinates.visual(4.0)), name_alpha)
	_draw_unit_statuses(unit, hp_bar_pos + Vector2(0, IsoCoordinates.visual(8.0)))
	_draw_gem_icons(unit, hp_bar_pos)
	var shield_value := StatusRules.get_shield(unit)
	_draw_hp_bar(hp_bar_pos, unit, shield_value)
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		_draw_intent_badge(center + Vector2(0, -sprite_size.y + IsoCoordinates.visual(8.0)) + ground_nudge, unit.intent)

func _unit_sprite_size(unit: UnitState) -> Vector2:
	var sprite_size := IsoCoordinates.visual_vec(Vector2(62.0, 70.0))
	var fp := unit.footprint_size
	if fp != Vector2i(1, 1):
		sprite_size *= Vector2(float(fp.x), float(fp.y)).length() * 0.8
	return sprite_size

func _uses_player_sprite(unit: UnitState) -> bool:
	return unit.unit_def_id == "unit_player"

func _uses_slime_sprite(unit: UnitState) -> bool:
	return SLIME_SPRITES_SCRIPT.supports_unit(unit.unit_def_id)

func _uses_animated_idle(unit: UnitState) -> bool:
	return _uses_player_sprite(unit) or _uses_slime_sprite(unit)

func _unit_sprite_layout(unit: UnitState, center: Vector2, sprite_size: Vector2) -> Dictionary:
	var ground_y := _UNIT_SPRITE_GROUND_OFFSET_Y
	var foot_extra_y := 2.0
	if _uses_slime_sprite(unit):
		ground_y = _SLIME_SPRITE_GROUND_OFFSET_Y
		foot_extra_y = 0.0
	var ground_nudge := Vector2(0.0, IsoCoordinates.visual(ground_y))
	var foot := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(foot_extra_y))
	var top_left := Vector2(foot.x - sprite_size.x * 0.5, foot.y - sprite_size.y)
	return {"top_left": top_left, "ground_nudge": ground_nudge, "foot": foot}

func _strike_duration_for(unit_uid: String) -> float:
	if state == null:
		return _KNIGHT_STRIKE_DURATION
	var unit: UnitState = state.units.get(unit_uid, null)
	if unit != null and _uses_player_sprite(unit):
		return _PLAYER_STRIKE_DURATION
	if unit != null and _uses_slime_sprite(unit):
		return _SLIME_STRIKE_DURATION
	return _KNIGHT_STRIKE_DURATION

func _unit_shadow_texture(unit: UnitState) -> Texture2D:
	if _uses_slime_sprite(unit):
		return null
	if _uses_player_sprite(unit) and _player_sprites != null:
		return _player_sprites.texture_shadow()
	if _knight_sprites != null:
		return _knight_sprites.texture_shadow()
	return null

func _draw_unit_shadow(unit: UnitState, center: Vector2, ground_nudge: Vector2, sprite_size: Vector2) -> void:
	if _uses_slime_sprite(unit):
		if _player_sprites == null:
			return
		var sdw: Texture2D = _player_sprites.texture_shadow()
		if sdw == null:
			return
		var foot: Vector2 = center + ground_nudge
		var sh_sz := Vector2(sprite_size.x * 0.58, IsoCoordinates.visual(9.0))
		var sh_tl := Vector2(foot.x - sh_sz.x * 0.5, foot.y - sh_sz.y * 0.68)
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.32))
		return
	var sdw: Texture2D = _unit_shadow_texture(unit)
	if sdw == null:
		return
	if _uses_player_sprite(unit):
		var foot := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(2.0))
		var sh_sz := Vector2(sprite_size.x * 0.72, IsoCoordinates.visual(10.0))
		var sh_tl := Vector2(foot.x - sh_sz.x * 0.5, foot.y - sh_sz.y * 0.55)
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.34))
		return
	var sh_sz := Vector2(sprite_size.x * 0.82, sprite_size.y * 0.24)
	var sh_tl := center + Vector2(-sh_sz.x * 0.5, -IsoCoordinates.visual(2.0)) + ground_nudge
	draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.42))

func _resolve_unit_pose(unit: UnitState, facing: String) -> Dictionary:
	if _uses_player_sprite(unit):
		return _resolve_player_pose(unit.uid, facing)
	if _uses_slime_sprite(unit):
		return _resolve_slime_pose(unit, facing)
	return _resolve_knight_pose(unit, facing)

func _resolve_player_pose(unit_uid: String, facing: String) -> Dictionary:
	if _player_sprites == null:
		return {}
	var anim := "Idle"
	var idle_t: float = float(_anim.idle_phase.get(unit_uid, 0.0))
	var frame := int(idle_t * _PLAYER_IDLE_FPS) % _PLAYER_IDLE_FRAMES
	if _anim.hit_elapsed.has(unit_uid):
		anim = "Dash"
		frame = 6
	elif _anim.strike_elapsed.has(unit_uid):
		anim = "Dash"
		var st: float = float(_anim.strike_elapsed[unit_uid])
		frame = clampi(
			int(st / (_PLAYER_STRIKE_DURATION / float(_PLAYER_STRIKE_FRAMES))),
			0,
			_PLAYER_STRIKE_FRAMES - 1
		)
	elif _anim.move_offsets.has(unit_uid):
		anim = "Walk"
		var walk_t: float = float(_anim.walk_phase.get(unit_uid, 0.0))
		frame = int(walk_t * _PLAYER_WALK_FPS) % _PLAYER_WALK_FRAMES
	var pose: Dictionary = _player_sprites.pose_frame(facing, anim, frame)
	if pose.is_empty():
		return {}
	var draw_size: Vector2 = pose.get("draw_size", Vector2.ZERO)
	return {
		"texture": pose.get("texture", null),
		"sprite_size": IsoCoordinates.visual_vec(draw_size),
	}

func _resolve_slime_pose(unit: UnitState, facing: String) -> Dictionary:
	var variant := SLIME_SPRITES_SCRIPT.variant_for_unit(unit.unit_def_id)
	if not _slime_sprites_by_variant.has(variant):
		_slime_sprites_by_variant[variant] = SLIME_SPRITES_SCRIPT.new(variant)
	var slime_sprites: RefCounted = _slime_sprites_by_variant.get(variant, null)
	if slime_sprites == null:
		return {}
	var display_facing := facing
	if not _anim.strike_elapsed.has(unit.uid) and not _anim.move_offsets.has(unit.uid):
		display_facing = _slime_display_facing(unit, facing)
	var anim := "Idle"
	var idle_t: float = float(_anim.idle_phase.get(unit.uid, 0.0))
	var frame := int(idle_t * _SLIME_IDLE_FPS) % _SLIME_IDLE_FRAMES
	if _anim.hit_elapsed.has(unit.uid):
		anim = "Strike"
		frame = 4
	elif _anim.strike_elapsed.has(unit.uid):
		anim = "Strike"
		var st: float = float(_anim.strike_elapsed[unit.uid])
		frame = clampi(
			int(st / (_SLIME_STRIKE_DURATION / float(_SLIME_STRIKE_FRAMES))),
			0,
			_SLIME_STRIKE_FRAMES - 1
		)
	elif _anim.move_offsets.has(unit.uid):
		anim = "Walk"
		var walk_t: float = float(_anim.walk_phase.get(unit.uid, 0.0))
		frame = int(walk_t * _SLIME_WALK_FPS) % _SLIME_ANIM_FRAMES
	var pose: Dictionary = slime_sprites.pose_frame(display_facing, anim, frame)
	if pose.is_empty():
		return {}
	var base_size := IsoCoordinates.visual_vec(Vector2(62.0, 70.0))
	var sprite_size := _unit_sprite_size(unit)
	var scale := sprite_size / base_size
	var draw_size: Vector2 = pose.get("draw_size", Vector2.ZERO) * scale
	return {
		"texture": pose.get("texture", null),
		"sprite_size": draw_size,
	}

func _slime_display_facing(unit: UnitState, fallback: String) -> String:
	if state == null:
		return fallback
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return fallback
	return _facing_from_screen_delta(
		_get_unit_screen_center(unit),
		_get_unit_screen_center(player),
		fallback
	)

func _resolve_knight_pose(unit: UnitState, facing: String) -> Dictionary:
	var tex: Texture2D = null
	if _knight_sprites == null:
		return {}
	if _anim.hit_elapsed.has(unit.uid):
		tex = _knight_sprites.texture_hurt(facing)
	elif _anim.strike_elapsed.has(unit.uid):
		var st: float = float(_anim.strike_elapsed[unit.uid])
		var fidx := clampi(int(st / (0.28 / 3.0)), 0, 2)
		tex = _knight_sprites.texture_sword_swing(facing, fidx)
	elif _anim.move_offsets.has(unit.uid):
		var wfr := int(float(_anim.walk_phase.get(unit.uid, 0.0)) * _SLIME_WALK_FPS) % 3
		tex = _knight_sprites.texture_walk(facing, wfr)
	else:
		tex = _knight_sprites.texture_walk(facing, 0)
	return {"texture": tex, "sprite_size": _unit_sprite_size(unit)}

func _draw_cell_outline(canvas: Control, grid: Vector2i, color: Color, line_width: float) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	canvas.draw_polyline(closed, color, line_width, false)

func _hover_outline_color() -> Color:
	return Color(UiPalette.HILITE_REACH.lightened(0.4), 0.98)

func _cell_hover_outline_color() -> Color:
	for raw_overlay in overlay_specs:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		if str(overlay.get("kind", "")) not in ["move", "map_choice", "map_focus"]:
			continue
		if hover_cell in overlay.get("cells", []):
			return _hover_outline_color()
	return Color(UiPalette.TEXT_BRIGHT, 0.95)

func _draw_unit_ground_outlines() -> void:
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
		var selection_alpha := float(_selection_outline_alpha_by_uid.get(unit.uid, 0.0))
		if selection_alpha > 0.01:
			_draw_unit_focus_outline(unit, Color(UiPalette.TEXT_BRIGHT, 0.92), IsoCoordinates.visual(1.8), offset, 0.0, selection_alpha)

func _draw_unit_texture_outline(texture: Texture2D, rect: Rect2, alpha: float) -> void:
	if texture == null or alpha <= 0.01:
		return
	var px := maxf(1.0, IsoCoordinates.visual(2.0))
	var outline := Color(UiPalette.TEXT_BRIGHT, 0.82 * alpha)
	var offsets := [
		Vector2(-px, 0.0),
		Vector2(px, 0.0),
		Vector2(0.0, -px),
		Vector2(0.0, px),
		Vector2(-px, -px),
		Vector2(px, -px),
		Vector2(-px, px),
		Vector2(px, px),
	]
	for offset in offsets:
		draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false, outline)

func _draw_unit_focus_outline(
	unit: UnitState,
	color: Color,
	line_width: float,
	offset: Vector2 = Vector2.ZERO,
	fill_alpha: float = 0.1,
	alpha: float = 1.0
) -> void:
	if alpha <= 0.01:
		return
	var outline := color
	outline.a *= alpha
	for cell in unit.occupied_cells():
		var corners := IsoCoordinates.diamond_corners(grid_to_screen(cell) + offset)
		var fill := outline
		fill.a = fill_alpha * alpha
		draw_colored_polygon(corners, fill)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, outline, line_width, false)

func _draw_active_turn_aura(unit: UnitState, center: Vector2, alpha: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var pulse := sin(_anim.pulse_time * 4.2) * 0.5 + 0.5
	var base_color := BattleUiTheme.PHASE_PLAYER if unit.team == Constants.TEAM_PLAYER else BattleUiTheme.PHASE_ENEMY
	var size_scale := maxf(float(unit.footprint_size.x + unit.footprint_size.y) * 0.5, 1.0)
	var radius_x := IsoCoordinates.visual(20.0 + 8.0 * (size_scale - 1.0))
	var radius_y := IsoCoordinates.visual(8.0 + 4.0 * (size_scale - 1.0))
	var outer_scale := 1.05 + pulse * 0.16
	var fill_color := base_color
	fill_color.a = (0.12 + pulse * 0.12) * alpha
	var outer_color := base_color.lightened(0.18)
	outer_color.a = (0.52 + pulse * 0.28) * alpha
	var inner_color := base_color.lightened(0.08)
	inner_color.a = (0.35 + pulse * 0.18) * alpha
	_draw_ellipse(center, radius_x * outer_scale, radius_y * outer_scale, fill_color, outer_color, IsoCoordinates.visual(2.0))
	_draw_ellipse(center, radius_x * 0.82, radius_y * 0.82, Color.TRANSPARENT, inner_color, IsoCoordinates.visual(1.2))

func _draw_unit_nameplate(unit: UnitState, anchor: Vector2, alpha: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var font := BattleUiTheme.ui_font()
	var font_size := int(IsoCoordinates.visual(9.0))
	var text: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var backdrop_center := Vector2(anchor.x, anchor.y - text_size.y * 0.38)
	var radius_x := text_size.x * 0.5 + IsoCoordinates.visual(5.0)
	var radius_y := maxf(text_size.y * 0.56, IsoCoordinates.visual(5.0))
	_draw_soft_backdrop(backdrop_center, radius_x, radius_y, Color(0.0, 0.0, 0.0, 0.82 * alpha))
	var text_color := BattleUiTheme.TEXT
	text_color.a *= alpha
	var shadow_color := Color(0.0, 0.0, 0.0, 0.96 * alpha)
	_draw_text_with_shadow(
		font,
		Vector2(anchor.x - text_size.x * 0.5, anchor.y - 1.0),
		text,
		font_size,
		text_color,
		shadow_color
	)

func _draw_unit_statuses(unit: UnitState, origin: Vector2) -> void:
	var has_other := false
	for status in unit.statuses:
		if status.status_id != Constants.STATUS_ARMOR:
			has_other = true
			break
	if not has_other:
		return
	_draw_status_row(origin, unit, IsoCoordinates.visual(12.0), IsoCoordinates.visual(2.0), IsoCoordinates.visual(44.0))

func _draw_gem_icons(unit: UnitState, anchor: Vector2) -> void:
	if state == null or _gem_sprites == null:
		return
	var visible_slots: Array[SlotState] = []
	for slot in unit.slots:
		if slot == null:
			continue
		if not slot.gem_uid.is_empty() and _anim.masked_embedded_gems.has(slot.gem_uid):
			continue
		visible_slots.append(slot)
	if visible_slots.is_empty():
		return
	var icon_size := IsoCoordinates.visual(10.0)
	var spacing := IsoCoordinates.visual(11.0)
	var start_x := anchor.x - spacing * float(visible_slots.size() - 1) * 0.5
	var icon_y := anchor.y - IsoCoordinates.visual(13.0)
	for i in range(visible_slots.size()):
		var slot: SlotState = visible_slots[i]
		var cx := start_x + spacing * float(i)
		var pos := Vector2(cx, icon_y)
		if slot.gem_uid.is_empty():
			var slot_col := UnitLooks.slot_color(slot.slot_type)
			slot_col.a = 0.82
			var slot_fill := slot_col
			slot_fill.a = 0.18
			_draw_small_diamond(pos, icon_size * 0.34, icon_size * 0.26, slot_fill)
			var corners := PackedVector2Array([
				pos + Vector2(0, -icon_size * 0.34),
				pos + Vector2(icon_size * 0.34, 0),
				pos + Vector2(0, icon_size * 0.34),
				pos + Vector2(-icon_size * 0.34, 0),
				pos + Vector2(0, -icon_size * 0.34),
			])
			draw_polyline(corners, slot_col, IsoCoordinates.visual(1.1), false)
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tex: Texture2D = _gem_sprites.texture_for_gem_id(gem.gem_id)
		if tex != null:
			tex = _display_gem_texture(gem, tex)
			var tint: Color = _gem_sprites.modulate_for_gem_id(gem.gem_id)
			draw_texture_rect(
				tex,
				Rect2(Vector2(cx - icon_size * 0.5, icon_y - icon_size * 0.5), Vector2(icon_size, icon_size)),
				false,
				tint
			)
		else:
			_draw_small_diamond(
				pos,
				icon_size * 0.38,
				icon_size * 0.3,
				GemEchoVisuals.fallback_color(state, gem.uid, UnitLooks.gem_color(gem))
			)
		_draw_echo_smoke(gem.uid, pos, icon_size, 0.92)

func _draw_unit_slot_panels() -> void:
	if _slot_panel_renderer == null:
		return
	_slot_panel_renderer.draw(
		self,
		state,
		Callable(self, "_unit_panel_anchor"),
		Callable(self, "_draw_soft_backdrop"),
		Callable(self, "_draw_text_with_shadow"),
		Callable(self, "_draw_small_diamond"),
		Callable(self, "_display_gem_texture"),
		Callable(self, "_draw_echo_smoke"),
		Callable(UnitLooks, "get_gem_texture"),
		Callable(UnitLooks, "gem_sprite_modulate"),
		Callable(UnitLooks, "gem_color")
	)

func _unit_panel_anchor(unit: UnitState) -> Vector2:
	var center := _get_unit_screen_center(unit)
	var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var pose: Dictionary = _resolve_unit_pose(unit, unit.facing)
	var sprite_size: Vector2 = pose.get("sprite_size", Vector2.ZERO)
	if sprite_size == Vector2.ZERO:
		sprite_size = _unit_sprite_size(unit)
	var layout := _unit_sprite_layout(unit, center, sprite_size)
	var top_left: Vector2 = layout.get("top_left", center - Vector2(sprite_size.x * 0.5, sprite_size.y))
	return top_left + Vector2(sprite_size.x * 0.5, IsoCoordinates.visual(10.0))

func _draw_small_diamond(center: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height),
		center + Vector2(-width * 0.5, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.35), IsoCoordinates.visual(1.2), true)

func _draw_gem_visuals(front_layer: bool) -> void:
	for visual in _anim.inserting_gem_visuals:
		if _gem_visual_draws_in_front(visual) == front_layer:
			_draw_single_gem_visual(visual)
	if not _anim.held_gem_visual.is_empty() and _gem_visual_draws_in_front(_anim.held_gem_visual) == front_layer:
		_draw_single_gem_visual(_anim.held_gem_visual)
	if not _anim.hooked_gem_visual.is_empty() and _gem_visual_draws_in_front(_anim.hooked_gem_visual) == front_layer:
		_draw_single_gem_visual(_anim.hooked_gem_visual)

func _gem_visual_draws_in_front(visual: Dictionary) -> bool:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return true
	var pos: Vector2 = visual.get("current_pos", Vector2.ZERO)
	if pos.distance_to(anchor) > IsoCoordinates.visual(30.0):
		return true
	return pos.y >= anchor.y

func _draw_single_gem_visual(visual: Dictionary) -> void:
	var pos: Vector2 = visual.get("current_pos", Vector2.ZERO)
	var tint: Color = visual.get("tint", Color.WHITE)
	var phase := str(visual.get("phase", "orbit"))
	var progress := _gem_visual_progress(visual)
	var alpha := 1.0
	var scale := 1.0
	if phase == "extract":
		scale = lerpf(0.82, 1.0, progress)
	elif phase == "insert":
		alpha = 1.0 - progress * 0.35
		scale = lerpf(1.0, 0.74, progress)
	else:
		scale = 1.0 + sin(float(visual.get("bob_time", 0.0)) * 0.5) * 0.05
	var draw_tint := tint
	draw_tint.a *= alpha
	var glow := tint
	glow.a = 0.22 * alpha
	var shadow := Color(0.0, 0.0, 0.0, 0.16 * alpha)
	var draw_size := IsoCoordinates.visual(_GEM_DRAW_SIZE) * scale
	_draw_soft_backdrop(pos + Vector2(0.0, IsoCoordinates.visual(8.0)), draw_size * 0.28, draw_size * 0.14, shadow)
	_draw_soft_backdrop(pos, draw_size * 0.5, draw_size * 0.34, glow)
	var tex: Texture2D = visual.get("texture", null)
	if tex != null:
		draw_texture_rect(tex, Rect2(pos - Vector2.ONE * draw_size * 0.5, Vector2.ONE * draw_size), false, draw_tint)
	else:
		_draw_small_diamond(pos, draw_size * 0.48, draw_size * 0.32, draw_tint)

func _gem_visual_progress(visual: Dictionary) -> float:
	var duration := maxf(float(visual.get("duration", 1.0)), 0.001)
	return clampf(float(visual.get("elapsed", 0.0)) / duration, 0.0, 1.0)

func _draw_hp_bar(origin: Vector2, unit: UnitState, shield_value: int = 0) -> void:
	var icon_size := IsoCoordinates.visual(8.0) if shield_value > 0 else 0.0
	var gap := IsoCoordinates.visual(2.0) if shield_value > 0 else 0.0
	var width := IsoCoordinates.visual(36.0)
	var bar_h := IsoCoordinates.visual(5.0)
	var bar_x := origin.x + icon_size + gap
	if shield_value > 0:
		StatusIcons.draw_icon(self, origin, Constants.STATUS_ARMOR, icon_size)
	BattleUiTheme.draw_combined_hp_bar(
		self,
		Rect2(bar_x, origin.y, width, bar_h),
		unit.hp,
		unit.max_hp,
		shield_value
	)
	var font := BattleUiTheme.pixel_font()
	var font_size := int(IsoCoordinates.visual(7.0))
	var hp_text := "%d/%d" % [unit.hp, unit.max_hp]
	var text_size := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_draw_text_with_shadow(
		font,
		Vector2(bar_x + (width - text_size.x) * 0.5, origin.y + bar_h - IsoCoordinates.visual(0.5)),
		hp_text,
		font_size,
		UiPalette.TEXT_BRIGHT,
		UiPalette.TEXT_OUTLINE
	)

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

func _get_unit_screen_center(unit: UnitState) -> Vector2:
	return _footprint_screen_center_at(unit, unit.pos)

func _footprint_screen_center_at(unit: UnitState, anchor: Vector2i) -> Vector2:
	if unit == null:
		return grid_to_screen(anchor)
	var cells := BoardUtils.footprint_cells_at(unit.footprint_size, anchor)
	var total_screen := Vector2.ZERO
	for cell in cells:
		total_screen += grid_to_screen(cell)
	return total_screen / cells.size()

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

func _draw_status_row(origin: Vector2, unit: UnitState, icon_size: float = -1.0, gap: float = -1.0, max_width: float = -1.0) -> void:
	var ICON_SIZE := icon_size if icon_size > 0.0 else IsoCoordinates.visual(13.0)
	var GAP := gap if gap > 0.0 else IsoCoordinates.visual(2.0)
	var FONT_SIZE := int(IsoCoordinates.visual(7.0))
	var PAD_X := IsoCoordinates.visual(3.0)
	var PAD_Y := IsoCoordinates.visual(2.0)
	var WRAP_WIDTH := max_width if max_width > 0.0 else 999999.0
	var sorted: Array = StatusRegistry.sort_statuses(unit.statuses)
	var pixel_font := BattleUiTheme.pixel_font()
	var cursor := Vector2.ZERO
	var row_h := ICON_SIZE + GAP
	for status in sorted:
		if status.status_id == Constants.STATUS_ARMOR:
			continue
		var draw_pos := origin + cursor
		var item_w := ICON_SIZE
		var item_h := ICON_SIZE
		if not StatusIcons.has_icon(status.status_id):
			var label: String = StatusRegistry.short_label(status)
			var label_size := pixel_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			item_w = label_size.x + PAD_X * 2.0
			item_h = FONT_SIZE + PAD_Y * 2.0
		if cursor.x > 0.0 and cursor.x + item_w > WRAP_WIDTH:
			cursor.x = 0.0
			cursor.y += row_h
			draw_pos = origin + cursor
		if StatusIcons.draw_icon(self , draw_pos, status.status_id, ICON_SIZE):
			var badge_text: String = StatusRegistry.icon_badge(status)
			if not badge_text.is_empty():
				var badge_size := pixel_font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
				_draw_text_with_shadow(
					pixel_font,
					Vector2(draw_pos.x + ICON_SIZE - badge_size.x - IsoCoordinates.visual(0.5), draw_pos.y + ICON_SIZE - IsoCoordinates.visual(1.0)),
					badge_text,
					FONT_SIZE,
					UiPalette.TEXT_BRIGHT,
					UiPalette.TEXT_OUTLINE
				)
		else:
			var fallback_label: String = StatusRegistry.short_label(status)
			var text_w: float = pixel_font.get_string_size(fallback_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var chip_w := text_w + PAD_X * 2.0
			var chip_h := FONT_SIZE + PAD_Y * 2.0
			var color: Color = StatusRegistry.status_color(status.status_id)
			var bg := color.darkened(0.55)
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), bg)
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), color.lightened(0.1), false, 1.0)
			_draw_text_with_shadow(
				pixel_font,
				Vector2(draw_pos.x + PAD_X, draw_pos.y + PAD_Y + FONT_SIZE - 1.0),
				fallback_label,
				FONT_SIZE,
				UiPalette.TEXT_BRIGHT,
				UiPalette.TEXT_OUTLINE
			)
		cursor.x += item_w + GAP

func _draw_text_with_shadow(
	font: Font,
	position: Vector2,
	text: String,
	font_size: int,
	color: Color,
	shadow_color: Color
) -> void:
	for shadow_offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, position + IsoCoordinates.visual_vec(shadow_offset), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, fill_color: Color, outline_color: Color, line_width: float) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	if fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline_color, line_width, false)

func _draw_soft_backdrop(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var tex := _get_soft_gradient_texture()
	if tex == null:
		_draw_ellipse(center, radius_x, radius_y, color, Color.TRANSPARENT, 0.0)
		return
	var outer_tint := color
	outer_tint.a *= 0.42
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(radius_x * 1.28, radius_y * 1.18), Vector2(radius_x * 2.56, radius_y * 2.36)),
		false,
		outer_tint
	)
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(radius_x, radius_y), Vector2(radius_x * 2.0, radius_y * 2.0)),
		false,
		color
	)
	var core := color
	core.a = minf(1.0, color.a * 1.12)
	_draw_ellipse(center, radius_x * 0.62, radius_y * 0.58, core, Color.TRANSPARENT, 0.0)

func _get_soft_gradient_texture() -> Texture2D:
	if _soft_gradient_tex != null:
		return _soft_gradient_tex
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.68), Color.TRANSPARENT])
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	_soft_gradient_tex = texture
	return _soft_gradient_tex

func _draw_intent_badge(pos: Vector2, intent: IntentState) -> void:
	var center := Vector2(pos.x, pos.y)
	var icon_size_px := IsoCoordinates.visual(18.0)
	_draw_soft_backdrop(center, IsoCoordinates.visual(11.0), IsoCoordinates.visual(10.0), Color(0.0, 0.0, 0.0, 0.38))
	var draw_pos := center - Vector2(icon_size_px, icon_size_px) * 0.5
	if IntentIcons.draw_icon(self, draw_pos, intent.type, icon_size_px):
		return
	var icon: String = IntentState.intent_icon(intent.type)
	var font := BattleUiTheme.ui_font()
	var font_size := int(IsoCoordinates.visual(14.0))
	var text_size := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_draw_text_with_shadow(
		font,
		Vector2(center.x - text_size.x * 0.5, center.y + font_size * 0.35),
		icon,
		font_size,
		_intent_badge_color(intent.type).lightened(0.25),
		Color(0.0, 0.0, 0.0, 0.96)
	)

func _intent_badge_color(intent_type: String) -> Color:
	return Color(UiPalette.intent_color(intent_type), 0.95)

func pick_cell(screen_pos: Vector2) -> Vector2i:
	return IsoCoordinates.pick_grid_at(screen_pos, _board_origin, _board_size(), invert_origin)


# ═══════════════════════════════════════════════════════════════════════════
# 动画 API
# ═══════════════════════════════════════════════════════════════════════════

## 近战劈砍：Knight 三段挥剑sprite，与粒子伤害并行播放

