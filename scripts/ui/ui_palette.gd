class_name UiPalette
extends RefCounted

## 全游戏 UI 唯一调色板。表现层颜色一律引用此处，禁止在各 UI 文件再硬编码。
## 色板基调：低饱和深蓝夜色底 + 高对比语义色，硬边像素风。

const BG_DEEP := Color("#0d0e16")
const BG_PANEL := Color("#161826")
const BG_DOCK := Color("#11131e")
const BG_RAISED := Color("#1f2233")
const BG_INSET := Color("#0a0b12")

const EDGE_DARK := Color("#05060a")
const EDGE_MID := Color("#2c3147")
const EDGE_LIGHT := Color("#454b66")
const EDGE_BRIGHT := Color("#6a7190")
const EDGE_ACCENT := Color("#c9a04a")

const TEXT_BRIGHT := Color("#f2f3f7")
const TEXT_MUTED := Color("#9aa0b4")
const TEXT_FAINT := Color("#666b78")
const TEXT_GOLD := Color("#f2cf6b")
const TEXT_HINT := Color("#c7b878")
const TEXT_OUTLINE := Color("#05060af2")

const HP_HIGH := Color("#4ec167")
const HP_MID := Color("#e8b33b")
const HP_LOW := Color("#d84a4a")
const HP_BG := Color("#0a0b12")

const SHIELD_FILL := Color("#c4ccd8")
const SHIELD_FILL_HI := Color("#e9eef5")
const SHIELD_BG := Color("#14161f")
const SHIELD_BORDER := Color("#5a6074")

const PHASE_PLAYER := Color("#58a7e8")
const PHASE_ENEMY := Color("#e05656")
const PHASE_END := Color("#8b8fa0")

const SLOT_RED := Color("#e85050")
const SLOT_BLUE := Color("#54a0ea")
const SLOT_BLACK := Color("#8d8da0")
const SLOT_BLACK_DEEP := Color("#26262f")

const RARITY_COMMON := Color("#c0c4d2")
const RARITY_UNCOMMON := Color("#5fc06a")
const RARITY_RARE := Color("#6ec6f5")
const RARITY_EPIC := Color("#c77dff")
const RARITY_LEGENDARY := Color("#ffd166")
const RARITY_BOSS := Color("#ff8a5b")

const ACTION_MOVE := Color("#3f86c8")
const ACTION_COMBAT := Color("#c84848")
const ACTION_SKILL := Color("#9a5ad8")
const ACTION_GEM := Color("#46b478")
const ACTION_END := Color("#d8a23f")

const HILITE_MOVE := Color("#58a7e8")
const HILITE_REACH := Color("#6be58a")
const HILITE_TARGET := Color("#f2e9b0")
const HILITE_RANGE := Color("#e8954a")
const HILITE_DANGER := Color("#d84a4a")

const INTENT_ATTACK := Color("#e05656")
const INTENT_MOVE := Color("#58a7e8")
const INTENT_SKILL := Color("#b06ae0")
const INTENT_IDLE := Color("#8b8fa0")

const POISON_GREEN := Color("#6ce04f")
const FIRE_ORANGE := Color("#f07a23")
const ARMOR_STEEL := Color("#b8c4d8")
const EXPOSE_YELLOW := Color("#f5e878")
const BLIND_SAND := Color("#e8dca0")
const BIND_VIOLET := Color("#8a72e8")
const REVEAL_AMBER := Color("#e8b455")
const DISORDER_RED := Color("#e85050")
const AI_MAGENTA := Color("#d044e8")
const PLUNDER_ORANGE := Color("#e88c38")
const PARALYZE_YELLOW := Color("#e0e033")
const FROZEN_CYAN := Color("#8de8ff")
const SLOW_CYAN := Color("#7ed4ec")
const WET_BLUE := Color("#66aef5")
const STAGNATE_ICE := Color("#9cd6f5")
const VULNERABLE_RED := Color("#f07070")
const STATUS_FALLBACK := Color("#b2b2bf")

const BRAND_RED := Color("#eb4860")
const BRAND_GLOW := Color("#ff9e70")

const HEAL_GREEN := Color("#5fdc7a")
const CRIT_GOLD := Color("#f5d156")
const MISS_GRAY := Color("#8b8fa0")

const ROOM_COMBAT := Color("#d84a4a")
const ROOM_ELITE := Color("#c04a78")
const ROOM_SHOP := Color("#f2cf6b")
const ROOM_EVENT := Color("#a585e8")
const ROOM_REST := Color("#58a7e8")
const ROOM_START := Color("#5fc06a")
const ROOM_END := Color("#f2b93f")
const ROOM_EXIT := Color("#7ec4ec")
const ROOM_UNKNOWN := Color("#8b8fa0")


static func rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return RARITY_UNCOMMON
		"rare":
			return RARITY_RARE
		"epic":
			return RARITY_EPIC
		"legendary":
			return RARITY_LEGENDARY
		"boss":
			return RARITY_BOSS
	return RARITY_COMMON


static func intent_color(intent_type: String) -> Color:
	match intent_type:
		"melee_attack", "split_attack", "trample":
			return INTENT_ATTACK
		"slam_attack":
			return HEAL_GREEN
		"ranged_attack":
			return BLIND_SAND
		"explosion_attack", "charge_explode", "fire_attack", "impact_attack":
			return FIRE_ORANGE
		"pull":
			return BIND_VIOLET
		"poison_attack":
			return POISON_GREEN
		"arc_attack", "light_beam":
			return PARALYZE_YELLOW
		"ice_attack":
			return STAGNATE_ICE
		"extract":
			return AI_MAGENTA
		"move":
			return INTENT_MOVE
		"lawless_extract", "lawless_attack", "lawless_move", "rolling_uncontrolled":
			return DISORDER_RED
		"black_suicide":
			return SLOT_BLACK_DEEP.lightened(0.15)
		"bomb_rat_plunder_wait":
			return PHASE_END
		"bomb_rat_plunder_steal":
			return INTENT_ATTACK
	return INTENT_IDLE


static func slot_color(slot_type: String) -> Color:
	match slot_type:
		"red":
			return SLOT_RED
		"blue":
			return SLOT_BLUE
		"black":
			return SLOT_BLACK
	return TEXT_BRIGHT
