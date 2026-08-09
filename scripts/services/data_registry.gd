extends "res://scripts/services/data_registry_base.gd"

func _ready() -> void:
	var started_usec := Time.get_ticks_usec()
	_register_gem_effect_profiles()
	_load_gem_effect_levels_from_json()
	_load_gem_defs_from_json()
	_load_gem_pools_from_json()
	_load_relic_numeric_refs_from_json()
	_load_relic_source_weights_from_json()
	_validate_shop_pools_source_refs()
	_load_reward_offer_config_from_json()
	_load_battle_reward_ui_config_from_json()
	_load_enemy_slot_curves_from_json()
	_load_unit_defs_from_json()
	_load_encounters_from_json()
	_validate_adventure_progression_refs()
	_load_relic_defs_from_json()
	_startup_load_duration_usec = Time.get_ticks_usec() - started_usec


func create_battle_state(encounter_id: String, seed_value: int = 0, room_id: String = "", restore_run_player_state: bool = true) -> GameState:
	var encounter: Dictionary = _encounters.get(encounter_id, {})
	var current_chapter := 1
	var pending_room_type := ""
	var adventure_svc: Node = Engine.get_main_loop().root.get_node_or_null("AdventureService")
	if adventure_svc != null:
		pending_room_type = str(adventure_svc.get("pending_room_type"))
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc != null and run_svc.has_method("get_current_chapter"):
		current_chapter = int(run_svc.call("get_current_chapter"))
	_uid_counter = 0
	if seed_value != 0:
		# 外部显式提供种子（如单元测试、重放）：以此初始化 master seed
		RngService.start_run(seed_value)
	# 从 master seed 确定性衍生战斗种子，保证 SL 安全
	# master seed 不存在时（首次裸启）退化为时间戳，行为与旧逻辑一致
	var combat_seed := RngService.derive_combat_seed(encounter_id, room_id)
	RngService.reset_state(combat_seed, "combat:%s" % encounter_id)
	if encounter_id == ProceduralEncounterGenerator.ENCOUNTER_ID:
		encounter = ProceduralEncounterGenerator.generate(combat_seed, current_chapter, room_id)
	if encounter.is_empty():
		push_error("Encounter not found: %s" % encounter_id)
		return null
	var state := BattleStateFactory.create_base_state(
		encounter_id,
		encounter.get("player_spawn", Vector2i(3, 2)),
		_unit_defs["unit_player"],
		RngService.get_seed(),
		Callable(self, "_next_uid")
	)
	var player := state.get_player()
	if restore_run_player_state:
		_apply_run_slot_overrides(player)
		_restore_run_player_state(state, player)
	for enemy_data in _resolve_encounter_enemies(encounter, encounter_id):
		var enemy_uid := _next_uid(enemy_data.get("def_id", "enemy"))
		var def: Dictionary = _unit_defs[enemy_data.get("def_id", "unit_bomb_rat")].duplicate(true)
		var base_slots: Array = def.get("slots", [])
		var spawn_gem_slots: Array = def.get("spawn_gem_slots", [])
		var restrict_spawn_gem_slots := def.has("spawn_gem_slots")
		var enemy_slot_budget := _resolve_enemy_slot_budget(current_chapter, pending_room_type, encounter_id, enemy_data, def)
		def["slots"] = []
		for slot_data in base_slots:
			var slot_entry: Dictionary = slot_data.duplicate(true)
			var slot_type := str(slot_entry.get("slot_type", ""))
			var should_roll_gem := not slot_entry.has("gem_id")
			if should_roll_gem and restrict_spawn_gem_slots:
				should_roll_gem = slot_type in spawn_gem_slots
			if should_roll_gem and enemy_slot_budget > 0:
				enemy_slot_budget -= 1
				var enemy_pool_source := _resolve_enemy_pool_source(current_chapter, pending_room_type)
				var roll_gem_id := roll_spawnable_gem_id("enemy_spawn_%s_%s_%s" % [encounter_id, enemy_uid, slot_type], [], enemy_pool_source, current_chapter)
				if not roll_gem_id.is_empty():
					slot_entry["gem_id"] = roll_gem_id
			def["slots"].append(slot_entry)
		var enemy := BattleStateFactory.add_enemy(
			state,
			enemy_data,
			def,
			enemy_uid,
			Callable(self, "_next_uid"),
			Callable(self, "create_gem_instance")
		)
		_apply_unit_spawn_variants(enemy, def)
		OldMageEncounterSetup.configure_loadout(self, state, enemy)
	BoardMapGenerator.build(state, encounter)
	OldMageEncounterSetup.spawn_gem_field(self, state, encounter)
	TileRules.sync_all_units_standing_ground(state)
	IntentSystem.refresh_all_intents(state)
	# 所有单位就位后建立 O(1) 占格索引（多格单位 footprint 一并注册）
	state.rebuild_occupancy()
	if encounter_id == ProceduralEncounterGenerator.ENCOUNTER_ID:
		ProceduralEncounterGenerator.freeze_initial_blueprint(state, encounter)
	EncounterContentDiagnostics.report(state)
	state.log("遭遇战开始: %s" % encounter_id)
	return state
func create_battle_state_from_editor_payload(encounter_id: String, encounter: Dictionary, seed_value: int = 0) -> GameState:
	if encounter.is_empty():
		push_error("Encounter payload is empty: %s" % encounter_id)
		return null
	_uid_counter = 0
	if seed_value != 0:
		RngService.start_run(seed_value)
	var combat_seed := int(encounter.get("floor_seed", RngService.derive_combat_seed(encounter_id, "")))
	RngService.reset_state(combat_seed, "combat:%s" % encounter_id)
	var player_spawn: Vector2i = encounter.get("player_spawn", Vector2i(3, 2))
	var state := BattleStateFactory.create_base_state(
		encounter_id,
		player_spawn,
		_unit_defs["unit_player"],
		combat_seed,
		Callable(self, "_next_uid")
	)
	for enemy_data in _resolve_encounter_enemies(encounter, encounter_id):
		var enemy_uid := _next_uid(str(enemy_data.get("def_id", "enemy")))
		var def_id := str(enemy_data.get("def_id", "unit_bomb_rat"))
		var enemy_def: Dictionary = get_unit_def(def_id)
		var slot_defs: Array = enemy_data.get("slots", enemy_def.get("slots", [])).duplicate(true)
		enemy_def["slots"] = slot_defs
		var enemy := BattleStateFactory.add_enemy(
			state,
			enemy_data,
			enemy_def,
			enemy_uid,
			Callable(self, "_next_uid"),
			Callable(self, "create_gem_instance")
		)
		OldMageEncounterSetup.configure_loadout(self, state, enemy)
	BoardMapGenerator.build(state, encounter)
	OldMageEncounterSetup.spawn_gem_field(self, state, encounter)
	TileRules.sync_all_units_standing_ground(state)
	IntentSystem.refresh_all_intents(state)
	state.rebuild_occupancy()
	EncounterContentDiagnostics.report(state)
	state.log("遭遇战开始: %s" % encounter_id)
	return state


func _load_gem_defs_from_json() -> void:
	var path := "res://resources/gems/gem_defs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_gem_defs(raw, _key_set(_gem_effect_profiles.keys()))
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_defs = {}
	if not errors.is_empty():
		return
	for gem_id in raw.keys():
		var entry: Dictionary = (raw[gem_id] as Dictionary).duplicate(true)
		if entry.has("color"):
			var c: Array = entry["color"]
			entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
		_gem_defs[gem_id] = entry


func _load_gem_effect_levels_from_json() -> void:
	var path := "res://resources/gems/gem_effect_levels.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_gem_effect_levels(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_effect_levels = {}
	if not errors.is_empty():
		return
	_gem_effect_levels = raw.duplicate(true)


func _load_gem_pools_from_json() -> void:
	var path := "res://resources/gems/gem_pools.json"
	var raw := _read_json_file(path)
	var known_tags: Dictionary = {}
	for gem_id in get_gem_ids():
		known_tags[get_gem_tag(gem_id)] = true
	var errors := BalanceConfigValidator.validate_gem_pools(raw, known_tags)
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_pools = {}
	_gem_teaching_boosts = {}
	if not errors.is_empty():
		return
	_gem_teaching_boosts = (raw["teaching_boosts"] as Dictionary).duplicate(true)
	_gem_pools = raw.duplicate(true)
	_gem_pools.erase("teaching_boosts")


func _load_relic_numeric_refs_from_json() -> void:
	var path := "res://resources/relics/relic_numeric_refs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_numeric_refs(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_numeric_refs = {}
	if not errors.is_empty():
		return
	_relic_numeric_refs = raw.duplicate(true)


func _load_relic_source_weights_from_json() -> void:
	var path := "res://resources/adventure/relic_source_weights.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_source_weights(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_source_weights = {}
	if not errors.is_empty():
		return
	_relic_source_weights = raw.duplicate(true)


func _load_reward_offer_config_from_json() -> void:
	var path := "res://resources/adventure/reward_offer_config.json"
	var raw := _read_json_file(path)
	var errors := AdventureConfigValidator.validate_reward_offer_config(
		raw,
		_key_set(get_relic_source_ids())
	)
	AdventureConfigValidator.ensure_valid(path, errors)
	_reward_offer_config = {}
	if not errors.is_empty():
		return
	_reward_offer_config = raw.duplicate(true)


func _load_battle_reward_ui_config_from_json() -> void:
	var path := "res://resources/ui/battle_reward_ui_config.json"
	var raw := _read_json_file(path)
	var errors := AdventureConfigValidator.validate_battle_reward_ui_config(raw)
	AdventureConfigValidator.ensure_valid(path, errors)
	_battle_reward_ui_config = {}
	if not errors.is_empty():
		return
	_battle_reward_ui_config = raw.duplicate(true)


func _validate_shop_pools_source_refs() -> void:
	var path := "res://resources/adventure/shop_pools.json"
	var raw := _read_json_file(path)
	if raw.is_empty():
		return
	AdventureConfigValidator.ensure_valid(
		path,
		AdventureConfigValidator.validate_shop_pools(
			raw,
			_key_set(get_gem_pool_source_ids()),
			_key_set(get_relic_source_ids())
		)
	)


func _load_enemy_slot_curves_from_json() -> void:
	var path := "res://resources/adventure/enemy_slot_curves.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_enemy_slot_curves(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_enemy_slot_curves = {}
	if not errors.is_empty():
		return
	_enemy_slot_curves = raw.duplicate(true)


func _validate_adventure_progression_refs() -> void:
	var path := AdventureProgressionConfig.CONFIG_PATH
	var event_defs := _read_json_file("res://resources/adventure/event_defs.json")
	AdventureConfigValidator.ensure_valid(
		path,
		AdventureConfigValidator.validate_adventure_progression(
			AdventureProgressionConfig.get_config(),
			_key_set(get_encounter_ids()),
			_key_set(event_defs.keys())
		)
	)


func _load_unit_defs_from_json() -> void:
	var path := "res://resources/units/unit_defs.json"
	var raw := _read_json_file(path)
	var known_ai_profile_ids := _key_set(AIProfiles.get_profile_ids())
	known_ai_profile_ids["player"] = true
	known_ai_profile_ids["training_dummy"] = true
	var errors := BalanceConfigValidator.validate_unit_defs(
		raw,
		_key_set(get_gem_ids()),
		_key_set(BehaviorRegistry.get_behavior_ids()),
		known_ai_profile_ids
	)
	BalanceConfigValidator.ensure_valid(path, errors)
	_unit_defs = {}
	if not errors.is_empty():
		return
	_unit_defs = raw.duplicate(true)


func _load_encounters_from_json() -> void:
	_encounters = {}
	var production_dir := "res://resources/encounters/"
	var loaded_count := _load_encounters_from_dir(production_dir)
	if loaded_count <= 0:
		AdventureConfigValidator.ensure_valid(production_dir, ["no valid encounter definitions loaded"])
	if OS.is_debug_build():
		_load_encounters_from_dir("res://tests/fixtures/encounters/")


func _load_encounters_from_dir(dir_path: String) -> int:
	var raw_entries := EncounterCatalogLoader.load_raw_entries(
		dir_path,
		_encounters,
		Callable(self, "_read_json_file"),
		Callable(self, "_validate_encounter_def"),
		Callable(self, "_report_encounter_errors")
	)
	for encounter_id in raw_entries:
		_encounters[encounter_id] = _parse_encounter_json(raw_entries[encounter_id])
	return raw_entries.size()


func _validate_encounter_def(encounter_id: String, raw: Dictionary) -> Array[String]:
	return AdventureConfigValidator.validate_encounter_def(
		encounter_id,
		raw,
		_unit_defs,
		_key_set(get_tile_ids()),
		_key_set(get_entity_ids()),
		_key_set(get_overlay_ids()),
		_key_set(get_gem_ids()),
		Constants.BOARD_SIZE
	)


func _report_encounter_errors(path: String, errors: Array[String]) -> void:
	AdventureConfigValidator.ensure_valid(path, errors)


func _parse_encounter_json(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	# player_spawn: [x, y] → Vector2i
	if result.has("player_spawn"):
		var sp: Array = result["player_spawn"]
		result["player_spawn"] = Vector2i(int(sp[0]), int(sp[1]))
	# enemies: pos [x, y] → Vector2i
	if result.has("enemies"):
		result["enemies"] = _parse_enemy_positions(result["enemies"])
	if result.has("enemy_groups"):
		var groups: Array = result["enemy_groups"]
		for i in range(groups.size()):
			var group: Dictionary = groups[i].duplicate(true)
			group["enemies"] = _parse_enemy_positions(group.get("enemies", []))
			groups[i] = group
		result["enemy_groups"] = groups
	if result.has("random_enemies"):
		var random_enemies: Array = result["random_enemies"]
		for i in range(random_enemies.size()):
			var slot: Dictionary = random_enemies[i].duplicate(true)
			if slot.has("pos"):
				var p: Array = slot["pos"]
				slot["pos"] = Vector2i(int(p[0]), int(p[1]))
			random_enemies[i] = slot
		result["random_enemies"] = random_enemies
	# tiles: pos [x, y] → Vector2i
	if result.has("tiles"):
		var tiles: Array = result["tiles"]
		for i in range(tiles.size()):
			var t: Dictionary = tiles[i].duplicate(true)
			if t.has("pos"):
				var p: Array = t["pos"]
				t["pos"] = Vector2i(int(p[0]), int(p[1]))
			tiles[i] = t
		result["tiles"] = tiles
	if result.has("entities"):
		var entities: Array = result["entities"]
		for i in range(entities.size()):
			var entry: Dictionary = entities[i].duplicate(true)
			if entry.has("pos"):
				var p: Variant = entry["pos"]
				if p is Array and p.size() >= 2:
					entry["pos"] = Vector2i(int(p[0]), int(p[1]))
			entities[i] = entry
		result["entities"] = entities
	return result


func _parse_enemy_positions(raw_enemies: Array) -> Array:
	var enemies := raw_enemies.duplicate(true)
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i].duplicate(true)
		if enemy.has("pos"):
			var p: Array = enemy["pos"]
			enemy["pos"] = Vector2i(int(p[0]), int(p[1]))
		enemies[i] = enemy
	return enemies


func _resolve_enemy_slot_budget(
	chapter: int,
	room_type: String,
	encounter_id: String,
	enemy_data: Dictionary,
	def: Dictionary
) -> int:
	var fixed_count := 0
	var random_slot_defs: Array[Dictionary] = []
	var spawn_gem_slots: Array = def.get("spawn_gem_slots", [])
	var restrict_spawn_gem_slots := def.has("spawn_gem_slots")
	for raw_slot in def.get("slots", []):
		if not raw_slot is Dictionary:
			continue
		var slot_def := raw_slot as Dictionary
		if slot_def.has("gem_id"):
			fixed_count += 1
			continue
		if restrict_spawn_gem_slots and not str(slot_def.get("slot_type", "")) in spawn_gem_slots:
			continue
		random_slot_defs.append(slot_def)
	if random_slot_defs.is_empty():
		return 0
	var target_total := _roll_enemy_total_gem_slots(chapter, room_type, encounter_id, enemy_data, def)
	return clampi(target_total - fixed_count, 0, random_slot_defs.size())


func _roll_enemy_total_gem_slots(
	chapter: int,
	room_type: String,
	encounter_id: String,
	enemy_data: Dictionary,
	def: Dictionary
) -> int:
	var def_id := str(enemy_data.get("def_id", ""))
	if def_id == "unit_bomb_rat":
		return 1
	var slots: Array = def.get("slots", [])
	var max_slots := slots.size()
	if max_slots <= 0:
		return 0
	var normalized_room_type := room_type.to_upper()
	var weights := get_enemy_total_slot_weights(normalized_room_type, chapter)
	var items: Array = []
	var item_weights: Array[float] = []
	for slot_count in range(weights.size()):
		if slot_count > max_slots:
			continue
		items.append(slot_count)
		item_weights.append(float(weights[slot_count]))
	var picked: Variant = RngService.weighted_pick(
		"enemy_slot_budget_%s_%s_%s" % [encounter_id, def_id, str(enemy_data.get("pos", Vector2i.ZERO))],
		items,
		item_weights
	)
	var picked_count := int(picked) if picked != null else mini(1, max_slots)
	if _enemy_requires_initial_gem(enemy_data, def):
		picked_count = maxi(1, picked_count)
	return clampi(picked_count, 0, max_slots)


func _enemy_requires_initial_gem(enemy_data: Dictionary, def: Dictionary) -> bool:
	if bool(enemy_data.get("allow_empty_gems", false)) or bool(def.get("allow_empty_gems", false)):
		return false
	for raw_tag in def.get("tags", []):
		if str(raw_tag) == "unit:test_fixture":
			return false
	return not def.get("slots", []).is_empty()


func _enemy_total_slot_weights(chapter: int, room_type: String) -> Array[float]:
	return get_enemy_total_slot_weights(room_type, chapter)


func _load_relic_defs_from_json() -> void:
	var path := "res://resources/relics/relic_defs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_defs(raw, _relic_numeric_refs)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_defs = {}
	if not errors.is_empty():
		return
	for relic_id in raw.keys():
		var entry: Dictionary = (raw[relic_id] as Dictionary).duplicate(true)
		if entry.has("desc"):
			entry["desc"] = NumericTextResolver.format_text(str(entry.get("desc", "")), {
				"relic_numeric_refs": _relic_numeric_refs,
			})
		if _relic_defs.has(relic_id):
			_relic_defs[relic_id] = _deep_merge_dict(_relic_defs[relic_id], entry)
		else:
			_relic_defs[relic_id] = entry


## 将 RunState 记录的持久槽位变更应用到刚创建的玩家单位上
func _apply_run_slot_overrides(player: UnitState) -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		return
	var run: RunState = run_svc.get_run()
	if run == null:
		return
	for entry in run.extra_slots:
		var slot_type: String = str(entry.get("slot_type", ""))
		if not slot_type.is_empty():
			player.slots.append(SlotState.create(slot_type))
	var upgrades_applied: int = 0
	for entry in run.upgraded_slots:
		var from_type: String = str(entry.get("from_type", ""))
		var to_dual: String = str(entry.get("to_dual_type", ""))
		if from_type.is_empty() or to_dual.is_empty():
			continue
		var applied := false
		for i in range(upgrades_applied, player.slots.size()):
			var slot: SlotState = player.slots[i]
			if slot.slot_type == from_type and slot.dual_type.is_empty():
				slot.dual_type = to_dual
				applied = true
				upgrades_applied += 1
				break
		if not applied:
			upgrades_applied += 1


func _restore_run_player_state(state: GameState, player: UnitState) -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		return
	var run: RunState = run_svc.get_run()
	if run == null:
		return
	if run.player_max_hp > 0:
		player.max_hp = run.player_max_hp
	if run.player_hp >= 0:
		player.hp = mini(player.max_hp, maxi(0, run.player_hp))
	_ensure_player_slots_for_restore(player, run.player_slot_gems)
	for i in range(run.player_slot_gems.size()):
		var raw_slot: Variant = run.player_slot_gems[i]
		if not raw_slot is Dictionary:
			continue
		var slot_snapshot := raw_slot as Dictionary
		if slot_snapshot.is_empty():
			continue
		var gem := create_gem_instance(
			_next_uid("gem"),
			str(slot_snapshot.get("gem_id", "")),
			slot_snapshot.get("def_overrides", {}) if slot_snapshot.get("def_overrides", {}) is Dictionary else {}
		)
		if gem.gem_id.is_empty():
			continue
			
		var slot: SlotState = player.slots[i]
		slot.gem_uid = gem.uid
		var lock_type := str(slot_snapshot.get("lock_type", ""))
		if not lock_type.is_empty():
			slot.lock_type = lock_type
		slot.overload_slot = bool(slot_snapshot.get("overload_slot", lock_type == Constants.LOCK_OVERLOAD_SLOT))
		if slot.dual_type.is_empty():
			var dual_type := str(slot_snapshot.get("dual_type", ""))
			if not dual_type.is_empty():
				slot.dual_type = dual_type
		gem.mark_slotted(player.uid, i)
		state.gems[gem.uid] = gem
	if not run.carried_gem.is_empty():
		var carried := create_gem_instance(
			_next_uid("gem"),
			str(run.carried_gem.get("gem_id", "")),
			run.carried_gem.get("def_overrides", {}) if run.carried_gem.get("def_overrides", {}) is Dictionary else {}
		)
		if not carried.gem_id.is_empty():
			carried.mark_held(player.uid)
			state.gems[carried.uid] = carried
			state.held_gem_uid = carried.uid
	state.overload_active_mutations = run.overload_active_mutations.duplicate()


## 过载等战斗内追加的槽位只写入 player_slot_gems，不会进入 extra_slots
func _ensure_player_slots_for_restore(player: UnitState, slot_gems: Array) -> void:
	while player.slots.size() < slot_gems.size():
		var i := player.slots.size()
		var raw_slot: Variant = slot_gems[i]
		var slot_type := Constants.SLOT_RED
		var dual_type := ""
		var lock_type := ""
		var overload_slot := false
		if raw_slot is Dictionary:
			var snapshot := raw_slot as Dictionary
			slot_type = str(snapshot.get("slot_type", Constants.SLOT_RED))
			if slot_type.is_empty():
				slot_type = Constants.SLOT_RED
			dual_type = str(snapshot.get("dual_type", ""))
			lock_type = str(snapshot.get("lock_type", ""))
			overload_slot = bool(snapshot.get("overload_slot", lock_type == Constants.LOCK_OVERLOAD_SLOT))
		var slot := SlotState.create(slot_type)
		if not dual_type.is_empty():
			slot.dual_type = dual_type
		if not lock_type.is_empty():
			slot.lock_type = lock_type
		slot.overload_slot = overload_slot
		player.slots.append(slot)
## 根据章节和房间类型映射到对应的敌人宝石 pool key
func _resolve_enemy_pool_source(chapter: int, room_type: String) -> String:
	var normalized := room_type.to_upper()
	match normalized:
		"BOSS", "BOSS_COMBAT", "END":
			return "enemy_boss"
		"ELITE_COMBAT":
			if chapter >= 3:
				return "enemy_boss"
			return "enemy_elite"
		_:
			if chapter >= 2:
				return "enemy_elite"
			return "enemy_normal"


## 返回当前 source pool 的候选列表，附带每项权重，供 debug 工具查看
func get_gem_pool_candidates(source: String, chapter_tier: int = 99) -> Array[Dictionary]:
	var pool_def := get_gem_pool_def(source)
	var rarity_weights: Dictionary = pool_def.get("rarity_weights", {})
	var tag_weights: Dictionary = pool_def.get("tag_weights", {}).duplicate(true)
	_apply_teaching_boosts(tag_weights, chapter_tier)
	var allowed: Array = []
	if not rarity_weights.is_empty():
		for rarity in rarity_weights.keys():
			if float(rarity_weights[rarity]) > 0.0:
				allowed.append(str(rarity))
	var candidates := get_spawnable_gem_ids_for_source(source, chapter_tier, allowed)
	var result: Array[Dictionary] = []
	for gem_id in candidates:
		var weight := _gem_pool_weight(gem_id, rarity_weights, tag_weights)
		result.append({
			"gem_id": gem_id,
			"tag": get_gem_tag(gem_id),
			"rarity": get_gem_rarity(gem_id),
			"pool_tier": get_gem_pool_tier(gem_id),
			"weight": weight,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(b.get("weight", 0.0)) > float(a.get("weight", 0.0))
	)
	return result


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DataRegistry: cannot open %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("DataRegistry: JSON parse error in %s — %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return data as Dictionary
	push_warning("DataRegistry: expected JSON object in %s" % path)
	return {}


func _key_set(ids: Array) -> Dictionary:
	var result := {}
	for id in ids:
		result[str(id)] = true
	return result
