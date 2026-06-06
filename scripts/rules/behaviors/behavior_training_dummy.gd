extends EnemyBehavior


static func compute_intent(_state: GameState, unit: UnitState, _cell_blockers: Dictionary = {}) -> IntentState:
	var intent := IntentState.wait(unit.uid)
	intent.preview_text = "木桩待机"
	return intent
