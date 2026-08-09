class_name SystemPauseMenu
extends CanvasLayer

signal save_and_exit_requested
signal animation_speed_changed

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const PixelMenuButtonScript = preload("res://scripts/ui/pixel_menu_button.gd")
const MenuButtonEdgeTexture = preload("res://assets/ui/menu_btn_edge.png")
const MenuTitleTexture = preload("res://assets/ui/main_title_v2.png")
const _ANIMATION_SPEED_OPTIONS := [0.75, 1.0, 1.5, 2.0]
const _PAGE_MENU := "menu"
const _PAGE_SETTINGS := "settings"

var _page: String = _PAGE_MENU
var _panel: PanelContainer = null
var _title_art: TextureRect = null
var _title: Label = null
var _separator: HSeparator = null
var _body: VBoxContainer = null
var _first_focus: Control = null
var _resume_text_key := "battle.menu.resume"
var _resume_fallback := "继续战斗"


func _init() -> void:
	layer = 300
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_shell()


func open_menu() -> void:
	_show_menu_page()
	visible = true
	_focus_first_control()


func configure_context(resume_text_key: String, resume_fallback: String) -> void:
	_resume_text_key = resume_text_key
	_resume_fallback = resume_fallback


func close_menu() -> void:
	visible = false


func is_open() -> bool:
	return visible


func is_settings_page() -> bool:
	return visible and _page == _PAGE_SETTINGS


func handle_cancel() -> bool:
	if not visible:
		return false
	if _page == _PAGE_SETTINGS:
		_show_menu_page()
		_focus_first_control()
	else:
		close_menu()
	return true


func show_settings() -> void:
	_show_settings_page()
	visible = true
	_focus_first_control()


func _build_shell() -> void:
	var root := Control.new()
	root.name = "SystemMenuRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = BattleUiTheme.build_theme()
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.005, 0.012, 0.02, 0.46)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "MenuPanel"
	center.add_child(_panel)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_panel.add_child(stack)

	_title_art = TextureRect.new()
	_title_art.name = "TitleArt"
	_title_art.custom_minimum_size = Vector2(360, 207)
	_title_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_art.texture = MenuTitleTexture
	_title_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_title_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack.add_child(_title_art)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	stack.add_child(_title)

	_separator = HSeparator.new()
	_separator.modulate = Color(0.35, 0.75, 0.62, 0.28)
	stack.add_child(_separator)

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 12)
	stack.add_child(_body)

func _show_menu_page() -> void:
	_page = _PAGE_MENU
	_clear_body()
	_apply_page_chrome(false)
	_title.text = ""

	var button_stack := VBoxContainer.new()
	button_stack.name = "MenuActions"
	button_stack.add_theme_constant_override("separation", 10)
	button_stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(button_stack)

	var resume_btn := _build_main_menu_button(
		_text(_resume_text_key, _resume_fallback),
		close_menu,
		true
	)
	button_stack.add_child(resume_btn)
	_first_focus = resume_btn

	var settings_btn := _build_main_menu_button(
		_text("system.menu.settings", "设置"),
		show_settings
	)
	settings_btn.name = "SettingsButton"
	button_stack.add_child(settings_btn)

	var save_btn := _build_main_menu_button(
		_text("system.menu.save_exit", "保存并返回"),
		_on_save_and_exit_pressed
	)
	save_btn.name = "SaveAndExitButton"
	button_stack.add_child(save_btn)


func _show_settings_page() -> void:
	_page = _PAGE_SETTINGS
	_clear_body()
	_apply_page_chrome(true)
	_title.text = _text("system.settings.title", "设置")

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.custom_minimum_size = Vector2(624, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)

	var settings_stack := VBoxContainer.new()
	settings_stack.name = "SettingsContent"
	settings_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_stack.add_theme_constant_override("separation", 12)
	scroll.add_child(settings_stack)

	var back_btn := _build_button(
		_text("system.settings.back", "返回"),
		"ghost",
		_on_back_to_menu_pressed
	)
	back_btn.name = "BackToMenuButton"
	back_btn.custom_minimum_size = Vector2(190, 40)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings_stack.add_child(back_btn)
	_first_focus = back_btn

	_add_section_label(settings_stack, _text("settings.section.common", "常用"))
	settings_stack.add_child(_build_toggle_row(
		_text("settings.fullscreen", "全屏显示"),
		"fullscreen"
	))
	settings_stack.add_child(_build_toggle_row(
		_text("settings.tutorial", "教学提示"),
		"show_tutorial"
	))
	settings_stack.add_child(_build_animation_speed_row())

	_add_section_label(settings_stack, _text("settings.section.audio", "声音"))
	settings_stack.add_child(_build_toggle_row(
		_text("settings.music", "音乐"),
		"music_enabled"
	))
	settings_stack.add_child(_build_volume_row(
		_text("settings.master_volume", "主音量"),
		"master"
	))
	settings_stack.add_child(_build_volume_row(
		_text("settings.music_volume", "音乐音量"),
		"music"
	))
	settings_stack.add_child(_build_toggle_row(
		_text("settings.sfx", "音效"),
		"sfx_enabled"
	))
	settings_stack.add_child(_build_volume_row(
		_text("settings.sfx_volume", "音效音量"),
		"sfx"
	))

	var reset_btn := _build_button(
		_text("settings.reset", "恢复默认设置"),
		"ghost",
		_on_reset_settings_pressed
	)
	reset_btn.name = "ResetSettingsButton"
	reset_btn.custom_minimum_size = Vector2(190, 40)
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	settings_stack.add_child(reset_btn)


func _clear_body() -> void:
	_first_focus = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _build_button(label: String, kind: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(420, 48)
	BattleUiTheme.apply_button(button, kind)
	button.pressed.connect(callback)
	return button


func _build_main_menu_button(label: String, callback: Callable, prominent: bool = false) -> Button:
	var button: Button = PixelMenuButtonScript.new()
	button.text = label
	button.custom_minimum_size = Vector2(480, 64 if not prominent else 72)
	button.set("ornament_texture", MenuButtonEdgeTexture)
	button.set("prominent", prominent)
	button.add_theme_font_override("font", BattleUiTheme.pixel_font())
	button.add_theme_font_size_override("font_size", 26 if prominent else 22)
	button.pressed.connect(callback)
	return button


func _apply_page_chrome(settings_page: bool) -> void:
	_title_art.visible = not settings_page
	_title.visible = settings_page
	_separator.visible = settings_page
	if settings_page:
		_panel.custom_minimum_size = Vector2(680, 0)
		var panel_style := BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT)
		panel_style.bg_color = Color(0.025, 0.045, 0.065, 0.98)
		panel_style.border_color = Color(0.22, 0.82, 0.64, 0.52)
		panel_style.shadow_size = 0
		panel_style.content_margin_left = 28
		panel_style.content_margin_right = 28
		panel_style.content_margin_top = 24
		panel_style.content_margin_bottom = 20
		_panel.add_theme_stylebox_override("panel", panel_style)
		return
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _add_section_label(parent: VBoxContainer, label: String) -> void:
	var section := Label.new()
	section.text = label
	section.add_theme_font_size_override("font_size", 16)
	section.add_theme_color_override("font_color", BattleUiTheme.BORDER_ACCENT)
	parent.add_child(section)


func _build_toggle_row(label: String, setting_key: String) -> Control:
	var row := _build_setting_row(label)
	var toggle := CheckButton.new()
	toggle.name = "%sToggle" % setting_key.to_pascal_case()
	toggle.button_pressed = bool(SettingsService.get_value(setting_key))
	toggle.text = _text("settings.on", "开启") if toggle.button_pressed else _text("settings.off", "关闭")
	toggle.custom_minimum_size = Vector2(120, 40)
	toggle.toggled.connect(_on_toggle_changed.bind(setting_key, toggle))
	row.add_child(toggle)
	return row


func _build_animation_speed_row() -> Control:
	var row := _build_setting_row(_text("settings.animation_speed", "战斗动画速度"))
	var selector := OptionButton.new()
	selector.name = "AnimationSpeedSelector"
	selector.custom_minimum_size = Vector2(160, 40)
	var current := SettingsService.get_animation_speed_scale()
	for speed in _ANIMATION_SPEED_OPTIONS:
		selector.add_item("x%.2f" % float(speed))
		if is_equal_approx(float(speed), current):
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(_on_animation_speed_selected.bind(selector))
	row.add_child(selector)
	return row


func _build_volume_row(label: String, track_name: String) -> Control:
	var row := _build_setting_row(label)
	var percent := SettingsService.get_track_volume_percent(track_name)
	var slider := HSlider.new()
	slider.name = "%sVolumeSlider" % track_name.to_pascal_case()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = percent
	slider.custom_minimum_size = Vector2(230, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%%" % percent
	value_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	row.add_child(value_label)
	slider.value_changed.connect(_on_volume_changed.bind(track_name, value_label))
	return row


func _build_setting_row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.add_theme_constant_override("separation", 12)
	var title_label := Label.new()
	title_label.text = label
	title_label.custom_minimum_size = Vector2(210, 0)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	row.add_child(title_label)
	return row


func _on_toggle_changed(enabled: bool, setting_key: String, toggle: CheckButton) -> void:
	SettingsService.set_value(setting_key, enabled)
	toggle.text = _text("settings.on", "开启") if enabled else _text("settings.off", "关闭")


func _on_animation_speed_selected(index: int, selector: OptionButton) -> void:
	if index < 0 or index >= _ANIMATION_SPEED_OPTIONS.size():
		return
	var speed := float(_ANIMATION_SPEED_OPTIONS[index])
	SettingsService.set_animation_speed_scale(speed)
	selector.select(index)
	animation_speed_changed.emit()


func _on_volume_changed(value: float, track_name: String, value_label: Label) -> void:
	var percent := SettingsService.set_track_volume_percent(track_name, int(round(value)))
	value_label.text = "%d%%" % percent


func _on_reset_settings_pressed() -> void:
	SettingsService.reset_to_defaults()
	animation_speed_changed.emit()
	call_deferred("show_settings")


func _on_back_to_menu_pressed() -> void:
	_show_menu_page()
	_focus_first_control()


func _on_save_and_exit_pressed() -> void:
	save_and_exit_requested.emit()


func _focus_first_control() -> void:
	call_deferred("_grab_first_focus")


func _grab_first_focus() -> void:
	if not visible or not is_inside_tree():
		return
	if _first_focus == null or not is_instance_valid(_first_focus):
		return
	if not _first_focus.is_inside_tree():
		return
	_first_focus.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		handle_cancel()
		get_viewport().set_input_as_handled()


func _text(key: String, fallback: String) -> String:
	var translated := TranslationServer.translate(key)
	return fallback if translated == key or translated.is_empty() else translated
