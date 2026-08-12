class_name RelicBattleState
extends RefCounted

var turn_flags: Dictionary = {}
var move_capacity: int = 0
var active_unit_capacity: int = 0
var move_spent: int = 0
var movement_action_origin: Vector2i = Vector2i(-1, -1)
var movement_action_spent: int = 0
var movement_action_active: bool = false
var temp_move_by_source: Dictionary = {}
var flywheel_layers: int = 0
var scavenger_hook_triggered: bool = false
var hooked_gem_uid: String = ""
var hooked_drop_metadata: Dictionary = {}
var hook_expires_after_turn: int = -1
var beast_ticket_triggered: bool = false
## victim uid -> enemy source uid; at most one entry exists because the relic is once per battle.
var retaliation_targets: Dictionary = {}
## Runtime records for locked counterfeit gems. The gem itself owns slot occupancy;
## this record only preserves the deferred extraction context needed after it breaks.
var counterfeits: Dictionary = {}


func clone():
	var snapshot: Variant = get_script().new()
	snapshot.turn_flags = turn_flags.duplicate(true)
	snapshot.move_capacity = move_capacity
	snapshot.active_unit_capacity = active_unit_capacity
	snapshot.move_spent = move_spent
	snapshot.movement_action_origin = movement_action_origin
	snapshot.movement_action_spent = movement_action_spent
	snapshot.movement_action_active = movement_action_active
	snapshot.temp_move_by_source = temp_move_by_source.duplicate(true)
	snapshot.flywheel_layers = flywheel_layers
	snapshot.scavenger_hook_triggered = scavenger_hook_triggered
	snapshot.hooked_gem_uid = hooked_gem_uid
	snapshot.hooked_drop_metadata = hooked_drop_metadata.duplicate(true)
	snapshot.hook_expires_after_turn = hook_expires_after_turn
	snapshot.beast_ticket_triggered = beast_ticket_triggered
	snapshot.retaliation_targets = retaliation_targets.duplicate(true)
	snapshot.counterfeits = counterfeits.duplicate(true)
	return snapshot


func begin_player_turn(capacity: int) -> void:
	turn_flags.clear()
	move_capacity = maxi(0, capacity)
	active_unit_capacity = move_capacity
	move_spent = 0
	movement_action_origin = Vector2i(-1, -1)
	movement_action_spent = 0
	movement_action_active = false
	temp_move_by_source.clear()


func add_controlled_unit_capacity(capacity: int) -> void:
	active_unit_capacity = maxi(0, capacity)
	move_capacity += active_unit_capacity


func reconcile_active_capacity(current_capacity: int) -> void:
	current_capacity = maxi(0, current_capacity)
	if current_capacity >= active_unit_capacity:
		return
	move_capacity = maxi(move_spent, move_capacity - (active_unit_capacity - current_capacity))
	active_unit_capacity = current_capacity


func record_move_segment(origin: Vector2i, spent: int) -> void:
	if spent <= 0:
		return
	if not movement_action_active:
		movement_action_origin = origin
		movement_action_spent = 0
		movement_action_active = true
	movement_action_spent += spent
	move_spent += spent


func finish_movement_action() -> Dictionary:
	if not movement_action_active or movement_action_spent <= 0:
		return {}
	var result := {
		"from": movement_action_origin,
		"spent_move": movement_action_spent,
	}
	movement_action_origin = Vector2i(-1, -1)
	movement_action_spent = 0
	movement_action_active = false
	return result


func add_temp_move(source_id: String, amount: int) -> void:
	if source_id.is_empty() or amount <= 0:
		return
	temp_move_by_source[source_id] = int(temp_move_by_source.get(source_id, 0)) + amount
	move_capacity += amount
	active_unit_capacity += amount


func take_all_temp_move() -> int:
	var total := 0
	for amount in temp_move_by_source.values():
		total += maxi(0, int(amount))
	temp_move_by_source.clear()
	move_capacity = maxi(move_spent, move_capacity - total)
	active_unit_capacity = maxi(0, active_unit_capacity - total)
	return total


func remaining_move() -> int:
	return maxi(0, move_capacity - move_spent)


func clear_hooked_gem() -> void:
	hooked_gem_uid = ""
	hooked_drop_metadata.clear()
	hook_expires_after_turn = -1
