extends RefCounted
const EntityRules = preload("res://scripts/rules/entity_rules.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")
const GemComboResolver = preload("res://scripts/rules/gem_combo_resolver.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _UnitSpawnService = preload("res://scripts/rules/unit_spawn_service.gd")
const _GemLightVisuals = preload("res://scripts/rules/gem_light_visuals.gd")
const _ColoredSlimeRules = preload("res://scripts/rules/colored_slime_rules.gd")
const _FrozenStatusRules = preload("res://scripts/rules/frozen_status_rules.gd")
const FootprintRules = preload("res://scripts/rules/footprint_rules.gd")
const FlurryRules = preload("res://scripts/rules/flurry_rules.gd")
const TideRules = preload("res://scripts/rules/tide_rules.gd")

static func _rng_service() -> Node: return Engine.get_main_loop().root.get_node_or_null("RngService")

static func _relic_effect_registry() -> Node: return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")
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
const ABILITY_ATTACK_BONUS := "attack_bonus"
const ABILITY_ARMOR_BONUS := "armor_bonus"
const BLACK_DEATH_PROFILE_ORDER: Array[String] = [
	"arc",
	"impact",
	"gravity",
	"ice", "tide",
	"poison",
	"fire_gem",
	"explosion",
	"light",
	"counter",
	"echo",
	"flurry",
	"split",
]
const SPLIT_ORIGIN_SLOT_PREFIX := "split_origin_slot:"

static func _gem_explosion_rules() -> GDScript:
	return load("res://scripts/rules/gem_explosion_rules.gd") as GDScript

static func _impact_rules() -> GDScript:
	return load("res://scripts/rules/impact_rules.gd") as GDScript

static func begin_explosion_reaction_chain() -> void: _gem_explosion_rules().begin_reaction_chain()

static func end_explosion_reaction_chain() -> void: _gem_explosion_rules().end_reaction_chain()

static func split_origin_slot_key(gem_uid: String) -> String: return "%s%s" % [SPLIT_ORIGIN_SLOT_PREFIX, gem_uid]

static func _behavior_for(unit: UnitState) -> GDScript:
	var behavior_registry := load("res://scripts/services/behavior_registry.gd") as GDScript
	return behavior_registry.get_behavior(unit.behavior_id) if behavior_registry != null else null

static func explode_cross_at(state: GameState, center: Vector2i, source_uid: String,
		opts: Dictionary = {}) -> Array[Dictionary]:
	return _gem_explosion_rules().explode_cross_at(state, center, source_uid, opts)

static func explode_at(state: GameState, center: Vector2i, damage: int, source_uid: String,
		gem_ctx: Dictionary = {}) -> Array[Dictionary]:
	return _gem_explosion_rules().explode_at(state, center, damage, source_uid, gem_ctx)

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

