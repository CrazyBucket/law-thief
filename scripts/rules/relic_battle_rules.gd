class_name RelicBattleRules
extends RefCounted


static func begin_player_turn(state: GameState) -> void:
	if state == null:
		return
	var player := state.get_player()
	var capacity := StatusRules.effective_move_points(player, player.move_points) if player != null else 0
	state.relic_battle.begin_player_turn(capacity)


static func begin_next_controllable(state: GameState) -> void:
	if state == null:
		return
	var player := state.get_player()
	if player == null:
		return
	state.relic_battle.add_controlled_unit_capacity(
		StatusRules.effective_move_points(player, player.move_points)
	)


static func grant_temp_move(state: GameState, source_id: String, amount: int) -> void:
	if state == null or amount <= 0:
		return
	var player := state.get_player()
	if player == null:
		return
	player.move_points += amount
	state.relic_battle.add_temp_move(source_id, amount)


static func record_voluntary_move(
	state: GameState,
	actor_uid: String,
	from_pos: Vector2i,
	spent_move: int,
	window_finished: bool
) -> void:
	if state == null or actor_uid != state.player_uid or spent_move <= 0:
		return
	reconcile_move_capacity(state)
	state.relic_battle.record_move_segment(from_pos, spent_move)
	clear_temp_move(state)
	if window_finished:
		finish_movement_window(state, actor_uid)


static func finish_movement_window(state: GameState, actor_uid: String = "") -> void:
	if state == null:
		return
	var summary := state.relic_battle.finish_movement_action()
	if summary.is_empty():
		return
	var registry := _relic_effect_registry()
	if registry == null:
		return
	registry.fire_event("voluntary_move_finished", state, {
		"actor_uid": state.player_uid if actor_uid.is_empty() else actor_uid,
		"from": summary.get("from", Vector2i(-1, -1)),
		"to": state.get_player().pos if state.get_player() != null else Vector2i(-1, -1),
		"spent_move": int(summary.get("spent_move", 0)),
	})


static func clear_temp_move(state: GameState) -> void:
	if state == null:
		return
	var amount := state.relic_battle.take_all_temp_move()
	if amount <= 0:
		return
	var player := state.get_player()
	if player != null:
		player.move_points = maxi(0, player.move_points - amount)


static func reconcile_move_capacity(state: GameState) -> void:
	if state == null:
		return
	var player := state.get_player()
	if player == null:
		return
	state.relic_battle.reconcile_active_capacity(
		StatusRules.effective_move_points(player, player.move_points)
	)


static func enemy_intent_snapshot(state: GameState) -> Dictionary:
	var snapshot: Dictionary = {}
	if state == null:
		return snapshot
	var enemy_uids: Array[String] = []
	for enemy in state.get_alive_enemies():
		enemy_uids.append(enemy.uid)
	enemy_uids.sort()
	for enemy_uid in enemy_uids:
		var enemy: UnitState = state.units.get(enemy_uid, null)
		if enemy == null or enemy.intent == null:
			snapshot[enemy_uid] = null
		elif enemy.intent.action_plan != null:
			snapshot[enemy_uid] = enemy.intent.action_plan.to_dict()
		else:
			snapshot[enemy_uid] = {
				"type": enemy.intent.type,
				"target_uid": enemy.intent.target_uid,
				"target_pos": enemy.intent.target_pos,
				"path": enemy.intent.path.duplicate(),
				"affected_cells": enemy.intent.affected_cells.duplicate(),
				"base_damage": enemy.intent.base_damage,
				"damage": enemy.intent.damage,
				"damage_components": enemy.intent.damage_components.map(
					func(component): return component.to_dict()
				),
				"preview_effects": enemy.intent.preview_effects.map(
					func(effect): return effect.to_dict()
				),
			}
	return snapshot


static func fire_gem_operation_result(
	state: GameState,
	actor_uid: String,
	operation: String,
	before_intents: Dictionary
) -> void:
	var registry := _relic_effect_registry()
	if registry == null:
		return
	registry.fire_event("after_gem_operation", state, {
		"actor_uid": actor_uid,
		"operation": operation,
		"enemy_intent_changed": before_intents != enemy_intent_snapshot(state),
	})


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")
