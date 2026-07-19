extends SceneTree

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Pool Roll Test ===")
	_test_registry_accessors()
	_test_source_tier_filtering()
	_test_roll_uses_source_pool()
	if _failed:
		push_error("GEM_POOL_ROLL_TEST_FAIL")
		quit(1)
		return
	print("GEM_POOL_ROLL_TEST_PASS")
	quit(0)


func _test_registry_accessors() -> void:
	var reg := _registry()
	_expect(reg.get_gem_tag(Constants.GEM_EXPLOSION) == "explosion", "explosion tag should load from JSON")
	_expect(reg.get_gem_tag(Constants.GEM_FIRE) == "fire", "fire tag should hide legacy fire_gem profile")
	_expect(reg.get_gem_element(Constants.GEM_CONDUCTIVE) == "electric", "conductive element should be electric")
	_expect(reg.get_gem_pool_tier(Constants.GEM_SPLIT) == 2, "split pool tier should remain tier 2")
	_expect(reg.get_gem_max_stack_level(Constants.GEM_EXPLOSION) == 3, "explosion max stack should be 3")
	print("  [OK] registry accessors")


func _test_source_tier_filtering() -> void:
	var reg := _registry()
	var normal_chapter_1: Array[String] = reg.get_spawnable_gem_ids_for_source("normal_chest", 1)
	_expect(Constants.GEM_EXPLOSION in normal_chapter_1, "normal chapter 1 should retain explosion pool access")
	_expect(not Constants.GEM_SPLIT in normal_chapter_1, "normal chapter 1 should exclude tier 2 split")
	var elite_chapter_2: Array[String] = reg.get_spawnable_gem_ids_for_source("elite_combat", 2)
	_expect(Constants.GEM_EXPLOSION in elite_chapter_2, "elite chapter 2 should include explosion")
	_expect(Constants.GEM_SPLIT in elite_chapter_2, "elite chapter 2 should retain split pool access")
	var boss_chapter_3: Array[String] = reg.get_spawnable_gem_ids_for_source("boss_reward", 3)
	_expect(Constants.GEM_SPLIT in boss_chapter_3, "boss chapter 3 should include split")
	print("  [OK] source tier filtering")


func _test_roll_uses_source_pool() -> void:
	var reg := _registry()
	_rng().start_run(24680)
	for i in range(20):
		var gem_id: String = reg.roll_spawnable_gem_id("pool_roll_%d" % i, [], "normal_chest", 1)
		_expect(not gem_id.is_empty(), "normal chest roll should return a gem")
		_expect(reg.get_gem_pool_tier(gem_id) <= 1, "normal chest chapter 1 roll should stay tier 1")
	print("  [OK] source pool roll")


func _registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _rng() -> Node:
	return Engine.get_main_loop().root.get_node("RngService")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
