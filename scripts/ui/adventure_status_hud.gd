extends Node

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const CoinTexture = preload("res://assets/ui/coin_gold.png")

var _layer: CanvasLayer = null
var _root: Control = null
var _panel: PanelContainer = null
var _gold_value: Label = null
var _hp_bar: ProgressBar = null
var _hp_value: Label = null
var _last_signature := ""
var _layout_viewport_size := Vector2.ZERO
var _gold_feedback_active := false
var _gold_feedback_value := 0
var _gold_feedback_tween: Tween = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "AdventureStatusLayer"
	_layer.layer = 200
	add_child(_layer)
	_root = Control.new()
	_root.name = "AdventureStatusRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	_build_view()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _build_view() -> void:
	_panel = PanelContainer.new()
	_panel.name = "AdventureStatus"
	_panel.custom_minimum_size = Vector2(0, 72)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _screen_edge_panel_style())
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	_panel.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(56, 56)
	portrait_frame.clip_contents = true
	portrait_frame.add_theme_stylebox_override("panel", _portrait_frame_style())
	row.add_child(portrait_frame)

	var portrait := TextureRect.new()
	portrait.texture = _player_portrait_texture()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(portrait)

	var status_frame := PanelContainer.new()
	status_frame.custom_minimum_size = Vector2(220, 56)
	status_frame.add_theme_stylebox_override("panel", _status_frame_style())
	row.add_child(status_frame)

	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 4)
	status_frame.add_child(status)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(210, 16)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.add_theme_stylebox_override("background", BattleUiTheme.bar_bg_style())
	_hp_bar.add_theme_stylebox_override("fill", BattleUiTheme.bar_fill_style(BattleUiTheme.HP_HIGH))
	status.add_child(_hp_bar)

	var values := HBoxContainer.new()
	values.add_theme_constant_override("separation", 6)
	status.add_child(values)

	_hp_value = Label.new()
	_hp_value.add_theme_font_size_override("font_size", 12)
	_hp_value.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	values.add_child(_hp_value)

	var value_spacer := Control.new()
	value_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.add_child(value_spacer)

	var coin := TextureRect.new()
	coin.texture = CoinTexture
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.custom_minimum_size = Vector2(20, 20)
	coin.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	values.add_child(coin)

	_gold_value = Label.new()
	_gold_value.add_theme_font_size_override("font_size", 16)
	_gold_value.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	values.add_child(_gold_value)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)


func _refresh() -> void:
	if _panel == null:
		return
	var scene := get_tree().current_scene
	var probe_scene_path := str(get_tree().root.get_meta("ui_visual_scene_path", ""))
	var scene_path := probe_scene_path if not probe_scene_path.is_empty() else (str(scene.scene_file_path) if scene != null else "")
	_apply_layout()
	_panel.visible = RunService.is_run_active() and not scene_path.is_empty() and scene_path != "res://scenes/battle/battle_scene.tscn" and scene_path != "res://scenes/main/main.tscn"
	if not _panel.visible:
		return
	var snapshot := RunService.get_player_run_snapshot()
	var gold := RunService.get_balance("gold")
	var current := int(snapshot.get("hp", 0))
	var maximum := maxi(1, int(snapshot.get("max_hp", 1)))
	var signature := "%d:%d:%d" % [gold, current, maximum]
	if signature == _last_signature:
		return
	_last_signature = signature
	if not _gold_feedback_active:
		_gold_value.text = str(gold)
	_hp_bar.max_value = maximum
	_hp_bar.value = clampi(current, 0, maximum)
	_hp_bar.add_theme_stylebox_override(
		"fill",
		BattleUiTheme.bar_fill_style(BattleUiTheme.hp_fill_color(float(current) / float(maximum)))
	)
	_hp_value.text = "%d / %d" % [current, maximum]


func gold_target_global_position() -> Vector2:
	if _gold_value == null or not is_instance_valid(_gold_value):
		return Vector2(270, 48)
	return _gold_value.get_global_rect().get_center()


func begin_gold_gain_feedback(previous_value: int) -> void:
	if _gold_value == null or not is_instance_valid(_gold_value):
		return
	_gold_feedback_active = true
	_gold_feedback_value = maxi(0, previous_value)
	_gold_value.text = str(_gold_feedback_value)


func apply_gold_arrival(amount: int) -> void:
	if _gold_value == null or not is_instance_valid(_gold_value):
		return
	_gold_feedback_value += maxi(0, amount)
	_gold_value.text = str(_gold_feedback_value)
	if _gold_feedback_tween != null and _gold_feedback_tween.is_valid():
		_gold_feedback_tween.kill()
	_gold_value.pivot_offset = _gold_value.size * 0.5
	_gold_value.scale = Vector2.ONE
	_gold_value.add_theme_color_override("font_color", Color("#fff0a8"))
	_gold_feedback_tween = create_tween()
	_gold_feedback_tween.tween_property(_gold_value, "scale", Vector2(1.22, 1.22), 0.055)
	_gold_feedback_tween.tween_property(_gold_value, "scale", Vector2.ONE, 0.10)
	_gold_feedback_tween.tween_callback(_restore_gold_feedback_color)


func finish_gold_gain_feedback() -> void:
	_gold_feedback_active = false
	_gold_feedback_value = RunService.get_balance("gold")
	if _gold_value != null and is_instance_valid(_gold_value):
		_gold_value.text = str(_gold_feedback_value)
	_restore_gold_feedback_color()


func _restore_gold_feedback_color() -> void:
	if _gold_value != null and is_instance_valid(_gold_value):
		_gold_value.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)


func _apply_layout() -> void:
	if _panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if _layout_viewport_size == viewport_size:
		return
	_layout_viewport_size = viewport_size
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = 0
	_panel.offset_bottom = 72


func _screen_edge_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BattleUiTheme.BG_PANEL
	style.border_color = BattleUiTheme.BORDER_ACCENT.darkened(0.2)
	style.border_width_bottom = 2
	style.content_margin_left = 18
	style.content_margin_top = 8
	style.content_margin_right = 18
	style.content_margin_bottom = 8
	return style


func _portrait_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BattleUiTheme.BG_INSET
	style.border_color = BattleUiTheme.BORDER_ACCENT.darkened(0.08)
	style.set_border_width_all(2)
	style.content_margin_left = 3
	style.content_margin_top = 3
	style.content_margin_right = 3
	style.content_margin_bottom = 3
	return style


func _status_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BattleUiTheme.BG_INSET.darkened(0.08)
	style.border_color = BattleUiTheme.BORDER_ACCENT.darkened(0.32)
	style.set_border_width_all(2)
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	return style


func _player_portrait_texture() -> Texture2D:
	var source := UnitLooks.get_unit_texture("unit_player")
	if not source is AtlasTexture:
		return source
	var source_atlas := source as AtlasTexture
	var crop := AtlasTexture.new()
	crop.atlas = source_atlas.atlas
	var region := source_atlas.region
	region.size.y *= 0.58
	crop.region = region
	return crop
