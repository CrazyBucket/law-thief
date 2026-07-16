extends SceneTree

const Presenter = preload("res://scripts/ui/adventure_map_copy_presenter.gd")


func _initialize() -> void:
	var active_rules: Array = [
		{"rule_id": "map_rule_shop_discount_20", "name": "商路折扣"},
		{"rule_id": "event_debug_cache", "name": "event_debug_cache"},
		{"rule_id": "map_rule_missing_name", "name": ""},
		{"rule_id": "map_rule_shop_discount_20", "name": "商路折扣"},
	]
	var context := {
		"cell": Vector2i(3, 2),
		"room_id": "chapter_1:3_2",
		"event_id": "event_debug_cache",
	}
	var player_copy := Presenter.present(active_rules, context, false)
	assert(player_copy.rule_names == ["商路折扣"], "player copy should keep named rules and remove duplicates")
	assert((player_copy.debug_lines as PackedStringArray).is_empty(), "release copy must not expose debug metadata")
	var player_text := " / ".join(player_copy.rule_names)
	for internal_value in ["map_rule_shop_discount_20", "event_debug_cache", "chapter_1:3_2", "(3, 2)"]:
		assert(not player_text.contains(internal_value), "player copy leaked internal metadata: %s" % internal_value)

	var debug_copy := Presenter.present(active_rules, context, true)
	var debug_text := "\n".join(debug_copy.debug_lines)
	assert(debug_text.contains("cell=(3, 2)"), "debug copy should retain map coordinates")
	assert(debug_text.contains("room_id=chapter_1:3_2"), "debug copy should retain room ids")
	assert(debug_text.contains("event_id=event_debug_cache"), "debug copy should retain event ids")
	assert(debug_text.contains("rule_ids=map_rule_shop_discount_20,event_debug_cache,map_rule_missing_name"), "debug copy should retain deduplicated rule ids")
	assert(active_rules[1].name == "event_debug_cache", "copy presentation must not mutate service data")
	print("ADVENTURE_MAP_COPY_PRESENTER_TEST_PASS")
	quit(0)
