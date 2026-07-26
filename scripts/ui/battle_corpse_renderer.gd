class_name BattleCorpseRenderer
extends RefCounted


static func draw(
	canvas: CanvasItem,
	state: GameState,
	context_fn: Callable,
	draw_gems_fn: Callable
) -> void:
	if canvas == null or state == null:
		return
	var corpses: Array[UnitState] = []
	for unit: UnitState in state.units.values():
		if state.is_player_split_corpse(unit):
			corpses.append(unit)
	corpses.sort_custom(_sort_corpse)
	for unit in corpses:
		var ctx: Dictionary = context_fn.call(unit)
		var pose_tex: Texture2D = ctx.get("pose_tex", null)
		var sprite_size: Vector2 = ctx.get("sprite_size", Vector2.ZERO)
		var top_left: Vector2 = ctx.get("top_left", Vector2.ZERO)
		var center: Vector2 = ctx.get("center", Vector2.ZERO)
		if pose_tex != null:
			var corpse_rect := Rect2(
				top_left + Vector2(0.0, sprite_size.y * 0.5),
				Vector2(sprite_size.x, sprite_size.y * 0.5)
			)
			canvas.draw_texture_rect(pose_tex, corpse_rect, false, Color(0.42, 0.45, 0.5, 0.68))
		draw_gems_fn.call(unit, center + IsoCoordinates.visual_vec(Vector2(0.0, 15.0)))


static func _sort_corpse(a: UnitState, b: UnitState) -> bool:
	if a.pos.y != b.pos.y:
		return a.pos.y < b.pos.y
	if a.pos.x != b.pos.x:
		return a.pos.x < b.pos.x
	return a.uid < b.uid
