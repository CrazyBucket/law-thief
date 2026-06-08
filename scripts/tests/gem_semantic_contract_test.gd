extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const CONTRACT_PATH := "res://tests/contracts/gem_semantics.json"

var _failed := false
var _passed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var document := _load_contract()
	for raw_case in document.get("cases", []):
		_run_case(raw_case)
	if _failed:
		push_error("GEM_SEMANTIC_CONTRACT_FAIL passed=%d" % _passed)
		quit(1)
		return
	print("GEM_SEMANTIC_CONTRACT_PASS cases=%d" % _passed)
	quit(0)


func _run_case(contract: Dictionary) -> void:
	var builder = Builder.new("fission_slime_test", 4401, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(2, 3))
	builder.mount_gems(player, Constants.SLOT_RED, contract.get("gems", []))
	var target := builder.add_unit(
		"contract_target",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(5, 3),
		{"hp": 100, "max_hp": 100}
	)
	var state := builder.finish()
	var setup: Dictionary = contract.get("setup", {})
	if str(setup.get("target_status", "")) == Constants.STATUS_BURNING:
		StatusRules.apply_burning(state, target, 1, player.uid)
	var hp_before := target.hp
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	var expect: Dictionary = contract.get("expect", {})
	var label := str(contract.get("id", "unnamed"))

	_check(result.get("ok", false), label, "action should succeed")
	_check(hp_before - target.hp == int(expect.get("damage", -1)), label, "damage expected=%d actual=%d" % [int(expect.get("damage", -1)), hp_before - target.hp])
	if expect.has("target_status"):
		_check(target.has_status(str(expect["target_status"])), label, "target missing status %s" % expect["target_status"])
	if expect.has("fire_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_FIRE) == int(expect["fire_cells"]), label, "fire cell count expected=%d actual=%d" % [int(expect["fire_cells"]), _count_tiles(state, Constants.TILE_MOD_FIRE)])
	if expect.has("poison_fog_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_POISON_FOG) == int(expect["poison_fog_cells"]), label, "poison fog count expected=%d actual=%d" % [int(expect["poison_fog_cells"]), _count_tiles(state, Constants.TILE_MOD_POISON_FOG)])
	if expect.has("toxic_smoke_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_TOXIC_SMOKE) == int(expect["toxic_smoke_cells"]), label, "toxic smoke count expected=%d actual=%d" % [int(expect["toxic_smoke_cells"]), _count_tiles(state, Constants.TILE_MOD_TOXIC_SMOKE)])
	if expect.has("combo_event"):
		_check(_has_combo(events, str(expect["combo_event"])), label, "missing combo event %s" % expect["combo_event"])
	_check(BattleInvariantChecker.check_all(state).is_empty(), label, "battle invariant violation")
	_check(EventValidator.validate_events(events).is_empty(), label, "event invariant violation")
	if not _failed:
		_passed += 1
		print("  CONTRACT_PASS ", label)


func _count_tiles(state: GameState, modifier: String) -> int:
	var count := 0
	for tile: TileState in state.tiles.values():
		if tile.has_modifier(modifier):
			count += 1
	return count


func _has_combo(events: Array, combo: String) -> bool:
	for event in events:
		if str(event.get("combo", "")) == combo:
			return true
	return false


func _check(condition: bool, label: String, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CONTRACT_FAIL %s: %s" % [label, message])


func _load_contract() -> Dictionary:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	assert(file != null, "contract file should exist")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "contract file should be valid JSON")
	return parsed
