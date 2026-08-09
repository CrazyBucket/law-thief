class_name PresentationStateApplier
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const StatusRules = preload("res://scripts/rules/status_rules.gd")

var _display_state: GameState = null
var _runtime_state: GameState = null


func set_states(display_state: GameState, runtime_state: GameState = null) -> void:
	_display_state = display_state
	_runtime_state = runtime_state


func prime(event: Dictionary) -> void:
	if _display_state == null:
		return
	if str(event.get("type", "")) not in ["move_step", "knockback"]:
		return
	var uid := str(event.get("uid", ""))
	var unit: UnitState = _display_state.units.get(uid, null)
	if unit == null:
		return
	var from_pos: Vector2i = event.get("from", unit.pos)
	var to_pos: Vector2i = event.get("to", unit.pos)
	if unit.pos != to_pos:
		_display_state.move_unit(unit, to_pos)
	unit.facing = UnitState.facing_from_step(from_pos, to_pos)


func apply(event: Dictionary) -> void:
	if _display_state == null:
		return
	match str(event.get("type", "")):
		"damage":
			_apply_damage(event)
		"poison_burst":
			_apply_poison_burst(event)
		"fire_burst":
			TileRules.create_fire(_display_state, event.get("pos", Vector2i.ZERO))
			_display_state.bump_revision()
		"split_spawn":
			_copy_runtime_unit(str(event.get("uid", "")))
		"spawn":
			_copy_runtime_unit(str(event.get("uid", "")))
		"transform":
			_copy_runtime_unit(str(event.get("uid", "")), true)
		"die":
			var dead_unit: UnitState = _display_state.units.get(str(event.get("uid", "")), null)
			if dead_unit != null:
				_display_state.kill_unit(dead_unit)
		"entity_destroyed":
			var entity: EntityState = _display_state.entities.get(str(event.get("uid", "")), null)
			if entity != null:
				entity.alive = false
				_display_state.bump_revision()
		"explode", "gem_flash", "projectile_deflect", "lightning", "frost_pulse", "arc", "light_beam", "impact_charge", "move_step", "displacement_impact", "knockback":
			pass


func _apply_damage(event: Dictionary) -> void:
	var pos: Vector2i = event.get("pos", Vector2i.ZERO)
	var victim_uid := str(event.get("uid", event.get("victim_uid", "")))
	var victim: UnitState = _display_state.units.get(victim_uid, null) if not victim_uid.is_empty() else null
	if victim == null:
		victim = _display_state.get_unit_at(pos)
	if victim == null:
		return
	if event.has("remaining_shield"):
		var remaining_shield := maxi(0, int(event.get("remaining_shield", 0)))
		var shield: StatusInstance = victim.get_status(Constants.STATUS_ARMOR)
		if remaining_shield <= 0:
			victim.remove_status(Constants.STATUS_ARMOR)
		elif shield != null:
			shield.value = remaining_shield
		else:
			StatusRules.apply_shield(_display_state, victim, remaining_shield, 0)
	victim.hp = maxi(0, victim.hp - int(event.get("damage", 0)))
	_display_state.bump_revision()
	# Lethal victims remain visible through the hit beat; the die event removes occupancy.


func _apply_poison_burst(event: Dictionary) -> void:
	var center: Vector2i = event.get("pos", Vector2i.ZERO)
	var pattern := str(event.get("pattern", ""))
	var radius := int(event.get("radius", 0))
	var cells: Array[Vector2i] = []
	if pattern == "cross":
		cells.append(center)
		for neighbor in BoardUtils.neighbors4(center):
			if BoardUtils.in_bounds(_display_state, neighbor):
				cells.append(neighbor)
	elif radius <= 0:
		cells.append(center)
	else:
		for cell in BoardUtils.cells_in_radius(center, radius):
			if BoardUtils.in_bounds(_display_state, cell):
				cells.append(cell)
	var duration := CombatConfig.poison_fog_duration()
	if int(event.get("duration", 0)) > 0:
		duration = int(event.get("duration", duration))
	TileRules.begin_overlay_batch(_display_state)
	for cell in cells:
		TileRules.create_poison_fog(_display_state, cell, duration)
	TileRules.end_overlay_batch(_display_state)
	_display_state.bump_revision()


func _copy_runtime_unit(uid: String, replace_existing: bool = false) -> void:
	if uid.is_empty() or _display_state == null or _runtime_state == null:
		return
	var runtime_unit: UnitState = _runtime_state.units.get(uid, null)
	if runtime_unit == null or not runtime_unit.alive:
		return
	var existing: UnitState = _display_state.units.get(uid, null)
	if existing != null:
		_display_state.unregister_unit(existing)
	for slot in runtime_unit.slots:
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = _runtime_state.gems.get(slot.gem_uid, null)
		if gem != null:
			_display_state.gems[gem.uid] = gem.clone()
	_display_state.register_unit(runtime_unit.clone())
