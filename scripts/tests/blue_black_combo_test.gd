extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

const PROFILES: Array[String] = [
	"explosion",
	"poison",
	"gravity",
	"arc",
	"fire_gem",
	"ice",
	"split",
]

const BLUE_CONTACT_PROFILES: Array[String] = ["poison", "fire_gem", "ice"]

const BLUE_DAMAGED_PROFILES: Array[String] = ["explosion", "gravity", "arc", "split"]

const PROFILE_GEM: Dictionary = {
	"explosion": Constants.GEM_EXPLOSION,
	"poison": Constants.GEM_POISON,
	"gravity": Constants.GEM_GRAVITY,
	"arc": Constants.GEM_CONDUCTIVE,
	"fire_gem": Constants.GEM_FIRE,
	"ice": Constants.GEM_ICE,
	"split": Constants.GEM_SPLIT,
	"light": Constants.GEM_LIGHT,
	"counter": Constants.GEM_COUNTER,
	"echo": Constants.GEM_ECHO,
}

const VICTIM_POS := Vector2i(4, 3)
const NEIGHBOR_POS := Vector2i(5, 3)
const ATTACKER_POS := Vector2i(2, 3)

var _failed := false
var _case_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Blue/Black Gem Combo Matrix Test ===")
	var contact_total := 1 << BLUE_CONTACT_PROFILES.size()
	for mask in range(1, contact_total):
		_run_blue_contact_case(_profiles_from_list(BLUE_CONTACT_PROFILES, mask))
	var damaged_total := 1 << BLUE_DAMAGED_PROFILES.size()
	for mask in range(1, damaged_total):
		_run_blue_damaged_case(_profiles_from_list(BLUE_DAMAGED_PROFILES, mask))
	var black_total := 1 << PROFILES.size()
	for mask in range(1, black_total):
		_run_black_death_case(_profiles_from_list(PROFILES, mask))
	_test_dual_blue_slot_contact()
	_test_blue_explosion_events()
	_test_blue_poison_turn_end_spread_uses_level_context()
	_test_blue_light_reflects_ranged_attack()
	_test_blue_counter_reflects_damage()
	_test_blue_counter_level_two_carries_tags()
	_test_black_poison_level_two_emits_fog()
	_test_black_poison_level_three_spreads_to_two_targets()
	_test_black_light_judges_exposed_targets()
	_test_black_counter_hits_killer()
	_test_black_death_priority_over_slot_order()
	if _failed:
		push_error("BLUE_BLACK_COMBO_TEST_FAIL")
		quit(1)
		return
	print("BLUE_BLACK_COMBO_TEST_PASS (%d cases)" % _case_count)
	quit(0)


func _profiles_from_list(profiles: Array, mask: int) -> Array:
	var result: Array = []
	for i in range(profiles.size()):
		if (mask & (1 << i)) != 0:
			result.append(profiles[i])
	return result


func _run_blue_contact_case(profiles: Array) -> void:
	_case_count += 1
	var label := "blue_contact:" + "+".join(profiles)
	var state := _create_state()
	var carrier := _spawn_unit(state, "contact_carrier", VICTIM_POS + Vector2i(-1, 0), Constants.TEAM_PLAYER)
	_ensure_blue_slots(carrier, profiles.size())
	_mount_on_slots(state, carrier, Constants.SLOT_BLUE, profiles)
	var target := _spawn_unit(state, "contact_target", VICTIM_POS, Constants.TEAM_ENEMY)
	ContactResolver.on_attack_contact(state, carrier, target)
	if profiles.has("poison") and not target.has_status(Constants.STATUS_POISON):
		_fail("[%s] target should be poisoned" % label)
		return
	if profiles.has("fire_gem") and not target.has_status(Constants.STATUS_BURNING):
		_fail("[%s] target should be burning" % label)
		return
	if profiles.has("ice") and not target.has_status(Constants.STATUS_SLOWED):
		_fail("[%s] target should be slowed" % label)
		return
	print("  [OK] %s" % label)


func _run_blue_damaged_case(profiles: Array) -> void:
	_case_count += 1
	var label := "blue_damaged:" + "+".join(profiles)
	var state := _create_state()
	var attacker := _spawn_unit(state, "damaged_attacker", ATTACKER_POS, Constants.TEAM_PLAYER)
	var victim := _spawn_unit(state, "damaged_victim", VICTIM_POS, Constants.TEAM_ENEMY, 40)
	var deflect_neighbor := _spawn_unit(state, "deflect_neighbor", NEIGHBOR_POS, Constants.TEAM_ENEMY, 40)
	_ensure_blue_slots(victim, profiles.size())
	_mount_on_slots(state, victim, Constants.SLOT_BLUE, profiles)
	var victim_hp_before := victim.hp
	var neighbor_hp_before := deflect_neighbor.hp
	var attacker_hp_before := attacker.hp
	var reason := "ranged_attack"
	if profiles.has("explosion"):
		StatusRules.apply_burning(state, victim, 1, attacker.uid)
		reason = "burning"
	var dealt := CombatRules.apply_damage(state, victim, 6, attacker.uid, reason)
	if profiles.has("split") and not profiles.has("explosion"):
		if dealt >= 6:
			_fail("[%s] split blue should reduce damage taken" % label)
			return
	if profiles.has("gravity"):
		if deflect_neighbor.hp >= neighbor_hp_before:
			_fail("[%s] gravity blue should deflect damage to neighbor" % label)
			return
	if profiles.has("explosion"):
		if deflect_neighbor.hp >= neighbor_hp_before and victim.hp >= victim_hp_before:
			_fail("[%s] explosion blue should damage on burning hit" % label)
			return
	if profiles.has("arc"):
		if attacker.hp >= attacker_hp_before and victim.hp >= victim_hp_before:
			_fail("[%s] arc blue should rebound or victim should take damage" % label)
			return
	if victim.hp >= victim_hp_before and not profiles.has("split"):
		_fail("[%s] victim should take damage" % label)
		return
	print("  [OK] %s" % label)


func _run_black_death_case(profiles: Array) -> void:
	_case_count += 1
	var label := "black_death:" + "+".join(profiles)
	var state := _create_state()
	var neighbor := _spawn_unit(state, "death_neighbor", NEIGHBOR_POS, Constants.TEAM_ENEMY, 80)
	var victim := _spawn_unit(state, "death_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	_ensure_black_slots(victim, profiles.size())
	_mount_on_slots(state, victim, Constants.SLOT_BLACK, profiles)
	var poison_level := _profile_stack_level(profiles, "poison")
	if poison_level > 0:
		StatusRules.apply_slowed(state, victim, 2, "test_poison_payload")
	var poison_overlay_before := _count_poison_overlays(state)
	var unit_count_before := state.units.size()
	var events := _kill_and_collect_events(state, victim)
	if profiles.has("explosion"):
		if _count_events(events, "explode") < 1:
			_fail("[%s] expected explode on death" % label)
			return
	if profiles.has("poison"):
		if not neighbor.has_status(Constants.STATUS_SLOWED):
			_fail("[%s] poison death should transfer an existing debuff" % label)
			return
		var expect_poison_burst := poison_level >= 2 or profiles.has("explosion")
		if expect_poison_burst:
			if _count_events(events, "poison_burst") < 1:
				_fail("[%s] expected poison_burst on death" % label)
				return
			if _count_poison_overlays(state) <= poison_overlay_before:
				_fail("[%s] expected poison overlay on death" % label)
				return
		elif _count_events(events, "poison_burst") > 0:
			_fail("[%s] level 1 poison death should not emit poison_burst without combo" % label)
			return
	if profiles.has("gravity"):
		if neighbor.pos == NEIGHBOR_POS:
			_fail("[%s] gravity death should pull neighbor" % label)
			return
	if profiles.has("arc"):
		if _count_events(events, "lightning") < 1:
			_fail("[%s] expected lightning on death" % label)
			return
		if neighbor.hp >= 80:
			_fail("[%s] arc death should damage neighbor" % label)
			return
	if profiles.has("fire_gem"):
		if _count_events(events, "fire_burst") < 1:
			_fail("[%s] expected fire_burst on death" % label)
			return
	if profiles.has("ice"):
		if _count_events(events, "frost_pulse") < 1:
			_fail("[%s] expected frost_pulse on death" % label)
			return
		if not neighbor.has_status(Constants.STATUS_SLUGGISH):
			_fail("[%s] neighbor should be sluggish after ice death" % label)
			return
	if profiles.has("split"):
		if _count_events(events, "split_spawn") < 1:
			_fail("[%s] expected split_spawn on death" % label)
			return
		if state.units.size() <= unit_count_before:
			_fail("[%s] split death should spawn clones" % label)
			return
	print("  [OK] %s" % label)


func _test_blue_explosion_events() -> void:
	_case_count += 1
	var state := _create_state()
	var attacker := _spawn_unit(state, "burn_attacker", ATTACKER_POS, Constants.TEAM_PLAYER)
	var victim := _spawn_unit(state, "burn_victim", VICTIM_POS, Constants.TEAM_ENEMY, 40)
	_mount_on_slots(state, victim, Constants.SLOT_BLUE, ["explosion"])
	StatusRules.apply_burning(state, victim, 1, attacker.uid)
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, victim, 6, attacker.uid, "burning")
	state.unbind_combat_events()
	if _count_events(events, "explode") < 1:
		_fail("[blue_explosion_events] burning hit should emit explode event")
		return
	print("  [OK] blue_explosion_events")


func _test_blue_poison_turn_end_spread_uses_level_context() -> void:
	_case_count += 1
	var state := _create_state()
	var owner := _spawn_unit(state, "poison_owner", Vector2i(3, 3), Constants.TEAM_ENEMY)
	var nearest_clean := _spawn_unit(state, "poison_clean", Vector2i(4, 3), Constants.TEAM_ENEMY)
	var farther_clean := _spawn_unit(state, "poison_far", Vector2i(7, 3), Constants.TEAM_ENEMY)
	_ensure_blue_slots(owner, 2)
	_mount_on_slots(state, owner, Constants.SLOT_BLUE, ["poison", "poison"])
	GemEffects.run_blue_poison_turn_end_spreads(state, owner.uid)
	var nearest_poison := nearest_clean.get_status(Constants.STATUS_POISON)
	if nearest_poison == null:
		_fail("[blue_poison_turn_end] nearest clean unit should receive poison")
		return
	if str(nearest_poison.source_uid) != owner.uid:
		_fail("[blue_poison_turn_end] spread poison source should be carrier")
		return
	if farther_clean.has_status(Constants.STATUS_POISON):
		_fail("[blue_poison_turn_end] farther ally should stay clean when nearer target exists")
		return
	print("  [OK] blue_poison_turn_end_spread_uses_level_context")


func _test_blue_light_reflects_ranged_attack() -> void:
	_case_count += 1
	var state := _create_state()
	var attacker := _spawn_unit(state, "light_blue_attacker", ATTACKER_POS, Constants.TEAM_PLAYER, 40)
	var victim := _spawn_unit(state, "light_blue_victim", VICTIM_POS, Constants.TEAM_ENEMY, 40)
	_ensure_blue_slots(victim, 2)
	_mount_on_slots(state, victim, Constants.SLOT_BLUE, ["light", "light"])
	var attacker_hp := attacker.hp
	CombatRules.apply_damage(state, victim, 6, attacker.uid, "ranged_attack")
	if attacker.hp >= attacker_hp:
		_fail("[blue_light_reflect] attacker should take reflected light damage")
		return
	if not attacker.has_status(Constants.STATUS_LIGHT_EXPOSED):
		_fail("[blue_light_reflect] attacker should gain light exposed")
		return
	print("  [OK] blue_light_reflects_ranged_attack")


func _test_blue_counter_reflects_damage() -> void:
	_case_count += 1
	var state := _create_state()
	var attacker := _spawn_unit(state, "counter_blue_attacker", ATTACKER_POS, Constants.TEAM_PLAYER, 40)
	var victim := _spawn_unit(state, "counter_blue_victim", VICTIM_POS, Constants.TEAM_ENEMY, 40)
	_ensure_blue_slots(victim, 1)
	_mount_on_slots(state, victim, Constants.SLOT_BLUE, ["counter"])
	var attacker_hp := attacker.hp
	CombatRules.apply_damage(state, victim, 6, attacker.uid, "ranged_attack")
	if attacker.hp >= attacker_hp:
		_fail("[blue_counter] attacker should take reflected damage")
		return
	print("  [OK] blue_counter_reflects_damage")


func _test_blue_counter_level_two_carries_tags() -> void:
	_case_count += 1
	var state := _create_state()
	var attacker := _spawn_unit(state, "counter_blue_l2_attacker", ATTACKER_POS, Constants.TEAM_PLAYER, 40)
	var victim := _spawn_unit(state, "counter_blue_l2_victim", VICTIM_POS, Constants.TEAM_ENEMY, 40)
	_ensure_blue_slots(victim, 2)
	_mount_on_slots(state, victim, Constants.SLOT_BLUE, ["counter", "counter"])
	_mount_on_slots(state, victim, Constants.SLOT_RED, ["fire_gem"])
	CombatRules.apply_damage(state, victim, 6, attacker.uid, "ranged_attack")
	if not attacker.has_status(Constants.STATUS_BURNING):
		_fail("[blue_counter_l2] attacker should be burning from carried tag")
		return
	print("  [OK] blue_counter_level_two_carries_tags")


func _test_black_poison_level_two_emits_fog() -> void:
	_case_count += 1
	var state := _create_state()
	var victim := _spawn_unit(state, "poison_l2_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	_ensure_black_slots(victim, 2)
	_mount_on_slots(state, victim, Constants.SLOT_BLACK, ["poison", "poison"])
	StatusRules.apply_slowed(state, victim, 2, "test_poison_payload")
	var poison_overlay_before := _count_poison_overlays(state)
	var events := _kill_and_collect_events(state, victim)
	if _count_events(events, "poison_burst") < 1:
		_fail("[black_poison_level_two] expected poison_burst")
		return
	if _count_poison_overlays(state) <= poison_overlay_before:
		_fail("[black_poison_level_two] expected poison overlay")
		return
	print("  [OK] black_poison_level_two_emits_fog")


func _test_black_poison_level_three_spreads_to_two_targets() -> void:
	_case_count += 1
	var state := _create_state()
	var victim := _spawn_unit(state, "poison_l3_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	var near_a := _spawn_unit(state, "poison_l3_a", NEIGHBOR_POS, Constants.TEAM_ENEMY, 80)
	var near_b := _spawn_unit(state, "poison_l3_b", Vector2i(4, 4), Constants.TEAM_ENEMY, 80)
	_ensure_black_slots(victim, 3)
	_mount_on_slots(state, victim, Constants.SLOT_BLACK, ["poison", "poison", "poison"])
	StatusRules.apply_slowed(state, victim, 2, "test_poison_payload")
	_kill_and_collect_events(state, victim)
	if not near_a.has_status(Constants.STATUS_SLOWED):
		_fail("[black_poison_level_three] first nearby target should receive debuff")
		return
	if not near_b.has_status(Constants.STATUS_SLOWED):
		_fail("[black_poison_level_three] second nearby target should receive debuff")
		return
	print("  [OK] black_poison_level_three_spreads_to_two_targets")


func _test_black_light_judges_exposed_targets() -> void:
	_case_count += 1
	var state := _create_state()
	var victim := _spawn_unit(state, "light_black_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	var exposed_target := _spawn_unit(state, "light_black_target", NEIGHBOR_POS, Constants.TEAM_ENEMY, 80)
	_ensure_black_slots(victim, 3)
	_mount_on_slots(state, victim, Constants.SLOT_BLACK, ["light", "light", "light"])
	StatusRules.apply_light_exposed(state, exposed_target, 2, victim.uid)
	var target_hp := exposed_target.hp
	var events := _kill_and_collect_events(state, victim)
	if exposed_target.hp >= target_hp:
		_fail("[black_light] exposed target should take judgement damage")
		return
	if not exposed_target.has_status(Constants.STATUS_BLINDED):
		_fail("[black_light] level 3 light should blind surviving targets")
		return
	if _count_events(events, "light_beam") < 1:
		_fail("[black_light] should emit light_beam event")
		return
	print("  [OK] black_light_judges_exposed_targets")


func _test_black_counter_hits_killer() -> void:
	_case_count += 1
	var state := _create_state()
	var victim := _spawn_unit(state, "counter_black_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	var killer := _spawn_unit(state, "counter_black_killer", ATTACKER_POS, Constants.TEAM_PLAYER, 40)
	_ensure_black_slots(victim, 1)
	_mount_on_slots(state, victim, Constants.SLOT_BLACK, ["counter"])
	var killer_hp := killer.hp
	CombatRules.apply_damage(state, victim, victim.hp, killer.uid, "ranged_attack")
	if killer.hp >= killer_hp:
		_fail("[black_counter] killer should take reflected death damage")
		return
	print("  [OK] black_counter_hits_killer")


func _test_black_death_priority_over_slot_order() -> void:
	_case_count += 1
	var state := _create_state()
	var neighbor := _spawn_unit(state, "prio_neighbor", NEIGHBOR_POS, Constants.TEAM_ENEMY, 80)
	var victim := _spawn_unit(state, "prio_victim", VICTIM_POS, Constants.TEAM_ENEMY, 20)
	_ensure_black_slots(victim, 2)
	var slots := victim.slots_accepting(Constants.SLOT_BLACK)
	_mount_gem_on_slot(state, victim, slots[0], Constants.GEM_EXPLOSION)
	_mount_gem_on_slot(state, victim, slots[1], Constants.GEM_CONDUCTIVE)
	var events := _kill_and_collect_events(state, victim)
	if _count_events(events, "explode") < 1:
		_fail("[black_death_priority] expected explode")
		return
	if _count_events(events, "lightning") < 1:
		_fail("[black_death_priority] arc should run before explosion knocks neighbor away")
		return
	if neighbor.hp >= 80:
		_fail("[black_death_priority] arc should damage neighbor")
		return
	print("  [OK] black_death_priority_over_slot_order")


func _test_dual_blue_slot_contact() -> void:
	_case_count += 1
	var state := _create_state()
	var carrier := state.get_player()
	state.move_unit(carrier, VICTIM_POS + Vector2i(-1, 0))
	var dual_slot := carrier.get_slot(Constants.SLOT_BLUE)
	dual_slot.dual_type = Constants.SLOT_RED
	_mount_gem_on_slot(state, carrier, dual_slot, Constants.GEM_POISON)
	var target := _spawn_unit(state, "dual_target", VICTIM_POS, Constants.TEAM_ENEMY)
	ContactResolver.on_attack_contact(state, carrier, target)
	if not target.has_status(Constants.STATUS_POISON):
		_fail("[dual_blue_slot] target should be poisoned")
		return
	print("  [OK] dual_blue_slot_contact")


func _kill_and_collect_events(state: GameState, victim: UnitState) -> Array:
	var events: Array[Dictionary] = []
	victim.hp = 0
	state.kill_unit(victim)
	GemEffects.trigger_black_death_effects(state, victim, events)
	return events


func _create_state() -> GameState:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc != null:
		var run: RunState = run_svc.get_run()
		if run != null:
			run.owned_relics.clear()
	var builder := ScenarioBuilder.new("fission_slime_test", 42, true)
	builder.clear_slots(builder.player())
	return builder.finish()


func _ensure_blue_slots(unit: UnitState, needed: int) -> void:
	while unit.slots_accepting(Constants.SLOT_BLUE).size() < needed:
		unit.slots.append(SlotState.create(Constants.SLOT_BLUE))


func _ensure_black_slots(unit: UnitState, needed: int) -> void:
	while unit.slots_accepting(Constants.SLOT_BLACK).size() < needed:
		unit.slots.append(SlotState.create(Constants.SLOT_BLACK))


func _mount_on_slots(state: GameState, unit: UnitState, slot_type: String, profiles: Array) -> void:
	var slots := unit.slots_accepting(slot_type)
	for i in range(profiles.size()):
		var profile: String = str(profiles[i])
		_mount_gem_on_slot(state, unit, slots[i], str(PROFILE_GEM.get(profile, "")))


func _profile_stack_level(profiles: Array, profile: String) -> int:
	var count := 0
	for raw in profiles:
		if str(raw) == profile:
			count += 1
	return count


func _mount_gem_on_slot(state: GameState, unit: UnitState, slot: SlotState, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	if not slot.gem_uid.is_empty():
		_GemTransfer.remove(state, slot.gem_uid)
	var gem_uid: String = str(reg.call("_next_uid", "gem"))
	var gem := GemState.create(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	assert(_GemTransfer.to_unit_slot(state, gem, unit, slot))


func _spawn_unit(
	state: GameState,
	uid: String,
	pos: Vector2i,
	team: String,
	hp: int = 30
) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.unit_def_id = "unit_patrol_guard"
	unit.team = team
	unit.pos = pos
	unit.hp = hp
	unit.max_hp = hp
	unit.speed = 5
	unit.base_attack = 6
	unit.alive = true
	unit.slots.append(SlotState.create(Constants.SLOT_RED))
	unit.slots.append(SlotState.create(Constants.SLOT_BLUE))
	unit.slots.append(SlotState.create(Constants.SLOT_BLACK))
	state.register_unit(unit)
	return unit


func _count_events(events: Array, event_type: String) -> int:
	var n := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			n += 1
	return n


func _count_poison_overlays(state: GameState) -> int:
	var n := 0
	for tile in state.tiles.values():
		if tile.has_modifier(Constants.TILE_MOD_POISON_FOG) \
			or tile.has_modifier(Constants.TILE_MOD_POISON_PUDDLE) \
			or tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE):
			n += 1
	return n


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
