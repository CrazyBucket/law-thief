extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const GameConfirmDialog = preload("res://scripts/ui/game_confirm_dialog.gd")
const EditorConsoleScene = preload("res://scenes/ui/editor_console.tscn")
const MetaConsoleCli = preload("res://scripts/debug/meta_console_cli.gd")
const MAP_SCENE := "res://scenes/map/adventure_map.tscn"
const MENU_ACCENT := Color("#4ce58d")
const ANIMATION_SPEED_OPTIONS := [0.75, 1.0, 1.5, 2.0]

@onready var _content_margin: MarginContainer = $ContentMargin
@onready var _particle_canvas: Control = $ParticleCanvas
@onready var _menu_panel: PanelContainer = $ContentMargin/CenterWrap/MainStack/MenuPanel
@onready var _title_art: TextureRect = $ContentMargin/CenterWrap/MainStack/TitleArt
@onready var _subtitle: Label = $HiddenMeta/Subtitle
@onready var _slot_badge_panel: PanelContainer = $HiddenMeta/BadgePanel
@onready var _slot_badge: Label = $HiddenMeta/BadgePanel/SlotBadge
@onready var _summary_panel: PanelContainer = $HiddenMeta/SummaryPanel
@onready var _summary: Label = $HiddenMeta/SummaryPanel/Summary
@onready var _continue_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/Buttons/ContinueBtn
@onready var _new_run_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/Buttons/NewRunBtn
@onready var _editor_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/EditorBtn
@onready var _codex_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/Buttons/CodexBtn
@onready var _settings_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/Buttons/SettingsBtn
@onready var _exit_btn: Button = $ContentMargin/CenterWrap/MainStack/MenuPanel/VBox/Buttons/ExitBtn
@onready var _footer_hint: Label = $HiddenMeta/FooterHint
@onready var _bottom_info: Label = $BottomInfo
@onready var _menu_music: AudioStreamPlayer = $MenuMusic
@onready var _page_layer: Control = $PageLayer
@onready var _page_panel: PanelContainer = $PageLayer/PageMargin/PageFrame
@onready var _page_title: Label = $PageLayer/PageMargin/PageFrame/VBox/Header/HeaderText/Title
@onready var _page_subtitle: Label = $PageLayer/PageMargin/PageFrame/VBox/Header/HeaderText/Subtitle
@onready var _page_content: VBoxContainer = $PageLayer/PageMargin/PageFrame/VBox/Scroll/Content
@onready var _page_back_btn: Button = $PageLayer/PageMargin/PageFrame/VBox/Header/CloseBtn

var _particles: Array[Dictionary] = []
var _time: float = 0.0
var _title_base_y: float = 0.0
var _navigating: bool = false
var _console_layer: CanvasLayer = null
var _console: Control = null
var _meta_cli: MetaConsoleCli = null
var _exit_confirm_dialog: GameConfirmDialog = null


func _ready() -> void:
	DebugService.log_info("Main scene ready")
	theme = BattleUiTheme.build_theme()
	_create_meta_console()
	_spawn_background_particles()
	_wire_actions()
	_apply_theme()
	_create_exit_confirm_dialog()
	_configure_menu_music()
	_page_layer.visible = false
	_content_margin.visible = true
	if not SaveService.slot_changed.is_connected(_on_slot_changed):
		SaveService.slot_changed.connect(_on_slot_changed)
	AchievementService.refresh_progress_flags()
	_refresh_all()
	_title_base_y = _title_art.position.y
	_play_intro_animation()


func _process(delta: float) -> void:
	_time += delta
	var title_float := sin(_time * 0.82)
	_title_art.rotation = sin(_time * 0.43) * 0.004
	_title_art.position.y = _title_base_y + title_float * 3.0
	_update_particles(delta)
	_particle_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9 and _console != null:
			_console.toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _console != null and _console.is_open():
			_console.close()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and _page_layer.visible:
		_close_page()
		get_viewport().set_input_as_handled()


func _wire_actions() -> void:
	_continue_btn.pressed.connect(_on_continue_pressed)
	_new_run_btn.pressed.connect(_on_new_run_pressed)
	_editor_btn.pressed.connect(_on_editor_pressed)
	_codex_btn.pressed.connect(_show_achievements_page)
	_settings_btn.pressed.connect(_show_settings_page)
	_exit_btn.pressed.connect(_on_exit_pressed)
	_page_back_btn.pressed.connect(_close_page)


func _apply_theme() -> void:
	var menu_style := StyleBoxEmpty.new()
	_menu_panel.add_theme_stylebox_override("panel", menu_style)
	_slot_badge_panel.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(MENU_ACCENT))
	_summary_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(Color("#2fb37a")))
	var page_style := BattleUiTheme.panel_style(MENU_ACCENT.darkened(0.2))
	page_style.bg_color = Color(0.03, 0.05, 0.08, 0.94)
	page_style.border_color = Color(0.2, 0.82, 0.64, 0.35)
	page_style.shadow_size = 0
	page_style.content_margin_left = 28
	page_style.content_margin_right = 28
	page_style.content_margin_top = 24
	page_style.content_margin_bottom = 24
	_page_panel.add_theme_stylebox_override("panel", page_style)
	_slot_badge.add_theme_color_override("font_color", Color.WHITE)
	_summary.add_theme_color_override("font_color", Color("#d8f4de"))
	_footer_hint.add_theme_color_override("font_color", Color("#9fcaad"))
	_bottom_info.add_theme_color_override("font_color", Color("#90b99f"))
	_page_title.add_theme_color_override("font_color", Color("#e8f6ef"))
	_page_subtitle.add_theme_color_override("font_color", Color("#88ae9a"))
	_style_menu_buttons()
	BattleUiTheme.apply_button(_page_back_btn, "ghost")


func _style_menu_buttons() -> void:
	var has_run := RunService.has_saved_run()
	_continue_btn.disabled = not has_run
	_continue_btn.prominent = has_run
	_new_run_btn.prominent = not has_run
	_editor_btn.visible = OS.is_debug_build() and bool(SettingsService.get_value("battle_editor_enabled"))
	_style_menu_button(_continue_btn, true)
	_style_menu_button(_new_run_btn, true)
	_style_menu_button(_settings_btn, false)
	_style_menu_button(_codex_btn, false)
	_style_menu_button(_exit_btn, false)
	_style_menu_button(_editor_btn, false)


func _style_menu_button(button: Button, large: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_font_override("font", BattleUiTheme.pixel_font())
	button.add_theme_font_size_override("font_size", 26 if large else 22)


func _refresh_all() -> void:
	AchievementService.refresh_progress_flags()
	var active_slot: Dictionary = SaveService.peek_slot_summary(SaveService.get_active_slot_id())
	_slot_badge.text = SaveService.get_active_slot_label()
	_summary.text = "%s\n%s\n上次游玩：%s" % [
		str(active_slot.get("status", "空白档案")),
		str(active_slot.get("subtitle", "尚未开始")),
		str(active_slot.get("last_played_text", "未记录")),
	]
	var run_invalid_reason := str(active_slot.get("run_invalid_reason", ""))
	if run_invalid_reason.is_empty():
		_footer_hint.text = ""
	else:
		_footer_hint.text = ""
	_bottom_info.text = ""
	_style_menu_buttons()


func _show_achievements_page() -> void:
	_open_page("成就", "查看当前档案的解锁进度与冒险记录。")
	_add_page_section("成就")
	var achievement_summary: Dictionary = AchievementService.get_summary()
	_add_page_card(
		"进度总览",
		"当前档案",
		[
			"已解锁 %d / %d" % [int(achievement_summary.get("unlocked", 0)), int(achievement_summary.get("total", 0))],
			"累计胜场 %d" % RunHistoryService.get_total_wins(),
			"已见敌人 %d 种" % ProfileService.get_seen_enemy_ids().size(),
		],
		BattleUiTheme.BORDER_ACCENT
	)
	for entry in AchievementService.get_achievement_entries():
		var unlocked := bool(entry.get("unlocked", false))
		_add_page_card(
			str(entry.get("title", "成就")),
			"%s · %s" % ["已解锁" if unlocked else "进行中", str(entry.get("progress_text", "0 / 0"))],
			[str(entry.get("desc", ""))],
			BattleUiTheme.TEXT_GOLD if unlocked else BattleUiTheme.BORDER
		)
	_add_page_section("遗物")
	var relic_ids: Array[String] = DataRegistry.get_relic_ids()
	relic_ids.sort()
	for relic_id in relic_ids:
		var seen := ProfileService.has_seen_relic(relic_id)
		var def: Dictionary = DataRegistry.get_relic_def(relic_id)
		var rarity := DataRegistry.get_relic_rarity(relic_id)
		var relic_name := str(def.get("name", relic_id)) if seen else "未识别遗物"
		var relic_lines: Array = []
		if seen:
			relic_lines.append(_relic_desc(def))
		else:
			relic_lines.append("在冒险中见到后会显示详细效果。")
		_add_page_card(
			relic_name,
			"%s · %s" % [rarity, "已见" if seen else "未见"],
			relic_lines,
			_rarity_color(rarity) if seen else BattleUiTheme.BORDER
		)
	_add_page_section("敌人")
	var seen_enemy_ids: Array[String] = ProfileService.get_seen_enemy_ids()
	var killed_enemy_ids: Array[String] = ProfileService.get_killed_enemy_ids()
	var enemy_ids: Array[String] = DataRegistry.get_unit_def_ids()
	enemy_ids.sort()
	for unit_id in enemy_ids:
		if unit_id == "unit_player":
			continue
		var seen_enemy := unit_id in seen_enemy_ids
		var killed_enemy := unit_id in killed_enemy_ids
		var enemy_def: Dictionary = DataRegistry.get_unit_def(unit_id)
		var enemy_lines: Array = []
		if seen_enemy:
			enemy_lines.append("生命 %d · 攻击 %d · 速度 %d" % [int(enemy_def.get("max_hp", 0)), int(enemy_def.get("base_attack", 0)), int(enemy_def.get("speed", 0))])
			enemy_lines.append("状态：%s" % ("已击败" if killed_enemy else "已发现"))
		else:
			enemy_lines.append("尚未遭遇该敌人。")
		var enemy_state := "未发现"
		if seen_enemy:
			enemy_state = "已击败" if killed_enemy else "已发现"
		_add_page_card(
			DataRegistry.get_unit_display_name(unit_id) if seen_enemy else "未知敌人",
			enemy_state,
			enemy_lines,
			BattleUiTheme.PHASE_ENEMY if seen_enemy else BattleUiTheme.BORDER
		)
	_add_page_section("宝石")
	var gem_ids: Array[String] = DataRegistry.get_gem_ids()
	gem_ids.sort()
	for gem_id in gem_ids:
		_add_page_card(
			DataRegistry.get_gem_display_name(gem_id),
			DataRegistry.get_gem_symbol(gem_id),
			[
				"稀有度：%s" % DataRegistry.get_gem_rarity_label(gem_id),
			],
			DataRegistry.get_gem_color(gem_id)
		)
	_add_page_section("遭遇战")
	var encounter_ids_raw: Array = DataRegistry.get_encounter_ids()
	var encounter_ids: Array[String] = []
	for encounter_id in encounter_ids_raw:
		encounter_ids.append(str(encounter_id))
	encounter_ids.sort()
	for index in range(encounter_ids.size()):
		var encounter_id := encounter_ids[index]
		var win_count := RunHistoryService.get_encounter_win_count(encounter_id)
		_add_page_card(
			"遭遇战 %02d" % (index + 1),
			"胜利 %d 次" % win_count,
			[
				"已通关" if win_count > 0 else "尚未通关",
			],
			BattleUiTheme.TEXT_GOLD if win_count > 0 else BattleUiTheme.BORDER
		)


func _show_settings_page() -> void:
	_open_page("设置", "调整显示、提示、演出节奏与声音。")
	_add_settings_group("常用", [
		_build_toggle_setting_row("全屏显示", "窗口 / 全屏", "fullscreen", BattleUiTheme.PHASE_PLAYER),
		_build_toggle_setting_row("教学提示", "战斗引导", "show_tutorial", BattleUiTheme.TEXT_GOLD),
		_build_animation_speed_row(),
	])
	_add_settings_group("声音", [
		_build_toggle_setting_row("音乐", "背景音乐", "music_enabled", BattleUiTheme.BORDER_ACCENT),
		_build_volume_setting_row("主音量", "整体声音", "master", BattleUiTheme.TEXT_GOLD),
		_build_volume_setting_row("音乐音量", "背景音乐", "music", BattleUiTheme.BORDER_ACCENT, "music_enabled"),
		_build_toggle_setting_row("音效", "交互反馈", "sfx_enabled", BattleUiTheme.PHASE_PLAYER),
		_build_volume_setting_row("音效音量", "交互反馈", "sfx", BattleUiTheme.PHASE_PLAYER, "sfx_enabled"),
	])
	_add_settings_group("维护", [
		_build_reset_setting_row(),
	])


func _open_page(title: String, subtitle: String) -> void:
	_clear_page_content()
	_page_title.text = title
	_page_subtitle.text = subtitle
	_content_margin.visible = false
	_page_layer.visible = true
	_page_layer.modulate.a = 1.0


func _close_page() -> void:
	if not _page_layer.visible:
		return
	_page_layer.visible = false
	_content_margin.visible = true
	_clear_page_content()


func _clear_page_content() -> void:
	for child in _page_content.get_children():
		child.queue_free()


func _add_page_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#d9f5e5"))
	label.add_theme_constant_override("outline_size", 0)
	_page_content.add_child(label)


func _add_page_card(title: String, subtitle: String, lines: Array, accent: Color, actions: Array = []) -> void:
	_page_content.add_child(_build_card(title, subtitle, lines, accent, actions))


func _add_settings_group(title: String, rows: Array) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.12))
	style.bg_color = Color(0.035, 0.055, 0.075, 0.92)
	style.border_color = Color(0.18, 0.46, 0.38, 0.48)
	style.shadow_size = 0
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#d9f5e5"))
	stack.add_child(label)

	for i in range(rows.size()):
		if i > 0:
			stack.add_child(_build_setting_separator())
		stack.add_child(rows[i])
	_page_content.add_child(panel)


func _build_toggle_setting_row(title: String, subtitle: String, key: String, accent: Color) -> Control:
	var enabled := bool(SettingsService.get_value(key))
	var row_data := _build_setting_row_shell(
		title,
		subtitle,
		"当前：%s" % ("开启" if enabled else "关闭"),
		accent
	)
	var control_box: HBoxContainer = row_data["control_box"]
	var toggle := CheckButton.new()
	toggle.text = "开启" if enabled else "关闭"
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(132, 42)
	_style_check_button(toggle, accent)
	toggle.toggled.connect(_on_toggle_setting_changed.bind(key))
	control_box.add_child(toggle)
	return row_data["row"]


func _build_animation_speed_row() -> Control:
	var current := SettingsService.get_animation_speed_scale()
	var row_data := _build_setting_row_shell(
		"战斗动画速度",
		"演出节奏",
		"当前倍率：x%.2f" % current,
		BattleUiTheme.BORDER_ACCENT
	)
	var control_box: HBoxContainer = row_data["control_box"]
	control_box.custom_minimum_size = Vector2(300, 0)
	for speed in ANIMATION_SPEED_OPTIONS:
		var speed_value := float(speed)
		var button := _build_action_button(
			_action(
				"x%.2f" % speed_value,
				"end",
				_set_animation_speed.bind(speed_value),
				false,
				is_equal_approx(current, speed_value)
			),
			Vector2(66, 40)
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control_box.add_child(button)
	return row_data["row"]


func _build_volume_setting_row(
	title: String,
	subtitle: String,
	track_name: String,
	accent: Color,
	enabled_setting: String = ""
) -> Control:
	var percent := SettingsService.get_track_volume_percent(track_name)
	var row_data := _build_setting_row_shell(
		title,
		subtitle,
		"当前：%d%%" % percent,
		accent
	)
	var status_label: Label = row_data["status_label"]
	var control_box: HBoxContainer = row_data["control_box"]
	control_box.custom_minimum_size = Vector2(300, 0)
	var enabled := enabled_setting.is_empty() or bool(SettingsService.get_value(enabled_setting))
	if not enabled:
		row_data["row"].modulate = Color(1, 1, 1, 0.62)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%%" % percent
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color("#e4efe9"))
	control_box.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = percent
	slider.editable = enabled
	slider.custom_minimum_size = Vector2(220, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_volume_slider(slider, accent)
	control_box.add_child(slider)
	slider.value_changed.connect(_on_volume_slider_changed.bind(track_name, status_label, value_label))
	return row_data["row"]


func _build_reset_setting_row() -> Control:
	var row_data := _build_setting_row_shell(
		"恢复默认设置",
		"回到推荐配置",
		"不会影响存档与成就",
		BattleUiTheme.BORDER
	)
	var control_box: HBoxContainer = row_data["control_box"]
	var button := _build_action_button(_action("恢复默认", "ghost", _reset_settings), Vector2(132, 40))
	control_box.add_child(button)
	return row_data["row"]


func _build_setting_row_shell(title: String, subtitle: String, status: String, accent: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 66)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 18)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", accent if accent != BattleUiTheme.BORDER else Color("#edf4ef"))
	info.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color("#8ba99c"))
	info.add_child(subtitle_label)

	var status_label := Label.new()
	status_label.text = status
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#d6e2dc"))
	info.add_child(status_label)

	var control_box := HBoxContainer.new()
	control_box.custom_minimum_size = Vector2(240, 0)
	control_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	control_box.alignment = BoxContainer.ALIGNMENT_CENTER
	control_box.add_theme_constant_override("separation", 10)
	row.add_child(control_box)

	return {
		"row": row,
		"status_label": status_label,
		"control_box": control_box,
	}


func _build_setting_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 0)
	separator.modulate = Color(0.35, 0.75, 0.62, 0.22)
	return separator


func _build_card(title: String, subtitle: String, lines: Array, accent: Color, actions: Array = []) -> PanelContainer:
	var panel := PanelContainer.new()
	var card_style := BattleUiTheme.panel_style(accent)
	card_style.bg_color = Color(0.05, 0.08, 0.11, 0.9)
	card_style.border_color = accent.darkened(0.18)
	card_style.shadow_size = 0
	card_style.content_margin_left = 18
	card_style.content_margin_right = 18
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", card_style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", accent if accent != BattleUiTheme.BORDER else Color("#e9f3ee"))
	vbox.add_child(title_label)
	if not subtitle.is_empty():
		var subtitle_label := Label.new()
		subtitle_label.text = subtitle
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle_label.add_theme_font_size_override("font_size", 13)
		subtitle_label.add_theme_color_override("font_color", Color("#82a693"))
		vbox.add_child(subtitle_label)
	for item in lines:
		var body_label := Label.new()
		body_label.text = str(item)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.add_theme_font_size_override("font_size", 13)
		body_label.add_theme_color_override("font_color", Color("#c9d8d1"))
		vbox.add_child(body_label)
	if not actions.is_empty():
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 10)
		vbox.add_child(action_row)
		for action in actions:
			var button := _build_action_button(action, Vector2(0, 40))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action_row.add_child(button)
	return panel


func _build_action_button(action: Dictionary, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = str(action.get("text", "操作"))
	button.custom_minimum_size = min_size
	button.disabled = bool(action.get("disabled", false))
	BattleUiTheme.apply_button(button, str(action.get("kind", "ghost")), bool(action.get("active", false)))
	var raw_callback: Variant = action.get("call", Callable())
	if raw_callback is Callable:
		var callback: Callable = raw_callback
		if callback.is_valid() and not button.disabled:
			button.pressed.connect(callback)
	return button


func _style_check_button(button: CheckButton, accent: Color) -> void:
	button.add_theme_font_override("font", BattleUiTheme.pixel_font())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("#d9e7e0"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", BattleUiTheme.TEXT_MUTED)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	button.modulate = Color.WHITE if button.button_pressed else Color(0.78, 0.86, 0.82)
	button.tooltip_text = "开启" if button.button_pressed else "关闭"
	var focus := BattleUiTheme.button_style("ghost")
	focus.border_color = accent.lightened(0.12)
	button.add_theme_stylebox_override("focus", focus)


func _action(text: String, kind: String, callback: Callable, disabled: bool = false, active: bool = false) -> Dictionary:
	return {
		"text": text,
		"kind": kind,
		"call": callback,
		"disabled": disabled,
		"active": active,
	}


func _relic_desc(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "效果待补充。"


func _rarity_color(rarity: String) -> Color:
	if rarity.is_empty():
		return BattleUiTheme.BORDER_ACCENT
	return UiPalette.rarity_color(rarity)


func _on_toggle_setting_changed(enabled: bool, key: String) -> void:
	_set_setting_value(key, enabled)


func _set_setting_value(key: String, value: Variant) -> void:
	SettingsService.set_value(key, value)
	_refresh_all()
	_show_settings_page()


func _set_animation_speed(speed_scale: float) -> void:
	SettingsService.set_animation_speed_scale(speed_scale)
	_refresh_all()
	_show_settings_page()


func _reset_settings() -> void:
	SettingsService.reset_to_defaults()
	_configure_menu_music()
	_refresh_all()
	_show_settings_page()


func _on_volume_slider_changed(
	value: float,
	track_name: String,
	status_label: Label,
	value_label: Label
) -> void:
	var percent := SettingsService.set_track_volume_percent(track_name, int(round(value)))
	status_label.text = "当前：%d%%" % percent
	value_label.text = "%d%%" % percent


func _on_continue_pressed() -> void:
	if _navigating:
		return
	_close_page()
	if not AdventureService.resume_loaded_run():
		return
	_transition_to_scene(GameService.continue_scene_for_active_run())


func _on_new_run_pressed() -> void:
	if _navigating:
		return
	_close_page()
	AdventureService.start_new_run()
	_transition_to_scene(MAP_SCENE)


func _on_editor_pressed() -> void:
	if _navigating:
		return
	_close_page()
	GameService.start_editor_battle("procedural_normal")
	_transition_to_scene("res://scenes/battle/battle_scene.tscn")


func _on_exit_pressed() -> void:
	if _exit_confirm_dialog == null:
		_confirm_exit_game()
		return
	_exit_confirm_dialog.popup_centered(Vector2i(420, 180))


func _create_exit_confirm_dialog() -> void:
	if _exit_confirm_dialog != null:
		return
	_exit_confirm_dialog = GameConfirmDialog.new()
	_exit_confirm_dialog.configure(
		tr("menu.exit.confirm.title"),
		tr("menu.exit.confirm.body"),
		tr("menu.exit.confirm.ok"),
		tr("menu.exit.confirm.cancel")
	)
	_exit_confirm_dialog.confirmed.connect(_confirm_exit_game)
	add_child(_exit_confirm_dialog)


func _confirm_exit_game() -> void:
	if RunService.is_run_active():
		RunService.save_run()
	get_tree().quit()


func _on_slot_changed(_slot_id: int) -> void:
	_refresh_all()


func _configure_menu_music() -> void:
	if _menu_music == null or _menu_music.stream == null:
		return
	if _menu_music.stream is AudioStreamWAV:
		(_menu_music.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif _menu_music.stream is AudioStreamOggVorbis:
		(_menu_music.stream as AudioStreamOggVorbis).loop = true
	if not _menu_music.finished.is_connected(_on_menu_music_finished):
		_menu_music.finished.connect(_on_menu_music_finished)
	if bool(SettingsService.get_value("music_enabled")) and not _menu_music.playing:
		_menu_music.play()


func _on_menu_music_finished() -> void:
	if _menu_music == null:
		return
	if bool(SettingsService.get_value("music_enabled")):
		_menu_music.play()


func _transition_to_scene(scene_path: String) -> void:
	_navigating = true
	var style := TransitionManager.Style.SILHOUETTE if scene_path.ends_with("/battle_scene.tscn") else TransitionManager.Style.CHECKERBOARD
	TransitionManager.change_scene(
		scene_path, style, 0.38,
		{"columns": 10, "cover_color": Color.BLACK}, TransitionManager.Direction.IN if style == TransitionManager.Style.SILHOUETTE else TransitionManager.Direction.OUT
	)


func _spawn_background_particles() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(56):
		var is_mote := i < 40
		_particles.append({
			"pos": Vector2(randf() * viewport_size.x, randf() * viewport_size.y),
			"vel": Vector2(randf_range(-14.0, 14.0), randf_range(-38.0, -14.0) if is_mote else randf_range(-17.0, -7.0)),
			"size": randf_range(1.8, 4.2) if is_mote else randf_range(5.0, 10.0),
			"alpha": randf_range(0.30, 0.62) if is_mote else randf_range(0.10, 0.22),
			"color_idx": randi() % 4,
			"phase": randf_range(0.0, TAU),
			"mote": is_mote,
		})
	if not _particle_canvas.draw.is_connected(_draw_particles):
		_particle_canvas.draw.connect(_draw_particles)


func _update_particles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for particle in _particles:
		particle["pos"] = particle["pos"] + particle["vel"] * delta
		particle["pos"].x += sin(_time * 0.7 + float(particle["phase"])) * 8.0 * delta
		if particle["pos"].y < -10.0 or particle["pos"].x < -10.0 or particle["pos"].x > viewport_size.x + 10.0:
			particle["pos"] = Vector2(randf() * viewport_size.x, viewport_size.y + randf_range(5.0, 22.0))
			particle["vel"].x = randf_range(-12.0, 12.0)


func _draw_particles() -> void:
	var colors: Array[Color] = [
		UiPalette.BRAND_RED,
		UiPalette.SLOT_BLUE,
		UiPalette.CRIT_GOLD,
		UiPalette.RARITY_UNCOMMON,
	]
	for particle in _particles:
		var color: Color = colors[int(particle["color_idx"])]
		color.a = float(particle["alpha"])
		var size := float(particle["size"])
		var pos: Vector2 = particle["pos"]
		var shimmer := 0.72 + sin(_time * 1.4 + float(particle["phase"])) * 0.28
		color.a *= shimmer
		if not bool(particle["mote"]):
			for glow_step in range(3, 0, -1):
				var glow_color := color
				glow_color.a *= 0.055 * float(4 - glow_step)
				_particle_canvas.draw_circle(pos, size * float(glow_step), glow_color)
			continue
		var points := PackedVector2Array([
			pos + Vector2(0, -size * 1.7),
			pos + Vector2(size * 0.6, 0),
			pos + Vector2(0, size * 1.7),
			pos + Vector2(-size * 0.6, 0),
		])
		_particle_canvas.draw_colored_polygon(points, color)
		var core := color.lightened(0.35)
		core.a = min(0.9, color.a * 1.45)
		_particle_canvas.draw_circle(pos, max(0.8, size * 0.32), core)


func _create_meta_console() -> void:
	if not OS.is_debug_build():
		return
	_meta_cli = MetaConsoleCli.new()
	_console_layer = CanvasLayer.new()
	_console_layer.layer = 64
	add_child(_console_layer)
	_console = EditorConsoleScene.instantiate()
	_console.command_submitted.connect(_on_meta_console_submitted)
	_console_layer.add_child(_console)
	_console.append_log("存档调试（F9）", "#6bdc8e")
	_console.append_log("unlock all — 解锁当前档案全部未解锁标记", "#7a9a82")


func _on_meta_console_submitted(command: String) -> void:
	_console.append_log("> %s" % command, "#ffd166")
	var result: Dictionary = _meta_cli.run(command)
	if result.get("ok", false):
		_console.append_log(str(result.get("message", "ok")), "#8fd4a8")
		for line in result.get("lines", []):
			_console.append_log("- %s" % str(line), "#c8cad4")
		_refresh_all()
	else:
		_console.append_log(str(result.get("reason", "failed")), "#ff8a80")
	_console.clear_input()


func _play_intro_animation() -> void:
	_title_art.pivot_offset = _title_art.size * 0.5
	_title_art.modulate.a = 0.0
	_title_art.scale = Vector2(0.94, 0.94)
	_menu_panel.modulate.a = 0.0
	_menu_panel.scale = Vector2(0.97, 0.97)
	_bottom_info.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_title_art, "modulate:a", 1.0, 0.38)
	tween.tween_property(_title_art, "scale", Vector2.ONE, 0.34)
	tween.tween_property(_menu_panel, "modulate:a", 1.0, 0.32).set_delay(0.08)
	tween.tween_property(_menu_panel, "scale", Vector2.ONE, 0.28).set_delay(0.08)
	tween.tween_property(_bottom_info, "modulate:a", 1.0, 0.3).set_delay(0.08)


func _style_volume_slider(slider: HSlider, accent: Color) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color("#162027")
	groove.border_color = accent.darkened(0.3)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(0)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent.darkened(0.36)
	fill.border_color = accent.lightened(0.12)
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
