extends Node

var _pool: RefCounted = null
var _resources: RefCounted = null
var _pool_sizes: Array[int] = []
var _delay_frames: int = 0
var _next_shader_index: int = -1
var _warming: Array[Dictionary] = []


func configure(pool: RefCounted, resources: RefCounted, pool_sizes: Array, delay_frames: int = 2) -> void:
	_pool = pool
	_resources = resources
	_pool_sizes.clear()
	for pool_size in pool_sizes:
		_pool_sizes.append(int(pool_size))
	_delay_frames = maxi(0, delay_frames)
	_next_shader_index = 0
	set_process(true)


func _process(_delta: float) -> void:
	if not _warming.is_empty():
		_pool.finish_render_warmup(_warming)
		_warming.clear()
	if _delay_frames > 0:
		_delay_frames -= 1
		return
	if _next_shader_index < 0 or _next_shader_index >= _pool_sizes.size():
		_next_shader_index = -1
		set_process(false)
		return
	var shader := _shader_at(_next_shader_index)
	if shader != null:
		_pool.prewarm(shader, _pool_sizes[_next_shader_index])
		_warming = _pool.begin_render_warmup([shader])
	_next_shader_index += 1


func _exit_tree() -> void:
	if _pool != null and not _warming.is_empty():
		_pool.finish_render_warmup(_warming)
	_warming.clear()
	set_process(false)


func _shader_at(index: int) -> Shader:
	match index:
		0:
			return _resources.lightning_shader()
		1:
			return _resources.radial_burst_shader()
		2:
			return _resources.cloud_pulse_shader()
	return null
