class_name ImpactAnimationPresenter
extends RefCounted

const WINDUP_DURATION := 0.16
const DASH_BASE_DURATION := 0.07
const DASH_PER_CELL_DURATION := 0.055
const RECOIL_DURATION := 0.08
const RECOVERY_DURATION := 0.14


static func play(board: Node, event: Dictionary, motions: Array = []) -> Dictionary:
	if board == null:
		return {}
	var unit_uid := str(event.get("uid", ""))
	var from_pos: Vector2i = event.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = event.get("to", from_pos)
	var board_state: GameState = board.get("state")
	var unit: UnitState = board_state.units.get(unit_uid, null) if board_state != null else null
	if unit != null and from_pos != to_pos:
		unit.facing = UnitState.facing_from_step(from_pos, to_pos)
	var logical_pos := unit.pos if unit != null else to_pos
	var logical_screen: Vector2 = board.call("grid_to_screen", logical_pos)
	var start_screen: Vector2 = board.call("grid_to_screen", from_pos)
	var end_screen: Vector2 = board.call("grid_to_screen", to_pos)
	var start_offset := start_screen - logical_screen
	var travel_screen := end_screen - start_screen
	if travel_screen.length_squared() <= 0.001:
		var target_screen: Vector2 = board.call("grid_to_screen", event.get("target_pos", from_pos))
		travel_screen = target_screen - start_screen
	var direction := travel_screen.normalized() if travel_screen.length_squared() > 0.001 else Vector2.RIGHT
	var windup_offset := start_offset - direction * IsoCoordinates.visual(9.0)
	var recoil_offset := -direction * IsoCoordinates.visual(5.0)
	var steps := maxi(int(event.get("steps", motions.size())), 1)
	var windup := float(board.call("_scaled_duration", WINDUP_DURATION))
	var dash := float(board.call("_scaled_duration", DASH_BASE_DURATION + DASH_PER_CELL_DURATION * float(steps)))
	var recoil := float(board.call("_scaled_duration", RECOIL_DURATION))
	var recovery := float(board.call("_scaled_duration", RECOVERY_DURATION))
	var anim = board.get("_anim")
	anim.move_offsets[unit_uid] = start_offset
	anim.walk_phase[unit_uid] = 0.0
	var set_offset := Callable(board, "_set_move_offset").bind(unit_uid)
	var tween: Tween = board.create_tween()
	tween.tween_method(set_offset, start_offset, windup_offset, windup).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(set_offset, windup_offset, Vector2.ZERO, dash).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	tween.tween_method(set_offset, Vector2.ZERO, recoil_offset, recoil).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(set_offset, recoil_offset, Vector2.ZERO, recovery).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(Callable(board, "_on_move_anim_done").bind(unit_uid, Vector2.ZERO, true))
	return {"duration": windup + dash + recoil + recovery, "impact_time": windup + dash}
