class_name RulesIndex
extends RefCounted


static func slot_inspect_context(unit: UnitState, slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "enemy_active" if unit.team == Constants.TEAM_ENEMY else "player_skill"
		Constants.SLOT_BLUE:
			return "unit_blue"
	return ""


static func tile_inspect_context(_tile: TileState) -> String:
	return ""
