extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

const PROFILES: Array[String] = [
	"explosion",
	"poison",
	"gravity",
	"arc",
	"fire_gem",
	"ice",
	"split",
]

const PROFILE_GEM: Dictionary = {
	"explosion": Constants.GEM_EXPLOSION,
	"poison": Constants.GEM_POISON,
	"gravity": Constants.GEM_GRAVITY,
	"arc": Constants.GEM_CONDUCTIVE,
	"fire_gem": Constants.GEM_FIRE,
	"ice": Constants.GEM_ICE,
	"split": Constants.GEM_SPLIT,
}

const PLAYER_POS := Vector2i(2, 3)
const MAIN_AIM := Vector2i(5, 3)
const WING_POS := Vector2i(4, 2)
const ARC_VICTIM_POS := Vector2i(6, 3)
const PULL_TARGET_POS := Vector2i(4, 3)

var _failed := false
var _case_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Attack Tag Combo Matrix Test ===")
	var total := 1 << PROFILES.size()
	for mask in range(1, total):
		_run_combo_case(_profiles_from_mask(mask))
	_test_dual_color_slot_mount()
	if _failed:
		push_error("ATTACK_TAG_COMBO_TEST_FAIL")
		quit(1)
		return
	print("ATTACK_TAG_COMBO_TEST_PASS (%d combinations)" % _case_count)
	quit(0)


func _profiles_from_mask(mask: int) -> Array:
	var result: Array = []
	for i in range(PROFILES.size()):
		if (mask & (1 << i)) != 0:
			result.append(PROFILES[i])
	return result


func _run_combo_case(profiles: Array) -> void:
	_case_count += 1
	var label := "+".join(profiles)
	var state := _create_isolated_state()
	var player := state.get_player()
	_ensure_red_slots(player, profiles.size())
	_mount_profiles(state, player, profiles)
	var arena := _setup_arena(state, player, profiles)
	var result := AttackPipeline.execute_aimed(
		state,
		player,
		MAIN_AIM,
		[AttackPipeline.TAG_RANGED],
		{},
		CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("[%s] attack failed: %s" % [label, result.get("reason", "")])
		return
	var events: Array = result.get("events", [])
	if not EventValidator.assert_valid(events, "attack_tag_combo.%s" % label):
		_fail("[%s] emitted invalid combat events" % label)
		return
	if not BattleInvariantChecker.assert_valid(state, "attack_tag_combo.%s" % label):
		_fail("[%s] violated battle invariants" % label)
		return
	if not _assert_combo(label, profiles, events, arena, player):
		return
	print("  [OK] %s" % label)


func _test_dual_color_slot_mount() -> void:
	var state := _create_isolated_state()
	var player := state.get_player()
	var dual_slot := player.get_slot(Constants.SLOT_BLUE)
	dual_slot.dual_type = Constants.SLOT_RED
	_mount_red_gem_on_slot(state, player, dual_slot, Constants.GEM_FIRE)
	state.move_unit(player, PLAYER_POS)
	var main := _spawn_guard(state, MAIN_AIM, 60)
	var result := AttackPipeline.execute_aimed(
		state, player, MAIN_AIM, [AttackPipeline.TAG_RANGED], {}, CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("[dual_slot] attack failed")
		return
	var events: Array = result.get("events", [])
	if not events.any(func(e): return str(e.get("type", "")) == "fire_burst"):
		_fail("[dual_slot] expected fire_burst")
		return
	if not main.has_status(Constants.STATUS_BURNING):
		_fail("[dual_slot] target should burn")
		return
	_case_count += 1
	print("  [OK] dual_color_slot_mount")


func _assert_combo(
	label: String,
	profiles: Array,
	events: Array,
	arena: Dictionary,
	player: UnitState
) -> bool:
	var shots := 3 if profiles.has("split") else 1
	var main: UnitState = arena.get("main")
	if profiles.has("explosion"):
		var n := _count_events(events, "explode")
		if n != shots:
			_fail("[%s] expected %d explode events, got %d" % [label, shots, n])
			return false
	if profiles.has("poison"):
		var n := _count_events(events, "poison_burst")
		if n < shots:
			_fail("[%s] expected >= %d poison_burst events, got %d" % [label, shots, n])
			return false
		if main.alive and not main.has_status(Constants.STATUS_POISON):
			_fail("[%s] main target should be poisoned" % label)
			return false
	if profiles.has("fire_gem"):
		var n := _count_events(events, "fire_burst")
		if n < shots:
			_fail("[%s] expected >= %d fire_burst events, got %d" % [label, shots, n])
			return false
		if main.alive and not main.has_status(Constants.STATUS_BURNING):
			_fail("[%s] main target should be burning" % label)
			return false
	if profiles.has("ice"):
		if _count_events(events, "frost_pulse") < 1:
			_fail("[%s] expected frost_pulse event" % label)
			return false
		if not player.has_status(Constants.STATUS_SLOWED):
			_fail("[%s] attacker should be slowed" % label)
			return false
		if main.alive and not main.has_status(Constants.STATUS_SLOWED):
			_fail("[%s] main target should be slowed" % label)
			return false
	if profiles.has("gravity"):
		if _count_events(events, "gem_flash") < 1:
			_fail("[%s] expected gem_flash for gravity" % label)
			return false
		if _count_events(events, "move_step") < 1:
			_fail("[%s] expected pull move_step for gravity" % label)
			return false
	if profiles.has("arc"):
		var arc_min := 2 if profiles.has("split") else 1
		var n := _count_events(events, "arc")
		if n < arc_min:
			_fail("[%s] expected >= %d arc events, got %d" % [label, arc_min, n])
			return false
		var arc_victim: UnitState = arena.get("arc_victim")
		if arc_victim.hp >= 60:
			_fail("[%s] arc bounce victim should take damage" % label)
			return false
	if profiles.has("split"):
		if _count_events(events, "projectile") < 3:
			_fail("[%s] expected >= 3 projectile events for split" % label)
			return false
		var wing: UnitState = arena.get("wing")
		if wing != null and wing.hp >= 60:
			_fail("[%s] wing target should take split damage" % label)
			return false
	if not profiles.has("explosion") and main.alive and main.hp >= 60:
		_fail("[%s] main target should take direct damage without explosion" % label)
		return false
	return true


func _setup_arena(state: GameState, player: UnitState, profiles: Array) -> Dictionary:
	state.move_unit(player, PLAYER_POS)
	player.base_attack = 8
	var arena := {}
	arena["main"] = _spawn_guard(state, MAIN_AIM, 60)
	if profiles.has("arc"):
		arena["arc_victim"] = _spawn_guard(state, ARC_VICTIM_POS, 60)
	if profiles.has("split"):
		arena["wing"] = _spawn_guard(state, WING_POS, 60)
	return arena


func _create_isolated_state() -> GameState:
	var builder := ScenarioBuilder.new("fission_slime_test", 42, true)
	builder.clear_slots(builder.player())
	return builder.finish()


func _ensure_red_slots(player: UnitState, needed: int) -> void:
	while player.slots_accepting(Constants.SLOT_RED).size() < needed:
		player.slots.append(SlotState.create(Constants.SLOT_RED))


func _mount_profiles(state: GameState, player: UnitState, profiles: Array) -> void:
	var red_slots := player.slots_accepting(Constants.SLOT_RED)
	for i in range(profiles.size()):
		var profile: String = str(profiles[i])
		var gem_id: String = str(PROFILE_GEM.get(profile, ""))
		assert(not gem_id.is_empty(), "unknown profile: %s" % profile)
		_mount_red_gem_on_slot(state, player, red_slots[i], gem_id)


func _mount_red_gem_on_slot(state: GameState, player: UnitState, slot: SlotState, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = str(reg.call("_next_uid", "gem"))
	var gem := GemState.create(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	assert(GemTransfer.to_unit_slot(state, gem, player, slot))


func _spawn_guard(state: GameState, pos: Vector2i, hp: int) -> UnitState:
	var guard := UnitState.new()
	guard.uid = "matrix_guard_%d_%d" % [pos.x, pos.y]
	guard.unit_def_id = "unit_patrol_guard"
	guard.team = Constants.TEAM_ENEMY
	guard.pos = pos
	guard.hp = hp
	guard.max_hp = hp
	guard.speed = 5
	guard.base_attack = 4
	guard.alive = true
	state.register_unit(guard)
	return guard


func _count_events(events: Array, event_type: String) -> int:
	var n := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			n += 1
	return n


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
