extends Control
## 主菜单

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

@onready var _particle_canvas: Control = $ParticleCanvas
@onready var _title: Label = $ContentLayer/TitleBlock/Title
@onready var _subtitle: Label = $ContentLayer/TitleBlock/Subtitle
@onready var _tagline: Label = $ContentLayer/TitleBlock/Tagline
@onready var _menu_block: VBoxContainer = $ContentLayer/MenuBlock
@onready var _bottom_info: Label = $ContentLayer/BottomInfo

var _particles: Array[Dictionary] = []
var _time: float = 0.0
var _title_glow: float = 0.0


func _ready() -> void:
	DebugService.log_info("Main scene ready")
	_spawn_background_particles()
	_style_buttons()
	_play_intro_animation()


func _process(delta: float) -> void:
	_time += delta
	_title_glow = (sin(_time * 1.5) + 1.0) * 0.5
	# 标题颜色呼吸
	var base_color := Color(0.92, 0.28, 0.38)
	var glow_color := Color(1.0, 0.55, 0.4)
	_title.add_theme_color_override("font_color", base_color.lerp(glow_color, _title_glow * 0.4))
	# 副标题微弱闪烁
	_subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78, 0.6 + _title_glow * 0.3))
	# 更新粒子
	_update_particles(delta)
	_particle_canvas.queue_redraw()


func _spawn_background_particles() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for _i in range(40):
		_particles.append({
			"pos": Vector2(randf() * viewport_size.x, randf() * viewport_size.y),
			"vel": Vector2(randf_range(-12, 12), randf_range(-20, -5)),
			"size": randf_range(1.5, 4.0),
			"alpha": randf_range(0.15, 0.45),
			"color_idx": randi() % 4,
		})
	_particle_canvas.draw.connect(_draw_particles)


func _update_particles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for p in _particles:
		p["pos"] = p["pos"] + p["vel"] * delta
		# 缓慢漂浮 + 微弱横向摆动
		p["pos"].x += sin(_time * 0.8 + p["size"] * 10.0) * 8.0 * delta
		# 超出屏幕则重置
		if p["pos"].y < -10 or p["pos"].x < -10 or p["pos"].x > viewport_size.x + 10:
			p["pos"] = Vector2(randf() * viewport_size.x, viewport_size.y + randf_range(5, 30))
			p["vel"] = Vector2(randf_range(-12, 12), randf_range(-20, -8))


func _draw_particles() -> void:
	var colors: Array[Color] = [
		Color(0.92, 0.28, 0.38, 1.0),  # 红
		Color(0.35, 0.65, 0.95, 1.0),  # 蓝
		Color(1.0, 0.75, 0.2, 1.0),    # 金
		Color(0.55, 0.9, 0.35, 1.0),   # 绿
	]
	for p in _particles:
		var color: Color = colors[p["color_idx"]]
		color.a = p["alpha"]
		var sz: float = p["size"]
		# 画菱形粒子
		var pos: Vector2 = p["pos"]
		var points := PackedVector2Array([
			pos + Vector2(0, -sz),
			pos + Vector2(sz * 0.6, 0),
			pos + Vector2(0, sz),
			pos + Vector2(-sz * 0.6, 0),
		])
		_particle_canvas.draw_colored_polygon(points, color)


func _style_buttons() -> void:
	var buttons: Array[Button] = []
	for child in _menu_block.get_children():
		if child is Button:
			buttons.append(child as Button)

	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		var is_primary: bool = (i == 0)
		_apply_button_style(btn, is_primary)


func _apply_button_style(btn: Button, is_primary: bool) -> void:
	BattleUiTheme.apply_button(btn, "end" if is_primary else "ghost")
	btn.add_theme_font_size_override("font_size", 16 if is_primary else 14)


func _play_intro_animation() -> void:
	# 标题从上方滑入
	var title_block: Control = $ContentLayer/TitleBlock
	title_block.modulate.a = 0.0
	title_block.position.y -= 30
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(title_block, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(title_block, "position:y", title_block.position.y + 30, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 按钮逐个淡入
	var delay: float = 0.3
	for child in _menu_block.get_children():
		if child is Button:
			child.modulate.a = 0.0
			var btn_tween := create_tween()
			btn_tween.tween_interval(delay)
			btn_tween.tween_property(child, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)
			delay += 0.08

	# 底部信息
	_bottom_info.modulate.a = 0.0
	var bottom_tween := create_tween()
	bottom_tween.tween_interval(0.8)
	bottom_tween.tween_property(_bottom_info, "modulate:a", 0.6, 0.5)
	_tagline.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55, 0.8))


func _on_start_pressed() -> void:
	var encounters: Array[String] = ["template_a", "template_b", "template_c", "template_d"]
	var pick: String = encounters[randi() % encounters.size()]
	_start_battle(pick)


func _on_map_pressed() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		AdventureService.start_new_run()
		get_tree().change_scene_to_file("res://scenes/map/adventure_map.tscn")
	)


func _start_battle(encounter_id: String) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		GameService.start_battle(encounter_id)
		get_tree().change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	)
