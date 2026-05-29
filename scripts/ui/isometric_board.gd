extends Control

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const BoardFxTexturesClass := preload("res://scripts/ui/board_fx_textures.gd")
const BoardUtilsClass := preload("res://scripts/rules/board_utils.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _Vpf := preload("res://scripts/ui/vfx_pack_frames.gd")
const StatusIcons := preload("res://scripts/ui/status_icons.gd")

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal animation_finished()

var highlights: Dictionary = {}
var hover_cell: Vector2i = Vector2i(-1, -1)
var selected_unit_uid: String = ""
var timeline_hover_unit_uid: String = ""
var active_turn_unit_uid: String = ""
var _nameplate_alpha_by_uid: Dictionary = {}
var _hover_outline_alpha_by_uid: Dictionary = {}
var _selection_outline_alpha_by_uid: Dictionary = {}
var _active_aura_alpha_by_uid: Dictionary = {}
var state: GameState = null:
	set(value):
		var prev_id := state.get_instance_id() if state != null else 0
		state = value
		var next_id := value.get_instance_id() if value != null else 0
		if next_id != prev_id:
			_walk_phase.clear()
			_strike_elapsed.clear()
			_facing_screen_refs.clear()
			_nameplate_alpha_by_uid.clear()
			_hover_outline_alpha_by_uid.clear()
			_selection_outline_alpha_by_uid.clear()
			_active_aura_alpha_by_uid.clear()
		if is_node_ready():
			_update_origin()
		queue_redraw()
## 为 true 时逻辑 (0,0) 显示在棋盘底部（等距原点对调，仅冒险地图）
var invert_origin: bool = false

var _board_origin: Vector2 = Vector2.ZERO
var _animation_speed_scale: float = 1.0

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim_queue: Array[Dictionary] = [] # 待播放动画队列
var _is_animating: bool = false

var _pulse_time: float = 0.0

# 移动动画：单位 uid → 当前屏幕偏移（相对于逻辑位置）
var _move_offsets: Dictionary = {} # uid → Vector2

# 特效粒子
var _particles: Array[Dictionary] = [] # {pos, color, life, max_life, velocity, type}

var _strike_elapsed: Dictionary = {}
var _walk_phase: Dictionary = {}

var _cached_puff_paths: PackedStringArray = PackedStringArray()

var _knight_sprites: RefCounted = null ## DoodleKnightSprites
var _fx_textures: RefCounted = null
var _soft_gradient_tex: Texture2D = null
# 抛射物动画：二次贝塞尔曲线飞行
var _projectile: Dictionary = {} # {from, to, ctrl, t, color} 空表示无飞行中抛射物

## Knight 底板锚点在格心；贴图腿长导致视觉上偏悬空，下移若干像素压住地面感
const _UNIT_SPRITE_GROUND_OFFSET_Y := 12.0
const _PUFF_FRAME_PATH := "res://assets/demo/doodle-rpg/ALL SPRITES/Particles/Puff_%d.png"
const _INVALID_GRID := Vector2i(-9999, -9999)
## 等距棋盘仅四斜向（由 grid_to_screen 校准）
const _FACING_GRID_STEPS: Dictionary = {
	"DR": Vector2i(1, 0),
	"DL": Vector2i(0, 1),
	"UL": Vector2i(-1, 0),
	"UR": Vector2i(0, -1),
}

var _facing_screen_refs: Dictionary = {}


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_origin)
	_update_origin()
	_knight_sprites = KNIGHT_SPRITES_SCRIPT.new()
	_fx_textures = BoardFxTexturesClass.new()
	set_process(true)
	call_deferred("_sync_unit_orientations")


func _update_origin() -> void:
	var board_sz := _board_size()
	IsoCoordinates.tile_scale = IsoCoordinates.compute_tile_scale(size, board_sz)
	_board_origin = IsoCoordinates.board_origin(size, board_sz)


func _process(delta: float) -> void:
	_pulse_time += delta
	var scaled_dt := delta * _animation_speed_scale
	var has_highlights: bool = not highlights.is_empty()
	var visuals_dirty := _update_overlay_fades(delta)
	if has_highlights or not active_turn_unit_uid.is_empty():
		visuals_dirty = true
	for mv_uid in _move_offsets.keys():
		if _strike_elapsed.has(mv_uid):
			continue
		_walk_phase[mv_uid] = _walk_phase.get(mv_uid, 0.0) + scaled_dt * 11.5
		visuals_dirty = true

	var strike_done: Array[String] = []
	for stk in _strike_elapsed.keys():
		var next_t: float = float(_strike_elapsed[stk]) + scaled_dt
		_strike_elapsed[stk] = next_t
		visuals_dirty = true
		if next_t >= 0.28:
			strike_done.append(str(stk))
	for stk_rem in strike_done:
		_strike_elapsed.erase(stk_rem)

	var needs_redraw: bool = false
	var i: int = _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		var p_kind: String = str(p.get("type", "spark"))
		p["life"] = p["life"] - delta
		if p["life"] <= 0.0:
			_particles.remove_at(i)
		else:
			if p_kind == "sprite_seq":
				p["frame_time"] = float(p.get("frame_time", 0.0)) + delta
				p["pos"] = p["pos"] + p["velocity"] * delta
				p["velocity"] = p["velocity"] + Vector2(0, 40.0) * delta
			else:
				p["pos"] = p["pos"] + p["velocity"] * delta
				p["velocity"] = p["velocity"] + Vector2(0, 120.0) * delta
		needs_redraw = true
		i -= 1
	if needs_redraw or visuals_dirty:
		queue_redraw()


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


func set_highlights(new_highlights: Dictionary) -> void:
	highlights = new_highlights
	queue_redraw()


func set_hover(cell: Vector2i) -> void:
	hover_cell = cell
	queue_redraw()


func set_timeline_hover_unit(uid: String) -> void:
	timeline_hover_unit_uid = uid
	queue_redraw()


func set_active_turn_unit(uid: String) -> void:
	active_turn_unit_uid = uid
	queue_redraw()


func grid_to_screen(grid: Vector2i) -> Vector2:
	return IsoCoordinates.grid_to_screen(grid, _board_origin, invert_origin, _board_size())


func _board_size() -> Vector2i:
	if state != null:
		return state.board_size
	return Constants.BOARD_SIZE


func _sorted_cells() -> Array[Vector2i]:
	return IsoCoordinates.sorted_cells(_board_size(), invert_origin)


func _draw() -> void:
	if state == null:
		return
	for grid in _sorted_cells():
		_draw_tile(grid)
	_draw_highlight_outlines()
	# 多格单位在 sorted_cells 中会被多次命中；用 Set 勿重复绘制
	var drawn_uids: Dictionary = {}
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and not drawn_uids.has(unit.uid):
			drawn_uids[unit.uid] = true
			_draw_unit(unit)
	if hover_cell.x >= 0:
		TileRenderer.draw_hover_outline(self , grid_to_screen(hover_cell))
	_draw_particles()
	_draw_projectile()


func _draw_highlight_outlines() -> void:
	var targets: Array = highlights.get("targets", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_pulse_time * 3.2) * 0.5 + 0.5)
	for grid in targets:
		var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
		var closed: PackedVector2Array = corners.duplicate()
		closed.append(corners[0])
		var c := Color(1.0, 0.92, 0.3, 0.55 + pulse * 0.35)
		draw_polyline(closed, c, IsoCoordinates.visual(1.8), false)
	for grid in danger:
		var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
		var closed: PackedVector2Array = corners.duplicate()
		closed.append(corners[0])
		var c := Color(1.0, 0.28, 0.28, 0.5 + pulse * 0.35)
		draw_polyline(closed, c, IsoCoordinates.visual(1.8), false)
	for grid in effect_list:
		var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
		var closed: PackedVector2Array = corners.duplicate()
		closed.append(corners[0])
		var c := Color(1.0, 0.52, 0.15, 0.45 + pulse * 0.3)
		draw_polyline(closed, c, IsoCoordinates.visual(1.5), false)


func _draw_tile(grid: Vector2i) -> void:
	var center := grid_to_screen(grid)
	var tile := state.get_tile(grid)
	var highlight := _tile_highlight(grid)
	TileRenderer.draw_tile(self , center, tile, highlight)


func _tile_highlight(grid: Vector2i) -> Color:
	var reachable: Array = highlights.get("reachable", [])
	var targets: Array = highlights.get("targets", [])
	var paths: Array = highlights.get("paths", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_pulse_time * 3.2) * 0.5 + 0.5)
	if grid in targets:
		var a: float = 0.52 + pulse * 0.22
		return Color(1.0, 0.9, 0.25, a)
	if grid in effect_list:
		var a: float = 0.48 + pulse * 0.2
		return Color(1.0, 0.48, 0.12, a)
	if grid in danger:
		var a: float = 0.42 + pulse * 0.22
		return Color(1.0, 0.2, 0.2, a)
	if grid in reachable:
		var a: float = 0.32 + pulse * 0.14
		return Color(0.3, 0.88, 1.0, a)
	if grid in paths:
		return Color(0.95, 0.65, 0.2, 0.24 + pulse * 0.1)
	return Color.TRANSPARENT


func _draw_unit(unit: UnitState) -> void:
	# 坑2：多格单位的视觉中心（及 Y-Sort 锚点）必须是 footprint 右下角格的屏幕坐标
	# 而非左上角锚点，否则站在大单位右下方的小单位会被错误遮挡
	var fp := unit.footprint_size
	var visual_anchor_grid := unit.pos + fp - Vector2i(1, 1)  # footprint 右下角格
	var center := grid_to_screen(visual_anchor_grid)
	# 多格时水平中心取 footprint 宽度的屏幕跨度中点
	if fp != Vector2i(1, 1):
		var anchor_left := grid_to_screen(unit.pos)
		center.x = (anchor_left.x + center.x) * 0.5
	var offset: Vector2 = _move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var sprite_size := IsoCoordinates.visual_vec(Vector2(62.0, 70.0))
	# 多格单位 sprite 按 footprint 宽度等比放大
	if fp != Vector2i(1, 1):
		sprite_size *= Vector2(float(fp.x), float(fp.y)).length() * 0.8
	var ground_nudge := Vector2(0.0, IsoCoordinates.visual(_UNIT_SPRITE_GROUND_OFFSET_Y))
	var top_left := center + Vector2(-sprite_size.x * 0.5, -sprite_size.y + IsoCoordinates.visual(2.0)) + ground_nudge
	var facing := unit.facing
	var tint := UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)

	var pose_tex: Texture2D = null
	if _strike_elapsed.has(unit.uid):
		var st: float = float(_strike_elapsed[unit.uid])
		var fidx := clampi(int(st / (0.28 / 3.0)), 0, 2)
		pose_tex = _knight_sprites.texture_sword_swing(facing, fidx)
	elif _move_offsets.has(unit.uid):
		var pf := float(_walk_phase.get(unit.uid, 0.0))
		var wfr := int(pf) % 3
		pose_tex = _knight_sprites.texture_walk(facing, wfr)
	else:
		pose_tex = _knight_sprites.texture_walk(facing, 0)

	var sdw: Texture2D = _knight_sprites.texture_shadow() if _knight_sprites != null else null
	if sdw != null:
		var sh_sz := Vector2(sprite_size.x * 0.82, sprite_size.y * 0.24)
		var sh_tl := center + Vector2(-sh_sz.x * 0.5, -IsoCoordinates.visual(2.0)) + ground_nudge
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.42))

	var aura_alpha := float(_active_aura_alpha_by_uid.get(unit.uid, 0.0))
	if aura_alpha > 0.01:
		_draw_active_turn_aura(unit, center + Vector2(0, IsoCoordinates.visual(2.0)), aura_alpha)
	if pose_tex != null:
		draw_texture_rect(pose_tex, Rect2(top_left, sprite_size), false, tint)
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	var hover_alpha := float(_hover_outline_alpha_by_uid.get(unit.uid, 0.0))
	var selection_alpha := float(_selection_outline_alpha_by_uid.get(unit.uid, 0.0))
	if hover_alpha > 0.01:
		_draw_unit_focus_outline(unit, Color(1.0, 0.82, 0.32, 0.95), IsoCoordinates.visual(2.2), offset, 0.15, hover_alpha)
	if selection_alpha > 0.01:
		_draw_unit_focus_outline(unit, Color(1.0, 1.0, 1.0, 0.92), IsoCoordinates.visual(1.8), offset, 0.08, selection_alpha)
	if name_alpha > 0.01:
		_draw_unit_nameplate(unit, Vector2(hp_bar_pos.x + IsoCoordinates.visual(18.0), hp_bar_pos.y - IsoCoordinates.visual(4.0)), name_alpha)
	_draw_unit_statuses(unit, hp_bar_pos + Vector2(0, IsoCoordinates.visual(8.0)))
	_draw_hp_bar(hp_bar_pos, unit)
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		_draw_intent_badge(center + Vector2(0, -sprite_size.y + IsoCoordinates.visual(8.0)) + ground_nudge, unit.intent)


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
	var pulse := sin(_pulse_time * 4.2) * 0.5 + 0.5
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
	var font := ThemeDB.fallback_font
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
	if unit.statuses.is_empty():
		return
	_draw_status_row(origin, unit, IsoCoordinates.visual(12.0), IsoCoordinates.visual(2.0), IsoCoordinates.visual(44.0))


func _draw_gem_diamonds(_unit: UnitState, _anchor: Vector2) -> void:
	return


func _draw_small_diamond(center: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height),
		center + Vector2(-width * 0.5, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.35), IsoCoordinates.visual(1.2), true)


func _draw_hp_bar(center: Vector2, unit: UnitState) -> void:
	var width := IsoCoordinates.visual(36.0)
	var bar_h := IsoCoordinates.visual(5.0)
	var ratio := clampf(float(unit.hp) / float(maxi(unit.max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(center, Vector2(width, bar_h)), Color(0.12, 0.12, 0.16, 0.85))
	var fill_color := Color(0.25, 0.85, 0.45) if unit.team == Constants.TEAM_PLAYER else Color(0.9, 0.35, 0.45)
	draw_rect(Rect2(center, Vector2(width * ratio, bar_h)), fill_color)
	var font := ThemeDB.fallback_font
	var font_size := int(IsoCoordinates.visual(7.0))
	var hp_text := "%d/%d" % [unit.hp, unit.max_hp]
	var text_size := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_draw_text_with_shadow(
		font,
		Vector2(center.x + (width - text_size.x) * 0.5, center.y + bar_h - IsoCoordinates.visual(0.5)),
		hp_text,
		font_size,
		Color(0.98, 0.98, 1.0),
		Color(0.04, 0.04, 0.08, 0.96)
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
	var cells := unit.occupied_cells()
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
	var cursor := Vector2.ZERO
	var row_h := ICON_SIZE + GAP
	for status in sorted:
		var draw_pos := origin + cursor
		var item_w := ICON_SIZE
		var item_h := ICON_SIZE
		if not StatusIcons.has_icon(status.status_id):
			var label: String = StatusRegistry.short_label(status)
			var label_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			item_w = label_size.x + PAD_X * 2.0
			item_h = FONT_SIZE + PAD_Y * 2.0
		if cursor.x > 0.0 and cursor.x + item_w > WRAP_WIDTH:
			cursor.x = 0.0
			cursor.y += row_h
			draw_pos = origin + cursor
		if StatusIcons.draw_icon(self, draw_pos, status.status_id, ICON_SIZE):
			var badge_text: String = StatusRegistry.icon_badge(status)
			if not badge_text.is_empty():
				var badge_size := ThemeDB.fallback_font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
				_draw_text_with_shadow(
					ThemeDB.fallback_font,
					Vector2(draw_pos.x + ICON_SIZE - badge_size.x - IsoCoordinates.visual(0.5), draw_pos.y + ICON_SIZE - IsoCoordinates.visual(1.0)),
					badge_text,
					FONT_SIZE,
					Color(0.98, 0.98, 1.0),
					Color(0.02, 0.02, 0.04, 0.96)
				)
		else:
			var font := ThemeDB.fallback_font
			var fallback_label: String = StatusRegistry.short_label(status)
			var text_w: float = font.get_string_size(fallback_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var chip_w := text_w + PAD_X * 2.0
			var chip_h := FONT_SIZE + PAD_Y * 2.0
			var color: Color = StatusRegistry.status_color(status.status_id)
			var bg := color.darkened(0.5)
			bg.a = 0.88
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), bg)
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), color.lightened(0.1), false, 1.0)
			_draw_text_with_shadow(
				font,
				Vector2(draw_pos.x + PAD_X, draw_pos.y + PAD_Y + FONT_SIZE - 1.0),
				fallback_label,
				FONT_SIZE,
				Color(0.95, 0.96, 0.98),
				Color(0.02, 0.02, 0.04, 0.96)
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
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var nx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var ny := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var dist := sqrt(nx * nx + ny * ny)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = pow(alpha, 0.48)
			var core := clampf(1.0 - dist * 1.8, 0.0, 1.0)
			alpha = maxf(alpha * 0.95, core * 0.48)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	_soft_gradient_tex = ImageTexture.create_from_image(image)
	return _soft_gradient_tex


func _draw_intent_badge(pos: Vector2, intent: IntentState) -> void:
	var icon: String = IntentState.intent_icon(intent.type)
	var font := ThemeDB.fallback_font
	var font_size := int(IsoCoordinates.visual(14.0))
	var icon_size := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := Vector2(pos.x, pos.y)
	_draw_soft_backdrop(center, maxf(icon_size.x * 0.6, IsoCoordinates.visual(9.0)), IsoCoordinates.visual(10.0), Color(0.0, 0.0, 0.0, 0.38))
	_draw_text_with_shadow(
		font,
		Vector2(center.x - icon_size.x * 0.5, center.y + font_size * 0.35),
		icon,
		font_size,
		_intent_badge_color(intent.type).lightened(0.25),
		Color(0.0, 0.0, 0.0, 0.96)
	)


func _intent_badge_color(intent_type: String) -> Color:
	match intent_type:
		"melee_attack": return Color(0.95, 0.35, 0.35, 0.95)
		"slam_attack": return Color(0.55, 0.85, 0.45, 0.95)
		"ranged_attack": return Color(0.75, 0.82, 0.55, 0.95)
		"charge_explode": return Color(1.0, 0.55, 0.1, 0.95)
		"pull": return Color(0.6, 0.35, 0.9, 0.95)
		"poison_attack": return Color(0.35, 0.85, 0.45, 0.95)
		"arc_attack": return Color(0.95, 0.9, 0.25, 0.95)
		"fire_attack": return Color(1.0, 0.45, 0.15, 0.95)
		"ice_attack": return Color(0.45, 0.85, 1.0, 0.95)
		"extract": return Color(0.95, 0.25, 0.75, 0.95)
		"move": return Color(0.45, 0.75, 0.95, 0.95)
		"lawless_extract", "lawless_attack", "lawless_move": return Color(0.9, 0.2, 0.2, 0.95)
		"black_suicide": return Color(0.35, 0.35, 0.42, 0.95)
		"bomb_rat_plunder_wait": return Color(0.7, 0.7, 0.75, 0.95)
		"bomb_rat_plunder_steal": return Color(0.95, 0.35, 0.35, 0.95)
	return Color(0.55, 0.58, 0.68, 0.85)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := IsoCoordinates.pick_grid_at(event.position, _board_origin, _board_size(), invert_origin)
		cell_hovered.emit(cell, cell.x >= 0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := IsoCoordinates.pick_grid_at(event.position, _board_origin, _board_size(), invert_origin)
		if cell.x >= 0:
			cell_clicked.emit(cell)


# ═══════════════════════════════════════════════════════════════════════════
# 动画 API
# ═══════════════════════════════════════════════════════════════════════════

## 近战劈砍：Knight 三段挥剑sprite，与粒子伤害并行播放
func start_strike_effect(attacker_uid: String, victim_cell: Vector2i) -> void:
	if state == null:
		return
	var attacker: UnitState = state.units.get(attacker_uid, null)
	if attacker == null:
		return
	attacker.facing = _facing_from_unit_to_cell(attacker, victim_cell)
	_strike_elapsed[attacker_uid] = 0.0
	queue_redraw()


## 播放移动动画：单位从 from_pos 滑动到 to_pos
func animate_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			mover.facing = _facing_from_unit_to_cell(mover, to_pos)
	_walk_phase[unit_uid] = 0.0
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
	_move_offsets[unit_uid] = from_offset
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_move_offset.bind(unit_uid), from_offset, to_offset, _scaled_duration(0.25))
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, to_offset))


func set_animation_speed_scale(speed_scale: float) -> void:
	_animation_speed_scale = maxf(speed_scale, 0.05)


func _scaled_duration(base_duration: float) -> float:
	return base_duration / _animation_speed_scale


func _set_move_offset(offset: Vector2, uid: String) -> void:
	_move_offsets[uid] = offset
	queue_redraw()


func _on_move_anim_done(uid: String, final_offset: Vector2) -> void:
	_walk_phase.erase(uid)
	if final_offset.length_squared() <= 0.001:
		_move_offsets.erase(uid)
	else:
		_move_offsets[uid] = final_offset
	queue_redraw()
	animation_finished.emit()


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _push_sprite_sequence(cfg: Dictionary) -> bool:
	var paths_val: Variant = cfg.get("paths", PackedStringArray())
	var packed_paths: PackedStringArray = PackedStringArray()
	if paths_val is PackedStringArray:
		packed_paths = paths_val as PackedStringArray
	elif paths_val is Array:
		var rows: Array = paths_val as Array
		for item in rows:
			packed_paths.append(str(item))
	else:
		return false
	if packed_paths.is_empty():
		return false
	var pos: Vector2 = cfg.get("pos", Vector2.ZERO)
	var fps_val: float = float(cfg.get("fps", 26.0))
	var draw_here: Variant = cfg.get("draw_size", Vector2(88.0, 88.0))
	var draw_sz: Vector2 = draw_here if draw_here is Vector2 else Vector2(88.0, 88.0)
	draw_sz = IsoCoordinates.visual_vec(draw_sz)
	var tint: Color = cfg.get("tint", Color.WHITE)
	var vel_here: Variant = cfg.get("velocity", Vector2.ZERO)
	var vel2: Vector2 = vel_here if vel_here is Vector2 else Vector2.ZERO
	vel2 = IsoCoordinates.visual_vec(vel2)
	var extra_life := float(cfg.get("life_pad", 0.05))
	var dur := float(packed_paths.size()) / maxf(fps_val, 0.01) + extra_life
	_particles.append({
		"type": "sprite_seq",
		"pos": pos,
		"life": dur,
		"max_life": dur,
		"velocity": vel2,
		"frame_time": 0.0,
		"fps": fps_val,
		"paths": packed_paths,
		"draw_size": draw_sz,
		"tint": tint,
	})
	return true


## 播放伤害/爆炸特效
func play_damage_effect(grid: Vector2i, damage: int, is_crit: bool) -> void:
	var hit_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_SMALL_HIT)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -16.0))
	var used_pack := false
	if _Vpf.is_pack_available() and not hit_paths.is_empty():
		var dim_big := IsoCoordinates.visual(72.0)
		var dim_small := IsoCoordinates.visual(56.0)
		var dim := dim_small
		if is_crit:
			dim = dim_big
		var dmg_tint := Color(0.88, 0.98, 1.0)
		if is_crit:
			dmg_tint = Color(1.0, 0.68, 0.68)
		used_pack = _push_sprite_sequence({
			"paths": hit_paths,
			"pos": center_scr,
			"fps": 38.0,
			"draw_size": Vector2(dim, dim),
			"tint": dmg_tint,
			"velocity": Vector2.ZERO,
			"life_pad": 0.03,
		})
	if not used_pack:
		_play_damage_procedural_fallback(grid, damage, is_crit)
	queue_redraw()


func _play_damage_procedural_fallback(grid: Vector2i, damage: int, is_crit: bool) -> void:
	var center: Vector2 = grid_to_screen(grid)
	var count: int = clampi(damage * 2, 4, 20)
	var base_color := Color(1.0, 0.65, 0.2)
	if is_crit:
		base_color = Color(1.0, 0.3, 0.15)
	
	# 加入一个居中的打击十字/星形特效（类型 hit_mark）
	_particles.append({
		"pos": center + IsoCoordinates.visual_vec(Vector2(0, -15)),
		"color": Color(1.0, 1.0, 1.0, 0.9) if not is_crit else Color(1.0, 0.4, 0.4, 1.0),
		"life": 0.25,
		"max_life": 0.25,
		"velocity": Vector2.ZERO,
		"type": "hit_mark",
		"scale": 1.5 if is_crit else 1.0
	})
	
	for _i in range(count):
		var angle: float = randf() * TAU
		var speed: float = randf_range(IsoCoordinates.visual(60.0), IsoCoordinates.visual(180.0))
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		var life: float = randf_range(0.3, 0.6)
		var color: Color = base_color.lerp(Color.WHITE, randf() * 0.4)
		_particles.append({
			"pos": center + Vector2(randf_range(-IsoCoordinates.visual(8.0), IsoCoordinates.visual(8.0)), randf_range(-IsoCoordinates.visual(20.0), -IsoCoordinates.visual(5.0))),
			"color": color,
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "spark"
		})


## 播放治疗特效
func play_heal_effect(grid: Vector2i) -> void:
	var heal_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_HEAL_CHARGE)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -20.0))
	var used_pack := false
	if _Vpf.is_pack_available() and not heal_paths.is_empty():
		used_pack = _push_sprite_sequence({
			"paths": heal_paths,
			"pos": center_scr,
			"fps": 32.0,
			"draw_size": Vector2(80.0, 80.0),
			"tint": Color(0.35, 1.0, 0.55),
			"velocity": Vector2.ZERO,
			"life_pad": 0.04,
		})
	if not used_pack:
		var center_legacy: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
		for _i in range(8):
			var vel: Vector2 = Vector2(randf_range(-IsoCoordinates.visual(20.0), IsoCoordinates.visual(20.0)), randf_range(-IsoCoordinates.visual(80.0), -IsoCoordinates.visual(40.0)))
			var life: float = randf_range(0.4, 0.8)
			_particles.append({
				"pos": center_legacy + Vector2(randf_range(-12, 12), randf_range(0, 10)),
				"color": Color(0.3, 1.0, 0.5, 0.9),
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "heal"
			})
	queue_redraw()


## 播放宝石拔出/嵌入闪光
func play_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	var sparkle_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_GEM_SPARK)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -30.0))
	var pulse_tint: Color = Color.WHITE.lerp(gem_color, 0.55)
	var used_pack := false
	if _Vpf.is_pack_available() and not sparkle_paths.is_empty():
		used_pack = _push_sprite_sequence({
			"paths": sparkle_paths,
			"pos": center_scr,
			"fps": 28.0,
			"draw_size": Vector2(64.0, 64.0),
			"tint": pulse_tint,
			"velocity": Vector2.ZERO,
			"life_pad": 0.03,
		})
	if not used_pack:
		var center_legacy: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0, -30))
		for _i in range(6):
			var angle: float = randf() * TAU
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(IsoCoordinates.visual(30.0), IsoCoordinates.visual(80.0))
			var life: float = randf_range(0.2, 0.5)
			_particles.append({
				"pos": center_legacy,
				"color": gem_color,
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "gem"
			})
	queue_redraw()


## 剧毒：优先 VFX 包 puff；缺失时用 Doodle Particles/Puff。
func play_poison_burst(anchor_grid: Vector2i, radius: int) -> void:
	if state == null:
		return
	var puff_vfx: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_PUFF)
	for cell in BoardUtilsClass.cells_in_radius(anchor_grid, radius):
		if not BoardUtilsClass.in_bounds(state, cell):
			continue
		var base: Vector2 = grid_to_screen(cell) + IsoCoordinates.visual_vec(Vector2(0, -10))
		var placed_pack := false
		if _Vpf.is_pack_available() and not puff_vfx.is_empty():
			placed_pack = _push_sprite_sequence({
				"paths": puff_vfx,
				"pos": base + Vector2(randf_range(-IsoCoordinates.visual(12.0), IsoCoordinates.visual(12.0)), randf_range(-IsoCoordinates.visual(14.0), IsoCoordinates.visual(6.0))),
				"fps": 42.0,
				"draw_size": Vector2(72.0, 72.0),
				"tint": Color(0.38, 0.95, 0.52),
				"velocity": Vector2(randf_range(-IsoCoordinates.visual(10.0), IsoCoordinates.visual(10.0)), randf_range(-IsoCoordinates.visual(22.0), -IsoCoordinates.visual(6.0))),
				"life_pad": 0.03,
			})
		if not placed_pack:
			var puff_legacy: PackedStringArray = _puff_sprite_paths()
			for _j in range(2):
				var life_here: float = randf_range(0.48, 0.62)
				_particles.append({
					"type": "sprite_seq",
					"pos": base + Vector2(randf_range(-IsoCoordinates.visual(14.0), IsoCoordinates.visual(14.0)), randf_range(-IsoCoordinates.visual(18.0), IsoCoordinates.visual(8.0))),
					"life": life_here,
					"max_life": life_here,
					"velocity": Vector2(randf_range(-IsoCoordinates.visual(18.0), IsoCoordinates.visual(18.0)), randf_range(-IsoCoordinates.visual(32.0), -IsoCoordinates.visual(12.0))),
					"frame_time": 0.0,
					"fps": randf_range(16.0, 22.0),
					"paths": puff_legacy,
					"draw_size": Vector2(44, 44),
					"tint": Color(0.42, 0.92, 0.38, 1.0),
				})
	queue_redraw()


## 爆炸（宝石/敌人）：优先 VFX 包；缺失时沿用程序粒子。
func play_explosion(grid: Vector2i) -> void:
	var exp_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_EXPLOSION)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -24.0))
	var ok := false
	if _Vpf.is_pack_available() and not exp_paths.is_empty():
		ok = _push_sprite_sequence({
			"paths": exp_paths,
			"pos": center_scr,
			"fps": 48.0,
			"draw_size": Vector2(164.0, 164.0),
			"tint": Color(1.0, 1.0, 0.98),
			"velocity": Vector2.ZERO,
			"life_pad": 0.1,
		})
	if not ok:
		var center_legacy: Vector2 = grid_to_screen(grid) + Vector2(0, -20)
		for _i in range(30):
			var angle: float = randf() * TAU
			var speed: float = randf_range(100.0, 280.0)
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
			var life: float = randf_range(0.4, 0.9)
			var color: Color = Color(1.0, randf_range(0.2, 0.6), 0.05).lerp(Color.WHITE, randf() * 0.3)
			_particles.append({
				"pos": center_legacy + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				"color": color,
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "spark"
			})
		for _k in range(12):
			var angle2: float = randf() * TAU
			var speed2: float = randf_range(20.0, 60.0)
			var vel2: Vector2 = Vector2(cos(angle2), sin(angle2)) * speed2 + Vector2(0, -30)
			var life2: float = randf_range(0.6, 1.2)
			_particles.append({
				"pos": center_legacy + Vector2(randf_range(-10, 10), randf_range(-5, 5)),
				"color": Color(0.3, 0.3, 0.35, 0.7),
				"life": life2,
				"max_life": life2,
				"velocity": vel2,
				"type": "smoke"
			})
		_particles.append({
			"pos": center_legacy,
			"color": Color(1.0, 0.6, 0.1, 0.8),
			"life": 0.4,
			"max_life": 0.4,
			"velocity": Vector2.ZERO,
			"type": "ring"
		})
	queue_redraw()


## 绘制所有粒子
func _draw_particles() -> void:
	for p in _particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var color: Color = p.get("color", Color.WHITE)
		color.a *= alpha
		var pos: Vector2 = p["pos"]
		match p["type"]:
			"spark":
				var sz: float = 3.0 * alpha + 1.0
				draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), color)
			"heal":
				var sz: float = 4.0 * alpha
				draw_circle(pos, sz, color)
			"gem":
				_draw_small_diamond(pos, 6.0 * alpha + 2.0, 4.0 * alpha + 1.0, color)
			"smoke":
				var sz: float = 8.0 * (1.0 - alpha * 0.5)
				draw_circle(pos, sz, color)
			"ring":
				var progress: float = 1.0 - alpha
				var radius_px: float = 20.0 + progress * 60.0
				var ring_color: Color = color
				ring_color.a = alpha * 0.7
				draw_arc(pos, radius_px, 0, TAU, 24, ring_color, 2.5 * alpha + 0.5)
			"hit_mark":
				var scale := float(p.get("scale", 1.0))
				var expand := (1.0 - alpha) * 10.0 * scale
				var len := (20.0 + expand) * scale
				var thick := (3.0 * alpha + 1.0) * scale
				draw_line(pos + Vector2(-len, -len), pos + Vector2(len, len), color, thick)
				draw_line(pos + Vector2(-len, len), pos + Vector2(len, -len), color, thick)
				draw_line(pos + Vector2(-len * 1.2, 0), pos + Vector2(len * 1.2, 0), color, thick * 0.6)
				draw_line(pos + Vector2(0, -len * 1.2), pos + Vector2(0, len * 1.2), color, thick * 0.6)
			"sprite_seq":
				if _fx_textures == null:
					continue
				var paths: Variant = p.get("paths", null)
				if paths == null or paths.is_empty():
					continue
				var ft: float = float(p.get("frame_time", 0.0))
				var fps_val: float = float(p.get("fps", 14.0))
				var fidx: int = clampi(int(ft * fps_val), 0, int(paths.size()) - 1)
				var path_s: String = str(paths[fidx])
				var tex: Texture2D = _fx_textures.texture_at(path_s)
				if tex == null:
					continue
				var dsz: Variant = p.get("draw_size", Vector2(40, 40))
				var hs: Vector2 = dsz * 0.5
				var tnt: Color = p.get("tint", Color.WHITE)
				tnt.a *= alpha
				draw_texture_rect(tex, Rect2(pos - hs, dsz), false, tnt)


func _puff_sprite_paths() -> PackedStringArray:
	if not _cached_puff_paths.is_empty():
		return _cached_puff_paths
	for fi in range(7):
		_cached_puff_paths.append(_PUFF_FRAME_PATH % fi)
	return _cached_puff_paths


# ═══════════════════════════════════════════════════════════════════════════
# 抛射物动画
# ═══════════════════════════════════════════════════════════════════════════

## 播放玩家投射物：从 from_grid 飞向 to_grid，走贝塞尔弧线
## 落地后 emit animation_finished
func play_projectile(from_grid: Vector2i, to_grid: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	var from_scr: Vector2 = grid_to_screen(from_grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
	var to_scr: Vector2 = grid_to_screen(to_grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
	var mid: Vector2 = (from_scr + to_scr) * 0.5
	var dist: float = from_scr.distance_to(to_scr)
	var ctrl: Vector2 = mid + Vector2(0, -clampf(dist * 0.45, IsoCoordinates.visual(28.0), IsoCoordinates.visual(90.0)))
	_projectile = {
		"from": from_scr,
		"to": to_scr,
		"ctrl": ctrl,
		"t": 0.0,
		"color": proj_color,
	}
	var duration: float = _scaled_duration(clampf(dist / IsoCoordinates.visual(520.0), 0.18, 0.38))
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_projectile_t, 0.0, 1.0, duration)
	tween.tween_callback(_on_projectile_done)


func _set_projectile_t(t: float) -> void:
	if _projectile.is_empty():
		return
	_projectile["t"] = t
	queue_redraw()


func _on_projectile_done() -> void:
	_projectile = {}
	queue_redraw()
	animation_finished.emit()


func _draw_projectile() -> void:
	if _projectile.is_empty():
		return
	var t: float = float(_projectile["t"])
	var from: Vector2 = _projectile["from"]
	var to: Vector2 = _projectile["to"]
	var ctrl: Vector2 = _projectile["ctrl"]
	var color: Color = _projectile["color"]

	# 二次贝塞尔插值当前位置
	var inv := 1.0 - t
	var pos: Vector2 = inv * inv * from + 2.0 * inv * t * ctrl + t * t * to

	# 朝向（飞行方向的切线）决定绘制角度
	var tangent: Vector2 = (2.0 * (1.0 - t) * (ctrl - from) + 2.0 * t * (to - ctrl)).normalized()

	# 拖尾：沿切线反方向画几段渐隐线段
	const TRAIL_STEPS := 5
	for i in range(TRAIL_STEPS):
		var s: float = float(i + 1) / float(TRAIL_STEPS)
		var alpha: float = (1.0 - s) * 0.55
		var trail_t: float = clampf(t - s * 0.06, 0.0, 1.0)
		var tinv := 1.0 - trail_t
		var trail_pos: Vector2 = tinv * tinv * from + 2.0 * tinv * trail_t * ctrl + trail_t * trail_t * to
		var trail_color: Color = color
		trail_color.a = alpha
		draw_line(pos, trail_pos, trail_color, maxf(IsoCoordinates.visual(3.0) - s * IsoCoordinates.visual(1.5), IsoCoordinates.visual(0.5)))

	var perp: Vector2 = Vector2(-tangent.y, tangent.x)
	var tip: Vector2 = pos + tangent * IsoCoordinates.visual(7.0)
	var tail_pt: Vector2 = pos - tangent * IsoCoordinates.visual(5.0)
	var left_pt: Vector2 = pos + perp * IsoCoordinates.visual(3.5)
	var right_pt: Vector2 = pos - perp * IsoCoordinates.visual(3.5)
	var pts := PackedVector2Array([tip, left_pt, tail_pt, right_pt])
	draw_colored_polygon(pts, color)
	var outline_color: Color = color.darkened(0.3)
	outline_color.a = 0.85
	draw_polyline(PackedVector2Array([tip, left_pt, tail_pt, right_pt, tip]), outline_color, IsoCoordinates.visual(1.0))
