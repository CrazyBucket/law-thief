extends Node

## 遗物事件系统与 Modifier 查询层
##
## 事件词表（fire_event 的 event_id）：
##   battle_start       战斗开始
##   turn_start         回合开始（payload: turn_index）
##   turn_end           回合结束（payload: turn_index）
##   before_attack      攻击前（payload: attacker_uid, target_uid）
##   after_attack_hit   命中后（payload: attacker_uid, target_uid, damage）
##   before_damage_taken 受伤前（payload: unit_uid, amount, reason）
##   after_damage_taken 受伤后（payload: unit_uid, amount, reason）
##   unit_die           击杀后（payload: unit_uid, killer_uid, reason）
##   after_extract      拔出宝石后（payload: unit_uid, gem_id, slot_type）
##   after_insert       嵌入宝石后（payload: unit_uid, gem_id, slot_type）
##   move_step          走一步（payload: unit_uid, from, to）
##   battle_win         战斗胜利（payload: encounter_id）
##
## Modifier 词表（query_modifier 的 modifier_id）：
##   attack_damage_mult      攻击伤害乘数（叠乘）
##   arc_damage_mult         电弧伤害乘数（叠乘）
##   collision_damage_mult   碰撞伤害乘数（叠乘）
##   extract_range_bonus     拔出射程加成（叠加）
##   insert_range_bonus      嵌入射程加成（叠加）
##   move_bonus              移动力加成（叠加）
##   forced_move_immune      强制位移免疫（bool，任一遗物为 true 则免疫）
##   tile_effect_immune      地块效果免疫（bool）
##   first_damage_absorb     首次受伤吸收为 1（bool，使用后消耗 battle_temp_flag）

## effect 格式（JSON effects 数组中一条）：
##   {"on": "<event_id>", "action": "<action_id>", ...params}
##   {"modifier": "<modifier_id>", ...params}
## modifier 格式：返回数值或 bool，由 query_modifier 汇总


# ─── 内部结构 ──────────────────────────────────────────────────────────────────

## _handlers[event_id] → Array[Callable]（每个 Callable 接受 state, payload）
var _event_handlers: Dictionary = {}

## _modifier_handlers[modifier_id] → Array[Callable]（返回 Variant）
var _modifier_handlers: Dictionary = {}


func _ready() -> void:
	_register_builtin_actions()


# ─── 对外接口 ─────────────────────────────────────────────────────────────────

## 对当前局持有的所有遗物触发事件
## 调用方只需传 state 和 payload，不用关心谁持有哪些遗物
func fire_event(event_id: String, state: GameState, payload: Dictionary = {}) -> void:
	var owned := RunService.get_owned_relics()
	for relic_id in owned:
		var def: Dictionary = DataRegistry.get_relic_def(relic_id)
		var effects: Variant = def.get("effects", [])
		if not effects is Array:
			continue
		for effect in effects:
			if not effect is Dictionary:
				continue
			if str(effect.get("on", "")) != event_id:
				continue
			_dispatch_action(relic_id, effect, state, payload)


## 查询 modifier：对当前局持有的所有遗物累计查询
## 对于乘数类 modifier，返回叠乘结果；对于加成类，返回叠加；对于 bool 类，返回任一为 true
func query_modifier(modifier_id: String, state: GameState, ctx: Dictionary = {}) -> Variant:
	var owned := RunService.get_owned_relics()
	var mult_result := 1.0
	var add_result := 0
	var bool_result := false
	var is_mult := modifier_id.ends_with("_mult")
	var is_bool := modifier_id.ends_with("_immune") or modifier_id == "first_damage_absorb"

	for relic_id in owned:
		var def: Dictionary = DataRegistry.get_relic_def(relic_id)
		var effects: Variant = def.get("effects", [])
		if not effects is Array:
			continue
		for effect in effects:
			if not effect is Dictionary:
				continue
			if str(effect.get("modifier", "")) != modifier_id:
				continue
			var val: Variant = _eval_modifier_entry(relic_id, effect, state, ctx)
			if is_bool:
				if val == true:
					bool_result = true
			elif is_mult:
				mult_result *= float(val)
			else:
				add_result += int(val)

	if is_bool:
		return bool_result
	elif is_mult:
		return mult_result
	else:
		return add_result


# ─── Action 分发 ──────────────────────────────────────────────────────────────

func _dispatch_action(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var action: String = str(effect.get("action", ""))
	match action:
		"add_armor":
			_action_add_armor(relic_id, effect, state, payload)
		"heal":
			_action_heal(relic_id, effect, state, payload)
		"add_move":
			_action_add_move(relic_id, effect, state, payload)
		"mark_flag":
			_action_mark_flag(relic_id, effect, state, payload)
		_:
			DebugService.log_info("RelicEffectRegistry: unknown action '%s' for %s" % [action, relic_id])


# ─── 内置 actions ──────────────────────────────────────────────────────────────

## add_armor：给目标单位增加临时护甲
## effect: {"on": ..., "action": "add_armor", "target": "player", "amount": <int>}
func _action_add_armor(relic_id: String, effect: Dictionary, state: GameState, _payload: Dictionary) -> void:
	var unit := _resolve_target(effect, state)
	if unit == null:
		return
	var amount: int = int(effect.get("amount", 1))
	unit.armor += amount
	state.log("[Relic] %s -> +%d armor for %s" % [relic_id, amount, unit.uid])


## heal：给目标单位回血
## effect: {"on": ..., "action": "heal", "target": "player", "amount": <int>}
## 可选 "condition": "killer_is_player" 要求 payload.killer_uid == player_uid
func _action_heal(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var condition: String = str(effect.get("condition", ""))
	if condition == "killer_is_player":
		var killer: String = str(payload.get("killer_uid", ""))
		if killer != state.player_uid:
			return
	var unit := _resolve_target(effect, state)
	if unit == null:
		return
	var amount: int = int(effect.get("amount", 1))
	var def := DataRegistry.get_unit_def(unit.unit_def_id)
	var max_hp: int = int(def.get("hp", unit.hp))
	unit.hp = mini(unit.hp + amount, max_hp)
	state.log("[Relic] %s -> +%d hp for %s" % [relic_id, amount, unit.uid])


## add_move：给玩家本回合增加额外移动力
## effect: {"on": ..., "action": "add_move", "amount": <int>}
func _action_add_move(_relic_id: String, effect: Dictionary, state: GameState, _payload: Dictionary) -> void:
	var amount: int = int(effect.get("amount", 1))
	var player := state.get_player()
	if player == null:
		return
	player.move_range += amount


## mark_flag：在 battle_temp_flags 里写一个 flag（供单次触发遗物使用）
## effect: {"on": ..., "action": "mark_flag", "flag": "<key>"}
func _action_mark_flag(_relic_id: String, effect: Dictionary, state: GameState, _payload: Dictionary) -> void:
	var flag: String = str(effect.get("flag", ""))
	if flag.is_empty():
		return
	state.battle_temp_flags[flag] = true


# ─── Modifier 求值 ────────────────────────────────────────────────────────────

## modifier entry 格式：
##   乘数: {"modifier": "attack_damage_mult", "value": 1.3}
##   加成: {"modifier": "move_bonus", "value": 1}
##   bool: {"modifier": "forced_move_immune", "value": true}
##   首次伤害吸收: {"modifier": "first_damage_absorb", "flag": "painkiller_used"}
func _eval_modifier_entry(relic_id: String, effect: Dictionary, state: GameState, _ctx: Dictionary) -> Variant:
	var modifier_id: String = str(effect.get("modifier", ""))
	if modifier_id == "first_damage_absorb":
		var flag: String = str(effect.get("flag", "painkiller_%s_used" % relic_id))
		if state.battle_temp_flags.has(flag):
			return false
		return true
	var val: Variant = effect.get("value", 0)
	return val


# ─── 工具 ────────────────────────────────────────────────────────────────────

func _resolve_target(effect: Dictionary, state: GameState) -> UnitState:
	var target: String = str(effect.get("target", "player"))
	match target:
		"player":
			return state.get_player()
		_:
			return state.units.get(target, null)


func _register_builtin_actions() -> void:
	pass
