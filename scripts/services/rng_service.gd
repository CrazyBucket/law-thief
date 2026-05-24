extends Node

var _seed: int = 0
var _step: int = 0
var _streams: Dictionary = {}


func set_seed(seed_value: int) -> void:
	_seed = seed_value
	_step = 0
	_streams.clear()


func get_seed() -> int:
	return _seed


func get_step() -> int:
	return _step


func roll_int(domain: String, min_value: int, max_value: int) -> int:
	var stream := _get_stream(domain)
	_step += 1
	stream.seed = hash(str(_seed, domain, _step))
	return stream.randi_range(min_value, max_value)


func pick(domain: String, items: Array):
	if items.is_empty():
		return null
	var index := roll_int(domain, 0, items.size() - 1)
	return items[index]


func _get_stream(domain: String) -> RandomNumberGenerator:
	if not _streams.has(domain):
		_streams[domain] = RandomNumberGenerator.new()
	return _streams[domain]
