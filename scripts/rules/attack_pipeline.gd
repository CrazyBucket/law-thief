class_name AttackPipeline
extends RefCounted

const _ContactResolver = preload("res://scripts/rules/contact_resolver.gd")
const _Displacement = preload("res://scripts/rules/displacement.gd")
const GemEffectsScript = preload("res://scripts/rules/gem_effects.gd")

# ─── 攻击标签集合 ────────────────────────────────────────────────────────────
# 标签用于各阶段之间传递语义，宝石/规则通过检查/追加标签影响流程
const TAG_RANGED       := "ranged"        # 远程攻击
const TAG_MELEE        := "melee"         # 近战攻击
const TAG_EXPLOSIVE    := "explosive"     # 附带爆炸
const TAG_KNOCKBACK    := "knockback"     # 附带击退
const TAG_PULL         := "pull"          # 攻击后拉扯目标靠近
const TAG_DEFLECT      := "deflect"       # 受到远程攻击时偏转投射物
const TAG_DEFLECT_DONE := "deflect_done"  # 投射物偏转到地块，跳过后续伤害
const TAG_POISON       := "poison"        # 附带中毒
const TAG_POISON_FOG   := "poison_fog"    # 命中点生成毒雾
const TAG_ARC          := "arc"           # 电弧弹射
const TAG_FIRE_ON_HIT  := "fire_on_hit"   # 命中附着火
const TAG_SLOW_ON_HIT  := "slow_on_hit"   # 命中附缓速/冻结
const TAG_FORCED_MOVE  := "forced_move"   # 强制位移类来源（引力、击退等）
const TAG_PIERCING     := "piercing"      # 穿甲
const TAG_NO_KILL_PROC := "no_kill_proc"  # 击杀后不触发死亡效果
const TAG_SPLIT_SHOT   := "split_shot"    # V字三发（分裂宝石红槽）


# ─── 攻击上下文 ──────────────────────────────────────────────────────────────
class AttackContext:
	var state: GameState
	var attacker: UnitState
	var target: UnitState

	## 标签集合：各阶段通过 add_tag / has_tag 通信
	var tags: Array[String] = []

	## OnDamageCalculate 阶段写入最终伤害
	var base_damage: int = 0
	var final_damage: int = 0

	## 事件列表：各阶段 append，最终由 UI 层消费
	var events: Array[Dictionary] = []

	## 额外 payload，供宝石/规则挂钩任意写入
	var payload: Dictionary = {}

	func _init(p_state: GameState, p_attacker: UnitState, p_target: UnitState) -> void:
		state    = p_state
		attacker = p_attacker
		target   = p_target

	func add_tag(tag: String) -> void:
		if tag not in tags:
			tags.append(tag)

	func has_tag(tag: String) -> bool:
		return tag in tags

	func remove_tag(tag: String) -> void:
		tags.erase(tag)

	func push_event(ev: Dictionary) -> void:
		events.append(ev)

	func push_damage_event(pos: Vector2i, damage: int, is_crit: bool = false) -> void:
		events.append({"type": "damage", "pos": pos, "damage": damage, "is_crit": is_crit})

	func push_move_event(uid: String, from: Vector2i, to: Vector2i) -> void:
		events.append({"type": "move_step", "uid": uid, "from": from, "to": to})

	func push_explode_event(pos: Vector2i, radius: int) -> void:
		events.append({"type": "explode", "pos": pos, "radius": radius})


# ─── Pipeline 入口 ──────────────────────────────────────────────────────────

## 执行完整攻击 pipeline，返回 {ok, reason, events}
static func execute(
	state: GameState,
	attacker: UnitState,
	target: UnitState,
	initial_tags: Array[String] = [],
	payload: Dictionary = {}
) -> Dictionary:
	if not attacker.alive or not target.alive:
		return _fail("目标或攻击者无效")

	var ctx := AttackContext.new(state, attacker, target)
	ctx.payload = payload.duplicate()
	for tag in initial_tags:
		ctx.add_tag(tag)

	if ctx.has_tag(TAG_MELEE) and not BoardUtils.are_units_adjacent(attacker, target):
		return _fail("近战目标不在相邻格")

	# 阶段 1：准备（修改范围、追加标签）
	state.on_attack_prepare.emit(attacker.uid, target.uid, ctx.tags.duplicate())
	_phase_prepare(ctx)
	if not ctx.target.alive:
		return _ok(ctx.events)

	# 偷跑：目标蓝槽引力宝石对远程投射物做偏转（在伤害计算前介入）
	if ctx.has_tag(TAG_RANGED):
		_try_deflect(ctx)
	if ctx.has_tag(TAG_DEFLECT_DONE):
		return _ok(ctx.events)

	# 阶段 2：伤害计算（暴击、护甲抵扣）
	_phase_damage_calculate(ctx)

	# 阶段 3：命中（真正扣血、附着效果）
	_phase_hit(ctx)

	# 阶段 4：攻击后/击杀后结算
	_phase_post_attack(ctx)

	return _ok(ctx.events)


# ─── 阶段实现 ────────────────────────────────────────────────────────────────

static func _phase_prepare(ctx: AttackContext) -> void:
	_gem_hooks_prepare(ctx)


static func _phase_damage_calculate(ctx: AttackContext) -> void:
	ctx.base_damage = CombatRules.attack_damage(ctx.state, ctx.attacker)
	var charge_bonus: int = int(ctx.payload.get("charge_bonus", 0))
	if charge_bonus > 0:
		ctx.base_damage += charge_bonus
	var bonus_damage: int = int(ctx.payload.get("bonus_damage", 0))
	if bonus_damage > 0:
		ctx.base_damage += bonus_damage
	if ctx.has_tag(TAG_SPLIT_SHOT):
		ctx.base_damage = maxi(1, int(ctx.base_damage * Constants.SPLIT_ATTACK_DAMAGE_RATIO))
	# 护甲抵扣由 CombatRules.apply_damage 统一处理；
	# 此处仅预估 final_damage 供后续阶段判断是否触发附加效果
	var armor := CombatRules.current_armor(ctx.state, ctx.target)
	if ctx.has_tag(TAG_PIERCING):
		armor = 0
	ctx.final_damage = maxi(0, ctx.base_damage - armor)


static func _phase_hit(ctx: AttackContext) -> void:
	if ctx.payload.get("force_miss", false):
		ctx.state.log("%s 的攻击未命中 %s" % [ctx.attacker.uid, ctx.target.uid])
		ctx.push_event({"type": "miss", "pos": ctx.target.pos, "attacker_uid": ctx.attacker.uid})
		return
	var reason: String = str(ctx.payload.get("damage_reason", ""))
	if reason.is_empty():
		if ctx.has_tag(TAG_RANGED):
			reason = "ranged_attack"
		elif ctx.has_tag(TAG_MELEE):
			reason = "melee_attack"
		else:
			reason = "attack"
	var dealt := CombatRules.apply_damage(ctx.state, ctx.target, ctx.base_damage, ctx.attacker.uid, reason)
	if dealt > 0:
		ctx.push_damage_event(ctx.target.pos, dealt)
		ctx.state.on_attack_hit.emit(ctx.attacker.uid, ctx.target.uid, dealt)
	elif not ctx.has_tag(TAG_EXPLOSIVE):
		return  # 护甲全吸收且无附带爆炸，直接结束

	# 命中瞬间：接触钩子（攻击/被攻击）
	_ContactResolver.on_attack_contact(ctx.state, ctx.attacker, ctx.target)

	# 命中瞬间：宝石附着效果（中毒等）
	_gem_hooks_on_hit(ctx)

	# 击退：非爆炸宝石近战才推离主目标；爆炸宝石仅震开十字四邻
	if ctx.has_tag(TAG_KNOCKBACK) and not ctx.has_tag(TAG_EXPLOSIVE) and ctx.target.alive:
		_Displacement.knockback(ctx.state, ctx.target, ctx.attacker.pos, 1, ctx.attacker.uid, ctx.events)

	if ctx.has_tag(TAG_EXPLOSIVE):
		_apply_cross_explosion(ctx)

	# 毒雾：命中点生成毒雾
	if ctx.has_tag(TAG_POISON_FOG):
		TileRules.create_poison_fog(ctx.state, ctx.target.pos)

	# 着火：命中附着火
	if ctx.has_tag(TAG_FIRE_ON_HIT) and ctx.target.alive:
		StatusRules.apply_burning(ctx.state, ctx.target, 1, ctx.attacker.uid)

	# 冰冻/缓速：命中附缓速，潮湿单位直接冻结（麻痹+缓速）
	if ctx.has_tag(TAG_SLOW_ON_HIT) and ctx.target.alive:
		GemEffects.apply_ice_hit_effect(ctx.state, ctx.target, ctx.attacker.uid)

	# 红槽导电：命中水域则水域导电；否则被击者 2 格内弹射 1 次
	if ctx.has_tag(TAG_ARC):
		var hit_tile := ctx.state.get_tile(ctx.target.pos)
		if hit_tile != null and hit_tile.has_tile_tag(Constants.TAG_TILE_WATER):
			GemEffects.apply_water_conduction(ctx.state, ctx.target.pos, ctx.attacker, ctx.events)
		elif ctx.target.alive:
			GemEffects.apply_arc_bounce_from_victim(
				ctx.state, ctx.target, ctx.attacker, ctx.base_damage, ctx.events
			)


static func _phase_post_attack(ctx: AttackContext) -> void:
	var killed := not ctx.target.alive

	# 红槽引力宝石：攻击后将目标拉近 1 格（目标存活时才拉扯）
	if ctx.has_tag(TAG_PULL) and not killed:
		_Displacement.pull_toward(ctx.state, ctx.target, ctx.attacker.pos, 1, ctx.attacker.uid, ctx.events)

	# 分裂宝石红槽：V字两翼追加伤害
	if ctx.has_tag(TAG_SPLIT_SHOT):
		_apply_split_wings(ctx)

	if killed and not ctx.has_tag(TAG_NO_KILL_PROC):
		_gem_hooks_on_kill(ctx)


# ─── 宝石挂钩 ─────────────────────────────────────────────────────────────

static func _gem_hooks_prepare(ctx: AttackContext) -> void:
	for slot in ctx.attacker.slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		match slot.slot_type:
			Constants.SLOT_RED:
				match _ability_profile(gem, GemEffects.ABILITY_UNIT_RED_ACTIVE):
					"explosion":
						ctx.add_tag(TAG_EXPLOSIVE)
					"gravity":
						ctx.add_tag(TAG_PULL)
					"poison":
						ctx.add_tag(TAG_POISON_FOG)
					"arc":
						ctx.add_tag(TAG_ARC)
					"fire_gem":
						ctx.add_tag(TAG_FIRE_ON_HIT)
					"ice":
						ctx.add_tag(TAG_SLOW_ON_HIT)
					"split":
						ctx.add_tag(TAG_SPLIT_SHOT)


## 偏转检测：目标蓝槽引力宝石将远程攻击偏转到周围随机单位；无单位则落地
static func _try_deflect(ctx: AttackContext) -> void:
	for slot in ctx.target.slots:
		if slot.slot_type != Constants.SLOT_BLUE or slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctx.state.gems.get(slot.gem_uid, null)
		if gem == null:
			continue
		if _ability_profile(gem, GemEffects.ABILITY_BLUE_DAMAGED) != "gravity":
			continue
		# 收集周围可命中的单位（排除攻击者本人）
		var candidates: Array[UnitState] = []
		for neighbor in BoardUtils.neighbors4(ctx.target.pos):
			var hit := ctx.state.get_unit_at(neighbor)
			if hit != null and hit.alive and hit.uid != ctx.attacker.uid:
				candidates.append(hit)
		if candidates.is_empty():
			# 无单位：投射物落地在随机邻格，不造成伤害
			var neighbors := BoardUtils.neighbors4(ctx.target.pos)
			var land: Vector2i = neighbors[randi() % neighbors.size()]
			ctx.state.log("%s 被引力偏转，投射物落地 %s" % [ctx.target.uid, land])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": land})
			ctx.add_tag(TAG_DEFLECT_DONE)
		else:
			# 有单位：投射物转向随机一个，继续走 pipeline
			var new_target: UnitState = candidates[randi() % candidates.size()]
			ctx.state.log("%s 被引力偏转，投射物转向 %s" % [ctx.target.uid, new_target.uid])
			ctx.push_event({"type": "projectile_deflect", "from": ctx.target.pos, "to": new_target.pos})
			ctx.target = new_target
		break


static func _gem_hooks_on_hit(ctx: AttackContext) -> void:
	if ctx.has_tag(TAG_POISON) and ctx.target.alive:
		StatusRules.apply_poison(ctx.state, ctx.target, 1, 0, ctx.attacker.uid)


static func _gem_hooks_on_kill(ctx: AttackContext) -> void:
	# 黑槽死亡效果由 CombatRules._kill_unit → GemEffects.on_unit_death 触发
	pass


# ─── 爆炸辅助 ────────────────────────────────────────────────────────────

static func _apply_cross_explosion(ctx: AttackContext) -> void:
	var cross_events := GemEffectsScript.explode_cross_at(
		ctx.state,
		ctx.target.pos,
		ctx.attacker.uid,
		0,
		Constants.EXPLOSION_CROSS_DAMAGE,
		false
	)
	for ev in cross_events:
		ctx.events.append(ev)


# ─── 内部工具 ────────────────────────────────────────────────────────────

## V字两翼：以攻击方向的垂直方向各偏一格，在中心弹射程-1处各打一发
static func _apply_split_wings(ctx: AttackContext) -> void:
	var attacker_pos := ctx.attacker.pos
	var target_pos := ctx.target.pos
	# 计算主攻击方向（取主轴分量，等距4方向）
	var delta := target_pos - attacker_pos
	var forward: Vector2i
	if absi(delta.x) >= absi(delta.y):
		forward = Vector2i(signi(delta.x), 0)
	else:
		forward = Vector2i(0, signi(delta.y))
	# 两翼落点 = 前进(range-1)步 + 垂直方向各偏1格
	var perp := Vector2i(forward.y, -forward.x)  # 顺时针90°
	var wing_advance := Constants.ATTACK_RANGE - 1
	var wing_a := attacker_pos + forward * wing_advance + perp
	var wing_b := attacker_pos + forward * wing_advance - perp
	var wing_damage := maxi(1, int(ctx.base_damage * Constants.SPLIT_ATTACK_DAMAGE_RATIO))
	for wing_pos in [wing_a, wing_b]:
		if not BoardUtils.in_bounds(ctx.state, wing_pos):
			continue
		var wing_target := ctx.state.get_unit_at(wing_pos)
		if wing_target == null or not wing_target.alive or wing_target.uid == ctx.attacker.uid:
			continue
		var dealt := CombatRules.apply_damage(ctx.state, wing_target, wing_damage, ctx.attacker.uid, "split_wing")
		if dealt > 0:
			ctx.push_damage_event(wing_target.pos, dealt)
			ctx.state.on_attack_hit.emit(ctx.attacker.uid, wing_target.uid, dealt)


static func _ability_profile(gem: GemState, ability_slot: String) -> String:
	return _data_registry().get_gem_ability_profile(gem, ability_slot)


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


static func _ok(events: Array[Dictionary]) -> Dictionary:
	return {"ok": true, "events": events}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": [] as Array[Dictionary]}
