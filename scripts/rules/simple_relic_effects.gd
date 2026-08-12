class_name SimpleRelicEffects
extends RefCounted

const _RelicBattleRules = preload("res://scripts/rules/relic_battle_rules.gd")


static func add_temp_move(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var condition := str(effect.get("condition", ""))
	if condition == "actor_is_player" and str(payload.get("actor_uid", "")) != state.player_uid:
		return
	if condition == "intent_changed_once_per_turn":
		if str(payload.get("actor_uid", "")) != state.player_uid:
			return
		if not bool(payload.get("enemy_intent_changed", false)):
			return
		var turn_flag := "%s_intent_move" % relic_id
		if bool(state.relic_battle.turn_flags.get(turn_flag, false)):
			return
		state.relic_battle.turn_flags[turn_flag] = true
	var amount := _resolve_amount(effect)
	_RelicBattleRules.grant_temp_move(state, relic_id, amount)
	state.log("[Relic] %s -> temporary move +%d" % [relic_id, amount])


static func grant_shield_if_adjacent_after_move(
	relic_id: String,
	effect: Dictionary,
	state: GameState,
	payload: Dictionary
) -> void:
	if str(payload.get("actor_uid", "")) != state.player_uid or int(payload.get("spent_move", 0)) <= 0:
		return
	var player := state.get_player()
	if player == null or not player.alive:
		return
	if not state.get_alive_enemies().any(func(enemy): return BoardUtils.are_units_adjacent(player, enemy)):
		return
	var amount := _resolve_amount(effect)
	StatusRules.apply_shield(state, player, amount)
	state.log("[Relic] %s -> +%d shield for %s" % [relic_id, amount, player.uid])


static func store_unused_move(relic_id: String, state: GameState) -> void:
	_RelicBattleRules.reconcile_move_capacity(state)
	var turn_flag := "%s_stored_turn" % relic_id
	if bool(state.relic_battle.turn_flags.get(turn_flag, false)):
		return
	state.relic_battle.turn_flags[turn_flag] = true
	var layers := state.relic_battle.remaining_move()
	if layers <= 0:
		return
	state.relic_battle.flywheel_layers += layers
	state.log("[Relic] %s -> flywheel +%d layers" % [relic_id, layers])


static func clear_flywheel_on_manual_shot(relic_id: String, state: GameState, payload: Dictionary) -> void:
	if not bool(payload.get("manual_player_shot", false)):
		return
	if str(payload.get("attacker_uid", "")) != state.player_uid or state.relic_battle.flywheel_layers <= 0:
		return
	state.relic_battle.flywheel_layers = 0
	state.log("[Relic] %s -> flywheel cleared" % relic_id)


static func manual_shot_damage_bonus(effect: Dictionary, state: GameState, ctx: Dictionary) -> int:
	if not bool(ctx.get("manual_player_shot", false)) or str(ctx.get("attacker_uid", "")) != state.player_uid:
		return 0
	return int(_resolve_number(effect, "value", 0.0)) * state.relic_battle.flywheel_layers


static func apply_flywheel_damage(ctx) -> void:
	var registry := _relic_effect_registry()
	if registry == null:
		return
	var bonus: int = int(registry.query_modifier("manual_shot_damage_bonus", ctx.state, {
		"attacker_uid": ctx.attacker.uid,
		"manual_player_shot": bool(ctx.payload.get("manual_player_shot", false)),
	}))
	if bonus <= 0:
		return
	ctx.base_damage += bonus
	ctx.push_trace({
		"phase": "damage_calculate",
		"operation": "add_flywheel_bonus",
		"value": bonus,
		"result": ctx.base_damage,
	})


static func fire_direct_hit(ctx, target: UnitState, dealt: int) -> void:
	var registry := _relic_effect_registry()
	if registry == null:
		return
	registry.fire_event("after_attack_hit", ctx.state, {
		"attacker_uid": ctx.attacker.uid,
		"target_uid": target.uid,
		"damage": dealt,
		"manual_player_shot": bool(ctx.payload.get("manual_player_shot", false)),
		"attack_event_id": str(ctx.payload.get("attack_event_id", "")),
	})


static func _resolve_amount(effect: Dictionary) -> int:
	return int(_resolve_number(effect, "amount", 1.0))


static func _resolve_number(effect: Dictionary, field_id: String, fallback: float) -> float:
	var ref_key := "%s_ref" % field_id
	if effect.has(ref_key):
		var registry := _data_registry()
		return registry.get_relic_numeric_ref(str(effect.get(ref_key, "")), fallback) if registry != null else fallback
	return float(effect.get(field_id, fallback))


static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")
