extends Control

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const PLAYER_SPRITES_SCRIPT := preload("res://scripts/ui/female_adventurer_sprites.gd")
const SLIME_SPRITES_SCRIPT := preload("res://scripts/ui/slime_sprites.gd")
const GEM_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_gem_sprites.gd")
const PROP_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_prop_sprites.gd")
const BoardFxTexturesClass := preload("res://scripts/ui/board_fx_textures.gd")
const BoardUtilsClass := preload("res://scripts/rules/board_utils.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _Vpf := preload("res://scripts/ui/vfx_pack_frames.gd")
const StatusIcons := preload("res://scripts/ui/status_icons.gd")

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal animation_finished()

class BoardAnimationHostState:
	var pulse_time: float = 0.0
	var move_offsets: Dictionary = {}
	var particles: Array[Dictionary] = []
	var strike_elapsed: Dictionary = {}
	var walk_phase: Dictionary = {}
	var idle_phase: Dictionary = {}
	var active_projectiles: Array = []
	var parallel_move_remaining: int = 0
	var held_gem_visual: Dictionary = {}
	var inserting_gem_visuals: Array[Dictionary] = []
	var masked_embedded_gems: Dictionary = {}
	var cached_puff_paths: PackedStringArray = PackedStringArray()

	func clear_state_runtime() -> void:
		move_offsets.clear()
		walk_phase.clear()
		idle_phase.clear()
		strike_elapsed.clear()

	func clear_gem_visuals() -> void:
		held_gem_visual.clear()
		inserting_gem_visuals.clear()
		masked_embedded_gems.clear()


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
			_anim.clear_state_runtime()
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

## 棋盘地砖贴图（替代程序化绘制的菱形格子），按网格几何自动对齐
var _board_texture: Sprite2D = null
## 贴图去掉白边后的实际内容区域（缓存，仅扫描一次）
var _board_texture_region: Rect2 = Rect2()

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim := BoardAnimationHostState.new()
## 移动 tween 插值元数据，用于把行走帧与位移进度对齐

var _knight_sprites: RefCounted = null ## DoodleKnightSprites
var _player_sprites: RefCounted = null ## FemaleAdventurerSprites
var _slime_sprites: RefCounted = null ## SlimeSprites
var _gem_sprites: RefCounted = null ## DoodleGemSprites
var _prop_sprites: RefCounted = null ## DoodlePropSprites
var _fx_textures: RefCounted = null
var _soft_gradient_tex: Texture2D = null
# 抛射物动画：二次贝塞尔曲线飞行（支持齐射）

## Knight 底板锚点在格心；贴图腿长导致视觉上偏悬空，下移若干像素压住地面感
const _UNIT_SPRITE_GROUND_OFFSET_Y := 12.0
const _SLIME_SPRITE_GROUND_OFFSET_Y := -2.0
const _PLAYER_WALK_FRAMES := 8
const _PLAYER_IDLE_FRAMES := 8
const _PLAYER_IDLE_FPS := 10.0
const _PLAYER_WALK_FPS := 12.0
const _PLAYER_STRIKE_FRAMES := 8
const _PLAYER_STRIKE_DURATION := 0.52
const _KNIGHT_STRIKE_DURATION := 0.28
const _SLIME_IDLE_FPS := 2.0
const _SLIME_IDLE_FRAMES := 2
const _SLIME_WALK_FPS := 10.0
const _SLIME_ANIM_FRAMES := 6
const _SLIME_STRIKE_FRAMES := 6
const _SLIME_STRIKE_DURATION := 0.36
const _PUFF_FRAME_PATH := "res://assets/demo/doodle-rpg/ALL SPRITES/Particles/Puff_%d.png"
const _INVALID_GRID := Vector2i(-9999, -9999)
const _GEM_LIFT_DURATION := 0.48
const _GEM_INSERT_DURATION := 0.38
const _GEM_ORBIT_SPEED := 1.9
const _GEM_ORBIT_RADIUS_X := 20.0
const _GEM_ORBIT_RADIUS_Y := 7.5
const _GEM_BOB_SPEED := 1.7
const _GEM_BOB_AMPLITUDE := 1.0
const _GEM_DRAW_SIZE := 18.0
const _GEM_SLOT_SOURCE_OFFSET := Vector2(0.0, -28.0)
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
	_board_texture = get_node_or_null("Grids")
	resized.connect(_update_origin)
	_update_origin()
	_knight_sprites = KNIGHT_SPRITES_SCRIPT.new()
	_player_sprites = PLAYER_SPRITES_SCRIPT.new()
	_slime_sprites = SLIME_SPRITES_SCRIPT.new("green")
	_gem_sprites = GEM_SPRITES_SCRIPT.new()
	_prop_sprites = PROP_SPRITES_SCRIPT.new()
	_fx_textures = BoardFxTexturesClass.new()
	set_process(true)
	call_deferred("_sync_unit_orientations")


func _update_origin() -> void:
	var board_sz := _board_size()
	IsoCoordinates.tile_scale = IsoCoordinates.compute_tile_scale(size, board_sz)
	_board_origin = IsoCoordinates.board_origin(size, board_sz)
	_update_board_texture_transform()


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


## 扫描贴图，按 shader 同阈值（接近纯白即背景）求出内容包围盒，用于裁掉白边
func _board_texture_content_rect() -> Rect2:
	if _board_texture_region.size.x > 0.0:
		return _board_texture_region
	var tex := _board_texture.texture
	var full := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img == null:
		_board_texture_region = full
		return full
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var step := 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.04 or (c.r > 0.95 and c.g > 0.95 and c.b > 0.95):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		_board_texture_region = full
	else:
		_board_texture_region = Rect2(min_x, min_y, max_x - min_x + step, max_y - min_y + step)
	return _board_texture_region


func _process(delta: float) -> void:
	_anim.pulse_time += delta
	var scaled_dt := delta * _animation_speed_scale
	var has_highlights: bool = not highlights.is_empty()
	var visuals_dirty := _update_overlay_fades(delta)
	if has_highlights or not active_turn_unit_uid.is_empty():
		visuals_dirty = true
	for mv_uid in _anim.move_offsets.keys():
		if _anim.strike_elapsed.has(mv_uid):
			continue
		_anim.walk_phase[mv_uid] = _anim.walk_phase.get(mv_uid, 0.0) + scaled_dt
		visuals_dirty = true
	if state != null:
		for unit: UnitState in state.units.values():
			if not unit.alive or not _uses_animated_idle(unit):
				continue
			if _anim.strike_elapsed.has(unit.uid) or _anim.move_offsets.has(unit.uid):
				continue
			_anim.idle_phase[unit.uid] = _anim.idle_phase.get(unit.uid, 0.0) + scaled_dt
			visuals_dirty = true

	var strike_done: Array[String] = []
	for stk in _anim.strike_elapsed.keys():
		var next_t: float = float(_anim.strike_elapsed[stk]) + scaled_dt
		_anim.strike_elapsed[stk] = next_t
		visuals_dirty = true
		if next_t >= _strike_duration_for(stk):
			strike_done.append(str(stk))
	for stk_rem in strike_done:
		_anim.strike_elapsed.erase(stk_rem)

	var needs_redraw: bool = false
	var i: int = _anim.particles.size() - 1
	while i >= 0:
		var p: Dictionary = _anim.particles[i]
		var p_kind: String = str(p.get("type", "spark"))
		p["life"] = p["life"] - delta
		if p["life"] <= 0.0:
			_anim.particles.remove_at(i)
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
	var gem_dirty := _update_gem_visuals(scaled_dt)
	if needs_redraw or visuals_dirty or gem_dirty:
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
	queue_redraw()


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
	var drawn_units: Dictionary = {}
	var drawn_entities: Dictionary = {}
	for grid in _sorted_cells():
		_draw_tile(grid)
	_draw_move_highlight_outlines()
	for grid in _sorted_cells():
		_draw_entity_at_grid(grid, drawn_entities)
		if hover_cell == grid:
			var hover_unit := state.get_unit_at(hover_cell)
			if hover_unit == null or not hover_unit.alive:
				TileRenderer.draw_hover_outline(self, grid_to_screen(hover_cell), _cell_hover_outline_color())
	_draw_unit_ground_outlines()
	_draw_gem_visuals(false)
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive and not drawn_units.has(unit.uid):
			drawn_units[unit.uid] = true
			_draw_unit(unit)
	_draw_highlight_outlines()
	_draw_anim_particles()
	_draw_projectile()
	_draw_gem_visuals(true)


func _draw_entity_at_grid(grid: Vector2i, drawn_entities: Dictionary) -> void:
	var entity := state.get_entity_at(grid)
	if entity == null or not entity.alive or drawn_entities.has(entity.uid):
		return
	drawn_entities[entity.uid] = true
	var center := grid_to_screen(entity.pos)
	match entity.entity_id:
		Constants.ENTITY_SPIKE:
			TileRenderer.draw_spikes(self, center)
		Constants.ENTITY_PROP, Constants.ENTITY_ROCK:
			_draw_prop_entity(entity, center)
		_:
			pass


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


func _draw_move_highlight_outlines() -> void:
	var reachable: Array = highlights.get("reachable", [])
	if reachable.is_empty():
		return
	var outline: Color = _reachable_outline_color()
	var hover_outline: Color = _hover_outline_color()
	for grid in reachable:
		var cell: Vector2i = grid
		var is_hovered: bool = (cell == hover_cell)
		var color: Color = hover_outline if is_hovered else outline
		var width: float = IsoCoordinates.visual(2.0 if is_hovered else 1.5)
		_draw_cell_outline(cell, color, width)


func _draw_highlight_outlines() -> void:
	var attack_range: Array = highlights.get("attack_range", [])
	var targets: Array = highlights.get("targets", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	for grid in attack_range:
		var c := Color(0.45, 0.92, 0.55, 0.45 + pulse * 0.25)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.6))
	for grid in targets:
		var c := Color(1.0, 0.92, 0.3, 0.55 + pulse * 0.35)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.8))
	for grid in danger:
		var c := Color(1.0, 0.28, 0.28, 0.5 + pulse * 0.35)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.8))
	for grid in effect_list:
		var c := Color(1.0, 0.52, 0.15, 0.45 + pulse * 0.3)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.5))


func _draw_tile(grid: Vector2i) -> void:
	var center := grid_to_screen(grid)
	var tile := state.get_tile(grid)
	var highlight := _tile_highlight(grid)
	# 地砖底由 Grids 贴图统一绘制，这里只叠加高亮与特殊地块（水/柱/毒/火等）
	TileRenderer.draw_tile_overlays(self , center, tile, highlight)


func _tile_highlight(grid: Vector2i) -> Color:
	var attack_range: Array = highlights.get("attack_range", [])
	var targets: Array = highlights.get("targets", [])
	var paths: Array = highlights.get("paths", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	if grid in effect_list:
		var a: float = 0.5 + pulse * 0.22
		return Color(1.0, 0.22, 0.22, a)
	if grid in attack_range:
		var a: float = 0.28 + pulse * 0.12
		return Color(0.42, 0.9, 0.5, a)
	if grid in targets:
		var a: float = 0.52 + pulse * 0.22
		return Color(1.0, 0.9, 0.25, a)
	if grid in danger:
		var a: float = 0.42 + pulse * 0.22
		return Color(1.0, 0.2, 0.2, a)
	if grid in paths:
		return Color(0.95, 0.65, 0.2, 0.24 + pulse * 0.1)
	return Color.TRANSPARENT


func _draw_unit(unit: UnitState) -> void:
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
	var pose: Dictionary = _resolve_unit_pose(unit, facing)
	var pose_tex: Texture2D = pose.get("texture", null)
	var sprite_size: Vector2 = pose.get("sprite_size", Vector2.ZERO)
	var layout := _unit_sprite_layout(unit, center, sprite_size)
	var top_left: Vector2 = layout["top_left"]
	var ground_nudge: Vector2 = layout["ground_nudge"]
	_draw_unit_shadow(unit, center, ground_nudge, sprite_size)

	var aura_alpha := float(_active_aura_alpha_by_uid.get(unit.uid, 0.0))
	if aura_alpha > 0.01 and not _uses_player_sprite(unit) and not _uses_slime_sprite(unit):
		var aura_center := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(2.0))
		_draw_active_turn_aura(unit, aura_center, aura_alpha)
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	if pose_tex != null:
		draw_texture_rect(pose_tex, Rect2(top_left, sprite_size), false, tint)
	if name_alpha > 0.01:
		_draw_unit_nameplate(unit, Vector2(hp_bar_pos.x + IsoCoordinates.visual(18.0), hp_bar_pos.y - IsoCoordinates.visual(4.0)), name_alpha)
	_draw_unit_statuses(unit, hp_bar_pos + Vector2(0, IsoCoordinates.visual(8.0)))
	_draw_gem_icons(unit, hp_bar_pos)
	var shield_value := StatusRules.get_shield(unit)
	if shield_value > 0:
		var shield_gap := IsoCoordinates.visual(2.0)
		var shield_h := IsoCoordinates.visual(5.0)
		_draw_shield_bar(hp_bar_pos - Vector2(0, shield_h + shield_gap), unit, shield_value)
	_draw_hp_bar(hp_bar_pos, unit)
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
	return unit.unit_def_id == "unit_fission_slime"


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
	if _anim.strike_elapsed.has(unit_uid):
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
	if _slime_sprites == null:
		return {}
	var display_facing := facing
	if not _anim.strike_elapsed.has(unit.uid) and not _anim.move_offsets.has(unit.uid):
		display_facing = _slime_display_facing(unit, facing)
	var anim := "Idle"
	var idle_t: float = float(_anim.idle_phase.get(unit.uid, 0.0))
	var frame := int(idle_t * _SLIME_IDLE_FPS) % _SLIME_IDLE_FRAMES
	if _anim.strike_elapsed.has(unit.uid):
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
	var pose: Dictionary = _slime_sprites.pose_frame(display_facing, anim, frame)
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
	if _anim.strike_elapsed.has(unit.uid):
		var st: float = float(_anim.strike_elapsed[unit.uid])
		var fidx := clampi(int(st / (0.28 / 3.0)), 0, 2)
		tex = _knight_sprites.texture_sword_swing(facing, fidx)
	elif _anim.move_offsets.has(unit.uid):
		var wfr := int(float(_anim.walk_phase.get(unit.uid, 0.0)) * _SLIME_WALK_FPS) % 3
		tex = _knight_sprites.texture_walk(facing, wfr)
	else:
		tex = _knight_sprites.texture_walk(facing, 0)
	return {"texture": tex, "sprite_size": _unit_sprite_size(unit)}


func _draw_cell_outline(grid: Vector2i, color: Color, line_width: float) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	draw_polyline(closed, color, line_width, false)


func _reachable_outline_color() -> Color:
	return Color(1.0, 1.0, 1.0, 0.92)


func _hover_outline_color() -> Color:
	return Color(0.76, 0.98, 0.78, 0.98)


func _cell_hover_outline_color() -> Color:
	var reachable: Array = highlights.get("reachable", [])
	return _hover_outline_color() if hover_cell in reachable else Color(0.95, 0.95, 1.0, 0.95)


func _draw_unit_ground_outlines() -> void:
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
		var hover_alpha := float(_hover_outline_alpha_by_uid.get(unit.uid, 0.0))
		var selection_alpha := float(_selection_outline_alpha_by_uid.get(unit.uid, 0.0))
		if hover_alpha > 0.01:
			_draw_unit_focus_outline(unit, Color(1.0, 0.82, 0.32, 0.95), IsoCoordinates.visual(2.2), offset, 0.0, hover_alpha)
		if selection_alpha > 0.01:
			_draw_unit_focus_outline(unit, Color(1.0, 1.0, 1.0, 0.92), IsoCoordinates.visual(1.8), offset, 0.0, selection_alpha)


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
	var occupied_slots: Array[SlotState] = []
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		if _anim.masked_embedded_gems.has(slot.gem_uid):
			continue
		occupied_slots.append(slot)
	if occupied_slots.is_empty():
		return
	var icon_size := IsoCoordinates.visual(10.0)
	var spacing := IsoCoordinates.visual(11.0)
	var start_x := anchor.x - spacing * float(occupied_slots.size() - 1) * 0.5
	var icon_y := anchor.y - IsoCoordinates.visual(13.0)
	for i in range(occupied_slots.size()):
		var slot: SlotState = occupied_slots[i]
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tex: Texture2D = _gem_sprites.texture_for_gem_id(gem.gem_id)
		if tex == null:
			continue
		var tint: Color = _gem_sprites.modulate_for_gem_id(gem.gem_id)
		var cx := start_x + spacing * float(i)
		draw_texture_rect(
			tex,
			Rect2(Vector2(cx - icon_size * 0.5, icon_y - icon_size * 0.5), Vector2(icon_size, icon_size)),
			false,
			tint
		)


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


func _draw_shield_bar(origin: Vector2, unit: UnitState, shield_value: int) -> void:
	var icon_size := IsoCoordinates.visual(8.0)
	var gap := IsoCoordinates.visual(2.0)
	var bar_w := IsoCoordinates.visual(28.0)
	var bar_h := IsoCoordinates.visual(4.0)
	var bar_x := origin.x + icon_size + gap
	StatusIcons.draw_icon(self, origin, Constants.STATUS_ARMOR, icon_size)
	draw_rect(Rect2(bar_x, origin.y, bar_w, bar_h), BattleUiTheme.SHIELD_BG.darkened(0.05))
	var max_ref := maxi(unit.max_hp, shield_value)
	var ratio := clampf(float(shield_value) / float(maxi(max_ref, 1)), 0.0, 1.0)
	draw_rect(Rect2(bar_x, origin.y, bar_w * ratio, bar_h), BattleUiTheme.SHIELD_FILL)


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
		if status.status_id == Constants.STATUS_ARMOR:
			continue
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
		if StatusIcons.draw_icon(self , draw_pos, status.status_id, ICON_SIZE):
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
		"explosion_attack": return Color(1.0, 0.55, 0.1, 0.95)
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


func pick_cell(screen_pos: Vector2) -> Vector2i:
	return IsoCoordinates.pick_grid_at(screen_pos, _board_origin, _board_size(), invert_origin)


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
	_anim.strike_elapsed[attacker_uid] = 0.0
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
	tween.tween_method(_set_move_offset.bind(unit_uid), from_offset, to_offset, _scaled_duration(0.35))
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, to_offset, emit_finished))


## 播放一整条路径。逻辑位置已提前写到终点，视觉 offset 沿路径连续归零。
func animate_move_path(unit_uid: String, path: Array, emit_finished: bool = true) -> void:
	if path.size() < 2:
		if emit_finished:
			animation_finished.emit()
		return
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			mover.facing = _facing_from_grid_pos(path[path.size() - 2], path[path.size() - 1])
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
	tween.tween_method(_set_move_path_progress.bind(unit_uid, offset_path), 0.0, float(segment_count), duration)
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, Vector2.ZERO, emit_finished))


## 多单位同时位移（爆炸击退等）
func animate_moves_parallel(moves: Array) -> void:
	if moves.is_empty():
		animation_finished.emit()
		return
	_anim.parallel_move_remaining = moves.size()
	for mv in moves:
		var uid := str(mv.get("uid", ""))
		animate_move(uid, mv.get("from", Vector2i.ZERO), mv.get("to", Vector2i.ZERO), false)


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


func _set_move_path_progress(progress: float, uid: String, offset_path: Array[Vector2]) -> void:
	if offset_path.is_empty():
		return
	var max_segment := offset_path.size() - 1
	var seg := clampi(int(floor(progress)), 0, max_segment)
	if seg >= max_segment:
		_anim.move_offsets[uid] = offset_path[max_segment]
	else:
		var local_t := clampf(progress - float(seg), 0.0, 1.0)
		_anim.move_offsets[uid] = offset_path[seg].lerp(offset_path[seg + 1], local_t)
	queue_redraw()


func _on_move_anim_done(uid: String, _final_offset: Vector2, emit_finished: bool = true) -> void:
	_anim.walk_phase.erase(uid)
	_anim.move_offsets.erase(uid)
	queue_redraw()
	if not emit_finished:
		_anim.parallel_move_remaining = maxi(0, _anim.parallel_move_remaining - 1)
		if _anim.parallel_move_remaining <= 0:
			animation_finished.emit()
		return
	animation_finished.emit()


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
	_anim.particles.append({
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
	_anim.particles.append({
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
		_anim.particles.append({
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
			_anim.particles.append({
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
			_anim.particles.append({
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
				_anim.particles.append({
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
			_anim.particles.append({
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
			_anim.particles.append({
				"pos": center_legacy + Vector2(randf_range(-10, 10), randf_range(-5, 5)),
				"color": Color(0.3, 0.3, 0.35, 0.7),
				"life": life2,
				"max_life": life2,
				"velocity": vel2,
				"type": "smoke"
			})
		_anim.particles.append({
			"pos": center_legacy,
			"color": Color(1.0, 0.6, 0.1, 0.8),
			"life": 0.4,
			"max_life": 0.4,
			"velocity": Vector2.ZERO,
			"type": "ring"
		})
	queue_redraw()


## 绘制所有粒子
func _draw_anim_particles() -> void:
	for p in _anim.particles:
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
	if not _anim.cached_puff_paths.is_empty():
		return _anim.cached_puff_paths
	for fi in range(7):
		_anim.cached_puff_paths.append(_PUFF_FRAME_PATH % fi)
	return _anim.cached_puff_paths


# ═══════════════════════════════════════════════════════════════════════════
# 抛射物动画
# ═══════════════════════════════════════════════════════════════════════════

## 播放玩家投射物：从 from_grid 飞向 to_grid，走贝塞尔弧线
func play_projectile(from_grid: Vector2i, to_grid: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	play_projectiles([ {"from": from_grid, "to": to_grid, "color": proj_color}])


## 齐射：多枚投射物同时飞行
func play_projectiles(shots: Array) -> void:
	if shots.is_empty():
		animation_finished.emit()
		return
	_anim.active_projectiles.clear()
	var max_duration := 0.0
	for shot in shots:
		var from_grid: Vector2i = shot.get("from", Vector2i.ZERO)
		var to_grid: Vector2i = shot.get("to", Vector2i.ZERO)
		var proj_color: Color = shot.get("color", Color(0.95, 0.92, 0.45))
		var from_scr: Vector2 = grid_to_screen(from_grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
		var to_scr: Vector2 = grid_to_screen(to_grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
		var mid: Vector2 = (from_scr + to_scr) * 0.5
		var dist: float = from_scr.distance_to(to_scr)
		var ctrl: Vector2 = mid + Vector2(0, -clampf(dist * 0.45, IsoCoordinates.visual(28.0), IsoCoordinates.visual(90.0)))
		var duration: float = _scaled_duration(clampf(dist / IsoCoordinates.visual(520.0), 0.18, 0.38))
		max_duration = maxf(max_duration, duration)
		_anim.active_projectiles.append({
			"from": from_scr,
			"to": to_scr,
			"ctrl": ctrl,
			"t": 0.0,
			"color": proj_color,
		})
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_projectiles_t, 0.0, 1.0, max_duration)
	tween.tween_callback(_on_projectiles_done)


func _set_projectiles_t(t: float) -> void:
	for projectile in _anim.active_projectiles:
		projectile["t"] = t
	queue_redraw()


func _on_projectiles_done() -> void:
	_anim.active_projectiles.clear()
	queue_redraw()
	animation_finished.emit()


func _draw_projectile() -> void:
	for projectile in _anim.active_projectiles:
		_draw_single_projectile(projectile)


func _draw_single_projectile(projectile: Dictionary) -> void:
	var t: float = float(projectile["t"])
	var from: Vector2 = projectile["from"]
	var to: Vector2 = projectile["to"]
	var ctrl: Vector2 = projectile["ctrl"]
	var color: Color = projectile["color"]

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
