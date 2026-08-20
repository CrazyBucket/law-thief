class_name BattleSlotPanelLayout
extends RefCounted


## Produces interaction geometry only; rendering stays with the board draw pass.
static func build(
	unit: UnitState,
	anchor: Vector2,
	action: String,
	check_fn: Callable,
	inner_radius: float,
	outer_radius: float
) -> Dictionary:
	var count := maxi(1, unit.slots.size())
	var spread := minf(PI * 1.5, maxf(PI * 0.7, float(count) * PI * 0.34))
	var center_angle := -PI * 0.5
	var gap := PI * 0.018
	var step_angle := spread / float(count)
	var items: Array = []
	for index in range(unit.slots.size()):
		var slot: SlotState = unit.slots[index]
		var visible := should_show(slot, action)
		var enabled := false
		if visible and check_fn.is_valid():
			var check: Dictionary = check_fn.call(unit.uid, index)
			enabled = bool(check.get("ok", false))
		items.append({
			"center": anchor,
			"inner_radius": inner_radius,
			"outer_radius": outer_radius,
			"start_angle": center_angle - spread * 0.5 + step_angle * float(index) + gap,
			"end_angle": center_angle - spread * 0.5 + step_angle * float(index + 1) - gap,
			"slot_index": index,
			"slot": slot,
			"unit_uid": unit.uid,
			"visible": visible,
			"enabled": enabled,
		})
	return {"center": anchor, "radius": outer_radius, "items": items}


static func should_show(slot: SlotState, action: String) -> bool:
	if slot == null:
		return false
	match action:
		Constants.ACTION_EXTRACT:
			return not slot.gem_uid.is_empty()
		Constants.ACTION_INSERT, Constants.ACTION_INSERT_HOOKED:
			return true
	return false


static func contains_point(pos: Vector2, item: Dictionary) -> bool:
	var center: Vector2 = item.get("center", Vector2.ZERO)
	var delta := pos - center
	var distance := delta.length()
	if distance < float(item.get("inner_radius", 0.0)) or distance > float(item.get("outer_radius", 0.0)):
		return false
	return angle_between(atan2(delta.y, delta.x), float(item.get("start_angle", 0.0)), float(item.get("end_angle", 0.0)))


static func angle_between(angle: float, start_angle: float, end_angle: float) -> bool:
	var normalized_angle := wrapf(angle, -PI, PI)
	var normalized_start := wrapf(start_angle, -PI, PI)
	var normalized_end := wrapf(end_angle, -PI, PI)
	if normalized_start <= normalized_end:
		return normalized_angle >= normalized_start and normalized_angle <= normalized_end
	return normalized_angle >= normalized_start or normalized_angle <= normalized_end
