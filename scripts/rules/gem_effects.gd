class_name GemEffects
extends "res://scripts/rules/gem_effects_resolution.gd"

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const _CounterfeitRules = preload("res://scripts/rules/counterfeit_rules.gd")

static func run_unit_hooks(state: GameState, unit: UnitState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	# The old mage's blue slots are telegraphed spell material, not generic reactive gems.
	if unit != null and unit.behavior_id == "old_mage" and slot_type == Constants.SLOT_BLUE:
		return
	var gem_ctx := GemTagResolver.build_context(state, unit, slot_type, timing)
	var triggered_tags: Dictionary = {}
	for slot in unit.slots:
		if not slot.accepts_slot_type(slot_type) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if triggered_tags.has(tag):
			continue
		triggered_tags[tag] = true
		var hook_ctx := ctx.duplicate()
		hook_ctx["gem_tag_context"] = gem_ctx
		_run_slot_hook(state, unit, slot, timing, hook_ctx)

static func run_blue_explosion_after_damage(state: GameState, unit: UnitState, ctx: Dictionary = {}) -> void:
	if unit != null and unit.behavior_id == "old_mage":
		return
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED)
	for slot in unit.slots_accepting(Constants.SLOT_BLUE):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null or _ability_profile(gem, ABILITY_BLUE_DAMAGED) != "explosion":
			continue
		var hook_ctx := ctx.duplicate()
		hook_ctx["gem_tag_context"] = gem_ctx
		var triggered := _run_unit_damaged_effect(state, unit, slot, gem, hook_ctx)
		if triggered:
			var relic_registry := _relic_effect_registry()
			if relic_registry != null:
				relic_registry.fire_event("blue_gem_triggered", state, {"actor_uid": unit.uid})
		return

static func flush_stored_flurry_after_attacks(state: GameState, attack_event_ids: Array[String]) -> void:
	if state == null or attack_event_ids.is_empty():
		return
	var pending_variant: Variant = state.battle_temp_flags.get("pending_stored_flurry", {})
	if not pending_variant is Dictionary:
		return
	var pending: Dictionary = pending_variant
	for attack_event_id in attack_event_ids:
		var gains_variant: Variant = pending.get(attack_event_id, {})
		if gains_variant is Dictionary:
			for unit_uid in (gains_variant as Dictionary).keys():
				var unit: UnitState = state.units.get(str(unit_uid), null)
				if unit != null and unit.alive:
					FlurryRules.add_stored(
						state,
						unit,
						int((gains_variant as Dictionary)[unit_uid]),
						unit.uid
					)
		pending.erase(attack_event_id)
	if pending.is_empty():
		state.battle_temp_flags.erase("pending_stored_flurry")
	else:
		state.battle_temp_flags["pending_stored_flurry"] = pending

static func _queue_stored_flurry_after_attack(
	state: GameState,
	owner: UnitState,
	damage_context: Dictionary,
	stacks: int
) -> void:
	if stacks <= 0 or not DamageContext.is_active_attack(damage_context):
		return
	var attack_event_id := str(damage_context.get("attack_event_id", ""))
	if attack_event_id.is_empty():
		return
	var pending_variant: Variant = state.battle_temp_flags.get("pending_stored_flurry", {})
	var pending: Dictionary = pending_variant if pending_variant is Dictionary else {}
	var gains_variant: Variant = pending.get(attack_event_id, {})
	var gains: Dictionary = gains_variant if gains_variant is Dictionary else {}
	# 同一攻击事件只记录一次；多段伤害不会重复获得蓄连。
	if not gains.has(owner.uid):
		gains[owner.uid] = stacks
		pending[attack_event_id] = gains
		state.battle_temp_flags["pending_stored_flurry"] = pending

static func tick_turn_start(state: GameState) -> void:
	var to_remove: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE):
			continue
		var expire_turn := int(state.battle_temp_flags.get("split_blue_temp_expire:%s" % unit.uid, state.turn_index))
		if expire_turn <= state.turn_index:
			to_remove.append(unit)
	for unit in to_remove:
		state.log("%s 的蓝槽分裂临时分身消失" % unit.uid)
		state.unregister_unit(unit)
		state.battle_temp_flags.erase("split_blue_temp_expire:%s" % unit.uid)
	state.purge_dead_controllable()

static func run_blue_poison_turn_end_spreads(state: GameState, acting_unit_uid: String) -> void:
	if state == null or acting_unit_uid.is_empty():
		return
	var acting: UnitState = state.units.get(acting_unit_uid, null)
	if acting == null or not acting.alive:
		return
	var gem_ctx := GemTagResolver.build_context(state, acting, Constants.SLOT_BLUE, TIMING_TURN_END)
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
	if not bool(poison_level_def["turn_end_spread"]):
		return
	_spread_blue_poison_from_unit(state, acting, poison_level_def)

static func capture_blue_poison_turn_end_sources(state: GameState) -> Dictionary:
	var snapshot: Dictionary = {}
	if state == null:
		return snapshot
	for unit in state.units.values():
		if not unit.alive:
			continue
		var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
		if poison == null:
			continue
		var source_uid := str(poison.source_uid)
		if source_uid.is_empty():
			continue
		var source_uids: Array = snapshot.get(source_uid, [])
		if not unit.uid in source_uids:
			source_uids.append(unit.uid)
		snapshot[source_uid] = source_uids
	return snapshot

static func trigger_gem(
	state: GameState,
	owner_uid: String,
	slot: SlotState,
	out_events: Array[Dictionary] = [],
	target_uid: String = "",
	target_pos: Vector2i = Vector2i(-1, -1)
) -> bool:
	if slot.slot_type != Constants.SLOT_RED:
		return false
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	var owner: UnitState = state.units.get(owner_uid, null)
	if owner == null:
		return false
	return _run_slot_hook(
		state,
		owner,
		slot,
		TIMING_ACTIVE,
		{"events": out_events, "target_uid": target_uid, "target_pos": target_pos}
	)

static func on_unit_death(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary] = [],
	ctx: Dictionary = {}
) -> void:
	_CounterfeitRules.remove_for_unit_death(state, unit)
	_behavior_for(unit).on_unit_death(state, unit)
	if bool(ctx.get("black_death_already_triggered", false)):
		return
	_run_death_hooks_with_events(state, unit, out_events, ctx)

static func trigger_black_death_effects(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary] = [],
	ctx: Dictionary = {}
) -> void:
	_run_death_hooks_with_events(state, unit, out_events, ctx)

static func get_slot_effect_description(gem_ref: Variant, slot_type: String, context: String) -> String:
	return _data_registry().get_gem_effect_description(gem_ref, slot_type, context)

static func get_attack_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0

static func get_armor_bonus(_state: GameState, _unit: UnitState) -> int:
	return 0

static func split_red_damage_ratio(state: GameState, unit: UnitState, gem_ctx: Dictionary = {}) -> float:
	var resolved_ctx := gem_ctx
	if resolved_ctx.is_empty():
		resolved_ctx = GemTagResolver.build_context(state, unit, Constants.SLOT_RED, TIMING_ACTIVE)
	var level := maxi(1, GemTagResolver.tag_level(resolved_ctx, "split"))
	var level_def := _effect_level_def("split", _effect_level_scope(resolved_ctx, Constants.SLOT_RED), level)
	var ratio := float(level_def["damage_ratio"])
	var registry := _relic_effect_registry()
	if registry != null and unit.team == Constants.TEAM_PLAYER:
		ratio = registry.query_override_modifier("split_red_damage_ratio", state, ratio)
	return ratio

static func red_split_damage(
	state: GameState,
	unit: UnitState,
	base_damage: int,
	gem_ctx: Dictionary = {}
) -> int:
	return maxi(1, int(float(base_damage) * split_red_damage_ratio(state, unit, gem_ctx)))

static func red_light_damage(
	state: GameState,
	unit: UnitState,
	base_damage: int,
	gem_ctx: Dictionary = {}
) -> int:
	var resolved_ctx := gem_ctx
	if resolved_ctx.is_empty():
		resolved_ctx = GemTagResolver.build_context(state, unit, Constants.SLOT_RED, TIMING_ACTIVE)
	var level := maxi(1, GemTagResolver.tag_level(resolved_ctx, "light"))
	var level_def := _effect_level_def("light", _effect_level_scope(resolved_ctx, Constants.SLOT_RED), level)
	return maxi(1, int(float(base_damage) * float(level_def["damage_ratio"])))


## 分裂宝石蓝槽伤害拦截：随机转移或在本体与周围单位间均分。
## 无合法转移目标时不减伤。
static func intercept_damage_for_split(
	state: GameState,
	unit: UnitState,
	source_uid: String,
	reason: String,
	damage: int,
	damage_context: Dictionary = {}
) -> int:
	if damage <= 0:
		return damage
	var has_split_blue := false
	for slot in unit.slots_accepting(Constants.SLOT_BLUE):
		if slot.gem_uid.is_empty() or slot.locked:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "split":
			has_split_blue = true
			break
	if not has_split_blue:
		return damage
	if not _behavior_for(unit).should_trigger_split_blue(unit, reason):
		return damage
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED)
	var split_level := GemTagResolver.tag_level(gem_ctx, "split")
	if split_level < 1:
		return damage
	var split_level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), split_level)
	var redirect_mode := str(split_level_def["redirect_mode"])
	var redirect_ratio := float(split_level_def["redirect_ratio"])
	var redirect_radius := int(split_level_def["redirect_radius"])
	var split_blue_registry := _relic_effect_registry()
	if split_blue_registry != null and unit.team == Constants.TEAM_PLAYER:
		redirect_ratio = split_blue_registry.query_override_modifier("split_blue_redirect_ratio", state, redirect_ratio)
	if redirect_ratio <= 0.0 or redirect_radius <= 0:
		return damage
	var candidates: Array[UnitState] = []
	for other in state.units.values():
		if not other.alive or other.uid == unit.uid:
			continue
		if BoardUtils.is_within_surround(unit, other, redirect_radius):
			candidates.append(other)
	if candidates.is_empty():
		return damage
	candidates.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	var shared_pool := int(float(damage) * redirect_ratio)
	if shared_pool <= 0:
		return damage
	if redirect_mode == "equal_all":
		var participant_count := candidates.size() + 1
		var owner_share := ceili(float(shared_pool) / float(participant_count))
		var redirected := shared_pool - owner_share
		var owner_damage := damage - shared_pool + owner_share
		if redirected <= 0:
			return owner_damage
		var base_share := int(redirected / candidates.size())
		var remainder := redirected % candidates.size()
		for i in range(candidates.size()):
			var share := base_share + (1 if i < remainder else 0)
			if share <= 0:
				continue
			_damage_from_state_sink(state, candidates[i], share, source_uid, "split_redirect", {
				"damage_context": damage_context,
			})
		state.log("%s 分裂宝石把 %d 点伤害均分给 %d 名周围单位" % [unit.uid, redirected, candidates.size()])
		return owner_damage
	if redirect_mode != "random_ratio":
		return damage
	var rng := _rng_service()
	if rng == null:
		return damage
	var redirect_target: UnitState = candidates[int(rng.roll_int("gem_split_redirect_%s" % unit.uid, 0, candidates.size() - 1))]
	state.log("%s 分裂宝石把 %d 点伤害转移给 %s" % [unit.uid, shared_pool, redirect_target.uid])
	_damage_from_state_sink(state, redirect_target, shared_pool, source_uid, "split_redirect", {
		"damage_context": damage_context,
	})
	return damage - shared_pool

static func run_blue_split_after_damage(
	state: GameState,
	owner: UnitState,
	reason: String,
	damage: int
) -> void:
	if state == null or owner == null or not owner.alive or owner.hp <= 0 or damage <= 0:
		return
	if not _behavior_for(owner).should_trigger_split_blue(owner, reason):
		return
	var gem_ctx := GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED)
	var level := GemTagResolver.tag_level(gem_ctx, "split")
	if level < 1:
		return
	var level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
	if int(level_def["temp_clone_count"]) <= 0:
		return
	var out_events: Array = state.get_combat_event_sink() if state.has_combat_event_sink() else []
	_try_spawn_split_blue_temp_clone(state, owner, out_events, level_def)

static func _damage_from_state_sink(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin_from_state(state)
	var dealt := tx.damage_unit(unit, amount, source_uid, reason, opts)
	tx.finish("GemEffects.%s" % reason)
	return dealt

static func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	return _data_registry().get_enemy_red_intent_meta(gem_ref, damage)

static func unit_has_red_arc(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "arc")

static func unit_has_red_light(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "light")

static func unit_has_red_impact(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "impact")

static func is_valid_impact_aim(attacker: UnitState, target_pos: Vector2i) -> bool:
	return _impact_rules().is_valid_aim(attacker, target_pos)

static func impact_preview_path(state: GameState, attacker: UnitState, aim_cell: Vector2i, max_range: int) -> Array[Vector2i]:
	return _impact_rules().preview_path(state, attacker, aim_cell, max_range)

static func impact_target_in_direction(state: GameState, attacker: UnitState, aim_cell: Vector2i, max_range: int) -> UnitState:
	return _impact_rules().target_in_direction(state, attacker, aim_cell, max_range)

static func red_attack_range_bonus(state: GameState, unit: UnitState) -> int:
	if state == null or unit == null:
		return 0
	return _impact_rules().red_range_bonus(state, unit)

static func red_attack_range(state: GameState, unit: UnitState, base_range: int = -1) -> int:
	if base_range < 0:
		base_range = CombatConfig.attack_range()
	if unit_has_red_light(state, unit):
		return Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	return base_range + red_attack_range_bonus(state, unit)


static func enemy_normal_attack_base_range(state: GameState, unit: UnitState, from_pos: Vector2i) -> int:
	if state == null or unit == null:
		return 1
	var behavior := _behavior_for(unit)
	if behavior == null:
		return 1
	return maxi(1, int(behavior.normal_attack_base_range(state, unit, from_pos)))


static func on_red_action(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var slot := unit.get_slot(Constants.SLOT_RED)
	if slot == null or slot.gem_uid.is_empty():
		return [] as Array[Dictionary]
	var raw_events: Array = _behavior_for(unit).execute_red_action(state, unit, intent)
	var events: Array[Dictionary] = []
	for event in raw_events:
		if event is Dictionary:
			events.append(event as Dictionary)
	return events

static func cross_explosion_cells(center: Vector2i) -> Array[Vector2i]:
	return _gem_explosion_rules().cross_cells(center)

static func explosion_blast_pattern(gem_ctx: Dictionary) -> String:
	return _gem_explosion_rules().blast_pattern(_explosion_level_def(gem_ctx))

static func explosion_uses_square_blast(gem_ctx: Dictionary) -> bool:
	return _gem_explosion_rules().uses_square_blast(_explosion_level_def(gem_ctx))

static func red_explosion_center_damage(attack_damage: int, gem_ctx: Dictionary) -> int:
	return _gem_explosion_rules().scaled_damage(
		attack_damage,
		_gem_explosion_rules().center_damage_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_RED))
	)

static func red_explosion_splash_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	return _gem_explosion_rules().scaled_damage(
		base_attack,
		_gem_explosion_rules().splash_base_attack_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_RED))
	)

static func blue_explosion_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	return _gem_explosion_rules().scaled_damage(
		base_attack,
		_gem_explosion_rules().blue_damage_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_BLUE))
	)

static func primary_attack_damage_preview(state: GameState, unit: UnitState, fallback_damage: int) -> int:
	if state == null or unit == null:
		return fallback_damage
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_RED, TIMING_ACTIVE)
	if not GemTagResolver.has_tag(gem_ctx, "explosion"):
		return fallback_damage
	# Light has its own multi-target damage model; a single intent.damage value cannot summarize it.
	if GemTagResolver.has_tag(gem_ctx, "light"):
		return fallback_damage
	return fallback_damage + red_explosion_center_damage(fallback_damage, gem_ctx)

static func red_explosion_blast_cells(center: Vector2i, gem_ctx: Dictionary) -> Array[Vector2i]:
	return _gem_explosion_rules().red_blast_cells(center, _explosion_level_def(gem_ctx))

static func resolve_blast_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	return _gem_explosion_rules().resolve_center(fallback, aim_cell)

static func unit_has_red_explosion(state: GameState, unit: UnitState) -> bool:
	return _unit_has_red_active_profile(state, unit, "explosion")

static func unit_has_red_split(state: GameState, unit: UnitState) -> bool:
	if _unit_has_red_active_profile(state, unit, "split"):
		return true
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_ENEMY_RED_ACTION) == "split":
			return true
	return false

static func _unit_has_red_active_profile(state: GameState, unit: UnitState, profile: String) -> bool:
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == profile:
			return true
	return false

static func find_red_active_gem(state: GameState, unit: UnitState, profile: String) -> GemState:
	for slot in unit.slots_accepting(Constants.SLOT_RED):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE) == profile:
			return gem
	return null

static func explode_square_at(state: GameState, center: Vector2i, source_uid: String, damage: int,
		gem_ctx: Dictionary = {}, opts: Dictionary = {}) -> Array[Dictionary]:
	return _gem_explosion_rules().explode_square_at(state, center, source_uid, damage, gem_ctx, opts)

static func on_forced_displacement(state: GameState, unit: UnitState, events: Array[Dictionary]) -> void:
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLUE, TIMING_FORCED_MOVE)
	var triggered_tags: Dictionary = {}
	for slot in unit.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLUE) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if triggered_tags.has(tag):
			continue
		triggered_tags[tag] = true
		if _ability_profile(gem, ABILITY_BLUE_DAMAGED) == "explosion":
			state.log("%s 被强制位移触发爆炸！" % unit.uid)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			_append_blue_explosion_by_pattern(state, unit, str(level_def["blast_pattern"]), gem_ctx, events)

static func pull_around(
	state: GameState,
	center: Vector2i,
	pull_range: int,
	steps: int,
	source_uid: String = "",
	damage_context: Dictionary = {}
) -> void:
	for unit in state.units.values():
		if not unit.alive:
			continue
		if unit.pos == center:
			continue
		if BoardUtils.chebyshev(center, unit.pos) > pull_range:
			continue
		pull_unit_toward_with_events(state, unit, center, steps, source_uid, damage_context)

static func pull_unit_toward_with_events(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	steps: int,
	source_uid: String = "",
	damage_context: Dictionary = {}
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_Displacement.pull_toward(
		state, unit, anchor, steps, source_uid, events,
		-1,
		false,
		false,
		damage_context
	)
	return events

static func _run_slot_hook(state: GameState, owner: Variant, slot: SlotState, timing: String, ctx: Dictionary) -> bool:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return false
	if owner is UnitState:
		return _run_unit_slot_hook(state, owner as UnitState, slot, gem, timing, ctx)
	return false

static func _run_unit_slot_hook(state: GameState, owner: UnitState, slot: SlotState, gem: GemState, timing: String, ctx: Dictionary) -> bool:
	match timing:
		TIMING_ACTIVE:
			if not slot.accepts_slot_type(Constants.SLOT_RED):
				return false
			return _run_unit_active_effect(state, owner, slot, gem, ctx)
		TIMING_TURN_START:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_turn_start_effect(state, owner, slot, gem)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_TURN_END:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_turn_end_effect(state, owner, slot, gem, ctx)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_OWNER_DAMAGED:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			var triggered := _run_unit_damaged_effect(state, owner, slot, gem, ctx)
			if triggered:
				var _rr := _relic_effect_registry()
				if _rr != null:
					_rr.fire_event("blue_gem_triggered", state, {"actor_uid": owner.uid})
			return triggered
		TIMING_ON_DEATH:
			if not slot.accepts_slot_type(Constants.SLOT_BLACK):
				return false
			return _run_unit_death_effect(state, owner, gem)
		TIMING_MOVED_THROUGH:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			return _run_unit_moved_through_effect(state, owner, gem, ctx)
		TIMING_ON_CONTACT:
			if not slot.accepts_slot_type(Constants.SLOT_BLUE):
				return false
			return _run_unit_contact_effect(state, owner, gem, ctx)
	return false

static func _run_unit_active_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var out_events: Array[Dictionary] = _events_from_ctx(ctx)
	match _ability_profile(gem, ABILITY_UNIT_RED_ACTIVE):
		"explosion":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var blast_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var target_unit: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if target_unit != null and target_unit.alive:
				blast_center = resolve_blast_center(target_unit.pos, ctx.get("target_pos", null))
			var center_damage := red_explosion_center_damage(owner.base_attack, gem_ctx)
			var splash_damage := red_explosion_splash_damage(owner.base_attack, gem_ctx)
			if explosion_uses_square_blast(gem_ctx):
				out_events.append_array(explode_square_at(
					state,
					blast_center,
					owner.uid,
					splash_damage,
					gem_ctx,
					{"center_damage": center_damage}
				))
			else:
				out_events.append_array(
					explode_cross_at(state, blast_center, owner.uid, {
						"center_damage": center_damage,
						"cross_damage": splash_damage,
						"gem_tag_context": gem_ctx,
					})
				)
			return true
		"poison":
			var poison_level := 1
			var poison_duration := CombatConfig.poison_fog_duration()
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			poison_level = maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def(
				"poison",
				_effect_level_scope(gem_ctx, Constants.SLOT_RED),
				poison_level
			)
			poison_duration += int(poison_level_def["duration_bonus"])
			var poison_center := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var poison_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if poison_target != null and poison_target.alive:
				poison_center = resolve_blast_center(poison_target.pos, ctx.get("target_pos", null))
			var poison_pattern := str(poison_level_def["fog_pattern"])
			var burst := {
				"type": "poison_burst",
				"pos": poison_center,
				"radius": 0,
				"duration": poison_duration,
			}
			if poison_pattern == "cross":
				burst["pattern"] = "cross"
			out_events.append(burst)
			if BoardUtils.in_bounds(state, poison_center):
				TileRules.begin_overlay_batch(state)
				TileRules.create_poison_fog(state, poison_center, poison_duration)
				if poison_pattern == "cross":
					for neighbor in BoardUtils.neighbors4(poison_center):
						if BoardUtils.in_bounds(state, neighbor):
							TileRules.create_poison_fog(state, neighbor, poison_duration)
				TileRules.end_overlay_batch(state)
			if poison_target != null and poison_target.alive:
				StatusRules.apply_poison(
					state,
					poison_target,
					int(poison_level_def["hit_poison_stacks"]),
					int(poison_level_def["hit_poison_duration"]),
					owner.uid
				)
			return true
		"gravity":
			var gravity_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gravity_ctx.is_empty():
				gravity_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var gravity_level := maxi(1, GemTagResolver.tag_level(gravity_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def(
				"gravity",
				_effect_level_scope(gravity_ctx, Constants.SLOT_RED),
				gravity_level
			)
			var pull_steps := int(gravity_level_def["pull_steps"])
			out_events.append(_EventBuilder.gem_flash(owner.pos, {"color": _data_registry().get_gem_color(gem)}))
			var pull_target: UnitState = state.units.get(str(ctx.get("target_uid", "")), null)
			if pull_target != null and pull_target.alive and pull_target.uid != owner.uid:
				out_events.append_array(
					pull_unit_toward_with_events(
						state,
						pull_target,
						owner.pos,
						pull_steps,
						owner.uid,
						DamageContext.create(
							owner.uid, "gravity_collision", ["gravity"], gravity_ctx
						)
					)
				)
			return true
		"impact":
			return false
		"arc":
			var arc_target_uid: String = ctx.get("target_uid", "")
			var arc_anchor: Vector2i = owner.pos
			var arc_target: UnitState = state.units.get(arc_target_uid, null)
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			if arc_target != null:
				arc_anchor = arc_target.pos
			var trigger_tile := state.get_tile(arc_anchor)
			if trigger_tile != null and trigger_tile.has_tile_tag(Constants.TAG_TILE_WATER):
				apply_water_conduction(state, arc_anchor, owner, out_events, gem_ctx)
			elif arc_target != null and arc_target.alive:
				_arc_to(state, owner.pos, arc_target, owner.uid, _calc_arc_damage(owner, state), out_events, gem_ctx)
				apply_arc_bounce_from_anchor(state, arc_target, owner, out_events, gem_ctx, false)
			return true
		"fire_gem":
			var fire_pos := resolve_blast_center(owner.pos, ctx.get("target_pos", null))
			var fire_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			var fire_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if fire_ctx.is_empty():
				fire_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			var fire_level := maxi(1, GemTagResolver.tag_level(fire_ctx, "fire"))
			var fire_level_def: Dictionary = _effect_level_def(
				"fire",
				_effect_level_scope(fire_ctx, Constants.SLOT_RED),
				fire_level
			)
			var spread_count := 0
			if fire_target != null and fire_target.alive:
				fire_pos = resolve_blast_center(fire_target.pos, ctx.get("target_pos", null))
				spread_count += int(fire_level_def["spread_count"])
				if fire_target.has_status(Constants.STATUS_BURNING):
					spread_count += int(fire_level_def["burning_bonus_spread_count"])
			out_events.append(_EventBuilder.area_effect("fire_burst", fire_pos))
			TileRules.begin_overlay_batch(state)
			TileRules.create_fire(state, fire_pos)
			for cell in _random_adjacent_cells(state, fire_pos, spread_count, "gem_fire_red_spread_%s_%s" % [owner.uid, str(fire_pos)]):
				TileRules.create_fire(state, cell)
				out_events.append(_EventBuilder.area_effect("fire_burst", cell, {"spread": true}))
			TileRules.end_overlay_batch(state)
			return true
		"ice":
			var ice_target: UnitState = state.units.get(ctx.get("target_uid", ""), null)
			if ice_target == null or not ice_target.alive:
				return true
			var ice_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if ice_ctx.is_empty():
				ice_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_RED, TIMING_ACTIVE, _slot)
			out_events.append(_EventBuilder.area_effect("frost_pulse", ice_target.pos))
			apply_ice_hit_effect(state, ice_target, owner.uid, GemTagResolver.tag_level(ice_ctx, "ice"))
			return true
		"split":
			return true
	return false

static func _run_unit_turn_start_effect(state: GameState, owner: UnitState, slot: SlotState, gem: GemState) -> bool:
	var _unused := [state, owner, slot, gem]
	return false

static func _run_unit_turn_end_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_TURN_END, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			if not bool(level_def["turn_end_spread"]):
				return false
			var snapshot_variant: Variant = ctx.get("poison_turn_end_sources", {})
			var snapshot: Dictionary = snapshot_variant if snapshot_variant is Dictionary else {}
			return _spread_blue_poison_turn_end(state, owner, snapshot, str(ctx.get("acting_unit_uid", "")))
	return false

static func _run_unit_damaged_effect(state: GameState, owner: UnitState, _slot: SlotState, gem: GemState, ctx: Dictionary) -> bool:
	var reason: String = ctx.get("reason", "")
	var source_uid: String = ctx.get("source_uid", "")
	var damage: int = ctx.get("damage", 0)
	var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var poison_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if poison_ctx.is_empty():
				poison_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var poison_level := maxi(1, GemTagResolver.tag_level(poison_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(poison_ctx, Constants.SLOT_BLUE), poison_level)
			if bool(poison_level_def["copy_debuff_on_damaged"]) and source != null and source.alive:
				if BoardUtils.chebyshev(owner.pos, source.pos) <= 1:
					_copy_one_debuff_to_nearest_unit(state, source, owner.uid)
			return false
		"explosion":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			var detonate_on_any_damage := bool(level_def["detonate_on_any_damage"])
			var detonate_on_burning := bool(level_def["detonate_on_burning"])
			var detonate_on_explosion := bool(level_def["detonate_on_explosion"])
			var blast_pattern := str(level_def["blast_pattern"])
			var damage_context: Dictionary = ctx.get("damage_context", {})
			var damage_tags := DamageContext.tags(damage_context)
			var is_burning_damage := reason == "burning" or reason == "tile_fire" or "fire" in damage_tags
			var is_explosion_damage := "explosion" in damage_tags
			if detonate_on_any_damage \
					or (detonate_on_burning and is_burning_damage) \
					or (detonate_on_explosion and is_explosion_damage):
				state.log("%s 受伤触发蓝槽爆炸。" % owner.uid)
				var out_events: Array[Dictionary] = _events_from_ctx(ctx)
				_append_blue_explosion_by_pattern(state, owner, blast_pattern, gem_ctx, out_events)
				return true
			return false
		"gravity":
			var gravity_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gravity_ctx.is_empty():
				gravity_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var gravity_level := maxi(1, GemTagResolver.tag_level(gravity_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def("gravity", _effect_level_scope(gravity_ctx, Constants.SLOT_BLUE), gravity_level)
			if source != null and source.alive and BoardUtils.manhattan(owner.pos, source.pos) > 1 and damage > 0:
				var deflect_target: UnitState = _random_neighbor_unit(
					state,
					owner,
					source.uid,
					int(gravity_level_def["redirect_radius"])
				)
				if deflect_target != null:
					_damage_from_state_sink(state, deflect_target, damage, owner.uid, "gravity_deflect")
				if bool(gravity_level_def["slow_on_damaged"]):
					StatusRules.apply_slowed(state, source, 1, owner.uid)
				if bool(gravity_level_def["root_on_damaged"]):
					StatusRules.apply_rooted(state, source, 1, owner.uid)
			return true
		"impact":
			return false
		"arc":
			var rng := _rng_service()
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
			var level_def: Dictionary = _effect_level_def("arc", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
			var chance := float(level_def["rebound_chance"])
			var damage_context: Dictionary = ctx.get("damage_context", {})
			if source != null and source.uid != owner.uid and source.alive and rng != null \
					and DamageContext.is_active_attack(damage_context) \
					and bool(rng.chance("gem_arc_rebound_%s" % owner.uid, chance)):
				_arc_to(
					state,
					owner.pos,
					source,
					owner.uid,
					_calc_arc_damage(owner, state),
					_events_from_ctx(ctx),
					gem_ctx
				)
				apply_arc_bounce_from_anchor(state, source, owner, _events_from_ctx(ctx), gem_ctx, false, {source.uid: true}, 1)
			return true
		"tide":
			return TideRules.apply_blue_damaged_from_hook(state, owner, source, ctx, _slot)
		"split":
			return true
		"light":
			if source != null and source.alive and reason == "ranged_attack":
				var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
				_reflect_light_on_damage(state, owner, source, gem_ctx, _events_from_ctx(ctx))
			return true
		"counter":
			var damage_context: Dictionary = ctx.get("damage_context", {})
			if source != null and source.alive and damage > 0 and DamageContext.is_active_attack(damage_context):
				var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
				if gem_ctx.is_empty():
					gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
				var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "counter"))
				var level_def: Dictionary = _effect_level_def("counter", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
				if not StatusRules.can_attack(owner):
					return true
				if bool(level_def["use_ranged_counter"]):
					var result := AttackPipeline.execute_aimed(
						state,
						owner,
						source.pos,
						[AttackPipeline.TAG_RANGED],
						{"damage_reason": "counter_blue"},
						Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
					)
					_events_from_ctx(ctx).append_array(result.get("events", []))
					if bool(level_def["grant_extra_move_on_kill"]) and not source.alive and owner.uid == state.player_uid:
						StatusRules.grant_extra_move(state, owner, 1, owner.uid)
				else:
					_damage_unit_event(
						state,
						source,
						CombatRules.attack_damage(state, owner),
						owner.uid,
						"counter_blue",
						_events_from_ctx(ctx)
					)
			return true
		"echo":
			var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_OWNER_DAMAGED, _slot)
			_apply_blue_echo(state, owner, source, gem_ctx, ctx)
			return true
		"flurry":
			var damage_context: Dictionary = ctx.get("damage_context", {})
			_queue_stored_flurry_after_attack(
				state,
				owner,
				damage_context,
				FlurryRules.blue_flurry_value(state, owner)
			)
			return true
	return false

static func _append_blue_explosion_by_pattern(
	state: GameState,
	owner: UnitState,
	blast_pattern: String,
	gem_ctx: Dictionary,
	events: Array[Dictionary]
) -> void:
	var owns_reaction_chain: bool = not _gem_explosion_rules().has_active_reaction_chain()
	if owns_reaction_chain:
		begin_explosion_reaction_chain()
	if not _gem_explosion_rules().mark_blue_triggered(owner.uid):
		if owns_reaction_chain:
			end_explosion_reaction_chain()
		return
	var damage := blue_explosion_damage(owner.base_attack, gem_ctx)
	if blast_pattern == "square":
		events.append_array(explode_square_at(state, owner.pos, owner.uid, damage, gem_ctx))
	else:
		events.append_array(explode_cross_at(
			state,
			owner.pos,
			owner.uid,
			{"cross_damage": damage, "gem_tag_context": gem_ctx}
		))
	if owns_reaction_chain:
		end_explosion_reaction_chain()


## 带事件输出的死亡钩子入口

static func _run_death_hooks_with_events(
	state: GameState,
	unit: UnitState,
	out_events: Array[Dictionary],
	ctx: Dictionary = {}
) -> void:
	var death_gems: Array[GemState] = []
	var seen_tags: Dictionary = {}
	var gem_ctx := GemTagResolver.build_context(state, unit, Constants.SLOT_BLACK, TIMING_ON_DEATH, null, ctx)
	if ctx.has("death_chain_id"):
		gem_ctx["death_chain_id"] = int(ctx.get("death_chain_id", 0))
	if ctx.has("source_uid"):
		gem_ctx["source_uid"] = str(ctx.get("source_uid", ""))
	if ctx.has("damage"):
		gem_ctx["damage"] = int(ctx.get("damage", 0))
	if ctx.has("reason"):
		gem_ctx["reason"] = str(ctx.get("reason", ""))
	if ctx.has("lethal_damage"):
		var raw_lethal: Variant = ctx.get("lethal_damage", {})
		if raw_lethal is Dictionary:
			var lethal_damage: Dictionary = raw_lethal
			var normalized := DamageContext.normalize(
				str(lethal_damage.get("source_uid", ctx.get("source_uid", ""))),
				str(lethal_damage.get("reason", ctx.get("reason", ""))),
				lethal_damage
			)
			normalized["actual_hp_loss"] = int(lethal_damage.get("actual_hp_loss", ctx.get("damage", 0)))
			gem_ctx["lethal_damage"] = normalized
			gem_ctx["lethal_damage_tags"] = DamageContext.tags(normalized)
	for slot in unit.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLACK) or slot.gem_uid.is_empty():
			continue
		if slot.locked and slot.lock_type == Constants.LOCK_SPLIT_DISABLED:
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var tag := str(_data_registry().get_gem_tag(gem))
		if seen_tags.has(tag):
			continue
		seen_tags[tag] = true
		death_gems.append(gem)
	death_gems.sort_custom(func(a: GemState, b: GemState) -> bool:
		return _black_death_order_index(a) < _black_death_order_index(b)
	)
	var deferred_split_gem: GemState = death_gems.pop_back() if not death_gems.is_empty() and _ability_profile(death_gems.back(), ABILITY_BLACK_DEATH) == "split" else null
	if deferred_split_gem != null: gem_ctx["split_spawn_deferred"] = true
	for gem in death_gems:
		_run_unit_death_effect_with_events(state, unit, gem, out_events, gem_ctx)
	var repeat_count := FlurryRules.black_flurry_value(gem_ctx)
	for repeat_index in range(repeat_count):
		var repeat_ctx := gem_ctx.duplicate(true)
		repeat_ctx["effect_strength"] = FlurryRules.BLACK_REPEAT_STRENGTH
		repeat_ctx["flurry_repeat"] = true
		repeat_ctx["flurry_repeat_index"] = repeat_index
		for gem in death_gems:
			var tag := str(_data_registry().get_gem_tag(gem))
			# 黑槽分裂每次死亡固定只结算一次；连击不能把同一具尸体继续裂成更多单位。
			if tag == "flurry" or tag == "split":
				continue
			_run_unit_death_effect_with_events(state, unit, gem, out_events, repeat_ctx)
	if deferred_split_gem != null:
		_run_unit_death_effect_with_events(state, unit, deferred_split_gem, out_events, gem_ctx)
