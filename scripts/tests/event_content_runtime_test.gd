extends SceneTree

const _Settlement = preload("res://scripts/battle/battle_settlement_service.gd")
const _GemPlacement = preload("res://scripts/services/run_player_gem_service.gd")

var _adventure: Node
var _events: Node
var _run_service: Node
var _seed := 93000


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Event Content Runtime Test ===")
	_adventure = root.get_node("AdventureService")
	_events = root.get_node("EventService")
	_run_service = root.get_node("RunService")
	for test_case in [
		Callable(self, "_test_availability_filter"),
		Callable(self, "_test_scribe"),
		Callable(self, "_test_furnace"),
		Callable(self, "_test_injury_appraisal"),
		Callable(self, "_test_auction"),
		Callable(self, "_test_execution_order"),
		Callable(self, "_test_slag_refiner"),
		Callable(self, "_test_common_reforge"),
		Callable(self, "_test_rare_reforge"),
		Callable(self, "_test_anesthetist"),
		Callable(self, "_test_evidence_cabinet"),
	]:
		if not bool(test_case.call()):
			return
	_run_service.end_run()
	print("EVENT_CONTENT_RUNTIME_TEST_PASS")
	quit(0)


func _test_availability_filter() -> bool:
	var furnace_room := _open_event("event_sealed_gem_furnace", 1)
	var furnace_view: Dictionary = _events.get_event_view(furnace_room)
	if not _require(str(furnace_view.get("event_id", "")) != "event_sealed_gem_furnace", "sealed furnace must not appear in chapter one"):
		return false
	var order_room := _open_event("event_preliminary_execution_order", 2, Vector2i(5, 4))
	var order_view: Dictionary = _events.get_event_view(order_room)
	if not _require(str(order_view.get("event_id", "")) != "event_preliminary_execution_order", "execution order must not appear after layer eight"):
		return false
	var scribe_room := _open_event("event_misaccounting_scribe", 3, Vector2i(4, 3))
	var scribe_view: Dictionary = _events.get_event_view(scribe_room)
	if not _require(str(scribe_view.get("event_id", "")) != "event_misaccounting_scribe", "scribe must not appear after chapter-three layer six"):
		return false
	print("  [OK] chapter and late-layer restrictions reroute invalid production events")
	return true


func _test_scribe() -> bool:
	var room_id := _open_event("event_misaccounting_scribe", 1)
	var run: RunState = _run_service.get_run()
	var slots := _GemPlacement.slot_snapshots(run)
	var first := (slots[0] as Dictionary).duplicate(true)
	first["gem_id"] = "gem_poison"
	run.player_slot_gems[0] = first
	var view: Dictionary = _events.get_event_view(room_id)
	if not _require(str(view.get("event_id", "")) == "event_misaccounting_scribe", "scribe should stay selected"):
		return false
	if not _require(_has_option(view, "large"), "scribe large gamble should appear with a destructible gem"):
		return false
	var state: Dictionary = _event_state(room_id)
	var data: Dictionary = state.get("data", {})
	var hp_before := int(_run_service.get_player_run_snapshot().get("hp", 0))
	var gold_before: int = _run_service.get_balance("gold")
	var result: Dictionary = _events.choose_option(room_id, "small")
	if not _require(bool(result.get("ok", false)), "scribe small gamble should resolve"):
		return false
	if bool(data.get("small_success", false)):
		if not _require(_run_service.get_balance("gold") > gold_before, "successful scribe gamble should grant snapped gold"):
			return false
	else:
		if not _require(int(_run_service.get_player_run_snapshot().get("hp", 0)) == hp_before - 7, "failed scribe gamble should cost 7 HP in chapter one"):
			return false
	print("  [OK] scribe uses snapshotted chapter-scaled outcomes and a real gem-loss branch")
	return true


func _test_furnace() -> bool:
	var room_id := _open_event("event_sealed_gem_furnace", 2)
	_events.get_event_view(room_id)
	var state := _event_state(room_id)
	var queue: Array = (state.get("data", {}) as Dictionary).get("queue", [])
	if not _require(queue.size() == 3 and _unique_count(queue) == 3, "furnace should snapshot three distinct gems"):
		return false
	var take: Dictionary = _events.choose_option(room_id, "take")
	if not _require(bool(take.get("ok", false)) and not bool(take.get("result", {}).get("resolved", true)), "taking a furnace gem should wait for placement"):
		return false
	var hold: Dictionary = _events.choose_option(room_id, "hold")
	if not _require(bool(hold.get("ok", false)) and str(_run_service.get_run().carried_gem.get("gem_id", "")) == str(queue[0]), "furnace reward should support holding"):
		return false
	print("  [OK] sealed furnace snapshots a visible three-gem queue and places the chosen reward")
	return true


func _test_injury_appraisal() -> bool:
	var room_id := _open_event("event_injury_appraisal", 1)
	var run: RunState = _run_service.get_run()
	run.player_max_hp = 100
	run.player_hp = 20
	var view: Dictionary = _events.get_event_view(room_id)
	if not _require(str(view.get("body", "")).count("\n") >= 2, "injury appraisal should present a two-paragraph event description"):
		return false
	if not _require(_has_option(view, "relief") and not _has_option(view, "treatment"), "low health should replace treatment with one-run relief"):
		return false
	if not _require(bool(_events.choose_option(room_id, "relief").get("ok", false)), "relief should resolve"):
		return false
	if not _require(run.player_hp == 30 and bool(run.run_stats.get("injury_relief_claimed", false)), "relief should heal 10 and persist its run flag"):
		return false
	print("  [OK] injury appraisal swaps paid treatment for one-run low-health relief")
	return true


func _test_auction() -> bool:
	var room_id := _open_event("event_counterfeit_auction", 2)
	_run_service.set_resource_balance("gold", 300)
	_run_service.acquire_relic("relic_vernier_caliper")
	var view: Dictionary = _events.get_event_view(room_id)
	var safe := _option_by_id(view, "buy_safe")
	if not _require(str(safe.get("label", "")).contains("真品") or str(safe.get("label", "")).contains("赝品"), "vernier caliper should reveal authenticity"):
		return false
	var state := _event_state(room_id)
	var data: Dictionary = state.get("data", {})
	var price := int(data.get("safe_price", 0))
	var relic_id := str(data.get("safe_relic", ""))
	if not _require(bool(_events.choose_option(room_id, "buy_safe").get("ok", false)), "auction purchase should resolve"):
		return false
	if not _require(_run_service.get_balance("gold") == 300 - price and _run_service.has_relic(relic_id), "auction should spend snapped price and grant snapped outcome"):
		return false
	print("  [OK] auction locks price/authenticity/relic and caliper reveals only authenticity")
	return true


func _test_execution_order() -> bool:
	var room_id := _open_event("event_preliminary_execution_order", 1)
	if not _require(bool(_events.choose_option(room_id, "sign").get("ok", false)), "execution order should be signable"):
		return false
	var first := _Settlement.grant_combat_gold("withheld_1", "NORMAL_COMBAT")
	var replay := _Settlement.grant_combat_gold("withheld_1", "NORMAL_COMBAT")
	var second := _Settlement.grant_combat_gold("withheld_2", "ELITE_COMBAT")
	var third := _Settlement.grant_combat_gold("paid_3", "END")
	if not _require(bool(first.get("withheld", false)) and bool(replay.get("withheld", false)) and bool(second.get("withheld", false)), "first two distinct battles should be withheld and replay safe"):
		return false
	if not _require(int(third.get("amount", 0)) > 0 and int(_run_service.get_run().run_stats.get("combat_gold_withheld_remaining", -1)) == 0, "third battle should pay normally"):
		return false
	print("  [OK] execution order withholds exactly two distinct combat gold settlements across room types")
	return true


func _test_slag_refiner() -> bool:
	var room_id := _open_event("event_slag_refiner", 2)
	var run: RunState = _run_service.get_run()
	var slots := _GemPlacement.slot_snapshots(run)
	for fixture in [[0, "gem_poison"], [1, "gem_fire"]]:
		var snapshot := (slots[int(fixture[0])] as Dictionary).duplicate(true)
		snapshot["gem_id"] = str(fixture[1])
		run.player_slot_gems[int(fixture[0])] = snapshot
	var start: Dictionary = _events.get_event_view(room_id)
	if not _require(bool(_option_by_id(start, "stable").get("enabled", false)), "stable refining should enable with two common gems"):
		return false
	_events.choose_option(room_id, "stable")
	_events.choose_option(room_id, "toggle:slot:0")
	_events.choose_option(room_id, "toggle:slot:1")
	var confirm: Dictionary = _events.choose_option(room_id, "confirm")
	if not _require(bool(confirm.get("ok", false)), "stable refining should commit two selected gems"):
		return false
	var candidates: Array = ((_event_state(room_id).get("data", {}) as Dictionary).get("reward_candidates", []))
	if not _require(candidates.size() == 2 and _unique_count(candidates) == 2 and not "gem_poison" in candidates and not "gem_fire" in candidates, "stable candidates should be distinct and exclude sacrificed types"):
		return false
	_events.choose_option(room_id, "reward:0")
	var placement: Dictionary = _events.get_event_view(room_id)
	var place_id := str((placement.get("options", []) as Array)[0].get("id", ""))
	if not _require(bool(_events.choose_option(room_id, place_id).get("ok", false)), "refined reward should embed immediately"):
		return false
	print("  [OK] slag refiner selects and destroys exact gems, then offers distinct non-common rewards")
	return true


func _test_common_reforge() -> bool:
	var room_id := _open_event("event_unlicensed_reforge", 2)
	_run_service.acquire_relic("relic_crowbar")
	var count_before: int = _run_service.get_owned_relics().size()
	_events.choose_option(room_id, "common")
	var result: Dictionary = _events.choose_option(room_id, "sacrifice:relic_crowbar")
	if not _require(bool(result.get("ok", false)) and bool(result.get("result", {}).get("resolved", false)), "common reforge should resolve in one blind roll"):
		return false
	if not _require(not _run_service.has_relic("relic_crowbar") and _run_service.get_owned_relics().size() == count_before, "common reforge should replace without increasing relic count"):
		return false
	print("  [OK] common reforge is a one-for-one blind replacement")
	return true


func _test_rare_reforge() -> bool:
	var room_id := _open_event("event_unlicensed_reforge", 3)
	_run_service.acquire_relic("relic_autopsy_log")
	var count_before: int = _run_service.get_owned_relics().size()
	_events.choose_option(room_id, "rare")
	var sacrifice: Dictionary = _events.choose_option(room_id, "sacrifice:relic_autopsy_log")
	if not _require(bool(sacrifice.get("ok", false)) and not bool(sacrifice.get("result", {}).get("resolved", true)), "rare reforge should continue to a reward choice"):
		return false
	var candidates: Array = ((_event_state(room_id).get("data", {}) as Dictionary).get("reward_candidates", []))
	if not _require(not candidates.is_empty() and candidates.size() <= 3 and _unique_count(candidates) == candidates.size() and not "relic_autopsy_log" in candidates, "rare reforge should offer up to three distinct legal relics"):
		return false
	if not _require(bool(_events.choose_option(room_id, "reward:0").get("ok", false)) and _run_service.get_owned_relics().size() == count_before, "rare reforge choice should restore relic count"):
		return false
	print("  [OK] rare reforge destroys first, then grants one of up to three distinct rare relics")
	return true


func _test_anesthetist() -> bool:
	var room_id := _open_event("event_alley_anesthetist", 1)
	var run: RunState = _run_service.get_run()
	run.player_max_hp = 60
	run.player_hp = 20
	_events.get_event_view(room_id)
	var data: Dictionary = _event_state(room_id).get("data", {})
	if not _require(bool(_events.choose_option(room_id, "first").get("ok", false)), "first injection should resolve into a second decision"):
		return false
	var expected_first := 32 if bool(data.get("first_success", false)) else 13
	if not _require(run.player_hp == expected_first and str(_event_state(room_id).get("phase", "")) == "second", "first injection should use its room-entry snapshot"):
		return false
	if not _require(bool(_events.choose_option(room_id, "second").get("ok", false)) and run.player_hp >= 1, "second injection should resolve and remain nonlethal"):
		return false
	print("  [OK] anesthetist locks both hidden outcomes and keeps failed injections nonlethal")
	return true


func _test_evidence_cabinet() -> bool:
	var room_id := _open_event("event_evidence_cabinet", 3)
	var run: RunState = _run_service.get_run()
	_run_service.set_resource_balance("gold", 200)
	var slots := _GemPlacement.slot_snapshots(run)
	for i in range(slots.size()):
		var snapshot := (slots[i] as Dictionary).duplicate(true)
		snapshot["gem_id"] = "gem_poison"
		run.player_slot_gems[i] = snapshot
	run.carried_gem = {"gem_id": "gem_fire"}
	var original_slots := run.player_slot_gems.size()
	if not _require(bool(_events.choose_option(room_id, "open_black").get("ok", false)) and _run_service.get_balance("gold") == 125, "black drawer should charge before reveal"):
		return false
	_events.choose_option(room_id, "reward:0")
	var placement: Dictionary = _events.get_event_view(room_id)
	if not _require(not _has_option(placement, "hold"), "occupied hand should not offer a second carried gem"):
		return false
	var place_id := str((placement.get("options", []) as Array)[0].get("id", ""))
	if not _require(place_id.ends_with(":1"), "fully occupied slots should offer overload placement"):
		return false
	if not _require(bool(_events.choose_option(room_id, place_id).get("ok", false)) and run.player_slot_gems.size() == original_slots + 1 and str(run.carried_gem.get("gem_id", "")) == "gem_fire", "cabinet reward should overload without replacing the carried gem"):
		return false
	print("  [OK] evidence cabinet pays before reveal and supports reward overload with an occupied hand")
	return true


func _open_event(event_id: String, chapter: int, cell: Vector2i = Vector2i.ZERO) -> String:
	_seed += 1
	_adventure.start_new_run(_seed)
	var run: RunState = _run_service.get_run()
	_adventure._begin_chapter_map(chapter, run.map_seed)
	_adventure.current_pos = cell
	_adventure.pending_room_type = "EVENT"
	var node = _adventure.get_current_node()
	node.room_type = "EVENT"
	node.properties["event_id"] = event_id
	var room_id: String = _adventure.current_room_id()
	return room_id


func _event_state(room_id: String) -> Dictionary:
	return _run_service.get_room_state(room_id).get("snapshot", {}).get("event", {})


func _has_option(view: Dictionary, option_id: String) -> bool:
	return not _option_by_id(view, option_id).is_empty()


func _option_by_id(view: Dictionary, option_id: String) -> Dictionary:
	for raw in view.get("options", []):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == option_id:
			return raw as Dictionary
	return {}


func _unique_count(items: Array) -> int:
	var unique := {}
	for item in items:
		unique[str(item)] = true
	return unique.size()


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
