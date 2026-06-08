extends SceneTree

const Snapshot = preload("res://scripts/testkit/state_snapshot.gd")
const SnapshotDiff = preload("res://scripts/testkit/state_diff.gd")
const Builder = preload("res://scripts/testkit/scenario_builder.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var builder = Builder.new("fission_slime_test", 991, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(2, 3))
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_EXPLOSION, Constants.GEM_EXPLOSION, Constants.GEM_EXPLOSION])
	var target := builder.add_unit(
		"snapshot_test_target",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(5, 3),
		{"hp": 100, "max_hp": 100}
	)
	var state := builder.finish()
	var before := Snapshot.capture(state, [], false)
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	var events: Array = result.get("events", [])
	var after := Snapshot.capture(state, events, false)
	var diff := SnapshotDiff.between(before, after)
	assert(result.get("ok", false))
	assert(target.hp == 76, "three red explosions should deal 24 damage according to detailed gem design")
	assert(after["invariants"].is_empty())
	assert(after["event_violations"].is_empty())
	assert(not diff["units"]["changed"].is_empty())
	print("TESTKIT_SNAPSHOT_PASS")
	quit(0)
