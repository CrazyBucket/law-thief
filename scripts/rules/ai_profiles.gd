class_name AIProfiles
extends RefCounted
## AI 性格配置 —— 数据驱动的权重系统


static func get_profile(ai_profile_id: String) -> Dictionary:
	match ai_profile_id:
		"bomb_rat":
			return _bomb_rat()
		"stone_bow":
			return _stone_bow()
		_:
			return _melee_chase()


static func _melee_chase() -> Dictionary:
	return {
		"w_damage": 10.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -20.0,
		"w_self_damage": 8.0,
		"w_friendly_fire": 30.0,
		"w_approach": 6.0,
		"w_move_cost": 0.5,
		"w_pull": 0.0,
		"w_poison": 0.0,
		"wait_score": -10.0,
		"can_extract": false,
		"prefer_distance": false,
		"guard_ally": false,
	}


static func _stone_bow() -> Dictionary:
	return {
		"w_damage": 10.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -25.0,
		"w_self_damage": 8.0,
		"w_friendly_fire": 25.0,
		"w_approach": 2.0,
		"w_move_cost": 0.4,
		"w_deploy_bonus": 14.0,
		"w_keep_distance": 5.0,
		"wait_score": 2.0,
		"can_ranged_attack": true,
		"prefer_distance": true,
		"can_extract": false,
		"guard_ally": false,
	}


static func _bomb_rat() -> Dictionary:
	return {
		"w_approach": 10.0,
		"wait_score": -50.0,
		"can_extract": false,
	}
