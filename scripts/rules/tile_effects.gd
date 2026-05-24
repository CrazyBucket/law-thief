class_name TileEffects
extends RefCounted
## 地块槽位效果 — 统一走 GemEffects hook 分发


static func on_altar_activated(state: GameState, tile: TileState, gem: GemState) -> void:
	for slot in tile.slots:
		if slot.gem_uid == gem.uid:
			GemEffects.on_tile_gem_inserted(state, tile, slot, gem)
			return


static func on_pillar_activated(state: GameState, tile: TileState, gem: GemState) -> void:
	for slot in tile.slots:
		if slot.gem_uid == gem.uid:
			GemEffects.on_tile_gem_inserted(state, tile, slot, gem)
			return


static func tick_pillar_aura(state: GameState, tile: TileState) -> void:
	GemEffects.run_tile_hooks(state, tile, Constants.SLOT_BLUE, GemEffects.TIMING_TURN_START, {})


static func on_tile_trigger(state: GameState, tile: TileState, gem: GemState) -> void:
	for slot in tile.slots:
		if slot.gem_uid == gem.uid:
			GemEffects.trigger_tile_gem(state, tile, slot)
			return
