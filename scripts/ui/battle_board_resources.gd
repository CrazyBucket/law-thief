extends RefCounted

const WATER_TILE_SHADER_PATH := "res://scenes/battle/water_tile.gdshader"
const FX_LIGHTNING_SHADER_PATH := "res://scenes/battle/fx_lightning_bolt.gdshader"
const FX_RADIAL_BURST_SHADER_PATH := "res://scenes/battle/fx_radial_burst.gdshader"
const FX_CLOUD_PULSE_SHADER_PATH := "res://scenes/battle/fx_cloud_pulse.gdshader"
const OVERLAY_DRIFT_SHADER_PATH := "res://scenes/battle/overlay_drift.gdshader"
const GEM_ECHO_ICON_SHADER_PATH := "res://scenes/battle/gem_echo_icon.gdshader"
const GEM_ECHO_SMOKE_SHADER_PATH := "res://scenes/battle/gem_echo_smoke.gdshader"
const UNIT_SLOT_PANEL_RENDERER_SCRIPT_PATH := "res://scripts/ui/battle_unit_slot_panel_renderer.gd"
const BOARD_FX_TEXTURES_SCRIPT_PATH := "res://scripts/ui/board_fx_textures.gd"
const LIGHT_BEAM_FX_SCRIPT_PATH := "res://scripts/ui/battle_light_beam_fx.gd"
const PROJECTILE_FX_SCRIPT_PATH := "res://scripts/ui/battle_projectile_fx.gd"
const PARTICLE_FX_SCRIPT_PATH := "res://scripts/ui/battle_particle_fx.gd"
const SHADER_FX_POOL_SCRIPT_PATH := "res://scripts/ui/battle_shader_fx_pool.gd"
const SHADER_FX_WARMUP_SCRIPT_PATH := "res://scripts/ui/battle_shader_fx_warmup.gd"
const WATER_BOTTOM_TEXTURE_PATH := "res://assets/tiles/mew_water_bottom.png"
const WATER_TOP_TEXTURE_PATH := "res://assets/tiles/mew_water_top.png"
const ENTITY_SPIKE_TEXTURE_PATH := "res://assets/entities/entity_spike.png"
const ENTITY_BARREL_TEXTURE_PATH := "res://assets/demo/doodle-rpg/ALL SPRITES/Barrel_0.png"
const ENTITY_ROCK_TEXTURE_PATH := "res://assets/demo/doodle-rpg/ALL SPRITES/Rock1_0.png"
const ROUTE_ARROW_TEXTURE_PATHS := [
	"res://assets/ui/route_arrows_generated/route_arrow_ne.png",
	"res://assets/ui/route_arrows_generated/route_arrow_se.png",
	"res://assets/ui/route_arrows_generated/route_arrow_sw.png",
	"res://assets/ui/route_arrows_generated/route_arrow_nw.png",
]

var _cache: Dictionary = {}


func load_resource(path: String) -> Resource:
	var cached := _cache.get(path, null) as Resource
	if cached != null:
		return cached
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource != null:
		_cache[path] = resource
	return resource


func lightning_shader() -> Shader:
	return load_resource(FX_LIGHTNING_SHADER_PATH) as Shader


func radial_burst_shader() -> Shader:
	return load_resource(FX_RADIAL_BURST_SHADER_PATH) as Shader


func cloud_pulse_shader() -> Shader:
	return load_resource(FX_CLOUD_PULSE_SHADER_PATH) as Shader


func unit_slot_panel_renderer_script() -> Script:
	return load_resource(UNIT_SLOT_PANEL_RENDERER_SCRIPT_PATH) as Script


func board_fx_textures_script() -> Script:
	return load_resource(BOARD_FX_TEXTURES_SCRIPT_PATH) as Script


func light_beam_fx_script() -> Script:
	return load_resource(LIGHT_BEAM_FX_SCRIPT_PATH) as Script


func projectile_fx_script() -> Script:
	return load_resource(PROJECTILE_FX_SCRIPT_PATH) as Script


func particle_fx_script() -> Script:
	return load_resource(PARTICLE_FX_SCRIPT_PATH) as Script


func shader_fx_pool_script() -> Script:
	return load_resource(SHADER_FX_POOL_SCRIPT_PATH) as Script


func shader_fx_warmup_script() -> Script:
	return load_resource(SHADER_FX_WARMUP_SCRIPT_PATH) as Script
