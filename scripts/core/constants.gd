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

const TILE_FLOOR := "tile_floor"
const TILE_SPIKE := "tile_spike"
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

const ACTION_MOVE := "move"
const ACTION_ATTACK := "attack"
const ACTION_SKILL := "skill"
const ACTION_EXTRACT := "extract"
const ACTION_INSERT := "insert"
const ACTION_TRIGGER := "trigger"
const ACTION_END_TURN := "end_turn"
const ACTION_NONE := ""

const ATTACK_RANGE := 3
const EXTRACT_RANGE := 3
const INSERT_RANGE := 3
const TRIGGER_RANGE := 3
const SKILL_RANGE := 3

const EXPLOSION_DAMAGE := 12
const EXPLOSION_RADIUS := 1
const EXPLOSION_CROSS_DAMAGE := 1   # 爆炸宝石命中时十字扩散伤害
const EXPLOSION_DEATH_RADIUS := 1   # 死亡爆炸半径（3x3 = radius 1 的 chebyshev 范围）
const GRAVITY_COLLISION_DAMAGE := 3
const KNOCKBACK_COLLISION_DAMAGE := 3  # 击退撞墙/撞单位碰撞伤害
const SPIKE_DAMAGE := 5
const POISON_FOG_DAMAGE := 3
const POISON_FOG_DURATION := 2
const POISON_SKILL_DEBUFF_TURNS := 3

const ARC_PROC_CHANCE := 0.066       # 电弧触发概率 6.6%
const ARC_PARALYSIS_CHANCE := 0.33   # 电弧麻痹概率 33%（落雷用）
const ARC_CHAIN_DAMAGE_RATIO := 0.2  # 弹射伤害倍率 20%
const ARC_CHAIN_RANGE := 2           # 电弧弹射范围
const ARC_HIT_DAMAGE := 8            # 电弧单次命中伤害
const LIGHTNING_DEATH_DAMAGE := 25   # 死亡落雷固定伤害
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
const STATUS_SLUGGISH := "sluggish"  # 冰冻黑槽：下回合行动顺序垫底
const STATUS_VULNERABLE := "vulnerable"  # 易伤：受到伤害 +50%，被推入地刺时附加

const TILE_MOD_POISON_FOG := "poison_fog"
const TILE_MOD_FIRE := "fire"
const FIRE_DURATION := 2
const FIRE_SPREAD_CHANCE := 0.5

const TILE_MOD_POISON_PUDDLE := "poison_puddle"

# ─── 基础地块 ground 标签 ──────────────────────────────────────────────────────
const GROUND_TAG_FLAMMABLE  := "ground:flammable"   # 可被点燃（草地、草丛）
const GROUND_TAG_ICE        := "ground:ice"          # 冰面：强制位移 +1 格
const GROUND_TAG_WATER      := "ground:water"        # 水洼：进入上潮湿，移动消耗 2

# ─── 地块实体 ──────────────────────────────────────────────────────────────────
const ENTITY_ROCK   := "entity_rock"    # 石块：无敌，阻挡移动与弹道
const ENTITY_SPIKE  := "entity_spike"   # 地刺：进入受伤，碰撞暴击
const ENTITY_BARREL := "entity_barrel"  # 油桶：可破坏，着火/血量归零时爆炸

const BARREL_HP              := 3
const BARREL_EXPLOSION_DAMAGE := 10
const BARREL_EXPLOSION_RADIUS := 1

const SPIKE_COLLISION_DAMAGE := 10  # 被推/拉撞入地刺时的基础伤害（易伤状态下 ×1.5 = 15）

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
# 通过 unit.has_tag() 查询，避免在业务逻辑中硬编码 unit_def_id 字符串
const TAG_UNIT_BOMBER    := "unit:bomber"    # 自爆单位（携带爆炸宝石的特殊 AI 角色）
const TAG_UNIT_TRAINING  := "unit:training"  # 训练场守卫（教学关专用，弱化单位）
const TAG_UNIT_HEAVY     := "unit:heavy"     # 重甲单位（高血量、低速）
const TAG_UNIT_MOBILE    := "unit:mobile"    # 高机动单位（速度优先、移动力高）
const TAG_UNIT_RANGED    := "unit:ranged"    # 远程攻击单位（射程 > 1）
const TAG_UNIT_TURRET    := "unit:turret"    # 炮台单位（零移动力，固定位置）
const TAG_UNIT_THIEF     := "unit:thief"     # 窃取型单位（可主动拔取宝石）
const TAG_UNIT_PULLER    := "unit:puller"    # 引力型单位（使用引力宝石）

# ─── 地块语义标签 ──────────────────────────────────────────────────────────────
# 通过 tile.has_tile_tag() 查询，将 tile_id 字面量比较集中到 TileState 内部
const TAG_TILE_HAZARD       := "tile:hazard"       # 危险地块（进入时受到伤害）
const TAG_TILE_CONDUCTIVE   := "tile:conductive"   # 导体地块（电弧/电击可连锁）
const TAG_TILE_INTERACTIVE  := "tile:interactive"  # 可交互地块（有槽位，可嵌入宝石）
