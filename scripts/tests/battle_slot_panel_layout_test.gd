extends SceneTree

const Layout = preload("res://scripts/ui/battle_slot_panel_layout.gd")
const Renderer = preload("res://scripts/ui/battle_unit_slot_panel_renderer.gd")


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
	var hook_insert := Layout.build(unit, Vector2(100, 100), Constants.ACTION_INSERT_HOOKED, Callable(), 18.0, 52.0)
	assert(bool(hook_insert.items[0].get("visible", false)) and bool(hook_insert.items[1].get("visible", false)), "hook insert should expose every slot like ordinary insert")
	var first: Dictionary = extract_items[0]
	var middle_angle := (float(first.start_angle) + float(first.end_angle)) * 0.5
	var hit := Vector2(100, 100) + Vector2(cos(middle_angle), sin(middle_angle)) * 35.0
	assert(Layout.contains_point(hit, first), "a point in the sector should be selectable")
	assert(not Layout.contains_point(Vector2(100, 100), first), "the panel center should not be selectable")

	var state := GameState.new()
	state.units[unit.uid] = unit
	var renderer := Renderer.new()
	renderer.configure(
		Constants.ACTION_EXTRACT,
		func(_uid: String, _index: int) -> Dictionary: return {"ok": true},
		func(_uid: String) -> bool: return true
	)
	var anchor := func(_unit: UnitState) -> Vector2: return Vector2(100, 100)
	var renderer_hit := renderer.pick(hit, state, anchor)
	assert(str(renderer_hit.get("unit_uid", "")) == unit.uid, "lazy renderer should preserve unit hit testing")
	assert(int(renderer_hit.get("slot_index", -1)) == 0, "lazy renderer should preserve slot hit testing")
	assert(renderer.set_hover(hit, state, anchor), "first renderer hover should report a visual change")
	assert(not renderer.set_hover(hit, state, anchor), "stable renderer hover should avoid redundant redraw")
	print("BATTLE_SLOT_PANEL_LAYOUT_TEST_PASS")
	quit()
