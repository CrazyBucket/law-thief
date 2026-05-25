class_name IsoCoordinates
extends RefCounted

# 标准 2:1 等距：菱形宽 ISO_TILE_W，半高 ISO_TILE_H，四边完美拼接
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
	var half_w := Constants.ISO_TILE_W * 0.5
	return origin + Vector2(
		(display.x - display.y) * half_w,
		(display.x + display.y) * Constants.ISO_TILE_H * 0.5
	)


static func screen_to_grid(screen: Vector2, origin: Vector2) -> Vector2i:
	var local := screen - origin
	var half_w := Constants.ISO_TILE_W * 0.5
	var half_h := Constants.ISO_TILE_H * 0.5
	var gx := (local.x / half_w + local.y / half_h) * 0.5
	var gy := (local.y / half_h - local.x / half_w) * 0.5
	return Vector2i(int(round(gx)), int(round(gy)))


static func diamond_corners(center: Vector2) -> PackedVector2Array:
	var half_w := Constants.ISO_TILE_W * 0.5
	var half_h := Constants.ISO_TILE_H * 0.5
	return PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
	])


static func point_in_diamond(point: Vector2, center: Vector2) -> bool:
	var half_w := Constants.ISO_TILE_W * 0.5
	var half_h := Constants.ISO_TILE_H * 0.5
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


static func board_pixel_size() -> Vector2:
	## 棋盘实际像素边界框（含菱形边缘）
	var half_w := Constants.ISO_TILE_W * 0.5
	var half_h := Constants.ISO_TILE_H * 0.5
	# 宽度：最左 grid(0,N-1) 到最右 grid(N-1,0) 的 x 跨度 + 一个菱形宽
	var span_x: float = (Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y - 2) * half_w + Constants.ISO_TILE_W
	# 高度：最上 grid(0,0) 到最下 grid(N-1,N-1) 的 y 跨度 + 一个菱形高
	var span_y: float = (Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y - 2) * half_h + Constants.ISO_TILE_H
	return Vector2(span_x, span_y)


static func board_origin(view_size: Vector2) -> Vector2:
	## 返回 grid(0,0) 的屏幕坐标，使整个棋盘在 view_size 内居中
	var half_h := Constants.ISO_TILE_H * 0.5
	var pixel_size := board_pixel_size()
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
