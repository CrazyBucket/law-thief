class_name AIProfiles
extends RefCounted
## AI 性格配置 —— 数据驱动的权重系统
## 不同怪物通过不同的权重偏好表现出截然不同的战术风格


# ─── 获取 AI 配置 ─────────────────────────────────────────────────────────
static func get_profile(ai_profile_id: String) -> Dictionary:
	match ai_profile_id:
		"bomber":
			return _bomber()
		"melee_chase":
			return _melee_chase()
		"guard":
			return _guard()
		"puller":
			return _puller()
		"poison_roamer":
			return _poison_roamer()
		"turret":
			return _turret()
		"thief":
			return _thief()
	return _melee_chase()  # 默认


# ─── 自爆工兵 ─────────────────────────────────────────────────────────────
# 特点：不惜一切代价冲向玩家引爆，不在乎自身存活
static func _bomber() -> Dictionary:
	return {
		"w_damage": 15.0,          # 伤害权重高
		"w_kill_player": 200.0,    # 击杀玩家极高奖励
		"w_self_sacrifice": 50.0,  # 自爆不扣分反而加分
		"w_self_damage": 0.0,      # 完全不在乎自身受伤
		"w_friendly_fire": 10.0,   # 稍微在意友军
		"w_approach": 8.0,         # 强烈靠近欲望
		"w_move_cost": 0.0,        # 移动无成本
		"w_pull": 0.0,
		"w_poison": 0.0,
		"wait_score": -50.0,       # 极度不想等待
		"can_extract": false,
		"prefer_distance": false,
		"guard_ally": false,
	}


# ─── 近战追击者 ─────────────────────────────────────────────────────────
# 特点：直线追击玩家，到了就打，简单粗暴
static func _melee_chase() -> Dictionary:
	return {
		"w_damage": 10.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -20.0,  # 不想死
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


# ─── 重甲守卫 ─────────────────────────────────────────────────────────────
# 特点：优先保护友军，其次才攻击玩家；移动缓慢但坚韧
static func _guard() -> Dictionary:
	return {
		"w_damage": 8.0,
		"w_kill_player": 100.0,
		"w_self_sacrifice": -30.0,  # 非常不想死
		"w_self_damage": 12.0,      # 很在意自身安全
		"w_friendly_fire": 50.0,
		"w_approach": 3.0,          # 不急着靠近
		"w_move_cost": 1.0,
		"w_pull": 0.0,
		"w_poison": 0.0,
		"w_guard_proximity": 6.0,   # 强烈靠近友军
		"wait_score": 0.0,          # 等待也行
		"can_extract": false,
		"prefer_distance": false,
		"guard_ally": true,
	}


# ─── 引力眼 ─────────────────────────────────────────────────────────────
# 特点：不移动（move_points=0），远程拉人，喜欢把玩家拉到危险地块
static func _puller() -> Dictionary:
	return {
		"w_damage": 10.0,
		"w_kill_player": 100.0,
		"w_self_sacrifice": -50.0,
		"w_self_damage": 15.0,
		"w_friendly_fire": 20.0,
		"w_approach": 0.0,          # 不需要靠近
		"w_move_cost": 0.0,
		"w_pull": 20.0,             # 拉人高价值
		"w_poison": 0.0,
		"w_keep_distance": 5.0,
		"wait_score": 5.0,          # 等待也可以
		"can_extract": false,
		"prefer_distance": true,    # 喜欢保持距离
		"guard_ally": false,
	}


# ─── 毒虫 ─────────────────────────────────────────────────────────────────
# 特点：侧翼游走，铺毒雾，毒攻击；不正面硬刚
static func _poison_roamer() -> Dictionary:
	return {
		"w_damage": 8.0,
		"w_kill_player": 100.0,
		"w_self_sacrifice": -15.0,
		"w_self_damage": 6.0,
		"w_friendly_fire": 20.0,
		"w_approach": 4.0,
		"w_move_cost": 0.3,
		"w_pull": 0.0,
		"w_poison": 12.0,           # 中毒附加价值高
		"wait_score": -5.0,
		"can_extract": false,
		"prefer_distance": false,
		"guard_ally": false,
	}


# ─── 炮台 ─────────────────────────────────────────────────────────────────
# 特点：不移动，原地输出
static func _turret() -> Dictionary:
	return {
		"w_damage": 12.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -30.0,
		"w_self_damage": 10.0,
		"w_friendly_fire": 40.0,
		"w_approach": 0.0,
		"w_move_cost": 0.0,
		"w_pull": 0.0,
		"w_poison": 0.0,
		"wait_score": 5.0,
		"can_extract": false,
		"prefer_distance": true,
		"guard_ally": false,
	}


# ─── 窃贼 ─────────────────────────────────────────────────────────────────
# 特点：优先偷宝石，偷完就跑；不正面战斗
static func _thief() -> Dictionary:
	return {
		"w_damage": 5.0,
		"w_kill_player": 50.0,
		"w_self_sacrifice": -40.0,
		"w_self_damage": 10.0,
		"w_friendly_fire": 30.0,
		"w_approach": 2.0,
		"w_move_cost": 0.3,
		"w_pull": 0.0,
		"w_poison": 0.0,
		"w_extract_base": 25.0,     # 拔出基础分高
		"w_steal_player": 40.0,     # 偷玩家的超高分
		"w_steal_red": 30.0,        # 偷红槽更高
		"w_keep_distance": 3.0,
		"wait_score": -20.0,
		"can_extract": true,        # 能拔出宝石
		"prefer_distance": false,
		"guard_ally": false,
	}
