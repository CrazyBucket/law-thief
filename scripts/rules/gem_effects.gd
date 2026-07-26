class_name GemEffects
extends RefCounted
const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const EntityRules = preload("res://scripts/rules/entity_rules.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _UnitSpawnService = preload("res://scripts/rules/unit_spawn_service.gd")
const _GemLightVisuals = preload("res://scripts/rules/gem_light_visuals.gd")
const _GemExplosionRules = preload("res://scripts/rules/gem_explosion_rules.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const _ColoredSlimeRules = preload("res://scripts/rules/colored_slime_rules.gd")
const FootprintRules = preload("res://scripts/rules/footprint_rules.gd")
const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")
const ImpactRules = preload("res://scripts/rules/impact_rules.gd")
static func _rng_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RngService")
static func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")
const TIMING_ACTIVE := "active"
const TIMING_TURN_START := "turn_start"
const TIMING_TURN_END := "turn_end"
const TIMING_OWNER_DAMAGED := "owner_damaged"
const TIMING_ON_DEATH := "on_death"
const TIMING_MOVED_THROUGH := "moved_through"
const TIMING_FORCED_MOVE := "forced_move"   # 被强制位移时（击退、引力等）
const TIMING_ON_CONTACT := "on_contact"     # 接触时（碰撞、相邻、攻击）

const MODE_TRIGGER := "trigger"
const ABILITY_UNIT_RED_ACTIVE := "unit_red_active"
const ABILITY_ENEMY_RED_ACTION := "enemy_red_action"
const ABILITY_BLUE_TURN_START := "blue_turn_start"
const ABILITY_BLUE_DAMAGED := "blue_damaged"
const ABILITY_BLUE_MOVE_THROUGH := "blue_move_through"
const ABILITY_BLACK_DEATH := "black_death"
const ABILITY_TILE_TURN_START := "tile_turn_start"
const ABILITY_ATTACK_BONUS := "attack_bonus"
const ABILITY_ARMOR_BONUS := "armor_bonus"
const BLACK_DEATH_PROFILE_ORDER: Array[String] = [
	"arc",
	"impact",
	"gravity",
	"ice",
	"poison",
	"fire_gem",
	"explosion",
	"split",
	"light",
	"counter",
	"echo",
	"flurry",
]
const SPLIT_ORIGIN_SLOT_PREFIX := "split_origin_slot:"
static func begin_explosion_reaction_chain() -> void:
	_GemExplosionRules.begin_reaction_chain()
static func end_explosion_reaction_chain() -> void:
	_GemExplosionRules.end_reaction_chain()
static func split_origin_slot_key(gem_uid: String) -> String:
	return "%s%s" % [SPLIT_ORIGIN_SLOT_PREFIX, gem_uid]
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


static func run_tile_hooks(state: GameState, tile: TileState, slot_type: String, timing: String, ctx: Dictionary = {}) -> void:
	for slot in tile.slots:
		if not slot.accepts_slot_type(slot_type) or slot.gem_uid.is_empty():
			continue
		_run_slot_hook(state, tile, slot, timing, ctx)


static func on_tile_gem_inserted(state: GameState, tile: TileState, slot: SlotState, gem: GemState) -> void:
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("机关柱激活！宝石 %s 产生光环" % gem_name)


static func trigger_tile_gem(state: GameState, tile: TileState, slot: SlotState, out_events: Array[Dictionary] = []) -> bool:
	if tile.tile_id == Constants.TILE_PILLAR and slot.slot_type == Constants.SLOT_BLUE:
		state.log("触发 %s 地块的 %s" % [tile.tile_id, _gem_id(state, slot)])
		return _run_slot_hook(state, tile, slot, TIMING_TURN_START, {"events": out_events})
	return false


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


static func _behavior_for(unit: UnitState) -> GDScript:
	return BehaviorRegistry.get_behavior(unit.behavior_id)


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
## 无合法转移目标时不减伤
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
		state.log("%s 分裂宝石将 %d 点伤害均分给 %d 名周围单位" % [unit.uid, redirected, candidates.size()])
		return owner_damage
	if redirect_mode != "random_ratio":
		return damage
	var rng := _rng_service()
	if rng == null:
		return damage
	var redirect_target: UnitState = candidates[int(rng.roll_int("gem_split_redirect_%s" % unit.uid, 0, candidates.size() - 1))]
	state.log("%s 分裂宝石将 %d 点伤害转移给 %s" % [unit.uid, shared_pool, redirect_target.uid])
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
	return ImpactRules.is_valid_aim(attacker, target_pos)


static func impact_preview_path(state: GameState, attacker: UnitState, aim_cell: Vector2i, max_range: int) -> Array[Vector2i]:
	return ImpactRules.preview_path(state, attacker, aim_cell, max_range)


static func impact_target_in_direction(state: GameState, attacker: UnitState, aim_cell: Vector2i, max_range: int) -> UnitState:
	return ImpactRules.target_in_direction(state, attacker, aim_cell, max_range)


static func red_attack_range_bonus(state: GameState, unit: UnitState) -> int:
	if state == null or unit == null:
		return 0
	return ImpactRules.red_range_bonus(state, unit)


static func red_attack_range(state: GameState, unit: UnitState, base_range: int = -1) -> int:
	if base_range < 0:
		base_range = CombatConfig.attack_range()
	if unit_has_red_light(state, unit):
		return Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	return base_range + red_attack_range_bonus(state, unit)


static func gravity_pull_range(state: GameState, unit: UnitState, base_range: int = -1) -> int:
	if base_range < 0:
		base_range = CombatConfig.enemy_gravity_pull_range()
	return base_range + red_attack_range_bonus(state, unit)


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
	return _GemExplosionRules.cross_cells(center)


static func explosion_blast_pattern(gem_ctx: Dictionary) -> String:
	return _GemExplosionRules.blast_pattern(_explosion_level_def(gem_ctx))


static func explosion_uses_square_blast(gem_ctx: Dictionary) -> bool:
	return _GemExplosionRules.uses_square_blast(_explosion_level_def(gem_ctx))


static func red_explosion_center_damage(attack_damage: int, gem_ctx: Dictionary) -> int:
	return _GemExplosionRules.scaled_damage(
		attack_damage,
		_GemExplosionRules.center_damage_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_RED))
	)


static func red_explosion_splash_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	return _GemExplosionRules.scaled_damage(
		base_attack,
		_GemExplosionRules.splash_base_attack_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_RED))
	)


static func blue_explosion_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	return _GemExplosionRules.scaled_damage(
		base_attack,
		_GemExplosionRules.blue_damage_ratio(_explosion_level_def(gem_ctx, Constants.SLOT_BLUE))
	)


static func black_explosion_damage(base_attack: int, gem_ctx: Dictionary) -> int:
	var damage := _GemExplosionRules.scaled_damage(
		base_attack,
		_GemExplosionRules.black_damage_multiplier(_explosion_level_def(gem_ctx, Constants.SLOT_BLACK))
	)
	return FlurryRules.scaled_repeat_damage(damage, gem_ctx)


static func _explosion_level_def(gem_ctx: Dictionary, fallback_slot: String = Constants.SLOT_RED) -> Dictionary:
	var level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
	return _effect_level_def(
		"explosion",
		_effect_level_scope(gem_ctx, fallback_slot),
		level
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
	return _GemExplosionRules.red_blast_cells(center, _explosion_level_def(gem_ctx))


static func resolve_blast_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	return _GemExplosionRules.resolve_center(fallback, aim_cell)


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


static func explode_cross_at(state: GameState, center: Vector2i, source_uid: String,
		opts: Dictionary = {}) -> Array[Dictionary]:
	return _GemExplosionRules.explode_cross_at(state, center, source_uid, opts)


static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String,
		gem_ctx: Dictionary = {}) -> Array[Dictionary]:
	return _GemExplosionRules.explode_at(state, center, damage, source_uid, gem_ctx)


static func explode_square_at(state: GameState, center: Vector2i, source_uid: String, damage: int,
		gem_ctx: Dictionary = {}, opts: Dictionary = {}) -> Array[Dictionary]:
	return _GemExplosionRules.explode_square_at(state, center, source_uid, damage, gem_ctx, opts)


static func _damage_unit_event(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	events: Array[Dictionary],
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin(state, events)
	return tx.damage_unit(unit, amount, source_uid, reason, opts)


static func _true_damage_unit_event(
	state: GameState,
	unit: UnitState,
	amount: int,
	source_uid: String,
	reason: String,
	events: Array[Dictionary],
	opts: Dictionary = {}
) -> int:
	var tx := _CombatTransaction.begin(state, events)
	return tx.true_damage_unit(unit, amount, source_uid, reason, opts)


## 强制位移钩子：携带爆炸宝石的单位被强制位移时自爆
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
	if owner is TileState:
		return _run_tile_slot_hook(state, owner as TileState, slot, gem, timing, ctx)
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
				state.log("%s 受伤触发蓝槽爆炸！" % owner.uid)
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
			return true
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
	var owns_reaction_chain := not _GemExplosionRules.has_active_reaction_chain()
	if owns_reaction_chain:
		begin_explosion_reaction_chain()
	if not _GemExplosionRules.mark_blue_triggered(owner.uid):
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
			ImpactRules.resolve_black_death(state, owner, out_events, gem_ctx)
			return true
		"impact":
			ImpactRules.resolve_black_death(state, owner, out_events, gem_ctx)
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
						StatusRules.apply_paralyzed(state, unit, freeze_duration, owner.uid)
					out_events.append(_EventBuilder.area_effect("frost_pulse", unit.pos))
			return true
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


## 蓝槽接触效果：接触到其他单位时触发
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


static func _run_tile_slot_hook(state: GameState, tile: TileState, slot: SlotState, gem: GemState, timing: String, ctx: Dictionary = {}) -> bool:
	match timing:
		TIMING_TURN_START:
			if slot.slot_type != Constants.SLOT_BLUE or tile.tile_id != Constants.TILE_PILLAR:
				return false
			return _run_tile_turn_start_effect(state, tile, gem, ctx)
	return false


static func _run_tile_turn_start_effect(state: GameState, tile: TileState, gem: GemState, ctx: Dictionary = {}) -> bool:
	var out_events: Array[Dictionary] = _events_from_ctx(ctx)
	var gem_ctx: Dictionary = ctx.get("gem_tag_context", {})
	if gem_ctx.is_empty():
		gem_ctx = GemTagResolver.build_context(state, tile, Constants.SLOT_BLUE, TIMING_TURN_START)
	match _ability_profile(gem, ABILITY_TILE_TURN_START):
		"poison":
			var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
			var poison_level_def: Dictionary = _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), poison_level)
			var pillar_radius := int(poison_level_def["pillar_radius"])
			var pillar_stacks := int(poison_level_def["pillar_poison_stacks"])
			var pillar_duration := int(poison_level_def["pillar_poison_duration"])
			out_events.append(_EventBuilder.area_effect("poison_burst", tile.pos, {"radius": pillar_radius}))
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= pillar_radius:
					StatusRules.apply_poison(state, unit, pillar_stacks, pillar_duration, tile.tile_id)
			return true
		"explosion":
			var explosion_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "explosion"))
			var explosion_level_def: Dictionary = _effect_level_def("explosion", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), explosion_level)
			var pillar_radius := int(explosion_level_def["pillar_radius"])
			var pillar_damage := int(explosion_level_def["pillar_damage"])
			out_events.append(_EventBuilder.explode(tile.pos, pillar_radius))
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= pillar_radius:
					_damage_unit_event(state, unit, pillar_damage, "", "pillar_burn", out_events)
			return true
		"gravity":
			var gravity_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "gravity"))
			var gravity_level_def: Dictionary = _effect_level_def("gravity", _effect_level_scope(gem_ctx, Constants.SLOT_BLUE), gravity_level)
			var pillar_pull_radius := int(gravity_level_def["pillar_pull_radius"])
			var pillar_pull_steps := int(gravity_level_def["pillar_pull_steps"])
			out_events.append(_EventBuilder.gem_flash(tile.pos, {"color": _data_registry().get_gem_color(gem)}))
			for unit in state.units.values():
				if not unit.alive:
					continue
				if unit.pos == tile.pos:
					continue
				if BoardUtils.chebyshev(tile.pos, unit.pos) > pillar_pull_radius:
					continue
				out_events.append_array(
					pull_unit_toward_with_events(
						state,
						unit,
						tile.pos,
						pillar_pull_steps,
						"",
						DamageContext.create(
							"", "gravity_collision", ["gravity"], gem_ctx
						)
					)
				)
			return true
	return false



static func _gem_id(state: GameState, slot: SlotState) -> String:
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return ""
	return _data_registry().get_gem_display_name(gem)


static func _effect_level_scope(gem_ctx: Dictionary, fallback_scope: String) -> String:
	return str(gem_ctx.get("effect_level_scope", fallback_scope))


static func _effect_level_def(tag: String, scope: String, level: int) -> Dictionary:
	return _data_registry().get_gem_effect_level_def(tag, scope, level)


static func red_poison_hit_config(gem_ctx: Dictionary = {}) -> Dictionary:
	var poison_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "poison"))
	return _effect_level_def("poison", _effect_level_scope(gem_ctx, Constants.SLOT_RED), poison_level)


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
## 攻击水域：对相连水域及其边缘格上的所有潮湿单位各造成一次电弧伤害
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


## 水域导电目标：站在水域格上，或导电区边缘格且带潮湿
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
	single_target_guarantee: bool = true
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

## 命中冰冻效果：潮湿单位直接冻结（麻痹+缓速），普通单位仅缓速
static func apply_ice_hit_effect(state: GameState, target: UnitState, source_uid: String, level: int = 1) -> void:
	if not target.alive:
		return
	var level_def: Dictionary = _effect_level_def("ice", Constants.SLOT_RED, maxi(1, level))
	var slowed_min_move_points := int(level_def["slowed_min_move_points"])
	if bool(level_def["freeze_if_target_slowed"]) and target.has_status(Constants.STATUS_SLOWED):
		_freeze_target(state, target, source_uid, slowed_min_move_points)
		return
	if StatusRules.is_wet(target):
		_freeze_target(state, target, source_uid, slowed_min_move_points)
		return
	StatusRules.apply_slowed(
		state,
		target,
		int(level_def["hit_slowed_stacks"]),
		source_uid,
		slowed_min_move_points
	)


static func _freeze_target(state: GameState, target: UnitState, source_uid: String, slowed_min_move_points: int = 1) -> void:
	StatusRules.apply_paralyzed(state, target, 1, source_uid)
	StatusRules.apply_slowed(state, target, 2, source_uid, slowed_min_move_points)
	target.remove_status(Constants.STATUS_WET)
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
	# 优先选空格
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

## 优先在死亡单位刚腾出的 footprint 格生成分身，不足时再向外找空地
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


## 找 owner 周围（或更远）第一个空地
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
		state.log("%s 蓝槽分裂生成临时分身 %s 于 %s" % [owner.uid, clone.uid, clone.pos])
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
		state.log("%s 分裂失败：周围没有空地" % owner.uid)
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
		state.log("%s 分裂生成分身 %s 于 %s" % [owner.uid, clone.uid, spawn_cells[i]])
	if not clones.is_empty() and owner.team == Constants.TEAM_PLAYER:
		var uids: Array = clones.map(func(c: UnitState) -> String: return c.uid)
		state.push_controllable_batch(uids)
		state.log("分裂激活：操控 %s，队列 %s" % [state.player_uid, state.controllable_queue])
