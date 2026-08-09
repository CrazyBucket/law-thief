extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var profile: Node = root.get_node("ProfileService")
	var save_service: Node = root.get_node("SaveService")
	var flags: Array[String] = [
		"test_profile_batch_alpha",
		"test_profile_batch_alpha",
		"test_profile_batch_beta",
	]
	var added: int = profile.unlock_flags(flags)
	assert(added == 2, "batch unlock should deduplicate flags")
	assert(profile.is_flag_unlocked("test_profile_batch_alpha"), "first batch flag should be visible immediately")
	assert(profile.is_flag_unlocked("test_profile_batch_beta"), "second batch flag should be visible immediately")
	assert(bool(profile.get("_dirty")), "batch unlock should defer persistence until the frame boundary")

	await process_frame
	assert(not bool(profile.get("_dirty")), "deferred batch save should flush at the frame boundary")
	var profile_path: String = save_service.slot_file_path("profile.json")
	var saved: Dictionary = save_service.read_json_file(profile_path)
	var saved_flags: Array = saved.get("flags", [])
	assert(saved_flags.has("test_profile_batch_alpha"), "batch save should persist the first flag")
	assert(saved_flags.has("test_profile_batch_beta"), "batch save should persist the second flag")
	assert(profile.unlock_flags(flags) == 0, "repeating the same batch should not mark the profile dirty")
	assert(not bool(profile.get("_dirty")), "duplicate flags should not schedule another save")

	print("PROFILE_SERVICE_BATCH_TEST_PASS")
	quit()
