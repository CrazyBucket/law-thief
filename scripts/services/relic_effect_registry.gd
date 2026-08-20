extends Node
const _SimpleRelicEffects = preload("res://scripts/rules/simple_relic_effects.gd")
const _CounterfeitRules = preload("res://scripts/rules/counterfeit_rules.gd")
const _ScavengerHookRules = preload("res://scripts/rules/scavenger_hook_rules.gd")
const _FightTicketRules = preload("res://scripts/rules/fight_ticket_rules.gd")
const _FuseRules = preload("res://scripts/rules/fuse_rules.gd")
## 遗物事件系统与 Modifier 查询层
##
## 事件词表（fire_event 的 event_id）：
##   battle_start         战斗开始
##   turn_start           回合开始（payload: turn_index）
##   turn_end             回合结束（payload: turn_index）
##   before_attack        攻击前（payload: attacker_uid, target_uid）
##   after_attack_hit     命中后（payload: attacker_uid, target_uid, damage）
##   before_damage_taken  受伤前（payload: unit_uid, amount, reason）
##   after_damage_taken   受伤结算后（payload: unit_uid, source_uid, amount, reason；amount 为实际生命损失）
##   unit_die             击杀后（payload: unit_uid, killer_uid, reason, kill_reason）
##   after_extract        拔出宝石后（payload: unit_uid, gem_id, slot_type, from_uid）
##   after_insert         嵌入宝石后（payload: unit_uid, gem_id, slot_type, from_uid, actor_uid）
##   overload_slot_created 正式生成过载槽后（payload: unit_uid, slot_index, gem_uid）
##   blue_gem_triggered   蓝色宝石效果触发后（payload: actor_uid）
##   move_step            走一步（payload: unit_uid, from, to）
##   battle_win           战斗胜利（payload: encounter_id）
##
## Modifier 词表（query_modifier 的 modifier_id）：
##   attack_damage_mult         攻击伤害乘数（叠乘）
##   arc_damage_bonus           电弧伤害固定加成（叠加，整数）
##   collision_damage_mult      碰撞伤害乘数（叠乘）
##   extract_range_bonus        拔出射程加成（叠加）
##   insert_range_bonus         嵌入射程加成（叠加）
##   move_bonus                 移动力加成（叠加）
##   forced_move_immune         强制位移免疫（bool，仅玩家受铁靴等遗物保护）
##   tile_effect_immune         地块效果免疫（bool）
##   first_damage_absorb        首次受伤吸收为 1（bool）
##   attack_damage_bonus        攻击额外固定伤害（叠加，整数）
##   attack_split_count         攻击分裂次数加成（叠加，整数）
##   arc_bounce_count_bonus     电弧弹射目标数加成（叠加，整数）
##   chaos_launcher_active      混沌发射器激活（bool）
##   split_move_enabled         允许把每回合移动拆成两段（bool）
##   attack_miss_chance         攻击命中率降低（叠加，浮点）
##   armor_break_bonus          普通攻击额外削减护甲（叠加，整数）
##   overlay_move_cost_reduction 地块覆盖层移动消耗减少（需 ctx.overlay_type）
##   split_red_damage_ratio     分裂红槽攻击伤害倍率覆盖（替换常量；取最大值）
##   split_blue_redirect_ratio  分裂蓝槽转移伤害比例覆盖（取最大值）
##   split_black_stat_ratio     分裂黑槽分身属性比例覆盖（取最大值）
##
## Action 词表（_dispatch_action 的 action 字段）：
##   add_shield                 给目标增加护盾（amount，可选 duration）
##   add_armor                  add_shield 的别名
##   heal                       给目标回血（amount，可选 condition）
##   add_move                   给玩家增加移动力（amount）
##   add_temp_move              给玩家增加临时移动力（amount，移动一次后重置）
##   mark_flag                  向 battle_temp_flags 写 flag
##   add_slot                   给玩家新增槽位（slot_type: red/blue/black/random）
##   upgrade_slot               将玩家指定槽位升级为双色槽
##   upgrade_slot_random        随机升级玩家某个单色槽为双色槽
##   replace_gem_random         随机替换玩家某个槽的宝石
##   apply_max_hp_reduction     减少玩家最大 HP（ratio）
##   apply_weak_on_insert_target 对嵌入宝石的目标施加虚弱（condition: insert_to_enemy_from_enemy）
##   random_gem_transform_one   每回合随机将场上一颗宝石变为另一颗

# ─── 内部结构 ──────────────────────────────────────────────────────────────────

## _event_handlers[event_id] → Array[Callable]（每个 Callable 接受 state, payload）
var _event_handlers: Dictionary = {}

## _modifier_handlers[modifier_id] → Array[Callable]（返回 Variant）
var _modifier_handlers: Dictionary = {}

func _ready() -> void:
	_register_builtin_actions()

# ─── 对外接口 ─────────────────────────────────────────────────────────────────
## 对当前局持有的所有遗物触发事件
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

## Applies only the newly acquired relic's immediate effects. This is used by
## battle settlement so slot-granting relics are available to the next reward.
func apply_acquired_relic(relic_id: String, event_id: String, state: GameState) -> void:
	if relic_id.is_empty() or state == null:
		return
	var def: Dictionary = DataRegistry.get_relic_def(relic_id)
	var effects: Variant = def.get("effects", [])
	if not effects is Array:
		return
	for effect in effects:
		if effect is Dictionary and str((effect as Dictionary).get("on", "")) == event_id:
			_dispatch_action(relic_id, effect as Dictionary, state, {})

## 查询 modifier：对当前局持有的所有遗物累计查询
func query_modifier(modifier_id: String, state: GameState, ctx: Dictionary = {}) -> Variant:
	var owned := RunService.get_owned_relics()
	var mult_result := 1.0
	var add_result := 0
	var float_result := 0.0
	var bool_result := false
	var is_mult := modifier_id.ends_with("_mult")
	var is_float := modifier_id == "attack_miss_chance"
	var is_bool := (modifier_id.ends_with("_immune")
		or modifier_id == "first_damage_absorb"
		or modifier_id == "chaos_launcher_active"
		or modifier_id == "split_move_enabled")

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
				if bool(val):
					bool_result = true
			elif is_mult:
				mult_result *= float(val)
			elif is_float:
				float_result += float(val)
			else:
				add_result += int(val)

	if is_bool:
		return bool_result
	elif is_mult:
		return mult_result
	elif is_float:
		return float_result
	else:
		return add_result


## 查询带替换语义的 modifier（取最大值替代，而非叠加）
## 用于 split_red_damage_ratio / split_blue_redirect_ratio / split_black_stat_ratio
func query_override_modifier(modifier_id: String, state: GameState, default_value: float) -> float:
	var owned := RunService.get_owned_relics()
	var best := default_value
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
			var cond: String = str(effect.get("condition", ""))
			if not cond.is_empty():
				if not _check_modifier_condition(cond, state):
					continue
			var v := _resolve_number(effect, "value", default_value)
			if v > best:
				best = v
	return best


# ─── Action 分发 ──────────────────────────────────────────────────────────────

func _dispatch_action(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var action: String = str(effect.get("action", ""))
	match action:
		"add_armor", "add_shield":
			_action_add_shield(relic_id, effect, state, payload)
		"heal":
			_action_heal(relic_id, effect, state, payload)
		"add_move":
			_action_add_move(relic_id, effect, state, payload)
		"add_temp_move":
			_action_add_temp_move(relic_id, effect, state, payload)
		"mark_flag":
			_action_mark_flag(relic_id, effect, state, payload)
		"add_slot":
			_action_add_slot(relic_id, effect, state)
		"upgrade_slot":
			_action_upgrade_slot(relic_id, effect, state)
		"upgrade_slot_random":
			_action_upgrade_slot_random(relic_id, effect, state)
		"replace_gem_random":
			_action_replace_gem_random(relic_id, effect, state, payload)
		"apply_max_hp_reduction":
			_action_apply_max_hp_reduction(relic_id, effect, state)
		"apply_weak_on_insert_target":
			_action_apply_weak_on_insert_target(relic_id, effect, state, payload)
		"random_gem_transform_one":
			_action_random_gem_transform_one(relic_id, state)
		"grant_shield_if_adjacent_after_move":
			_SimpleRelicEffects.grant_shield_if_adjacent_after_move(relic_id, effect, state, payload)
		"store_unused_move":
			_SimpleRelicEffects.store_unused_move(relic_id, state)
		"clear_flywheel_on_manual_shot":
			_SimpleRelicEffects.clear_flywheel_on_manual_shot(relic_id, state, payload)
		"leave_counterfeit_once_per_turn": _CounterfeitRules.try_leave_once(relic_id, effect, state, payload)
		"hook_enemy_drop_once": _ScavengerHookRules.try_hook_enemy_drop(relic_id, effect, state, payload)
		"return_hooked_gem": _ScavengerHookRules.return_before_settlement(relic_id, effect, state, payload)
		"mark_enemy_retaliation_once": _FightTicketRules.try_mark_retaliation(relic_id, effect, state, payload)
		"clear_invalid_retaliation": _FightTicketRules.clear_for_death(state, str(payload.get("unit_uid", "")))
		"defer_first_overload_mutation": _FuseRules.try_defer_first_overload(relic_id, effect, state, payload)
		"materialize_deferred_mutation": _FuseRules.materialize_after_win(relic_id, effect, state, payload)
		_:
			DebugService.log_info("RelicEffectRegistry: unknown action '%s' for %s" % [action, relic_id])


# ─── 内置 actions ──────────────────────────────────────────────────────────────
func _action_add_shield(_relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var unit := _resolve_target(effect, state, payload)
	if unit == null:
		return
	var amount := _resolve_amount(effect, 1)
	var duration: int = int(effect.get("duration", 0))
	StatusRules.apply_shield(state, unit, amount, duration)
	state.log("[Relic] %s -> +%d shield for %s" % [_relic_id, amount, unit.uid])


func _action_heal(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var condition: String = str(effect.get("condition", ""))
	if condition == "killer_is_player":
		var killer: String = str(payload.get("killer_uid", ""))
		if killer != state.player_uid:
			return
	elif condition == "black_gem_kill":
		if not _check_black_gem_kill(state, payload):
			return
	var unit := _resolve_target(effect, state)
	if unit == null:
		return
	var amount := _resolve_amount(effect, 1)
	var def := DataRegistry.get_unit_def(unit.unit_def_id)
	var max_hp: int = int(def.get("max_hp", unit.max_hp))
	unit.hp = mini(unit.hp + amount, max_hp)
	state.log("[Relic] %s -> +%d hp for %s" % [relic_id, amount, unit.uid])
func _action_add_move(_relic_id: String, effect: Dictionary, state: GameState, _payload: Dictionary) -> void:
	var amount := _resolve_amount(effect, 1)
	var player := state.get_player()
	if player == null:
		return
	player.move_points += amount

## 临时移动力：加 1 点，但只能用于移动一次后重置
## 通过 battle_temp_flags 标记是否已消耗
func _action_add_temp_move(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	_SimpleRelicEffects.add_temp_move(relic_id, effect, state, payload)

func _action_mark_flag(_relic_id: String, effect: Dictionary, state: GameState, _payload: Dictionary) -> void:
	var flag: String = str(effect.get("flag", ""))
	if flag.is_empty():
		return
	state.battle_temp_flags[flag] = true


## add_slot：持久给玩家新增一个槽位
## slot_type 支持 "random"（随机 red/blue/black 之一）
func _action_add_slot(relic_id: String, effect: Dictionary, state: GameState) -> void:
	var once_flag: String = str(effect.get("once_per_run", ""))
	if not once_flag.is_empty():
		var rt := RunService.get_relic_runtime(relic_id)
		if rt != null and rt.flags.get(once_flag, false):
			return
	var slot_type: String = str(effect.get("slot_type", Constants.SLOT_RED))
	if slot_type == "random":
		var types := [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]
		slot_type = types[RngService.roll_int("add_slot_random_%s" % relic_id, 0, 2)]
	var player := state.get_player()
	if player == null:
		return
	var new_slot := SlotState.create(slot_type)
	player.slots.append(new_slot)
	state.log("[Relic] %s -> player +1 %s slot (total %d)" % [relic_id, slot_type, player.slots.size()])
	var run := RunService.get_run()
	if run != null:
		run.add_extra_slot(slot_type)
	if not once_flag.is_empty():
		var rt2 := RunService.get_relic_runtime(relic_id)
		if rt2 != null:
			rt2.flags[once_flag] = true
		RunService.save_run()


## upgrade_slot：持久将玩家指定类型槽升级为双色槽
func _action_upgrade_slot(relic_id: String, effect: Dictionary, state: GameState) -> void:
	var once_flag: String = str(effect.get("once_per_run", ""))
	if not once_flag.is_empty():
		var rt := RunService.get_relic_runtime(relic_id)
		if rt != null and rt.flags.get(once_flag, false):
			return
	var from_type: String = str(effect.get("from_type", ""))
	var to_dual: String = str(effect.get("to_dual_type", ""))
	if from_type.is_empty() or to_dual.is_empty():
		return
	var player := state.get_player()
	if player == null:
		return
	for slot in player.slots:
		if slot.slot_type == from_type and slot.dual_type.is_empty():
			slot.dual_type = to_dual
			state.log("[Relic] %s -> upgraded %s slot to dual(%s/%s)" % [relic_id, from_type, from_type, to_dual])
			var run := RunService.get_run()
			if run != null:
				run.add_slot_upgrade(from_type, to_dual)
			if not once_flag.is_empty():
				var rt2 := RunService.get_relic_runtime(relic_id)
				if rt2 != null:
					rt2.flags[once_flag] = true
				RunService.save_run()
			return


## upgrade_slot_random：随机选玩家一个单色槽升级为双色槽（另一种颜色随机）
func _action_upgrade_slot_random(relic_id: String, effect: Dictionary, state: GameState) -> void:
	var once_flag: String = str(effect.get("once_per_run", ""))
	if not once_flag.is_empty():
		var rt := RunService.get_relic_runtime(relic_id)
		if rt != null and rt.flags.get(once_flag, false):
			return
	var player := state.get_player()
	if player == null:
		return
	var eligible: Array[SlotState] = []
	for slot in player.slots:
		if slot.dual_type.is_empty():
			eligible.append(slot)
	if eligible.is_empty():
		return
	var target_slot: SlotState = eligible[RngService.roll_int(
		"upgrade_slot_random_%s" % relic_id, 0, eligible.size() - 1
	)]
	var all_colors := [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]
	all_colors.erase(target_slot.slot_type)
	var dual_color: String = all_colors[RngService.roll_int(
		"upgrade_slot_dual_color_%s" % relic_id, 0, all_colors.size() - 1
	)]
	target_slot.dual_type = dual_color
	state.log("[Relic] %s -> upgraded %s slot to dual(%s/%s)" % [
		relic_id, target_slot.slot_type, target_slot.slot_type, dual_color
	])
	var run := RunService.get_run()
	if run != null:
		run.add_slot_upgrade(target_slot.slot_type, dual_color)
	if not once_flag.is_empty():
		var rt2 := RunService.get_relic_runtime(relic_id)
		if rt2 != null:
			rt2.flags[once_flag] = true
		RunService.save_run()


## replace_gem_random：随机将玩家某个槽的宝石替换为另一个随机宝石
func _action_replace_gem_random(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary = {}) -> void:
	var condition: String = str(effect.get("condition", ""))
	if condition == "killer_is_player":
		var killer: String = str(payload.get("killer_uid", ""))
		if killer != state.player_uid:
			return
	var once_flag: String = str(effect.get("once_per_run", ""))
	if not once_flag.is_empty():
		var rt := RunService.get_relic_runtime(relic_id)
		if rt != null and rt.flags.get(once_flag, false):
			return
	var player := state.get_player()
	if player == null:
		return
	var filled_slots: Array[SlotState] = []
	for slot in player.slots:
		if not slot.gem_uid.is_empty():
			filled_slots.append(slot)
	if filled_slots.is_empty():
		return
	var target_slot: SlotState = filled_slots[RngService.roll_int(
		"replace_gem_%s" % relic_id, 0, filled_slots.size() - 1
	)]
	var old_gem: GemState = state.gems.get(target_slot.gem_uid, null)
	if old_gem == null:
		return
	var old_gem_id := old_gem.gem_id
	var new_gem_id := DataRegistry.roll_spawnable_gem_id("replace_gem_roll_%s" % relic_id)
	if new_gem_id.is_empty() or new_gem_id == old_gem_id:
		return
	old_gem.gem_id = new_gem_id
	old_gem.def_overrides = {}
	state.log("[Relic] %s -> replaced %s→%s in player slot" % [relic_id, old_gem_id, new_gem_id])
	if not once_flag.is_empty():
		var rt2 := RunService.get_relic_runtime(relic_id)
		if rt2 != null:
			rt2.flags[once_flag] = true
			RunService.save_run()


## apply_max_hp_reduction：减少玩家最大 HP（ratio = 比例，如 0.3 = 减少30%）
func _action_apply_max_hp_reduction(relic_id: String, effect: Dictionary, state: GameState) -> void:
	var once_flag: String = str(effect.get("once_per_run", ""))
	if not once_flag.is_empty():
		var rt := RunService.get_relic_runtime(relic_id)
		if rt != null and rt.flags.get(once_flag, false):
			return
	var player := state.get_player()
	if player == null:
		return
	var ratio := _resolve_number(effect, "ratio", 0.0)
	if ratio <= 0.0:
		push_error("RelicEffectRegistry: apply_max_hp_reduction requires a positive ratio")
		return
	var reduction: int = maxi(1, int(float(player.max_hp) * ratio))
	player.max_hp = maxi(1, player.max_hp - reduction)
	player.hp = mini(player.hp, player.max_hp)
	state.log("[Relic] %s -> player max_hp reduced by %d (now %d)" % [relic_id, reduction, player.max_hp])
	if not once_flag.is_empty():
		var rt2 := RunService.get_relic_runtime(relic_id)
		if rt2 != null:
			rt2.flags[once_flag] = true
		RunService.save_run()


## apply_weak_on_insert_target：嫁祸——玩家将宝石从敌人身上拔出再嵌入另一敌人时，施加虚弱
## condition: "insert_to_enemy_from_enemy" 要求 payload.from_uid 是敌人、unit_uid 是敌人
func _action_apply_weak_on_insert_target(relic_id: String, effect: Dictionary, state: GameState, payload: Dictionary) -> void:
	var condition: String = str(effect.get("condition", ""))
	if condition == "insert_to_enemy_from_enemy":
		var unit_uid: String = str(payload.get("unit_uid", ""))
		var from_uid: String = str(payload.get("from_uid", ""))
		var target_unit: UnitState = state.units.get(unit_uid, null)
		if target_unit == null or target_unit.team != Constants.TEAM_ENEMY:
			return
		var from_unit: UnitState = state.units.get(from_uid, null)
		if from_unit == null or from_unit.team != Constants.TEAM_ENEMY:
			return
	StatusRules.apply_weak(state, state.units.get(str(payload.get("unit_uid", "")), null), 1, relic_id)
	state.log("[Relic] %s -> 嫁祸：对 %s 施加虚弱" % [relic_id, payload.get("unit_uid", "?")])


## random_gem_transform_one：每回合开始时随机将场上槽位内的普通宝石变为另一颗。
func _action_random_gem_transform_one(relic_id: String, state: GameState) -> void:
	var all_gem_uids: Array[String] = []
	var unit_uids: Array[String] = []
	for raw_uid in state.units.keys():
		unit_uids.append(str(raw_uid))
	unit_uids.sort()
	for unit_uid in unit_uids:
		var unit: UnitState = state.units.get(unit_uid, null)
		if unit == null or not unit.alive:
			continue
		for slot: SlotState in unit.slots:
			if slot == null or slot.gem_uid.is_empty():
				continue
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem == null or gem.gem_id == Constants.GEM_COUNTERFEIT:
				continue
			# 过载残响与赝品都是带有独立生命周期的临时占位物，
			# 不能被普通宝石的随机变换打断清理与解锁。
			if state.overload_echo_gems.has(gem.uid):
				continue
			all_gem_uids.append(gem.uid)
	if all_gem_uids.is_empty():
		return
	var idx: int = RngService.roll_int("mini_casino_pick_%s_%d" % [relic_id, state.turn_index], 0, all_gem_uids.size() - 1)
	var target_uid: String = all_gem_uids[idx]
	var target_gem: GemState = state.gems.get(target_uid, null)
	if target_gem == null:
		return
	var old_id := target_gem.gem_id
	var new_id := DataRegistry.roll_spawnable_gem_id(
		"mini_casino_roll_%s_%d" % [relic_id, state.turn_index], [], "global", 99, [old_id]
	)
	if new_id.is_empty():
		return
	target_gem.gem_id = new_id
	target_gem.def_overrides = {}
	state.log("[Relic] %s -> 微型赌场：%s 变为 %s" % [relic_id, old_id, new_id])


# ─── Modifier 求值 ────────────────────────────────────────────────────────────

func _eval_modifier_entry(relic_id: String, effect: Dictionary, state: GameState, ctx: Dictionary) -> Variant:
	var modifier_id: String = str(effect.get("modifier", ""))
	if modifier_id == "manual_shot_damage_bonus":
		return _SimpleRelicEffects.manual_shot_damage_bonus(effect, state, ctx)

	# 首次伤害吸收
	if modifier_id == "first_damage_absorb":
		var flag: String = str(effect.get("flag", "painkiller_%s_used" % relic_id))
		if state.battle_temp_flags.has(flag):
			return false
		return true

	# 混沌发射器激活（bool）
	if modifier_id == "chaos_launcher_active":
		return bool(effect.get("value", false))

	# 空槽倍数：每个空槽额外乘以 (1 + factor)，基础值 1.0
	if effect.has("empty_slot_mult") or effect.has("empty_slot_mult_ref"):
		var factor := _resolve_number(effect, "empty_slot_mult", 0.0)
		var player := state.get_player()
		var empty_count := 0
		if player != null:
			for slot in player.slots:
				if slot.gem_uid.is_empty():
					empty_count += 1
		return 1.0 + factor * float(empty_count)

	# 每个空槽加成（extract/insert range）
	if effect.has("per_empty_slot") or effect.has("per_empty_slot_ref"):
		var per := int(_resolve_number(effect, "per_empty_slot", 1.0))
		var player := state.get_player()
		var empty_count := 0
		if player != null:
			for slot in player.slots:
				if slot.gem_uid.is_empty():
					empty_count += 1
		return per * empty_count

	# 覆盖层移动消耗减少：需要 ctx.overlay_type 匹配
	if modifier_id == "overlay_move_cost_reduction":
		var overlays: Array = effect.get("overlays", [])
		var ctx_overlay: String = str(ctx.get("overlay_type", ""))
		if ctx_overlay.is_empty() or not (ctx_overlay in overlays):
			return 0
		return int(_resolve_number(effect, "value", 1.0))

	# 概率触发加成
	if effect.has("rng_chance") or effect.has("rng_chance_ref"):
		var chance := _resolve_number(effect, "rng_chance", 0.0)
		var roll: float = float(RngService.roll_int("rng_chance_%s" % relic_id, 0, 999)) / 1000.0
		if roll < chance:
			return _resolve_number(effect, "value", 0.0)
		return 0

	# condition 前置检查
	var cond: String = str(effect.get("condition", ""))
	if not cond.is_empty():
		if not _check_modifier_condition(cond, state):
			if modifier_id.ends_with("_mult"):
				return 1.0
			elif modifier_id.ends_with("_immune") or modifier_id == "first_damage_absorb":
				return false
			else:
				return 0

	var val: Variant = _resolve_number(effect, "value", 0.0)
	return val


## modifier condition 求值
func _check_modifier_condition(condition: String, state: GameState) -> bool:
	match condition:
		"has_gem_split":
			var player := state.get_player()
			if player == null:
				return false
			for slot in player.slots:
				if not slot.gem_uid.is_empty():
					var gem: GemState = state.gems.get(slot.gem_uid, null)
					if gem != null and gem.gem_id == Constants.GEM_SPLIT:
						return true
			return false
		"player_hp_low":
			var player := state.get_player()
			if player == null:
				return false
			return float(player.hp) / float(maxi(player.max_hp, 1)) < 0.3
		_:
			return true


## 检查是否是黑槽宝石导致的死亡（unit_die payload 中的 reason 含 black gem 相关原因）
func _check_black_gem_kill(state: GameState, payload: Dictionary) -> bool:
	var reason: String = str(payload.get("reason", ""))
	var black_reasons := ["explosion", "explosion_cross", "explosion_death", "poison", "arc", "fire", "ice_death"]
	for r in black_reasons:
		if reason.contains(r):
			return true
	# 检查击杀单位是否使用了黑色槽宝石
	var killer_uid: String = str(payload.get("killer_uid", ""))
	if killer_uid == state.player_uid:
		var player := state.get_player()
		if player != null:
			for slot in player.slots:
				if slot.slot_type == Constants.SLOT_BLACK and not slot.gem_uid.is_empty():
					return true
	return false


# ─── 工具 ────────────────────────────────────────────────────────────────────

func _resolve_target(effect: Dictionary, state: GameState, payload: Dictionary = {}) -> UnitState:
	var target: String = str(effect.get("target", "player"))
	match target:
		"player":
			return state.get_player()
		"payload_from_uid":
			return state.units.get(str(payload.get("from_uid", "")), null)
		_:
			return state.units.get(target, null)


func _resolve_amount(effect: Dictionary, fallback: int = 1) -> int:
	return int(_resolve_number(effect, "amount", float(fallback)))


func _resolve_number(effect: Dictionary, field_id: String, fallback: float = 0.0) -> float:
	var ref_key := "%s_ref" % field_id
	if effect.has(ref_key):
		return DataRegistry.get_relic_numeric_ref(str(effect.get(ref_key, "")), fallback)
	return float(effect.get(field_id, fallback))


func _register_builtin_actions() -> void:
	pass
