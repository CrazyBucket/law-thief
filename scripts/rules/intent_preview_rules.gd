class_name IntentPreviewRules
extends RefCounted

const IntentDamageComponentType = preload("res://scripts/data/intent_damage_component.gd")
const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")
const LightBeamRules = preload("res://scripts/rules/light_beam_rules.gd")
const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")
const StatusConfig = preload("res://scripts/core/status_config.gd")
const PreviewEffect = preload("res://scripts/data/intent_preview_effect.gd")

const PIPELINE_ATTACK_TYPES: Array[String] = [
	"melee_attack",
	"ranged_attack",
	"explosion_attack",
	"poison_attack",
	"arc_attack",
	"fire_attack",
	"ice_attack",
	"split_attack",
	"light_beam",
	"counter_attack",
	"echo_attack",
	"impact_attack",
	"broodmother_ranged_attack",
]


static func populate_damage(state: GameState, unit: UnitState, intent: IntentState) -> void:
	if intent == null:
		return
	intent.damage_components.clear()
	if intent.type in PIPELINE_ATTACK_TYPES:
		var target: UnitState = state.units.get(intent.target_uid, null)
		if target == null or not target.alive:
			return
		var anchor := intent.path[-1] if not intent.path.is_empty() else unit.pos
		var base_damage := intent.base_damage if intent.base_damage > 0 else intent.damage
		if base_damage <= 0:
			base_damage = CombatRules.attack_damage(state, unit)
		var profile := build_red_attack_profile(state, unit, anchor, target.pos, base_damage)
		intent.set_damage_components(profile.get("components", []))
		intent.affected_cells = _vector2i_array(profile.get("affected_cells", []))
		_refresh_dynamic_preview_text(intent)
		return
	match intent.type:
		"trample":
			var skill_damage := intent.base_damage if intent.base_damage > 0 else intent.damage
			var collision_damage := maxi(0, intent.damage - skill_damage)
			var components: Array = [IntentDamageComponentType.create(
				"trample",
				skill_damage,
				1,
				[intent.target_uid],
				intent.affected_cells
			)]
			if collision_damage > 0:
				components.append(IntentDamageComponentType.create(
					"collision",
					collision_damage,
					1,
					[intent.target_uid],
					intent.affected_cells
				))
			intent.set_damage_components(components)
		"charge_explode":
			var cells := _in_bounds_cells(
				state,
				BoardUtils.cells_in_radius(intent.target_pos, CombatConfig.explosion_radius())
			)
			intent.set_damage_components([IntentDamageComponentType.create(
				"explosion",
				CombatConfig.explosion_damage(),
				1,
				_target_hits_for_cells(state, unit.uid, cells),
				cells
			)])
			intent.affected_cells = cells
		"pull":
			intent.set_damage_components([IntentDamageComponentType.create(
				"collision",
				intent.damage,
				1,
				[intent.target_uid],
				intent.affected_cells,
				IntentDamageComponentType.CERTAINTY_CONDITIONAL
			)])
		_:
			if intent.damage > 0 and not intent.target_uid.is_empty():
				intent.set_damage_components([IntentDamageComponentType.create(
					"direct",
					intent.damage,
					1,
					[intent.target_uid],
					intent.affected_cells
				)])


static func populate(state: GameState, unit: UnitState, intent: IntentState) -> void:
	populate_damage(state, unit, intent)
	populate_effects(intent)


static func populate_effects(intent: IntentState) -> void:
	if intent == null:
		return
	intent.preview_effects.clear()
	if not intent.path.is_empty():
		intent.preview_effects.append(PreviewEffect.create("movement", intent.path, {
			"source_uid": intent.source_uid,
		}))
	for component in intent.damage_components:
		intent.preview_effects.append(PreviewEffect.create("damage", component.affected_cells, {
			"source_uid": intent.source_uid,
			"target_uid": intent.target_uid,
			"certainty": component.certainty,
			"metadata": {
				"source": component.source,
				"damage_per_hit": component.damage_per_hit,
				"instance_count": component.instance_count,
			},
		}))
	match intent.type:
		"mage_refill":
			intent.preview_effects.append(PreviewEffect.create("mage_pool_candidate", intent.plan_metadata.get("mage_candidate_cells", []), {
				"source_uid": intent.source_uid,
				"certainty": PreviewEffect.CONDITIONAL,
			}))
			intent.preview_effects.append(PreviewEffect.create("mage_pool_lock", [intent.target_pos], {
				"source_uid": intent.source_uid,
				"target_uid": intent.plan_metadata.get("mage_gem_uid", ""),
			}))
			intent.preview_effects.append(PreviewEffect.create("gem_consume", [intent.target_pos], {
				"source_uid": intent.source_uid,
				"target_uid": intent.target_uid,
			}))
		"mage_impact_charge":
			intent.preview_effects.append(PreviewEffect.create("mage_charge_route", intent.plan_metadata.get("mage_charge_path", []), {
				"source_uid": intent.source_uid,
			}))
			intent.preview_effects.append(PreviewEffect.create("displacement", intent.affected_cells, {
				"source_uid": intent.source_uid,
				"target_uid": intent.target_uid,
				"certainty": PreviewEffect.CONDITIONAL,
			}))
		"mage_spell":
			var retreat_path: Array = intent.plan_metadata.get("mage_retreat_path", [])
			if not retreat_path.is_empty():
				intent.preview_effects.append(PreviewEffect.create("displacement", retreat_path, {
					"source_uid": intent.source_uid,
					"target_uid": intent.source_uid,
					"certainty": PreviewEffect.CONDITIONAL,
				}))
			var grounded_cells: Array = intent.plan_metadata.get("mage_grounded_cells", [])
			if not grounded_cells.is_empty():
				intent.preview_effects.append(PreviewEffect.create("mage_grounded", grounded_cells, {
					"source_uid": intent.source_uid,
					"metadata": {"damage": 2},
				}))
			var wet_cells: Array = intent.plan_metadata.get("mage_wet_cells", [])
			if not wet_cells.is_empty():
				intent.preview_effects.append(PreviewEffect.create("mage_wet_danger", wet_cells, {
					"source_uid": intent.source_uid,
					"metadata": {"damage": 12},
				}))
		"broodmother_split":
			intent.preview_effects.append(PreviewEffect.create("spawn", intent.affected_cells, {
				"source_uid": intent.source_uid,
				"metadata": {"unit_id": "unit_law_worm"},
			}))
		"law_worm_consume":
			intent.preview_effects.append(PreviewEffect.create("gem_consume", [intent.target_pos], {
				"source_uid": intent.source_uid,
				"target_uid": intent.target_uid,
			}))
		"law_worm_transform":
			intent.preview_effects.append(PreviewEffect.create("transform", [intent.target_pos], {
				"source_uid": intent.source_uid,
				"metadata": {"unit_id": "unit_broodmother"},
			}))
		"pull", "trample", "impact_attack", "rolling_uncontrolled":
			intent.preview_effects.append(PreviewEffect.create("displacement", intent.affected_cells, {
				"source_uid": intent.source_uid,
				"target_uid": intent.target_uid,
				"certainty": PreviewEffect.CONDITIONAL,
			}))


static func build_red_attack_profile(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	aim_cell: Vector2i,
	base_damage: int
) -> Dictionary:
	var gem_ctx := GemTagResolver.build_context(
		state,
		unit,
		Constants.SLOT_RED,
		GemEffects.TIMING_ACTIVE
	)
	if GemTagResolver.has_tag(gem_ctx, "impact"):
		var target := state.get_unit_at(aim_cell)
		if target != null and target.alive:
			base_damage += maxi(0, BoardUtils.distance_between_unit_at_and_unit(unit, anchor, target) - 1)
	if GemTagResolver.has_tag(gem_ctx, "light"):
		return _build_light_profile(state, unit, anchor, aim_cell, base_damage, gem_ctx)
	if GemTagResolver.has_tag(gem_ctx, "split"):
		return _build_split_profile(state, unit, anchor, aim_cell, base_damage, gem_ctx)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		return _build_explosion_profile(state, unit, [aim_cell], gem_ctx, false, base_damage)
	var cells: Array[Vector2i] = [aim_cell]
	return {
		"components": [IntentDamageComponentType.create(
			"direct",
			base_damage,
			1,
			_target_hits_for_cells(state, unit.uid, cells),
			cells
		)],
		"affected_cells": cells,
	}


static func predicted_raw_damage_to(profile: Dictionary, target_uid: String) -> int:
	var total := 0
	for raw_component in profile.get("components", []):
		if raw_component is IntentDamageComponent:
			total += raw_component.predicted_raw_damage_to(target_uid)
	return total


static func predicted_mitigated_damage_to(
	state: GameState,
	target: UnitState,
	profile: Dictionary,
	include_conditional: bool = false
) -> int:
	if state == null or target == null or not target.alive:
		return 0
	var remaining_shield := StatusRules.get_shield(target)
	var vulnerable_mult := StatusConfig.float_value("vulnerable", "damage_taken_mult") \
		if StatusRules.is_vulnerable(target) else 1.0
	var total := 0
	for raw_component in profile.get("components", []):
		if not raw_component is IntentDamageComponent:
			continue
		var component := raw_component as IntentDamageComponent
		if not include_conditional and component.certainty == IntentDamageComponentType.CERTAINTY_CONDITIONAL:
			continue
		for target_uid in component.target_uids:
			if target_uid != target.uid:
				continue
			var incoming := component.damage_per_hit
			var blocked := mini(remaining_shield, incoming)
			remaining_shield -= blocked
			incoming -= blocked
			if incoming > 0 and vulnerable_mult != 1.0:
				incoming = int(float(incoming) * vulnerable_mult)
			total += maxi(0, incoming)
	return total


static func predicts_lethal_damage(
	state: GameState,
	source: UnitState,
	target: UnitState,
	profile: Dictionary
) -> bool:
	if target == null or not target.alive or _has_unmodeled_damage_defense(state, source, target):
		return false
	return predicted_mitigated_damage_to(state, target, profile, false) >= target.hp


static func _build_light_profile(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	aim_cell: Vector2i,
	base_damage: int,
	gem_ctx: Dictionary
) -> Dictionary:
	var uses_split := GemTagResolver.has_tag(gem_ctx, "split")
	var paths := LightBeamRules.compute_paths(
		state,
		unit,
		anchor,
		aim_cell,
		gem_ctx,
		uses_split
	)
	var affected_cells: Array[Vector2i] = []
	var target_hits: Array[String] = []
	var endpoints: Array[Vector2i] = []
	for path in paths:
		var cells := _vector2i_array(path.get("cells", []))
		_append_unique_cells(affected_cells, cells)
		target_hits.append_array(_target_hits_for_cells(state, unit.uid, cells))
		if not cells.is_empty():
			endpoints.append(cells[-1])
	var components: Array = [IntentDamageComponentType.create(
		"light",
		GemEffects.red_light_damage(
			state,
			unit,
			GemEffects.red_split_damage(state, unit, base_damage, gem_ctx) if uses_split else base_damage,
			gem_ctx
		),
		paths.size(),
		target_hits,
		affected_cells
	)]
	if GemTagResolver.has_tag(gem_ctx, "explosion") and not endpoints.is_empty():
		var explosion_profile := _build_explosion_profile(state, unit, endpoints, gem_ctx, true, base_damage)
		components.append_array(explosion_profile.get("components", []))
		_append_unique_cells(affected_cells, explosion_profile.get("affected_cells", []))
	return {
		"components": components,
		"affected_cells": affected_cells,
	}


static func _build_split_profile(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	aim_cell: Vector2i,
	base_damage: int,
	gem_ctx: Dictionary
) -> Dictionary:
	var origin := BoardUtils.projectile_origin_cell_at(unit, anchor, aim_cell)
	var forbidden := BoardUtils.footprint_cells_at(unit.footprint_size, anchor)
	var split_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "split"))
	var hit_cells := SplitShotRules.all_hit_cells(origin, aim_cell, forbidden, split_level)
	var flurry_value := FlurryRules.red_flurry_value(state, unit) + FlurryRules.stored(unit)
	var segment_count := 1 + flurry_value
	var split_damage := GemEffects.red_split_damage(state, unit, base_damage, gem_ctx)
	var segment_damage := FlurryRules.segment_damage(split_damage, 1, flurry_value)
	var repeated_hit_cells: Array[Vector2i] = []
	for _segment_index in range(segment_count):
		repeated_hit_cells.append_array(hit_cells)
	if GemTagResolver.has_tag(gem_ctx, "explosion"):
		return _build_explosion_profile(
			state,
			unit,
			repeated_hit_cells,
			gem_ctx,
			false,
			segment_damage
		)
	return {
		"components": [IntentDamageComponentType.create(
			"split",
			segment_damage,
			repeated_hit_cells.size(),
			_target_hits_for_impact_cells(state, unit.uid, repeated_hit_cells),
			hit_cells
		)],
		"affected_cells": hit_cells,
	}


static func _build_explosion_profile(
	state: GameState,
	unit: UnitState,
	centers: Array[Vector2i],
	gem_ctx: Dictionary,
	light_endpoint: bool,
	attack_damage: int
) -> Dictionary:
	var affected_cells: Array[Vector2i] = []
	var components: Array = []
	for center in centers:
		var blast_cells: Array[Vector2i]
		if light_endpoint:
			blast_cells = GemEffects.cross_explosion_cells(center)
		else:
			blast_cells = GemEffects.red_explosion_blast_cells(center, gem_ctx)
		blast_cells = _in_bounds_cells(state, blast_cells)
		_append_unique_cells(affected_cells, blast_cells)
		var center_cells: Array[Vector2i] = [center]
		var center_hits := _target_hits_for_cells(state, unit.uid, center_cells)
		if not light_endpoint:
			components.append(IntentDamageComponentType.create(
				"direct",
				attack_damage + GemEffects.red_explosion_center_damage(attack_damage, gem_ctx),
				1,
				center_hits,
				center_cells
			))
		else:
			components.append(IntentDamageComponentType.create(
				"explosion_center",
				GemEffects.red_explosion_center_damage(attack_damage, gem_ctx),
				1,
				center_hits,
				center_cells
			))
		var splash_cells: Array[Vector2i] = []
		for cell in blast_cells:
			if cell != center:
				splash_cells.append(cell)
		components.append(IntentDamageComponentType.create(
			"explosion",
			GemEffects.red_explosion_splash_damage(unit.base_attack, gem_ctx),
			1,
			_target_hits_for_cells(state, unit.uid, splash_cells),
			splash_cells
		))
	return {
		"components": components,
		"affected_cells": affected_cells,
	}


static func _target_hits_for_cells(state: GameState, source_uid: String, cells: Array) -> Array[String]:
	var hits: Array[String] = []
	var seen: Dictionary = {}
	for cell in cells:
		if not cell is Vector2i:
			continue
		var target := state.get_unit_at(cell)
		if target == null or not target.alive or target.uid == source_uid or seen.has(target.uid):
			continue
		seen[target.uid] = true
		hits.append(target.uid)
	return hits


static func _target_hits_for_impact_cells(
	state: GameState,
	source_uid: String,
	cells: Array
) -> Array[String]:
	var hits: Array[String] = []
	for cell in cells:
		if not cell is Vector2i:
			continue
		var target := state.get_unit_at(cell)
		if target != null and target.alive and target.uid != source_uid:
			hits.append(target.uid)
	return hits


static func _append_unique_cells(target: Array[Vector2i], cells: Array) -> void:
	for cell in cells:
		if cell is Vector2i and cell not in target:
			target.append(cell)


static func _in_bounds_cells(state: GameState, cells: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		if cell is Vector2i and BoardUtils.in_bounds(state, cell) and cell not in result:
			result.append(cell)
	return result


static func _vector2i_array(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in values:
		if value is Vector2i:
			result.append(value)
	return result


static func _refresh_dynamic_preview_text(intent: IntentState) -> void:
	if intent.damage_components.is_empty():
		return
	var primary: IntentDamageComponent = intent.damage_components[0]
	var key := ""
	var params := {"damage": primary.damage_per_hit}
	if primary.source == "split":
		key = "gem.intent.split_attack"
		params["hits"] = primary.instance_count
	elif primary.source == "light":
		if primary.instance_count > 1:
			key = "gem.intent.light_volley"
			params["beams"] = primary.instance_count
		else:
			key = "gem.intent.light_beam"
	elif intent.type == "impact_attack":
		key = "gem.intent.impact_attack"
	if key.is_empty():
		return
	var i18n: Node = Engine.get_main_loop().root.get_node_or_null("I18nService")
	if i18n == null:
		return
	var translated: String = i18n.tr_key(key, params)
	if translated != key:
		intent.preview_text = translated


static func _has_unmodeled_damage_defense(
	state: GameState,
	source: UnitState,
	target: UnitState
) -> bool:
	if state == null:
		return true
	if source != null:
		var mark: StatusInstance = source.get_status(Constants.STATUS_COUNTER_MARK)
		if mark != null:
			for watcher_data in mark.payload.get("watchers", []):
				if watcher_data is Dictionary \
						and str((watcher_data as Dictionary).get("uid", "")) == target.uid:
					return true
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	if registry == null:
		return true
	for slot in target.slots:
		if not slot.accepts_slot_type(Constants.SLOT_BLUE) or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		var profile := str(registry.get_gem_ability_profile(gem, GemEffects.ABILITY_BLUE_DAMAGED))
		if profile == "gravity" or (profile == "split" and not slot.locked):
			return true
	return false
