class_name BattleStateFactory
extends RefCounted


static func create_base_state(
	encounter_id: String,
	player_spawn: Vector2i,
	player_def: Dictionary,
	run_seed: int,
	next_uid: Callable
) -> GameState:
	var state := GameState.new()
	state.run_seed = run_seed
	state.encounter_id = encounter_id
	state.player_uid = str(next_uid.call("player"))
	var player := UnitState.from_def(
		state.player_uid,
		"unit_player",
		Constants.TEAM_PLAYER,
		player_spawn,
		player_def
	)
	state.units[state.player_uid] = player
	return state


## Materializes an enemy after encounter policy has already chosen its slot contents.
static func add_enemy(
	state: GameState,
	enemy_data: Dictionary,
	enemy_def: Dictionary,
	enemy_uid: String,
	next_uid: Callable,
	create_gem: Callable
) -> UnitState:
	var def_id := str(enemy_data.get("def_id", "unit_bomb_rat"))
	var materialized_def := enemy_def.duplicate(true)
	var slots: Array = materialized_def.get("slots", [])
	for index in range(slots.size()):
		if not slots[index] is Dictionary:
			continue
		var slot_entry: Dictionary = slots[index]
		if slot_entry.has("gem_id"):
			var gem_uid := str(next_uid.call("gem"))
			var gem: GemState = create_gem.call(
				gem_uid,
				slot_entry.get("gem_id", ""),
				slot_entry.get("gem_overrides", {})
			)
			state.gems[gem_uid] = gem
			slot_entry["gem_uid"] = gem_uid
			slot_entry.erase("gem_id")
			slot_entry.erase("gem_overrides")
		slots[index] = slot_entry
	materialized_def["slots"] = slots
	var enemy := UnitState.from_def(
		enemy_uid,
		def_id,
		Constants.TEAM_ENEMY,
		enemy_data.get("pos", Vector2i.ZERO),
		materialized_def
	)
	for index in range(enemy.slots.size()):
		var slot: SlotState = enemy.slots[index]
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems[slot.gem_uid]
			gem.mark_slotted(enemy.uid, index)
	state.units[enemy_uid] = enemy
	return enemy
