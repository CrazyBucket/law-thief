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
const GEM_HEAVY_ARMOR := "gem_heavy_armor"
const GEM_CONDUCTIVE := "gem_conductive"
const GEM_FRAGILE := "gem_fragile"
const GEM_CHAOS := "gem_chaos"

const TILE_FLOOR := "tile_floor"
const TILE_SPIKE := "tile_spike"
const TILE_WATER := "tile_water"
const TILE_ALTAR := "tile_altar"      # 祭坛：有 1 个红槽，嵌入宝石触发全场效果
const TILE_PILLAR := "tile_pillar"    # 机关柱：有 1 个蓝槽，嵌入宝石提供持续光环

const LOCK_ARMOR := "armor_lock"

const ACTION_MOVE := "move"
const ACTION_ATTACK := "attack"
const ACTION_SKILL := "skill"
const ACTION_EXTRACT := "extract"
const ACTION_INSERT := "insert"
const ACTION_TRIGGER := "trigger"
const ACTION_END_TURN := "end_turn"
const ACTION_NONE := ""

const EXTRACT_RANGE := 3
const INSERT_RANGE := 3
const TRIGGER_RANGE := 3
const SKILL_RANGE := 3

const EXPLOSION_DAMAGE := 2
const EXPLOSION_RADIUS := 1
const GRAVITY_COLLISION_DAMAGE := 1
const SPIKE_DAMAGE := 2
const POISON_FOG_DAMAGE := 1
const POISON_FOG_DURATION := 2
const POISON_SKILL_DEBUFF_TURNS := 3

const STATUS_POISON := "poison"
const STATUS_ARMOR := "armor"
const STATUS_ROOTED := "rooted"
const STATUS_EXPOSED := "exposed"
const STATUS_LAWLESS := "lawless"
