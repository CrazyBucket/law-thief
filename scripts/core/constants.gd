class_name Constants
extends RefCounted

const BOARD_SIZE := Vector2i(8, 8)
const ISO_TILE_W := 128
const ISO_TILE_H := 64

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"

const PHASE_PLAYER := "player"
const PHASE_ENEMY := "enemy"
const PHASE_ENDED := "ended"

const SLOT_RED := "red"
const SLOT_BLUE := "blue"
const SLOT_BLACK := "black"

const GEM_EXPLOSION := "gem_explosion"
const GEM_POISON := "gem_poison"
const GEM_GRAVITY := "gem_gravity"
const GEM_CONDUCTIVE := "gem_conductive"
const GEM_FIRE := "gem_fire"
const GEM_ICE := "gem_ice"
const GEM_SPLIT := "gem_split"
const GEM_LIGHT := "gem_light"
const GEM_COUNTER := "gem_counter"
const GEM_ECHO := "gem_echo"
const GEM_FLURRY := "gem_flurry"
const GEM_IMPACT := "gem_impact"

const TILE_FLOOR := "tile_floor"
const TILE_WATER := "tile_water"
const TILE_PILLAR := "tile_pillar"    # 机关柱：有 1 个蓝槽，嵌入宝石提供持续光环

const TILE_ROOM_START := "tile_room_start"
const TILE_ROOM_END := "tile_room_end"
const TILE_ROOM_COMBAT := "tile_room_combat"
const TILE_ROOM_ELITE := "tile_room_elite"
const TILE_ROOM_REST := "tile_room_rest"
const TILE_ROOM_SHOP := "tile_room_shop"
const TILE_ROOM_EVENT := "tile_room_event"

const ROOM_TILE_IDS: Array[String] = [
	TILE_ROOM_START, TILE_ROOM_END, TILE_ROOM_COMBAT, TILE_ROOM_ELITE,
	TILE_ROOM_REST, TILE_ROOM_SHOP, TILE_ROOM_EVENT,
]

const LOCK_ARMOR := "armor_lock"
const LOCK_SPLIT_DISABLED := "split_disabled"

const ACTION_MOVE := "move"
const ACTION_ATTACK := "attack"
const ACTION_EXTRACT := "extract"
const ACTION_INSERT := "insert"
const ACTION_TRIGGER := "trigger"
const ACTION_END_TURN := "end_turn"
const ACTION_NONE := ""

const STATUS_POISON := "poison"
const STATUS_BURNING := "burning"
const STATUS_PARALYZED := "paralyzed"
const STATUS_SLOWED := "slowed"
const STATUS_WET := "wet"
const STATUS_ARMOR := "armor"
const STATUS_ROOTED := "rooted"
const STATUS_EXPOSED := "exposed"
const STATUS_LAWLESS := "lawless"
const STATUS_OVERLOAD_AI_CONTROL := "overload_ai_control"
const STATUS_BOMB_RAT_PLUNDER := "bomb_rat_plunder"  # 炸弹鼠无律掠夺阶段
const STATUS_SLUGGISH := "sluggish"  # 冰冻黑槽：下回合行动顺序垫底
const STATUS_VULNERABLE := "vulnerable"  # 易伤：提高受到的伤害，被强制位移踩入地刺时附加
const STATUS_DISARMED := "disarmed"  # 缴械：下次自身行动期间无法攻击
const STATUS_WEAK := "weak"  # 虚弱：降低普通攻击伤害
const STATUS_LIGHT_EXPOSED := "light_exposed"
const STATUS_BLINDED := "blinded"
const STATUS_COUNTER_MARK := "counter_mark"
const STATUS_EXTRA_ATTACK := "extra_attack"
const STATUS_EXTRA_MOVE := "extra_move"
const STATUS_LAW_WORM_INCUBATING := "law_worm_incubating"
const STATUS_BROODMOTHER_CYCLE := "broodmother_cycle"
const STATUS_BROODMOTHER_CRISIS := "broodmother_crisis"
const STATUS_STORED_FLURRY := "stored_flurry"
const STATUS_STARTLED_FEATHER := "startled_feather"

const TILE_MOD_POISON_FOG := "poison_fog"
const TILE_MOD_FIRE := "fire"
const TILE_MOD_TOXIC_SMOKE := "toxic_smoke"

const TILE_MOD_POISON_PUDDLE := "poison_puddle"

# ─── 基础地块 ground 标签 ──────────────────────────────────────────────────────
const GROUND_TAG_FLAMMABLE  := "ground:flammable"   # 可被点燃（草地、草丛）
const GROUND_TAG_ICE        := "ground:ice"          # 冰面：强制位移 +1 格
const GROUND_TAG_WATER      := "ground:water"        # 水洼：进入上潮湿，移动消耗 2

# ─── 地块实体 ──────────────────────────────────────────────────────────────────
const ENTITY_ROCK   := "entity_rock"    # 石块：无敌，阻挡移动与弹道
const ENTITY_PROP   := "entity_prop"    # 静物：无敌，阻挡移动与弹道，Doodle 贴图
const ENTITY_SPIKE  := "entity_spike"   # 地刺：可通行，步入受伤，强制位移附加易伤
const ENTITY_BARREL := "entity_barrel"  # 油桶：可破坏，着火/血量归零时爆炸

# ─── 新地块 tile_id ────────────────────────────────────────────────────────────
const TILE_ICE   := "tile_ice"
const TILE_GRASS := "tile_grass"
const TILE_BUSH  := "tile_bush"

# ─── 新地块语义标签 ────────────────────────────────────────────────────────────
const TAG_TILE_FLAMMABLE := "tile:flammable"  # 可燃地块（草地/草丛）
const TAG_TILE_ICE       := "tile:ice"
const TAG_TILE_WATER     := "tile:water"      # 水洼（含毒水洼）

# ─── 单位语义标签 ──────────────────────────────────────────────────────────────
const TAG_UNIT_BOMB_RAT := "unit:bomb_rat"
const TAG_UNIT_PATROL_GUARD := "unit:patrol_guard"
const TAG_UNIT_STONE_BOW_GUARD := "unit:stone_bow_guard"
const TAG_UNIT_FISSION_SLIME := "unit:fission_slime"
const TAG_UNIT_SMALL_SLIME := "unit:small_slime"
const TAG_UNIT_MOBILE := "unit:mobile"
const TAG_UNIT_RANGED := "unit:ranged"
const TAG_UNIT_SPLIT_CLONE := "unit:split_clone"
const TAG_UNIT_SPLIT_BLUE_TEMP_CLONE := "unit:split_blue_temp_clone"
const TAG_UNIT_OVERLOAD_ENFORCER := "unit:overload_enforcer"
const TAG_UNIT_LAW_BEAST := "unit:law_beast"
const TAG_UNIT_LAW_WORM := "unit:law_worm"
const TAG_UNIT_BROODMOTHER := "unit:broodmother"
const TAG_UNIT_RUFFLED_CROW := "unit:ruffled_crow"

const OVERLOAD_LAWLESS_ANY_EXTRACT := "lawless_any_extract"
const OVERLOAD_GEM_OP_DAMAGE := "gem_op_damage"
const OVERLOAD_ECHO_EXTRACT := "echo_extract"
const OVERLOAD_RANDOM_ENEMY_GEMS := "random_enemy_gems"
const OVERLOAD_SPAWN_ENFORCER := "spawn_enforcer"
const OVERLOAD_AI_CONTROL := "ai_control"
const OVERLOAD_SPAWN_LAW_BEAST := "spawn_law_beast"
const LOCK_OVERLOAD_SLOT := "overload_slot"

const DAMAGE_REASON_SLAM := "slam_attack"
const DAMAGE_REASON_TRAMPLE := "trample"

# ─── 地块语义标签 ──────────────────────────────────────────────────────────────
# 通过 tile.has_tile_tag() 查询，将 tile_id 字面量比较集中到 TileState 内部
const TAG_TILE_CONDUCTIVE   := "tile:conductive"   # 导体地块（电弧/电击可连锁）
const TAG_TILE_INTERACTIVE  := "tile:interactive"  # 可交互地块（有槽位，可嵌入宝石）
