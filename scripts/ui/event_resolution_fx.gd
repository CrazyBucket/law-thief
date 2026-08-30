class_name EventResolutionFx
extends CanvasLayer

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const CoinTexture: Texture2D = preload("res://assets/ui/coin_gold.png")
const LowHealthShader: Shader = preload("res://scenes/adventure/event_low_health_vignette.gdshader")

const LOW_HEALTH_THRESHOLD := 0.10
const LOW_HEALTH_DURATION := 2.0
const COIN_SIZE := Vector2(16, 16)

var last_delta := {"hp": 0, "gold": 0}
var damage_shake_count := 0
var low_health_vignette_count := 0
var coin_burst_count := 0
var delta_text_count := 0

var _root: Control = null
var _vignette: ColorRect = null
var _vignette_material: ShaderMaterial = null
var _shake_targets: Array[Control] = []
var _shake_origins: Array[Vector2] = []
var _shake_tween: Tween = null
var _vignette_tween: Tween = null


func _ready() -> void:
	layer = 220
	_vignette = ColorRect.new()
	_vignette.name = "LowHealthVignette"
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = LowHealthShader
	_vignette.material = _vignette_material
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_root = Control.new()
	_root.name = "EventResolutionFxRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _exit_tree() -> void:
	_reset_shake()
	var status_hud := _status_hud()
	if status_hud != null:
		status_hud.call("finish_gold_gain_feedback")


func setup(shake_targets: Array[Control]) -> void:
	_shake_targets = shake_targets


func play(delta: Dictionary, before: Dictionary, after: Dictionary, origin: Vector2) -> void:
	var hp_delta := int(delta.get("hp", 0))
	var gold_delta := int(delta.get("gold", 0))
	last_delta = {"hp": hp_delta, "gold": gold_delta}
	if hp_delta < 0:
		_play_damage_shake()
		_spawn_delta_text("%d HP" % hp_delta, UiPalette.HP_LOW.lightened(0.14), origin, Vector2(-8, -42))
		var maximum := maxi(1, int(after.get("max_hp", 1)))
		if float(int(after.get("hp", 0))) / float(maximum) <= LOW_HEALTH_THRESHOLD:
			_play_low_health_vignette()
	elif hp_delta > 0:
		_spawn_delta_text("+%d HP" % hp_delta, UiPalette.HEAL_GREEN, origin, Vector2(4, -40))

	if gold_delta > 0:
		_spawn_delta_text("+%d 金币" % gold_delta, UiPalette.TEXT_GOLD, origin + Vector2(0, 24), Vector2(12, -46))
		_spawn_coin_burst(origin, int(before.get("gold", 0)), gold_delta)
	elif gold_delta < 0:
		_spawn_delta_text("%d 金币" % gold_delta, Color("#d59a74"), origin + Vector2(0, 24), Vector2(8, -38))


func _play_damage_shake() -> void:
	damage_shake_count += 1
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_reset_shake()
	_shake_origins.clear()
	for target in _shake_targets:
		_shake_origins.append(target.position)
	_shake_tween = create_tween()
	for offset in [Vector2(-3, 1), Vector2(3, -2), Vector2(-2, 2), Vector2(2, -1), Vector2(-1, 1)]:
		_shake_tween.tween_callback(_set_shake_offset.bind(offset))
		_shake_tween.tween_interval(0.035)
	_shake_tween.tween_callback(_reset_shake)


func _set_shake_offset(offset: Vector2) -> void:
	for i in range(mini(_shake_targets.size(), _shake_origins.size())):
		if is_instance_valid(_shake_targets[i]):
			_shake_targets[i].position = _shake_origins[i] + offset


func _reset_shake() -> void:
	for i in range(mini(_shake_targets.size(), _shake_origins.size())):
		if is_instance_valid(_shake_targets[i]):
			_shake_targets[i].position = _shake_origins[i]


func _play_low_health_vignette() -> void:
	low_health_vignette_count += 1
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette.visible = true
	_vignette_material.set_shader_parameter("intensity", 0.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(_set_vignette_intensity, 0.0, 1.0, 0.18)
	_vignette_tween.tween_interval(1.52)
	_vignette_tween.tween_method(_set_vignette_intensity, 1.0, 0.0, 0.30)
	_vignette_tween.tween_callback(_hide_vignette)


func _set_vignette_intensity(value: float) -> void:
	_vignette_material.set_shader_parameter("intensity", value)


func _hide_vignette() -> void:
	_vignette.visible = false


func _spawn_delta_text(text_value: String, color: Color, origin: Vector2, travel: Vector2) -> void:
	delta_text_count += 1
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", BattleUiTheme.event_semibold_font())
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = origin
	label.scale = Vector2(0.72, 0.72)
	_root.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", origin + travel, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.24).set_delay(0.48)
	tween.chain().tween_callback(label.queue_free)


func _spawn_coin_burst(origin: Vector2, previous_gold: int, amount: int) -> void:
	coin_burst_count += 1
	var count := clampi(int(ceil(float(amount) / 8.0)), 5, 12)
	var status_hud := _status_hud()
	var target := Vector2(270, 48)
	if status_hud != null:
		target = status_hud.call("gold_target_global_position")
		status_hud.call("begin_gold_gain_feedback", previous_gold)
	var base_amount := floori(float(amount) / float(count))
	var remainder := amount % count
	for i in range(count):
		var coin := TextureRect.new()
		coin.texture = CoinTexture
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(coin)
		coin.custom_minimum_size = COIN_SIZE
		coin.size = COIN_SIZE
		coin.position = origin - coin.size * 0.5
		var scatter := Vector2(randf_range(-42.0, 42.0), randf_range(-38.0, 14.0))
		var arrival_amount := base_amount + (1 if i < remainder else 0)
		var tween := create_tween()
		tween.tween_interval(float(i) * 0.035)
		tween.tween_property(coin, "position", origin + scatter - coin.size * 0.5, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", target - coin.size * 0.5, 0.44).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(coin, "scale", Vector2(0.62, 0.62), 0.44)
		if status_hud != null:
			tween.tween_callback(Callable(status_hud, "apply_gold_arrival").bind(arrival_amount))
		tween.tween_callback(coin.queue_free)
		if i == count - 1 and status_hud != null:
			tween.tween_callback(Callable(status_hud, "finish_gold_gain_feedback"))


func _status_hud() -> Node:
	return get_tree().root.get_node_or_null("AdventureStatusHud")
