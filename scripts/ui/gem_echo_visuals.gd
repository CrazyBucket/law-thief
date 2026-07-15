class_name GemEchoVisuals
extends RefCounted

const IconShader = preload("res://scenes/battle/gem_echo_icon.gdshader")
const _MATERIAL_META := &"law_thief_gem_echo_material"


static func is_echo(state: GameState, gem_uid: String) -> bool:
	return state != null and not gem_uid.is_empty() and state.overload_echo_gems.has(gem_uid)


static func fallback_color(state: GameState, gem_uid: String, base: Color, alpha: float = 1.0) -> Color:
	if not is_echo(state, gem_uid):
		var normal := base
		normal.a *= alpha
		return normal
	return Color(0.72, 0.40, 0.90, base.a * alpha)


static func apply_icon_material(icon: TextureRect, state: GameState, gem_uid: String) -> void:
	if icon == null:
		return
	if is_echo(state, gem_uid):
		var current := icon.material as ShaderMaterial
		if current == null or current.shader != IconShader:
			var material := ShaderMaterial.new()
			material.shader = IconShader
			icon.material = material
		icon.set_meta(_MATERIAL_META, true)
		return
	if icon.has_meta(_MATERIAL_META):
		icon.material = null
		icon.remove_meta(_MATERIAL_META)
