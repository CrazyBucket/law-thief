extends Control

const UnitVisuals = preload("res://scripts/ui/unit_visuals.gd")
const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal animation_finished()

var highlights: Dictionary = {}
var hover_cell: Vector2i = Vector2i(-1, -1)
var selected_unit_uid: String = ""
var state: GameState = null

var _board_origin: Vector2 = Vector2.ZERO

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim_queue: Array[Dictionary] = []  # 待播放动画队列
var _is_animating: bool = false

# 移动动画：单位 uid → 当前屏幕偏移（相对于逻辑位置）
var _move_offsets: Dictionary = {}  # uid → Vector2

# 特效粒子
var _particles: Array[Dictionary] = []  # {pos, color, life, max_life, velocity, type}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_origin)
	_update_origin()
	set_process(true)


func _update_origin() -> void:
	_board_origin = IsoCoordinates.board_origin(size)


func _process(delta: float) -> void:
	# 更新粒子
	var needs_redraw: bool = false
	var i: int = _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		p["life"] = p["life"] - delta
		if p["life"] <= 0.0:
			_particles.remove_at(i)
		else:
			p["pos"] = p["pos"] + p["velocity"] * delta
			p["velocity"] = p["velocity"] + Vector2(0, 120) * delta  # 重力
		needs_redraw = true
		i -= 1
	if needs_redraw and not _particles.is_empty():
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
	return IsoCoordinates.grid_to_screen(grid, _board_origin)


func _draw() -> void:
	if state == null:
		return
	for grid in IsoCoordinates.sorted_cells():
		_draw_tile(grid)
	for grid in IsoCoordinates.sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null:
			_draw_unit(unit)
	if hover_cell.x >= 0:
		TileRenderer.draw_hover_outline(self, grid_to_screen(hover_cell))
	# 绘制粒子特效
	_draw_particles()


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
	# 应用移动动画偏移
	var offset: Vector2 = _move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var texture: Texture2D = UnitVisuals.get_unit_texture(unit.unit_def_id)
	var sprite_size := Vector2(60, 66)
	# 单位底部对齐格子中心（站在菱形上）
	var top_left := center + Vector2(-sprite_size.x * 0.5, -sprite_size.y + 2)
	if texture != null:
		draw_texture_rect(texture, Rect2(top_left, sprite_size), false)
	if unit.uid == selected_unit_uid:
		var corners := IsoCoordinates.diamond_corners(center)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, Color(1, 1, 1, 0.9), 2.0, false)
	_draw_gem_diamonds(unit, center + Vector2(0, -sprite_size.y - 4))
	_draw_hp_bar(center + Vector2(-18, 6), unit)
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		_draw_intent_badge(center + Vector2(20, -sprite_size.y + 6), unit.intent.preview_text)


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
		var color: Color = UnitVisuals.gem_color(gem.gem_id).lerp(UnitVisuals.slot_color(slot.slot_type), 0.25)
		if slot.locked:
			color = color.darkened(0.35)
		_draw_small_diamond(pos, 11.0, 7.0, color)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-5, 3), UnitVisuals.gem_symbol(gem.gem_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.08, 0.08, 0.1))


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


func _draw_intent_badge(pos: Vector2, text: String) -> void:
	var short := text.substr(0, mini(4, text.length()))
	var badge_size := Vector2(36, 16)
	draw_rect(Rect2(pos, badge_size), Color(0.12, 0.12, 0.16, 0.85))
	draw_rect(Rect2(pos, badge_size), Color(0.95, 0.75, 0.25, 0.9), false, 1.0)
	draw_string(ThemeDB.fallback_font, pos + Vector2(4, 12), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.9, 0.7))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := IsoCoordinates.pick_grid_at(event.position, _board_origin, Constants.BOARD_SIZE)
		cell_hovered.emit(cell, cell.x >= 0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := IsoCoordinates.pick_grid_at(event.position, _board_origin, Constants.BOARD_SIZE)
		if cell.x >= 0:
			cell_clicked.emit(cell)


# ═══════════════════════════════════════════════════════════════════════════
# 动画 API
# ═══════════════════════════════════════════════════════════════════════════

## 播放移动动画：单位从 from_pos 滑动到 to_pos
func animate_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var from_screen: Vector2 = grid_to_screen(from_pos)
	var to_screen: Vector2 = grid_to_screen(to_pos)
	var delta_offset: Vector2 = from_screen - to_screen  # 初始偏移（从旧位置开始）
	_move_offsets[unit_uid] = delta_offset
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_move_offset.bind(unit_uid), delta_offset, Vector2.ZERO, 0.25)
	tween.tween_callback(_on_move_anim_done.bind(unit_uid))


func _set_move_offset(offset: Vector2, uid: String) -> void:
	_move_offsets[uid] = offset
	queue_redraw()


func _on_move_anim_done(uid: String) -> void:
	_move_offsets.erase(uid)
	queue_redraw()
	animation_finished.emit()


## 播放伤害/爆炸特效
func play_damage_effect(grid: Vector2i, damage: int, is_crit: bool) -> void:
	var center: Vector2 = grid_to_screen(grid)
	var count: int = clampi(damage * 2, 4, 20)
	var base_color: Color = Color(1.0, 0.3, 0.15) if is_crit else Color(1.0, 0.65, 0.2)
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
	queue_redraw()


## 播放治疗特效
func play_heal_effect(grid: Vector2i) -> void:
	var center: Vector2 = grid_to_screen(grid) + Vector2(0, -20)
	for _i in range(8):
		var vel: Vector2 = Vector2(randf_range(-20, 20), randf_range(-80, -40))
		var life: float = randf_range(0.4, 0.8)
		_particles.append({
			"pos": center + Vector2(randf_range(-12, 12), randf_range(0, 10)),
			"color": Color(0.3, 1.0, 0.5, 0.9),
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "heal"
		})
	queue_redraw()


## 播放宝石拔出/嵌入闪光
func play_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	var center: Vector2 = grid_to_screen(grid) + Vector2(0, -30)
	for _i in range(6):
		var angle: float = randf() * TAU
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(30, 80)
		var life: float = randf_range(0.2, 0.5)
		_particles.append({
			"pos": center,
			"color": gem_color,
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "gem"
		})
	queue_redraw()


## 播放大爆炸特效（自爆怪冲刺爆炸用）
func play_explosion(grid: Vector2i) -> void:
	var center: Vector2 = grid_to_screen(grid) + Vector2(0, -20)
	# 第一层：中心火焰爆发（大量高速粒子）
	for _i in range(30):
		var angle: float = randf() * TAU
		var speed: float = randf_range(100.0, 280.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		var life: float = randf_range(0.4, 0.9)
		var color: Color = Color(1.0, randf_range(0.2, 0.6), 0.05).lerp(Color.WHITE, randf() * 0.3)
		_particles.append({
			"pos": center + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
			"color": color,
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "spark"
		})
	# 第二层：烟雾（慢速大粒子）
	for _i in range(12):
		var angle: float = randf() * TAU
		var speed: float = randf_range(20.0, 60.0)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed + Vector2(0, -30)
		var life: float = randf_range(0.6, 1.2)
		_particles.append({
			"pos": center + Vector2(randf_range(-10, 10), randf_range(-5, 5)),
			"color": Color(0.3, 0.3, 0.35, 0.7),
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "smoke"
		})
	# 第三层：冲击波环（用 ring 类型）
	_particles.append({
		"pos": center,
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
		var color: Color = p["color"]
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
				var radius: float = 20.0 + progress * 60.0
				var ring_color: Color = color
				ring_color.a = alpha * 0.7
				draw_arc(pos, radius, 0, TAU, 24, ring_color, 2.5 * alpha + 0.5)
