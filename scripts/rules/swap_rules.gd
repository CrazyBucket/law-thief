class_name SwapRules
extends RefCounted

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


static func was_used_this_turn(state: GameState) -> bool:
	return state != null and state.relic_battle.swap_used_turn == state.turn_index


static func can_activate(state: GameState) -> Dictionary:
	if state == null:
		return _fail("战斗尚未开始")
	if state.phase != Constants.PHASE_PLAYER:
		return _fail("只能在玩家回合调包")
	if was_used_this_turn(state):
		return _fail("本回合已经调包")
	var valid_count := 0
	for unit: UnitState in state.units.values():
		for slot_index in range(unit.slots.size()):
			if can_select_slot(state, unit, slot_index).get("ok", false):
				valid_count += 1
				if valid_count >= 2:
					return {"ok": true}
	return _fail("场上没有两颗可交换的宝石")


static func can_select_slot(state: GameState, unit: UnitState, slot_index: int) -> Dictionary:
	if state == null or unit == null or state.units.get(unit.uid, null) != unit:
		return _fail("目标单位无效")
	if not unit.alive:
		return _fail("不能选择已退场单位")
	var slot := unit.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	if not slot.is_operable(state.turn_index):
		return _fail("该槽位已锁定")
	if slot.gem_uid.is_empty():
		return _fail("只能选择装有宝石的槽位")
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return _fail("槽位中的宝石不存在")
	if gem.gem_id == Constants.GEM_COUNTERFEIT:
		return _fail("赝品不能调包")
	if state.overload_echo_gems.has(gem.uid):
		return _fail("过载回响不能调包")
	return {
		"ok": true,
		"unit_uid": unit.uid,
		"slot_index": slot_index,
		"gem_uid": gem.uid,
		"gem_id": gem.gem_id,
		"gem_name": _gem_name(gem),
	}


static func can_swap(
	state: GameState,
	first_unit: UnitState,
	first_index: int,
	second_unit: UnitState,
	second_index: int
) -> Dictionary:
	var activation := can_activate(state)
	if not activation.get("ok", false):
		return activation
	var first := can_select_slot(state, first_unit, first_index)
	if not first.get("ok", false):
		return _fail("第一颗宝石已失效：%s" % str(first.get("reason", "无法选择")))
	var second := can_select_slot(state, second_unit, second_index)
	if not second.get("ok", false):
		return _fail("第二颗宝石无效：%s" % str(second.get("reason", "无法选择")))
	if first_unit.uid == second_unit.uid and first_index == second_index:
		return _fail("请选择另一颗宝石")
	return {
		"ok": true,
		"first": first,
		"second": second,
	}


static func try_swap(
	state: GameState,
	first_unit: UnitState,
	first_index: int,
	second_unit: UnitState,
	second_index: int
) -> Dictionary:
	var check := can_swap(state, first_unit, first_index, second_unit, second_index)
	if not check.get("ok", false):
		return check
	var first: Dictionary = check["first"]
	var second: Dictionary = check["second"]
	if not GemTransfer.swap_unit_slots(state, first_unit, first_index, second_unit, second_index):
		return _fail("宝石交换失败")
	# 调包不是嵌入，也不能把此前的连续嵌入预兆带到下一次嵌入。
	OverloadRules.record_non_insert_action(state, Constants.ACTION_RELIC_SWAP)
	state.relic_battle.swap_used_turn = state.turn_index
	state.bump_revision()
	IntentSystem.refresh_all_intents(state)
	state.log("调包：%s ↔ %s" % [first.get("gem_name", "宝石"), second.get("gem_name", "宝石")])
	return {
		"ok": true,
		"stage": "complete",
		"first": first,
		"second": second,
	}


static func _gem_name(gem: GemState) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	return registry.get_gem_display_name(gem) if registry != null else "宝石"


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
