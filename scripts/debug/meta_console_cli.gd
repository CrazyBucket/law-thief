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
					"unlock all                       — 解锁当前档案（profile.json）全部未解锁标记",
					"pool list <source> [chapter]     — 列出指定来源 pool 的候选宝石及权重",
					"pool sources                     — 列出所有可用 pool 来源 key",
					"pool roll <source> [chapter]     — 从指定 pool 即时 roll 一颗宝石（仅预览，不入存档）",
					"help                             — 显示本帮助",
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
		"pool":
			return _run_pool_command(tokens)
		_:
			return _fail("未知命令：%s（输入 help）" % tokens[0])


func _run_pool_command(tokens: Array[String]) -> Dictionary:
	if tokens.size() < 2:
		return _fail("用法：pool list <source> [chapter] | pool sources | pool roll <source> [chapter]")
	var sub := tokens[1].to_lower()
	match sub:
		"sources":
			var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
			if registry == null:
				return _fail("DataRegistry 未就绪")
			var pool_keys: Array = []
			var raw_pools: Dictionary = registry.get("_gem_pools")
			if not raw_pools.is_empty():
				pool_keys = raw_pools.keys()
			pool_keys.sort()
			var lines: Array[String] = []
			for key in pool_keys:
				var pool_def: Dictionary = registry.get_gem_pool_def(str(key))
				lines.append("  %-20s  tier=%d" % [str(key), int(pool_def.get("source_tier", 1))])
			return _ok({"message": "可用 pool 来源", "lines": lines})
		"list":
			if tokens.size() < 3:
				return _fail("用法：pool list <source> [chapter]")
			var source := tokens[2]
			var chapter := 1
			if tokens.size() >= 4 and tokens[3].is_valid_int():
				chapter = int(tokens[3])
			var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
			if registry == null:
				return _fail("DataRegistry 未就绪")
			var candidates: Array = registry.get_gem_pool_candidates(source, chapter)
			if candidates.is_empty():
				return _ok({"message": "pool [%s] chapter=%d 无候选宝石" % [source, chapter], "lines": []})
			var lines: Array[String] = []
			var total_w := 0.0
			for entry in candidates:
				total_w += float(entry.get("weight", 0.0))
			for entry in candidates:
				var w := float(entry.get("weight", 0.0))
				var pct := (w / total_w * 100.0) if total_w > 0.0 else 0.0
				lines.append("  %-24s  tag=%-12s  rarity=%-10s  tier=%d  weight=%.1f (%.1f%%)" % [
					str(entry.get("gem_id", "")),
					str(entry.get("tag", "")),
					str(entry.get("rarity", "")),
					int(entry.get("pool_tier", 1)),
					w,
					pct,
				])
			return _ok({
				"message": "pool [%s] chapter=%d  共 %d 项" % [source, chapter, candidates.size()],
				"lines": lines,
			})
		"roll":
			if tokens.size() < 3:
				return _fail("用法：pool roll <source> [chapter]")
			var source := tokens[2]
			var chapter := 1
			if tokens.size() >= 4 and tokens[3].is_valid_int():
				chapter = int(tokens[3])
			var registry: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
			if registry == null:
				return _fail("DataRegistry 未就绪")
			var gem_id: String = str(registry.roll_spawnable_gem_id("debug_pool_preview", [], source, chapter))
			if gem_id.is_empty():
				return _ok({"message": "pool [%s] chapter=%d 无候选宝石" % [source, chapter], "lines": []})
			var tag: String = str(registry.get_gem_tag(gem_id))
			var rarity: String = str(registry.get_gem_rarity(gem_id))
			return _ok({
				"message": "pool roll 结果（仅预览）",
				"lines": [
					"  gem_id=%s  tag=%s  rarity=%s" % [gem_id, tag, rarity],
				],
			})
		_:
			return _fail("pool 子命令未知：%s（pool list / pool sources / pool roll）" % sub)


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
