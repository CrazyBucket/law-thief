class_name UnitRewardRules
extends RefCounted


static func configure_root(unit: UnitState) -> void:
	if unit == null:
		return
	unit.spawn_origin_uid = ""
	unit.reward_origin_uid = unit.uid
	unit.grants_death_rewards = true
	unit.is_temporary_summon = false


static func configure_spawn(unit: UnitState, origin: UnitState, opts: Dictionary = {}) -> void:
	if unit == null:
		return
	unit.spawn_origin_uid = origin.uid if origin != null else str(opts.get("spawn_origin_uid", ""))
	var inherited_reward_origin := origin.reward_origin_uid if origin != null else ""
	if inherited_reward_origin.is_empty() and origin != null:
		inherited_reward_origin = origin.uid
	unit.reward_origin_uid = str(opts.get(
		"reward_origin_uid",
		inherited_reward_origin if not inherited_reward_origin.is_empty() else unit.uid
	))
	unit.grants_death_rewards = bool(opts.get("grants_death_rewards", false))
	unit.is_temporary_summon = bool(opts.get("temporary", false))


static func can_drop_gems(unit: UnitState) -> bool:
	return unit != null \
		and unit.team == Constants.TEAM_ENEMY \
		and unit.grants_death_rewards


static func reward_group_uid(unit: UnitState) -> String:
	if unit == null:
		return ""
	return unit.reward_origin_uid if not unit.reward_origin_uid.is_empty() else unit.uid
