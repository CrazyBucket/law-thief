extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_width_levels()
	_test_element_styles()
	_test_fx_overrides()
	_test_eight_direction_aim()
	_test_path_dye()
	_test_light_poison_is_colored_status_not_fog()
	_test_light_fire_is_colored_status_not_fire_tile()
	_test_light_arc_keeps_beam_and_bounces()
	_test_light_flurry_arc_keeps_defeated_anchor()
	_test_light_ice_slows_target_not_attacker()
	_test_light_split_emits_multiple_beams()
	_test_light_split_explosion_event_order()
	_test_light_explosion_blasts_at_beam_end()
	_test_light_gravity_does_not_pull()
	_test_light_ignores_blue_gravity_deflect()
	_test_light_counter_does_not_followup()
	_test_light_echo_does_not_followup()
	if _failed:
		push_error("LIGHT_GEM_EFFECT_TEST_FAIL")
		quit(1)
		return
	print("LIGHT_GEM_EFFECT_TEST_PASS")
	quit(0)


func _test_width_levels() -> void:
	var level_1 := GemEffects.light_beam_width_for_level(1)
	var level_2 := GemEffects.light_beam_width_for_level(2)
	var level_3 := GemEffects.light_beam_width_for_level(3)
	assert(level_1 < level_2 and level_2 < level_3, "light beam must become thicker at every level")


func _test_element_styles() -> void:
	var expected := {
		"fire": Color(1.0, 0.24, 0.12),
		"poison": Color(0.05, 0.95, 0.18),
		"arc": Color(1.0, 0.92, 0.22),
		"ice": Color(0.55, 0.9, 1.0),
		"explosion": Color(1.0, 0.58, 0.18),
	}
	for element in expected:
		var ctx := _context_with_tag(element)
		var event := GemEffects.build_light_beam_event(Vector2i.ZERO, Vector2i.ONE, ctx)
		assert(str(event.get("element", "")) == element, "beam should carry its element shader style")
		assert(event.get("color", Color.TRANSPARENT).is_equal_approx(expected[element]), "beam color should match element")


func _test_fx_overrides() -> void:
	var event := GemEffects.build_light_beam_event(
		Vector2i.ZERO,
		Vector2i.ONE,
		{},
		1.75,
		{"power": 1.8, "noise": 0.7}
	)
	assert(is_equal_approx(float(event.get("width", 0.0)), 1.75), "beam width should be a continuous parameter")
	assert(is_equal_approx(float(event.get("power", 0.0)), 1.8), "beam power override should survive event construction")
	assert(is_equal_approx(float(event.get("noise", 0.0)), 0.7), "beam noise override should survive event construction")


func _test_eight_direction_aim() -> void:
	var attacker := UnitState.new()
	attacker.pos = Vector2i(3, 3)
	for target in [Vector2i(3, 7), Vector2i(7, 3), Vector2i(7, 7), Vector2i(0, 0)]:
		assert(GemEffects.is_valid_light_aim(attacker, target), "cardinal and diagonal light aims must be valid")
	for target in [Vector2i(5, 7), Vector2i(7, 4), Vector2i(3, 3)]:
		assert(not GemEffects.is_valid_light_aim(attacker, target), "off-axis light aims must be rejected")


func _test_path_dye() -> void:
	var state := _mini_state()
	TileRules.create_fire(state, Vector2i(2, 2))
	var fire_ctx := GemEffects.light_context_with_path_dye(
		state,
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)],
		{}
	)
	assert(GemEffects.light_element_for_context(fire_ctx) == "fire", "fire on the beam path must dye the beam")
	assert(GemEffects.light_color_for_context(fire_ctx).is_equal_approx(Color(1.0, 0.24, 0.12)), "fire dye must change beam color")

	TileRules.create_poison_fog(state, Vector2i(4, 4))
	var poison_ctx := GemEffects.light_context_with_path_dye(
		state,
		[Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)],
		{}
	)
	assert(GemEffects.light_element_for_context(poison_ctx) == "poison", "last overlay on the beam path must control dye")
	assert(GemTagResolver.has_tag(poison_ctx, "poison"), "path dye must also apply its element status")
	var transitions := GemEffects.light_dye_transitions(
		state,
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]
	)
	assert(transitions.size() == 2, "beam must change color only when it reaches a dye overlay")
	assert(transitions[0].get("cell") == Vector2i(2, 2), "fire dye must begin where the beam crosses fire")
	assert(transitions[1].get("cell") == Vector2i(4, 4), "poison dye must begin where the beam crosses poison")


func _test_light_poison_is_colored_status_not_fog() -> void:
	var builder = Builder.new("fission_slime_test", 7101, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_POISON])
	var target := builder.add_unit("light_poison_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+poison attack should succeed")
	_check(target.hp == 95, "light+poison should deal light damage only before poison status")
	_check(target.has_status(Constants.STATUS_POISON), "light+poison should apply poison as colored light status")
	_check(target.has_status(Constants.STATUS_LIGHT_EXPOSED), "light+poison should still expose the target")
	_check(_count_tiles(state, Constants.TILE_MOD_POISON_FOG) == 0, "light+poison should not create poison fog at the aim cell")
	_check(_count_events(events, "poison_burst") == 0, "light+poison should not emit normal poison burst")
	_check(_count_events(events, "light_beam") == 1, "light+poison should emit one beam")


func _test_light_fire_is_colored_status_not_fire_tile() -> void:
	var builder = Builder.new("fission_slime_test", 7111, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_FIRE])
	var target := builder.add_unit("light_fire_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+fire attack should succeed")
	_check(target.hp == 95, "light+fire should deal light damage only before burning")
	_check(target.has_status(Constants.STATUS_BURNING), "light+fire should burn as colored light status")
	_check(_count_tiles(state, Constants.TILE_MOD_FIRE) == 0, "light+fire should not create normal fire tile at aim cell")
	_check(_count_events(events, "fire_burst") == 0, "light+fire should not emit normal fire burst")
	_check(_count_events(events, "light_beam") == 1, "light+fire should emit one beam")


func _test_light_arc_keeps_beam_and_bounces() -> void:
	var builder = Builder.new("fission_slime_test", 7112, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_CONDUCTIVE])
	var target := builder.add_unit("light_arc_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var arc_target := builder.add_unit("light_arc_chain", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+arc attack should succeed")
	_check(target.hp == 95, "light+arc should deal light damage to beam target")
	_check(arc_target.hp < 100, "light+arc should bounce from the lit target")
	_check(_count_events(events, "arc") >= 1, "light+arc should emit arc bounce")
	_check(_count_events(events, "light_beam") == 1, "light+arc should emit one beam")


func _test_light_flurry_arc_keeps_defeated_anchor() -> void:
	var builder = Builder.new("fission_slime_test", 7118, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_CONDUCTIVE, Constants.GEM_FLURRY])
	var target := builder.add_unit("light_flurry_lethal", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 2, "max_hp": 2})
	var arc_target := builder.add_unit("light_flurry_arc_chain", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(not target.alive, "the first light segment should defeat its target")
	_check(_count_events(events, "light_beam") == 2, "light flurry should preserve both beam segments")
	_check(_count_events(events, "arc") == 2, "both light segments should arc from the retained hit anchor")
	_check(arc_target.hp == 96, "light flurry should preserve two independent 2-damage arc hits")


func _test_light_ice_slows_target_not_attacker() -> void:
	var builder = Builder.new("fission_slime_test", 7113, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_ICE])
	var target := builder.add_unit("light_ice_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+ice attack should succeed")
	_check(target.hp == 95, "light+ice should deal light damage")
	_check(target.has_status(Constants.STATUS_SLOWED), "light+ice should slow the lit target")
	_check(not player.has_status(Constants.STATUS_SLOWED), "light+ice should not run normal ice self-slow")
	_check(_count_events(events, "light_beam") == 1, "light+ice should emit one beam")


func _test_light_split_emits_multiple_beams() -> void:
	var builder = Builder.new("fission_slime_test", 7102, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(2, 3))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_SPLIT])
	var main := builder.add_unit("light_split_main", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 3), {"hp": 100, "max_hp": 100})
	var upper := builder.add_unit("light_split_upper", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 1), {"hp": 100, "max_hp": 100})
	var lower := builder.add_unit("light_split_lower", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 5), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, main.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+split attack should succeed")
	_check(_count_events(events, "light_beam") == 3, "light+split level 1 should fire three beams")
	_check(_count_events(events, "projectile") == 0, "light+split should not fall back to normal split projectiles")
	_check(main.hp < 100 and upper.hp < 100 and lower.hp < 100, "light+split beams should damage all three lanes")


func _test_light_explosion_blasts_at_beam_end() -> void:
	var builder = Builder.new("fission_slime_test", 7103, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_EXPLOSION])
	var target := builder.add_unit("light_explosion_mid", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var blast_victim := builder.add_unit("light_explosion_end_neighbor", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+explosion attack should succeed")
	_check(target.hp == 95, "light+explosion should not explode at the normal aim target")
	_check(blast_victim.hp == 89, "light+explosion should deal 5 beam damage plus 6 adjacent explosion damage")
	_check(_has_event_at(events, "explode", Vector2i(7, 1)), "light+explosion should emit explosion at beam end")
	_check(not _has_event_at(events, "explode", target.pos), "light+explosion should not emit explosion at the aim cell")


func _test_light_split_explosion_event_order() -> void:
	var builder = Builder.new("fission_slime_test", 71031, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 3))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_SPLIT, Constants.GEM_EXPLOSION])
	var target := builder.add_unit("light_split_explosion_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
	builder.add_unit("light_split_explosion_victim", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 3), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	var explode_index := -1
	var explosion_damage_index := -1
	for i in range(events.size()):
		var event: Dictionary = events[i]
		if explode_index < 0 and str(event.get("type", "")) == "explode":
			explode_index = i
		if explosion_damage_index < 0 and str(event.get("type", "")) == "damage" and str(event.get("reason", "")) == "explosion_cross":
			explosion_damage_index = i
	_check(_count_events(events, "light_beam") == 3, "light+split+explosion should still emit one concurrent beam volley")
	_check(explode_index >= 0 and explosion_damage_index > explode_index, "explosion damage must remain behind its explosion animation event")


func _test_light_gravity_does_not_pull() -> void:
	var builder = Builder.new("fission_slime_test", 7114, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_GRAVITY])
	var target := builder.add_unit("light_gravity_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+gravity attack should still fire as a light beam")
	_check(target.hp == 95, "light+gravity should deal plain light damage")
	_check(target.pos == Vector2i(4, 1), "light+gravity is not a declared combo and should not pull target")
	_check(_count_events(events, "move_step") == 0, "light+gravity should not emit gravity movement")
	_check(_count_events(events, "light_beam") == 1, "light+gravity should emit one beam")


func _test_light_ignores_blue_gravity_deflect() -> void:
	var builder = Builder.new("fission_slime_test", 7117, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT])
	var target := builder.add_unit("light_gravity_deflect_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target)
	builder.mount_gems(target, Constants.SLOT_BLUE, [Constants.GEM_GRAVITY, Constants.GEM_GRAVITY, Constants.GEM_GRAVITY])
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light should attack through blue gravity deflect")
	_check(target.hp == 95, "blue gravity should not deflect or block a light beam")
	_check(_count_events(events, "projectile_deflect") == 0, "light beam should not emit projectile deflect")
	_check(_count_events(events, "light_beam") == 1, "light attack should remain a beam")


func _test_light_counter_does_not_followup() -> void:
	var builder = Builder.new("fission_slime_test", 7115, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_COUNTER])
	var target := builder.add_unit("light_counter_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+counter attack should still fire as a light beam")
	_check(target.hp == 95, "light+counter should not run counter followup")
	_check(_count_events(events, "light_beam") == 1, "light+counter should emit one beam")


func _test_light_echo_does_not_followup() -> void:
	var builder = Builder.new("fission_slime_test", 7116, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 1))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_ECHO, Constants.GEM_ECHO, Constants.GEM_ECHO])
	var target := builder.add_unit("light_echo_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	_check(result.get("ok", false), "light+echo attack should still fire as a light beam")
	_check(target.hp == 95, "light+echo should not run echo followup")
	_check(not _has_echo_followup(events), "light+echo should not emit echo followup flash")
	_check(_count_events(events, "light_beam") == 1, "light+echo should emit one beam")


func _mini_state() -> GameState:
	var state := GameState.new()
	state.board_size = Vector2i(8, 8)
	for y in range(state.board_size.y):
		for x in range(state.board_size.x):
			var pos := Vector2i(x, y)
			state.tiles[state.tile_key(pos)] = TileState.create(pos, Constants.TILE_FLOOR)
	return state


func _context_with_tag(tag: String) -> Dictionary:
	return {
		"tag_levels": {tag: 1},
		"tag_counts": {tag: 1},
		"tags": [tag],
	}


func _count_tiles(state: GameState, modifier: String) -> int:
	var count := 0
	for tile: TileState in state.tiles.values():
		if tile.has_modifier(modifier):
			count += 1
	return count


func _count_events(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


func _has_event_at(events: Array, event_type: String, pos: Vector2i) -> bool:
	for event in events:
		if str(event.get("type", "")) == event_type and event.get("pos", Vector2i(-999, -999)) == pos:
			return true
	return false


func _has_echo_followup(events: Array) -> bool:
	for event in events:
		if str(event.get("type", "")) == "gem_flash" and bool(event.get("echo_followup", false)):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
