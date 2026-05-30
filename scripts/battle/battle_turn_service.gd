class_name BattleTurnService
extends RefCounted

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func _c() -> BattleController:
	return _ctrl


# ═══════════════════════════════════════════════════════════════════════════
# 敌方回合推进
# ═══════════════════════════════════════════════════════════════════════════

func begin_enemy_phase() -> void:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in begin_enemy_phase")
		return
	if ctrl.state == null or ctrl.state.phase != Constants.PHASE_PLAYER:
		return
	ctrl.state.on_turn_end.emit(ctrl.state.turn_index)
	ctrl.state.phase = Constants.PHASE_ENEMY
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()


func execute_single_enemy(enemy: UnitState) -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in execute_single_enemy")
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	var presentation_state: GameState = ctrl.state.clone()
	if not enemy.alive:
		return {
			"events": [] as Array[Dictionary],
			"presentation_state": presentation_state,
		}
	if enemy.has_status(Constants.STATUS_PARALYZED):
		enemy.remove_status(Constants.STATUS_PARALYZED)
		ctrl.state.log("%s 因麻痹跳过回合" % enemy.uid)
		ctrl._emit_changed()
		return {
			"events": [] as Array[Dictionary],
			"presentation_state": presentation_state,
		}
	IntentSystem.refresh_unit_intent(ctrl.state, enemy)
	var events := IntentSystem.execute_intent(ctrl.state, enemy)
	ctrl._check_battle_end()
	ctrl._emit_changed()
	return {
		"events": events,
		"presentation_state": presentation_state,
	}


func finish_enemy_phase() -> void:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in finish_enemy_phase")
		return
	if ctrl.state == null:
		return
	StatusRules.tick_turn_end(ctrl.state)
	if ctrl.state.phase == Constants.PHASE_ENDED:
		return
	ctrl.state.turn_index += 1
	StatusRules.tick_turn_start(ctrl.state)
	ctrl.state.phase = Constants.PHASE_PLAYER
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	_apply_move_bonus(ctrl.state)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl.state.log("敌方回合结束")
	ctrl.state.on_turn_start.emit(ctrl.state.turn_index)
	ctrl._check_battle_end()
	ctrl._emit_changed()


func get_sorted_enemies() -> Array:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in get_sorted_enemies")
		return []
	if ctrl.state == null:
		return []
	var enemies: Array = ctrl.state.get_alive_enemies()
	enemies.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var a_slug: bool = a.has_status(Constants.STATUS_SLUGGISH)
		var b_slug: bool = b.has_status(Constants.STATUS_SLUGGISH)
		if a_slug != b_slug:
			return not a_slug
		if a.speed == b.speed:
			return a.uid < b.uid
		return a.speed > b.speed
	)
	return enemies


# ═══════════════════════════════════════════════════════════════════════════
# 战斗结束判定
# ═══════════════════════════════════════════════════════════════════════════

func check_battle_end() -> void:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in check_battle_end")
		return
	if ctrl.state == null:
		return
	var player: UnitState = ctrl.state.get_player()
	if player == null or not player.alive:
		if _try_inherit_split_clone(ctrl):
			return
		ctrl.state.phase = Constants.PHASE_ENDED
		ctrl.state.result = "lose"
		ctrl.state.log("战斗失败")
		ctrl.state.on_battle_end.emit("lose")
		ctrl.battle_ended.emit("lose")
		return
	if ctrl.state.get_alive_enemies().is_empty():
		_merge_split_clone_hp(ctrl)
		ctrl.state.phase = Constants.PHASE_ENDED
		ctrl.state.result = "win"
		ctrl.state.log("战斗胜利")
		ctrl.state.on_battle_end.emit("win")
		ctrl.battle_ended.emit("win")


func _apply_move_bonus(state: GameState) -> void:
	var bonus: int = RelicEffectRegistry.query_modifier("move_bonus", state)
	if bonus <= 0:
		return
	var player := state.get_player()
	if player == null:
		return
	player.move_points += bonus


func _try_inherit_split_clone(ctrl) -> bool:
	var survivors: Array = []
	for unit in ctrl.state.units.values():
		if unit.alive and unit.team == Constants.TEAM_PLAYER and unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			survivors.append(unit)
	if survivors.is_empty():
		return false
	var total_hp := 0
	for clone in survivors:
		total_hp += clone.hp
	var merged_hp := maxi(1, total_hp / Constants.SPLIT_DEATH_HP_MERGE_DIVISOR)
	var heir: UnitState = survivors[0]
	heir.hp = mini(merged_hp, heir.max_hp)
	for i in range(1, survivors.size()):
		var other: UnitState = survivors[i]
		other.hp = 0
		ctrl.state.kill_unit(other)
	ctrl.state.player_uid = heir.uid
	ctrl.state.log("分身合并：继承人 %s HP=%d" % [heir.uid, heir.hp])
	return true


func _merge_split_clone_hp(ctrl) -> void:
	var player: UnitState = ctrl.state.get_player()
	if player == null or not player.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return
	var origin_uid: String = player.split_origin_uid
	var all_clones: Array = []
	for unit in ctrl.state.units.values():
		if not unit.alive:
			continue
		if unit.split_origin_uid == origin_uid or unit.uid == player.uid:
			all_clones.append(unit)
	var total_hp := 0
	for clone in all_clones:
		total_hp += clone.hp
	var merged_hp := maxi(1, total_hp / Constants.SPLIT_DEATH_HP_MERGE_DIVISOR)
	player.hp = mini(merged_hp, player.max_hp)
	ctrl.state.log("战斗结算：分身血量合并 %d / %d = %d" % [total_hp, Constants.SPLIT_DEATH_HP_MERGE_DIVISOR, merged_hp])
