class_name FightTicketRules
extends RefCounted

const META_RETALIATION := "beast_ticket_retaliation"
const META_TARGET_UID := "beast_ticket_target_uid"


static func try_mark_retaliation(
	relic_id: String,
	_effect: Dictionary,
	state: GameState,
	payload: Dictionary
) -> String:
	if state == null or state.relic_battle.beast_ticket_triggered:
		return ""
	if int(payload.get("amount", 0)) <= 0:
		return ""
	var victim_uid := str(payload.get("unit_uid", ""))
	var source_uid := str(payload.get("source_uid", ""))
	if victim_uid.is_empty() or source_uid.is_empty() or victim_uid == source_uid:
		return ""
	var victim: UnitState = state.units.get(victim_uid, null)
	var source: UnitState = state.units.get(source_uid, null)
	if not _is_living_enemy(victim) or not _is_living_enemy(source):
		return ""
	state.relic_battle.beast_ticket_triggered = true
	state.relic_battle.retaliation_targets[victim_uid] = source_uid
	state.log("[Relic] %s -> %s will retaliate against %s" % [relic_id, victim_uid, source_uid])
	_refresh_intent(state, victim_uid)
	return victim_uid


static func retaliation_target(state: GameState, unit: UnitState) -> UnitState:
	if state == null or unit == null:
		return null
	var source_uid := str(state.relic_battle.retaliation_targets.get(unit.uid, ""))
	if source_uid.is_empty():
		return null
	var source: UnitState = state.units.get(source_uid, null)
	if not _is_living_enemy(unit) or not _is_living_enemy(source) or source.uid == unit.uid:
		state.relic_battle.retaliation_targets.erase(unit.uid)
		return null
	return source


static func tag_intent(intent: IntentState, target: UnitState) -> void:
	if intent == null or target == null:
		return
	if intent.target_uid.is_empty():
		intent.target_uid = target.uid
	if intent.target_uid != target.uid:
		return
	intent.plan_metadata[META_RETALIATION] = true
	intent.plan_metadata[META_TARGET_UID] = target.uid
	var format := TranslationServer.translate("battle.intent.retaliation")
	if format == "battle.intent.retaliation":
		format = "报复 · %s"
	intent.preview_text = format % intent.preview_text


static func consume_after_intent(state: GameState, unit: UnitState, intent: IntentState, active_attack: bool) -> bool:
	if state == null or unit == null or intent == null or not active_attack:
		return false
	if not bool(intent.plan_metadata.get(META_RETALIATION, false)):
		return false
	var pending_target := str(state.relic_battle.retaliation_targets.get(unit.uid, ""))
	var intent_target := str(intent.plan_metadata.get(META_TARGET_UID, ""))
	if pending_target.is_empty() or pending_target != intent_target:
		return false
	state.relic_battle.retaliation_targets.erase(unit.uid)
	return true


static func clear_for_death(state: GameState, dead_uid: String) -> void:
	if state == null or dead_uid.is_empty():
		return
	if state.relic_battle.retaliation_targets.has(dead_uid):
		state.relic_battle.retaliation_targets.erase(dead_uid)
	for victim_uid_variant in state.relic_battle.retaliation_targets.keys():
		var victim_uid := str(victim_uid_variant)
		if str(state.relic_battle.retaliation_targets.get(victim_uid, "")) != dead_uid:
			continue
		state.relic_battle.retaliation_targets.erase(victim_uid)
		_refresh_intent(state, victim_uid)


static func _refresh_intent(state: GameState, victim_uid: String) -> void:
	var victim: UnitState = state.units.get(victim_uid, null)
	if victim == null or not victim.alive:
		return
	var intent_system: GDScript = load("res://scripts/rules/intent_system.gd")
	intent_system.refresh_unit_intent(state, victim)


static func _is_living_enemy(unit: UnitState) -> bool:
	return unit != null and unit.alive and unit.team == Constants.TEAM_ENEMY
