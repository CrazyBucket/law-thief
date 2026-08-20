class_name BattleTurnService
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const GemEffects = preload("res://scripts/rules/gem_effects.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")
const RelicBattleRules = preload("res://scripts/rules/relic_battle_rules.gd")
const CounterfeitRules = preload("res://scripts/rules/counterfeit_rules.gd")
const ScavengerHookRules = preload("res://scripts/rules/scavenger_hook_rules.gd")
const FightTicketRules = preload("res://scripts/rules/fight_ticket_rules.gd")
const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const _StatusActionRules = preload("res://scripts/rules/status_action_rules.gd")

var _ctrl_ref: WeakRef
var _ctrl: BattleController:
	get:
		return _ctrl_ref.get_ref() as BattleController if _ctrl_ref != null else null


func setup(controller: BattleController) -> void:
	_ctrl_ref = weakref(controller)


func _c() -> BattleController:
	return _ctrl


func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


# ═══════════════════════════════════════════════════════════════════════════
# 敌方回合推进
# ═══════════════════════════════════════════════════════════════════════════

func begin_enemy_phase() -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in begin_enemy_phase")
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	if ctrl.state == null or ctrl.state.phase != Constants.PHASE_PLAYER:
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	var ending_player: UnitState = ctrl.state.get_player()
	StatusRules.consume_disarm(ending_player)
	RelicBattleRules.finish_movement_window(ctrl.state, ending_player.uid if ending_player != null else "")
	ctrl.state.clear_split_move()
	ctrl.clear_swap_selection()
	ctrl.selected_action = Constants.ACTION_NONE
	# 若队列中还有待操控单位，切换后继续玩家回合
	if _try_activate_next_controllable(ctrl):
		RelicBattleRules.begin_next_controllable(ctrl.state)
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	ScavengerHookRules.expire_at_player_turn_end(ctrl.state)
	var presentation_state: GameState = ctrl.state.clone()
	var events: Array[Dictionary] = []
	var player: UnitState = ctrl.state.get_player()
	StatusRules.clear_extra_action_statuses(player)
	var player_skip_status := _StatusActionRules.consume_turn_skip_status(player)
	if not player_skip_status.is_empty():
		ctrl.state.log("%s 因%s跳过回合" % [player.uid, _StatusRegistry.display_name(player_skip_status)])
	ctrl.state.on_turn_end.emit(ctrl.state.turn_index)
	RelicBattleRules.clear_temp_move(ctrl.state)
	ctrl._check_battle_end()
	if ctrl.state.phase == Constants.PHASE_ENDED:
		ctrl._emit_changed()
		return {"events": events, "presentation_state": presentation_state}
	ctrl.state.phase = Constants.PHASE_ENEMY
	ctrl.selected_action = Constants.ACTION_NONE
	OverloadRules.activate_pending(ctrl.state)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()
	return {"events": events, "presentation_state": presentation_state}


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
	var events: Array[Dictionary] = []
	if not enemy.alive:
		CounterfeitRules.remove_for_unit_death(ctrl.state, enemy)
		return {
			"events": events,
			"presentation_state": presentation_state,
		}
	BehaviorRegistry.get_behavior(enemy.behavior_id).on_turn_start(ctrl.state, enemy)
	StatusRules.tick_unit_turn_start(ctrl.state, enemy)
	var enemy_skip_status := _StatusActionRules.consume_turn_skip_status(enemy)
	if not enemy_skip_status.is_empty():
		ctrl.state.log("%s 因%s跳过回合" % [enemy.uid, _StatusRegistry.display_name(enemy_skip_status)])
		CounterfeitRules.break_after_action(ctrl.state, enemy)
		ctrl._check_battle_end()
		ctrl._emit_changed()
		return {
			"events": events,
			"presentation_state": presentation_state,
		}
	var first_action := true
	while enemy.alive and ctrl.state.phase != Constants.PHASE_ENDED:
		if not first_action and not StatusRules.consume_extra_attack(enemy):
			break
		IntentSystem.refresh_unit_intent(ctrl.state, enemy)
		var executed_intent: IntentState = enemy.intent
		events.append_array(IntentSystem.execute_intent(ctrl.state, enemy))
		FightTicketRules.consume_after_intent(
			ctrl.state,
			enemy,
			executed_intent,
			executed_intent != null and IntentSystem.is_attack_intent(executed_intent.type)
		)
		ctrl._check_battle_end()
		if ctrl.state.phase == Constants.PHASE_ENDED or not enemy.alive:
			break
		if not StatusRules.can_attack(enemy):
			break
		first_action = false
	StatusRules.consume_disarm(enemy)
	if enemy.alive and ctrl.state.phase != Constants.PHASE_ENDED:
		GemEffects.run_blue_poison_turn_end_spreads(ctrl.state, enemy.uid)
	CounterfeitRules.break_after_action(ctrl.state, enemy)
	ctrl._emit_changed()
	return {
		"events": events,
		"presentation_state": presentation_state,
	}


func finish_enemy_phase() -> Dictionary:
	var ctrl = _c()
	if ctrl == null:
		push_error("BattleTurnService: _ctrl is null in finish_enemy_phase")
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	if ctrl.state == null:
		return {"events": [] as Array[Dictionary], "presentation_state": null}
	var presentation_state: GameState = ctrl.state.clone()
	var events: Array[Dictionary] = []
	# All poison, burning, and other turn-end status damage settles together
	# after every combatant has completed its action window.
	StatusRules.tick_turn_end(ctrl.state, events)
	ctrl._check_battle_end()
	if ctrl.state.phase == Constants.PHASE_ENDED:
		return {"events": events, "presentation_state": presentation_state}
	ctrl.state.turn_index += 1
	GemEffects.tick_turn_start(ctrl.state)
	StatusRules.tick_unit_turn_start(ctrl.state, ctrl.state.get_player())
	ctrl.state.phase = Constants.PHASE_PLAYER
	ctrl.state.bootstrap_split_controllable_turn()
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	ctrl.state.clear_split_move()
	for unit in ctrl.state.units.values():
		if unit.team == Constants.TEAM_ENEMY:
			StatusRules.clear_extra_action_statuses(unit)
	ctrl.selected_action = ""
	if ctrl.state.get_player() != null:
		ctrl.selected_unit_uid = ctrl.state.player_uid
	_apply_move_bonus(ctrl.state)
	# 回合标记和移动账本必须先于任何回合开始自动行动初始化。
	# 过载 AI 接管可能执行拔取和移动，沿用上回合标记会漏触发赝品，
	# 在移动后才建账则会让飞轮重复计算已经消耗的移动力。
	RelicBattleRules.begin_player_turn(ctrl.state)
	var overload_result: Dictionary = OverloadRules.tick_turn_start(ctrl.state)
	events.append_array(overload_result.get("events", [] as Array[Dictionary]))
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl.state.log("敌方回合结束")
	ctrl.state.on_turn_start.emit(ctrl.state.turn_index)
	ctrl._check_battle_end()
	var auto_enemy_execution: Dictionary = {}
	var player: UnitState = ctrl.state.get_player()
	if ctrl.state.phase != Constants.PHASE_ENDED and not _StatusActionRules.turn_skip_status(player).is_empty():
		# 行动跳过状态占用玩家自己的行动窗口；无需等待玩家再点一次结束回合。
		auto_enemy_execution = begin_enemy_phase()
	ctrl._emit_changed()
	return {
		"events": events,
		"presentation_state": presentation_state,
		"action": str(overload_result.get("action", "")),
		"auto_enemy_execution": auto_enemy_execution,
	}


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
	if ctrl.editor_battle_active():
		_keep_editor_playable(ctrl, player)
		return
	var enemies_empty: bool = ctrl.state.get_alive_enemies().is_empty()
	# A split clone can die before the last enemy is removed.  The corpse still
	# owns the gems, so victory must settle the lineage before the ordinary
	# player-death branch turns the encounter into a loss.
	if enemies_empty and player != null and (player.alive or player.has_tag(Constants.TAG_UNIT_SPLIT_CLONE)):
		if not _merge_split_clones_on_win(ctrl):
			ctrl.state.log("战斗结算：分裂回归未完成，暂不结束战斗以避免丢失宝石")
			ctrl._emit_changed()
			return
		ctrl.state.phase = Constants.PHASE_ENDED
		ctrl.state.result = "win"
		ctrl.state.log("战斗胜利")
		ctrl.state.on_battle_end.emit("win")
		ctrl.battle_ended.emit("win")
		return
	if player == null or not player.alive:
		if _try_inherit_split_clone(ctrl):
			return
		ctrl.state.phase = Constants.PHASE_ENDED
		ctrl.state.result = "lose"
		ctrl.state.log("战斗失败")
		ctrl.state.on_battle_end.emit("lose")
		ctrl.battle_ended.emit("lose")
		return
	ctrl._emit_changed()


func _keep_editor_playable(ctrl, player: UnitState) -> void:
	if player != null and player.alive and not ctrl.state.get_alive_enemies().is_empty():
		return
	var needs_reset: bool = (
		ctrl.state.phase == Constants.PHASE_ENDED
		or not ctrl.state.result.is_empty()
		or ctrl.state.phase != Constants.PHASE_PLAYER
	)
	# Editor deaths are observable state, not a terminal result. Return to the
	# player phase so the board remains editable even if death happened during
	# enemy resolution or a previously terminal state is being repaired.
	ctrl.state.phase = Constants.PHASE_PLAYER
	ctrl.state.result = ""
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	ctrl.state.clear_split_move()
	ctrl.selected_action = ""
	if needs_reset:
		ctrl.state.log("编辑模式：死亡状态保留，战斗未结算")
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
	# 兜底：从存活的黑槽死亡分身里找一个接班，排除蓝槽临时分身。
	var survivors: Array = []
	for unit in ctrl.state.units.values():
		if (
			unit.alive
			and unit.team == Constants.TEAM_PLAYER
			and unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE)
			and not unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE)
		):
			survivors.append(unit)
	if survivors.is_empty():
		return false
	var heir: UnitState = survivors[0]
	ctrl.state.player_uid = heir.uid
	ctrl.selected_unit_uid = heir.uid
	ctrl.state.player_moved = false
	ctrl.state.player_acted = false
	ctrl.state.clear_split_move()
	ctrl.state.log("玩家死亡，%s 接班" % heir.uid)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._emit_changed()
	return true


func _merge_split_clones_on_win(ctrl) -> bool:
	var player: UnitState = ctrl.state.get_player()
	if player == null or not player.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
		return true
	var origin_uid: String = player.split_origin_uid
	var origin: UnitState = ctrl.state.units.get(origin_uid, null)
	if origin == null:
		push_error("BattleTurnService: missing split origin %s" % origin_uid)
		return false
	var living_clones: Array[UnitState] = ctrl.state.get_alive_split_clones(origin_uid)
	var all_clones: Array[UnitState] = ctrl.state.get_split_clones(origin_uid)
	if all_clones.is_empty():
		push_error("BattleTurnService: split origin %s has no clones to merge" % origin_uid)
		return false
	var total_hp := 0
	for clone in living_clones:
		total_hp += clone.hp
	var merged_hp := maxi(1, total_hp / CombatConfig.split_death_hp_merge_divisor())
	# 死亡分身作为尸体保留槽内宝石；胜利合并时与存活分身一起回收到原体。
	if not _return_split_clone_gems(ctrl.state, origin, all_clones):
		ctrl.state.log("战斗结算：分身宝石回归失败，保留分身以避免丢失")
		return false
	for clone in all_clones:
		ctrl.state.unregister_unit(clone)
	origin.alive = true
	origin.hp = mini(merged_hp, origin.max_hp)
	ctrl.state.move_unit(origin, player.pos)
	origin.facing = player.facing
	ctrl.state.player_uid = origin.uid
	ctrl.state.controllable_queue.clear()
	ctrl.selected_unit_uid = origin.uid
	ctrl.state.rebuild_occupancy()
	OverloadRules.sync_active_mutations_to_overload_slots(ctrl.state, true)
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl.state.log("战斗结算：分身合并回归原体 HP=%d" % origin.hp)
	return true


func _return_split_clone_gems(state: GameState, origin: UnitState, clones: Array[UnitState]) -> bool:
	var reserved_slots: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var transfers: Array[Dictionary] = []
	for clone in clones:
		for source_slot: SlotState in clone.slots:
			if source_slot == null or source_slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(source_slot.gem_uid, null)
			if gem == null:
				push_error("BattleTurnService: split clone references missing gem %s" % source_slot.gem_uid)
				return false
			candidates.append({
				"gem": gem,
				"source_slot": source_slot,
				"recorded_index": int(state.battle_temp_flags.get(
					GemEffects.split_origin_slot_key(gem.uid),
					-1
				)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_index := int(a.get("recorded_index", -1))
		var b_index := int(b.get("recorded_index", -1))
		if (a_index >= 0) != (b_index >= 0):
			return a_index >= 0
		if a_index != b_index:
			return a_index < b_index
		return (a["gem"] as GemState).uid < (b["gem"] as GemState).uid
	)
	for candidate: Dictionary in candidates:
		var gem: GemState = candidate["gem"]
		var source_slot: SlotState = candidate["source_slot"]
		var target_slot := _find_split_origin_slot(state, origin, source_slot, gem.uid, reserved_slots)
		if target_slot == null:
			target_slot = _append_split_merge_overload_slot(origin, source_slot)
		var target_index := origin.slots.find(target_slot)
		reserved_slots[target_index] = true
		transfers.append({"gem": gem, "slot": target_slot})
	for transfer in transfers:
		if not GemTransfer.to_unit_slot(state, transfer["gem"], origin, transfer["slot"]):
			push_error("BattleTurnService: failed to return split gem %s" % transfer["gem"].uid)
			return false
		state.battle_temp_flags.erase(GemEffects.split_origin_slot_key(transfer["gem"].uid))
	return true


func _append_split_merge_overload_slot(origin: UnitState, source_slot: SlotState) -> SlotState:
	var target := SlotState.create(
		source_slot.slot_type,
		"",
		false,
		Constants.LOCK_OVERLOAD_SLOT
	)
	target.dual_type = source_slot.dual_type
	target.overload_slot = true
	target.overload_mutation_deferred = source_slot.overload_mutation_deferred
	origin.slots.append(target)
	return target


func _find_split_origin_slot(
	state: GameState,
	origin: UnitState,
	source_slot: SlotState,
	gem_uid: String,
	reserved_slots: Dictionary
) -> SlotState:
	var recorded_index := int(state.battle_temp_flags.get(GemEffects.split_origin_slot_key(gem_uid), -1))
	var recorded_slot := origin.get_slot_by_index(recorded_index)
	if _is_available_split_origin_slot(origin, recorded_slot, source_slot, reserved_slots):
		return recorded_slot
	for candidate: SlotState in origin.slots:
		if _is_available_split_origin_slot(origin, candidate, source_slot, reserved_slots):
			return candidate
	return null


func _is_available_split_origin_slot(
	origin: UnitState,
	candidate: SlotState,
	source_slot: SlotState,
	reserved_slots: Dictionary
) -> bool:
	if candidate == null or not candidate.gem_uid.is_empty():
		return false
	var index := origin.slots.find(candidate)
	if index < 0 or reserved_slots.has(index):
		return false
	return (
		candidate.slot_type == source_slot.slot_type
		and candidate.dual_type == source_slot.dual_type
		and candidate.is_overload_slot() == source_slot.is_overload_slot()
	)
