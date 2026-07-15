class_name RunRecordBuilder
extends RefCounted


static func build(run: RunState, result: String, ended_at: int) -> Dictionary:
	if run == null:
		return {}
	var gold_earned := 0
	var gold_spent := 0
	for raw_entry in run.resource_ledger:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		if str(entry.get("resource_id", "")) != "gold":
			continue
		var delta := int(entry.get("final_amount", 0))
		if delta >= 0:
			gold_earned += delta
		else:
			gold_spent += -delta
	var active_rule_ids: Array[String] = []
	for raw_rule in run.adventure_rules:
		if raw_rule is Dictionary:
			active_rule_ids.append(str((raw_rule as Dictionary).get("rule_id", "")))
	return {
		"run_id": "run_%d_%d" % [ended_at, run.master_seed],
		"type": "run",
		"result": result,
		"chapter_reached": run.current_chapter,
		"ended_at": ended_at,
		"master_seed": run.master_seed,
		"summary": {
			"gold_earned": gold_earned,
			"gold_spent": gold_spent,
			"owned_relics": run.owned_relics.duplicate(),
			"active_rule_ids": active_rule_ids,
		},
	}
