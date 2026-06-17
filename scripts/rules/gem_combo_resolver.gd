class_name GemComboResolver
extends RefCounted

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")


static func apply_after_explosion(
	state: GameState,
	cells: Array[Vector2i],
	gem_ctx: Dictionary,
	out_events: Array[Dictionary]
) -> void:
	if state == null or gem_ctx.is_empty():
		return
	var has_fire := GemTagResolver.has_combo(gem_ctx, "explosion_fire")
	var has_poison := GemTagResolver.has_combo(gem_ctx, "explosion_poison")
	if not has_fire and not has_poison:
		return
	TileRules.begin_overlay_batch(state)
	if has_fire:
		for cell in cells:
			if not BoardUtils.in_bounds(state, cell):
				continue
			TileRules.create_fire(state, cell)
			out_events.append({"type": "fire_burst", "pos": cell, "combo": "explosion_fire"})
	if has_poison:
		for cell in cells:
			if not BoardUtils.in_bounds(state, cell):
				continue
			TileRules.create_poison_fog(state, cell)
			out_events.append({"type": "poison_burst", "pos": cell, "radius": 0, "combo": "explosion_poison"})
	TileRules.end_overlay_batch(state)


static func apply_after_attack_hit(
	state: GameState,
	hit_cell: Vector2i,
	gem_ctx: Dictionary,
	out_events: Array[Dictionary]
) -> void:
	if state == null or gem_ctx.is_empty():
		return
	if not GemTagResolver.has_combo(gem_ctx, "fire_poison"):
		return
	if not BoardUtils.in_bounds(state, hit_cell):
		return
	TileRules.create_toxic_smoke(state, hit_cell, 1)
	out_events.append({"type": "toxic_smoke", "pos": hit_cell, "combo": "fire_poison"})
