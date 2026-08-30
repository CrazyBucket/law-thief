class_name EventContentRuntime
extends RefCounted

const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")

const EVENT_SCRIBE := "event_misaccounting_scribe"
const EVENT_FURNACE := "event_sealed_gem_furnace"
const EVENT_INJURY := "event_injury_appraisal"
const EVENT_AUCTION := "event_counterfeit_auction"
const EVENT_EXECUTION := "event_preliminary_execution_order"
const EVENT_REFINER := "event_slag_refiner"
const EVENT_REFORGE := "event_unlicensed_reforge"
const EVENT_ANESTHETIST := "event_alley_anesthetist"
const EVENT_CABINET := "event_evidence_cabinet"

const EVENT_IDS: Array[String] = [
	EVENT_SCRIBE,
	EVENT_FURNACE,
	EVENT_INJURY,
	EVENT_AUCTION,
	EVENT_EXECUTION,
	EVENT_REFINER,
	EVENT_REFORGE,
	EVENT_ANESTHETIST,
	EVENT_CABINET,
]


static func handles(event_id: String) -> bool:
	return event_id in EVENT_IDS


static func resolve_event_id(room_id: String, assigned_event_id: String) -> String:
	if not handles(assigned_event_id):
		return assigned_event_id
	if handles(assigned_event_id) and _is_available(assigned_event_id, room_id):
		return assigned_event_id
	var candidates: Array[String] = []
	for event_id in EVENT_IDS:
		if _is_available(event_id, room_id):
			candidates.append(event_id)
	if candidates.is_empty():
		return assigned_event_id
	var rng := _room_rng(room_id, "event_reroute")
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func record_encounter(event_id: String) -> void:
	var run := RunService.get_run()
	if run == null or not handles(event_id):
		return
	var occurrences: Dictionary = run.run_stats.get("event_occurrences", {}).duplicate(true)
	var chapter := RunService.get_current_chapter()
	occurrences["run:%s" % event_id] = int(occurrences.get("run:%s" % event_id, 0)) + 1
	occurrences["chapter:%d:%s" % [chapter, event_id]] = int(
		occurrences.get("chapter:%d:%s" % [chapter, event_id], 0)
	) + 1
	run.run_stats["event_occurrences"] = occurrences
	RunService.save_run(false)


static func prepare(room_id: String, event_state: Dictionary) -> Dictionary:
	if bool(event_state.get("runtime_prepared", false)):
		return event_state
	var state := event_state.duplicate(true)
	var event_id := str(state.get("event_id", ""))
	var chapter := RunService.get_current_chapter()
	var rng := _room_rng(room_id, event_id)
	var data := {}
	match event_id:
		EVENT_SCRIBE:
			var small_range := _chapter_range(chapter, [[35, 55], [50, 80], [80, 120]])
			var large_range := _chapter_range(chapter, [[70, 100], [100, 140], [130, 180]])
			data = {
				"small_success": rng.randf() < 0.75,
				"small_gold": rng.randi_range(small_range[0], small_range[1]),
				"large_success": rng.randf() < 0.55,
				"large_gold": rng.randi_range(large_range[0], large_range[1]),
			}
			var gems := _destructible_gems("")
			if not gems.is_empty():
				data["large_destroy_locator"] = str(gems[rng.randi_range(0, gems.size() - 1)].get("locator", ""))
		EVENT_FURNACE:
			data = {
				"queue": _roll_gems(rng, 3, {"common": 55.0, "uncommon": 35.0, "rare": 10.0} if chapter == 2 else {"common": 25.0, "uncommon": 50.0, "rare": 25.0}, chapter),
				"queue_index": 0,
			}
		EVENT_INJURY:
			var blood_range := _chapter_range(chapter, [[45, 65], [65, 90], [90, 130]])
			data = {"blood_gold": rng.randi_range(blood_range[0], blood_range[1])}
		EVENT_AUCTION:
			var safe_price_range := [80, 110] if chapter == 2 else [60, 90]
			var risky_price_range := [100, 140] if chapter == 2 else [70, 110]
			var safe_real := rng.randf() < 0.80
			var risky_real := rng.randf() < 0.55
			var safe_relic := _roll_relic(rng, "common") if safe_real else "relic_placeholder"
			var risky_relic := _roll_relic(rng, "rare") if risky_real else "relic_placeholder"
			if safe_relic == "relic_placeholder":
				safe_real = false
			if risky_relic == "relic_placeholder":
				risky_real = false
			data = {
				"safe_price": rng.randi_range(safe_price_range[0], safe_price_range[1]),
				"safe_real": safe_real,
				"safe_relic": safe_relic,
				"risky_price": rng.randi_range(risky_price_range[0], risky_price_range[1]),
				"risky_real": risky_real,
				"risky_relic": risky_relic,
			}
		EVENT_EXECUTION:
			var payout_range := [70, 100] if chapter == 1 else [100, 140]
			data = {"payout": rng.randi_range(payout_range[0], payout_range[1])}
		EVENT_ANESTHETIST:
			data = {
				"first_success": rng.randf() < 0.65,
				"second_success": rng.randf() < 0.45,
			}
		EVENT_CABINET:
			data = {
				"gray": _roll_gems(rng, 3, {"common": 100.0}, chapter),
				"blue": _roll_gems(rng, 2, {"uncommon": 70.0, "rare": 30.0}, chapter),
				"black": _roll_gems(rng, 2, {"rare": 100.0}, chapter),
			}
	state["runtime_prepared"] = true
	state["phase"] = "start"
	state["data"] = data
	return state


static func get_event_view(room_id: String, event_state: Dictionary) -> Dictionary:
	var event_id := str(event_state.get("event_id", ""))
	var phase := str(event_state.get("phase", "start"))
	var view := {
		"ok": true,
		"room_id": room_id,
		"event_id": event_id,
		"node_id": phase,
		"resolved": false,
		"title": _event_title(event_id),
		"body": "",
		"options": [],
		"artwork_key": "%s_%s" % [event_id, phase],
	}
	if phase == "place_gem":
		return _gem_placement_view(view, event_state)
	if event_id == EVENT_REFINER and phase == "gem_select":
		return _refiner_gem_selection_view(view, event_state)
	if event_id == EVENT_REFINER and phase == "gem_reward":
		return _gem_reward_view(view, event_state, "熔炉吐出两颗仍在发光的结晶，热浪把旧封条卷成灰。\n\n它们都能改变你的构筑，但你只能带走一颗。")
	if event_id == EVENT_REFORGE and phase == "relic_select":
		return _relic_selection_view(view, event_state)
	if event_id == EVENT_REFORGE and phase == "relic_reward":
		return _relic_reward_view(view, event_state)
	match event_id:
		EVENT_SCRIBE:
			return _scribe_view(view)
		EVENT_FURNACE:
			return _furnace_view(view, event_state)
		EVENT_INJURY:
			return _injury_view(view, event_state)
		EVENT_AUCTION:
			return _auction_view(view, event_state)
		EVENT_EXECUTION:
			return _execution_view(view, event_state)
		EVENT_REFINER:
			return _refiner_view(view)
		EVENT_REFORGE:
			return _reforge_view(view)
		EVENT_ANESTHETIST:
			return _anesthetist_view(view, event_state)
		EVENT_CABINET:
			if phase == "gem_reward":
				return _gem_reward_view(view, event_state, "柜门弹开，证物投影依次亮起。不同颜色的宝石在玻璃后彼此呼应。\n\n选定一颗后，其余候选会随锁门一起消失。")
			return _cabinet_view(view)
	return view


static func choose_option(room_id: String, event_state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	var state := event_state.duplicate(true)
	var event_id := str(state.get("event_id", ""))
	var phase := str(state.get("phase", "start"))
	if phase == "place_gem":
		return _choose_gem_placement(state, option_id)
	if event_id == EVENT_REFINER and phase == "gem_select":
		return _choose_refiner_gem(state, option_id, room_id)
	if event_id in [EVENT_REFINER, EVENT_CABINET] and phase == "gem_reward":
		return _choose_gem_reward(state, option_id)
	if event_id == EVENT_REFORGE and phase == "relic_select":
		return _choose_relic_sacrifice(state, option_id, room_id)
	if event_id == EVENT_REFORGE and phase == "relic_reward":
		return _choose_relic_reward(state, option_id)
	match event_id:
		EVENT_SCRIBE:
			return _choose_scribe(state, option_id, transaction_id)
		EVENT_FURNACE:
			return _choose_furnace(state, option_id, transaction_id)
		EVENT_INJURY:
			return _choose_injury(state, option_id, transaction_id)
		EVENT_AUCTION:
			return _choose_auction(state, option_id, transaction_id)
		EVENT_EXECUTION:
			return _choose_execution(state, option_id, transaction_id)
		EVENT_REFINER:
			return _choose_refiner_start(state, option_id)
		EVENT_REFORGE:
			return _choose_reforge_start(state, option_id)
		EVENT_ANESTHETIST:
			return _choose_anesthetist(state, option_id)
		EVENT_CABINET:
			return _choose_cabinet(state, option_id, transaction_id)
	return _failure("unsupported_runtime_event")


static func _scribe_view(view: Dictionary) -> Dictionary:
	var chapter := RunService.get_current_chapter()
	var small_damage: int = [7, 8, 9][chapter - 1]
	var small_ranges := [[35, 55], [50, 80], [80, 120]]
	var large_ranges := [[70, 100], [100, 140], [130, 180]]
	view["body"] = "阴暗的据点废墟里，一名戴着老花镜的破产抄写员正在翻看查封账册。\n\n他压低声音向你示意：只要润笔费到位，他能在废土治安官的追缴清单上把你的名字涂掉。"
	view["options"] = [
		_option("small", "改一行：75%% 获得 %d～%d 金币；25%% 失去 %d HP" % [small_ranges[chapter - 1][0], small_ranges[chapter - 1][1], small_damage]),
	]
	if not _destructible_gems("").is_empty():
		view["options"].append(_option("large", "重写整页：55%% 获得 %d～%d 金币；45%% 随机销毁 1 颗宝石" % [large_ranges[chapter - 1][0], large_ranges[chapter - 1][1]]))
	view["options"].append(_option("leave", "离开"))
	return view


static func _furnace_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var data: Dictionary = state.get("data", {})
	var queue: Array = data.get("queue", [])
	var index := int(data.get("queue_index", 0))
	var gem_id := str(queue[index]) if index >= 0 and index < queue.size() else ""
	var chapter := RunService.get_current_chapter()
	var damage := 8 if chapter == 2 else 9
	var has_crowbar := RunService.has_relic("relic_crowbar")
	view["body"] = "这座大型熔炉贴满了警示符章与废弃封条。\n\n密封玻璃罩后，三颗散发着剧烈能量波动的高阶宝石正按顺序搁置在退火轨道上。\n\n观察窗当前露出【%s】；你可以取走它，或花钱让炉膛继续转动。" % DataRegistry.get_gem_display_name(gem_id)
	view["options"] = [
		_option("take", "撬开封条，获得当前宝石" if has_crowbar else "徒手取石：失去 %d HP，获得当前宝石" % damage),
	]
	if index < queue.size() - 1:
		var costs := [20, 40] if chapter == 2 else [25, 50]
		var cost: int = costs[index]
		view["options"].append(_option("turn", "支付 %d 金币，放弃当前宝石并转动嵌炉" % cost, RunService.get_balance("gold") >= cost, "金币不足"))
	view["options"].append(_option("leave", "离开"))
	return view


static func _injury_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var chapter := RunService.get_current_chapter()
	var snapshot := RunService.get_player_run_snapshot()
	var hp := int(snapshot.get("hp", 0))
	var max_hp := maxi(1, int(snapshot.get("max_hp", 1)))
	var ratio := float(hp) / float(max_hp)
	var data: Dictionary = state.get("data", {})
	var damages := [8, 9, 10]
	var costs := [30, 45, 60]
	var heals := [16, 20, 24]
	view["body"] = "这家黑诊所里飘着消毒水与陈腐血腥的恶臭。\n\n戴防毒面具的黑医生靠在锈斑解剖台旁，机械义眼剧烈咔哒聚焦。这里的逻辑简单粗暴：活人鲜血是合成药剂的原料，而伤口不过是待价而沽的商品。\n\n你可以拧干血管换成硬币，或者花钱让他用劣质镇痛剂与粗线强行缝补你的破烂躯体。"
	view["options"] = [
		_option("sell_blood", "出售血样：失去 %d HP，获得 %d 金币" % [damages[chapter - 1], int(data.get("blood_gold", 0))], ratio >= 0.60, "当前生命需达到 60%"),
	]
	var run := RunService.get_run()
	var relief_claimed := run != null and bool(run.run_stats.get("injury_relief_claimed", false))
	if ratio < 0.30 and not relief_claimed:
		view["options"].append(_option("relief", "申领救济：免费恢复 %d HP" % [10, 12, 15][chapter - 1]))
	else:
		view["options"].append(_option("treatment", "支付 %d 金币，恢复 %d HP" % [costs[chapter - 1], heals[chapter - 1]], RunService.get_balance("gold") >= costs[chapter - 1], "金币不足"))
	view["options"].append(_option("leave", "离开"))
	return view


static func _auction_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var data: Dictionary = state.get("data", {})
	var can_identify := RunService.has_relic("relic_vernier_caliper")
	view["body"] = "黑市地下室里正聚集着一群不怀好意的拾荒者。\n\n台上的拍卖师展示着两件盖着厚重防尘布的战遗物品，谁也不知道里面是神器还是废铁。"
	var safe_truth := "（%s）" % ("真品" if bool(data.get("safe_real", false)) else "赝品") if can_identify else ""
	var risky_truth := "（%s）" % ("真品" if bool(data.get("risky_real", false)) else "赝品") if can_identify else ""
	var safe_price := int(data.get("safe_price", 0))
	var risky_price := int(data.get("risky_price", 0))
	view["options"] = [
		_option("buy_safe", "稳妥拍品%s：支付 %d 金币（80%% 真品）" % [safe_truth, safe_price], RunService.get_balance("gold") >= safe_price, "金币不足"),
		_option("buy_risky", "冒险拍品%s：支付 %d 金币（55%% 真品）" % [risky_truth, risky_price], RunService.get_balance("gold") >= risky_price, "金币不足"),
		_option("leave", "离开"),
	]
	return view


static func _execution_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var payout := int((state.get("data", {}) as Dictionary).get("payout", 0))
	view["body"] = "一名身穿外骨骼战甲的赏金执行官拦住了你的去路。\n\n他抛给你一袋预付预支的现款：现在拿钱活命，但接下来两场战斗的斩首赏金必须全额归他。\n\n签字后，你将领取 %d 金币。" % payout
	view["options"] = [
		_option("sign", "签字领取 %d 金币" % payout),
		_option("tear", "撕毁执行令"),
	]
	return view


static func _refiner_view(view: Dictionary) -> Dictionary:
	var common_count := _destructible_gems("common").size()
	view["body"] = "轰鸣的工业废渣提纯终端仍在超载运转。\n\n只要将低阶结晶扔进高压熔炉中，强烈的粒子辐照就能将其提纯为高纯度的战术结晶。\n\n稳定档需要两颗祭品，超压档只要一颗，但失败时坩埚会连灰都不剩。"
	view["options"] = [
		_option("stable", "稳定提纯：指定销毁 2 颗普通宝石，随后二选一", common_count >= 2, "普通宝石不足"),
		_option("overpressure", "超压提纯：指定销毁 1 颗普通宝石；45% 获得稀有宝石", common_count >= 1, "没有可用的普通宝石"),
		_option("leave", "离开"),
	]
	return view


static func _reforge_view(view: Dictionary) -> Dictionary:
	var common_relics := _owned_relics_of_rarity("common")
	var rare_relics := _owned_relics_of_rarity("rare")
	var common_pool := _relic_candidates("common")
	var rare_pool := _relic_candidates("rare")
	view["body"] = "一台由旧时代3D打印机与高频切削刃拼凑出来的重铸装置。\n\n它的安全阀已被拆除，投入一件遗物，强行高热分子重组，能随机重铸出同等稀有度的崭新遗物。\n\n普通遗物会盲抽替换，稀有遗物则给你三件候选；BOSS 遗物不在这张桌上。"
	view["options"] = [
		_option("common", "重铸普通遗物：指定销毁 1 件，随机获得 1 件普通遗物", not common_relics.is_empty() and not common_pool.is_empty(), "没有可重铸的普通遗物或结果"),
		_option("rare", "重铸稀有遗物：指定销毁 1 件，从 3 件稀有遗物中选择 1 件", not rare_relics.is_empty() and not rare_pool.is_empty(), "没有可重铸的稀有遗物或结果"),
		_option("leave", "离开"),
	]
	return view


static func _anesthetist_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", "start"))
	var hp := int(RunService.get_player_run_snapshot().get("hp", 0))
	if phase == "second":
		view["body"] = "第一针的药效已经落定，麻醉师把第二支针剂推到灯下。\n\n它能让你恢复更多生命，但失败的沉淀也会更重；现在停手，至少还能带着现状离开。"
		view["options"] = [
			_option("second", "注射第二针：45% 恢复 18 HP；55% 失去 8 HP", hp >= 9, "当前生命至少需要 9"),
			_option("stop", "到此为止"),
		]
	else:
		view["body"] = "恶臭巷口里站着一名推着违禁药品的流浪麻醉师。\n\n他手里拿着两支没有任何标签的试剂针，冷笑着告诉你：结局早在你踏入这堵墙时就已经决定了。\n\n第一针可能止住疼痛，也可能让伤口裂开；如果你继续，第二针会更强，也更危险。"
		view["options"] = [
			_option("first", "注射第一针：65% 恢复 12 HP；35% 失去 7 HP", hp >= 8, "当前生命至少需要 8"),
			_option("leave", "离开"),
		]
	return view


static func _cabinet_view(view: Dictionary) -> Dictionary:
	var chapter := RunService.get_current_chapter()
	var gold := RunService.get_balance("gold")
	view["body"] = "旧时代废弃治安局的地下保管库里，矗立着一座高耸的重型三级证物柜。\n\n灰、蓝、黑三层防护锁对应着不同规格的解锁开锁成本，以及截然不同的风险奖池。\n\n你只能打开其中一层；锁扣一旦弹开，其余抽屉会同时封死。"
	view["options"] = [
		_option("open_gray", "灰色抽屉：支付 20 金币，普通宝石三选一", gold >= 20, "金币不足"),
	]
	if chapter >= 2:
		view["options"].append(_option("open_blue", "蓝色抽屉：支付 45 金币，非普通/稀有宝石二选一", gold >= 45, "金币不足"))
	if chapter >= 3:
		view["options"].append(_option("open_black", "黑色抽屉：支付 75 金币，稀有宝石二选一", gold >= 75, "金币不足"))
	view["options"].append(_option("leave", "离开"))
	return view


static func _refiner_gem_selection_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var data: Dictionary = state.get("data", {})
	var selected: Array = data.get("selected_gems", [])
	var required := int(data.get("required_gems", 1))
	view["body"] = "提纯机要求先交出普通宝石，祭品会在确认后永久熔毁。\n\n当前已选 %d / %d；挑错没有撤回，只有在确认前重新整理名单。" % [selected.size(), required]
	var options: Array[Dictionary] = []
	for gem in _destructible_gems("common"):
		var locator := str(gem.get("locator", ""))
		var selected_now := locator in selected
		var label := "%s【%s】（%s）" % ["取消选择 " if selected_now else "选择 ", str(gem.get("name", "")), str(gem.get("location_name", ""))]
		options.append(_option("toggle:%s" % locator, label, selected_now or selected.size() < required, "已选满"))
	options.append(_option("confirm", "确认销毁并提纯", selected.size() == required, "尚未选足宝石"))
	options.append(_option("cancel", "返回"))
	view["options"] = options
	return view


static func _gem_reward_view(view: Dictionary, state: Dictionary, body: String) -> Dictionary:
	var candidates: Array = (state.get("data", {}) as Dictionary).get("reward_candidates", [])
	view["body"] = body
	var options: Array[Dictionary] = []
	for i in range(candidates.size()):
		var gem_id := str(candidates[i])
		if gem_id.is_empty():
			continue
		options.append(_option("reward:%d" % i, "选择【%s】" % DataRegistry.get_gem_display_name(gem_id)))
	view["options"] = options
	return view


static func _relic_selection_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var route := str((state.get("data", {}) as Dictionary).get("reforge_route", "common"))
	view["body"] = "重铸台需要一件%s遗物作为熔材，投入后不会返回原物。\n\n先选定你愿意放弃的旧遗物，再让机器为你开出一条新的可能。" % ("普通" if route == "common" else "稀有")
	var options: Array[Dictionary] = []
	for relic_id in _owned_relics_of_rarity(route):
		options.append(_option("sacrifice:%s" % relic_id, "投入【%s】" % _relic_name(relic_id)))
	options.append(_option("cancel", "返回"))
	view["options"] = options
	return view


static func _relic_reward_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var candidates: Array = (state.get("data", {}) as Dictionary).get("reward_candidates", [])
	view["body"] = "旧遗物已经熔进模具，三道轮廓在冷却的金属上逐渐成形。\n\n它们都来自稀有池，选定一件后，另外两件会重新沉回炉渣。"
	var options: Array[Dictionary] = []
	for i in range(candidates.size()):
		var relic_id := str(candidates[i])
		options.append(_option("reward:%d" % i, "选择【%s】" % _relic_name(relic_id)))
	view["options"] = options
	return view


static func _gem_placement_view(view: Dictionary, state: Dictionary) -> Dictionary:
	var gem_id := str((state.get("data", {}) as Dictionary).get("pending_gem_id", ""))
	view["body"] = "【%s】从证物柜中落入你的手心，仍带着陌生的余温。\n\n你可以把它嵌进空槽，压入已有槽位，或暂时握住它等待下一场战斗。" % DataRegistry.get_gem_display_name(gem_id)
	var options: Array[Dictionary] = []
	for placement in RunPlayerGemService.reward_embed_options(RunService.get_run(), gem_id):
		var slot: Dictionary = placement.get("slot", {})
		var index := int(placement.get("index", -1))
		var overload := bool(placement.get("overload", false))
		var slot_name := _slot_name(str(slot.get("slot_type", "")))
		var label := "嵌入%s槽" % slot_name
		if overload:
			label = "过载嵌入%s槽（保留【%s】）" % [slot_name, DataRegistry.get_gem_display_name(str(slot.get("gem_id", "")))]
		options.append(_option("place:%d:%d" % [index, 1 if overload else 0], label))
	var run := RunService.get_run()
	var allow_hold := run != null and run.carried_gem.is_empty()
	if allow_hold:
		options.append(_option("hold", "暂时手持"))
	options.append(_option("abandon", "放弃这颗宝石"))
	view["options"] = options
	view["gem_placement"] = {
		"gem_id": gem_id,
		"allow_hold": allow_hold,
	}
	return view


static func _choose_scribe(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	if option_id == "leave":
		return _success(state, true, "你没有碰那本账册。")
	var data: Dictionary = state.get("data", {})
	var chapter := RunService.get_current_chapter()
	if option_id == "small":
		if bool(data.get("small_success", false)):
			var gold := int(data.get("small_gold", 0))
			EconomyService.grant("gold", gold, "event_reward", {"transaction_id": "%s:gold" % transaction_id})
			return _success(state, true, "账目蒙混过关，获得 %d 金币。" % gold)
		var damage: int = [7, 8, 9][chapter - 1]
		RunService.damage_player_amount(damage)
		return _success(state, true, "篡改被发现，失去 %d HP。" % damage)
	if option_id == "large" and not _destructible_gems("").is_empty():
		if bool(data.get("large_success", false)):
			var gold := int(data.get("large_gold", 0))
			EconomyService.grant("gold", gold, "event_reward", {"transaction_id": "%s:gold" % transaction_id})
			return _success(state, true, "整页账目通过核验，获得 %d 金币。" % gold)
		var destroyed := _destroy_gem_locators([str(data.get("large_destroy_locator", ""))])
		if destroyed.is_empty():
			return _failure("gem_not_found")
		return _success(state, true, "监察印落下，【%s】被销毁。" % destroyed[0])
	return _failure("option_not_found")


static func _choose_furnace(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	var data: Dictionary = state.get("data", {}).duplicate(true)
	var queue: Array = data.get("queue", [])
	var index := int(data.get("queue_index", 0))
	if option_id == "leave":
		return _success(state, true, "你放弃炉内剩余的宝石。")
	if option_id == "turn" and index < queue.size() - 1:
		var costs := [20, 40] if RunService.get_current_chapter() == 2 else [25, 50]
		var cost: int = costs[index]
		var spent := EconomyService.spend("gold", cost, "event_cost", {"transaction_id": "%s:turn" % transaction_id})
		if not bool(spent.get("ok", false)):
			return _failure("insufficient_funds")
		data["queue_index"] = index + 1
		state["data"] = data
		return _success(state, false, "嵌炉转动，下一颗宝石露了出来。")
	if option_id == "take" and index < queue.size():
		if not RunService.has_relic("relic_crowbar"):
			RunService.damage_player_amount(8 if RunService.get_current_chapter() == 2 else 9)
		return _begin_gem_placement(state, str(queue[index]), "你取出了当前宝石。")
	return _failure("option_not_found")


static func _choose_injury(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	var chapter := RunService.get_current_chapter()
	var snapshot := RunService.get_player_run_snapshot()
	var ratio := float(snapshot.get("hp", 0)) / float(maxi(1, int(snapshot.get("max_hp", 1))))
	if option_id == "leave":
		return _success(state, true, "你没有接受估价。")
	if option_id == "sell_blood" and ratio >= 0.60:
		var damage: int = [8, 9, 10][chapter - 1]
		var gold := int((state.get("data", {}) as Dictionary).get("blood_gold", 0))
		RunService.damage_player_amount(damage)
		EconomyService.grant("gold", gold, "event_reward", {"transaction_id": "%s:blood" % transaction_id})
		return _success(state, true, "血样成交：失去 %d HP，获得 %d 金币。" % [damage, gold])
	var run := RunService.get_run()
	if option_id == "relief" and ratio < 0.30 and run != null and not bool(run.run_stats.get("injury_relief_claimed", false)):
		var amount: int = [10, 12, 15][chapter - 1]
		run.run_stats["injury_relief_claimed"] = true
		RunService.heal_player_amount(amount)
		return _success(state, true, "领取救济，恢复 %d HP。" % amount)
	if option_id == "treatment":
		var costs := [30, 45, 60]
		var heals := [16, 20, 24]
		var spent := EconomyService.spend("gold", costs[chapter - 1], "event_cost", {"transaction_id": "%s:treatment" % transaction_id})
		if not bool(spent.get("ok", false)):
			return _failure("insufficient_funds")
		RunService.heal_player_amount(heals[chapter - 1])
		return _success(state, true, "伤口缝合完毕，恢复 %d HP。" % heals[chapter - 1])
	return _failure("conditions_failed")


static func _choose_auction(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	if option_id == "leave":
		return _success(state, true, "你没有参与竞拍。")
	var key := "safe" if option_id == "buy_safe" else "risky" if option_id == "buy_risky" else ""
	if key.is_empty():
		return _failure("option_not_found")
	var data: Dictionary = state.get("data", {})
	var price := int(data.get("%s_price" % key, 0))
	var spent := EconomyService.spend("gold", price, "event_cost", {"transaction_id": "%s:auction" % transaction_id})
	if not bool(spent.get("ok", false)):
		return _failure("insufficient_funds")
	var relic_id := str(data.get("%s_relic" % key, "relic_placeholder"))
	RunService.acquire_relic(relic_id)
	return _success(state, true, "蒙布掀开，你获得【%s】。" % _relic_name(relic_id))


static func _choose_execution(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	if option_id == "tear":
		return _success(state, true, "执行令被撕成两半。")
	if option_id != "sign":
		return _failure("option_not_found")
	var payout := int((state.get("data", {}) as Dictionary).get("payout", 0))
	EconomyService.grant("gold", payout, "event_reward", {"transaction_id": "%s:payout" % transaction_id})
	RunService.activate_combat_gold_withholding(2)
	return _success(state, true, "领取 %d 金币；之后两场战斗的金币奖励将被扣押。" % payout)


static func _choose_refiner_start(state: Dictionary, option_id: String) -> Dictionary:
	if option_id == "leave":
		return _success(state, true, "你关掉了提纯机。")
	var required := 2 if option_id == "stable" else 1 if option_id == "overpressure" else 0
	if required == 0 or _destructible_gems("common").size() < required:
		return _failure("conditions_failed")
	var data: Dictionary = state.get("data", {}).duplicate(true)
	data["refiner_route"] = option_id
	data["required_gems"] = required
	data["selected_gems"] = []
	state["data"] = data
	state["phase"] = "gem_select"
	return _success(state, false, "选择提纯耗材。")


static func _choose_refiner_gem(state: Dictionary, option_id: String, room_id: String) -> Dictionary:
	var data: Dictionary = state.get("data", {}).duplicate(true)
	var selected: Array = data.get("selected_gems", []).duplicate()
	var required := int(data.get("required_gems", 1))
	if option_id == "cancel":
		data.erase("selected_gems")
		state["data"] = data
		state["phase"] = "start"
		return _success(state, false, "返回提纯机前。")
	if option_id.begins_with("toggle:"):
		var locator := option_id.trim_prefix("toggle:")
		var valid := false
		for gem in _destructible_gems("common"):
			if str(gem.get("locator", "")) == locator:
				valid = true
				break
		if not valid:
			return _failure("gem_not_found")
		if locator in selected:
			selected.erase(locator)
		elif selected.size() < required:
			selected.append(locator)
		data["selected_gems"] = selected
		state["data"] = data
		return _success(state, false, "已更新祭品选择。")
	if option_id != "confirm" or selected.size() != required:
		return _failure("conditions_failed")
	var sacrificed_ids: Array[String] = []
	for gem in _destructible_gems("common"):
		if str(gem.get("locator", "")) in selected:
			sacrificed_ids.append(str(gem.get("gem_id", "")))
	var destroyed := _destroy_gem_locators(selected)
	if destroyed.size() != required:
		return _failure("gem_not_found")
	var route := str(data.get("refiner_route", "stable"))
	var rng := _room_rng(room_id, "refiner:%s:%s" % [route, ",".join(sacrificed_ids)])
	if route == "stable":
		var weights := {"uncommon": 70.0, "rare": 30.0} if RunService.get_current_chapter() == 2 else {"uncommon": 45.0, "rare": 55.0}
		data["reward_candidates"] = _roll_gems(rng, 2, weights, RunService.get_current_chapter(), sacrificed_ids)
		state["data"] = data
		state["phase"] = "gem_reward"
		return _success(state, false, "两颗结晶从熔渣中析出。")
	if rng.randf() < 0.45:
		var rewards := _roll_gems(rng, 1, {"rare": 100.0}, RunService.get_current_chapter(), sacrificed_ids)
		if not rewards.is_empty() and not str(rewards[0]).is_empty():
			return _begin_gem_placement(state, str(rewards[0]), "超压提纯成功。")
	return _success(state, true, "炉压骤降，坩埚里只剩黑灰。")


static func _choose_reforge_start(state: Dictionary, option_id: String) -> Dictionary:
	if option_id == "leave":
		return _success(state, true, "你没有启动重铸台。")
	if option_id not in ["common", "rare"]:
		return _failure("option_not_found")
	if _owned_relics_of_rarity(option_id).is_empty() or _relic_candidates(option_id).is_empty():
		return _failure("conditions_failed")
	var data: Dictionary = state.get("data", {}).duplicate(true)
	data["reforge_route"] = option_id
	state["data"] = data
	state["phase"] = "relic_select"
	return _success(state, false, "选择要重铸的遗物。")


static func _choose_relic_sacrifice(state: Dictionary, option_id: String, room_id: String) -> Dictionary:
	if option_id == "cancel":
		state["phase"] = "start"
		return _success(state, false, "返回重铸台前。")
	if not option_id.begins_with("sacrifice:"):
		return _failure("option_not_found")
	var relic_id := option_id.trim_prefix("sacrifice:")
	var data: Dictionary = state.get("data", {}).duplicate(true)
	var route := str(data.get("reforge_route", "common"))
	if relic_id not in _owned_relics_of_rarity(route):
		return _failure("relic_not_found")
	var candidates := _relic_candidates(route)
	if candidates.is_empty():
		return _failure("relic_pool_empty")
	var rng := _room_rng(room_id, "reforge:%s:%s" % [route, relic_id])
	var rewards := _pick_relics(rng, candidates, 1 if route == "common" else 3)
	if rewards.is_empty():
		return _failure("relic_pool_empty")
	RunService.remove_relic(relic_id)
	if route == "common":
		RunService.acquire_relic(str(rewards[0]))
		return _success(state, true, "【%s】被熔毁，重铸为【%s】。" % [_relic_name(relic_id), _relic_name(str(rewards[0]))])
	data["sacrificed_relic_id"] = relic_id
	data["reward_candidates"] = rewards
	state["data"] = data
	state["phase"] = "relic_reward"
	return _success(state, false, "稀有遗物已经熔毁，三个模具亮了起来。")


static func _choose_relic_reward(state: Dictionary, option_id: String) -> Dictionary:
	if not option_id.begins_with("reward:"):
		return _failure("option_not_found")
	var candidates: Array = (state.get("data", {}) as Dictionary).get("reward_candidates", [])
	var index := int(option_id.trim_prefix("reward:"))
	if index < 0 or index >= candidates.size():
		return _failure("reward_not_found")
	var relic_id := str(candidates[index])
	RunService.acquire_relic(relic_id)
	return _success(state, true, "重铸完成，获得【%s】。" % _relic_name(relic_id))


static func _choose_anesthetist(state: Dictionary, option_id: String) -> Dictionary:
	if option_id in ["leave", "stop"]:
		return _success(state, true, "你收起手臂，离开摊位。")
	var data: Dictionary = state.get("data", {})
	var hp := int(RunService.get_player_run_snapshot().get("hp", 0))
	if option_id == "first" and str(state.get("phase", "start")) == "start" and hp >= 8:
		var summary := _apply_anesthetic_outcome(bool(data.get("first_success", false)), 12, 7)
		state["phase"] = "second"
		return _success(state, false, summary)
	if option_id == "second" and str(state.get("phase", "")) == "second" and hp >= 9:
		return _success(state, true, _apply_anesthetic_outcome(bool(data.get("second_success", false)), 18, 8))
	return _failure("conditions_failed")


static func _choose_cabinet(state: Dictionary, option_id: String, transaction_id: String) -> Dictionary:
	if option_id == "leave":
		return _success(state, true, "你没有打开证物柜。")
	var drawer := "gray" if option_id == "open_gray" else "blue" if option_id == "open_blue" else "black" if option_id == "open_black" else ""
	var costs := {"gray": 20, "blue": 45, "black": 75}
	if drawer.is_empty() or (drawer == "blue" and RunService.get_current_chapter() < 2) or (drawer == "black" and RunService.get_current_chapter() < 3):
		return _failure("option_not_found")
	var cost := int(costs[drawer])
	var spent := EconomyService.spend("gold", cost, "event_cost", {"transaction_id": "%s:drawer" % transaction_id})
	if not bool(spent.get("ok", false)):
		return _failure("insufficient_funds")
	var data: Dictionary = state.get("data", {}).duplicate(true)
	data["opened_drawer"] = drawer
	data["reward_candidates"] = (data.get(drawer, []) as Array).duplicate()
	state["data"] = data
	state["phase"] = "gem_reward"
	return _success(state, false, "抽屉开启，其他封条同时锁死。")


static func _choose_gem_reward(state: Dictionary, option_id: String) -> Dictionary:
	if not option_id.begins_with("reward:"):
		return _failure("option_not_found")
	var candidates: Array = (state.get("data", {}) as Dictionary).get("reward_candidates", [])
	var index := int(option_id.trim_prefix("reward:"))
	if index < 0 or index >= candidates.size():
		return _failure("reward_not_found")
	return _begin_gem_placement(state, str(candidates[index]), "已经选定宝石。")


static func _choose_gem_placement(state: Dictionary, option_id: String) -> Dictionary:
	var data: Dictionary = state.get("data", {}).duplicate(true)
	var gem_id := str(data.get("pending_gem_id", ""))
	if gem_id.is_empty():
		return _failure("reward_not_found")
	if option_id == "hold":
		var acquired := RunService.acquire_gem(gem_id)
		if not bool(acquired.get("ok", false)):
			return _failure(str(acquired.get("error", "carried_gem_occupied")))
		return _success(state, true, "暂时手持【%s】。" % DataRegistry.get_gem_display_name(gem_id))
	if option_id == "abandon":
		return _success(state, true, "你放弃了【%s】。" % DataRegistry.get_gem_display_name(gem_id))
	if not option_id.begins_with("place:"):
		return _failure("option_not_found")
	var parts := option_id.split(":")
	if parts.size() != 3:
		return _failure("option_not_found")
	var result := RunPlayerGemService.embed_reward_gem(RunService.get_run(), gem_id, int(parts[1]), int(parts[2]) == 1)
	if not bool(result.get("ok", false)):
		return _failure(str(result.get("error", "slot_unavailable")))
	RunService.save_run(false)
	return _success(state, true, "【%s】已经嵌入。" % DataRegistry.get_gem_display_name(gem_id))


static func _begin_gem_placement(state: Dictionary, gem_id: String, summary: String) -> Dictionary:
	if gem_id.is_empty():
		return _failure("reward_not_found")
	var data: Dictionary = state.get("data", {}).duplicate(true)
	data["pending_gem_id"] = gem_id
	state["data"] = data
	state["phase"] = "place_gem"
	return _success(state, false, summary)


static func _apply_anesthetic_outcome(success: bool, heal: int, damage: int) -> String:
	if success:
		RunService.heal_player_amount(heal)
		return "药效稳定，恢复 %d HP。" % heal
	var hp := int(RunService.get_player_run_snapshot().get("hp", 1))
	var actual := mini(damage, maxi(0, hp - 1))
	RunService.damage_player_amount(actual)
	return "针剂出现黑色沉淀，失去 %d HP。" % actual


static func _is_available(event_id: String, room_id: String) -> bool:
	var chapter := RunService.get_current_chapter()
	var layer := _room_layer(room_id)
	match event_id:
		EVENT_SCRIBE:
			if chapter == 3 and layer > 6:
				return false
		EVENT_FURNACE:
			if chapter < 2 or (chapter == 3 and layer > 8):
				return false
		EVENT_INJURY:
			pass
		EVENT_AUCTION:
			if chapter < 2:
				return false
		EVENT_EXECUTION:
			if chapter > 2 or layer > 8:
				return false
		EVENT_REFINER, EVENT_REFORGE:
			if chapter < 2:
				return false
		EVENT_ANESTHETIST, EVENT_CABINET:
			pass
		_:
			return false
	var run := RunService.get_run()
	if run == null:
		return false
	var occurrences: Dictionary = run.run_stats.get("event_occurrences", {})
	if event_id in [EVENT_SCRIBE, EVENT_AUCTION, EVENT_EXECUTION]:
		return int(occurrences.get("run:%s" % event_id, 0)) == 0
	if event_id in [EVENT_FURNACE, EVENT_INJURY]:
		return int(occurrences.get("chapter:%d:%s" % [chapter, event_id], 0)) == 0
	return true


static func _destructible_gems(rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var run := RunService.get_run()
	if run == null:
		return result
	RunPlayerGemService.slot_snapshots(run)
	for i in range(run.player_slot_gems.size()):
		var raw: Variant = run.player_slot_gems[i]
		if not raw is Dictionary:
			continue
		var snapshot := raw as Dictionary
		var gem_id := str(snapshot.get("gem_id", ""))
		if not _is_destructible_gem(gem_id, snapshot, rarity):
			continue
		result.append({
			"locator": "slot:%d" % i,
			"gem_id": gem_id,
			"name": DataRegistry.get_gem_display_name(gem_id),
			"location_name": "%s槽" % _slot_name(str(snapshot.get("slot_type", ""))),
		})
	if not run.carried_gem.is_empty():
		var gem_id := str(run.carried_gem.get("gem_id", ""))
		if _is_destructible_gem(gem_id, run.carried_gem, rarity):
			result.append({
				"locator": "carried",
				"gem_id": gem_id,
				"name": DataRegistry.get_gem_display_name(gem_id),
				"location_name": "手持",
			})
	return result


static func _is_destructible_gem(gem_id: String, snapshot: Dictionary, rarity: String) -> bool:
	if gem_id.is_empty() or not DataRegistry.has_gem_def(gem_id):
		return false
	var def := DataRegistry.get_gem_def(gem_id)
	if not bool(def.get("allow_random_pool", true)):
		return false
	for flag in ["temporary", "story_item", "event_special"]:
		if bool(snapshot.get(flag, false)):
			return false
	return rarity.is_empty() or DataRegistry.get_gem_rarity(gem_id) == rarity


static func _destroy_gem_locators(locators: Array) -> Array[String]:
	var run := RunService.get_run()
	var destroyed: Array[String] = []
	if run == null:
		return destroyed
	var slot_indices: Array[int] = []
	var destroy_carried := false
	for raw_locator in locators:
		var locator := str(raw_locator)
		if locator == "carried":
			destroy_carried = true
		elif locator.begins_with("slot:"):
			slot_indices.append(int(locator.trim_prefix("slot:")))
	slot_indices.sort()
	slot_indices.reverse()
	for index in slot_indices:
		if index < 0 or index >= run.player_slot_gems.size():
			continue
		var raw: Variant = run.player_slot_gems[index]
		if not raw is Dictionary:
			continue
		var snapshot := (raw as Dictionary).duplicate(true)
		var gem_id := str(snapshot.get("gem_id", ""))
		if not _is_destructible_gem(gem_id, snapshot, ""):
			continue
		destroyed.append(DataRegistry.get_gem_display_name(gem_id))
		if bool(snapshot.get("overload_slot", false)) or str(snapshot.get("lock_type", "")) == Constants.LOCK_OVERLOAD_SLOT:
			run.player_slot_gems.remove_at(index)
		else:
			for key in ["gem_id", "def_overrides", "temporary", "story_item", "event_special"]:
				snapshot.erase(key)
			run.player_slot_gems[index] = snapshot
	if destroy_carried and not run.carried_gem.is_empty():
		var carried_id := str(run.carried_gem.get("gem_id", ""))
		if _is_destructible_gem(carried_id, run.carried_gem, ""):
			destroyed.append(DataRegistry.get_gem_display_name(carried_id))
			run.carried_gem = {}
	RunService.save_run(false)
	return destroyed


static func _roll_gems(rng: RandomNumberGenerator, count: int, rarity_weights: Dictionary, chapter: int, exclude_ids: Array = []) -> Array[String]:
	var result: Array[String] = []
	var excluded: Array = exclude_ids.duplicate()
	for _i in range(count):
		var by_rarity := {}
		for gem_id in DataRegistry.get_gem_ids():
			if gem_id in excluded:
				continue
			var def := DataRegistry.get_gem_def(gem_id)
			if not bool(def.get("allow_random_pool", true)) or DataRegistry.get_gem_pool_tier(gem_id) > chapter:
				continue
			var rarity := DataRegistry.get_gem_rarity(gem_id)
			if float(rarity_weights.get(rarity, 0.0)) <= 0.0:
				continue
			if not by_rarity.has(rarity):
				by_rarity[rarity] = []
			(by_rarity[rarity] as Array).append(gem_id)
		if by_rarity.is_empty():
			break
		var rarities: Array = []
		var weights: Array = []
		for rarity in rarity_weights.keys():
			if by_rarity.has(rarity) and not (by_rarity[rarity] as Array).is_empty():
				rarities.append(str(rarity))
				weights.append(float(rarity_weights[rarity]))
		var picked_rarity := str(_weighted_pick_rng(rng, rarities, weights))
		var candidates: Array = by_rarity.get(picked_rarity, [])
		var picked := str(candidates[rng.randi_range(0, candidates.size() - 1)])
		result.append(picked)
		excluded.append(picked)
	return result


static func _relic_candidates(rarity: String) -> Array[String]:
	var result: Array[String] = []
	var held := RunService.get_owned_relics()
	var unlock_flags := ProfileService.get_unlock_flags()
	for relic_id in DataRegistry.get_relic_ids():
		if relic_id in held:
			continue
		var def := DataRegistry.get_relic_def(relic_id)
		if str(def.get("rarity", "")) != rarity or float(def.get("base_weight", 0.0)) <= 0.0:
			continue
		if not "global" in def.get("pool_types", []):
			continue
		var unlock_condition := str(def.get("unlock_condition", ""))
		if not unlock_condition.is_empty() and not unlock_condition in unlock_flags:
			continue
		result.append(relic_id)
	result.sort()
	return result


static func _owned_relics_of_rarity(rarity: String) -> Array[String]:
	var result: Array[String] = []
	for relic_id in RunService.get_owned_relics():
		if DataRegistry.get_relic_rarity(relic_id) == rarity and rarity != "boss":
			result.append(relic_id)
	return result


static func _roll_relic(rng: RandomNumberGenerator, rarity: String) -> String:
	var candidates := _relic_candidates(rarity)
	if candidates.is_empty():
		return "relic_placeholder"
	return str(_pick_relics(rng, candidates, 1)[0])


static func _pick_relics(rng: RandomNumberGenerator, candidates: Array[String], count: int) -> Array[String]:
	var pool := candidates.duplicate()
	var result: Array[String] = []
	while not pool.is_empty() and result.size() < count:
		var weights: Array = []
		for relic_id in pool:
			weights.append(DataRegistry.compute_relic_weight(relic_id, RunService.get_weight_ctx()))
		var picked := str(_weighted_pick_rng(rng, pool, weights))
		result.append(picked)
		pool.erase(picked)
	return result


static func _weighted_pick_rng(rng: RandomNumberGenerator, items: Array, weights: Array) -> Variant:
	if items.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, float(weight))
	if total <= 0.0:
		return items[rng.randi_range(0, items.size() - 1)]
	var roll := rng.randf_range(0.0, total)
	var cumulative := 0.0
	for i in range(items.size()):
		cumulative += maxf(0.0, float(weights[i]))
		if roll < cumulative:
			return items[i]
	return items.back()


static func _event_title(event_id: String) -> String:
	match event_id:
		EVENT_SCRIBE: return "错账抄写员"
		EVENT_FURNACE: return "被查封的嵌炉"
		EVENT_INJURY: return "伤势估价所"
		EVENT_AUCTION: return "赝品拍卖会"
		EVENT_EXECUTION: return "先予执行令"
		EVENT_REFINER: return "熔渣提纯机"
		EVENT_REFORGE: return "无证重铸台"
		EVENT_ANESTHETIST: return "街巷麻醉师"
		EVENT_CABINET: return "三级证物柜"
	return "奇遇"


static func _relic_name(relic_id: String) -> String:
	return str(DataRegistry.get_relic_def(relic_id).get("name", relic_id))


static func _slot_name(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED: return "红"
		Constants.SLOT_BLUE: return "蓝"
		Constants.SLOT_BLACK: return "黑"
	return "未知"


static func _option(id: String, label: String, enabled: bool = true, disabled_reason: String = "") -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": enabled,
		"disabled_reason": disabled_reason if not enabled else "",
		"disabled_reason_code": "" if enabled else "runtime_condition_failed",
	}


static func _success(state: Dictionary, resolved: bool, summary: String) -> Dictionary:
	return {
		"ok": true,
		"event_state": state,
		"resolved": resolved,
		"summary": summary,
	}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _room_rng(room_id: String, salt: String) -> RandomNumberGenerator:
	return RngService.create_rng(RngService.derive_room_seed("EVENT", room_id), salt)


static func _room_layer(room_id: String) -> int:
	var coordinate := room_id.split(":")[-1]
	var parts := coordinate.split("_")
	if parts.size() != 2:
		return 0
	return int(parts[0]) + int(parts[1])


static func _chapter_range(chapter: int, ranges: Array) -> Array:
	return ranges[clampi(chapter - 1, 0, ranges.size() - 1)]
