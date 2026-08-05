extends RefCounted


static func tutorial_hint(state: GameState) -> String:
	var mage := _find_mage(state)
	if mage == null:
		return ""
	if mage.hp < 20:
		return _translate_or("boss.old_mage.hint.low_hp", "老法师进入终局：每回合会把一个非黑槽转为黑槽，移动力固定为 2。")
	var phase := str(state.battle_temp_flags.get("old_mage:%s:phase" % mage.uid, "cast"))
	if phase == "decoy":
		return _translate_or("boss.old_mage.hint.decoy", "这颗宝石不在技能池内。老法师会销毁它并空过本回合。")
	if phase == "refill":
		return _translate_or("boss.old_mage.hint.refill", "老法师正在补充：技能池宝石会被优先锁定，锁定后目标不会因你的移动改变。")
	return _translate_or("boss.old_mage.hint.cast", "老法师正在施法：观察槽位颜色、技能、伤害与范围预警，再离开锁定区域。")


static func _find_mage(state: GameState) -> UnitState:
	for unit in state.get_alive_enemies():
		if unit.behavior_id == "old_mage":
			return unit
	return null


static func _translate_or(key: String, fallback: String) -> String:
	var translated := TranslationServer.translate(key)
	return fallback if translated == key or translated.is_empty() else translated
