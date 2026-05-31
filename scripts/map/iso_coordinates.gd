class_name IsoCoordinates
extends RefCounted

## 战斗/地图棋盘相对视口的填充比例（由 IsometricBoard 在 resized 时写入）
static var tile_scale: float = 1.0
const BOARD_FILL_RATIO := 0.9

# 标准 2:1 等距：菱形宽 ISO_TILE_W，半高 ISO_TILE_H，四边完美拼接

static func _half_w() -> float:
	return Constants.ISO_TILE_W * 0.5 * tile_scale


static func _half_h() -> float:
	return Constants.ISO_TILE_H * 0.5 * tile_scale


static func _tile_w() -> float:
	return Constants.ISO_TILE_W * tile_scale


static func _tile_h() -> float:
	return Constants.ISO_TILE_H * tile_scale


static func compute_tile_scale(
	view_size: Vector2,
	board_size: Vector2i,
	fill_ratio: float = BOARD_FILL_RATIO
) -> float:
	var pixel := board_pixel_size(board_size, 1.0)
	if pixel.x <= 0.0 or pixel.y <= 0.0:
		return 1.0
	return minf(view_size.x * fill_ratio / pixel.x, view_size.y * fill_ratio / pixel.y)


## 棋盘 UI 装饰（单位贴图、特效尺寸等）与地块同比例缩放
static func visual(v: float) -> float:
	return v * tile_scale


static func visual_vec(v: Vector2) -> Vector2:
	return v * tile_scale


static func entity_foot_offset() -> Vector2:
	# 与 IsometricBoard 单位脚底对齐：top 留白 visual(2) + ground nudge visual(12)
	return Vector2(0.0, visual(14.0))


static func prop_draw_rect(center: Vector2, texture: Texture2D, foot_ratio: float = 1.0) -> Rect2:
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2()
	# 静物应略小于 Knight（62×70），避免柱/雕像压过棋盘
	var max_box := Vector2(_tile_w() * 0.36, _tile_h() * 0.92)
	var scale := minf(max_box.x / tex_size.x, max_box.y / tex_size.y)
	var draw_size := tex_size * scale
	var foot := center + entity_foot_offset()
	var foot_frac := clampf(foot_ratio, 0.15, 1.0)
	var top_left := Vector2(foot.x - draw_size.x * 0.5, foot.y - draw_size.y * foot_frac)
	return Rect2(top_left, draw_size)


static func invert_grid(grid: Vector2i, board_size: Vector2i) -> Vector2i:
	return Vector2i(board_size.x - 1 - grid.x, board_size.y - 1 - grid.y)


static func to_display_grid(grid: Vector2i, board_size: Vector2i, invert_origin: bool) -> Vector2i:
	if invert_origin:
		return invert_grid(grid, board_size)
	return grid


static func depth_sort_key(grid: Vector2i, board_size: Vector2i, invert_origin: bool) -> int:
	var g := to_display_grid(grid, board_size, invert_origin)
	return g.x + g.y


static func grid_to_screen(
	grid: Vector2i,
	origin: Vector2,
	invert_origin: bool = false,
	board_size: Vector2i = Constants.BOARD_SIZE
) -> Vector2:
	var display := to_display_grid(grid, board_size, invert_origin)
	var half_w := _half_w()
	return origin + Vector2(
		(display.x - display.y) * half_w,
		(display.x + display.y) * _half_h()
	)


static func screen_to_grid(screen: Vector2, origin: Vector2) -> Vector2i:
	var local := screen - origin
	var half_w := _half_w()
	var half_h := _half_h()
	var gx := (local.x / half_w + local.y / half_h) * 0.5
	var gy := (local.y / half_h - local.x / half_w) * 0.5
	return Vector2i(int(round(gx)), int(round(gy)))


static func diamond_corners(center: Vector2) -> PackedVector2Array:
	var half_w := _half_w()
	var half_h := _half_h()
	return PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])


static func point_in_diamond(point: Vector2, center: Vector2) -> bool:
	var half_w := _half_w()
	var half_h := _half_h()
	var rel := point - center
	if half_w <= 0.0 or half_h <= 0.0:
		return false
	return absf(rel.x) / half_w + absf(rel.y) / half_h <= 1.0


static func pick_grid_at(
	screen: Vector2,
	origin: Vector2,
	board_size: Vector2i,
	invert_origin: bool = false
) -> Vector2i:
	# screen_to_grid 解的是显示坐标；invert 时再反算回逻辑坐标（与战斗模式同量级）
	var display_rough := screen_to_grid(screen, origin)
	var logical_rough: Vector2i = (
		invert_grid(display_rough, board_size) if invert_origin else display_rough
	)
	var candidates: Array[Vector2i] = [
		logical_rough,
		logical_rough + Vector2i(-1, 0),
		logical_rough + Vector2i(1, 0),
		logical_rough + Vector2i(0, -1),
		logical_rough + Vector2i(0, 1),
		logical_rough + Vector2i(-1, -1),
		logical_rough + Vector2i(1, 1),
		logical_rough + Vector2i(-1, 1),
		logical_rough + Vector2i(1, -1),
	]
	var best: Vector2i = Vector2i(-1, -1)
	var best_depth: int = -1
	for logical in candidates:
		if logical.x < 0 or logical.y < 0 or logical.x >= board_size.x or logical.y >= board_size.y:
			continue
		if not point_in_diamond(screen, grid_to_screen(logical, origin, invert_origin, board_size)):
			continue
		if not invert_origin:
			return logical
		var depth: int = depth_sort_key(logical, board_size, true)
		if depth > best_depth:
			best_depth = depth
			best = logical
	return best


static func board_pixel_size(board_size: Vector2i = Constants.BOARD_SIZE, scale: float = -1.0) -> Vector2:
	## 棋盘实际像素边界框（含菱形边缘）
	var s := tile_scale if scale < 0.0 else scale
	var half_w := Constants.ISO_TILE_W * 0.5 * s
	var half_h := Constants.ISO_TILE_H * 0.5 * s
	var span_x: float = (board_size.x + board_size.y - 2) * half_w + Constants.ISO_TILE_W * s
	var span_y: float = (board_size.x + board_size.y - 2) * half_h + Constants.ISO_TILE_H * s
	return Vector2(span_x, span_y)


static func board_origin(view_size: Vector2, board_size: Vector2i = Constants.BOARD_SIZE) -> Vector2:
	## 返回 grid(0,0) 的屏幕坐标，使整个棋盘在 view_size 内居中
	var half_h := _half_h()
	var pixel_size := board_pixel_size(board_size)
	# 棋盘关于 origin.x 左右对称，所以 origin.x = 视图水平中心
	var ox: float = view_size.x * 0.5
	# 棋盘顶部边缘在 origin.y - half_h，底部在 origin.y + (N+N-2)*half_h + half_h
	# 要让棋盘垂直居中：origin.y - half_h = (view_h - pixel_size.y) / 2
	var oy: float = (view_size.y - pixel_size.y) * 0.5 + half_h
	return Vector2(ox, oy)


static func sorted_cells(
	board_size: Vector2i = Constants.BOARD_SIZE,
	invert_origin: bool = false
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(board_size.y):
		for x in range(board_size.x):
			cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := depth_sort_key(a, board_size, invert_origin)
		var db := depth_sort_key(b, board_size, invert_origin)
		if da == db:
			return a.x < b.x
		return da < db
	)
	return cells
