extends Node

const ROOM_DEFS_PATH := "res://resources/adventure/room_defs.json"
const _Validator = preload("res://scripts/services/adventure_config_validator.gd")

var _room_defs: Dictionary = {}


func _ready() -> void:
	_load_room_defs()


func reload_config() -> void:
	_load_room_defs()


func get_room_def(room_type: String) -> Dictionary:
	var raw: Variant = _room_defs.get(room_type, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func get_room_ui_kind(room_type: String) -> String:
	return str(get_room_def(room_type).get("ui_kind", "placeholder"))


func evaluate_conditions(conditions: Array, ctx: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var reasons: Array[String] = []
	for raw_condition in conditions:
		if not raw_condition is Dictionary:
			errors.append("invalid_condition")
			reasons.append("条件配置无效")
			continue
		var condition := raw_condition as Dictionary
		var result := _evaluate_condition(condition, ctx)
		if not bool(result.get("ok", false)):
			errors.append(str(result.get("error", "condition_failed")))
			reasons.append(str(result.get("reason", "条件不满足")))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"disabled_reason": reasons[0] if not reasons.is_empty() else "",
	}


func apply_effects(effects: Array, ctx: Dictionary = {}) -> Dictionary:
	var results: Array[Dictionary] = []
	var summaries: Array[String] = []
	for i in range(effects.size()):
		var raw_effect: Variant = effects[i]
		if not raw_effect is Dictionary:
			return {"ok": false, "error": "invalid_effect"}
		var effect_result := _apply_effect(raw_effect as Dictionary, ctx, i)
		if not bool(effect_result.get("ok", false)):
			return effect_result
		results.append(effect_result.duplicate(true))
		var summary := str(effect_result.get("summary", ""))
		if not summary.is_empty():
			summaries.append(summary)
	return {
		"ok": true,
		"results": results,
		"summaries": summaries,
		"summary": "，".join(summaries),
	}


func _apply_effect(effect: Dictionary, ctx: Dictionary, effect_index: int) -> Dictionary:
	var transaction_id := _effect_transaction_id(ctx, effect_index)
	match str(effect.get("action", "")):
		"grant_resource":
			var grant_amount_result := _resolve_numeric_field(effect, "amount")
			if not bool(grant_amount_result.get("ok", false)):
				return grant_amount_result
			var grant_result := EconomyService.grant(
				str(effect.get("resource_id", "gold")),
				int(grant_amount_result.get("value", 0.0)),
				"event_reward",
				_merge_ctx(ctx, {"transaction_id": transaction_id})
			)
			if not bool(grant_result.get("ok", false)):
				return grant_result
			var entry: Dictionary = grant_result.get("entry", {})
			return {"ok": true, "summary": EconomyService.format_entry(entry), "entry": entry}
		"spend_resource":
			var spend_amount_result := _resolve_numeric_field(effect, "amount")
			if not bool(spend_amount_result.get("ok", false)):
				return spend_amount_result
			var spend_result := EconomyService.spend(
				str(effect.get("resource_id", "gold")),
				int(spend_amount_result.get("value", 0.0)),
				"event_cost",
				_merge_ctx(ctx, {"transaction_id": transaction_id})
			)
			if not bool(spend_result.get("ok", false)):
				return spend_result
			var spend_entry: Dictionary = spend_result.get("entry", {})
			return {"ok": true, "summary": EconomyService.format_entry(spend_entry), "entry": spend_entry}
		"heal_player":
			var heal_amount_result := _resolve_numeric_field(effect, "amount")
			if not bool(heal_amount_result.get("ok", false)):
				return heal_amount_result
			var heal_result := RunService.heal_player_amount(int(heal_amount_result.get("value", 0.0)))
			return {"ok": true, "summary": "恢复 %d 点生命" % int(heal_result.get("amount", 0)), "heal": heal_result}
		"heal_player_percent":
			var heal_percent_amount_result := _resolve_numeric_field(effect, "amount")
			if not bool(heal_percent_amount_result.get("ok", false)):
				return heal_percent_amount_result
			var heal_percent_result := RunService.heal_player_percent(float(heal_percent_amount_result.get("value", 0.0)))
			return {"ok": true, "summary": "恢复 %d 点生命" % int(heal_percent_result.get("amount", 0)), "heal": heal_percent_result}
		"damage_player":
			var damage_amount_result := _resolve_numeric_field(effect, "amount")
			if not bool(damage_amount_result.get("ok", false)):
				return damage_amount_result
			var damage_result := RunService.damage_player_amount(int(damage_amount_result.get("value", 0.0)))
			return {"ok": true, "summary": "失去 %d 点生命" % int(damage_result.get("amount", 0)), "damage": damage_result}
		"grant_relic":
			var relic_id := str(effect.get("relic_id", ""))
			if relic_id.is_empty():
				return {"ok": false, "error": "missing_relic_id"}
			RunService.acquire_relic(relic_id)
			return {"ok": true, "summary": "获得遗物 %s" % relic_id}
		"grant_gem":
			var gem_id := str(effect.get("gem_id", ""))
			if gem_id.is_empty():
				return {"ok": false, "error": "missing_gem_id"}
			var gem_result := RunService.acquire_gem(gem_id)
			if not bool(gem_result.get("ok", false)):
				return gem_result
			return {"ok": true, "summary": "获得宝石 %s" % DataRegistry.get_gem_display_name(gem_id)}
		"add_adventure_rule":
			var add_rule_result := AdventureRuleRegistry.add_rule(
				str(effect.get("rule_id", "")),
				str(effect.get("scope", "run")),
				str(ctx.get("room_id", "")),
				ctx
			)
			if not bool(add_rule_result.get("ok", false)):
				return add_rule_result
			var display := AdventureRuleRegistry.get_rule_display(str(effect.get("rule_id", "")))
			return {"ok": true, "summary": "获得规则 %s" % str(display.get("name", effect.get("rule_id", "")))}
		"remove_adventure_rule":
			var remove_rule_result := AdventureRuleRegistry.remove_rule(str(effect.get("rule_id", "")), ctx)
			if not bool(remove_rule_result.get("ok", false)):
				return remove_rule_result
			var remove_display := AdventureRuleRegistry.get_rule_display(str(effect.get("rule_id", "")))
			return {"ok": true, "summary": "移除规则 %s" % str(remove_display.get("name", effect.get("rule_id", "")))}
		_:
			return {"ok": false, "error": "unknown_effect"}


func _evaluate_condition(condition: Dictionary, _ctx: Dictionary) -> Dictionary:
	match str(condition.get("type", "")):
		"resource_gte":
			var resource_id := str(condition.get("resource_id", "gold"))
			var amount_result := _resolve_numeric_field(condition, "amount")
			if not bool(amount_result.get("ok", false)):
				return amount_result
			var amount := int(amount_result.get("value", 0.0))
			if EconomyService.get_balance(resource_id) >= amount:
				return {"ok": true}
			return {"ok": false, "error": "resource_gte_failed", "reason": "%s 不足" % resource_id}
		"hp_below_ratio":
			var run := RunService.get_run()
			if run == null:
				return {"ok": false, "error": "no_active_run", "reason": "当前没有进行中的冒险"}
			var max_hp := maxi(1, int(run.player_max_hp))
			if float(run.player_hp) / float(max_hp) < float(condition.get("ratio", 1.0)):
				return {"ok": true}
			return {"ok": false, "error": "hp_below_ratio_failed", "reason": "生命条件不满足"}
		"has_relic":
			var relic_id := str(condition.get("relic_id", ""))
			if RunService.has_relic(relic_id):
				return {"ok": true}
			return {"ok": false, "error": "has_relic_failed", "reason": "缺少遗物 %s" % relic_id}
		"not_has_relic":
			var blocked_relic_id := str(condition.get("relic_id", ""))
			if not RunService.has_relic(blocked_relic_id):
				return {"ok": true}
			return {"ok": false, "error": "not_has_relic_failed", "reason": "已拥有遗物 %s" % blocked_relic_id}
		"has_carried_gem":
			var carried := RunService.get_run().carried_gem if RunService.get_run() != null else {}
			var required_gem_id := str(condition.get("gem_id", ""))
			if carried.is_empty():
				return {"ok": false, "error": "has_carried_gem_failed", "reason": "当前未携带宝石"}
			if required_gem_id.is_empty() or str(carried.get("gem_id", "")) == required_gem_id:
				return {"ok": true}
			return {"ok": false, "error": "has_carried_gem_failed", "reason": "携带宝石不匹配"}
		"chapter_gte":
			if RunService.get_current_chapter() >= int(condition.get("chapter", 1)):
				return {"ok": true}
			return {"ok": false, "error": "chapter_gte_failed", "reason": "章节条件不满足"}
		_:
			return {"ok": false, "error": "unknown_condition", "reason": "未知条件"}


func _effect_transaction_id(ctx: Dictionary, effect_index: int) -> String:
	var base := str(ctx.get("transaction_id", ""))
	if base.is_empty():
		base = "%s:%s" % [str(ctx.get("room_id", "room")), str(ctx.get("action_id", "effect"))]
	return "%s:effect:%d" % [base, effect_index]


func _merge_ctx(base: Dictionary, patch: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in patch.keys():
		result[key] = patch[key]
	return result


func _resolve_numeric_field(payload: Dictionary, field_id: String) -> Dictionary:
	return EconomyService.resolve_numeric_field(payload, field_id)


func _load_room_defs() -> void:
	_room_defs = _load_json(ROOM_DEFS_PATH)
	_Validator.ensure_valid(ROOM_DEFS_PATH, _Validator.validate_room_defs(_room_defs, EconomyService.get_amount_refs()))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var data: Variant = json.get_data()
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}
