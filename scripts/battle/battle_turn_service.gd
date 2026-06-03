class_name BattleTurnService
extends RefCounted

const OverloadRules = preload("res://scripts/rules/overload_rules.gd")

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func _c() -> BattleController:
	return _ctrl


func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


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
	# 若队列中还有待操控单位，切换后继续玩家回合
	if _try_activate_next_controllable(ctrl):
		return
	var player: UnitState = ctrl.state.get_player()
	if player != null and player.has_status(Constants.STATUS_PARALYZED):
		player.remove_status(Constants.STATUS_PARALYZED)
	ctrl.state.on_turn_end.emit(ctrl.state.turn_index)
	ctrl.state.phase = Constants.PHASE_ENEMY
	ctrl.selected_action = ""
	OverloadRules.activate_pending(ctrl.state)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()


## 弹出可操控队列下一个存活单位并激活；返回是否切换成功
func _try_activate_next_controllable(ctrl) -> bool:
	var activated: String = ctrl.state.activate_next_controllable()
	if activated.is_empty():
		return false
	ctrl.selected_unit_uid = activated
	ctrl.state.log("切换操控单位 → %s（剩余队列: %s）" % [activated, ctrl.state.controllable_queue])
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()
	return true


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
	ctrl.state.bootstrap_split_controllable_turn()
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	ctrl.selected_action = ""
	if ctrl.state.get_player() != null:
		ctrl.selected_unit_uid = ctrl.state.player_uid
	_apply_move_bonus(ctrl.state)
	OverloadRules.tick_turn_start(ctrl.state)
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
		_merge_split_clones_on_win(ctrl)
		ctrl.state.phase = Constants.PHASE_ENDED
		ctrl.state.result = "win"
		ctrl.state.log("战斗胜利")
		ctrl.state.on_battle_end.emit("win")
		ctrl.battle_ended.emit("win")
		return
	ctrl._emit_changed()


func _apply_move_bonus(state: GameState) -> void:
	var registry := _relic_effect_registry()
	if registry == null:
		return
	var bonus: int = registry.query_modifier("move_bonus", state)
	if bonus <= 0:
		return
	var player: UnitState = state.get_player()
	if player == null:
		return
	player.move_points += bonus


## 玩家死亡时：先尝试队列中的下一个，再回退到存活的友方克隆单位
func _try_inherit_split_clone(ctrl) -> bool:
	if _try_activate_next_controllable(ctrl):
		return true
	# 兜底：从所有存活的分裂分身里找一个接班
	var survivors: Array = []
	for unit in ctrl.state.units.values():
		if unit.alive and unit.team == Constants.TEAM_PLAYER and unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			survivors.append(unit)
	if survivors.is_empty():
		return false
	var heir: UnitState = survivors[0]
	ctrl.state.player_uid = heir.uid
	ctrl.selected_unit_uid = heir.uid
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	ctrl.state.log("玩家死亡，%s 接班" % heir.uid)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()
	return true


func _merge_split_clones_on_win(ctrl) -> void:
	var player: UnitState = ctrl.state.get_player()
	if player == null or not player.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return
	var origin_uid: String = player.split_origin_uid
	var origin: UnitState = ctrl.state.units.get(origin_uid, null)
	if origin == null:
		return
	var clones: Array[UnitState] = ctrl.state.get_alive_split_clones(origin_uid)
	if clones.is_empty():
		return
	var total_hp := 0
	for clone in clones:
		total_hp += clone.hp
	var merged_hp := maxi(1, total_hp / Constants.SPLIT_DEATH_HP_MERGE_DIVISOR)
	for clone in clones:
		for slot in clone.slots:
			if slot.gem_uid.is_empty():
				continue
			ctrl.state.gems.erase(slot.gem_uid)
		ctrl.state.unregister_unit(clone)
	origin.alive = true
	origin.hp = mini(merged_hp, origin.max_hp)
	origin.pos = player.pos
	origin.facing = player.facing
	ctrl.state.player_uid = origin.uid
	ctrl.state.controllable_queue.clear()
	ctrl.selected_unit_uid = origin.uid
	ctrl.state.rebuild_occupancy()
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl.state.log("战斗结算：分身合并回归原体 HP=%d" % origin.hp)
