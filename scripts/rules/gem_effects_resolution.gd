extends "res://scripts/rules/gem_effects_shared.gd"

static func black_explosion_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	var damage: int = _gem_explosion_rules().scaled_damage(
		base_attack,
		_gem_explosion_rules().black_damage_multiplier(_explosion_level_def(gem_ctx, Constants.SLOT_BLACK))
	)
	return FlurryRules.scaled_repeat_damage(damage, gem_ctx)

static func _explosion_level_def(gem_ctx: Dictionary, fallback_slot: String = Constants.SLOT_RED) -> Dictionary:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
	return _effect_level_def(
		"explosion",
		_effect_level_scope(gem_ctx, fallback_slot),
		level
	)

static func _black_death_order_index(gem: GemState) -> int:
	var profile := _ability_profile(gem, ABILITY_BLACK_DEATH)
	var idx := BLACK_DEATH_PROFILE_ORDER.find(profile)
	if idx < 0:
		return BLACK_DEATH_PROFILE_ORDER.size()
	return idx

static func _run_unit_death_effect_with_events(
	state: GameState,
	owner: UnitState,
	gem: GemState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> bool:
	var tag := str(_data_registry().get_gem_tag(gem))
	if _should_skip_black_death_tag(state, owner, tag, gem_ctx):
		return false
	match _ability_profile(gem, ABILITY_BLACK_DEATH):
		"explosion":
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLACK, TIMING_ON_DEATH)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
			var damage := black_explosion_damage(owner.base_attack, gem_ctx)
			begin_explosion_reaction_chain()
			var evs := explode_at(state, owner.pos, damage, owner.uid, gem_ctx)
			out_events.append(_EventBuilder.explode(owner.pos, CombatConfig.explosion_radius(), {"source_uid": owner.uid}))
			out_events.append_array(evs)
			GemComboResolver.apply_after_explosion(
				state,
				BoardUtils.cells_in_radius(owner.pos, CombatConfig.explosion_radius()),
				gem_ctx,
				out_events
			)
			if bool(level_def["chain_followup"]):
				_append_black_explosion_chain(
					state,
					owner,
					evs,
					out_events,
					gem_ctx,
					FlurryRules.scaled_repeat_damage(maxi(1, owner.base_attack), gem_ctx)
				)
			end_explosion_reaction_chain()
			return true
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), poison_level)
			if bool(poison_level_def["spawn_fog"]):
				var fog_radius := int(poison_level_def["fog_radius"])
				out_events.append(_EventBuilder.area_effect("poison_burst", owner.pos, {"radius": fog_radius}))
				TileRules.begin_overlay_batch(state)
				for cell in BoardUtils.cells_in_radius(owner.pos, fog_radius):
					if not BoardUtils.in_bounds(state, cell):
						continue
					TileRules.create_poison_fog(state, cell)
				TileRules.end_overlay_batch(state)
			_transfer_debuffs_to_random_units(
				state,
				owner,
				int(poison_level_def["debuff_spread_radius"]),
				FlurryRules.scaled_repeat_int(int(poison_level_def["debuff_copies"]), gem_ctx, 1),
				gem_ctx
			)
			return true
		"gravity":
			if GemTagResolver.has_tag(gem_ctx, "impact"):
				return true
			_impact_rules().resolve_black_death(state, owner, out_events, gem_ctx)
			return true
		"impact":
			_impact_rules().resolve_black_death(state, owner, out_events, gem_ctx)
			return true
		"arc":
			# 黑槽导电：死亡落雷，按同 tag 数量扩展命中目标数量。
			if gem_ctx.is_empty():
				gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLACK, TIMING_ON_DEATH)
			var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
			var level_def: Dictionary = _effect_level_def("arc", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
			var strike_radius := int(level_def["strike_radius"])
			var candidates: Array[UnitState] = []
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= strike_radius:
					candidates.append(unit)
			var rng := _rng_service()
			if not candidates.is_empty() and rng != null:
				if bool(level_def["strike_all_targets"]):
					for strike_target in candidates:
						_apply_lightning_death_strike(state, owner, strike_target, out_events, gem_ctx)
				else:
					var strikes := int(level_def["strike_count"])
					for i in range(mini(strikes, candidates.size())):
						var pick := int(rng.roll_int("gem_arc_death_strike_%s_%d" % [owner.uid, i], 0, candidates.size() - 1))
						var strike_target: UnitState = candidates[pick]
						candidates.remove_at(pick)
						_apply_lightning_death_strike(state, owner, strike_target, out_events, gem_ctx)
			return true
		"fire_gem":
			# 黑槽燃烧：范围、数量、持续时间与落点优先级由等级表决定。
			_scatter_fire_on_death(
				state,
				owner,
				out_events,
				maxi(1, GemTagResolver.tag_level(gem_ctx, "fire")),
				gem_ctx
			)
			return true
		"ice":
			# 黑槽冰冻：3x3 范围内所有单位下回合行动顺序垫底
			var ice_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "ice"))
			var ice_level_def: Dictionary = _effect_level_def("ice", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), ice_level)
			var death_radius := int(ice_level_def["death_radius"])
			var slowed_stacks := int(ice_level_def["slowed_stacks"])
			var slowed_min_move_points := int(ice_level_def["slowed_min_move_points"])
			var freeze_duration := int(ice_level_def["freeze_duration"])
			for unit in state.units.values():
				if not unit.alive or unit.uid == owner.uid:
					continue
				if BoardUtils.chebyshev(owner.pos, unit.pos) <= death_radius:
					StatusRules.apply_sluggish(state, unit, owner.uid)
					if slowed_stacks > 0:
						StatusRules.apply_slowed(state, unit, slowed_stacks, owner.uid, slowed_min_move_points)
					if freeze_duration > 0:
						_FrozenStatusRules.apply(state, unit, freeze_duration, owner.uid)
					out_events.append(_EventBuilder.area_effect("frost_pulse", unit.pos))
			return true
		"tide":
			return TideRules.apply_black_death_from_hook(state, owner, gem_ctx)
		"split":
			var split_ctx := gem_ctx.duplicate(true)
			split_ctx["split_trigger_gem_uid"] = gem.uid
			_spawn_split_clones(state, owner, out_events, split_ctx)
			return true
		"light":
			_resolve_black_light(
				state,
				owner,
				out_events,
				maxi(1, GemTagResolver.tag_level(gem_ctx, "light")),
				gem_ctx
			)
			return true
		"counter":
			var source_uid := str(gem_ctx.get("source_uid", ""))
			var source: UnitState = state.units.get(source_uid, null) if not source_uid.is_empty() else null
			if source != null and source.alive:
				var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "counter"))
				var level_def: Dictionary = _effect_level_def("counter", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
				var actual_hp_loss := maxi(0, int(gem_ctx.get("damage", 0)))
				var damage_multiplier := float(level_def["damage_multiplier"])
				var amount := maxi(0, int(round(float(actual_hp_loss) * damage_multiplier)))
				amount = FlurryRules.scaled_repeat_damage(amount, gem_ctx) if amount > 0 else 0
				if amount > 0:
					_damage_unit_event(state, source, amount, owner.uid, "counter_black", out_events)
				if source.alive:
					var vulnerable_duration := int(level_def["vulnerable_duration"])
					if vulnerable_duration > 0:
						StatusRules.apply_vulnerable(state, source, vulnerable_duration, owner.uid)
					var disarm_stacks := int(level_def["disarm_stacks"])
					if disarm_stacks > 0:
						StatusRules.apply_disarmed(state, source, disarm_stacks, owner.uid)
			return true
		"echo":
			_apply_black_echo(state, owner, out_events, gem_ctx)
			return true
		"flurry":
			return true
	return false

static func _run_unit_death_effect(state: GameState, owner: UnitState, gem: GemState) -> bool:
	var dummy: Array[Dictionary] = []
	return _run_unit_death_effect_with_events(state, owner, gem, dummy)

static func _append_black_explosion_chain(
	state: GameState,
	owner: UnitState,
	main_events: Array[Dictionary],
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {},
	damage: int = 1
) -> void:
	var nearest: UnitState = null
	var nearest_dist := 999999
	for ev in main_events:
		if str(ev.get("type", "")) != "damage":
			continue
		var uid := str(ev.get("uid", ""))
		if uid.is_empty() or uid == owner.uid:
			continue
		var unit: UnitState = state.units.get(uid, null)
		if unit == null or unit.alive or unit.team == owner.team:
			continue
		var dist := BoardUtils.chebyshev(owner.pos, unit.pos)
		if dist < nearest_dist or (dist == nearest_dist and (nearest == null or unit.uid < nearest.uid)):
			nearest_dist = dist
			nearest = unit
	if nearest == null:
		return
	var chain_events := explode_cross_at(
		state,
		nearest.pos,
		owner.uid,
		{
			"center_damage": damage,
			"cross_damage": damage,
			"gem_tag_context": gem_ctx,
		}
	)
	out_events.append_array(chain_events)

static func _apply_lightning_death_strike(
	state: GameState,
	owner: UnitState,
	strike_target: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	var impact_events: Array[Dictionary] = []
	_true_damage_unit_event(
		state,
		strike_target,
		FlurryRules.scaled_repeat_damage(CombatConfig.lightning_death_damage(), gem_ctx),
		owner.uid,
		"lightning_death",
		impact_events,
		{"gem_tag_context": gem_ctx, "damage_tags": ["arc"]}
	)
	var rng := _rng_service()
	if strike_target.alive and rng != null and bool(rng.chance("gem_arc_death_paralyze_%s_%s" % [owner.uid, strike_target.uid], CombatConfig.arc_paralysis_chance())):
		StatusRules.apply_paralyzed(state, strike_target, 1, owner.uid)
	out_events.append(_EventBuilder.lightning(owner.pos, strike_target.pos, {
		"source_uid": owner.uid, "target_uid": strike_target.uid,
	}))
	out_events.append_array(impact_events)

static func _reflect_light_on_damage(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	out_events: Array[Dictionary]
) -> void:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "light"))
	var level_def: Dictionary = _effect_level_def("light", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), level)
	var beams := int(level_def["reflect_beams"])
	var candidates: Array[UnitState] = [source]
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid or unit.uid == source.uid:
			continue
		if unit.team != owner.team:
			candidates.append(unit)
	var damage_ratio := float(level_def["reflect_damage_ratio"])
	var damage := maxi(1, int(float(CombatRules.attack_damage(state, owner)) * damage_ratio))
	var exposed_stacks := int(level_def["reflect_exposed_stacks"])
	var reflect_power := float(level_def["reflect_power"])
	var reflect_impact_size := float(level_def["reflect_impact_size"])
	var count := mini(beams, candidates.size())
	for i in range(count):
		var target := candidates[i]
		out_events.append(build_light_beam_event(
			owner.pos,
			target.pos,
			gem_ctx,
			reflect_impact_size,
			{"power": reflect_power, "impact_size": reflect_impact_size, "source_uid": owner.uid}
			))
		var dealt := _damage_unit_event(
			state,
			target,
			damage,
			owner.uid,
			"light_reflect",
			out_events,
			{"gem_tag_context": gem_ctx}
		)
		if dealt > 0:
			StatusRules.apply_light_exposed(state, target, exposed_stacks, owner.uid)
		apply_light_colored_hit_effects(state, target, owner, gem_ctx, out_events)

static func _resolve_black_light(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	level: int,
	gem_ctx: Dictionary = {}
) -> void:
	var level_def: Dictionary = _effect_level_def("light", Constants.SLOT_BLACK, level)
	var lethal_tags := DamageContext.tags(gem_ctx.get("lethal_damage", {}))
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		var exposed: StatusInstance = unit.get_status(Constants.STATUS_LIGHT_EXPOSED)
		if exposed == null:
			continue
		var damage := FlurryRules.scaled_repeat_damage(
			maxi(1, exposed.stacks * CombatRules.attack_damage(state, owner)),
			gem_ctx
		)
		out_events.append(build_light_beam_event(
			owner.pos,
			unit.pos,
			{},
			float(level_def["beam_width"]),
			{
				"power": float(level_def["beam_power"]),
				"impact_size": float(level_def["impact_size"]),
				"source_uid": owner.uid,
				"damage_tags": lethal_tags,
			}
			))
		_damage_unit_event(
			state,
			unit,
			damage,
			owner.uid,
			"light_judgement",
			out_events,
			{"damage_tags": ["light"]}
		)
		unit.remove_status(Constants.STATUS_LIGHT_EXPOSED)
		if bool(level_def["blind_on_survive"]) and unit.alive:
			StatusRules.apply_blinded(state, unit, 1, owner.uid)

static func _apply_blue_echo(
	state: GameState,
	owner: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	ctx: Dictionary
) -> void:
	var once_key := "echo_blue_used:%s:%d" % [owner.uid, state.turn_index]
	if bool(state.battle_temp_flags.get(once_key, false)):
		return
	state.battle_temp_flags[once_key] = true
	var out_events := _events_from_ctx(ctx)
	var tags := GemEchoRules.resolve_echo_tags(state, gem_ctx, "echo_blue_%s_%d" % [owner.uid, state.turn_index])
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	var echo_level_def: Dictionary = _effect_level_def("echo", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), echo_level)
	for i in range(tags.size()):
		var tag := tags[i]
		var strength := int(echo_level_def["first_tag_strength"]) if i == 0 else 1
		match tag:
			"arc":
				if source != null and source.alive:
					for _repeat in range(strength):
						_arc_to(
							state,
							owner.pos,
							source,
							owner.uid,
							_calc_arc_damage(owner, state),
							out_events,
							gem_ctx
						)
			"fire":
				if source != null and source.alive:
					StatusRules.apply_burning(state, source, strength, owner.uid)
			"poison":
				if source != null and source.alive:
					StatusRules.apply_poison(state, source, strength, 0, owner.uid)
			"ice":
				if source != null and source.alive:
					apply_ice_hit_effect(state, source, owner.uid, GemTagResolver.tag_level(gem_ctx, "ice") + strength - 1)
			"light":
				if source != null and source.alive:
					for _repeat in range(strength):
						_reflect_light_on_damage(state, owner, source, gem_ctx, out_events)

static func _apply_black_echo(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary
) -> void:
	if int(gem_ctx.get("echo_depth", 0)) > 0:
		return
	var echo_ctx := gem_ctx.duplicate(true)
	echo_ctx["echo_depth"] = int(gem_ctx.get("echo_depth", 0)) + 1
	var tags := GemEchoRules.resolve_echo_tags(state, gem_ctx, "echo_black_%s" % owner.uid)
	var echo_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "echo"))
	var echo_level_def: Dictionary = _effect_level_def("echo", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), echo_level)
	for i in range(tags.size()):
		var tag := tags[i]
		if tag == "split" and bool(gem_ctx.get("split_spawn_deferred", false)): continue
		var gem := _find_gem_by_tag(state, owner, Constants.SLOT_BLACK, tag)
		if gem == null:
			continue
		var repeat_count := int(echo_level_def["first_tag_repeat_count"]) if i == 0 else 1
		for _repeat in range(repeat_count):
			_run_unit_death_effect_with_events(state, owner, gem, out_events, echo_ctx)

static func _find_gem_by_tag(state: GameState, owner: UnitState, slot_type: String, tag: String) -> GemState:
	for slot in owner.slots_accepting(slot_type):
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and str(_data_registry().get_gem_tag(gem)) == tag:
			return gem
	return null

static func light_color_for_context(gem_ctx: Dictionary) -> Color:
	return _GemLightVisuals.color_for_context(gem_ctx)

static func light_element_for_context(gem_ctx: Dictionary) -> String:
	return _GemLightVisuals.element_for_context(gem_ctx)

static func light_beam_width_for_level(level: int) -> float:
	var level_def: Dictionary = _effect_level_def("light", Constants.SLOT_RED, maxi(1, level))
	return float(level_def["beam_width"])

static func is_valid_light_aim(attacker: UnitState, target_pos: Vector2i) -> bool:
	return _GemLightVisuals.is_valid_aim(attacker, target_pos)

static func light_context_with_path_dye(state: GameState, cells: Array[Vector2i], gem_ctx: Dictionary) -> Dictionary:
	return _GemLightVisuals.context_with_path_dye(state, cells, gem_ctx)

static func light_dye_element_at(state: GameState, cell: Vector2i) -> String:
	return _GemLightVisuals.dye_element_at(state, cell)

static func light_context_with_dye(gem_ctx: Dictionary, dye: String) -> Dictionary:
	return _GemLightVisuals.context_with_dye(gem_ctx, dye)

static func light_dye_transitions(state: GameState, cells: Array[Vector2i]) -> Array[Dictionary]:
	return _events_from_ctx({"events": _GemLightVisuals.dye_transitions(state, cells)})

static func apply_light_colored_hit_effects(
	state: GameState,
	target: UnitState,
	source: UnitState,
	gem_ctx: Dictionary,
	out_events: Array[Dictionary]
) -> void:
	if state == null or target == null or source == null:
		return
	if target.alive:
		if GemTagResolver.has_tag(gem_ctx, "poison"):
			var poison_level_def := red_poison_hit_config(gem_ctx)
			StatusRules.apply_poison(
				state,
				target,
				int(poison_level_def["hit_poison_stacks"]),
				int(poison_level_def["hit_poison_duration"]),
				source.uid
			)
		if GemTagResolver.has_tag(gem_ctx, "fire"):
			StatusRules.apply_burning(state, target, 1, source.uid)
		if GemTagResolver.has_tag(gem_ctx, "ice"):
			apply_ice_hit_effect(state, target, source.uid, GemTagResolver.tag_level(gem_ctx, "ice"))
	if GemTagResolver.has_tag(gem_ctx, "arc"):
		apply_arc_bounce_from_anchor(state, target, source, out_events, gem_ctx)

static func build_light_beam_event(
	from_cell: Vector2i,
	to_cell: Vector2i,
	gem_ctx: Dictionary = {},
	width: float = 1.0,
	overrides: Dictionary = {}
) -> Dictionary:
	return _GemLightVisuals.build_beam_event(from_cell, to_cell, gem_ctx, width, overrides)

static func _run_unit_moved_through_effect(_state: GameState, _owner: UnitState, _gem: GemState, _ctx: Dictionary) -> bool:
	return false


## 蓝槽接触效果：接触到其他单位时触发。
static func _run_unit_contact_effect(state: GameState, owner: UnitState, gem: GemState, ctx: Dictionary) -> bool:
	var other: UnitState = ctx.get("target", null)
	if other == null or not other.alive:
		return false
	var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_ON_CONTACT)
	match _ability_profile(gem, ABILITY_BLUE_DAMAGED):
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
			StatusRules.apply_poison(
				state,
				other,
				int(poison_level_def["contact_poison_stacks"]),
				int(poison_level_def["contact_poison_duration"]),
				owner.uid
			)
			if bool(poison_level_def["copy_debuff_on_contact"]):
				_copy_one_debuff_to_nearest_unit(state, other, owner.uid)
			return true
		"fire_gem":
			var fire_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "fire"))
			var fire_level_def: Dictionary = _effect_level_def("fire", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), fire_level)
			var had_burning := other.has_status(Constants.STATUS_BURNING)
			StatusRules.apply_burning(state, other, int(fire_level_def["contact_burning_stacks"]), owner.uid)
			if bool(fire_level_def["create_fire_on_contact"]):
				TileRules.create_fire(state, other.pos)
			if bool(fire_level_def["double_burning_on_already_burning"]) and had_burning:
				var once_key := "fire_blue_double:%s:%s:%d" % [owner.uid, other.uid, state.turn_index]
				if not bool(state.battle_temp_flags.get(once_key, false)):
					state.battle_temp_flags[once_key] = true
					var burning := other.get_status(Constants.STATUS_BURNING)
					if burning != null and burning.stacks > 0:
						StatusRules.apply_burning(state, other, burning.stacks, owner.uid)
			return true
		"ice":
			var ice_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "ice"))
			var ice_level_def: Dictionary = _effect_level_def("ice", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), ice_level)
			var had_slowed := other.has_status(Constants.STATUS_SLOWED)
			StatusRules.apply_slowed(
				state,
				other,
				int(ice_level_def["contact_slowed_stacks"]),
				owner.uid,
				int(ice_level_def["slowed_min_move_points"])
			)
			if bool(ice_level_def["upgrade_slowed_to_sluggish"]) and had_slowed:
				StatusRules.apply_sluggish(state, other, owner.uid)
			return true
	return false

static func _effect_level_scope(gem_ctx: Dictionary, fallback_scope: String) -> String:
	return str(gem_ctx.get("effect_level_scope", fallback_scope))

static func _effect_level_def(tag: String, scope: String, level: int) -> Dictionary:
	return _data_registry().get_gem_effect_level_def(tag, scope, level)

static func red_poison_hit_config(gem_ctx: Dictionary = {}) -> Dictionary:
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	return _effect_level_def("poison", Constants.SLOT_RED, poison_level)

static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")

static func _random_neighbor_unit(
	state: GameState,
	center: UnitState,
	exclude_uid: String = "",
	radius: int = 1
) -> UnitState:
	var candidates: Array[UnitState] = []
	for cell in BoardUtils.cells_in_radius(center.pos, radius):
		if cell == center.pos:
			continue
		var unit := state.get_unit_at(cell)
		if unit != null and unit.alive and unit.uid != center.uid and unit.uid != exclude_uid:
			candidates.append(unit)
	if candidates.is_empty():
		return null
	var rng := _rng_service()
	if rng == null:
		return null
	return candidates[int(rng.roll_int("gem_gravity_deflect_%s" % center.uid, 0, candidates.size() - 1))]

static func _random_adjacent_cells(state: GameState, center: Vector2i, count: int, rng_key: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in BoardUtils.neighbors4(center):
		if BoardUtils.in_bounds(state, cell):
			cells.append(cell)
	if cells.is_empty() or count <= 0:
		return []
	var rng := _rng_service()
	if rng == null:
		return cells.slice(0, mini(count, cells.size()))
	rng.shuffle_in_place(rng_key, cells)
	return cells.slice(0, mini(count, cells.size()))

static func _copy_one_debuff_to_nearest_unit(state: GameState, source: UnitState, source_uid: String) -> void:
	var debuffs: Array[StatusInstance] = []
	for status in source.statuses:
		if StatusRegistry.status_type(status.status_id) == StatusRegistry.TYPE_DEBUFF:
			debuffs.append(status)
	if debuffs.is_empty():
		return
	var nearest: UnitState = null
	var nearest_dist := 999999
	for unit in state.units.values():
		if not unit.alive or unit.uid == source.uid:
			continue
		var dist := BoardUtils.chebyshev(source.pos, unit.pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = unit
	if nearest == null:
		return
	var debuff := debuffs[0]
	var copy := StatusInstance.create(debuff.status_id, debuff.stacks, debuff.duration, source_uid, debuff.payload.duplicate(true))
	copy.value = debuff.value
	_CombatTransaction.begin_from_state(state).apply_status(nearest, copy, {"emit_event": false, "reason": "blue_poison_transfer"})

static func _spread_blue_poison_from_unit(state: GameState, carrier: UnitState, poison_level_def: Dictionary = {}) -> bool:
	var best_target: UnitState = null
	var best_dist := 999999
	for unit in state.units.values():
		if not unit.alive or unit.uid == carrier.uid:
			continue
		if unit.has_status(Constants.STATUS_POISON):
			continue
		var dist := BoardUtils.chebyshev(carrier.pos, unit.pos)
		if dist < best_dist:
			best_dist = dist
			best_target = unit
	if best_target == null:
		return false
	StatusRules.apply_poison(
		state,
		best_target,
		int(poison_level_def["turn_end_poison_stacks"]),
		int(poison_level_def["turn_end_poison_duration"]),
		carrier.uid
	)
	state.log("%s 的剧毒在回合结束传给 %s" % [carrier.uid, best_target.uid])
	return true

static func _spread_blue_poison_turn_end(
	state: GameState,
	owner: UnitState,
	_snapshot: Dictionary,
	acting_unit_uid: String = ""
) -> bool:
	if not acting_unit_uid.is_empty() and acting_unit_uid != owner.uid:
		return false
	var gem_ctx := GemTagResolver.build_context(state, owner, Constants.SLOT_BLUE, TIMING_TURN_END)
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
	if not bool(poison_level_def["turn_end_spread"]):
		return false
	return _spread_blue_poison_from_unit(state, owner, poison_level_def)

static func _poison_turn_end_source_uids(snapshot: Dictionary, owner_uid: String) -> Array[String]:
	var result: Array[String] = []
	for raw in snapshot.get(owner_uid, []):
		var uid := str(raw)
		if not uid.is_empty() and not uid in result:
			result.append(uid)
	return result

static func _should_skip_black_death_tag(state: GameState, owner: UnitState, tag: String, gem_ctx: Dictionary) -> bool:
	# Echo depth represents an intentional replay of a tag already resolved for this owner.
	if int(gem_ctx.get("echo_depth", 0)) > 0 or bool(gem_ctx.get("flurry_repeat", false)):
		return false
	var death_chain_id := int(gem_ctx.get("death_chain_id", 0))
	if death_chain_id <= 0 or tag.is_empty():
		return false
	var key := "death_chain:%d:%s:%s" % [death_chain_id, owner.uid, tag]
	if bool(state.battle_temp_flags.get(key, false)):
		return true
	state.battle_temp_flags[key] = true
	return false

static func _ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem_ref, ability_slot)


## ─── 电弧（arc）辅助 ──────────────────────────────────────────────────────

static func _calc_arc_damage(source: UnitState, state: GameState = null) -> int:
	if source == null:
		return 0
	var bonus := 0
	if state != null:
		var registry := _relic_effect_registry()
		if registry != null:
			bonus = int(registry.query_modifier("arc_damage_bonus", state))
	# 电弧取释放者的原始攻击；连击和分裂仅改变主攻击的伤害，不能削弱电弧。
	return maxi(1, int(source.base_attack * CombatConfig.arc_chain_damage_ratio())) + bonus

static func _events_from_ctx(ctx: Dictionary) -> Array[Dictionary]:
	var raw: Variant = ctx.get("events", null)
	if raw is Array[Dictionary]:
		return raw
	var events: Array[Dictionary] = []
	if not raw is Array:
		return events
	for event in raw:
		if event is Dictionary:
			events.append(event as Dictionary)
	return events

static func arc_reaction_damage(source: UnitState, state: GameState) -> int: return _calc_arc_damage(source, state)

static func arc_reaction_hit(state: GameState, from_pos: Vector2i, target: UnitState, source_uid: String, damage: int, events: Array[Dictionary], gem_ctx: Dictionary = {}) -> void: _arc_to(state, from_pos, target, source_uid, damage, events, gem_ctx)
## 攻击水域：对相连水域中的全部单位及边缘格上的潮湿单位各造成一次电弧伤害，包括站在水里的释放者。
static func apply_water_conduction(
	state: GameState,
	anchor_pos: Vector2i,
	attacker: UnitState,
	events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	var cluster := BoardUtils.water_cluster(state, anchor_pos)
	if cluster.is_empty():
		return
	var zone := BoardUtils.water_conduction_zone(cluster)
	var arc_damage := _calc_arc_damage(attacker, state)
	var hit_uids: Dictionary = {}
	var conduction_events: Array[Dictionary] = []
	for unit in state.units.values():
		if not unit.alive:
			continue
		if not _unit_in_water_conduction_zone(state, unit, zone):
			continue
		if hit_uids.has(unit.uid):
			continue
		hit_uids[unit.uid] = true
		_arc_to(state, anchor_pos, unit, attacker.uid, arc_damage, conduction_events, gem_ctx)
	for event in conduction_events:
		if str(event.get("type", "")) == "arc":
			events.append(event)
	for event in conduction_events:
		if str(event.get("type", "")) != "arc":
			events.append(event)
	state.log("水域导电 %s，命中 %d 名单位" % [anchor_pos, hit_uids.size()])


## 水域导电目标：站在水域格上，或导电区边缘格且带潮湿。
static func _unit_in_water_conduction_zone(state: GameState, unit: UnitState, zone: Dictionary) -> bool:
	if not zone.has(unit.pos):
		return false
	var tile := state.get_tile(unit.pos)
	if tile != null and tile.has_tile_tag(Constants.TAG_TILE_WATER):
		return true
	return StatusRules.is_wet(unit)


## 红槽 TAG_ARC：命中锚点范围内敌方各弹一次；范围内仅有锚点时保底命中一次。
static func apply_arc_bounce_from_anchor(
	state: GameState,
	anchor: UnitState,
	attacker: UnitState,
	events: Array[Dictionary],
	gem_ctx: Dictionary = {},
	single_target_guarantee: bool = true,
	excluded_uids: Dictionary = {},
	max_hops: int = -1
) -> void:
	if anchor == null or attacker == null: return
	var arc_damage := _calc_arc_damage(attacker, state)
	var registry := _relic_effect_registry()
	var arc_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "arc"))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def("arc", Constants.SLOT_RED, arc_level)
	var bounce_hops := int(level_def["bounce_hops"])
	var tag_counts: Dictionary = gem_ctx.get("tag_counts", {})
	var arc_count := maxi(arc_level, int(tag_counts.get("arc", arc_level)))
	# Lv3 已有三跳；超过三级的每颗导电继续额外提供一跳。
	bounce_hops += maxi(0, arc_count - 3)
	if registry != null: bounce_hops += int(registry.query_modifier("arc_bounce_count_bonus", state))
	if max_hops >= 0: bounce_hops = mini(bounce_hops, max_hops)
	var arc_range := int(level_def["range"])
	var opposing_in_range := state.units.values().filter(func(unit: UnitState): return unit.alive and unit.team != attacker.team and BoardUtils.chebyshev(anchor.pos, unit.pos) <= arc_range)
	if single_target_guarantee and opposing_in_range.size() == 1 and opposing_in_range[0] == anchor:
		_arc_to(state, attacker.pos, anchor, attacker.uid, arc_damage, events, gem_ctx)
		return
	var anchors: Array[UnitState] = [anchor]
	var hop := 0
	while hop < bounce_hops:
		var next_anchors: Array[UnitState] = []
		var hop_events: Array[Dictionary] = []
		# 只在当前跳内去重，避免零距离自命中；前跳受击者可在后续跳中再次成为目标。
		var hop_hit_uids: Dictionary = {}
		for arc_origin in anchors:
			for unit in state.units.values():
				if not unit.alive: continue
				if unit.uid == arc_origin.uid: continue
				if excluded_uids.has(unit.uid): continue
				if hop_hit_uids.has(unit.uid): continue
				if unit.team == attacker.team: continue
				if BoardUtils.chebyshev(arc_origin.pos, unit.pos) > arc_range: continue
				_arc_to(state, arc_origin.pos, unit, attacker.uid, arc_damage, hop_events, gem_ctx)
				hop_hit_uids[unit.uid] = true
				next_anchors.append(unit)
		# 同一跳的电弧并发出现，随后在统一命中点结算这一跳的伤害。
		for event in hop_events:
			if str(event.get("type", "")) == "arc":
				events.append(event)
		for event in hop_events:
			if str(event.get("type", "")) != "arc":
				events.append(event)
		if next_anchors.is_empty():
			break
		anchors = next_anchors
		hop += 1


## 对单个目标施加电弧伤害；命中 6.6% 麻痹

static func _arc_to(
	state: GameState,
	from_pos: Vector2i,
	target: UnitState,
	source_uid: String,
	damage: int,
	events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	if not target.alive:
		return
	events.append(_EventBuilder.arc(from_pos, target.pos, {"source_uid": source_uid, "target_uid": target.uid}))
	_damage_unit_event(
		state,
		target,
		damage,
		source_uid,
		"arc",
		events,
		{"gem_tag_context": gem_ctx, "damage_tags": ["arc"]}
	)
	var rng := _rng_service()
	if target.alive and rng != null and bool(rng.chance("gem_arc_proc_%s" % source_uid, CombatConfig.arc_proc_chance())):
		StatusRules.apply_paralyzed(state, target, 1, source_uid)


## ─── 冰冻（ice）辅助 ──────────────────────────────────────────────────────

## 命中冰冻效果：潮湿单位直接冻结，普通单位仅缓速。
static func apply_ice_hit_effect(state: GameState, target: UnitState, source_uid: String, level: int = 1) -> void:
	if not target.alive:
		return
	var level_def: Dictionary = _effect_level_def("ice", Constants.SLOT_RED, maxi(1, level))
	var slowed_min_move_points := int(level_def["slowed_min_move_points"])
	if bool(level_def["freeze_if_target_slowed"]) and target.has_status(Constants.STATUS_SLOWED):
		_freeze_target(state, target, source_uid)
		return
	if StatusRules.is_wet(target):
		_freeze_target(state, target, source_uid)
		return
	StatusRules.apply_slowed(
		state,
		target,
		int(level_def["hit_slowed_stacks"]),
		source_uid,
		slowed_min_move_points
	)

static func _freeze_target(state: GameState, target: UnitState, source_uid: String) -> void:
	_FrozenStatusRules.apply(state, target, 1, source_uid)
	state.log("%s 被冻结！" % target.uid)


## ─── 燃烧（fire_gem）辅助 ────────────────────────────────────────────────

## 死亡散布火焰：范围、数量、持续时间和落点优先级均由当前黑槽等级定义。
static func _scatter_fire_on_death(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	level: int = 1,
	gem_ctx: Dictionary = {}
) -> void:
	var level_scope := str(gem_ctx.get("effect_level_scope", Constants.SLOT_BLACK))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def("fire", level_scope, level)
	var radius := int(level_def["death_fire_radius"])
	var count := int(level_def["death_fire_count"])
	var duration := FlurryRules.scaled_repeat_int(int(level_def["death_fire_duration"]), gem_ctx, 1)
	if radius < 0 or count <= 0 or duration <= 0:
		return
	var all_cells: Array[Vector2i] = []
	for cell in BoardUtils.cells_in_radius(owner.pos, radius):
		if BoardUtils.in_bounds(state, cell):
			all_cells.append(cell)
	# 优先选空地
	var empty_cells: Array[Vector2i] = []
	var occupied_cells: Array[Vector2i] = []
	for cell in all_cells:
		if state.get_unit_at(cell) == null:
			empty_cells.append(cell)
		else:
			occupied_cells.append(cell)
	# 打乱顺序后取前 N 个
	var rng := _rng_service()
	if rng == null:
		return
	rng.shuffle_in_place("gem_fire_death_scatter_%s" % owner.uid, empty_cells)
	rng.shuffle_in_place("gem_fire_death_scatter_occ_%s" % owner.uid, occupied_cells)
	var prefer_occupied := bool(level_def["prefer_occupied_cells"])
	var pool: Array[Vector2i] = occupied_cells if prefer_occupied else empty_cells
	pool.append_array(empty_cells if prefer_occupied else occupied_cells)
	count = mini(count, pool.size())
	TileRules.begin_overlay_batch(state)
	for i in range(count):
		TileRules.create_fire(state, pool[i], duration)
		out_events.append(_EventBuilder.area_effect("fire_burst", pool[i]))
	TileRules.end_overlay_batch(state)


## 死亡转移负面：将 owner 身上所有负面状态随机转给 radius 内存活的敌方单位

static func _transfer_debuffs_to_random_units(
	state: GameState,
	owner: UnitState,
	radius: int,
	copies_per_debuff: int = 1,
	gem_ctx: Dictionary = {}
) -> void:
	var debuffs: Array[StatusInstance] = []
	for s in owner.statuses:
		if StatusRegistry.status_type(s.status_id) == StatusRegistry.TYPE_DEBUFF:
			debuffs.append(s)
	if debuffs.is_empty():
		return
	var candidates: Array[UnitState] = []
	for unit in state.units.values():
		if not unit.alive or unit.uid == owner.uid:
			continue
		if BoardUtils.chebyshev(owner.pos, unit.pos) <= radius:
			candidates.append(unit)
	if candidates.is_empty():
		return
	var rng := _rng_service()
	if rng == null:
		return
	for debuff in debuffs:
		var remaining := candidates.duplicate()
		var copies := mini(maxi(1, copies_per_debuff), remaining.size())
		for i in range(copies):
			var pick := int(rng.roll_int("gem_death_spread_%s_%d" % [owner.uid, i], 0, remaining.size() - 1))
			var target: UnitState = remaining[pick]
			remaining.remove_at(pick)
			var copy := StatusInstance.create(
				debuff.status_id,
				FlurryRules.scaled_repeat_int(debuff.stacks, gem_ctx, 1),
				FlurryRules.scaled_repeat_int(debuff.duration, gem_ctx, 1) if debuff.duration > 0 else 0,
				owner.uid,
				debuff.payload.duplicate(true)
			)
			copy.value = FlurryRules.scaled_repeat_int(debuff.value, gem_ctx, 1) if debuff.value > 0 else 0
			_CombatTransaction.begin_from_state(state).apply_status(target, copy, {"emit_event": false, "reason": "black_debuff_spread"})
			state.log("%s 死亡将 %s 转给 %s" % [owner.uid, StatusRegistry.display_name(debuff.status_id), target.uid])


## ─── 分裂（split）黑槽：死亡生成两个分身 ────────────────────────────────────

## 优先在死亡单位刚腾出的 footprint 格生成分身，不足时再向外找空格。
static func _find_split_spawn_cells(state: GameState, owner: UnitState, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in owner.occupied_cells():
		if not BoardUtils.in_bounds(state, cell):
			continue
		if not BoardUtils.is_passable(state, cell):
			continue
		if not result.has(cell):
			result.append(cell)
		if result.size() >= count:
			return result
	for cell in _find_empty_neighbor_cells(state, owner.pos, count):
		if result.has(cell):
			continue
		result.append(cell)
		if result.size() >= count:
			break
	return result


## 从 owner 周围（或更远）寻找空格。
static func _find_empty_neighbor_cells(state: GameState, origin: Vector2i, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 按 chebyshev 距离从近到远搜索
	var max_radius := maxi(state.board_size.x, state.board_size.y)
	for radius in range(1, max_radius):
		for cell in BoardUtils.cells_in_radius(origin, radius):
			if not BoardUtils.in_bounds(state, cell):
				continue
			if not BoardUtils.is_passable(state, cell):
				continue
			if not result.has(cell):
				result.append(cell)
			if result.size() >= count:
				return result
	return result


## 槽位按原顺序轮流分组，所有分身合计继承一份原槽位集合。
static func _partition_slots_for_clones(slots: Array, clone_count: int) -> Array:
	var groups: Array = []
	for _i in range(maxi(0, clone_count)):
		groups.append([])
	if groups.is_empty():
		return groups
	for i in range(slots.size()):
		(groups[i % groups.size()] as Array).append(slots[i])
	return groups

static func _split_black_ratio_for_context(gem_ctx: Dictionary) -> float:
	var level := GemTagResolver.tag_level(gem_ctx, "split")
	if level < 1:
		return 0.0
	var level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
	return float(level_def["stat_ratio"]) * float(gem_ctx.get("effect_strength", 1.0))

static func _try_spawn_split_blue_temp_clone(
	state: GameState,
	owner: UnitState,
	out_events: Array,
	level_def: Dictionary
) -> void:
	var used_key := "split_blue_temp_used:%s:%d" % [owner.uid, state.turn_index]
	var used_count := int(state.battle_temp_flags.get(used_key, 0))
	var per_turn_limit := int(level_def["temp_clone_per_turn_limit"])
	var spawn_count := mini(int(level_def["temp_clone_count"]), per_turn_limit - used_count)
	if spawn_count <= 0:
		return
	var spawn_cells := _find_empty_neighbor_cells(state, owner.pos, spawn_count)
	if spawn_cells.is_empty():
		return
	var stat_ratio := float(level_def["temp_clone_stat_ratio"])
	var clone_hp := int(level_def["temp_clone_hp"])
	var duration := int(level_def["temp_clone_duration"])
	var child_ids := _ColoredSlimeRules.child_unit_ids(owner, mini(spawn_count, spawn_cells.size()), "split_blue")
	var spawned := 0
	for i in range(mini(spawn_count, spawn_cells.size())):
		var clone := _create_split_clone(state, owner, spawn_cells[i], [], stat_ratio, {
			"inherit_slots": false,
			"temporary": true,
			"grants_death_rewards": false,
			"unit_def_id": child_ids[i] if i < child_ids.size() else owner.unit_def_id,
		})
		if clone == null:
			continue
		clone.max_hp = clone_hp
		clone.hp = clone_hp
		clone.add_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE)
		state.battle_temp_flags["split_blue_temp_expire:%s" % clone.uid] = state.turn_index + duration
		out_events.append(_EventBuilder.split_spawn(clone, {"source_uid": owner.uid, "reason": "split_blue"}))
		state.log("%s 蓝槽分裂生成临时分身 %s @ %s" % [owner.uid, clone.uid, clone.pos])
		spawned += 1
	if spawned > 0:
		state.battle_temp_flags[used_key] = used_count + spawned

## 创建分身单位并注册到 state

static func _create_split_clone(
	state: GameState,
	owner: UnitState,
	spawn_pos: Vector2i,
	slot_group: Array,
	stat_ratio: float,
	options: Dictionary = {}
) -> UnitState:
	var reg: Node = _data_registry()
	var clone_uid: String = str(reg.call("_next_uid", "split_clone"))
	var clone := UnitState.new()
	clone.uid = clone_uid
	clone.team = owner.team
	clone.pos = spawn_pos
	clone.facing = owner.facing
	clone.alive = true
	_ColoredSlimeRules.configure_child_clone(clone, owner, str(options.get("unit_def_id", owner.unit_def_id)), reg)
	clone.split_origin_uid = (
		owner.split_origin_uid
		if owner.has_tag(Constants.TAG_UNIT_SPLIT_CLONE) and not owner.split_origin_uid.is_empty()
		else owner.uid
	)
	clone.footprint_size = Vector2i(1, 1)
	clone.add_tag(Constants.TAG_UNIT_SPLIT_CLONE)
	var ratio := stat_ratio
	if bool(options.get("allow_unit_ratio_override", false)):
		ratio = maxf(ratio, float(_behavior_for(owner).split_clone_ratio(owner)))
	var split_black_registry := _relic_effect_registry()
	if bool(options.get("allow_player_relic_override", false)) and split_black_registry != null and owner.team == Constants.TEAM_PLAYER:
		ratio = split_black_registry.query_override_modifier("split_black_stat_ratio", state, ratio)
	clone.base_attack = ceili(owner.base_attack * ratio)
	clone.armor = ceili(owner.armor * ratio)
	clone.move_points = ceili(owner.move_points * ratio)
	clone.speed = ceili(owner.speed * ratio)
	var clone_max_hp := ceili(owner.max_hp * ratio)
	clone.max_hp = clone_max_hp
	clone.hp = clone_max_hp

	var inherit_slots := bool(options.get("inherit_slots", true))
	var inherited_gem_slots: Array = options.get("inherited_gem_slots", slot_group)
	for slot_data in slot_group if inherit_slots else []:
		if slot_data == null:
			continue
		var new_slot := SlotState.create(slot_data.slot_type, "", slot_data.locked, slot_data.lock_type)
		new_slot.dual_type = slot_data.dual_type
		new_slot.unlock_until_turn = slot_data.unlock_until_turn
		new_slot.overload_slot = slot_data.is_overload_slot()
		clone.slots.append(new_slot)
		var orig_gem_uid: String = slot_data.gem_uid
		var inherits_gem: bool = slot_data in inherited_gem_slots
		# 分裂禁用锁跟随实际宝石，不复制到另一具分身的同位空槽。
		if not inherits_gem and new_slot.is_split_disabled():
			new_slot.locked = false
			new_slot.lock_type = ""
			new_slot.unlock_until_turn = -1
		if orig_gem_uid.is_empty() or not inherits_gem:
			continue
		var orig_gem: GemState = state.gems.get(orig_gem_uid, null)
		if orig_gem == null:
			continue
		var origin_slot_index := owner.slots.find(slot_data)
		if origin_slot_index >= 0 and not state.battle_temp_flags.has(split_origin_slot_key(orig_gem_uid)):
			state.battle_temp_flags[split_origin_slot_key(orig_gem_uid)] = origin_slot_index
		# 黑槽分裂转移原宝石实例，宝石身份和奖励身份都不被复制。
		if not _GemTransfer.to_unit_slot(state, orig_gem, clone, new_slot):
			continue
		if (
			orig_gem_uid == str(options.get("disabled_split_gem_uid", ""))
			and new_slot.accepts_slot_type(Constants.SLOT_BLACK)
			and str(reg.get_gem_tag(orig_gem)) == "split"
		):
			new_slot.locked = true
			new_slot.lock_type = Constants.LOCK_SPLIT_DISABLED
			new_slot.unlock_until_turn = -1

	var spawn_result := _UnitSpawnService.register_spawn(state, clone, [], {
		"origin": owner,
		"grants_death_rewards": bool(options.get("grants_death_rewards", true)),
		"temporary": bool(options.get("temporary", false)),
		"event_kind": "none",
		"refresh_intent": true,
	})
	if not bool(spawn_result.get("ok", false)):
		return null
	return clone


## 生成等级表指定数量的分身，并推入玩家可操控队列。
static func _spawn_split_clones(
	state: GameState,
	owner: UnitState,
	out_events: Array[Dictionary],
	gem_ctx: Dictionary = {}
) -> void:
	var level := GemTagResolver.tag_level(gem_ctx, "split")
	if level < 1:
		return
	var level_def: Dictionary = _effect_level_def("split", _effect_level_scope(gem_ctx, Constants.SLOT_BLACK), level)
	var clone_count := int(level_def["clone_count"])
	if clone_count <= 0:
		return
	var spawn_cells := _find_split_spawn_cells(state, owner, clone_count)
	if spawn_cells.is_empty():
		state.log("%s 分裂失败：周围没有空格" % owner.uid)
		return
	var ordered_slots: Array = []
	for slot in owner.slots:
		if slot == null or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if (
			slot.accepts_slot_type(Constants.SLOT_BLACK)
			and gem != null
			and str(_data_registry().get_gem_tag(gem)) == "split"
		):
			ordered_slots.append(slot)
	for slot in owner.slots:
		if slot != null and slot not in ordered_slots:
			ordered_slots.append(slot)
	var slot_groups := _partition_slots_for_clones(ordered_slots, clone_count)
	var count := mini(clone_count, spawn_cells.size())
	var ratio := _split_black_ratio_for_context(gem_ctx)
	var child_ids := _ColoredSlimeRules.child_unit_ids(owner, count, "split_black")
	var clones: Array = []
	for i in range(count):
		# 两个分身都保留完整槽位结构；每颗宝石实例仍只由其中一个分身继承。
		var clone := _create_split_clone(state, owner, spawn_cells[i], owner.slots, ratio, {
			"allow_unit_ratio_override": true,
			"allow_player_relic_override": true,
			"grants_death_rewards": true,
			"disabled_split_gem_uid": str(gem_ctx.get("split_trigger_gem_uid", "")),
			"inherited_gem_slots": slot_groups[i],
			"unit_def_id": child_ids[i] if i < child_ids.size() else owner.unit_def_id,
		})
		if clone == null:
			continue
		clones.append(clone)
		out_events.append(_EventBuilder.split_spawn(clone, {"source_uid": owner.uid, "reason": "split_black"}))
		state.log("%s 分裂生成分身 %s @ %s" % [owner.uid, clone.uid, spawn_cells[i]])
	if not clones.is_empty() and owner.team == Constants.TEAM_PLAYER:
		var uids: Array = clones.map(func(c: UnitState) -> String: return c.uid)
		state.push_controllable_batch(uids)
		state.log("分裂激活：操控 %s，队列 %s" % [state.player_uid, state.controllable_queue])

