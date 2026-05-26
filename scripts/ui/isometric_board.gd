extends Control

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const BoardFxTexturesClass := preload("res://scripts/ui/board_fx_textures.gd")
const BoardUtilsClass := preload("res://scripts/rules/board_utils.gd")
const _Vpf := preload("res://scripts/ui/vfx_pack_frames.gd")
const StatusIcons := preload("res://scripts/ui/status_icons.gd")

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal animation_finished()

var highlights: Dictionary = {}
var hover_cell: Vector2i = Vector2i(-1, -1)
var selected_unit_uid: String = ""
var state: GameState = null
## 为 true 时逻辑 (0,0) 显示在棋盘底部（等距原点对调，仅冒险地图）
var invert_origin: bool = false

var _board_origin: Vector2 = Vector2.ZERO
var _animation_speed_scale: float = 1.0

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim_queue: Array[Dictionary] = []  # 待播放动画队列
var _is_animating: bool = false

# 移动动画：单位 uid → 当前屏幕偏移（相对于逻辑位置）
var _move_offsets: Dictionary = {}  # uid → Vector2

# 特效粒子
var _particles: Array[Dictionary] = []  # {pos, color, life, max_life, velocity, type}

var _strike_elapsed: Dictionary = {}
var _orientation: Dictionary = {}
var _walk_phase: Dictionary = {}

var _cached_puff_paths: PackedStringArray = PackedStringArray()

var _knight_sprites: RefCounted = null ## DoodleKnightSprites
var _fx_textures: RefCounted = null

# 抛射物动画：二次贝塞尔曲线飞行
var _projectile: Dictionary = {}  # {from, to, ctrl, t, color} 空表示无飞行中抛射物

## Knight 底板锚点在格心；贴图腿长导致视觉上偏悬空，下移若干像素压住地面感
const _UNIT_SPRITE_GROUND_OFFSET_Y := 12.0
const _PUFF_FRAME_PATH := "res://assets/demo/doodle-rpg/ALL SPRITES/Particles/Puff_%d.png"


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_origin)
	_update_origin()
	_knight_sprites = KNIGHT_SPRITES_SCRIPT.new()
	_fx_textures = BoardFxTexturesClass.new()
	set_process(true)


func _update_origin() -> void:
	_board_origin = IsoCoordinates.board_origin(size)


func _process(delta: float) -> void:
	var visuals_dirty := false
	var scaled_dt := delta * _animation_speed_scale
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


func set_battle_state(new_state: GameState) -> void:
	state = new_state
	queue_redraw()


func set_highlights(new_highlights: Dictionary) -> void:
	highlights = new_highlights
	queue_redraw()


func set_hover(cell: Vector2i) -> void:
	hover_cell = cell
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
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null:
			_draw_unit(unit)
	if hover_cell.x >= 0:
		TileRenderer.draw_hover_outline(self, grid_to_screen(hover_cell))
	# 绘制粒子特效
	_draw_particles()
	_draw_projectile()


func _draw_tile(grid: Vector2i) -> void:
	var center := grid_to_screen(grid)
	var tile := state.get_tile(grid)
	var highlight := _tile_highlight(grid)
	TileRenderer.draw_tile(self, center, tile, highlight)


func _tile_highlight(grid: Vector2i) -> Color:
	var reachable: Array = highlights.get("reachable", [])
	var targets: Array = highlights.get("targets", [])
	var paths: Array = highlights.get("paths", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	if grid in reachable:
		return Color(0.35, 0.85, 1.0, 0.42)
	if grid in targets:
		return Color(1.0, 0.95, 0.35, 0.48)
	if grid in effect_list:
		return Color(1.0, 0.5, 0.15, 0.45)
	if grid in danger:
		return Color(1.0, 0.25, 0.25, 0.45)
	if grid in paths:
		return Color(0.95, 0.65, 0.2, 0.28)
	return Color.TRANSPARENT


func _draw_unit(unit: UnitState) -> void:
	var center := grid_to_screen(unit.pos)
	var offset: Vector2 = _move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var sprite_size := Vector2(62.0, 70.0)
	var ground_nudge := Vector2(0.0, _UNIT_SPRITE_GROUND_OFFSET_Y)
	var top_left := center + Vector2(-sprite_size.x * 0.5, -sprite_size.y + 2.0) + ground_nudge
	var facing := str(_orientation.get(unit.uid, "Forward"))
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
		var sh_tl := center + Vector2(-sh_sz.x * 0.5, -2.0) + ground_nudge
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.42))

	if pose_tex != null:
		draw_texture_rect(pose_tex, Rect2(top_left, sprite_size), false, tint)
	if unit.uid == selected_unit_uid:
		var corners := IsoCoordinates.diamond_corners(center)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, Color(1, 1, 1, 0.9), 2.0, false)
	_draw_gem_diamonds(unit, center + Vector2(0, -sprite_size.y - 4) + ground_nudge)
	_draw_hp_bar(center + Vector2(-18, 6), unit)
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		_draw_intent_badge(center + Vector2(20, -sprite_size.y + 6) + ground_nudge, unit.intent.preview_text)


func _draw_gem_diamonds(unit: UnitState, anchor: Vector2) -> void:
	var gems_to_draw: Array = []
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		gems_to_draw.append({"slot": slot, "gem": gem})
	if gems_to_draw.is_empty():
		return
	var spacing := 14.0
	var start_x := anchor.x - (gems_to_draw.size() - 1) * spacing * 0.5
	for i in range(gems_to_draw.size()):
		var entry: Dictionary = gems_to_draw[i]
		var slot: SlotState = entry["slot"]
		var gem: GemState = entry["gem"]
		var pos := Vector2(start_x + i * spacing, anchor.y)
		var color: Color = UnitLooks.gem_color(gem).lerp(UnitLooks.slot_color(slot.slot_type), 0.25)
		if slot.locked:
			color = color.darkened(0.35)
		_draw_small_diamond(pos, 11.0, 7.0, color)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-5, 3), UnitLooks.gem_symbol(gem), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.08, 0.08, 0.1))


func _draw_small_diamond(center: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height),
		center + Vector2(-width * 0.5, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.35), 1.2, true)


func _draw_hp_bar(center: Vector2, unit: UnitState) -> void:
	var width := 36.0
	var ratio := clampf(float(unit.hp) / float(maxi(unit.max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(center, Vector2(width, 5)), Color(0.12, 0.12, 0.16, 0.85))
	var fill_color := Color(0.25, 0.85, 0.45) if unit.team == Constants.TEAM_PLAYER else Color(0.9, 0.35, 0.45)
	draw_rect(Rect2(center, Vector2(width * ratio, 5)), fill_color)
	if not unit.statuses.is_empty():
		_draw_status_row(center + Vector2(0, 7), unit)


func _draw_status_row(origin: Vector2, unit: UnitState) -> void:
	const ICON_SIZE := 13.0
	const GAP := 2.0
	const FONT_SIZE := 9
	const PAD_X := 3.0
	const PAD_Y := 2.0
	var sorted: Array = StatusRegistry.sort_statuses(unit.statuses)
	var cursor_x := origin.x
	for status in sorted:
		var color: Color = StatusRegistry.status_color(status.status_id)
		var bg := color.darkened(0.5)
		bg.a = 0.88
		if StatusIcons.has_icon(status.status_id):
			draw_rect(Rect2(Vector2(cursor_x, origin.y), Vector2(ICON_SIZE, ICON_SIZE)), bg)
			StatusIcons.draw_icon(self, Vector2(cursor_x, origin.y), status.status_id, ICON_SIZE)
			cursor_x += ICON_SIZE + GAP
		else:
			var font := ThemeDB.fallback_font
			var label: String = StatusRegistry.short_label(status)
			var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var chip_w := text_w + PAD_X * 2.0
			var chip_h := FONT_SIZE + PAD_Y * 2.0
			draw_rect(Rect2(Vector2(cursor_x, origin.y), Vector2(chip_w, chip_h)), bg)
			draw_rect(Rect2(Vector2(cursor_x, origin.y), Vector2(chip_w, chip_h)), color.lightened(0.1), false, 1.0)
			draw_string(font, Vector2(cursor_x + PAD_X, origin.y + PAD_Y + FONT_SIZE - 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.95, 0.96, 0.98))
			cursor_x += chip_w + GAP


func _draw_intent_badge(pos: Vector2, text: String) -> void:
	var short := text.substr(0, mini(4, text.length()))
	var badge_size := Vector2(36, 16)
	draw_rect(Rect2(pos, badge_size), Color(0.12, 0.12, 0.16, 0.85))
	draw_rect(Rect2(pos, badge_size), Color(0.95, 0.75, 0.25, 0.9), false, 1.0)
	draw_string(ThemeDB.fallback_font, pos + Vector2(4, 12), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.9, 0.7))


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
	var dg := victim_cell - attacker.pos
	_orientation[attacker_uid] = _knight_sprites.facing_from_grid_delta(dg)
	_strike_elapsed[attacker_uid] = 0.0
	queue_redraw()


## 播放移动动画：单位从 from_pos 滑动到 to_pos
func animate_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var dg := to_pos - from_pos
	_orientation[unit_uid] = _knight_sprites.facing_from_grid_delta(dg)
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
	var tint: Color = cfg.get("tint", Color.WHITE)
	var vel_here: Variant = cfg.get("velocity", Vector2.ZERO)
	var vel2: Vector2 = vel_here if vel_here is Vector2 else Vector2.ZERO
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
	var center_scr: Vector2 = grid_to_screen(grid) + Vector2(0.0, -16.0)
	var used_pack := false
	if _Vpf.is_pack_available() and not hit_paths.is_empty():
		var dim_big := 72.0
		var dim_small := 56.0
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
	for _i in range(count):
		var angle: float = randf() * TAU
		var speed: float = randf_range(60.0, 180.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		var life: float = randf_range(0.3, 0.6)
		var color: Color = base_color.lerp(Color.WHITE, randf() * 0.4)
		_particles.append({
			"pos": center + Vector2(randf_range(-8, 8), randf_range(-20, -5)),
			"color": color,
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "spark"
		})


## 播放治疗特效
func play_heal_effect(grid: Vector2i) -> void:
	var heal_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_HEAL_CHARGE)
	var center_scr: Vector2 = grid_to_screen(grid) + Vector2(0.0, -20.0)
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
		var center_legacy: Vector2 = grid_to_screen(grid) + Vector2(0, -20)
		for _i in range(8):
			var vel: Vector2 = Vector2(randf_range(-20, 20), randf_range(-80, -40))
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
	var center_scr: Vector2 = grid_to_screen(grid) + Vector2(0.0, -30.0)
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
		var center_legacy: Vector2 = grid_to_screen(grid) + Vector2(0, -30)
		for _i in range(6):
			var angle: float = randf() * TAU
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(30, 80)
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
		var base: Vector2 = grid_to_screen(cell) + Vector2(0, -10)
		var placed_pack := false
		if _Vpf.is_pack_available() and not puff_vfx.is_empty():
			placed_pack = _push_sprite_sequence({
				"paths": puff_vfx,
				"pos": base + Vector2(randf_range(-12, 12), randf_range(-14, 6)),
				"fps": 42.0,
				"draw_size": Vector2(72.0, 72.0),
				"tint": Color(0.38, 0.95, 0.52),
				"velocity": Vector2(randf_range(-10, 10), randf_range(-22, -6)),
				"life_pad": 0.03,
			})
		if not placed_pack:
			var puff_legacy: PackedStringArray = _puff_sprite_paths()
			for _j in range(2):
				var life_here: float = randf_range(0.48, 0.62)
				_particles.append({
					"type": "sprite_seq",
					"pos": base + Vector2(randf_range(-14, 14), randf_range(-18, 8)),
					"life": life_here,
					"max_life": life_here,
					"velocity": Vector2(randf_range(-18, 18), randf_range(-32, -12)),
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
	var center_scr: Vector2 = grid_to_screen(grid) + Vector2(0.0, -24.0)
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
	var from_scr: Vector2 = grid_to_screen(from_grid) + Vector2(0, -20)
	var to_scr: Vector2 = grid_to_screen(to_grid) + Vector2(0, -20)
	var mid: Vector2 = (from_scr + to_scr) * 0.5
	var dist: float = from_scr.distance_to(to_scr)
	# 控制点向上偏移，距离越远弧度越明显
	var ctrl: Vector2 = mid + Vector2(0, -clampf(dist * 0.45, 28.0, 90.0))
	_projectile = {
		"from": from_scr,
		"to": to_scr,
		"ctrl": ctrl,
		"t": 0.0,
		"color": proj_color,
	}
	var duration: float = _scaled_duration(clampf(dist / 520.0, 0.18, 0.38))
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
		draw_line(pos, trail_pos, trail_color, maxf(3.0 - s * 1.5, 0.5))

	# 弹头：菱形
	var perp: Vector2 = Vector2(-tangent.y, tangent.x)
	var tip: Vector2 = pos + tangent * 7.0
	var tail_pt: Vector2 = pos - tangent * 5.0
	var left_pt: Vector2 = pos + perp * 3.5
	var right_pt: Vector2 = pos - perp * 3.5
	var pts := PackedVector2Array([tip, left_pt, tail_pt, right_pt])
	draw_colored_polygon(pts, color)
	var outline_color: Color = color.darkened(0.3)
	outline_color.a = 0.85
	draw_polyline(PackedVector2Array([tip, left_pt, tail_pt, right_pt, tip]), outline_color, 1.0)
