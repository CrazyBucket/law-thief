extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const EditorConsoleScene = preload("res://scenes/ui/editor_console.tscn")
const MetaConsoleCli = preload("res://scripts/debug/meta_console_cli.gd")
const MAP_SCENE := "res://scenes/map/adventure_map.tscn"

@onready var _particle_canvas: Control = $ParticleCanvas
@onready var _menu_panel: PanelContainer = $CenterWrap/MenuPanel
@onready var _title: Label = $CenterWrap/MenuPanel/VBox/Title
@onready var _subtitle: Label = $CenterWrap/MenuPanel/VBox/Subtitle
@onready var _slot_badge_panel: PanelContainer = $CenterWrap/MenuPanel/VBox/BadgePanel
@onready var _slot_badge: Label = $CenterWrap/MenuPanel/VBox/BadgePanel/SlotBadge
@onready var _summary_panel: PanelContainer = $CenterWrap/MenuPanel/VBox/SummaryPanel
@onready var _summary: Label = $CenterWrap/MenuPanel/VBox/SummaryPanel/Summary
@onready var _continue_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/ContinueBtn
@onready var _new_run_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/NewRunBtn
@onready var _editor_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/EditorBtn
@onready var _save_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/SaveBtn
@onready var _achievement_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/AchievementBtn
@onready var _codex_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/CodexBtn
@onready var _settings_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/SettingsBtn
@onready var _exit_btn: Button = $CenterWrap/MenuPanel/VBox/Buttons/ExitBtn
@onready var _footer_hint: Label = $CenterWrap/MenuPanel/VBox/FooterHint
@onready var _bottom_info: Label = $BottomInfo
@onready var _modal_layer: Control = $ModalLayer
@onready var _modal_backdrop: ColorRect = $ModalLayer/Backdrop
@onready var _modal_panel: PanelContainer = $ModalLayer/Dialog
@onready var _modal_title: Label = $ModalLayer/Dialog/VBox/Header/Title
@onready var _modal_subtitle: Label = $ModalLayer/Dialog/VBox/Header/Subtitle
@onready var _modal_content: VBoxContainer = $ModalLayer/Dialog/VBox/Scroll/Content
@onready var _modal_close_btn: Button = $ModalLayer/Dialog/VBox/Footer/CloseBtn

var _particles: Array[Dictionary] = []
var _time: float = 0.0
var _title_glow: float = 0.0
var _navigating: bool = false
var _console_layer: CanvasLayer = null
var _console: Control = null
var _meta_cli: MetaConsoleCli = null


func _ready() -> void:
	DebugService.log_info("Main scene ready")
	_create_meta_console()
	_spawn_background_particles()
	_wire_actions()
	_apply_theme()
	_modal_layer.visible = false
	if not SaveService.slot_changed.is_connected(_on_slot_changed):
		SaveService.slot_changed.connect(_on_slot_changed)
	AchievementService.refresh_progress_flags()
	_refresh_all()
	_play_intro_animation()


func _process(delta: float) -> void:
	_time += delta
	_title_glow = (sin(_time * 1.35) + 1.0) * 0.5
	var base_color := Color(0.92, 0.28, 0.38)
	var glow_color := Color(1.0, 0.62, 0.44)
	_title.add_theme_color_override("font_color", base_color.lerp(glow_color, _title_glow * 0.35))
	_subtitle.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82, 0.68 + _title_glow * 0.18))
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
	if event.is_action_pressed("ui_cancel") and _modal_layer.visible:
		_close_modal()
		get_viewport().set_input_as_handled()


func _wire_actions() -> void:
	_continue_btn.pressed.connect(_on_continue_pressed)
	_new_run_btn.pressed.connect(_on_new_run_pressed)
	_editor_btn.pressed.connect(_on_editor_pressed)
	_save_btn.pressed.connect(_show_save_popup)
	_achievement_btn.pressed.connect(_show_achievements_popup)
	_codex_btn.pressed.connect(_show_codex_popup)
	_settings_btn.pressed.connect(_show_settings_popup)
	_exit_btn.pressed.connect(_on_exit_pressed)
	_modal_close_btn.pressed.connect(_close_modal)
	_modal_backdrop.gui_input.connect(_on_modal_backdrop_input)


func _apply_theme() -> void:
	_menu_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.08)))
	_slot_badge_panel.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(BattleUiTheme.TEXT_GOLD))
	_summary_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER))
	_modal_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT))
	_title.add_theme_color_override("font_color", Color(0.94, 0.36, 0.4))
	_subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_slot_badge.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_summary.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_footer_hint.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_bottom_info.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_modal_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_modal_subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_style_menu_buttons()
	BattleUiTheme.apply_button(_modal_close_btn, "ghost")


func _style_menu_buttons() -> void:
	var has_run := RunService.has_saved_run()
	_continue_btn.disabled = not has_run
	BattleUiTheme.apply_button(_continue_btn, "end")
	BattleUiTheme.apply_button(_new_run_btn, "end")
	_editor_btn.visible = OS.is_debug_build() and bool(SettingsService.get_value("battle_editor_enabled"))
	BattleUiTheme.apply_button(_editor_btn, "ghost")
	BattleUiTheme.apply_button(_save_btn, "ghost")
	BattleUiTheme.apply_button(_achievement_btn, "ghost")
	BattleUiTheme.apply_button(_codex_btn, "ghost")
	BattleUiTheme.apply_button(_settings_btn, "ghost")
	BattleUiTheme.apply_button(_exit_btn, "ghost")


func _refresh_all() -> void:
	AchievementService.refresh_progress_flags()
	var active_slot: Dictionary = SaveService.peek_slot_summary(SaveService.get_active_slot_id())
	var achievement_summary: Dictionary = AchievementService.get_summary()
	var profile_summary: Dictionary = ProfileService.get_summary()
	_slot_badge.text = SaveService.get_active_slot_label()
	_summary.text = "%s\n%s\n上次游玩：%s" % [
		str(active_slot.get("status", "空白档案")),
		str(active_slot.get("subtitle", "尚未开始")),
		str(active_slot.get("last_played_text", "未记录")),
	]
	var run_invalid_reason := str(active_slot.get("run_invalid_reason", ""))
	if run_invalid_reason.is_empty():
		_footer_hint.text = "开始/继续会切换到流程场景；存档、成就、图鉴、设置都通过弹窗查看。"
	else:
		_footer_hint.text = "当前进行中的这一局已失效：%s" % run_invalid_reason
	_bottom_info.text = "%s  ·  成就 %d/%d  ·  遗物 %d  ·  敌人 %d" % [
		SaveService.get_active_slot_label(),
		int(achievement_summary.get("unlocked", 0)),
		int(achievement_summary.get("total", 0)),
		int(profile_summary.get("seen_relic_count", 0)),
		int(profile_summary.get("seen_enemy_count", 0)),
	]
	_style_menu_buttons()


func _show_save_popup() -> void:
	_open_modal("存档切换", "切换当前档案，继续游戏和新开局都会以当前档案为准。")
	for summary in SaveService.get_slot_summaries():
		var slot_id := int(summary.get("slot_id", 1))
		var actions: Array = []
		if bool(summary.get("is_active", false)):
			actions.append(_action("当前档案", "ghost", Callable(), true))
		else:
			actions.append(_action("设为当前", "end", _on_slot_activate.bind(slot_id)))
		if bool(summary.get("has_run", false)):
			actions.append(_action("继续", "end", _on_continue_slot.bind(slot_id)))
		else:
			actions.append(_action("新开局", "ghost", _on_new_run_slot.bind(slot_id)))
		if bool(summary.get("has_data", false)):
			actions.append(_action("清空", "ghost", _show_clear_slot_confirm.bind(slot_id)))
		var lines := [
			"状态：%s" % str(summary.get("status", "空白档案")),
			"摘要：%s" % str(summary.get("subtitle", "尚未开始")),
			"战斗记录：%d，胜场：%d" % [int(summary.get("history_count", 0)), int(summary.get("win_count", 0))],
			"已见遗物：%d，局外标记：%d" % [int(summary.get("seen_relic_count", 0)), int(summary.get("flag_count", 0))],
			"上次游玩：%s" % str(summary.get("last_played_text", "未记录")),
		]
		_add_modal_card(
			str(summary.get("label", "档案")),
			str(summary.get("status", "空白档案")),
			lines,
			BattleUiTheme.TEXT_GOLD if bool(summary.get("is_active", false)) else BattleUiTheme.BORDER,
			actions
		)


func _show_clear_slot_confirm(slot_id: int) -> void:
	_open_modal("清空档案", "这个操作只会清空选中档案的数据，不影响其他档案。")
	var summary: Dictionary = SaveService.peek_slot_summary(slot_id)
	_add_modal_card(
		str(summary.get("label", "档案")),
		"确认要清空这个档案吗？",
		[
			"当前状态：%s" % str(summary.get("status", "空白档案")),
			"上次游玩：%s" % str(summary.get("last_played_text", "未记录")),
		],
		BattleUiTheme.PHASE_ENEMY,
		[
			_action("返回", "ghost", _show_save_popup),
			_action("确认清空", "end", _on_clear_slot_confirmed.bind(slot_id)),
		]
	)


func _show_achievements_popup() -> void:
	_open_modal("成就", "这里显示当前档案的局外目标进度。")
	var summary: Dictionary = AchievementService.get_summary()
	_add_modal_card(
		"总览",
		"当前档案的完成情况。",
		[
			"已解锁：%d / %d" % [int(summary.get("unlocked", 0)), int(summary.get("total", 0))],
			"累计胜场：%d" % RunHistoryService.get_total_wins(),
			"怪物图鉴：%d 种" % ProfileService.get_seen_enemy_ids().size(),
		],
		BattleUiTheme.BORDER_ACCENT
	)
	for entry in AchievementService.get_achievement_entries():
		var unlocked := bool(entry.get("unlocked", false))
		_add_modal_card(
			str(entry.get("title", "成就")),
			"%s · %s" % ["已解锁" if unlocked else "进行中", str(entry.get("progress_text", "0 / 0"))],
			[
				str(entry.get("desc", "")),
			],
			BattleUiTheme.TEXT_GOLD if unlocked else BattleUiTheme.BORDER
		)


func _show_codex_popup() -> void:
	_open_modal("图鉴", "未见内容保留占位，已见内容会显示简要信息。")
	_add_modal_section("遗物")
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
		_add_modal_card(
			relic_name,
			"%s · %s" % [rarity, "已见" if seen else "未见"],
			relic_lines,
			_rarity_color(rarity) if seen else BattleUiTheme.BORDER
		)
	_add_modal_section("敌人")
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
		_add_modal_card(
			DataRegistry.get_unit_display_name(unit_id) if seen_enemy else "未知敌人",
			unit_id,
			enemy_lines,
			BattleUiTheme.PHASE_ENEMY if seen_enemy else BattleUiTheme.BORDER
		)
	_add_modal_section("宝石")
	var gem_ids: Array[String] = DataRegistry.get_gem_ids()
	gem_ids.sort()
	for gem_id in gem_ids:
		_add_modal_card(
			DataRegistry.get_gem_display_name(gem_id),
			DataRegistry.get_gem_symbol(gem_id),
			[
				"稀有度：%s" % DataRegistry.get_gem_rarity_label(gem_id),
				"标识：%s" % gem_id,
			],
			DataRegistry.get_gem_color(gem_id)
		)
	_add_modal_section("遭遇战")
	var encounter_ids_raw: Array = DataRegistry.get_encounter_ids()
	var encounter_ids: Array[String] = []
	for encounter_id in encounter_ids_raw:
		encounter_ids.append(str(encounter_id))
	encounter_ids.sort()
	for encounter_id in encounter_ids:
		var win_count := RunHistoryService.get_encounter_win_count(encounter_id)
		_add_modal_card(
			encounter_id,
			"胜利 %d 次" % win_count,
			[
				"已通关" if win_count > 0 else "尚未通关",
			],
			BattleUiTheme.TEXT_GOLD if win_count > 0 else BattleUiTheme.BORDER
		)


func _show_settings_popup() -> void:
	_open_modal("设置", "全局设置通过服务变量直接驱动，并会立即持久化。")
	_add_modal_card(
		"显示模式",
		"切换窗口与全屏。",
		[
			"当前：%s" % ("全屏" if bool(SettingsService.get_value("fullscreen")) else "窗口"),
		],
		BattleUiTheme.PHASE_PLAYER,
		[
			_action("切换", "end", _toggle_setting.bind("fullscreen")),
		]
	)
	_add_modal_card(
		"教学提示",
		"控制战斗教学弹层是否显示。",
		[
			"当前：%s" % ("开启" if bool(SettingsService.get_value("show_tutorial")) else "关闭"),
		],
		BattleUiTheme.TEXT_GOLD,
		[
			_action("切换", "end", _toggle_setting.bind("show_tutorial")),
		]
	)
	_add_modal_card(
		"战斗动画速度",
		"直接影响战斗演出播放节奏。",
		[
			"当前倍率：x%.2f" % SettingsService.get_animation_speed_scale(),
		],
		BattleUiTheme.BORDER_ACCENT,
		[
			_action("减速", "ghost", _cycle_anim_speed.bind(-1)),
			_action("加速", "end", _cycle_anim_speed.bind(1)),
		]
	)
	_add_modal_card(
		"音乐开关",
		"为后续音频总线预留控制位。",
		[
			"当前：%s" % ("开启" if bool(SettingsService.get_value("music_enabled")) else "关闭"),
		],
		BattleUiTheme.BORDER,
		[
			_action("切换", "ghost", _toggle_setting.bind("music_enabled")),
		]
	)
	_add_modal_card(
		"音效开关",
		"为后续命中和交互反馈预留控制位。",
		[
			"当前：%s" % ("开启" if bool(SettingsService.get_value("sfx_enabled")) else "关闭"),
		],
		BattleUiTheme.BORDER,
		[
			_action("切换", "ghost", _toggle_setting.bind("sfx_enabled")),
		]
	)


func _open_modal(title: String, subtitle: String) -> void:
	_clear_modal_content()
	_modal_title.text = title
	_modal_subtitle.text = subtitle
	_modal_layer.visible = true
	_modal_layer.modulate.a = 1.0


func _close_modal() -> void:
	if not _modal_layer.visible:
		return
	_modal_layer.visible = false
	_clear_modal_content()


func _clear_modal_content() -> void:
	for child in _modal_content.get_children():
		child.queue_free()


func _add_modal_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_modal_content.add_child(label)


func _add_modal_card(title: String, subtitle: String, lines: Array, accent: Color, actions: Array = []) -> void:
	_modal_content.add_child(_build_card(title, subtitle, lines, accent, actions))


func _build_card(title: String, subtitle: String, lines: Array, accent: Color, actions: Array = []) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", accent if accent != BattleUiTheme.BORDER else BattleUiTheme.TEXT)
	vbox.add_child(title_label)
	if not subtitle.is_empty():
		var subtitle_label := Label.new()
		subtitle_label.text = subtitle
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle_label.add_theme_font_size_override("font_size", 12)
		subtitle_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
		vbox.add_child(subtitle_label)
	for item in lines:
		var body_label := Label.new()
		body_label.text = str(item)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.add_theme_font_size_override("font_size", 13)
		body_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		vbox.add_child(body_label)
	if not actions.is_empty():
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 10)
		vbox.add_child(action_row)
		for action in actions:
			var button := Button.new()
			button.text = str(action.get("text", "操作"))
			button.custom_minimum_size = Vector2(0, 40)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = bool(action.get("disabled", false))
			BattleUiTheme.apply_button(button, str(action.get("kind", "ghost")))
			var raw_callback: Variant = action.get("call", Callable())
			if raw_callback is Callable:
				var callback: Callable = raw_callback
				if callback.is_valid() and not button.disabled:
					button.pressed.connect(callback)
			action_row.add_child(button)
	return panel


func _action(text: String, kind: String, callback: Callable, disabled: bool = false) -> Dictionary:
	return {
		"text": text,
		"kind": kind,
		"call": callback,
		"disabled": disabled,
	}


func _relic_desc(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "效果待补充。"


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color("#c8cad4")
		"rare":
			return Color("#6ec6f5")
		"epic":
			return Color("#c77dff")
		"legendary":
			return Color("#ffd166")
		"boss":
			return Color("#ff6b6b")
		_:
			return BattleUiTheme.BORDER_ACCENT


func _toggle_setting(key: String) -> void:
	SettingsService.toggle_bool(key)
	_refresh_all()
	_show_settings_popup()


func _cycle_anim_speed(step: int) -> void:
	SettingsService.cycle_animation_speed(step)
	_refresh_all()
	_show_settings_popup()


func _on_continue_pressed() -> void:
	if _navigating:
		return
	_close_modal()
	if not AdventureService.resume_loaded_run():
		return
	_fade_to_scene(MAP_SCENE)


func _on_new_run_pressed() -> void:
	if _navigating:
		return
	_close_modal()
	AdventureService.start_new_run()
	_fade_to_scene(MAP_SCENE)


func _on_editor_pressed() -> void:
	if _navigating:
		return
	_close_modal()
	GameService.start_editor_battle("tutorial_001")
	_fade_to_scene("res://scenes/battle/battle_scene.tscn")


func _on_slot_activate(slot_id: int) -> void:
	SaveService.set_active_slot(slot_id)
	_refresh_all()
	_show_save_popup()


func _on_continue_slot(slot_id: int) -> void:
	SaveService.set_active_slot(slot_id)
	_on_continue_pressed()


func _on_new_run_slot(slot_id: int) -> void:
	SaveService.set_active_slot(slot_id)
	_on_new_run_pressed()


func _on_clear_slot_confirmed(slot_id: int) -> void:
	SaveService.clear_slot(slot_id)
	_refresh_all()
	_show_save_popup()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_slot_changed(_slot_id: int) -> void:
	_refresh_all()


func _on_modal_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_modal()


func _fade_to_scene(scene_path: String) -> void:
	_navigating = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(scene_path)
	)


func _spawn_background_particles() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for _i in range(28):
		_particles.append({
			"pos": Vector2(randf() * viewport_size.x, randf() * viewport_size.y),
			"vel": Vector2(randf_range(-10.0, 10.0), randf_range(-18.0, -6.0)),
			"size": randf_range(1.5, 3.6),
			"alpha": randf_range(0.14, 0.35),
			"color_idx": randi() % 4,
		})
	if not _particle_canvas.draw.is_connected(_draw_particles):
		_particle_canvas.draw.connect(_draw_particles)


func _update_particles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for particle in _particles:
		particle["pos"] = particle["pos"] + particle["vel"] * delta
		particle["pos"].x += sin(_time * 0.7 + particle["size"] * 9.0) * 6.0 * delta
		if particle["pos"].y < -10.0 or particle["pos"].x < -10.0 or particle["pos"].x > viewport_size.x + 10.0:
			particle["pos"] = Vector2(randf() * viewport_size.x, viewport_size.y + randf_range(5.0, 22.0))
			particle["vel"] = Vector2(randf_range(-10.0, 10.0), randf_range(-18.0, -6.0))


func _draw_particles() -> void:
	var colors: Array[Color] = [
		Color(0.92, 0.28, 0.38, 1.0),
		Color(0.35, 0.65, 0.95, 1.0),
		Color(1.0, 0.75, 0.2, 1.0),
		Color(0.55, 0.9, 0.35, 1.0),
	]
	for particle in _particles:
		var color: Color = colors[int(particle["color_idx"])]
		color.a = float(particle["alpha"])
		var size := float(particle["size"])
		var pos: Vector2 = particle["pos"]
		var points := PackedVector2Array([
			pos + Vector2(0, -size),
			pos + Vector2(size * 0.6, 0),
			pos + Vector2(0, size),
			pos + Vector2(-size * 0.6, 0),
		])
		_particle_canvas.draw_colored_polygon(points, color)


func _create_meta_console() -> void:
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
	_menu_panel.modulate.a = 0.0
	_menu_panel.scale = Vector2(0.96, 0.96)
	_bottom_info.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_menu_panel, "modulate:a", 1.0, 0.35)
	tween.tween_property(_menu_panel, "scale", Vector2.ONE, 0.28)
	tween.tween_property(_bottom_info, "modulate:a", 1.0, 0.3).set_delay(0.08)
