class_name MetaConsoleCli
extends RefCounted

func run(raw_command: String) -> Dictionary:
	var tokens := _tokens(raw_command)
	if tokens.is_empty():
		return _fail("输入命令，例如 unlock all")
	var cmd := tokens[0].to_lower()
	match cmd:
		"help", "?":
			return _ok({
				"message": "Meta CLI",
				"lines": [
					"unlock all  — 解锁当前档案（profile.json）全部未解锁标记",
					"help        — 显示本帮助",
				],
			})
		"unlock":
			if tokens.size() < 2 or tokens[1].to_lower() != "all":
				return _fail("用法：unlock all")
			var summary: Dictionary = ProfileService.unlock_all_for_active_slot()
			return _ok({
				"message": "已解锁当前档案全部未解锁标记",
				"lines": [
					"遗物池条件 +%d" % int(summary.get("unlock_conditions", 0)),
					"遗物图鉴 +%d" % int(summary.get("seen_relics", 0)),
					"敌人图鉴 +%d" % int(summary.get("seen_enemies", 0)),
					"成就 +%d" % int(summary.get("achievements", 0)),
					"遭遇战标记 +%d" % int(summary.get("boss_flags", 0)),
				],
			})
		_:
			return _fail("未知命令：%s（输入 help）" % tokens[0])


func _tokens(raw_command: String) -> Array[String]:
	var normalized := raw_command.strip_edges().replace("\t", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	var tokens: Array[String] = []
	for token in normalized.split(" ", false):
		var value := String(token).strip_edges()
		if value.begins_with("/"):
			value = value.substr(1)
		if value.is_empty():
			continue
		tokens.append(value.to_lower())
	return tokens


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
