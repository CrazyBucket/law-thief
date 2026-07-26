class_name BattleShaderFxPool
extends RefCounted

var _layer: Control = null
var _pools: Dictionary = {}


func configure(layer: Control) -> void:
	_layer = layer


func prewarm(shader: Shader, count: int) -> void:
	var shader_key := key_for(shader)
	var pool: Array = _pools.get(shader_key, [])
	while pool.size() < count:
		pool.append(_create_rect(shader))
	_pools[shader_key] = pool


func warm_rendering(shaders: Array) -> void:
	var warming: Array[Dictionary] = []
	for shader in shaders:
		var rect := acquire(shader as Shader)
		rect.position = Vector2.ZERO
		rect.size = Vector2.ONE
		rect.self_modulate = Color(1.0, 1.0, 1.0, 0.001)
		var material := rect.material as ShaderMaterial
		material.set_shader_parameter("progress", 0.5)
		rect.visible = true
		warming.append({"key": key_for(shader as Shader), "rect": rect})
	RenderingServer.force_draw(false)
	for item in warming:
		var rect: ColorRect = item.rect
		if not is_instance_valid(rect):
			continue
		rect.self_modulate = Color.WHITE
		release(str(item.key), rect)


func acquire(shader: Shader) -> ColorRect:
	var shader_key := key_for(shader)
	var pool: Array = _pools.get(shader_key, [])
	while not pool.is_empty():
		var candidate = pool.pop_back()
		if candidate is ColorRect and is_instance_valid(candidate):
			_pools[shader_key] = pool
			return candidate
	_pools[shader_key] = pool
	return _create_rect(shader)


func release(shader_key: String, rect: ColorRect) -> void:
	rect.visible = false
	var pool: Array = _pools.get(shader_key, [])
	pool.append(rect)
	_pools[shader_key] = pool


func key_for(shader: Shader) -> String:
	if not shader.resource_path.is_empty():
		return shader.resource_path
	return str(shader.get_instance_id())


func _create_rect(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "ShaderFx"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	rect.visible = false
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	_layer.add_child(rect)
	return rect
