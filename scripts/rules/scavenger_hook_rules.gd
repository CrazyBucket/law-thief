class_name ScavengerHookRules
extends RefCounted

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


static func try_hook_enemy_drop(
	relic_id: String,
	_effect: Dictionary,
	state: GameState,
	payload: Dictionary
) -> void:
	if state == null or state.relic_battle.scavenger_hook_triggered:
		return
	if not state.relic_battle.hooked_gem_uid.is_empty():
		return
	var source_uid := str(payload.get("unit_uid", ""))
	var source: UnitState = state.units.get(source_uid, null)
	if source == null or source.team != Constants.TEAM_ENEMY:
		return
	var candidates: Array[String] = []
	for raw_uid in state.dropped_gems.keys():
		var gem_uid := str(raw_uid)
		var drop: Dictionary = state.dropped_gems.get(gem_uid, {})
		if str(drop.get("source_unit_uid", "")) == source_uid and state.gems.has(gem_uid):
			candidates.append(gem_uid)
	if candidates.is_empty():
		return
	candidates.sort()
	var pick_index: int = Engine.get_main_loop().root.get_node("RngService").roll_int(
		"scavenger_hook:%s:%s:%d" % [relic_id, source_uid, state.turn_index],
		0,
		candidates.size() - 1
	)
	var gem_uid := candidates[pick_index]
	var gem: GemState = state.gems.get(gem_uid, null)
	var drop: Dictionary = state.dropped_gems.get(gem_uid, {}).duplicate(true)
	var origin: Vector2i = drop.get("pos", source.pos)
	if gem == null or not GemTransfer.to_hooked(state, gem, state.player_uid):
		return
	state.relic_battle.scavenger_hook_triggered = true
	state.relic_battle.hooked_drop_metadata = drop
	state.relic_battle.hook_expires_after_turn = state.turn_index \
		if state.phase == Constants.PHASE_PLAYER else state.turn_index + 1
	state.log("[Relic] %s 钩住 %s" % [relic_id, _data_registry().get_gem_display_name(gem)])
	state.on_gem_hooked.emit(gem.uid, origin)


static func get_hooked_gem(state: GameState) -> GemState:
	if state == null or state.relic_battle.hooked_gem_uid.is_empty():
		return null
	return state.gems.get(state.relic_battle.hooked_gem_uid, null)


static func can_insert_hooked(
	state: GameState,
	actor: UnitState,
	target: UnitState,
	slot: SlotState
) -> Dictionary:
	var gem := get_hooked_gem(state)
	if gem == null:
		return {"ok": false, "reason": "拾荒钩上没有宝石"}
	return GemRules.can_insert_gem(state, actor, target, slot, gem)


static func insert_hooked(
	state: GameState,
	actor: UnitState,
	target: UnitState,
	slot: SlotState,
	force_overload: bool = false
) -> Dictionary:
	var gem := get_hooked_gem(state)
	if gem == null:
		return {"ok": false, "reason": "拾荒钩上没有宝石"}
	var source_uid := str(state.relic_battle.hooked_drop_metadata.get("source_unit_uid", ""))
	var result := GemRules.insert_gem(
		state, actor, target, slot, gem, source_uid, force_overload
	)
	if result.get("ok", false):
		result["hooked_insert"] = true
	return result


static func expire_at_player_turn_end(state: GameState) -> bool:
	if state == null or state.relic_battle.hooked_gem_uid.is_empty():
		return false
	if state.turn_index < state.relic_battle.hook_expires_after_turn:
		return false
	return return_hooked_gem(state, "回合结束")


static func return_before_settlement(
	_relic_id: String,
	_effect: Dictionary,
	state: GameState,
	_payload: Dictionary
) -> void:
	return_hooked_gem(state, "战斗结束")


static func return_hooked_gem(state: GameState, reason: String = "") -> bool:
	var gem := get_hooked_gem(state)
	if gem == null:
		return false
	var drop: Dictionary = state.relic_battle.hooked_drop_metadata.duplicate(true)
	var origin: Vector2i = drop.get("pos", Vector2i(-1, -1))
	if origin == Vector2i(-1, -1):
		return false
	if not GemTransfer.to_ground(state, gem, origin, drop):
		return false
	state.log("拾荒钩归还 %s（%s）" % [_data_registry().get_gem_display_name(gem), reason])
	return true


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
