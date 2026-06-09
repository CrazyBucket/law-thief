extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run Service Acquire Gem Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260608)
	var first: Dictionary = run_service.acquire_gem("gem_explosion")
	assert(first.get("ok", false), "first gem acquire should succeed")
	var second: Dictionary = run_service.acquire_gem("gem_poison")
	assert(not second.get("ok", true), "second gem acquire should fail while carrying one gem")
	assert(str(second.get("error", "")) == "carried_gem_occupied", "should report carried gem conflict")
	assert(str(run_service.get_run().carried_gem.get("gem_id", "")) == "gem_explosion", "carried gem should remain unchanged")
	run_service.end_run()
	print("RUN_SERVICE_ACQUIRE_GEM_TEST_PASS")
	quit()
