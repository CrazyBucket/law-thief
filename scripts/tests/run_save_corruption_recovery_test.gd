extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Run Save Corruption Recovery Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var save_service: Node = root.get_node("SaveService")

	adventure_service.start_new_run(20260618)
	run_service.set_run_phase("ROOM")
	run_service.set_pending_decision({
		"type": "room",
		"room_id": "chapter_1:1_0",
		"room_type": "EVENT",
	})
	run_service.save_run()

	var active_summary: Dictionary = save_service.peek_slot_summary(save_service.get_active_slot_id())
	var active_subtitle := str(active_summary.get("subtitle", ""))
	assert(active_subtitle.find("种子") < 0, "active slot summary should not expose map seed")
	assert(active_subtitle.find("位置") < 0 and active_subtitle.find("(") < 0, "active slot summary should not expose map coordinates")
	assert(active_subtitle.find("第 ") >= 0 and active_subtitle.find("持有遗物") >= 0, "active slot summary should use player-facing progress")

	var path := ProjectSettings.globalize_path(str(save_service.slot_file_path("run_save.json")))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "should open active run save for corruption injection")
	file.store_string("{ invalid json")
	file.flush()
	file.close()

	run_service.reload_for_active_slot()
	assert(not run_service.is_run_active(), "corrupted run save should be invalidated")

	var summary: Dictionary = save_service.peek_slot_summary(save_service.get_active_slot_id())
	assert(str(summary.get("status", "")) == "进行中的这一局已失效", "slot summary should expose invalid status")
	assert(not str(summary.get("run_invalid_reason", "")).is_empty(), "slot summary should expose invalid reason")
	print("RUN_SAVE_CORRUPTION_RECOVERY_TEST_PASS")
	quit()
