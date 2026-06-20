class_name Constants
extends RefCounted

const BOARD_SIZE := Vector2i(8, 8)
const CELL_SIZE := 128
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

const SPLIT_ATTACK_RANGE := 1              # 红槽分裂：仅相邻格可瞄准
const SPLIT_ATTACK_DAMAGE_RATIO := 0.7     # 红槽：三发伤害倍率
const SPLIT_DAMAGE_REDIRECT_RATIO := 0.5   # 蓝槽：转移伤害比例（原单位受剩余50%）
const SPLIT_SURROUND_RADIUS := 1           # 蓝槽：转移范围（占格外圈切比雪夫距离）
const SPLIT_STAT_RATIO := 0.3              # 黑槽：分身全属性倍率
const SPLIT_DEATH_HP_MERGE_DIVISOR := 2    # 黑槽：战斗结算时分身血量之和除以此值

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

const ATTACK_RANGE := 3
const EXTRACT_RANGE := 3
const INSERT_RANGE := 3
const TRIGGER_RANGE := 3
const EXPLOSION_DAMAGE := 12
const EXPLOSION_RADIUS := 1
const EXPLOSION_CROSS_DAMAGE := 12   # 红槽十字四邻溅射（命中格为中心，不含对角）
const EXPLOSION_DEATH_RADIUS := 1   # 死亡爆炸半径（3x3 = radius 1 的 chebyshev 范围）
const CHARGE_EXPLODE_DASH_RANGE := 2  # 红槽冲刺爆炸：自爆前最大冲刺格数
const GRAVITY_COLLISION_DAMAGE := 3
const ENEMY_GRAVITY_PULL_RANGE := 4
const KNOCKBACK_COLLISION_DAMAGE := -1  # 击退碰撞伤害：-1 = 按实际位移格数自动算（max(1, steps)）
const SPIKE_DAMAGE := 5
const POISON_FOG_DAMAGE := 3
const POISON_FOG_DURATION := 2
const POISON_SKILL_DEBUFF_TURNS := 3

const ARC_PROC_CHANCE := 0.066       # 电弧弹射命中麻痹概率 6.6%
const ARC_PARALYSIS_CHANCE := 0.33   # 落雷/蓝槽反击麻痹概率 33%
const ARC_CHAIN_DAMAGE_RATIO := 0.2  # 弹射伤害倍率 20%
const ARC_CHAIN_RANGE := 2           # 电弧弹射范围
const ARC_HIT_DAMAGE := 8            # 电弧单次命中伤害
const LIGHTNING_DEATH_DAMAGE := 10   # 死亡落雷固定伤害
const FIRE_DEATH_FIRE_COUNT := 5     # 死亡爆裂火团数
const FIRE_DEATH_RADIUS := 2         # 死亡爆裂范围（5x5 = radius 2）
const ICE_DEATH_RADIUS := 1          # 冰冻死亡范围（3x3 = radius 1）

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
const STATUS_VULNERABLE := "vulnerable"  # 易伤：受到伤害 +50%，被强制位移踩入地刺时附加
const STATUS_WEAK := "weak"  # 虚弱：普通攻击伤害变为原先的 75%
const STATUS_LIGHT_EXPOSED := "light_exposed"
const STATUS_BLINDED := "blinded"
const STATUS_COUNTER_MARK := "counter_mark"
const STATUS_EXTRA_ATTACK := "extra_attack"
const STATUS_EXTRA_MOVE := "extra_move"

const TILE_MOD_POISON_FOG := "poison_fog"
const TILE_MOD_FIRE := "fire"
const TILE_MOD_TOXIC_SMOKE := "toxic_smoke"
const FIRE_DURATION := 2
const FIRE_SPREAD_CHANCE := 0.5

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

const BARREL_HP              := 3
const BARREL_EXPLOSION_DAMAGE := 10
const BARREL_EXPLOSION_RADIUS := 1

const SPIKE_COLLISION_DAMAGE := 10  # 强制位移踩入地刺的基础伤害（易伤状态下 ×1.5 = 15）

# ─── 新地块 tile_id ────────────────────────────────────────────────────────────
const TILE_ICE   := "tile_ice"
const TILE_GRASS := "tile_grass"
const TILE_BUSH  := "tile_bush"   # 草丛（投射物 50% 被阻挡）

const BUSH_PROJECTILE_BLOCK_CHANCE := 0.5
const GRASS_GROW_CHANCE            := 0.2  # 草地每回合长成草丛的概率

# ─── 新地块语义标签 ────────────────────────────────────────────────────────────
const TAG_TILE_FLAMMABLE := "tile:flammable"  # 可燃地块（草地/草丛）
const TAG_TILE_ICE       := "tile:ice"
const TAG_TILE_WATER     := "tile:water"      # 水洼（含毒水洼）

# ─── 单位语义标签 ──────────────────────────────────────────────────────────────
const TAG_UNIT_BOMB_RAT := "unit:bomb_rat"
const TAG_UNIT_PATROL_GUARD := "unit:patrol_guard"
const TAG_UNIT_STONE_BOW_GUARD := "unit:stone_bow_guard"
const TAG_UNIT_FISSION_SLIME := "unit:fission_slime"
const TAG_UNIT_MOBILE := "unit:mobile"
const TAG_UNIT_RANGED := "unit:ranged"
const TAG_UNIT_SPLIT_CLONE := "unit:split_clone"
const TAG_UNIT_OVERLOAD_ENFORCER := "unit:overload_enforcer"
const TAG_UNIT_LAW_BEAST := "unit:law_beast"

const OVERLOAD_LAWLESS_ANY_EXTRACT := "lawless_any_extract"
const OVERLOAD_GEM_OP_DAMAGE := "gem_op_damage"
const OVERLOAD_ECHO_EXTRACT := "echo_extract"
const OVERLOAD_RANDOM_ENEMY_GEMS := "random_enemy_gems"
const OVERLOAD_SPAWN_ENFORCER := "spawn_enforcer"
const OVERLOAD_AI_CONTROL := "ai_control"
const OVERLOAD_SPAWN_LAW_BEAST := "spawn_law_beast"
const OVERLOAD_GEM_OP_DAMAGE_AMOUNT := 3
const LOCK_OVERLOAD_SLOT := "overload_slot"

const BOMB_RAT_HP_ROLL_MAX := 5

const PATROL_GUARD_HP_ROLL_MAX := 4
const PATROL_GUARD_CHARGE_BONUS := 2
const PATROL_GUARD_CHARGE_MIN_STEPS := 2
const PATROL_GUARD_RAMPAGE_MOVE_BONUS := 1

const STONE_BOW_HP_ROLL_MAX := 3
const STONE_BOW_ATTACK_RANGE := 3
const STONE_BOW_DEPLOY_RANGE_BONUS := 1
const STONE_BOW_FAULTY_MISS_CHANCE := 0.5
const STONE_BOW_FAULTY_DAMAGE_BONUS := 1
const STONE_BOW_KITE_IDEAL_RANGE := 3      # 风筝理想射击距离
const STONE_BOW_KITE_MIN_RANGE := 2        # 低于此距离优先后撤

const FISSION_SLIME_HP_ROLL_MAX := 6
const FISSION_SLIME_SPLIT_STAT_RATIO := 0.5
const FISSION_SLIME_SLAM_PUSH_STEPS := 1
const FISSION_SLIME_TRAMPLE_DAMAGE := 3
const DAMAGE_REASON_SLAM := "slam_attack"
const DAMAGE_REASON_TRAMPLE := "trample"

# ─── 地块语义标签 ──────────────────────────────────────────────────────────────
# 通过 tile.has_tile_tag() 查询，将 tile_id 字面量比较集中到 TileState 内部
const TAG_TILE_CONDUCTIVE   := "tile:conductive"   # 导体地块（电弧/电击可连锁）
const TAG_TILE_INTERACTIVE  := "tile:interactive"  # 可交互地块（有槽位，可嵌入宝石）
