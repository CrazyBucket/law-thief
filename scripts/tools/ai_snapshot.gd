extends SceneTree

const Snapshot = preload("res://scripts/testkit/state_snapshot.gd")
const SnapshotDiff = preload("res://scripts/testkit/state_diff.gd")
const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const LEGACY_DESIGN_ROOT := "/Users/jinhuiwu/code/learning-notes/game/design/law-thief"
const DEFAULT_OUTPUT := "res://artifacts/verify/snapshot.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if options.has("help"):
		_print_help()
		quit(0)
		return
	var probe_gems := _csv(str(options.get("gems", "")))
	var encounter_id := str(options.get("encounter", "fission_slime_test" if not probe_gems.is_empty() else "tutorial_001"))
	var seed := int(options.get("seed", 1))
	var output := str(options.get("output", DEFAULT_OUTPUT))
	var state: GameState
	var events: Array = []
	var before: Dictionary
	var calculation_trace: Array = []
	if probe_gems.is_empty():
		var reg: Node = root.get_node("DataRegistry")
		state = reg.create_battle_state(encounter_id, seed)
		before = Snapshot.capture(state, [], false)
	else:
		var builder = Builder.new(encounter_id, seed, true)
		var actor := builder.player()
		builder.clear_slots(actor)
		builder.move(actor, Vector2i(2, 3))
		builder.mount_gems(actor, str(options.get("slot", Constants.SLOT_RED)), probe_gems)
		var target := builder.add_unit(
			"snapshot_target",
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(5, 3),
			{"hp": 100, "max_hp": 100}
		)
		state = builder.finish()
		before = Snapshot.capture(state, [], false)
		var action := str(options.get("action", "attack"))
		if action == "attack":
			var result := AttackPipeline.execute_aimed(
				state,
				actor,
				target.pos,
				[AttackPipeline.TAG_RANGED],
				{"debug_trace": true}
			)
			events = result.get("events", [])
			calculation_trace = result.get("trace", [])
		elif action == "trigger":
			var slots := actor.slots_accepting(str(options.get("slot", Constants.SLOT_RED)))
			if not slots.is_empty():
				GemEffects.trigger_gem(state, actor.uid, slots[0], events, target.uid, target.pos)
	var snapshot := Snapshot.capture(state, events)
	var design_root := _design_root()
	snapshot["before"] = before
	snapshot["diff"] = SnapshotDiff.between(before, snapshot)
	snapshot["calculation_trace"] = Snapshot.json_safe(calculation_trace)
	snapshot["design_context"] = {
		"root": design_root,
		"authority_order": [
			"%s/详细设计/宝石/宝石_v1.md" % design_root,
			"%s/详细设计/数值/数值设计_v1.md" % design_root,
			"%s/GDD.md" % design_root,
		],
		"warning": "设计文档可能互相冲突；修改语义前必须指出冲突，并以详细设计优先。",
	}
	var err := Snapshot.write_json(output, snapshot)
	if err != OK:
		push_error("AI_SNAPSHOT_WRITE_FAIL path=%s error=%d" % [output, err])
		quit(1)
		return
	print("AI_SNAPSHOT_OK ", ProjectSettings.globalize_path(output))
	quit(0)


func _design_root() -> String:
	var configured := OS.get_environment("DESIGN_ROOT")
	if not configured.is_empty():
		return configured
	var local_root := ProjectSettings.globalize_path("res://../learning-notes/game/design/law-thief")
	if DirAccess.dir_exists_absolute(local_root):
		return local_root
	return LEGACY_DESIGN_ROOT


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--help" or arg == "-h":
			out["help"] = true
		elif arg.begins_with("--") and i + 1 < args.size():
			out[arg.trim_prefix("--")] = args[i + 1]
			i += 1
		i += 1
	return out


func _print_help() -> void:
	print("Usage: ./tools/snapshot [--encounter ID] [--seed N] [--output PATH]")
	print("Probe: ./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion [--slot red] [--action attack|trigger]")


func _csv(raw: String) -> Array:
	var out: Array = []
	for value in raw.split(",", false):
		var clean := value.strip_edges()
		if not clean.is_empty():
			out.append(clean)
	return out
