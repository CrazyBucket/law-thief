class_name DamageTextManager
extends CanvasLayer

## 飘字系统：接收世界格坐标或屏幕坐标，生成带 Pop+Scatter+Fade 动画的伤害数字。
## 挂在战斗场景 HudLayer 之上（layer=8），节点永不随单位销毁。

# ─── 伤害类型常量 ───────────────────────────────────────────────────────────
const DMG_NORMAL  := "normal"
const DMG_CRIT    := "crit"
const DMG_HEAL    := "heal"
const DMG_ARMOR   := "armor"
const DMG_POISON  := "poison"
const DMG_FIRE    := "fire"
const DMG_ICE     := "ice"
const DMG_TRUE    := "true"

# ─── 颜色与样式字典 ──────────────────────────────────────────────────────────
const _STYLES: Dictionary = {
	DMG_NORMAL: {
		"color":   Color(0.95, 0.30, 0.30, 1.0),
		"scale":   1.0,
		"size":    20,
		"bold":    false,
	},
	DMG_CRIT: {
		"color":   Color(1.00, 0.28, 0.28, 1.0),
		"scale":   1.0,
		"size":    22,
		"bold":    true,
	},
	DMG_HEAL: {
		"color":   Color(0.28, 1.00, 0.55, 1.0),
		"scale":   1.0,
		"size":    16,
		"bold":    false,
	},
	DMG_ARMOR: {
		"color":   Color(0.55, 0.80, 1.00, 1.0),
		"scale":   1.0,
		"size":    14,
		"bold":    false,
	},
	DMG_POISON: {
		"color":   Color(0.42, 0.95, 0.45, 1.0),
		"scale":   1.0,
		"size":    15,
		"bold":    false,
	},
	DMG_FIRE: {
		"color":   Color(1.00, 0.52, 0.15, 1.0),
		"scale":   1.0,
		"size":    16,
		"bold":    false,
	},
	DMG_ICE: {
		"color":   Color(0.48, 0.88, 1.00, 1.0),
		"scale":   1.0,
		"size":    16,
		"bold":    false,
	},
	DMG_TRUE: {
		"color":   Color(1.00, 0.88, 0.25, 1.0),
		"scale":   1.0,
		"size":    18,
		"bold":    true,
	},
}

const _FONT_REGULAR := "res://assets/ui/Silkscreen-Regular.ttf"
const _FONT_BOLD    := "res://assets/ui/Silkscreen-Bold.ttf"

var _font_regular: FontFile = null
var _font_bold: FontFile = null


func _ready() -> void:
	layer = 8
	_font_regular = _load_pixel_font(_FONT_REGULAR)
	_font_bold    = _load_pixel_font(_FONT_BOLD)


func _load_pixel_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var f := ResourceLoader.load(path) as FontFile
	if f == null:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


## 在屏幕坐标 screen_pos 处弹出飘字（战斗 UI 全局坐标）
## dmg_type: 见 DMG_* 常量；value: 数字（正数伤害/负数回血均可）
func spawn(screen_pos: Vector2, value: int, dmg_type: String = DMG_NORMAL) -> void:
	var style: Dictionary = _STYLES.get(dmg_type, _STYLES[DMG_NORMAL])
	var label := Label.new()
	add_child(label)

	# 字体
	var use_bold: bool = style.get("bold", false)
	var font: FontFile = _font_bold if (use_bold and _font_bold != null) else _font_regular
	if font == null:
		font = ThemeDB.fallback_font as FontFile
	if font != null:
		label.add_theme_font_override("font", font)
	var base_size: int = style.get("size", 20)
	var font_size: int = base_size
	if dmg_type == DMG_NORMAL or dmg_type == DMG_CRIT:
		var bonus: int = int(sqrt(float(value)) * 1.8)
		font_size = mini(base_size + bonus, base_size + 14)
	label.add_theme_font_size_override("font_size", font_size)

	# 文本 & 颜色
	var prefix: String = "+" if dmg_type == DMG_HEAL else ""
	label.text = "%s%d" % [prefix, value]
	var col: Color = style.get("color", Color.WHITE)
	label.add_theme_color_override("font_color", col)

	# 关闭描边外额外的阴影，避免锯齿感
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))

	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 初始位置：在目标格上方，加随机 X 散射防止重叠
	var scatter_x: float = randf_range(-18.0, 18.0)
	var start_pos := screen_pos + Vector2(scatter_x, -28.0)
	label.position = start_pos
	label.pivot_offset = label.size * 0.5

	# 动画参数
	var travel_y: float = randf_range(52.0, 72.0)
	var end_pos := start_pos + Vector2(randf_range(-8.0, 8.0), -travel_y)
	var pop_scale_big: float = 1.55 if dmg_type == DMG_CRIT else 1.35
	var total_dur: float    = 0.88 if dmg_type == DMG_CRIT else 0.72

	# ── 阶段一：Pop（瞬间放大再缩回，0.10s） ────────────────────────────────
	label.scale = Vector2(pop_scale_big, pop_scale_big)
	var pop_tween := create_tween()
	pop_tween.set_ease(Tween.EASE_OUT)
	pop_tween.set_trans(Tween.TRANS_BACK)
	pop_tween.tween_property(label, "scale", Vector2.ONE, 0.10)

	# ── 阶段二：上浮（先快后慢，0.45s）+ 阶段三：淡出（最后 0.22s） ────────
	var fly_tween := create_tween()
	fly_tween.set_parallel(true)

	# 上浮曲线：Ease Out Cubic
	fly_tween.tween_property(label, "position", end_pos, total_dur)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)

	# 淡出延迟到后段才开始
	var fade_delay: float = total_dur * 0.62
	var fade_dur:   float = total_dur - fade_delay
	fly_tween.tween_property(label, "modulate:a", 0.0, fade_dur)\
		.set_delay(fade_delay)\
		.set_ease(Tween.EASE_IN)\
		.set_trans(Tween.TRANS_QUAD)

	# 动画结束后销毁
	fly_tween.tween_callback(label.queue_free).set_delay(total_dur + 0.02)
