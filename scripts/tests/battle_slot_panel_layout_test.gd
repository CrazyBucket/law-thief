extends SceneTree

const Layout = preload("res://scripts/ui/battle_slot_panel_layout.gd")


func _initialize() -> void:
	var unit := UnitState.new()
	unit.uid = "slot_layout_test"
	var filled_slot := SlotState.create(Constants.SLOT_RED)
	filled_slot.gem_uid = "gem_1"
	var empty_slot := SlotState.create(Constants.SLOT_BLUE)
	unit.slots = [filled_slot, empty_slot]
	var extract := Layout.build(unit, Vector2(100, 100), Constants.ACTION_EXTRACT, Callable(), 18.0, 52.0)
	var extract_items: Array = extract.get("items", [])
	assert(bool(extract_items[0].get("visible", false)), "extract should expose filled slots")
	assert(not bool(extract_items[1].get("visible", true)), "extract should hide empty slots")
	var insert := Layout.build(unit, Vector2(100, 100), Constants.ACTION_INSERT, Callable(), 18.0, 52.0)
	assert(bool(insert.items[0].get("visible", false)) and bool(insert.items[1].get("visible", false)), "insert should expose every slot")
	var first: Dictionary = extract_items[0]
	var middle_angle := (float(first.start_angle) + float(first.end_angle)) * 0.5
	var hit := Vector2(100, 100) + Vector2(cos(middle_angle), sin(middle_angle)) * 35.0
	assert(Layout.contains_point(hit, first), "a point in the sector should be selectable")
	assert(not Layout.contains_point(Vector2(100, 100), first), "the panel center should not be selectable")
	print("BATTLE_SLOT_PANEL_LAYOUT_TEST_PASS")
	quit()
