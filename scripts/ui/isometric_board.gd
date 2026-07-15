extends Control

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const TileRenderer = preload("res://scripts/map/tile_renderer.gd")
const AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const WaterLayerClass = preload("res://scripts/map/water_layer.gd")
const WaterAutotileClass = preload("res://scripts/map/water_autotile.gd")

const KNIGHT_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_unit_sprites.gd")
const PLAYER_SPRITES_SCRIPT := preload("res://scripts/ui/female_adventurer_sprites.gd")
const SLIME_SPRITES_SCRIPT := preload("res://scripts/ui/slime_sprites.gd")
const GEM_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_gem_sprites.gd")
const PROP_SPRITES_SCRIPT := preload("res://scripts/ui/doodle_prop_sprites.gd")
const BoardFxTexturesClass := preload("res://scripts/ui/board_fx_textures.gd")
const BattleLightBeamFx := preload("res://scripts/ui/battle_light_beam_fx.gd")
const BattleProjectileFx := preload("res://scripts/ui/battle_projectile_fx.gd")
const BattleParticleFx := preload("res://scripts/ui/battle_particle_fx.gd")
const BattleSlotPanelLayout := preload("res://scripts/ui/battle_slot_panel_layout.gd")
const GemEchoVisuals := preload("res://scripts/ui/gem_echo_visuals.gd")
const BoardUtilsClass := preload("res://scripts/rules/board_utils.gd")
const GemRules = preload("res://scripts/rules/gem_rules.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _Vpf := preload("res://scripts/ui/vfx_pack_frames.gd")
const IntentIcons := preload("res://scripts/ui/intent_icons.gd")
const StatusIcons := preload("res://scripts/ui/status_icons.gd")
const WaterTileShader := preload("res://scenes/battle/water_tile.gdshader")
const FxLightningShader := preload("res://scenes/battle/fx_lightning_bolt.gdshader")
const FxRadialBurstShader := preload("res://scenes/battle/fx_radial_burst.gdshader")
const FxCloudPulseShader := preload("res://scenes/battle/fx_cloud_pulse.gdshader")
const OverlayDriftShader := preload("res://scenes/battle/overlay_drift.gdshader")
const GemEchoSmokeShader := preload("res://scenes/battle/gem_echo_smoke.gdshader")
const WATER_BOTTOM := preload("res://assets/tiles/mew_water_bottom.png")
const WATER_TOP := preload("res://assets/tiles/mew_water_top.png")
const ENTITY_SPIKE_TEXTURE := preload("res://assets/entities/entity_spike.svg")
const ENTITY_BARREL_TEXTURE := preload("res://assets/demo/doodle-rpg/ALL SPRITES/Barrel_0.png")
const ENTITY_ROCK_TEXTURE := preload("res://assets/demo/doodle-rpg/ALL SPRITES/Rock1_0.png")

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i, has_cell: bool)
signal cell_released(cell: Vector2i, has_cell: bool)
signal unit_slot_clicked(unit_uid: String, slot_index: int)
signal editor_tool_drag_hovered(tool: Dictionary, cell: Vector2i, has_cell: bool)
signal editor_tool_dropped(tool: Dictionary, cell: Vector2i, has_cell: bool)
signal animation_finished()
signal move_animation_finished()
signal projectile_animation_finished()

class BoardAnimationHostState:
	var pulse_time: float = 0.0
	var move_offsets: Dictionary = {}
	var move_path_segments: Dictionary = {}
	var move_path_segment_facings: Dictionary = {}
	var strike_elapsed: Dictionary = {}
	var hit_elapsed: Dictionary = {}
	var walk_phase: Dictionary = {}
	var idle_phase: Dictionary = {}
	var parallel_move_remaining: int = 0
	var held_gem_visual: Dictionary = {}
	var inserting_gem_visuals: Array[Dictionary] = []
	var masked_embedded_gems: Dictionary = {}

	func clear_state_runtime() -> void:
		move_offsets.clear()
		move_path_segments.clear()
		move_path_segment_facings.clear()
		walk_phase.clear()
		idle_phase.clear()
		strike_elapsed.clear()
		hit_elapsed.clear()

	func clear_gem_visuals() -> void:
		held_gem_visual.clear()
		inserting_gem_visuals.clear()
		masked_embedded_gems.clear()


var highlights: Dictionary = {}
var hover_cell: Vector2i = Vector2i(-1, -1)
var editor_preview_cells: Array[Vector2i] = []
var editor_preview_active: bool = false
var editor_preview_valid: bool = false
var selected_unit_uid: String = ""
var timeline_hover_unit_uid: String = ""
var active_turn_unit_uid: String = ""
var slot_panel_action: String = ""
var _slot_hover_unit_uid: String = ""
var _slot_hover_index: int = -1
var slot_panel_check: Callable = Callable()
var _nameplate_alpha_by_uid: Dictionary = {}
var _hover_outline_alpha_by_uid: Dictionary = {}
var _selection_outline_alpha_by_uid: Dictionary = {}
var _active_aura_alpha_by_uid: Dictionary = {}
var state: GameState = null:
	set(value):
		var prev_id := state.get_instance_id() if state != null else 0
		state = value
		var next_id := value.get_instance_id() if value != null else 0
		if next_id != prev_id:
			_anim.clear_state_runtime()
			_facing_screen_refs.clear()
			_nameplate_alpha_by_uid.clear()
			_hover_outline_alpha_by_uid.clear()
			_selection_outline_alpha_by_uid.clear()
			_active_aura_alpha_by_uid.clear()
		if is_node_ready():
			_update_origin()
		queue_redraw()
## 为 true 时逻辑 (0,0) 显示在棋盘底部（等距原点对调，仅冒险地图）
var invert_origin: bool = false

var _board_origin: Vector2 = Vector2.ZERO
var _animation_speed_scale: float = 1.0

## 棋盘地砖贴图（替代程序化绘制的菱形格子），按网格几何自动对齐
var _board_texture: Sprite2D = null
## 贴图去掉白边后的实际内容区域（缓存，仅扫描一次）
var _board_texture_region: Rect2 = Rect2()
var _water_fill_layer: Node2D = null
var _water_edge_layer: Node2D = null
var _water_visual_signature: int = -1
var _overlay_shader_viewports: Array[SubViewport] = []
var _gem_echo_shader_viewport: SubViewport = null
var _gem_echo_smoke_texture: Texture2D = null
var _gem_echo_icon_viewports: Dictionary = {}
var _gem_echo_icon_textures: Dictionary = {}
var _gem_texture_content_bounds: Dictionary = {}
var _last_continuous_redraw_tick: int = -1
var _sorted_cells_cache: Array[Vector2i] = []
var _sorted_cells_cache_size: Vector2i = Vector2i(-1, -1)
var _sorted_cells_cache_invert: bool = false

# ─── 动画系统 ─────────────────────────────────────────────────────────────
var _anim := BoardAnimationHostState.new()
## 移动 tween 插值元数据，用于把行走帧与位移进度对齐

var _knight_sprites: RefCounted = null ## DoodleKnightSprites
var _player_sprites: RefCounted = null ## FemaleAdventurerSprites
var _slime_sprites: RefCounted = null ## SlimeSprites
var _gem_sprites: RefCounted = null ## DoodleGemSprites
var _prop_sprites: RefCounted = null ## DoodlePropSprites
var _fx_textures: RefCounted = null
var _soft_gradient_tex: Texture2D = null
var _beam_layer: Control = null
var _light_beam_fx: BattleLightBeamFx = null
var _projectile_fx: BattleProjectileFx = null
var _particle_fx: BattleParticleFx = null
var _shader_fx_seed: int = 0

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


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_board_texture = get_node_or_null("Grids")
	_ensure_water_layers()
	_ensure_combat_visual_layers()
	resized.connect(_update_origin)
	_update_origin()
	_knight_sprites = KNIGHT_SPRITES_SCRIPT.new()
	_player_sprites = PLAYER_SPRITES_SCRIPT.new()
	_slime_sprites = SLIME_SPRITES_SCRIPT.new("green")
	_gem_sprites = GEM_SPRITES_SCRIPT.new()
	_prop_sprites = PROP_SPRITES_SCRIPT.new()
	_fx_textures = BoardFxTexturesClass.new()
	set_process(true)
	call_deferred("_sync_unit_orientations")


func _update_origin() -> void:
	var board_sz := _board_size()
	IsoCoordinates.tile_scale = IsoCoordinates.compute_tile_scale(size, board_sz)
	_board_origin = IsoCoordinates.board_origin(size, board_sz)
	_update_board_texture_transform()
	_sync_water_visuals()


## 把正方棋盘贴图映射到等距菱形上：四个角分别对到菱形上/右/下/左顶点
## （等价于旋转 45°＋纵向压扁 2:1，但用仿射矩阵一次性完成缩放与定位）
func _update_board_texture_transform() -> void:
	if _board_texture == null or _board_texture.texture == null:
		return
	# 只取非白底内容区域，裁掉四周白边，避免透明白边在菱形里占位导致格子内缩
	var region := _board_texture_content_rect()
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	_board_texture.region_enabled = true
	_board_texture.region_rect = region
	var board_sz := _board_size()
	var half_h := IsoCoordinates._half_h()
	var top := grid_to_screen(Vector2i(0, 0)) - Vector2(0, half_h)
	var bottom := grid_to_screen(Vector2i(board_sz.x - 1, board_sz.y - 1)) + Vector2(0, half_h)
	var center := (top + bottom) * 0.5
	var half_diag := IsoCoordinates.board_pixel_size(board_sz) * 0.5
	var x_axis := Vector2(half_diag.x, half_diag.y) / region.size.x
	var y_axis := Vector2(-half_diag.x, half_diag.y) / region.size.y
	_board_texture.transform = Transform2D(x_axis, y_axis, center)


## 扫描贴图，按 shader 同阈值（接近纯白即背景）求出内容包围盒，用于裁掉白边
func _board_texture_content_rect() -> Rect2:
	if _board_texture_region.size.x > 0.0:
		return _board_texture_region
	var tex := _board_texture.texture
	var full := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img == null:
		_board_texture_region = full
		return full
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var step := 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.04 or (c.r > 0.95 and c.g > 0.95 and c.b > 0.95):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		_board_texture_region = full
	else:
		_board_texture_region = Rect2(min_x, min_y, max_x - min_x + step, max_y - min_y + step)
	return _board_texture_region


func _process(delta: float) -> void:
	_anim.pulse_time += delta
	var scaled_dt := delta * _animation_speed_scale
	var has_highlights: bool = not highlights.is_empty()
	var visuals_dirty := _update_overlay_fades(delta)
	if has_highlights or not active_turn_unit_uid.is_empty():
		visuals_dirty = true
	for mv_uid in _anim.move_offsets.keys():
		if _anim.strike_elapsed.has(mv_uid):
			continue
		_anim.walk_phase[mv_uid] = _anim.walk_phase.get(mv_uid, 0.0) + scaled_dt
		visuals_dirty = true
	if state != null:
		_update_overlay_shader_activity()
		if _update_gem_echo_shader_activity():
			visuals_dirty = true
		if _has_animated_tile_overlays():
			visuals_dirty = true
		for unit: UnitState in state.units.values():
			if not unit.alive or not _uses_animated_idle(unit):
				continue
			if _anim.strike_elapsed.has(unit.uid) or _anim.move_offsets.has(unit.uid):
				continue
			_anim.idle_phase[unit.uid] = _anim.idle_phase.get(unit.uid, 0.0) + scaled_dt
			visuals_dirty = true

	var strike_done: Array[String] = []
	for stk in _anim.strike_elapsed.keys():
		var next_t: float = float(_anim.strike_elapsed[stk]) + scaled_dt
		_anim.strike_elapsed[stk] = next_t
		visuals_dirty = true
		if next_t >= _strike_duration_for(stk):
			strike_done.append(str(stk))
	for stk_rem in strike_done:
		_anim.strike_elapsed.erase(stk_rem)
	var hit_done: Array[String] = []
	for hit_uid in _anim.hit_elapsed.keys():
		var next_hit_t := float(_anim.hit_elapsed[hit_uid]) + scaled_dt
		_anim.hit_elapsed[hit_uid] = next_hit_t
		visuals_dirty = true
		if next_hit_t >= _HIT_DURATION:
			hit_done.append(str(hit_uid))
	for hit_uid in hit_done:
		_anim.hit_elapsed.erase(hit_uid)

	var needs_redraw := _particle_fx.step(delta) if _particle_fx != null else false
	var gem_dirty := _update_gem_visuals(scaled_dt)
	if (needs_redraw or visuals_dirty or gem_dirty) and _continuous_redraw_due():
		queue_redraw()


func _continuous_redraw_due() -> bool:
	var redraw_tick := floori(_anim.pulse_time * _CONTINUOUS_REDRAW_FPS)
	if redraw_tick == _last_continuous_redraw_tick:
		return false
	_last_continuous_redraw_tick = redraw_tick
	return true


func _has_animated_tile_overlays() -> bool:
	for tile: TileState in state.tiles.values():
		if tile != null and (
			not tile.modifiers.is_empty()
			or tile.tile_id == Constants.TILE_GRASS
			or tile.tile_id == Constants.TILE_BUSH
		):
			return true
	return false


func _ensure_overlay_shader_textures() -> void:
	if not _overlay_shader_viewports.is_empty():
		return
	var specs := [
		{"path": TileRenderer.GRASS_SPROUTS_PATH, "sway": 20.0, "vertical": 0.0, "speed": 1.42, "tip_bias": 1.0, "tip_power": 1.7},
		{"path": TileRenderer.GRASS_PATCH_PATH, "sway": 19.0, "vertical": 0.0, "speed": 1.34, "tip_bias": 1.0, "tip_power": 1.65},
		{"path": TileRenderer.GRASS_TALL_PATH, "sway": 22.0, "vertical": 0.0, "speed": 1.28, "tip_bias": 1.0, "tip_power": 1.8},
		{"path": TileRenderer.GRASS_THICKET_PATH, "sway": 17.0, "vertical": 0.0, "speed": 1.18, "tip_bias": 1.0, "tip_power": 1.9},
		{
			"path": TileRenderer.POISON_FOG_BODY_PATH,
			"sway": 22.0,
			"vertical": 8.0,
			"speed": 0.68,
			"tip_bias": 0.24,
			"tip_power": 0.78,
			"tint": Color(0.64, 1.0, 0.34, 1.0),
			"alpha_boost": 1.45,
			"saturation_boost": 1.22,
			"alpha_breathe": 0.08,
		},
		{
			"path": TileRenderer.TOXIC_SMOKE_BODY_PATH,
			"sway": 15.0,
			"vertical": 4.5,
			"speed": 0.46,
			"tip_bias": 0.34,
			"tip_power": 1.0,
			"tint": Color(0.66, 0.86, 0.36, 1.0),
			"alpha_boost": 1.18,
			"saturation_boost": 1.05,
			"alpha_breathe": 0.05,
		},
	]
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var source := load(str(spec["path"])) as Texture2D
		if source == null:
			continue
		var viewport := SubViewport.new()
		viewport.name = "OverlayShaderViewport%d" % index
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.size = Vector2i(source.get_width() + 64, source.get_height() + 64)
		viewport.set_meta("overlay_path", str(spec["path"]))
		var sprite := Sprite2D.new()
		sprite.texture = source
		sprite.position = Vector2(viewport.size) * 0.5
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = OverlayDriftShader
		material.set_shader_parameter("sway_px", float(spec["sway"]))
		material.set_shader_parameter("vertical_px", float(spec["vertical"]))
		material.set_shader_parameter("speed", float(spec["speed"]))
		material.set_shader_parameter("phase", float(index) * 1.37)
		material.set_shader_parameter("tip_bias", float(spec["tip_bias"]))
		material.set_shader_parameter("tip_power", float(spec["tip_power"]))
		material.set_shader_parameter("tint", spec.get("tint", Color.WHITE))
		material.set_shader_parameter("alpha_boost", float(spec.get("alpha_boost", 1.0)))
		material.set_shader_parameter("saturation_boost", float(spec.get("saturation_boost", 1.0)))
		material.set_shader_parameter("alpha_breathe", float(spec.get("alpha_breathe", 0.0)))
		sprite.material = material
		viewport.add_child(sprite)
		add_child(viewport)
		_overlay_shader_viewports.append(viewport)
		var source_rect: Rect2 = TileRenderer._overlay_texture_content_rect(source)
		var source_offset := (Vector2(viewport.size) - source.get_size()) * 0.5
		TileRenderer.register_animated_overlay_texture(
			str(spec["path"]),
			viewport.get_texture(),
			Rect2(source_offset + source_rect.position, source_rect.size)
		)


func _update_overlay_shader_activity() -> void:
	var active_paths := _active_overlay_shader_paths()
	if not active_paths.is_empty():
		_ensure_overlay_shader_textures()
	for viewport in _overlay_shader_viewports:
		var path := str(viewport.get_meta("overlay_path", ""))
		viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active_paths.has(path) else SubViewport.UPDATE_DISABLED
		)


func _active_overlay_shader_paths() -> Dictionary:
	var active := {}
	if state == null:
		return active
	for tile: TileState in state.tiles.values():
		if tile == null:
			continue
		if tile.tile_id == Constants.TILE_GRASS or tile.tile_id == Constants.TILE_BUSH:
			active[TileRenderer.GRASS_SPROUTS_PATH] = true
			active[TileRenderer.GRASS_PATCH_PATH] = true
			active[TileRenderer.GRASS_TALL_PATH] = true
			active[TileRenderer.GRASS_THICKET_PATH] = true
		if tile.has_modifier(Constants.TILE_MOD_POISON_FOG):
			active[TileRenderer.POISON_FOG_BODY_PATH] = true
		if tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
			active[TileRenderer.TOXIC_SMOKE_BODY_PATH] = true
	return active


func _update_gem_echo_shader_activity() -> bool:
	var active_gem_ids := _active_gem_echo_ids()
	var active := not active_gem_ids.is_empty()
	if active:
		_ensure_gem_echo_shader_texture()
		for gem_id in active_gem_ids.keys():
			_ensure_gem_echo_icon_shader_texture(str(gem_id))
	if _gem_echo_shader_viewport != null:
		_gem_echo_shader_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)
	for gem_id in _gem_echo_icon_viewports.keys():
		var viewport: SubViewport = _gem_echo_icon_viewports[gem_id]
		viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active_gem_ids.has(gem_id) else SubViewport.UPDATE_DISABLED
		)
	return active


func _active_gem_echo_ids() -> Dictionary:
	var result := {}
	if state == null:
		return result
	for raw_uid in state.overload_echo_gems.keys():
		var gem: GemState = state.gems.get(str(raw_uid), null)
		if gem != null and not gem.gem_id.is_empty():
			result[gem.gem_id] = true
	return result


func _ensure_gem_echo_shader_texture() -> void:
	if _gem_echo_shader_viewport != null:
		return
	_gem_echo_shader_viewport = SubViewport.new()
	_gem_echo_shader_viewport.name = "GemEchoShaderViewport"
	_gem_echo_shader_viewport.disable_3d = true
	_gem_echo_shader_viewport.transparent_bg = true
	_gem_echo_shader_viewport.size = Vector2i(64, 64)
	_gem_echo_shader_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var smoke := ColorRect.new()
	smoke.size = Vector2(_gem_echo_shader_viewport.size)
	smoke.color = Color.WHITE
	smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = GemEchoSmokeShader
	smoke.material = material
	_gem_echo_shader_viewport.add_child(smoke)
	add_child(_gem_echo_shader_viewport)
	_gem_echo_smoke_texture = _gem_echo_shader_viewport.get_texture()


func _ensure_gem_echo_icon_shader_texture(gem_id: String) -> void:
	if _gem_echo_icon_viewports.has(gem_id) or _gem_sprites == null:
		return
	var source: Texture2D = _gem_sprites.texture_for_gem_id(gem_id)
	if source == null:
		return
	var viewport := SubViewport.new()
	viewport.name = "GemEchoIconShaderViewport%d" % _gem_echo_icon_viewports.size()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(source.get_width(), source.get_height())
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.set_meta("gem_id", gem_id)
	var sprite := Sprite2D.new()
	sprite.texture = source
	sprite.position = Vector2(viewport.size) * 0.5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = GemEchoVisuals.IconShader
	sprite.material = material
	viewport.add_child(sprite)
	add_child(viewport)
	_gem_echo_icon_viewports[gem_id] = viewport
	_gem_echo_icon_textures[gem_id] = viewport.get_texture()


func _display_gem_texture(gem: GemState, fallback: Texture2D) -> Texture2D:
	if gem != null and GemEchoVisuals.is_echo(state, gem.uid):
		return _gem_echo_icon_textures.get(gem.gem_id, fallback) as Texture2D
	return fallback


func _draw_echo_smoke(gem_uid: String, pos: Vector2, icon_size: float, alpha: float = 1.0) -> void:
	if not GemEchoVisuals.is_echo(state, gem_uid) or _gem_echo_smoke_texture == null:
		return
	var gem: GemState = state.gems.get(gem_uid, null)
	if gem == null:
		return
	var content_bounds := _gem_content_bounds(gem.gem_id)
	var pulse := 0.99 + sin(_anim.pulse_time * 1.10 + float(gem_uid.hash() % 17)) * 0.01
	var content_center := content_bounds.get_center()
	var smoke_center := pos + (content_center - Vector2(0.5, 0.5)) * icon_size
	var smoke_size := Vector2(icon_size, icon_size) * content_bounds.size
	# Leave enough room for two readable wisps at gameplay scale without turning them into a halo.
	smoke_size += Vector2.ONE * icon_size * 0.64
	smoke_size *= pulse
	draw_texture_rect(
		_gem_echo_smoke_texture,
		Rect2(smoke_center - smoke_size * 0.5, smoke_size),
		false,
		Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	)


func _gem_content_bounds(gem_id: String) -> Rect2:
	if _gem_texture_content_bounds.has(gem_id):
		return _gem_texture_content_bounds[gem_id]
	var fallback := Rect2(Vector2(0.18, 0.18), Vector2(0.64, 0.64))
	if _gem_sprites == null:
		return fallback
	var texture: Texture2D = _gem_sprites.texture_for_gem_id(gem_id)
	var image := texture.get_image() if texture != null else null
	if image == null:
		return fallback
	if image.is_compressed():
		image.decompress()
	var min_pos := Vector2i(image.get_width(), image.get_height())
	var max_pos := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.05:
				continue
			min_pos.x = mini(min_pos.x, x)
			min_pos.y = mini(min_pos.y, y)
			max_pos.x = maxi(max_pos.x, x)
			max_pos.y = maxi(max_pos.y, y)
	var bounds := fallback
	if max_pos.x >= min_pos.x and max_pos.y >= min_pos.y:
		var image_size := Vector2(image.get_width(), image.get_height())
		bounds = Rect2(Vector2(min_pos) / image_size, Vector2(max_pos - min_pos + Vector2i.ONE) / image_size)
	_gem_texture_content_bounds[gem_id] = bounds
	return bounds


func _update_overlay_fades(delta: float) -> bool:
	var name_targets: Array[String] = []
	var hover_targets: Array[String] = []
	var selection_targets: Array[String] = []
	var active_targets: Array[String] = []
	if state != null:
		for unit: UnitState in state.units.values():
			if not unit.alive:
				continue
			var uid := unit.uid
			if uid == selected_unit_uid or uid == timeline_hover_unit_uid:
				name_targets.append(uid)
			if uid == timeline_hover_unit_uid:
				hover_targets.append(uid)
			if uid == selected_unit_uid:
				selection_targets.append(uid)
			if uid == active_turn_unit_uid:
				active_targets.append(uid)
	var dirty := false
	dirty = _step_unit_fade(_nameplate_alpha_by_uid, name_targets, delta) or dirty
	dirty = _step_unit_fade(_hover_outline_alpha_by_uid, hover_targets, delta) or dirty
	dirty = _step_unit_fade(_selection_outline_alpha_by_uid, selection_targets, delta) or dirty
	dirty = _step_unit_fade(_active_aura_alpha_by_uid, active_targets, delta) or dirty
	return dirty


func _step_unit_fade(store: Dictionary, target_uids: Array[String], delta: float) -> bool:
	var targets: Dictionary = {}
	for uid in target_uids:
		targets[uid] = true
	var tracked: Dictionary = {}
	for uid in store.keys():
		tracked[uid] = true
	for uid in targets.keys():
		tracked[uid] = true
	var dirty := false
	for uid_value in tracked.keys():
		var uid := str(uid_value)
		var current := float(store.get(uid, 0.0))
		var target := 1.0 if targets.has(uid) else 0.0
		var speed := 12.0 if target > current else 4.5
		var next := move_toward(current, target, delta * speed)
		if absf(next - current) > 0.0001:
			dirty = true
		if next <= 0.001 and target <= 0.0:
			store.erase(uid)
		else:
			store[uid] = next
	return dirty


func set_battle_state(new_state: GameState) -> void:
	state = new_state


func init_unit_orientations() -> void:
	_sync_unit_orientations()


func _sync_unit_orientations() -> void:
	if state == null:
		return
	var player_cells: Array[Vector2i] = []
	var enemy_cells: Array[Vector2i] = []
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var center := _get_unit_screen_center(unit)
		if unit.team == Constants.TEAM_PLAYER:
			player_cells.append(Vector2i(int(center.x), int(center.y)))
		else:
			enemy_cells.append(Vector2i(int(center.x), int(center.y)))
	if player_cells.is_empty() or enemy_cells.is_empty():
		return
	var player_centroid := _screen_centroid(player_cells)
	var enemy_centroid := _screen_centroid(enemy_cells)
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var from_screen := _get_unit_screen_center(unit)
		var target_screen := enemy_centroid if unit.team == Constants.TEAM_PLAYER else player_centroid
		unit.facing = _facing_from_screen_delta(from_screen, target_screen, unit.facing)


func _screen_centroid(screen_points: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO
	for p in screen_points:
		sum += Vector2(p)
	return sum / screen_points.size()


func _facing_from_screen_delta(from_screen: Vector2, to_screen: Vector2, fallback: String) -> String:
	_ensure_facing_screen_refs()
	var screen_delta := to_screen - from_screen
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return fallback
	var dir := screen_delta.normalized()
	var best_name := fallback
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name


func set_highlights(new_highlights: Dictionary) -> void:
	highlights = new_highlights
	queue_redraw()


func set_hover(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	queue_redraw()


func set_editor_preview(cells: Array[Vector2i], valid: bool, active: bool = true) -> void:
	editor_preview_cells = cells.duplicate()
	editor_preview_valid = valid
	editor_preview_active = active
	queue_redraw()


func clear_editor_preview() -> void:
	set_editor_preview([], false, false)


func set_timeline_hover_unit(uid: String) -> void:
	if timeline_hover_unit_uid == uid:
		return
	timeline_hover_unit_uid = uid
	queue_redraw()


func set_active_turn_unit(uid: String) -> void:
	if active_turn_unit_uid == uid:
		return
	active_turn_unit_uid = uid
	queue_redraw()


func grid_to_screen(grid: Vector2i) -> Vector2:
	return IsoCoordinates.grid_to_screen(grid, _board_origin, invert_origin, _board_size())


func _board_size() -> Vector2i:
	if state != null:
		return state.board_size
	return Constants.BOARD_SIZE


func _sorted_cells() -> Array[Vector2i]:
	var size := _board_size()
	if _sorted_cells_cache.is_empty() or size != _sorted_cells_cache_size or invert_origin != _sorted_cells_cache_invert:
		_sorted_cells_cache = IsoCoordinates.sorted_cells(size, invert_origin)
		_sorted_cells_cache_size = size
		_sorted_cells_cache_invert = invert_origin
	return _sorted_cells_cache


func _draw() -> void:
	if state == null:
		_clear_water_visuals()
		return
	var drawn_units: Dictionary = {}
	var drawn_entities: Dictionary = {}
	var drawn_entity_ui: Dictionary = {}
	for grid in _sorted_cells():
		_draw_tile(grid)
	if not _has_unified_overlays():
		_draw_move_highlight_outlines()
	if _has_unified_overlays():
		_draw_overlay_routes()
	_draw_editor_preview()
	if _has_unified_overlays():
		_draw_unified_overlay_outlines()
	if hover_cell.x >= 0:
		var hover_unit := state.get_unit_at(hover_cell)
		if hover_unit == null or not hover_unit.alive:
			TileRenderer.draw_hover_outline(self, grid_to_screen(hover_cell), _cell_hover_outline_color())
	for grid in _sorted_cells():
		_draw_entity_at_grid(grid, drawn_entities)
		if state.get_unit_at(grid) == null and state.get_entity_at(grid) != null:
			_draw_front_tile_overlay_at(grid, true)
		_draw_dropped_gems_at_grid(grid)
	_draw_unit_ground_outlines()
	_draw_gem_visuals(false)
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive and not drawn_units.has(unit.uid):
			drawn_units[unit.uid] = true
			_draw_unit_body(unit)
		if unit != null and unit.alive:
			_draw_front_tile_overlay_at(grid, true)
	for grid in _sorted_cells():
		var entity := state.get_entity_at(grid)
		if entity != null and entity.alive and not drawn_entity_ui.has(entity.uid):
			drawn_entity_ui[entity.uid] = true
			_draw_entity_ui(entity)
	var drawn_unit_ui: Dictionary = {}
	for grid in _sorted_cells():
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive and not drawn_unit_ui.has(unit.uid):
			drawn_unit_ui[unit.uid] = true
			_draw_unit_ui(unit)
	if not _has_unified_overlays():
		_draw_highlight_outlines()
	_draw_gem_visuals(true)
	_draw_unit_slot_panels()


func _ensure_combat_visual_layers() -> void:
	if _beam_layer == null:
		_beam_layer = Control.new()
		_beam_layer.name = "BeamLayer"
		_beam_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_beam_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_beam_layer)
	if _light_beam_fx == null:
		_light_beam_fx = BattleLightBeamFx.new()
		_light_beam_fx.name = "LightBeamFx"
		_light_beam_fx.configure(Callable(self, "grid_to_screen"))
		_beam_layer.add_child(_light_beam_fx)
	if _projectile_fx == null:
		_projectile_fx = BattleProjectileFx.new()
		_projectile_fx.name = "ProjectileFx"
		_projectile_fx.configure(Callable(self, "grid_to_screen"))
		_projectile_fx.finished.connect(_on_projectile_fx_finished)
		_beam_layer.add_child(_projectile_fx)
	if _particle_fx == null:
		_particle_fx = BattleParticleFx.new()
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
	_ensure_combat_visual_layers()
	if _beam_layer == null or shader == null:
		return null
	_shader_fx_seed += 1
	var rect := ColorRect.new()
	rect.name = "ShaderFx"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	rect.size = fx_size
	rect.position = center - fx_size * 0.5
	rect.pivot_offset = fx_size * 0.5
	rect.rotation = rotation
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("seed", float(_shader_fx_seed))
	for key in params.keys():
		material.set_shader_parameter(str(key), params[key])
	rect.material = material
	_beam_layer.add_child(rect)
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
			rect.queue_free()
	)
	return rect


func _ensure_water_layers() -> void:
	if _water_fill_layer != null:
		return
	_water_fill_layer = WaterLayerClass.new()
	_water_fill_layer.name = "WaterFillLayer"
	_water_fill_layer.layer_kind = WaterLayerClass.LayerKind.FILL
	_water_fill_layer.fill_image_top = _load_generated_image("res://assets/tiles/waterMaskTop.generated.png")
	_water_fill_layer.fill_image_right = _load_generated_image("res://assets/tiles/waterMaskRight.generated.png")
	_water_fill_layer.show_behind_parent = true
	_water_fill_layer.z_index = 0
	var fill_material := ShaderMaterial.new()
	fill_material.shader = WaterTileShader
	fill_material.set_shader_parameter("base_color", Color("95e9fa"))
	fill_material.set_shader_parameter("water_bottom", WATER_BOTTOM)
	fill_material.set_shader_parameter("water_top", WATER_TOP)
	_water_fill_layer.material = fill_material
	add_child(_water_fill_layer)

	_water_edge_layer = WaterLayerClass.new()
	_water_edge_layer.name = "WaterEdgeLayer"
	_water_edge_layer.layer_kind = WaterLayerClass.LayerKind.EDGE
	_water_edge_layer.edge_image_top = _load_generated_image("res://assets/tiles/waterEdgeTop.generated.png")
	_water_edge_layer.edge_image_right = _load_generated_image("res://assets/tiles/waterEdgeRight.generated.png")
	_water_edge_layer.show_behind_parent = true
	_water_edge_layer.z_index = 0
	add_child(_water_edge_layer)


func _load_generated_texture(path: String) -> Texture2D:
	var image := _load_generated_image(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


func _load_generated_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null


func _clear_water_visuals() -> void:
	_water_visual_signature = -1
	if _water_fill_layer != null:
		_water_fill_layer.set_cells([])
	if _water_edge_layer != null:
		_water_edge_layer.set_cells([])


func _sync_water_visuals() -> void:
	_ensure_water_layers()
	if state == null:
		_clear_water_visuals()
		return
	var water := _water_cell_set()
	var signature := hash([
		state.get_instance_id(),
		IsoCoordinates.tile_scale,
		_board_origin,
		invert_origin,
		state.tiles.size(),
	])
	for tile in state.tiles.values():
		if tile == null or tile.tile_id != Constants.TILE_WATER:
			continue
		var edge_states := WaterAutotileClass.states(tile.pos, water)
		signature = hash(Vector4i(signature, hash(tile.pos), hash(edge_states), 0))
	if signature == _water_visual_signature:
		return

	var cells: Array = []
	for tile in state.tiles.values():
		if tile == null or tile.tile_id != Constants.TILE_WATER:
			continue
		var edge_states := WaterAutotileClass.states(tile.pos, water)
		var cell := {
			"center": grid_to_screen(tile.pos),
			"half_w": IsoCoordinates._half_w(),
			"half_h": IsoCoordinates._half_h(),
			"top": edge_states.x,
			"right": edge_states.y,
			"bottom": edge_states.z,
			"left": edge_states.w,
		}
		cells.append(cell)
	_water_visual_signature = signature
	_water_fill_layer.set_cells(cells)
	_water_edge_layer.set_cells(cells)


func _water_cell_set() -> Dictionary:
	var water := {}
	for tile in state.tiles.values():
		if tile != null and tile.tile_id == Constants.TILE_WATER:
			water[tile.pos] = true
	return water


func configure_unit_slot_panels(action: String, check_fn: Callable = Callable()) -> void:
	slot_panel_action = action
	slot_panel_check = check_fn
	_slot_hover_unit_uid = ""
	_slot_hover_index = -1
	queue_redraw()


func set_slot_hover(screen_pos: Vector2) -> void:
	var hit := pick_unit_slot(screen_pos)
	var uid := str(hit.get("unit_uid", ""))
	var idx := int(hit.get("slot_index", -1))
	if uid == _slot_hover_unit_uid and idx == _slot_hover_index:
		return
	_slot_hover_unit_uid = uid
	_slot_hover_index = idx
	queue_redraw()


func clear_unit_slot_panels() -> void:
	configure_unit_slot_panels("")


func pick_unit_slot(screen_pos: Vector2) -> Dictionary:
	if state == null or slot_panel_action.is_empty():
		return {}
	for unit: UnitState in state.units.values():
		if unit == null or not unit.alive or unit.slots.is_empty():
			continue
		if not _unit_slot_panel_in_range(unit):
			continue
		var panel := _unit_slot_panel_layout(unit)
		for item in panel.get("items", []):
			var item_dict: Dictionary = item
			if not bool(item_dict.get("visible", true)) or not bool(item_dict.get("enabled", false)):
				continue
			if _point_in_slot_sector(screen_pos, item_dict):
				return {
					"unit_uid": unit.uid,
					"slot_index": int(item_dict.get("slot_index", -1)),
				}
	return {}


func _draw_entity_at_grid(grid: Vector2i, drawn_entities: Dictionary) -> void:
	var entity := state.get_entity_at(grid)
	if entity == null or not entity.alive or drawn_entities.has(entity.uid):
		return
	drawn_entities[entity.uid] = true
	var center := grid_to_screen(entity.pos)
	match entity.entity_id:
		Constants.ENTITY_SPIKE:
			TileRenderer.draw_entity_texture(self, center, ENTITY_SPIKE_TEXTURE, 0.86)
		Constants.ENTITY_PROP:
			_draw_prop_entity(entity, center)
		Constants.ENTITY_ROCK:
			TileRenderer.draw_entity_texture(self, center, ENTITY_ROCK_TEXTURE, 0.72)
		Constants.ENTITY_BARREL:
			TileRenderer.draw_entity_texture(self, center, ENTITY_BARREL_TEXTURE, 0.78)
		_:
			TileRenderer.draw_prop_fallback(self, center)


func _draw_dropped_gems_at_grid(grid: Vector2i) -> void:
	if state == null or _gem_sprites == null:
		return
	var drops: Array[Dictionary] = []
	for raw_drop in state.dropped_gems.values():
		if not raw_drop is Dictionary:
			continue
		var drop := raw_drop as Dictionary
		if drop.get("pos", Vector2i(-999, -999)) == grid:
			drops.append(drop)
	if drops.is_empty():
		return
	drops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("gem_uid", "")) < str(b.get("gem_uid", ""))
	)
	var center := grid_to_screen(grid) + Vector2(0.0, IsoCoordinates.visual(4.0))
	var spacing := IsoCoordinates.visual(12.0)
	var size := IsoCoordinates.visual(13.0)
	var start_x := -spacing * float(drops.size() - 1) * 0.5
	for i in range(drops.size()):
		var gem_uid := str(drops[i].get("gem_uid", ""))
		var gem: GemState = state.gems.get(gem_uid, null)
		if gem == null:
			continue
		var pos := center + Vector2(start_x + spacing * float(i), 0.0)
		_draw_soft_backdrop(pos + Vector2(0.0, IsoCoordinates.visual(5.0)), size * 0.55, size * 0.24, Color(0.0, 0.0, 0.0, 0.42))
		var tex: Texture2D = _gem_sprites.texture_for_gem_id(gem.gem_id)
		var tint: Color = _gem_sprites.modulate_for_gem_id(gem.gem_id)
		if tex != null:
			draw_texture_rect(tex, Rect2(pos - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, tint)
		else:
			_draw_small_diamond(pos, size * 0.42, size * 0.32, tint)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("battle_editor_tool"):
		return false
	var cell := pick_cell(at_position)
	var has_cell := cell.x >= 0
	editor_tool_drag_hovered.emit(data.get("battle_editor_tool", {}), cell, has_cell)
	return has_cell


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary or not data.has("battle_editor_tool"):
		return
	var cell := pick_cell(at_position)
	editor_tool_dropped.emit(data.get("battle_editor_tool", {}), cell, cell.x >= 0)


func _draw_prop_entity(entity: EntityState, center: Vector2) -> void:
	if _prop_sprites == null or entity.prop_sprite.is_empty():
		TileRenderer.draw_prop_fallback(self, center)
		return
	var tex: Texture2D = _prop_sprites.texture_for_sprite_id(entity.prop_sprite)
	if tex == null:
		TileRenderer.draw_prop_fallback(self, center)
		return
	var foot_ratio: float = _prop_sprites.foot_ratio_for_sprite_id(entity.prop_sprite)
	TileRenderer.draw_prop_sprite(self, center, tex, foot_ratio)


func _draw_entity_ui(entity: EntityState) -> void:
	if entity.max_hp <= 0:
		return
	var center := grid_to_screen(entity.pos)
	var foot := center + IsoCoordinates.entity_foot_offset()
	var width := IsoCoordinates.visual(30.0)
	var height := IsoCoordinates.visual(4.0)
	var top := foot.y - IsoCoordinates.visual(65.0)
	BattleUiTheme.draw_combined_hp_bar(
		self,
		Rect2(foot.x - width * 0.5, top, width, height),
		entity.hp,
		entity.max_hp,
		0
	)


func _draw_move_highlight_outlines() -> void:
	var reachable: Array = highlights.get("reachable", [])
	if reachable.is_empty():
		return
	var outline: Color = _reachable_outline_color()
	var hover_outline: Color = _hover_outline_color()
	for grid in reachable:
		var cell: Vector2i = grid
		var is_hovered: bool = (cell == hover_cell)
		var color: Color = hover_outline if is_hovered else outline
		var width: float = IsoCoordinates.visual(2.0 if is_hovered else 1.5)
		_draw_cell_outline(cell, color, width)


func _draw_editor_preview() -> void:
	if not editor_preview_active or editor_preview_cells.is_empty():
		return
	var outline := Color(UiPalette.HILITE_REACH, 0.96) if editor_preview_valid else Color(UiPalette.HILITE_DANGER, 0.96)
	var fill := Color(UiPalette.HILITE_REACH, 0.22) if editor_preview_valid else Color(UiPalette.HILITE_DANGER, 0.2)
	for cell in editor_preview_cells:
		var corners := IsoCoordinates.diamond_corners(grid_to_screen(cell))
		draw_colored_polygon(corners, fill)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, outline, IsoCoordinates.visual(2.0), false)


func _draw_highlight_outlines() -> void:
	var attack_range: Array = highlights.get("attack_range", [])
	var targets: Array = highlights.get("targets", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	for grid in attack_range:
		var c := Color(UiPalette.HILITE_REACH, 0.45 + pulse * 0.25)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.6))
	for grid in targets:
		var c := Color(UiPalette.HILITE_TARGET, 0.55 + pulse * 0.35)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.8))
	for grid in danger:
		var c := Color(UiPalette.HILITE_DANGER, 0.5 + pulse * 0.35)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.8))
	for grid in effect_list:
		var c := Color(UiPalette.HILITE_RANGE, 0.45 + pulse * 0.3)
		_draw_cell_outline(grid, c, IsoCoordinates.visual(1.5))


func _has_unified_overlays() -> bool:
	var overlays: Array = highlights.get("overlays", [])
	var routes: Array = highlights.get("routes", [])
	return not overlays.is_empty() or not routes.is_empty()


func _draw_unified_overlay_outlines() -> void:
	var overlays: Array = highlights.get("overlays", [])
	if overlays.is_empty():
		return
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	for raw_overlay in overlays:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var kind := str(overlay.get("kind", ""))
		var cells: Array = overlay.get("cells", [])
		if cells.is_empty():
			continue
		var base_color := _overlay_outline_color(kind, pulse)
		var base_width := _overlay_line_width(kind)
		for raw_cell in cells:
			var cell: Vector2i = raw_cell
			var color := base_color
			var width := base_width
			if cell == hover_cell:
				color = color.lightened(0.18)
				color.a = minf(1.0, color.a + 0.12)
				width += IsoCoordinates.visual(0.6)
			_draw_cell_outline(cell, color, width)


func _draw_map_room_nameplates() -> void:
	if state == null or state.encounter_id != "adventure_map":
		return
	var cells: Dictionary = {}
	var overlays: Array = highlights.get("overlays", [])
	for raw_overlay in overlays:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var kind := str(overlay.get("kind", ""))
		if kind not in ["map_current", "map_choice", "map_focus"]:
			continue
		var priority := 2 if kind == "map_current" else (1 if kind == "map_focus" else 0)
		for raw_cell in overlay.get("cells", []):
			var cell: Vector2i = raw_cell
			cells[cell] = maxi(int(cells.get(cell, -1)), priority)
	if state.get_tile(hover_cell) != null:
		cells[hover_cell] = 3
	for cell in cells.keys():
		var tile := state.get_tile(cell)
		if tile == null or not AdventureRoomDisplay.is_room_tile(tile.tile_id):
			continue
		var display: Dictionary = AdventureRoomDisplay.get_display(
			AdventureRoomDisplay.room_type_from_tile(tile.tile_id),
			AdventureService.get_current_chapter(),
			AdventureService.get_chapter_count()
		)
		var color: Color = display.get("color", UiPalette.ROOM_UNKNOWN)
		_draw_map_room_nameplate(cell, str(display.get("label", "")), color, int(cells[cell]))


func _draw_map_room_nameplate(cell: Vector2i, label: String, color: Color, priority: int) -> void:
	if label.is_empty():
		return
	var font := BattleUiTheme.pixel_font()
	var font_size := 11 if priority < 2 else 12
	var center := grid_to_screen(cell)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := IsoCoordinates.visual_vec(Vector2(5.0, 3.0))
	var rect := Rect2(
		center.x - text_size.x * 0.5 - pad.x,
		center.y + IsoCoordinates.visual(7.0),
		text_size.x + pad.x * 2.0,
		text_size.y + pad.y * 2.0
	)
	var bg_alpha := 0.72 if priority < 2 else 0.86
	draw_rect(rect, Color(UiPalette.BG_INSET, bg_alpha), true)
	draw_rect(rect, Color(color.lightened(0.08), 0.55 + float(priority) * 0.08), false, IsoCoordinates.visual(1.0))
	var text_pos := Vector2(rect.position.x + pad.x, rect.position.y + text_size.y + pad.y * 0.3)
	_draw_text_with_shadow(font, text_pos, label, font_size, UiPalette.TEXT_BRIGHT, UiPalette.TEXT_OUTLINE)


func _draw_overlay_routes() -> void:
	var routes: Array = highlights.get("routes", [])
	if routes.is_empty():
		return
	for raw_route in routes:
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var path: Array = route.get("path", [])
		if path.size() < 2:
			continue
		var points := PackedVector2Array()
		for raw_cell in path:
			var cell: Vector2i = raw_cell
			points.append(grid_to_screen(cell))
		if points.size() < 2:
			continue
		var kind := str(route.get("kind", ""))
		var color := _route_color(kind)
		var width := IsoCoordinates.visual(3.2 if kind == "move" else 3.0)
		var outline := Color(0.02, 0.04, 0.06, minf(0.5, color.a + 0.18))
		draw_polyline(points, outline, width + IsoCoordinates.visual(2.0), true)
		draw_polyline(points, color, width, true)
		_draw_route_arrow(points, color, width, bool(route.get("arrow_reverse", false)))


func _draw_route_arrow(points: PackedVector2Array, color: Color, width: float, reverse_direction: bool) -> void:
	if points.size() < 2:
		return
	var end_pos: Vector2 = points[points.size() - 1]
	var prev_pos: Vector2 = points[points.size() - 2]
	var direction: Vector2 = prev_pos - end_pos if reverse_direction else end_pos - prev_pos
	if direction.length() < 0.01:
		return
	direction = direction.normalized()
	var perp := Vector2(-direction.y, direction.x)
	var tip := end_pos
	var base := end_pos - direction * IsoCoordinates.visual(10.0)
	var left := base + perp * IsoCoordinates.visual(5.5)
	var right := base - perp * IsoCoordinates.visual(5.5)
	var chevron := PackedVector2Array([left, tip, right])
	var outline := Color(0.02, 0.04, 0.06, minf(0.55, color.a + 0.2))
	draw_polyline(chevron, outline, width + IsoCoordinates.visual(2.0), true)
	draw_polyline(chevron, color, width, true)


func _draw_tile(grid: Vector2i) -> void:
	var center := grid_to_screen(grid)
	var tile := state.get_tile(grid)
	var highlight := _tile_highlight(grid)
	# 地砖底由 Grids 贴图统一绘制，这里只叠加高亮与特殊地块（水/柱/毒/火等）
	TileRenderer.draw_tile_overlays(self, center, tile, highlight, TileRenderer.PASS_BACK, false)


func _draw_front_tile_overlay_at(grid: Vector2i, occupied: bool = false) -> void:
	if not occupied:
		var unit := state.get_unit_at(grid)
		if unit != null and unit.alive:
			occupied = true
		elif state.get_entity_at(grid) != null:
			occupied = true
	if not occupied:
		return
	var tile := state.get_tile(grid)
	if tile == null:
		return
	TileRenderer.draw_tile_overlays(
		self,
		grid_to_screen(grid),
		tile,
		Color.TRANSPARENT,
		TileRenderer.PASS_FRONT,
		true
	)


func _tile_highlight(grid: Vector2i) -> Color:
	var overlays: Array = highlights.get("overlays", [])
	if not overlays.is_empty():
		return _tile_overlay_highlight(grid, overlays)
	var reachable: Array = highlights.get("reachable", [])
	var attack_range: Array = highlights.get("attack_range", [])
	var targets: Array = highlights.get("targets", [])
	var paths: Array = highlights.get("paths", [])
	var danger: Array = highlights.get("danger", [])
	var effect_list: Array = highlights.get("effect_preview", [])
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	if grid in effect_list:
		var a: float = 0.5 + pulse * 0.22
		return Color(UiPalette.HILITE_DANGER, a)
	if grid in reachable:
		var move_a: float = 0.28 + pulse * 0.12
		return Color(UiPalette.HILITE_REACH, move_a)
	if grid in attack_range:
		var a: float = 0.28 + pulse * 0.12
		return Color(UiPalette.HILITE_REACH, a)
	if grid in targets:
		var a: float = 0.52 + pulse * 0.22
		return Color(UiPalette.HILITE_TARGET, a)
	if grid in danger:
		var a: float = 0.42 + pulse * 0.22
		return Color(UiPalette.HILITE_DANGER, a)
	if grid in paths:
		return Color(UiPalette.HILITE_RANGE, 0.24 + pulse * 0.1)
	return Color.TRANSPARENT


func _tile_overlay_highlight(grid: Vector2i, overlays: Array) -> Color:
	var best_kind := ""
	var best_priority := -999
	for raw_overlay in overlays:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var cells: Array = overlay.get("cells", [])
		if not grid in cells:
			continue
		var kind := str(overlay.get("kind", ""))
		var priority := _overlay_priority(kind)
		if priority >= best_priority:
			best_priority = priority
			best_kind = kind
	if best_kind.is_empty():
		return Color.TRANSPARENT
	var pulse: float = (sin(_anim.pulse_time * 3.2) * 0.5 + 0.5)
	var base := _overlay_base_color(best_kind)
	var alpha := _overlay_fill_alpha(best_kind, pulse)
	if grid == hover_cell:
		alpha = minf(0.78, alpha + 0.14)
	return Color(base, alpha)


func _overlay_priority(kind: String) -> int:
	match kind:
		"danger":
			return 90
		"effect":
			return 80
		"target":
			return 70
		"map_focus":
			return 68
		"map_current":
			return 66
		"map_choice":
			return 60
		"map_future":
			return 24
		"intent_path":
			return 50
		"attack_range":
			return 40
		"move":
			return 30
		"map_resolved":
			return 10
	return 0


func _overlay_base_color(kind: String) -> Color:
	match kind:
		"move":
			return UiPalette.HILITE_MOVE
		"attack_range":
			return UiPalette.HILITE_RANGE.darkened(0.08)
		"target":
			return UiPalette.HILITE_TARGET
		"danger":
			return UiPalette.HILITE_DANGER
		"effect":
			return UiPalette.FIRE_ORANGE
		"intent_path":
			return UiPalette.INTENT_MOVE
		"map_focus":
			return UiPalette.TEXT_GOLD
		"map_current":
			return UiPalette.ROOM_START
		"map_choice":
			return UiPalette.ROOM_EXIT
		"map_future":
			return UiPalette.EDGE_BRIGHT
		"map_resolved":
			return UiPalette.EDGE_LIGHT
	return UiPalette.TEXT_BRIGHT


func _overlay_fill_alpha(kind: String, pulse: float) -> float:
	match kind:
		"danger":
			return 0.34 + pulse * 0.18
		"effect":
			return 0.32 + pulse * 0.16
		"target":
			return 0.32 + pulse * 0.18
		"map_focus":
			return 0.30 + pulse * 0.16
		"map_current":
			return 0.36 + pulse * 0.16
		"map_choice":
			return 0.26 + pulse * 0.14
		"map_future":
			return 0.14 + pulse * 0.06
		"intent_path":
			return 0.18 + pulse * 0.12
		"attack_range":
			return 0.20 + pulse * 0.10
		"move":
			return 0.22 + pulse * 0.10
		"map_resolved":
			return 0.10
	return 0.18


func _overlay_outline_color(kind: String, pulse: float) -> Color:
	var base := _overlay_base_color(kind)
	var alpha: float = 0.62 + pulse * 0.22
	match kind:
		"move":
			alpha = 0.58 + pulse * 0.18
		"attack_range", "intent_path":
			alpha = 0.48 + pulse * 0.18
		"map_future":
			alpha = 0.26 + pulse * 0.08
		"map_resolved":
			alpha = 0.28
		"map_current", "map_choice", "map_focus", "target", "danger", "effect":
			alpha = 0.72 + pulse * 0.22
	return Color(base, alpha)


func _overlay_line_width(kind: String) -> float:
	match kind:
		"target", "danger", "effect", "map_current", "map_focus":
			return IsoCoordinates.visual(2.0)
		"map_choice":
			return IsoCoordinates.visual(1.8)
		"map_future":
			return IsoCoordinates.visual(1.2)
		"move", "attack_range", "intent_path":
			return IsoCoordinates.visual(1.45)
	return IsoCoordinates.visual(1.3)


func _route_color(kind: String) -> Color:
	match kind:
		"move":
			return Color(0.72, 0.96, 1.0, 0.82)
		"intent":
			return Color(UiPalette.INTENT_ATTACK.lightened(0.08), 0.36)
		"map_focus":
			return Color(UiPalette.TEXT_GOLD.lightened(0.06), 0.82)
		"map_choice":
			return Color(UiPalette.ROOM_EXIT.lightened(0.14), 0.32)
		"map_future":
			return Color(UiPalette.EDGE_BRIGHT, 0.22)
	return Color(UiPalette.TEXT_BRIGHT, 0.34)


func _unit_draw_context(unit: UnitState) -> Dictionary:
	# 坑2：多格单位的视觉中心（及 Y-Sort 锚点）必须是 footprint 右下角格的屏幕坐标
	# 而非左上角锚点，否则站在大单位右下方的小单位会被错误遮挡
	var fp := unit.footprint_size
	var visual_anchor_grid := unit.pos + fp - Vector2i(1, 1) # footprint 右下角格
	var center := grid_to_screen(visual_anchor_grid)
	# 多格时水平中心取 footprint 宽度的屏幕跨度中点
	if fp != Vector2i(1, 1):
		var anchor_left := grid_to_screen(unit.pos)
		center.x = (anchor_left.x + center.x) * 0.5
	var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var facing := unit.facing
	var tint := UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	if _anim.hit_elapsed.has(unit.uid):
		var hit_progress := clampf(
			float(_anim.hit_elapsed[unit.uid]) / _HIT_DURATION,
			0.0,
			1.0
		)
		tint = tint.lerp(Color(1.0, 0.58, 0.58, 1.0), (1.0 - hit_progress) * 0.72)
	var pose: Dictionary = _resolve_unit_pose(unit, facing)
	var pose_tex: Texture2D = pose.get("texture", null)
	var sprite_size: Vector2 = pose.get("sprite_size", Vector2.ZERO)
	var layout := _unit_sprite_layout(unit, center, sprite_size)
	return {
		"center": center,
		"offset": offset,
		"tint": tint,
		"pose_tex": pose_tex,
		"sprite_size": sprite_size,
		"top_left": layout["top_left"],
		"ground_nudge": layout["ground_nudge"],
	}


func _draw_unit_body(unit: UnitState) -> void:
	var ctx := _unit_draw_context(unit)
	var center: Vector2 = ctx["center"]
	var offset: Vector2 = ctx["offset"]
	var tint: Color = ctx["tint"]
	var pose_tex: Texture2D = ctx["pose_tex"]
	var sprite_size: Vector2 = ctx["sprite_size"]
	var top_left: Vector2 = ctx["top_left"]
	var ground_nudge: Vector2 = ctx["ground_nudge"]
	_draw_unit_shadow(unit, center, ground_nudge, sprite_size)

	var aura_alpha := float(_active_aura_alpha_by_uid.get(unit.uid, 0.0))
	if aura_alpha > 0.01 and not _uses_player_sprite(unit) and not _uses_slime_sprite(unit):
		var aura_center := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(2.0))
		_draw_active_turn_aura(unit, aura_center, aura_alpha)
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	var hover_alpha := float(_hover_outline_alpha_by_uid.get(unit.uid, 0.0))
	if pose_tex != null:
		if hover_alpha > 0.01:
			_draw_unit_texture_outline(pose_tex, Rect2(top_left, sprite_size), hover_alpha)
		draw_texture_rect(pose_tex, Rect2(top_left, sprite_size), false, tint)
	elif hover_alpha > 0.01:
		_draw_unit_focus_outline(unit, Color(UiPalette.TEXT_BRIGHT, 0.92), IsoCoordinates.visual(1.8), offset, 0.0, hover_alpha)


func _draw_unit_ui(unit: UnitState) -> void:
	var ctx := _unit_draw_context(unit)
	var center: Vector2 = ctx["center"]
	var sprite_size: Vector2 = ctx["sprite_size"]
	var ground_nudge: Vector2 = ctx["ground_nudge"]
	var hp_bar_pos := center + IsoCoordinates.visual_vec(Vector2(-18, 6))
	var name_alpha := float(_nameplate_alpha_by_uid.get(unit.uid, 0.0))
	if name_alpha > 0.01:
		_draw_unit_nameplate(unit, Vector2(hp_bar_pos.x + IsoCoordinates.visual(18.0), hp_bar_pos.y - IsoCoordinates.visual(4.0)), name_alpha)
	_draw_unit_statuses(unit, hp_bar_pos + Vector2(0, IsoCoordinates.visual(8.0)))
	_draw_gem_icons(unit, hp_bar_pos)
	var shield_value := StatusRules.get_shield(unit)
	_draw_hp_bar(hp_bar_pos, unit, shield_value)
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		_draw_intent_badge(center + Vector2(0, -sprite_size.y + IsoCoordinates.visual(8.0)) + ground_nudge, unit.intent)


func _unit_sprite_size(unit: UnitState) -> Vector2:
	var sprite_size := IsoCoordinates.visual_vec(Vector2(62.0, 70.0))
	var fp := unit.footprint_size
	if fp != Vector2i(1, 1):
		sprite_size *= Vector2(float(fp.x), float(fp.y)).length() * 0.8
	return sprite_size


func _uses_player_sprite(unit: UnitState) -> bool:
	return unit.unit_def_id == "unit_player"


func _uses_slime_sprite(unit: UnitState) -> bool:
	return unit.unit_def_id == "unit_fission_slime"


func _uses_animated_idle(unit: UnitState) -> bool:
	return _uses_player_sprite(unit) or _uses_slime_sprite(unit)


func _unit_sprite_layout(unit: UnitState, center: Vector2, sprite_size: Vector2) -> Dictionary:
	var ground_y := _UNIT_SPRITE_GROUND_OFFSET_Y
	var foot_extra_y := 2.0
	if _uses_slime_sprite(unit):
		ground_y = _SLIME_SPRITE_GROUND_OFFSET_Y
		foot_extra_y = 0.0
	var ground_nudge := Vector2(0.0, IsoCoordinates.visual(ground_y))
	var foot := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(foot_extra_y))
	var top_left := Vector2(foot.x - sprite_size.x * 0.5, foot.y - sprite_size.y)
	return {"top_left": top_left, "ground_nudge": ground_nudge, "foot": foot}


func _strike_duration_for(unit_uid: String) -> float:
	if state == null:
		return _KNIGHT_STRIKE_DURATION
	var unit: UnitState = state.units.get(unit_uid, null)
	if unit != null and _uses_player_sprite(unit):
		return _PLAYER_STRIKE_DURATION
	if unit != null and _uses_slime_sprite(unit):
		return _SLIME_STRIKE_DURATION
	return _KNIGHT_STRIKE_DURATION


func _unit_shadow_texture(unit: UnitState) -> Texture2D:
	if _uses_slime_sprite(unit):
		return null
	if _uses_player_sprite(unit) and _player_sprites != null:
		return _player_sprites.texture_shadow()
	if _knight_sprites != null:
		return _knight_sprites.texture_shadow()
	return null


func _draw_unit_shadow(unit: UnitState, center: Vector2, ground_nudge: Vector2, sprite_size: Vector2) -> void:
	if _uses_slime_sprite(unit):
		if _player_sprites == null:
			return
		var sdw: Texture2D = _player_sprites.texture_shadow()
		if sdw == null:
			return
		var foot: Vector2 = center + ground_nudge
		var sh_sz := Vector2(sprite_size.x * 0.58, IsoCoordinates.visual(9.0))
		var sh_tl := Vector2(foot.x - sh_sz.x * 0.5, foot.y - sh_sz.y * 0.68)
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.32))
		return
	var sdw: Texture2D = _unit_shadow_texture(unit)
	if sdw == null:
		return
	if _uses_player_sprite(unit):
		var foot := center + ground_nudge + Vector2(0.0, IsoCoordinates.visual(2.0))
		var sh_sz := Vector2(sprite_size.x * 0.72, IsoCoordinates.visual(10.0))
		var sh_tl := Vector2(foot.x - sh_sz.x * 0.5, foot.y - sh_sz.y * 0.55)
		draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.34))
		return
	var sh_sz := Vector2(sprite_size.x * 0.82, sprite_size.y * 0.24)
	var sh_tl := center + Vector2(-sh_sz.x * 0.5, -IsoCoordinates.visual(2.0)) + ground_nudge
	draw_texture_rect(sdw, Rect2(sh_tl, sh_sz), false, Color(1, 1, 1, 0.42))


func _resolve_unit_pose(unit: UnitState, facing: String) -> Dictionary:
	if _uses_player_sprite(unit):
		return _resolve_player_pose(unit.uid, facing)
	if _uses_slime_sprite(unit):
		return _resolve_slime_pose(unit, facing)
	return _resolve_knight_pose(unit, facing)


func _resolve_player_pose(unit_uid: String, facing: String) -> Dictionary:
	if _player_sprites == null:
		return {}
	var anim := "Idle"
	var idle_t: float = float(_anim.idle_phase.get(unit_uid, 0.0))
	var frame := int(idle_t * _PLAYER_IDLE_FPS) % _PLAYER_IDLE_FRAMES
	if _anim.hit_elapsed.has(unit_uid):
		anim = "Dash"
		frame = 6
	elif _anim.strike_elapsed.has(unit_uid):
		anim = "Dash"
		var st: float = float(_anim.strike_elapsed[unit_uid])
		frame = clampi(
			int(st / (_PLAYER_STRIKE_DURATION / float(_PLAYER_STRIKE_FRAMES))),
			0,
			_PLAYER_STRIKE_FRAMES - 1
		)
	elif _anim.move_offsets.has(unit_uid):
		anim = "Walk"
		var walk_t: float = float(_anim.walk_phase.get(unit_uid, 0.0))
		frame = int(walk_t * _PLAYER_WALK_FPS) % _PLAYER_WALK_FRAMES
	var pose: Dictionary = _player_sprites.pose_frame(facing, anim, frame)
	if pose.is_empty():
		return {}
	var draw_size: Vector2 = pose.get("draw_size", Vector2.ZERO)
	return {
		"texture": pose.get("texture", null),
		"sprite_size": IsoCoordinates.visual_vec(draw_size),
	}


func _resolve_slime_pose(unit: UnitState, facing: String) -> Dictionary:
	if _slime_sprites == null:
		return {}
	var display_facing := facing
	if not _anim.strike_elapsed.has(unit.uid) and not _anim.move_offsets.has(unit.uid):
		display_facing = _slime_display_facing(unit, facing)
	var anim := "Idle"
	var idle_t: float = float(_anim.idle_phase.get(unit.uid, 0.0))
	var frame := int(idle_t * _SLIME_IDLE_FPS) % _SLIME_IDLE_FRAMES
	if _anim.hit_elapsed.has(unit.uid):
		anim = "Strike"
		frame = 4
	elif _anim.strike_elapsed.has(unit.uid):
		anim = "Strike"
		var st: float = float(_anim.strike_elapsed[unit.uid])
		frame = clampi(
			int(st / (_SLIME_STRIKE_DURATION / float(_SLIME_STRIKE_FRAMES))),
			0,
			_SLIME_STRIKE_FRAMES - 1
		)
	elif _anim.move_offsets.has(unit.uid):
		anim = "Walk"
		var walk_t: float = float(_anim.walk_phase.get(unit.uid, 0.0))
		frame = int(walk_t * _SLIME_WALK_FPS) % _SLIME_ANIM_FRAMES
	var pose: Dictionary = _slime_sprites.pose_frame(display_facing, anim, frame)
	if pose.is_empty():
		return {}
	var base_size := IsoCoordinates.visual_vec(Vector2(62.0, 70.0))
	var sprite_size := _unit_sprite_size(unit)
	var scale := sprite_size / base_size
	var draw_size: Vector2 = pose.get("draw_size", Vector2.ZERO) * scale
	return {
		"texture": pose.get("texture", null),
		"sprite_size": draw_size,
	}


func _slime_display_facing(unit: UnitState, fallback: String) -> String:
	if state == null:
		return fallback
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return fallback
	return _facing_from_screen_delta(
		_get_unit_screen_center(unit),
		_get_unit_screen_center(player),
		fallback
	)


func _resolve_knight_pose(unit: UnitState, facing: String) -> Dictionary:
	var tex: Texture2D = null
	if _knight_sprites == null:
		return {}
	if _anim.hit_elapsed.has(unit.uid):
		tex = _knight_sprites.texture_hurt(facing)
	elif _anim.strike_elapsed.has(unit.uid):
		var st: float = float(_anim.strike_elapsed[unit.uid])
		var fidx := clampi(int(st / (0.28 / 3.0)), 0, 2)
		tex = _knight_sprites.texture_sword_swing(facing, fidx)
	elif _anim.move_offsets.has(unit.uid):
		var wfr := int(float(_anim.walk_phase.get(unit.uid, 0.0)) * _SLIME_WALK_FPS) % 3
		tex = _knight_sprites.texture_walk(facing, wfr)
	else:
		tex = _knight_sprites.texture_walk(facing, 0)
	return {"texture": tex, "sprite_size": _unit_sprite_size(unit)}


func _draw_cell_outline(grid: Vector2i, color: Color, line_width: float) -> void:
	var corners: PackedVector2Array = IsoCoordinates.diamond_corners(grid_to_screen(grid))
	var closed: PackedVector2Array = corners.duplicate()
	closed.append(corners[0])
	draw_polyline(closed, color, line_width, false)


func _reachable_outline_color() -> Color:
	return Color(UiPalette.TEXT_BRIGHT, 0.92)


func _hover_outline_color() -> Color:
	return Color(UiPalette.HILITE_REACH.lightened(0.4), 0.98)


func _cell_hover_outline_color() -> Color:
	var reachable: Array = highlights.get("reachable", [])
	return _hover_outline_color() if hover_cell in reachable else Color(UiPalette.TEXT_BRIGHT, 0.95)


func _draw_unit_ground_outlines() -> void:
	for unit: UnitState in state.units.values():
		if not unit.alive:
			continue
		var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
		var selection_alpha := float(_selection_outline_alpha_by_uid.get(unit.uid, 0.0))
		if selection_alpha > 0.01:
			_draw_unit_focus_outline(unit, Color(UiPalette.TEXT_BRIGHT, 0.92), IsoCoordinates.visual(1.8), offset, 0.0, selection_alpha)


func _draw_unit_texture_outline(texture: Texture2D, rect: Rect2, alpha: float) -> void:
	if texture == null or alpha <= 0.01:
		return
	var px := maxf(1.0, IsoCoordinates.visual(2.0))
	var outline := Color(UiPalette.TEXT_BRIGHT, 0.82 * alpha)
	var offsets := [
		Vector2(-px, 0.0),
		Vector2(px, 0.0),
		Vector2(0.0, -px),
		Vector2(0.0, px),
		Vector2(-px, -px),
		Vector2(px, -px),
		Vector2(-px, px),
		Vector2(px, px),
	]
	for offset in offsets:
		draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false, outline)


func _draw_unit_focus_outline(
	unit: UnitState,
	color: Color,
	line_width: float,
	offset: Vector2 = Vector2.ZERO,
	fill_alpha: float = 0.1,
	alpha: float = 1.0
) -> void:
	if alpha <= 0.01:
		return
	var outline := color
	outline.a *= alpha
	for cell in unit.occupied_cells():
		var corners := IsoCoordinates.diamond_corners(grid_to_screen(cell) + offset)
		var fill := outline
		fill.a = fill_alpha * alpha
		draw_colored_polygon(corners, fill)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, outline, line_width, false)


func _draw_active_turn_aura(unit: UnitState, center: Vector2, alpha: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var pulse := sin(_anim.pulse_time * 4.2) * 0.5 + 0.5
	var base_color := BattleUiTheme.PHASE_PLAYER if unit.team == Constants.TEAM_PLAYER else BattleUiTheme.PHASE_ENEMY
	var size_scale := maxf(float(unit.footprint_size.x + unit.footprint_size.y) * 0.5, 1.0)
	var radius_x := IsoCoordinates.visual(20.0 + 8.0 * (size_scale - 1.0))
	var radius_y := IsoCoordinates.visual(8.0 + 4.0 * (size_scale - 1.0))
	var outer_scale := 1.05 + pulse * 0.16
	var fill_color := base_color
	fill_color.a = (0.12 + pulse * 0.12) * alpha
	var outer_color := base_color.lightened(0.18)
	outer_color.a = (0.52 + pulse * 0.28) * alpha
	var inner_color := base_color.lightened(0.08)
	inner_color.a = (0.35 + pulse * 0.18) * alpha
	_draw_ellipse(center, radius_x * outer_scale, radius_y * outer_scale, fill_color, outer_color, IsoCoordinates.visual(2.0))
	_draw_ellipse(center, radius_x * 0.82, radius_y * 0.82, Color.TRANSPARENT, inner_color, IsoCoordinates.visual(1.2))


func _draw_unit_nameplate(unit: UnitState, anchor: Vector2, alpha: float = 1.0) -> void:
	if alpha <= 0.01:
		return
	var font := ThemeDB.fallback_font
	var font_size := int(IsoCoordinates.visual(9.0))
	var text: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var backdrop_center := Vector2(anchor.x, anchor.y - text_size.y * 0.38)
	var radius_x := text_size.x * 0.5 + IsoCoordinates.visual(5.0)
	var radius_y := maxf(text_size.y * 0.56, IsoCoordinates.visual(5.0))
	_draw_soft_backdrop(backdrop_center, radius_x, radius_y, Color(0.0, 0.0, 0.0, 0.82 * alpha))
	var text_color := BattleUiTheme.TEXT
	text_color.a *= alpha
	var shadow_color := Color(0.0, 0.0, 0.0, 0.96 * alpha)
	_draw_text_with_shadow(
		font,
		Vector2(anchor.x - text_size.x * 0.5, anchor.y - 1.0),
		text,
		font_size,
		text_color,
		shadow_color
	)


func _draw_unit_statuses(unit: UnitState, origin: Vector2) -> void:
	var has_other := false
	for status in unit.statuses:
		if status.status_id != Constants.STATUS_ARMOR:
			has_other = true
			break
	if not has_other:
		return
	_draw_status_row(origin, unit, IsoCoordinates.visual(12.0), IsoCoordinates.visual(2.0), IsoCoordinates.visual(44.0))


func _draw_gem_icons(unit: UnitState, anchor: Vector2) -> void:
	if state == null or _gem_sprites == null:
		return
	var visible_slots: Array[SlotState] = []
	for slot in unit.slots:
		if slot == null:
			continue
		if not slot.gem_uid.is_empty() and _anim.masked_embedded_gems.has(slot.gem_uid):
			continue
		visible_slots.append(slot)
	if visible_slots.is_empty():
		return
	var icon_size := IsoCoordinates.visual(10.0)
	var spacing := IsoCoordinates.visual(11.0)
	var start_x := anchor.x - spacing * float(visible_slots.size() - 1) * 0.5
	var icon_y := anchor.y - IsoCoordinates.visual(13.0)
	for i in range(visible_slots.size()):
		var slot: SlotState = visible_slots[i]
		var cx := start_x + spacing * float(i)
		var pos := Vector2(cx, icon_y)
		if slot.gem_uid.is_empty():
			var slot_col := UnitLooks.slot_color(slot.slot_type)
			slot_col.a = 0.82
			var slot_fill := slot_col
			slot_fill.a = 0.18
			_draw_small_diamond(pos, icon_size * 0.34, icon_size * 0.26, slot_fill)
			var corners := PackedVector2Array([
				pos + Vector2(0, -icon_size * 0.34),
				pos + Vector2(icon_size * 0.34, 0),
				pos + Vector2(0, icon_size * 0.34),
				pos + Vector2(-icon_size * 0.34, 0),
				pos + Vector2(0, -icon_size * 0.34),
			])
			draw_polyline(corners, slot_col, IsoCoordinates.visual(1.1), false)
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tex: Texture2D = _gem_sprites.texture_for_gem_id(gem.gem_id)
		if tex != null:
			tex = _display_gem_texture(gem, tex)
			var tint: Color = _gem_sprites.modulate_for_gem_id(gem.gem_id)
			draw_texture_rect(
				tex,
				Rect2(Vector2(cx - icon_size * 0.5, icon_y - icon_size * 0.5), Vector2(icon_size, icon_size)),
				false,
				tint
			)
		else:
			_draw_small_diamond(
				pos,
				icon_size * 0.38,
				icon_size * 0.3,
				GemEchoVisuals.fallback_color(state, gem.uid, UnitLooks.gem_color(gem))
			)
		_draw_echo_smoke(gem.uid, pos, icon_size, 0.92)


func _draw_unit_slot_panels() -> void:
	if state == null or slot_panel_action.is_empty():
		return
	for unit: UnitState in state.units.values():
		if unit == null or not unit.alive or unit.slots.is_empty():
			continue
		if not _unit_slot_panel_in_range(unit):
			continue
		var panel := _unit_slot_panel_layout(unit)
		var items: Array = panel.get("items", [])
		if items.is_empty():
			continue
		var center: Vector2 = panel.get("center", Vector2.ZERO)
		var radius: float = float(panel.get("radius", IsoCoordinates.visual(34.0)))
		var has_visible := false
		for item in items:
			if bool((item as Dictionary).get("visible", true)):
				has_visible = true
				break
		if not has_visible:
			continue
		_draw_soft_backdrop(center, radius * 0.96, radius * 0.62, Color(0.02, 0.03, 0.05, 0.32))
		for item in items:
			_draw_unit_slot_sector(item as Dictionary)


func _draw_unit_slot_sector(item: Dictionary) -> void:
	if not bool(item.get("visible", true)):
		return
	var center: Vector2 = item.get("center", Vector2.ZERO)
	var inner_radius: float = float(item.get("inner_radius", 0.0))
	var outer_radius: float = float(item.get("outer_radius", 0.0))
	var start_angle: float = float(item.get("start_angle", 0.0))
	var end_angle: float = float(item.get("end_angle", 0.0))
	var enabled := bool(item.get("enabled", false))
	var slot: SlotState = item.get("slot", null)
	var hovered: bool = enabled \
		and str(item.get("unit_uid", "")) == _slot_hover_unit_uid \
		and int(item.get("slot_index", -1)) == _slot_hover_index
	var base := _slot_panel_color(slot.slot_type if slot != null else "")
	var fill := base
	fill.a = 0.78 if enabled else 0.22
	if hovered:
		fill = base.lightened(0.18)
		fill.a = 0.92
	var points := PackedVector2Array()
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(a), sin(a)) * outer_radius)
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var a := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(a), sin(a)) * inner_radius)
	draw_colored_polygon(points, fill)
	draw_polyline(points, Color(UiPalette.EDGE_DARK, 0.9 if enabled else 0.4), IsoCoordinates.visual(2.2), true)
	var line := Color(UiPalette.TEXT_BRIGHT, 0.95) if hovered else Color(UiPalette.TEXT_BRIGHT, 0.6 if enabled else 0.22)
	draw_polyline(points, line, IsoCoordinates.visual(1.1), true)
	if slot != null and not slot.dual_type.is_empty():
		var mid_angle := (start_angle + end_angle) * 0.5
		var dual_col := _slot_panel_color(slot.dual_type)
		dual_col.a = 0.46 if enabled else 0.16
		var dual_center := center + Vector2(cos(mid_angle), sin(mid_angle)) * ((inner_radius + outer_radius) * 0.56)
		draw_circle(dual_center, (outer_radius - inner_radius) * 0.42, dual_col)
	_draw_slot_sector_content(item)
	var label := _slot_panel_label(slot)
	if not label.is_empty():
		var font := BattleUiTheme.pixel_font()
		var font_size := int(IsoCoordinates.visual(8.0))
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var mid := (start_angle + end_angle) * 0.5
		var text_pos := center + Vector2(cos(mid), sin(mid)) * (inner_radius + (outer_radius - inner_radius) * 0.28)
		var text_col := Color(UiPalette.TEXT_BRIGHT, 0.95 if enabled else 0.42)
		_draw_text_with_shadow(font, text_pos + Vector2(-label_size.x * 0.5, label_size.y * 0.35), label, font_size, text_col, UiPalette.TEXT_OUTLINE)


## 扇区内容：已嵌宝石画图标，空槽画空心菱形占位，便于拔出/嵌入时一眼区分
func _draw_slot_sector_content(item: Dictionary) -> void:
	var slot: SlotState = item.get("slot", null)
	if slot == null or state == null:
		return
	var center: Vector2 = item.get("center", Vector2.ZERO)
	var inner_radius: float = float(item.get("inner_radius", 0.0))
	var outer_radius: float = float(item.get("outer_radius", 0.0))
	var mid := (float(item.get("start_angle", 0.0)) + float(item.get("end_angle", 0.0))) * 0.5
	var enabled := bool(item.get("enabled", false))
	var content_pos := center + Vector2(cos(mid), sin(mid)) * (inner_radius + (outer_radius - inner_radius) * 0.68)
	var alpha := 1.0 if enabled else 0.45
	if not slot.gem_uid.is_empty():
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			return
		var tex: Texture2D = UnitLooks.get_gem_texture(gem)
		var icon_size := (outer_radius - inner_radius) * 0.52
		if tex != null:
			tex = _display_gem_texture(gem, tex)
			var tint: Color = UnitLooks.gem_sprite_modulate(gem)
			tint.a *= alpha
			draw_texture_rect(tex, Rect2(content_pos - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, tint)
		else:
			var gem_col := GemEchoVisuals.fallback_color(state, gem.uid, UnitLooks.gem_color(gem), alpha)
			_draw_small_diamond(content_pos, icon_size * 0.4, icon_size * 0.3, gem_col)
		_draw_echo_smoke(gem.uid, content_pos, icon_size, alpha * 0.95)
		return
	var hole := (outer_radius - inner_radius) * 0.16
	draw_arc(content_pos, hole, 0.0, TAU, 12, Color(UiPalette.TEXT_BRIGHT, 0.55 * alpha), IsoCoordinates.visual(1.0))


func _unit_slot_panel_layout(unit: UnitState) -> Dictionary:
	var anchor := _unit_panel_anchor(unit)
	return BattleSlotPanelLayout.build(
		unit,
		anchor,
		slot_panel_action,
		slot_panel_check,
		IsoCoordinates.visual(18.0),
		IsoCoordinates.visual(52.0)
	)


func _unit_panel_anchor(unit: UnitState) -> Vector2:
	var center := _get_unit_screen_center(unit)
	var offset: Vector2 = _anim.move_offsets.get(unit.uid, Vector2.ZERO)
	center += offset
	var pose: Dictionary = _resolve_unit_pose(unit, unit.facing)
	var sprite_size: Vector2 = pose.get("sprite_size", Vector2.ZERO)
	if sprite_size == Vector2.ZERO:
		sprite_size = _unit_sprite_size(unit)
	var layout := _unit_sprite_layout(unit, center, sprite_size)
	var top_left: Vector2 = layout.get("top_left", center - Vector2(sprite_size.x * 0.5, sprite_size.y))
	return top_left + Vector2(sprite_size.x * 0.5, IsoCoordinates.visual(10.0))


func _unit_slot_panel_in_range(unit: UnitState) -> bool:
	if state == null or unit == null or slot_panel_action.is_empty():
		return false
	var player: UnitState = state.get_player()
	if player == null:
		return false
	return GemRules.is_unit_in_operation_range(state, player, unit, slot_panel_action)


func _slot_panel_should_show(slot: SlotState) -> bool:
	return BattleSlotPanelLayout.should_show(slot, slot_panel_action)


func _point_in_slot_sector(pos: Vector2, item: Dictionary) -> bool:
	return BattleSlotPanelLayout.contains_point(pos, item)


func _angle_between(angle: float, start_angle: float, end_angle: float) -> bool:
	return BattleSlotPanelLayout.angle_between(angle, start_angle, end_angle)


func _slot_panel_color(slot_type: String) -> Color:
	match slot_type:
		Constants.SLOT_RED:
			return UiPalette.SLOT_RED
		Constants.SLOT_BLUE:
			return UiPalette.SLOT_BLUE
		Constants.SLOT_BLACK:
			return UiPalette.SLOT_BLACK_DEEP
	return UiPalette.INTENT_IDLE


func _slot_panel_label(slot: SlotState) -> String:
	if slot == null:
		return ""
	var label := "?"
	match slot.slot_type:
		Constants.SLOT_RED:
			label = "红"
		Constants.SLOT_BLUE:
			label = "蓝"
		Constants.SLOT_BLACK:
			label = "黑"
	if slot.locked:
		label += "·锁"
	return label


func _draw_small_diamond(center: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height),
		center + Vector2(-width * 0.5, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points, color.darkened(0.35), IsoCoordinates.visual(1.2), true)


func _draw_gem_visuals(front_layer: bool) -> void:
	for visual in _anim.inserting_gem_visuals:
		if _gem_visual_draws_in_front(visual) == front_layer:
			_draw_single_gem_visual(visual)
	if not _anim.held_gem_visual.is_empty() and _gem_visual_draws_in_front(_anim.held_gem_visual) == front_layer:
		_draw_single_gem_visual(_anim.held_gem_visual)


func _gem_visual_draws_in_front(visual: Dictionary) -> bool:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return true
	var pos: Vector2 = visual.get("current_pos", Vector2.ZERO)
	if pos.distance_to(anchor) > IsoCoordinates.visual(30.0):
		return true
	return pos.y >= anchor.y


func _draw_single_gem_visual(visual: Dictionary) -> void:
	var pos: Vector2 = visual.get("current_pos", Vector2.ZERO)
	var tint: Color = visual.get("tint", Color.WHITE)
	var phase := str(visual.get("phase", "orbit"))
	var progress := _gem_visual_progress(visual)
	var alpha := 1.0
	var scale := 1.0
	if phase == "extract":
		scale = lerpf(0.82, 1.0, progress)
	elif phase == "insert":
		alpha = 1.0 - progress * 0.35
		scale = lerpf(1.0, 0.74, progress)
	else:
		scale = 1.0 + sin(float(visual.get("bob_time", 0.0)) * 0.5) * 0.05
	var draw_tint := tint
	draw_tint.a *= alpha
	var glow := tint
	glow.a = 0.22 * alpha
	var shadow := Color(0.0, 0.0, 0.0, 0.16 * alpha)
	var draw_size := IsoCoordinates.visual(_GEM_DRAW_SIZE) * scale
	_draw_soft_backdrop(pos + Vector2(0.0, IsoCoordinates.visual(8.0)), draw_size * 0.28, draw_size * 0.14, shadow)
	_draw_soft_backdrop(pos, draw_size * 0.5, draw_size * 0.34, glow)
	var tex: Texture2D = visual.get("texture", null)
	if tex != null:
		draw_texture_rect(tex, Rect2(pos - Vector2.ONE * draw_size * 0.5, Vector2.ONE * draw_size), false, draw_tint)
	else:
		_draw_small_diamond(pos, draw_size * 0.48, draw_size * 0.32, draw_tint)


func _gem_visual_progress(visual: Dictionary) -> float:
	var duration := maxf(float(visual.get("duration", 1.0)), 0.001)
	return clampf(float(visual.get("elapsed", 0.0)) / duration, 0.0, 1.0)


func _draw_hp_bar(origin: Vector2, unit: UnitState, shield_value: int = 0) -> void:
	var icon_size := IsoCoordinates.visual(8.0) if shield_value > 0 else 0.0
	var gap := IsoCoordinates.visual(2.0) if shield_value > 0 else 0.0
	var width := IsoCoordinates.visual(36.0)
	var bar_h := IsoCoordinates.visual(5.0)
	var bar_x := origin.x + icon_size + gap
	if shield_value > 0:
		StatusIcons.draw_icon(self, origin, Constants.STATUS_ARMOR, icon_size)
	BattleUiTheme.draw_combined_hp_bar(
		self,
		Rect2(bar_x, origin.y, width, bar_h),
		unit.hp,
		unit.max_hp,
		shield_value
	)
	var font := BattleUiTheme.pixel_font()
	var font_size := int(IsoCoordinates.visual(7.0))
	var hp_text := "%d/%d" % [unit.hp, unit.max_hp]
	var text_size := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_draw_text_with_shadow(
		font,
		Vector2(bar_x + (width - text_size.x) * 0.5, origin.y + bar_h - IsoCoordinates.visual(0.5)),
		hp_text,
		font_size,
		UiPalette.TEXT_BRIGHT,
		UiPalette.TEXT_OUTLINE
	)


func _facing_from_grid_pos(from_grid: Vector2i, to_grid: Vector2i) -> String:
	_ensure_facing_screen_refs()
	var screen_delta := grid_to_screen(to_grid) - grid_to_screen(from_grid)
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return "DR"
	var dir := screen_delta.normalized()
	var best_name := "DR"
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name


func _get_unit_screen_center(unit: UnitState) -> Vector2:
	var cells := unit.occupied_cells()
	var total_screen := Vector2.ZERO
	for cell in cells:
		total_screen += grid_to_screen(cell)
	return total_screen / cells.size()


func _facing_from_unit_to_cell(unit: UnitState, to_grid: Vector2i) -> String:
	_ensure_facing_screen_refs()
	var from_screen := _get_unit_screen_center(unit)
	var to_screen := grid_to_screen(to_grid)
	var screen_delta := to_screen - from_screen
	var facing_thresh := IsoCoordinates.visual(4.0)
	if screen_delta.length_squared() < facing_thresh * facing_thresh:
		return unit.facing
	var dir := screen_delta.normalized()
	var best_name := "DR"
	var best_dot := -2.0
	for facing_name in _facing_screen_refs.keys():
		var ref: Vector2 = _facing_screen_refs[facing_name]
		var dot := dir.dot(ref)
		if dot > best_dot:
			best_dot = dot
			best_name = facing_name
	return best_name


func _ensure_facing_screen_refs() -> void:
	if not _facing_screen_refs.is_empty():
		return
	var origin_screen := grid_to_screen(Vector2i(0, 0))
	for facing_name in _FACING_GRID_STEPS.keys():
		var step: Vector2i = _FACING_GRID_STEPS[facing_name]
		var v := grid_to_screen(step) - origin_screen
		if v.length_squared() > 0.01:
			_facing_screen_refs[facing_name] = v.normalized()


func _draw_status_row(origin: Vector2, unit: UnitState, icon_size: float = -1.0, gap: float = -1.0, max_width: float = -1.0) -> void:
	var ICON_SIZE := icon_size if icon_size > 0.0 else IsoCoordinates.visual(13.0)
	var GAP := gap if gap > 0.0 else IsoCoordinates.visual(2.0)
	var FONT_SIZE := int(IsoCoordinates.visual(7.0))
	var PAD_X := IsoCoordinates.visual(3.0)
	var PAD_Y := IsoCoordinates.visual(2.0)
	var WRAP_WIDTH := max_width if max_width > 0.0 else 999999.0
	var sorted: Array = StatusRegistry.sort_statuses(unit.statuses)
	var pixel_font := BattleUiTheme.pixel_font()
	var cursor := Vector2.ZERO
	var row_h := ICON_SIZE + GAP
	for status in sorted:
		if status.status_id == Constants.STATUS_ARMOR:
			continue
		var draw_pos := origin + cursor
		var item_w := ICON_SIZE
		var item_h := ICON_SIZE
		if not StatusIcons.has_icon(status.status_id):
			var label: String = StatusRegistry.short_label(status)
			var label_size := pixel_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			item_w = label_size.x + PAD_X * 2.0
			item_h = FONT_SIZE + PAD_Y * 2.0
		if cursor.x > 0.0 and cursor.x + item_w > WRAP_WIDTH:
			cursor.x = 0.0
			cursor.y += row_h
			draw_pos = origin + cursor
		if StatusIcons.draw_icon(self , draw_pos, status.status_id, ICON_SIZE):
			var badge_text: String = StatusRegistry.icon_badge(status)
			if not badge_text.is_empty():
				var badge_size := pixel_font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
				_draw_text_with_shadow(
					pixel_font,
					Vector2(draw_pos.x + ICON_SIZE - badge_size.x - IsoCoordinates.visual(0.5), draw_pos.y + ICON_SIZE - IsoCoordinates.visual(1.0)),
					badge_text,
					FONT_SIZE,
					UiPalette.TEXT_BRIGHT,
					UiPalette.TEXT_OUTLINE
				)
		else:
			var fallback_label: String = StatusRegistry.short_label(status)
			var text_w: float = pixel_font.get_string_size(fallback_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var chip_w := text_w + PAD_X * 2.0
			var chip_h := FONT_SIZE + PAD_Y * 2.0
			var color: Color = StatusRegistry.status_color(status.status_id)
			var bg := color.darkened(0.55)
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), bg)
			draw_rect(Rect2(draw_pos, Vector2(chip_w, chip_h)), color.lightened(0.1), false, 1.0)
			_draw_text_with_shadow(
				pixel_font,
				Vector2(draw_pos.x + PAD_X, draw_pos.y + PAD_Y + FONT_SIZE - 1.0),
				fallback_label,
				FONT_SIZE,
				UiPalette.TEXT_BRIGHT,
				UiPalette.TEXT_OUTLINE
			)
		cursor.x += item_w + GAP


func _draw_text_with_shadow(
	font: Font,
	position: Vector2,
	text: String,
	font_size: int,
	color: Color,
	shadow_color: Color
) -> void:
	for shadow_offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, position + IsoCoordinates.visual_vec(shadow_offset), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, fill_color: Color, outline_color: Color, line_width: float) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	if fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline_color, line_width, false)


func _draw_soft_backdrop(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var tex := _get_soft_gradient_texture()
	if tex == null:
		_draw_ellipse(center, radius_x, radius_y, color, Color.TRANSPARENT, 0.0)
		return
	var outer_tint := color
	outer_tint.a *= 0.42
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(radius_x * 1.28, radius_y * 1.18), Vector2(radius_x * 2.56, radius_y * 2.36)),
		false,
		outer_tint
	)
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(radius_x, radius_y), Vector2(radius_x * 2.0, radius_y * 2.0)),
		false,
		color
	)
	var core := color
	core.a = minf(1.0, color.a * 1.12)
	_draw_ellipse(center, radius_x * 0.62, radius_y * 0.58, core, Color.TRANSPARENT, 0.0)


func _get_soft_gradient_texture() -> Texture2D:
	if _soft_gradient_tex != null:
		return _soft_gradient_tex
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var nx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var ny := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var dist := sqrt(nx * nx + ny * ny)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = pow(alpha, 0.48)
			var core := clampf(1.0 - dist * 1.8, 0.0, 1.0)
			alpha = maxf(alpha * 0.95, core * 0.48)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	_soft_gradient_tex = ImageTexture.create_from_image(image)
	return _soft_gradient_tex


func _draw_intent_badge(pos: Vector2, intent: IntentState) -> void:
	var center := Vector2(pos.x, pos.y)
	var icon_size_px := IsoCoordinates.visual(18.0)
	_draw_soft_backdrop(center, IsoCoordinates.visual(11.0), IsoCoordinates.visual(10.0), Color(0.0, 0.0, 0.0, 0.38))
	var draw_pos := center - Vector2(icon_size_px, icon_size_px) * 0.5
	if IntentIcons.draw_icon(self, draw_pos, intent.type, icon_size_px):
		return
	var icon: String = IntentState.intent_icon(intent.type)
	var font := ThemeDB.fallback_font
	var font_size := int(IsoCoordinates.visual(14.0))
	var text_size := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_draw_text_with_shadow(
		font,
		Vector2(center.x - text_size.x * 0.5, center.y + font_size * 0.35),
		icon,
		font_size,
		_intent_badge_color(intent.type).lightened(0.25),
		Color(0.0, 0.0, 0.0, 0.96)
	)


func _intent_badge_color(intent_type: String) -> Color:
	return Color(UiPalette.intent_color(intent_type), 0.95)


func pick_cell(screen_pos: Vector2) -> Vector2i:
	return IsoCoordinates.pick_grid_at(screen_pos, _board_origin, _board_size(), invert_origin)


# ═══════════════════════════════════════════════════════════════════════════
# 动画 API
# ═══════════════════════════════════════════════════════════════════════════

## 近战劈砍：Knight 三段挥剑sprite，与粒子伤害并行播放
func start_strike_effect(attacker_uid: String, victim_cell: Vector2i) -> void:
	if state == null:
		return
	var attacker: UnitState = state.units.get(attacker_uid, null)
	if attacker == null:
		return
	attacker.facing = _facing_from_unit_to_cell(attacker, victim_cell)
	_anim.strike_elapsed[attacker_uid] = 0.0
	queue_redraw()


func play_unit_hit(unit_uid: String) -> void:
	if state == null or not state.units.has(unit_uid):
		return
	_anim.hit_elapsed[unit_uid] = 0.0
	queue_redraw()


## 播放移动动画：单位从 from_pos 滑动到 to_pos
func animate_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i, emit_finished: bool = true) -> void:
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			mover.facing = _facing_from_grid_pos(from_pos, to_pos)
	var from_screen: Vector2 = grid_to_screen(from_pos)
	var to_screen: Vector2 = grid_to_screen(to_pos)
	var logical_pos: Vector2i = to_pos
	if state != null:
		var unit: UnitState = state.units.get(unit_uid, null)
		if unit != null:
			logical_pos = unit.pos
	var logical_screen: Vector2 = grid_to_screen(logical_pos)
	var from_offset: Vector2 = from_screen - logical_screen
	var to_offset: Vector2 = to_screen - logical_screen
	_anim.move_offsets[unit_uid] = from_offset
	_anim.walk_phase[unit_uid] = 0.0
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_move_offset.bind(unit_uid), from_offset, to_offset, _scaled_duration(_MOVE_DURATION))
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, to_offset, emit_finished))


func animate_move_task(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	animate_move(unit_uid, from_pos, to_pos)
	await move_animation_finished


## 播放一整条路径。逻辑位置已提前写到终点，视觉 offset 沿路径连续归零。
func animate_move_path(unit_uid: String, path: Array, emit_finished: bool = true) -> void:
	if path.size() < 2:
		if emit_finished:
			animation_finished.emit()
		return
	var fallback_facing := "DR"
	if state != null:
		var mover: UnitState = state.units.get(unit_uid, null)
		if mover != null:
			fallback_facing = mover.facing
	var segment_facings := _build_path_segment_facings(path, fallback_facing)
	_anim.move_path_segment_facings[unit_uid] = segment_facings
	_anim.move_path_segments[unit_uid] = -1
	if not segment_facings.is_empty():
		_apply_move_path_segment_facing(unit_uid, 0, segment_facings)
	var logical_pos: Vector2i = path[path.size() - 1]
	if state != null:
		var unit: UnitState = state.units.get(unit_uid, null)
		if unit != null:
			logical_pos = unit.pos
	var logical_screen := grid_to_screen(logical_pos)
	var offset_path: Array[Vector2] = []
	for cell in path:
		offset_path.append(grid_to_screen(cell) - logical_screen)
	_anim.move_offsets[unit_uid] = offset_path[0]
	_anim.walk_phase[unit_uid] = 0.0
	var segment_count := maxi(1, offset_path.size() - 1)
	var duration := _scaled_duration(0.26 * float(segment_count))
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(
		_set_move_path_progress.bind(unit_uid, offset_path, segment_facings),
		0.0,
		float(segment_count),
		duration
	)
	tween.tween_callback(_on_move_path_anim_done.bind(unit_uid, segment_facings, emit_finished))


func animate_move_path_task(unit_uid: String, path: Array) -> void:
	if path.size() < 2:
		return
	animate_move_path(unit_uid, path)
	await move_animation_finished


## 多单位同时位移（爆炸击退等）
func animate_moves_parallel(moves: Array) -> float:
	return animate_unit_motions_parallel(moves)


func animate_unit_motions_parallel(motions: Array) -> float:
	if motions.is_empty():
		animation_finished.emit()
		move_animation_finished.emit()
		return 0.0
	var sequences: Dictionary = {}
	for motion in motions:
		var uid := str(motion.get("uid", ""))
		if uid.is_empty():
			continue
		if not sequences.has(uid):
			sequences[uid] = []
		(sequences[uid] as Array).append(motion)
	if sequences.is_empty():
		animation_finished.emit()
		move_animation_finished.emit()
		return 0.0
	_anim.parallel_move_remaining = sequences.size()
	var max_duration := 0.0
	for uid in sequences.keys():
		max_duration = maxf(max_duration, _animate_unit_motion_sequence(str(uid), sequences[uid]))
	return max_duration


func _animate_unit_motion_sequence(unit_uid: String, motions: Array) -> float:
	var unit: UnitState = state.units.get(unit_uid, null) if state != null else null
	var final_motion: Dictionary = motions[-1]
	var logical_pos: Vector2i = unit.pos if unit != null else final_motion.get("to", final_motion.get("from", Vector2i.ZERO))
	var logical_screen := grid_to_screen(logical_pos)
	var first_from: Vector2i = motions[0].get("from", logical_pos)
	var current_offset := grid_to_screen(first_from) - logical_screen
	_anim.move_offsets[unit_uid] = current_offset
	_anim.walk_phase[unit_uid] = 0.0
	var tween := create_tween()
	var total_duration := 0.0
	for motion in motions:
		match str(motion.get("type", "move_step")):
			"displacement_impact":
				var motion_from: Vector2i = motion.get("from", logical_pos)
				var contact: Vector2i = motion.get("contact", motion_from)
				var contact_offset := current_offset + (
					grid_to_screen(contact) - grid_to_screen(motion_from)
				) * _COLLISION_CONTACT_RATIO
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					current_offset,
					contact_offset,
					_scaled_duration(_COLLISION_LUNGE_DURATION)
				).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					contact_offset,
					current_offset,
					_scaled_duration(_COLLISION_RECOIL_DURATION)
				).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				total_duration += _scaled_duration(_COLLISION_LUNGE_DURATION + _COLLISION_RECOIL_DURATION)
			_:
				var to_pos: Vector2i = motion.get("to", motion.get("from", logical_pos))
				var to_offset := grid_to_screen(to_pos) - logical_screen
				tween.tween_method(
					_set_move_offset.bind(unit_uid),
					current_offset,
					to_offset,
					_scaled_duration(_MOVE_DURATION)
				).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				current_offset = to_offset
				total_duration += _scaled_duration(_MOVE_DURATION)
	tween.tween_callback(_on_move_anim_done.bind(unit_uid, current_offset, false))
	return total_duration


func animate_unit_motions_parallel_task(motions: Array) -> void:
	if motions.is_empty():
		return
	animate_unit_motions_parallel(motions)
	await move_animation_finished


func animate_moves_parallel_task(moves: Array) -> void:
	if moves.is_empty():
		return
	animate_moves_parallel(moves)
	await move_animation_finished


func clear_gem_visuals() -> void:
	_anim.clear_gem_visuals()
	queue_redraw()


func has_active_held_gem_visual() -> bool:
	return not _anim.held_gem_visual.is_empty()


func gem_insert_anim_duration() -> float:
	return _scaled_duration(_GEM_INSERT_DURATION)


func start_held_gem_extract(source_grid: Vector2i, gem: GemState) -> void:
	if gem == null:
		return
	var source_pos := _consume_inserting_gem_position(gem.uid, _gem_grid_anchor(source_grid))
	_anim.held_gem_visual = _make_gem_visual(gem, source_pos)
	_anim.held_gem_visual["phase"] = "extract"
	_anim.held_gem_visual["from_pos"] = source_pos
	_anim.held_gem_visual["current_pos"] = source_pos
	_anim.held_gem_visual["elapsed"] = 0.0
	_anim.held_gem_visual["duration"] = _scaled_duration(_GEM_LIFT_DURATION)
	_anim.held_gem_visual["arc_height"] = IsoCoordinates.visual(54.0)
	_anim.held_gem_visual["orbit_angle"] = _orbit_angle_from_position(source_pos)
	_anim.held_gem_visual["bob_time"] = randf() * TAU
	queue_redraw()


func start_held_gem_insert(target_grid: Vector2i, gem: GemState) -> void:
	var visual: Dictionary = {}
	if not _anim.held_gem_visual.is_empty():
		visual = _anim.held_gem_visual.duplicate(true)
		_anim.held_gem_visual.clear()
	elif gem != null:
		var fallback := {
			"orbit_angle": 0.0,
			"bob_time": _anim.pulse_time * _GEM_BOB_SPEED,
		}
		visual = _make_gem_visual(gem, _current_player_orbit_position(fallback))
	if visual.is_empty():
		return
	var start_pos: Vector2 = visual.get("current_pos", _gem_grid_anchor(target_grid))
	visual["phase"] = "insert"
	visual["from_pos"] = start_pos
	visual["current_pos"] = start_pos
	visual["target_grid"] = target_grid
	visual["elapsed"] = 0.0
	visual["duration"] = _scaled_duration(_GEM_INSERT_DURATION)
	visual["arc_height"] = IsoCoordinates.visual(36.0)
	var gem_uid := str(visual.get("uid", ""))
	if not gem_uid.is_empty():
		_anim.masked_embedded_gems[gem_uid] = true
	_anim.inserting_gem_visuals.append(visual)
	queue_redraw()


func set_animation_speed_scale(speed_scale: float) -> void:
	_animation_speed_scale = maxf(speed_scale, 0.05)


func _scaled_duration(base_duration: float) -> float:
	return base_duration / _animation_speed_scale


func _set_move_offset(offset: Vector2, uid: String) -> void:
	_anim.move_offsets[uid] = offset
	queue_redraw()


func _build_path_segment_facings(path: Array, fallback_facing: String) -> Array[String]:
	var facings: Array[String] = []
	var last_facing := fallback_facing
	for i in range(path.size() - 1):
		var from_cell: Vector2i = path[i]
		var to_cell: Vector2i = path[i + 1]
		if from_cell == to_cell:
			facings.append(last_facing)
		else:
			last_facing = _facing_from_grid_pos(from_cell, to_cell)
			facings.append(last_facing)
	return facings


func _apply_move_path_segment_facing(uid: String, seg: int, segment_facings: Array[String]) -> void:
	if seg < 0 or seg >= segment_facings.size():
		return
	if int(_anim.move_path_segments.get(uid, -1)) == seg:
		return
	_anim.move_path_segments[uid] = seg
	if state == null:
		return
	var mover: UnitState = state.units.get(uid, null)
	if mover != null:
		mover.facing = segment_facings[seg]


func _set_move_path_progress(
	progress: float,
	uid: String,
	offset_path: Array[Vector2],
	segment_facings: Array[String]
) -> void:
	if offset_path.is_empty():
		return
	var max_segment := offset_path.size() - 1
	var seg := clampi(int(floor(progress)), 0, max_segment)
	if seg >= max_segment:
		_anim.move_offsets[uid] = offset_path[max_segment]
		if max_segment > 0:
			_apply_move_path_segment_facing(uid, max_segment - 1, segment_facings)
	else:
		var local_t := clampf(progress - float(seg), 0.0, 1.0)
		_anim.move_offsets[uid] = offset_path[seg].lerp(offset_path[seg + 1], local_t)
		_apply_move_path_segment_facing(uid, seg, segment_facings)
	queue_redraw()


func _on_move_path_anim_done(uid: String, segment_facings: Array[String], emit_finished: bool) -> void:
	if state != null and not segment_facings.is_empty():
		var mover: UnitState = state.units.get(uid, null)
		if mover != null:
			mover.facing = segment_facings[segment_facings.size() - 1]
	_on_move_anim_done(uid, Vector2.ZERO, emit_finished)


func _on_move_anim_done(uid: String, _final_offset: Vector2, emit_finished: bool = true) -> void:
	_anim.walk_phase.erase(uid)
	_anim.move_offsets.erase(uid)
	_anim.move_path_segments.erase(uid)
	_anim.move_path_segment_facings.erase(uid)
	queue_redraw()
	if not emit_finished:
		_anim.parallel_move_remaining = maxi(0, _anim.parallel_move_remaining - 1)
		if _anim.parallel_move_remaining <= 0:
			animation_finished.emit()
			move_animation_finished.emit()
		return
	animation_finished.emit()
	move_animation_finished.emit()


func _update_gem_visuals(scaled_dt: float) -> bool:
	var dirty := false
	if not _anim.held_gem_visual.is_empty():
		dirty = _update_held_gem_visual(scaled_dt) or dirty
	if not _anim.inserting_gem_visuals.is_empty():
		var idx := _anim.inserting_gem_visuals.size() - 1
		while idx >= 0:
			var visual: Dictionary = _anim.inserting_gem_visuals[idx]
			dirty = true
			if _step_inserting_gem_visual(visual, scaled_dt):
				_anim.inserting_gem_visuals[idx] = visual
			else:
				var gem_uid := str(visual.get("uid", ""))
				if not gem_uid.is_empty():
					_anim.masked_embedded_gems.erase(gem_uid)
				play_gem_flash(visual.get("target_grid", Vector2i.ZERO), visual.get("tint", Color.WHITE))
				_anim.inserting_gem_visuals.remove_at(idx)
				queue_redraw()
			idx -= 1
	return dirty


func _update_held_gem_visual(scaled_dt: float) -> bool:
	var phase := str(_anim.held_gem_visual.get("phase", "orbit"))
	if phase == "extract":
		var duration := maxf(float(_anim.held_gem_visual.get("duration", 0.01)), 0.01)
		var elapsed := minf(float(_anim.held_gem_visual.get("elapsed", 0.0)) + scaled_dt, duration)
		_anim.held_gem_visual["elapsed"] = elapsed
		_anim.held_gem_visual["bob_time"] = float(_anim.held_gem_visual.get("bob_time", 0.0)) + scaled_dt * _GEM_BOB_SPEED
		var from_pos: Vector2 = _anim.held_gem_visual.get("from_pos", _anim.held_gem_visual.get("current_pos", Vector2.ZERO))
		var to_pos := _current_player_orbit_position(_anim.held_gem_visual)
		var ctrl := (from_pos + to_pos) * 0.5 + Vector2(0.0, -float(_anim.held_gem_visual.get("arc_height", IsoCoordinates.visual(54.0))))
		var pos := _quadratic_bezier(from_pos, ctrl, to_pos, _ease_out_cubic(elapsed / duration))
		_anim.held_gem_visual["current_pos"] = pos
		if elapsed >= duration:
			_anim.held_gem_visual["phase"] = "orbit"
			_anim.held_gem_visual["orbit_angle"] = _orbit_angle_from_position(pos)
	else:
		_anim.held_gem_visual["orbit_angle"] = float(_anim.held_gem_visual.get("orbit_angle", 0.0)) + scaled_dt * _GEM_ORBIT_SPEED
		_anim.held_gem_visual["bob_time"] = float(_anim.held_gem_visual.get("bob_time", 0.0)) + scaled_dt * _GEM_BOB_SPEED
		_anim.held_gem_visual["current_pos"] = _current_player_orbit_position(_anim.held_gem_visual)
	return true


func _step_inserting_gem_visual(visual: Dictionary, scaled_dt: float) -> bool:
	var duration := maxf(float(visual.get("duration", 0.01)), 0.01)
	var elapsed := minf(float(visual.get("elapsed", 0.0)) + scaled_dt, duration)
	visual["elapsed"] = elapsed
	var from_pos: Vector2 = visual.get("from_pos", visual.get("current_pos", Vector2.ZERO))
	var to_pos := _gem_grid_anchor(visual.get("target_grid", Vector2.ZERO))
	var ctrl := (from_pos + to_pos) * 0.5 + Vector2(0.0, -float(visual.get("arc_height", IsoCoordinates.visual(36.0))))
	visual["current_pos"] = _quadratic_bezier(from_pos, ctrl, to_pos, _ease_in_out_cubic(elapsed / duration))
	return elapsed < duration


func _make_gem_visual(gem: GemState, start_pos: Vector2) -> Dictionary:
	if gem == null:
		return {}
	return {
		"uid": gem.uid,
		"gem_id": gem.gem_id,
		"texture": UnitLooks.get_gem_texture(gem),
		"tint": UnitLooks.gem_sprite_modulate(gem),
		"current_pos": start_pos,
		"phase": "orbit",
		"orbit_angle": randf() * TAU,
		"bob_time": randf() * TAU,
	}


func _consume_inserting_gem_position(gem_uid: String, fallback: Vector2) -> Vector2:
	for idx in range(_anim.inserting_gem_visuals.size() - 1, -1, -1):
		var visual: Dictionary = _anim.inserting_gem_visuals[idx]
		if str(visual.get("uid", "")) != gem_uid:
			continue
		_anim.masked_embedded_gems.erase(gem_uid)
		_anim.inserting_gem_visuals.remove_at(idx)
		return visual.get("current_pos", fallback)
	return fallback


func _gem_grid_anchor(grid: Vector2i) -> Vector2:
	return grid_to_screen(grid) + IsoCoordinates.visual_vec(_GEM_SLOT_SOURCE_OFFSET)


func _player_gem_anchor() -> Vector2:
	if state == null:
		return Vector2.ZERO
	var player := state.get_player()
	if player == null or not player.alive:
		return Vector2.ZERO
	var fp := player.footprint_size
	var visual_anchor_grid := player.pos + fp - Vector2i(1, 1)
	var center := grid_to_screen(visual_anchor_grid)
	if fp != Vector2i(1, 1):
		var anchor_left := grid_to_screen(player.pos)
		center.x = (anchor_left.x + center.x) * 0.5
	return center + _anim.move_offsets.get(player.uid, Vector2.ZERO)


func _current_player_orbit_position(visual: Dictionary) -> Vector2:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return visual.get("current_pos", Vector2.ZERO)
	var angle := float(visual.get("orbit_angle", 0.0))
	var bob_time := float(visual.get("bob_time", 0.0))
	var radius_x := IsoCoordinates.visual(_GEM_ORBIT_RADIUS_X)
	var radius_y := IsoCoordinates.visual(_GEM_ORBIT_RADIUS_Y)
	return anchor + Vector2(
		cos(angle) * radius_x,
		sin(angle) * radius_y + sin(bob_time) * IsoCoordinates.visual(_GEM_BOB_AMPLITUDE)
	)


func _orbit_angle_from_position(pos: Vector2) -> float:
	var anchor := _player_gem_anchor()
	if anchor == Vector2.ZERO:
		return 0.0
	var rel := pos - anchor
	if rel.length_squared() <= 0.0001:
		return 0.0
	var radius_x := maxf(IsoCoordinates.visual(_GEM_ORBIT_RADIUS_X), 0.001)
	var radius_y := maxf(IsoCoordinates.visual(_GEM_ORBIT_RADIUS_Y), 0.001)
	return atan2(rel.y / radius_y, rel.x / radius_x)


func _quadratic_bezier(from_pos: Vector2, ctrl: Vector2, to_pos: Vector2, t: float) -> Vector2:
	var clamped_t := clampf(t, 0.0, 1.0)
	var inv := 1.0 - clamped_t
	return inv * inv * from_pos + 2.0 * inv * clamped_t * ctrl + clamped_t * clamped_t * to_pos


func _ease_out_cubic(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped_t, 3.0)


func _ease_in_out_cubic(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	if clamped_t < 0.5:
		return 4.0 * clamped_t * clamped_t * clamped_t
	return 1.0 - pow(-2.0 * clamped_t + 2.0, 3.0) * 0.5


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _add_particle(spec: Dictionary) -> void:
	_ensure_combat_visual_layers()
	if _particle_fx != null:
		_particle_fx.add(spec)


func _push_sprite_sequence(cfg: Dictionary) -> bool:
	_ensure_combat_visual_layers()
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
		FxLightningShader,
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
		FxRadialBurstShader,
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
		FxCloudPulseShader,
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
		for neighbor in BoardUtilsClass.neighbors4(anchor_grid):
			if BoardUtilsClass.in_bounds(state, neighbor):
				cells.append(neighbor)
	elif radius <= 0:
		cells.append(anchor_grid)
	else:
		for cell in BoardUtilsClass.cells_in_radius(anchor_grid, radius):
			if BoardUtilsClass.in_bounds(state, cell):
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
	_ensure_combat_visual_layers()
	return _particle_fx.puff_paths() if _particle_fx != null else PackedStringArray()


# ═══════════════════════════════════════════════════════════════════════════
# 抛射物动画
# ═══════════════════════════════════════════════════════════════════════════

## 播放玩家投射物：从 from_grid 飞向 to_grid，走贝塞尔弧线
func play_projectile(from_grid: Vector2i, to_grid: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	play_projectiles([ {"from": from_grid, "to": to_grid, "color": proj_color}])


func play_projectile_task(from_grid: Vector2i, to_grid: Vector2i, proj_color: Color = Color(0.95, 0.92, 0.45)) -> void:
	play_projectile(from_grid, to_grid, proj_color)
	await projectile_animation_finished


## 齐射：多枚投射物同时飞行
func play_projectiles(shots: Array) -> void:
	_ensure_combat_visual_layers()
	if _projectile_fx == null:
		animation_finished.emit()
		projectile_animation_finished.emit()
		return
	_projectile_fx.play(shots, _animation_speed_scale)


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
	_ensure_combat_visual_layers()
	if _light_beam_fx == null:
		return 0.0
	return _light_beam_fx.play(beams, _light_beam_fx_config())


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
