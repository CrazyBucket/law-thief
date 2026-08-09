extends Control
const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")
const PoisonCloudRendererClass := preload("res://scripts/map/poison_cloud_renderer.gd")
const PoisonCloudLifecycleClass := preload("res://scripts/map/poison_cloud_lifecycle.gd")
const AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const WaterLayerClass = preload("res://scripts/map/water_layer.gd")
const ShallowWaterLayerClass = preload("res://scripts/map/shallow_water_overlay_renderer.gd")
const WaterAutotileClass = preload("res://scripts/map/water_autotile.gd")
const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const PLAYER_SPRITES_SCRIPT := preload("res://scripts/ui/female_adventurer_sprites.gd")
const SLIME_SPRITES_SCRIPT := preload("res://scripts/ui/slime_sprites.gd")
const GEM_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_gem_sprites.gd")
const PROP_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_prop_sprites.gd")
const BattleBoardBackLayerScript := preload("res://scripts/ui/battle_board_back_layer.gd")
const BattleBoardAnimationStateScript := preload("res://scripts/ui/battle_board_animation_state.gd")
const BattleBoardResourcesScript := preload("res://scripts/ui/battle_board_resources.gd")
const BattleCorpseRenderer := preload("res://scripts/ui/battle_corpse_renderer.gd")
const GemEchoVisuals := preload("res://scripts/ui/gem_echo_visuals.gd")
const BoardVisualGeometry := preload("res://scripts/ui/board_visual_geometry.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _Vpf := preload("res://scripts/ui/vfx_pack_frames.gd")
const IntentIcons := preload("res://scripts/ui/intent_icons.gd")
const OldMageBoardVisuals := preload("res://scripts/ui/old_mage_board_visuals.gd")
const StatusIcons := preload("res://scripts/ui/status_icons.gd")
const _LIGHTNING_FX_POOL_SIZE := 12
const _RADIAL_FX_POOL_SIZE := 16
const _CLOUD_FX_POOL_SIZE := 6
signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal cell_released(cell: Vector2i, has_cell: bool)
signal unit_slot_clicked(unit_uid: String, slot_index: int)
signal editor_tool_drag_hovered(tool: Dictionary, cell: Vector2i, has_cell: bool)
signal editor_tool_dropped(tool: Dictionary, cell: Vector2i, has_cell: bool)
signal animation_finished()
signal move_animation_finished()
signal projectile_animation_finished()

var overlay_specs: Array = []
var overlay_routes: Array = []
var hover_cell: Vector2i = Vector2i(-1, -1)
var editor_preview_cells: Array[Vector2i] = []
var editor_preview_active: bool = false
var editor_preview_valid: bool = false
var selected_unit_uid: String = ""
var timeline_hover_unit_uid: String = ""
var active_turn_unit_uid: String = ""
var _nameplate_alpha_by_uid: Dictionary = {}
var _hover_outline_alpha_by_uid: Dictionary = {}
var _selection_outline_alpha_by_uid: Dictionary = {}
var _active_aura_alpha_by_uid: Dictionary = {}
var state: GameState = null:
	set(value):
		var prev_id := state.get_instance_id() if state != null else 0
		_poison_cloud_lifecycle.prepare_state_change(state, value)
		state = value
		var next_id := value.get_instance_id() if value != null else 0
		if next_id != prev_id:
			_anim.clear_state_runtime()
			_facing_screen_refs.clear()
			_last_active_aura_redraw_tick = -1
			_nameplate_alpha_by_uid.clear()
			_hover_outline_alpha_by_uid.clear()
			_selection_outline_alpha_by_uid.clear()
			_active_aura_alpha_by_uid.clear()
		if is_node_ready():
			call("_update_origin")
		queue_redraw()
## 当 true 时逻辑 (0,0) 显示在棋盘底部（等距原点对调，仅冒险地图）
var invert_origin: bool = false

var _board_origin: Vector2 = Vector2.ZERO
var _animation_speed_scale: float = 1.0

## 棋盘地砖贴图（替代程序化绘制的菱形格子），按网格几何自动对齐
var _board_texture: Sprite2D = null
var _water_fill_layer: Node2D = null
var _water_edge_layer: Node2D = null
var _shallow_water_layer: Node2D = null
var _back_overlay_layer: Control = null
var _water_visual_signature: int = -1
var _overlay_shader_viewports: Array[SubViewport] = []
var _gem_echo_shader_viewport: SubViewport = null
var _gem_echo_smoke_texture: Texture2D = null
var _gem_echo_icon_viewports: Dictionary = {}
var _gem_echo_icon_textures: Dictionary = {}
var _gem_texture_content_bounds: Dictionary = {}
var _resources := BattleBoardResourcesScript.new()
var _slot_panel_renderer = null
var _last_continuous_redraw_tick: int = -1
var _last_back_overlay_redraw_tick: int = -1
var _last_active_aura_redraw_tick: int = -1
var _draw_count: int = 0
var _sorted_cells_cache: Array[Vector2i] = []
var _sorted_cells_cache_size: Vector2i = Vector2i(-1, -1)
var _sorted_cells_cache_invert: bool = false

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim := BattleBoardAnimationStateScript.new()

var _knight_sprites: RefCounted = null ## DoodleKnightSprites
var _player_sprites: RefCounted = null ## FemaleAdventurerSprites
var _slime_sprites: RefCounted = null ## SlimeSprites
var _slime_sprites_by_variant: Dictionary = {}
var _gem_sprites: RefCounted = null ## DoodleGemSprites
var _prop_sprites: RefCounted = null ## DoodlePropSprites
var _fx_textures: RefCounted = null
var _soft_gradient_tex: Texture2D = null
var _beam_layer: Control = null
var _light_beam_fx = null
var _projectile_fx = null
var _particle_fx = null
var _shader_fx_seed: int = 0
var _shader_fx_pool = null
var _shader_fx_warmup = null
var _combat_fx_warmup_stage: int = -2
var _frozen_unit_visuals := preload("res://scripts/ui/frozen_unit_visuals.gd").new()
var _poison_cloud_lifecycle := PoisonCloudLifecycleClass.new()
@export_group("Light Beam FX")
@export_range(2.0, 30.0, 0.5) var light_beam_base_half_width: float = 13.5
@export_range(0.1, 3.0, 0.05) var light_beam_global_scale: float = 1.0
@export_range(0.1, 3.0, 0.05) var light_beam_global_power: float = 1.0
@export_range(0.1, 2.0, 0.05) var light_beam_duration: float = 0.46
@export_range(-60.0, 0.0, 1.0) var light_beam_plane_height: float = -28.0
@export_range(0.0, 20.0, 1.0) var light_beam_source_drop: float = 7.0

@export_group("Shader FX")
@export_range(0.1, 2.0, 0.05) var lightning_fx_duration: float = 0.34
@export_range(0.1, 2.0, 0.05) var radial_fx_duration: float = 0.42
@export_range(0.1, 2.0, 0.05) var cloud_fx_duration: float = 0.58
@export_range(0.1, 2.0, 0.05) var explosion_presentation_duration: float = 0.75
@export_range(0.05, 0.95, 0.05) var explosion_impact_ratio: float = 0.16
@export_range(0.05, 0.95, 0.05) var lightning_impact_ratio: float = 0.41
# 抛射物动画：二次贝塞尔曲线飞行（支持齐射）

## Knight 底板锚点在格心；贴图腿长导致视觉上偏悬空，下移若干像素压住地面感
const _UNIT_SPRITE_GROUND_OFFSET_Y := 12.0
const _SLIME_SPRITE_GROUND_OFFSET_Y := -2.0
const _PLAYER_WALK_FRAMES := 8
const _PLAYER_IDLE_FRAMES := 8
const _PLAYER_IDLE_FPS := 10.0
const _PLAYER_WALK_FPS := 12.0
const _PLAYER_STRIKE_FRAMES := 8
const _PLAYER_STRIKE_DURATION := 0.52
const _KNIGHT_STRIKE_DURATION := 0.28
const _SLIME_IDLE_FPS := 2.0
const _SLIME_IDLE_FRAMES := 2
const _SLIME_WALK_FPS := 10.0
const _SLIME_ANIM_FRAMES := 6
const _SLIME_STRIKE_FRAMES := 6
const _SLIME_STRIKE_DURATION := 0.36
const _INVALID_GRID := Vector2i(-9999, -9999)
const _MOVE_DURATION := 0.35
const _COLLISION_LUNGE_DURATION := 0.11
const _COLLISION_RECOIL_DURATION := 0.13
const _COLLISION_CONTACT_RATIO := 0.42
const _HIT_DURATION := 0.24
const _GEM_LIFT_DURATION := 0.48
const _GEM_INSERT_DURATION := 0.38
const _GEM_ORBIT_SPEED := 1.9
const _GEM_ORBIT_RADIUS_X := 20.0
const _GEM_ORBIT_RADIUS_Y := 7.5
const _GEM_BOB_SPEED := 1.7
const _GEM_BOB_AMPLITUDE := 1.0
const _CONTINUOUS_REDRAW_FPS := 60.0
const _BACK_OVERLAY_REDRAW_FPS := 30.0
const _ACTIVE_AURA_REDRAW_FPS := 30.0
const _BOARD_TEXTURE_SOURCE_SIZE := Vector2(1254.0, 1254.0)
const _BOARD_TEXTURE_CONTENT_RECT := Rect2(70.0, 76.0, 1116.0, 1102.0)
const _GEM_DRAW_SIZE := 18.0
const _GEM_SLOT_SOURCE_OFFSET := Vector2(0.0, -28.0)
## 等距棋盘仅四斜向（由 grid_to_screen 校准）
const _FACING_GRID_STEPS: Dictionary = {
	"DR": Vector2i(1, 0),
	"DL": Vector2i(0, 1),
	"UL": Vector2i(-1, 0),
	"UR": Vector2i(0, -1),
}

var _facing_screen_refs: Dictionary = {}
var _startup_ready_duration_usec: int = 0
var _startup_first_draw_duration_usec: int = 0
var _startup_first_draw_phases: Dictionary = {}

func grid_to_screen(grid: Vector2i) -> Vector2:
	return IsoCoordinates.grid_to_screen(grid, _board_origin, invert_origin, _board_size())

func _board_size() -> Vector2i:
	if state != null:
		return state.board_size
	return Constants.BOARD_SIZE

func _ensure_beam_layer() -> void:
	if _beam_layer == null:
		_beam_layer = Control.new()
		_beam_layer.name = "BeamLayer"
		_beam_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_beam_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_beam_layer)

func _ensure_fx_textures() -> void:
	if _fx_textures != null:
		return
	var textures_script := _resources.board_fx_textures_script() as Script
	if textures_script != null:
		_fx_textures = textures_script.new()

func _ensure_shader_fx_pool() -> void:
	_ensure_beam_layer()
	if _shader_fx_pool == null:
		var pool_script := _resources.shader_fx_pool_script() as Script
		if pool_script != null:
			_shader_fx_pool = pool_script.new()
			_shader_fx_pool.configure(_beam_layer)
	if _shader_fx_warmup == null and _shader_fx_pool != null:
		var warmup_script := _resources.shader_fx_warmup_script() as Script
		if warmup_script != null:
			_shader_fx_warmup = warmup_script.new()
			add_child(_shader_fx_warmup)
			_shader_fx_warmup.configure(
				_shader_fx_pool,
				_resources,
				[_LIGHTNING_FX_POOL_SIZE, _RADIAL_FX_POOL_SIZE, _CLOUD_FX_POOL_SIZE]
			)

func _ensure_light_beam_fx() -> void:
	if _light_beam_fx != null:
		return
	_ensure_beam_layer()
	var light_beam_script := _resources.light_beam_fx_script() as Script
	if light_beam_script != null:
		_light_beam_fx = light_beam_script.new()
		_light_beam_fx.name = "LightBeamFx"
		_light_beam_fx.configure(Callable(self, "grid_to_screen"))
		_beam_layer.add_child(_light_beam_fx)

func _ensure_projectile_fx() -> void:
	if _projectile_fx != null:
		return
	_ensure_beam_layer()
	_ensure_fx_textures()
	var projectile_script := _resources.projectile_fx_script() as Script
	if projectile_script != null:
		_projectile_fx = projectile_script.new()
		_projectile_fx.name = "ProjectileFx"
		_projectile_fx.configure(Callable(self, "grid_to_screen"), _fx_textures)
		_projectile_fx.finished.connect(_on_projectile_fx_finished)
		_beam_layer.add_child(_projectile_fx)

func _ensure_particle_fx() -> void:
	if _particle_fx != null:
		return
	_ensure_beam_layer()
	_ensure_fx_textures()
	var particle_script := _resources.particle_fx_script() as Script
	if particle_script != null:
		_particle_fx = particle_script.new()
		_particle_fx.name = "ParticleFx"
		_particle_fx.configure(_fx_textures)
		_beam_layer.add_child(_particle_fx)

func _spawn_shader_rect_fx(
	shader: Shader,
	center: Vector2,
	fx_size: Vector2,
	duration: float,
	params: Dictionary = {},
	rotation: float = 0.0
) -> Control:
	_ensure_shader_fx_pool()
	if _beam_layer == null or shader == null:
		return null
	_shader_fx_seed += 1
	var shader_key: String = _shader_fx_pool.key_for(shader)
	var rect: ColorRect = _shader_fx_pool.acquire(shader)
	rect.size = fx_size
	rect.position = center - fx_size * 0.5
	rect.pivot_offset = fx_size * 0.5
	rect.rotation = rotation
	var material := rect.material as ShaderMaterial
	for old_key in rect.get_meta("shader_fx_param_keys", []):
		material.set_shader_parameter(str(old_key), null)
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("seed", float(_shader_fx_seed))
	for key in params.keys():
		material.set_shader_parameter(str(key), params[key])
	rect.set_meta("shader_fx_param_keys", params.keys())
	rect.visible = true
	_beam_layer.move_child(rect, _beam_layer.get_child_count() - 1)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		if not is_instance_valid(rect):
			return
		var live_material := rect.material as ShaderMaterial
		if live_material != null:
			live_material.set_shader_parameter("progress", v)
	, 0.0, 1.0, _scaled_duration(duration))
	tween.tween_callback(func() -> void:
		if is_instance_valid(rect):
			_shader_fx_pool.release(shader_key, rect)
	)
	return rect

func _get_unit_screen_center(unit: UnitState) -> Vector2:
	return _footprint_screen_center_at(unit, unit.pos)

func _footprint_screen_center_at(unit: UnitState, anchor: Vector2i) -> Vector2:
	if unit == null:
		return grid_to_screen(anchor)
	var cells := BoardUtils.footprint_cells_at(unit.footprint_size, anchor)
	var total_screen := Vector2.ZERO
	for cell in cells:
		total_screen += grid_to_screen(cell)
	return total_screen / cells.size()

func _scaled_duration(base_duration: float) -> float:
	return base_duration / _animation_speed_scale

func _add_particle(spec: Dictionary) -> void:
	_ensure_particle_fx()
	if _particle_fx != null:
		_particle_fx.add(spec)

func _push_sprite_sequence(cfg: Dictionary) -> bool:
	_ensure_particle_fx()
	return _particle_fx.push_sprite_sequence(cfg) if _particle_fx != null else false


## 播放伤害/爆炸特效

func play_lightning_bolt(from_grid: Vector2i, to_grid: Vector2i, bolt_color: Color = Color(0.58, 0.9, 1.0)) -> void:
	var from_scr := grid_to_screen(from_grid) + IsoCoordinates.visual_vec(Vector2(0.0, -44.0))
	var to_scr := grid_to_screen(to_grid) + IsoCoordinates.visual_vec(Vector2(0.0, -38.0))
	_spawn_lightning_between_points(from_scr, to_scr, bolt_color)
	_spawn_radial_burst_at_grid(
		to_grid,
		Color(0.84, 0.98, 1.0, 1.0),
		Color(0.12, 0.52, 1.0, 0.74),
		{
			"ring_width": 0.07,
			"ray_count": 16.0,
			"ray_strength": 0.72,
			"core_strength": 0.2,
			"squash": 0.62,
		},
		0.28
	)
	queue_redraw()

func play_lightning_bolt_task(from_grid: Vector2i, to_grid: Vector2i, bolt_color: Color = Color(0.58, 0.9, 1.0)) -> void:
	play_lightning_bolt(from_grid, to_grid, bolt_color)
	if is_inside_tree():
		await get_tree().create_timer(_scaled_duration(lightning_fx_duration)).timeout

func play_electrical_batch(events: Array) -> Dictionary:
	for event in events:
		var from_grid: Vector2i = event.get("from", event.get("pos", Vector2i.ZERO))
		var to_grid: Vector2i = event.get("target_pos", event.get("pos", from_grid))
		if from_grid == to_grid:
			play_lightning_strike(to_grid)
		else:
			play_lightning_bolt(from_grid, to_grid)
	var duration := _scaled_duration(lightning_fx_duration)
	return {
		"duration": duration,
		"impact_time": duration * lightning_impact_ratio,
	}

func play_lightning_strike(grid: Vector2i, bolt_color: Color = Color(0.58, 0.9, 1.0)) -> void:
	var to_scr := grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -34.0))
	var from_scr := to_scr + IsoCoordinates.visual_vec(Vector2(0.0, -120.0))
	_spawn_lightning_between_points(from_scr, to_scr, bolt_color)
	_spawn_radial_burst_at_grid(
		grid,
		Color(0.85, 0.98, 1.0, 1.0),
		Color(0.18, 0.62, 1.0, 0.78),
		{
			"ring_width": 0.06,
			"ray_count": 18.0,
			"ray_strength": 0.78,
			"core_strength": 0.24,
			"squash": 0.58,
		},
		0.3
	)
	queue_redraw()

func play_lightning_strike_task(grid: Vector2i, bolt_color: Color = Color(0.58, 0.9, 1.0)) -> void:
	play_lightning_strike(grid, bolt_color)
	if is_inside_tree():
		await get_tree().create_timer(_scaled_duration(lightning_fx_duration)).timeout

func play_fire_burst(grid: Vector2i) -> void:
	_spawn_radial_burst_at_grid(
		grid,
		Color(1.0, 0.78, 0.28, 1.0),
		Color(1.0, 0.16, 0.04, 0.82),
		{
			"ring_width": 0.11,
			"ray_count": 13.0,
			"ray_strength": 0.58,
			"core_strength": 0.33,
			"squash": 0.7,
		},
		radial_fx_duration
	)
	play_gem_flash(grid, Color(1.0, 0.45, 0.1))

func play_frost_pulse(grid: Vector2i) -> void:
	_spawn_radial_burst_at_grid(
		grid,
		Color(0.82, 1.0, 1.0, 1.0),
		Color(0.18, 0.78, 1.0, 0.72),
		{
			"ring_width": 0.055,
			"ray_count": 20.0,
			"ray_strength": 0.45,
			"core_strength": 0.16,
			"squash": 0.58,
		},
		radial_fx_duration
	)
	play_gem_flash(grid, Color(0.45, 0.9, 1.0))

func _spawn_lightning_between_points(from_scr: Vector2, to_scr: Vector2, bolt_color: Color) -> void:
	var delta := to_scr - from_scr
	var length := delta.length()
	if length < 1.0:
		return
	var center := (from_scr + to_scr) * 0.5
	var rect_size := Vector2(length + IsoCoordinates.visual(42.0), IsoCoordinates.visual(104.0))
	var core := Color.WHITE.lerp(bolt_color, 0.46)
	var glow := Color(0.12, 0.42, 1.0).lerp(bolt_color, 0.55)
	_spawn_shader_rect_fx(
		_resources.lightning_shader(),
		center,
		rect_size,
		lightning_fx_duration,
		{
			"core_color": core,
			"glow_color": glow,
			"jitter": 0.15,
			"thickness": 0.022,
			"branch_strength": 0.68,
		},
		delta.angle()
	)

func _spawn_radial_burst_at_grid(
	grid: Vector2i,
	inner_color: Color,
	outer_color: Color,
	params: Dictionary = {},
	duration: float = -1.0
) -> void:
	var center := grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -18.0))
	var size := Vector2(IsoCoordinates.visual(128.0), IsoCoordinates.visual(112.0))
	var fx_params := params.duplicate(true)
	fx_params["inner_color"] = inner_color
	fx_params["outer_color"] = outer_color
	_spawn_shader_rect_fx(
		_resources.radial_burst_shader(),
		center,
		size,
		radial_fx_duration if duration <= 0.0 else duration,
		fx_params
	)

func _spawn_cloud_pulse_at_grid(
	grid: Vector2i,
	cloud_color: Color,
	rim_color: Color,
	duration: float = -1.0
) -> void:
	var center := grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -10.0))
	var size := Vector2(IsoCoordinates.visual(118.0), IsoCoordinates.visual(88.0))
	_spawn_shader_rect_fx(
		_resources.cloud_pulse_shader(),
		center,
		size,
		cloud_fx_duration if duration <= 0.0 else duration,
		{
			"cloud_color": cloud_color,
			"rim_color": rim_color,
			"density": 1.12,
			"squash": 0.62,
		}
	)

func play_damage_effect(grid: Vector2i, damage: int, is_crit: bool) -> void:
	var hit_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_SMALL_HIT)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -16.0))
	var used_pack := false
	if _Vpf.is_pack_available() and not hit_paths.is_empty():
		var dim_big := IsoCoordinates.visual(72.0)
		var dim_small := IsoCoordinates.visual(56.0)
		var dim := dim_small
		if is_crit:
			dim = dim_big
		var dmg_tint := Color(0.88, 0.98, 1.0)
		if is_crit:
			dmg_tint = Color(1.0, 0.68, 0.68)
		used_pack = _push_sprite_sequence({
			"paths": hit_paths,
			"pos": center_scr,
			"fps": 38.0,
			"draw_size": Vector2(dim, dim),
			"tint": dmg_tint,
			"velocity": Vector2.ZERO,
			"life_pad": 0.03,
		})
	if not used_pack:
		_play_damage_procedural_fallback(grid, damage, is_crit)
	queue_redraw()

func _play_damage_procedural_fallback(grid: Vector2i, damage: int, is_crit: bool) -> void:
	var center: Vector2 = grid_to_screen(grid)
	var count: int = clampi(damage * 2, 4, 20)
	var base_color := Color(1.0, 0.65, 0.2)
	if is_crit:
		base_color = Color(1.0, 0.3, 0.15)
	
	# 加入一个居中的打击十字/星形特效（类型 hit_mark）
	_add_particle({
		"pos": center + IsoCoordinates.visual_vec(Vector2(0, -15)),
		"color": Color(1.0, 1.0, 1.0, 0.9) if not is_crit else Color(1.0, 0.4, 0.4, 1.0),
		"life": 0.25,
		"max_life": 0.25,
		"velocity": Vector2.ZERO,
		"type": "hit_mark",
		"scale": 1.5 if is_crit else 1.0
	})
	
	for _i in range(count):
		var angle: float = randf() * TAU
		var speed: float = randf_range(IsoCoordinates.visual(60.0), IsoCoordinates.visual(180.0))
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		var life: float = randf_range(0.3, 0.6)
		var color: Color = base_color.lerp(Color.WHITE, randf() * 0.4)
		_add_particle({
			"pos": center + Vector2(randf_range(-IsoCoordinates.visual(8.0), IsoCoordinates.visual(8.0)), randf_range(-IsoCoordinates.visual(20.0), -IsoCoordinates.visual(5.0))),
			"color": color,
			"life": life,
			"max_life": life,
			"velocity": vel,
			"type": "spark"
		})


## 播放治疗特效

func play_heal_effect(grid: Vector2i) -> void:
	var heal_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_HEAL_CHARGE)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -20.0))
	var used_pack := false
	if _Vpf.is_pack_available() and not heal_paths.is_empty():
		used_pack = _push_sprite_sequence({
			"paths": heal_paths,
			"pos": center_scr,
			"fps": 32.0,
			"draw_size": Vector2(80.0, 80.0),
			"tint": Color(0.35, 1.0, 0.55),
			"velocity": Vector2.ZERO,
			"life_pad": 0.04,
		})
	if not used_pack:
		var center_legacy: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0, -20))
		for _i in range(8):
			var vel: Vector2 = Vector2(randf_range(-IsoCoordinates.visual(20.0), IsoCoordinates.visual(20.0)), randf_range(-IsoCoordinates.visual(80.0), -IsoCoordinates.visual(40.0)))
			var life: float = randf_range(0.4, 0.8)
			_add_particle({
				"pos": center_legacy + Vector2(randf_range(-12, 12), randf_range(0, 10)),
				"color": Color(0.3, 1.0, 0.5, 0.9),
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "heal"
			})
	queue_redraw()


## 播放宝石拔出/嵌入闪光

func play_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	var sparkle_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_GEM_SPARK)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -30.0))
	var pulse_tint: Color = Color.WHITE.lerp(gem_color, 0.55)
	var used_pack := false
	if _Vpf.is_pack_available() and not sparkle_paths.is_empty():
		used_pack = _push_sprite_sequence({
			"paths": sparkle_paths,
			"pos": center_scr,
			"fps": 28.0,
			"draw_size": Vector2(64.0, 64.0),
			"tint": pulse_tint,
			"velocity": Vector2.ZERO,
			"life_pad": 0.03,
		})
	if not used_pack:
		var center_legacy: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0, -30))
		for _i in range(6):
			var angle: float = randf() * TAU
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(IsoCoordinates.visual(30.0), IsoCoordinates.visual(80.0))
			var life: float = randf_range(0.2, 0.5)
			_add_particle({
				"pos": center_legacy,
				"color": gem_color,
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "gem"
			})
	queue_redraw()


## 剧毒：优先 VFX 包 puff；缺失时用 Doodle Particles/Puff。

func play_poison_burst(anchor_grid: Vector2i, radius: int, pattern: String = "") -> void:
	if state == null:
		return
	var cells: Array[Vector2i] = []
	if pattern == "cross":
		cells.append(anchor_grid)
		for neighbor in BoardVisualGeometry.neighbors4(anchor_grid):
			if BoardVisualGeometry.in_bounds(neighbor, state.board_size):
				cells.append(neighbor)
	elif radius <= 0:
		cells.append(anchor_grid)
	else:
		for cell in BoardVisualGeometry.cells_in_radius(anchor_grid, radius):
			if BoardVisualGeometry.in_bounds(cell, state.board_size):
				cells.append(cell)
	var puff_vfx: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_PUFF)
	for cell in cells:
		var base: Vector2 = grid_to_screen(cell) + IsoCoordinates.visual_vec(Vector2(0, -10))
		_spawn_cloud_pulse_at_grid(
			cell,
			Color(0.18, 0.78, 0.28, 0.62),
			Color(0.62, 1.0, 0.42, 0.44),
			cloud_fx_duration
		)
		var placed_pack := false
		if _Vpf.is_pack_available() and not puff_vfx.is_empty():
			placed_pack = _push_sprite_sequence({
				"paths": puff_vfx,
				"pos": base + Vector2(randf_range(-IsoCoordinates.visual(12.0), IsoCoordinates.visual(12.0)), randf_range(-IsoCoordinates.visual(14.0), IsoCoordinates.visual(6.0))),
				"fps": 42.0,
				"draw_size": Vector2(72.0, 72.0),
				"tint": Color(0.38, 0.95, 0.52),
				"velocity": Vector2(randf_range(-IsoCoordinates.visual(10.0), IsoCoordinates.visual(10.0)), randf_range(-IsoCoordinates.visual(22.0), -IsoCoordinates.visual(6.0))),
				"life_pad": 0.03,
			})
		if not placed_pack:
			var puff_legacy: PackedStringArray = _puff_sprite_paths()
			for _j in range(2):
				var life_here: float = randf_range(0.48, 0.62)
				_add_particle({
					"type": "sprite_seq",
					"pos": base + Vector2(randf_range(-IsoCoordinates.visual(14.0), IsoCoordinates.visual(14.0)), randf_range(-IsoCoordinates.visual(18.0), IsoCoordinates.visual(8.0))),
					"life": life_here,
					"max_life": life_here,
					"velocity": Vector2(randf_range(-IsoCoordinates.visual(18.0), IsoCoordinates.visual(18.0)), randf_range(-IsoCoordinates.visual(32.0), -IsoCoordinates.visual(12.0))),
					"frame_time": 0.0,
					"fps": randf_range(16.0, 22.0),
					"paths": puff_legacy,
					"draw_size": Vector2(44, 44),
					"tint": Color(0.42, 0.92, 0.38, 1.0),
				})
	queue_redraw()


## 爆炸（宝石/敌人）：优先 VFX 包；缺失时沿用程序粒子。

func play_explosion(grid: Vector2i) -> void:
	var exp_paths: PackedStringArray = _Vpf.frame_paths(_Vpf.EFFECT_EXPLOSION)
	var center_scr: Vector2 = grid_to_screen(grid) + IsoCoordinates.visual_vec(Vector2(0.0, -24.0))
	_spawn_radial_burst_at_grid(
		grid,
		Color(1.0, 0.9, 0.45, 1.0),
		Color(1.0, 0.22, 0.04, 0.78),
		{
			"ring_width": 0.12,
			"ray_count": 16.0,
			"ray_strength": 0.66,
			"core_strength": 0.36,
			"squash": 0.72,
		},
		0.42
	)
	var ok := false
	if _Vpf.is_pack_available() and not exp_paths.is_empty():
		ok = _push_sprite_sequence({
			"paths": exp_paths,
			"pos": center_scr,
			"fps": 48.0,
			"draw_size": Vector2(164.0, 164.0),
			"tint": Color(1.0, 1.0, 0.98),
			"velocity": Vector2.ZERO,
			"life_pad": 0.1,
		})
	if not ok:
		var center_legacy: Vector2 = grid_to_screen(grid) + Vector2(0, -20)
		for _i in range(30):
			var angle: float = randf() * TAU
			var speed: float = randf_range(100.0, 280.0)
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
			var life: float = randf_range(0.4, 0.9)
			var color: Color = Color(1.0, randf_range(0.2, 0.6), 0.05).lerp(Color.WHITE, randf() * 0.3)
			_add_particle({
				"pos": center_legacy + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				"color": color,
				"life": life,
				"max_life": life,
				"velocity": vel,
				"type": "spark"
			})
		for _k in range(12):
			var angle2: float = randf() * TAU
			var speed2: float = randf_range(20.0, 60.0)
			var vel2: Vector2 = Vector2(cos(angle2), sin(angle2)) * speed2 + Vector2(0, -30)
			var life2: float = randf_range(0.6, 1.2)
			_add_particle({
				"pos": center_legacy + Vector2(randf_range(-10, 10), randf_range(-5, 5)),
				"color": Color(0.3, 0.3, 0.35, 0.7),
				"life": life2,
				"max_life": life2,
				"velocity": vel2,
				"type": "smoke"
			})
		_add_particle({
			"pos": center_legacy,
			"color": Color(1.0, 0.6, 0.1, 0.8),
			"life": 0.4,
			"max_life": 0.4,
			"velocity": Vector2.ZERO,
			"type": "ring"
		})
	queue_redraw()

func play_explosion_batch(events: Array) -> Dictionary:
	for event in events:
		play_explosion(event.get("pos", Vector2i.ZERO))
	var duration := _scaled_duration(explosion_presentation_duration)
	return {
		"duration": duration,
		"impact_time": duration * explosion_impact_ratio,
	}

func _puff_sprite_paths() -> PackedStringArray:
	_ensure_particle_fx()
	return _particle_fx.puff_paths() if _particle_fx != null else PackedStringArray()


# ═══════════════════════════════════════════════════════════════════════════
# 抛射物动画
# ═══════════════════════════════════════════════════════════════════════════

## 播放玩家投射物：从 from_grid 飞向 to_grid，走贝塞尔弧线

func play_projectile(
	from_grid: Vector2i,
	to_grid: Vector2i,
	proj_color: Color = Color(0.95, 0.92, 0.45),
	source_uid: String = "", element: String = "", gem_level: int = 0
) -> void:
	play_projectiles([{
		"from": from_grid,
		"to": to_grid,
		"color": proj_color,
		"source_uid": source_uid, "element": element, "gem_level": gem_level,
	}])

func play_projectile_task(
	from_grid: Vector2i,
	to_grid: Vector2i,
	proj_color: Color = Color(0.95, 0.92, 0.45),
	source_uid: String = "", element: String = "", gem_level: int = 0
) -> void:
	play_projectile(from_grid, to_grid, proj_color, source_uid, element, gem_level)
	await projectile_animation_finished


## 齐射：多枚投射物同时飞行

func play_projectiles(shots: Array) -> void:
	_ensure_projectile_fx()
	if _projectile_fx == null:
		animation_finished.emit()
		projectile_animation_finished.emit()
		return
	var visual_shots: Array = []
	for raw_shot in shots:
		var shot: Dictionary = raw_shot.duplicate(true)
		var source_uid := str(shot.get("source_uid", ""))
		var source: UnitState = state.units.get(source_uid, null) if state != null else null
		if source != null:
			shot["from_screen"] = _get_unit_screen_center(source) + IsoCoordinates.visual_vec(Vector2(0, -20))
		visual_shots.append(shot)
	_projectile_fx.play(visual_shots, _animation_speed_scale)

func play_projectiles_task(shots: Array) -> void:
	if shots.is_empty():
		return
	play_projectiles(shots)
	await projectile_animation_finished

func _on_projectile_fx_finished() -> void:
	animation_finished.emit()
	projectile_animation_finished.emit()

func play_light_beam_task(
	from_grid: Vector2i,
	to_grid: Vector2i,
	beam_color: Color = Color(1.0, 0.96, 0.58),
	beam_width: float = 1.0,
	fx: Dictionary = {}
) -> void:
	await play_light_beams_task([{
		"from": from_grid,
		"to": to_grid,
		"color": beam_color,
		"width": beam_width,
		"fx": fx,
	}])

func play_light_beams(beams: Array) -> float:
	_ensure_light_beam_fx()
	if _light_beam_fx == null:
		return 0.0
	var visual_beams: Array = []
	for raw_beam in beams:
		var beam: Dictionary = raw_beam.duplicate(true)
		var fx: Dictionary = beam.get("fx", {})
		var source_uid := str(beam.get("source_uid", fx.get("source_uid", "")))
		var source: UnitState = state.units.get(source_uid, null) if state != null else null
		if source != null:
			beam["from_screen"] = _get_unit_screen_center(source)
		visual_beams.append(beam)
	return _light_beam_fx.play(visual_beams, _light_beam_fx_config())

func play_light_beams_task(beams: Array) -> void:
	var duration := play_light_beams(beams)
	if duration > 0.0 and is_inside_tree():
		await get_tree().create_timer(duration).timeout

func _light_beam_fx_config() -> Dictionary:
	return {
		"duration": _scaled_duration(light_beam_duration),
		"base_half_width": light_beam_base_half_width,
		"global_scale": light_beam_global_scale,
		"global_power": light_beam_global_power,
		"plane_height": light_beam_plane_height,
		"source_drop": light_beam_source_drop,
	}


