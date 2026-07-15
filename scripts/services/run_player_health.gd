class_name RunPlayerHealth
extends RefCounted


static func heal_percent(run: RunState, ratio: float, fallback_max_hp: int) -> Dictionary:
	if run == null:
		return {}
	var max_hp := _resolve_max_hp(run, fallback_max_hp)
	var current_hp := _resolve_current_hp(run, max_hp)
	var amount := maxi(1, ceili(maxf(0.0, float(max_hp) * ratio) - 0.0001))
	return _set_health(run, current_hp, max_hp, mini(max_hp, current_hp + amount))


static func heal_amount(run: RunState, amount: int, fallback_max_hp: int) -> Dictionary:
	if run == null:
		return {}
	var max_hp := _resolve_max_hp(run, fallback_max_hp)
	var current_hp := _resolve_current_hp(run, max_hp)
	return _set_health(run, current_hp, max_hp, mini(max_hp, current_hp + maxi(0, amount)))


static func damage_amount(run: RunState, amount: int, fallback_max_hp: int) -> Dictionary:
	if run == null:
		return {}
	var max_hp := _resolve_max_hp(run, fallback_max_hp)
	var current_hp := _resolve_current_hp(run, max_hp)
	return _set_health(run, current_hp, max_hp, maxi(0, current_hp - maxi(0, amount)))


static func _resolve_max_hp(run: RunState, fallback_max_hp: int) -> int:
	return run.player_max_hp if run.player_max_hp > 0 else fallback_max_hp


static func _resolve_current_hp(run: RunState, max_hp: int) -> int:
	return run.player_hp if run.player_hp >= 0 else max_hp


static func _set_health(run: RunState, current_hp: int, max_hp: int, next_hp: int) -> Dictionary:
	run.player_max_hp = max_hp
	run.player_hp = next_hp
	return {
		"amount": maxi(0, absi(next_hp - current_hp)),
		"after_hp": next_hp,
		"max_hp": max_hp,
	}
