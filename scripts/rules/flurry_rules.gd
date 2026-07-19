class_name FlurryRules
extends RefCounted

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")

const TOTAL_DAMAGE_BASE_PERCENT := 70
const TOTAL_DAMAGE_PER_FLURRY_PERCENT := 10
const BLACK_REPEAT_STRENGTH := 0.4


static func red_flurry_value(state: GameState, unit: UnitState) -> int:
	if state == null or unit == null:
		return 0
	var gem_ctx := GemTagResolver.build_context(
		state, unit, Constants.SLOT_RED, "active"
	)
	return maxi(0, int((gem_ctx.get("tag_counts", {}) as Dictionary).get("flurry", 0)))


static func blue_flurry_value(state: GameState, unit: UnitState) -> int:
	if state == null or unit == null:
		return 0
	var gem_ctx := GemTagResolver.build_context(
		state, unit, Constants.SLOT_BLUE, "owner_damaged"
	)
	return maxi(0, int((gem_ctx.get("tag_counts", {}) as Dictionary).get("flurry", 0)))


static func add_stored(state: GameState, unit: UnitState, stacks: int, source_uid: String = "") -> void:
	if stacks <= 0:
		return
	StatusRules._apply(state, unit, Constants.STATUS_STORED_FLURRY, {
		"stacks": stacks,
		"source_uid": source_uid,
	})


static func stored(unit: UnitState) -> int:
	var status: StatusInstance = unit.get_status(Constants.STATUS_STORED_FLURRY)
	return maxi(0, status.stacks) if status != null else 0


static func consume_stored(unit: UnitState) -> int:
	var stacks := stored(unit)
	if stacks > 0:
		unit.remove_status(Constants.STATUS_STORED_FLURRY)
	return stacks


static func black_flurry_value(gem_ctx: Dictionary) -> int:
	return maxi(0, int((gem_ctx.get("tag_counts", {}) as Dictionary).get("flurry", 0)))


static func total_damage_multiplier(flurry_value: int) -> float:
	return float(total_damage_percent(flurry_value)) / 100.0


static func total_damage_percent(flurry_value: int) -> int:
	if flurry_value <= 0:
		return 100
	return mini(TOTAL_DAMAGE_BASE_PERCENT + TOTAL_DAMAGE_PER_FLURRY_PERCENT * flurry_value, 100)


static func segment_damage(base_damage: int, base_segments: int, flurry_value: int) -> int:
	var hit_count := maxi(1, base_segments + maxi(0, flurry_value))
	var scaled_numerator := base_damage * total_damage_percent(flurry_value)
	return maxi(1, floori(float(scaled_numerator) / float(100 * hit_count)))


static func total_damage_preview(base_damage: int, base_segments: int, flurry_value: int) -> int:
	return segment_damage(base_damage, base_segments, flurry_value) * maxi(1, base_segments + maxi(0, flurry_value))


static func scaled_repeat_int(value: int, gem_ctx: Dictionary, minimum: int = 0) -> int:
	if value <= 0:
		return 0
	var strength := float(gem_ctx.get("effect_strength", 1.0))
	return maxi(minimum, int(float(value) * strength))


static func scaled_repeat_damage(value: int, gem_ctx: Dictionary) -> int:
	return scaled_repeat_int(value, gem_ctx, 1)
