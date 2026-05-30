class_name BattleController
extends RefCounted

signal state_changed
signal battle_ended(result: String)
signal anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i)
signal anim_damage(grid: Vector2i, damage: int, is_crit: bool)
signal anim_gem_flash(grid: Vector2i, gem_color: Color)

var state: GameState = null
var selected_action: String = ""
var selected_unit_uid: String = ""

var _action_svc: BattleActionService = BattleActionService.new()
var _turn_svc: BattleTurnService = BattleTurnService.new()
var _query_svc: BattleQueryService = BattleQueryService.new()
var _editor_cli: BattleEditorCli = BattleEditorCli.new()


func _init() -> void:
	_action_svc.setup(self)
	_turn_svc.setup(self)
	_query_svc.setup(self)
	_editor_cli.setup(self)


# ═══════════════════════════════════════════════════════════════════════════
# 战斗启动
# ═══════════════════════════════════════════════════════════════════════════

func start_encounter(encounter_id: String, seed_value: int = 0, room_id: String = "") -> void:
	state = _data_registry().create_battle_state(encounter_id, seed_value, room_id)
	selected_action = ""
	selected_unit_uid = state.player_uid if state != null else ""
	state.battle_temp_flags.clear()
	_connect_relic_signals(state)
	state.on_battle_start.emit()
	_emit_changed()


## 统一在信号层连接遗物事件触发，避免分散在各规则文件
func _connect_relic_signals(s: GameState) -> void:
	s.on_battle_start.connect(func() -> void:
		RelicEffectRegistry.fire_event("battle_start", s)
	)
	s.on_turn_start.connect(func(turn_index: int) -> void:
		RelicEffectRegistry.fire_event("turn_start", s, {"turn_index": turn_index})
	)
	s.on_turn_end.connect(func(turn_index: int) -> void:
		RelicEffectRegistry.fire_event("turn_end", s, {"turn_index": turn_index})
	)
	s.on_unit_die.connect(func(unit_uid: String, killer_uid: String, reason: String) -> void:
		RelicEffectRegistry.fire_event("unit_die", s, {
			"unit_uid": unit_uid, "killer_uid": killer_uid, "reason": reason
		})
	)
	s.on_battle_end.connect(func(result: String) -> void:
		if result == "win":
			RelicEffectRegistry.fire_event("battle_win", s, {"encounter_id": s.encounter_id})
	)


func select_action(action: String) -> void:
	selected_action = action
	_emit_changed()


# ═══════════════════════════════════════════════════════════════════════════
# 玩家行动（委托 BattleActionService）
# ═══════════════════════════════════════════════════════════════════════════

func try_move(target_pos: Vector2i) -> Dictionary:
	return _action_svc.try_move(target_pos)


func try_attack(target_uid: String) -> Dictionary:
	return _action_svc.try_attack(target_uid)


func try_attack_cell(target_pos: Vector2i) -> Dictionary:
	return _action_svc.try_attack_cell(target_pos)


func try_extract(target_uid: String, slot_index: int) -> Dictionary:
	return _action_svc.try_extract(target_uid, slot_index)


func try_insert(target_uid: String, slot_index: int) -> Dictionary:
	return _action_svc.try_insert(target_uid, slot_index)


func try_trigger(target_uid: String, slot_index: int) -> Dictionary:
	return _action_svc.try_trigger(target_uid, slot_index)


func try_extract_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	return _action_svc.try_extract_tile(tile_pos, slot_index)


func try_insert_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	return _action_svc.try_insert_tile(tile_pos, slot_index)


func try_trigger_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	return _action_svc.try_trigger_tile(tile_pos, slot_index)


# ═══════════════════════════════════════════════════════════════════════════
# 槽位可用性检查
# ═══════════════════════════════════════════════════════════════════════════

func check_slot_action(target_uid: String, slot_index: int) -> Dictionary:
	if state == null:
		return _fail("战斗未开始")
	var player := state.get_player()
	var target: UnitState = state.units.get(target_uid, null)
	if player == null or target == null:
		return _fail("目标无效")
	var slot := target.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	match selected_action:
		Constants.ACTION_EXTRACT:
			return GemRules.can_extract(state, player, target, slot)
		Constants.ACTION_INSERT:
			return GemRules.can_insert(state, player, target, slot)
		Constants.ACTION_TRIGGER:
			return GemRules.can_trigger(state, player, target, slot)
	return _fail("当前操作不支持槽位")


func check_tile_slot_action(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	if state == null:
		return _fail("战斗未开始")
	var player := state.get_player()
	var tile := state.get_tile(tile_pos)
	if player == null or tile == null or not tile.has_slots():
		return _fail("目标无效")
	var slot := tile.get_slot_by_index(slot_index)
	if slot == null:
		return _fail("槽位无效")
	match selected_action:
		Constants.ACTION_EXTRACT:
			return GemRules.can_extract_tile(state, player, tile, slot)
		Constants.ACTION_INSERT:
			return GemRules.can_insert_tile(state, player, tile, slot)
		Constants.ACTION_TRIGGER:
			return GemRules.can_trigger_tile(state, player, tile, slot)
	return _fail("当前操作不支持地块槽位")


func can_use_action(action: String) -> bool:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return false
	match action:
		Constants.ACTION_MOVE:
			return not state.player_moved
		Constants.ACTION_ATTACK, Constants.ACTION_TRIGGER:
			return not state.player_acted
		Constants.ACTION_EXTRACT:
			return state.held_gem_uid.is_empty()
		Constants.ACTION_INSERT:
			return not state.held_gem_uid.is_empty()
		Constants.ACTION_END_TURN:
			return true
	return false


func get_held_gem() -> GemState:
	if state == null or state.held_gem_uid.is_empty():
		return null
	return state.gems.get(state.held_gem_uid, null)


# ═══════════════════════════════════════════════════════════════════════════
# 敌方回合（委托 BattleTurnService）
# ═══════════════════════════════════════════════════════════════════════════

func begin_enemy_phase() -> void:
	_turn_svc.begin_enemy_phase()


func execute_single_enemy(enemy: UnitState) -> Dictionary:
	return _turn_svc.execute_single_enemy(enemy)


func finish_enemy_phase() -> void:
	_turn_svc.finish_enemy_phase()


func get_sorted_enemies() -> Array:
	return _turn_svc.get_sorted_enemies()


# ═══════════════════════════════════════════════════════════════════════════
# UI 查询（委托 BattleQueryService）
# ═══════════════════════════════════════════════════════════════════════════

func get_highlights(hover_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	return _query_svc.get_highlights(hover_cell)


func get_cell_preview(cell: Vector2i) -> Dictionary:
	return _query_svc.get_cell_preview(cell)


func get_action_hint() -> String:
	return _query_svc.get_action_hint()


func get_tutorial_hint() -> String:
	return _query_svc.get_tutorial_hint()


# ═══════════════════════════════════════════════════════════════════════════
# 编辑器 CLI（委托 BattleEditorCli）
# ═══════════════════════════════════════════════════════════════════════════

func run_editor_command(raw_command: String) -> Dictionary:
	return _editor_cli.run(raw_command)


# ═══════════════════════════════════════════════════════════════════════════
# 内部方法（供各 service 回调）
# ═══════════════════════════════════════════════════════════════════════════

func _check_battle_end() -> void:
	_turn_svc.check_battle_end()


func _emit_changed() -> void:
	state_changed.emit()


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
