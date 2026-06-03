extends SceneTree

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Adventure Chapter Transition Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260604)
	var run: RunState = run_service.get_run()
	if run == null:
		_fail("run was not created")
		return
	adventure_service._begin_chapter_map(2, run.map_seed)
	adventure_service.current_pos = Vector2i(7, 7)
	adventure_service.pending_room_type = "END"
	adventure_service.pending_room_label = "终点"
	var old_end_room_id: String = adventure_service.current_room_id()
	var result: Dictionary = adventure_service.resolve_pending_room()
	if not bool(result.get("chapter_advanced", false)):
		_fail("chapter 2 end did not advance")
		return
	if adventure_service.get_current_chapter() != 3:
		_fail("expected chapter 3, got %d" % adventure_service.get_current_chapter())
		return
	if adventure_service.current_pos != Vector2i.ZERO:
		_fail("chapter 3 did not reset current position")
		return
	if adventure_service.pending_room_type != "START":
		_fail("chapter 3 did not reset pending room to START")
		return
	if not run_service.get_resolved_room(old_end_room_id).is_empty():
		_fail("old end room leaked into new chapter resolved rooms")
		return
	print("  [OK] chapter 2 end advances cleanly to chapter 3")
	adventure_service._begin_chapter_map(1, run.map_seed)
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
