class_name BattleController
extends RefCounted

const _BattleActionService = preload("res://scripts/battle/battle_action_service.gd")
const _BattleTurnService = preload("res://scripts/battle/battle_turn_service.gd")
const _BattleQueryService = preload("res://scripts/battle/battle_query_service.gd")
const _BattleEditorCli = preload("res://scripts/debug/battle_editor_cli.gd")
const _BattleEditorService = preload("res://scripts/debug/battle_editor_service.gd")
const OverloadRules = preload("res://scripts/rules/overload_rules.gd")

signal state_changed
signal battle_ended(result: String)
signal anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i)
signal anim_damage(grid: Vector2i, damage: int, is_crit: bool)
signal anim_gem_flash(grid: Vector2i, gem_color: Color)

var state: GameState = null
var selected_action: String = ""
var selected_unit_uid: String = ""
var editor_unlimited_actions: bool = false

var _action_svc: BattleActionService = null
var _turn_svc: BattleTurnService = null
var _query_svc: BattleQueryService = null
var _editor_cli: BattleEditorCli = null
var _editor_svc = null


func _init() -> void:
	_ensure_services()


func _ensure_services() -> void:
	if _action_svc == null:
		_action_svc = _BattleActionService.new()
		_action_svc.setup(self)
	if _turn_svc == null:
		_turn_svc = _BattleTurnService.new()
		_turn_svc.setup(self)
	if _query_svc == null:
		_query_svc = _BattleQueryService.new()
		_query_svc.setup(self)
	if _editor_svc == null:
		_editor_svc = _BattleEditorService.new()
		_editor_svc.setup(self)
	if _editor_cli == null:
		_editor_cli = _BattleEditorCli.new()
		_editor_cli.setup(self)


func _relic_effect_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RelicEffectRegistry")


func _fire_relic_event(event_id: String, battle_state: GameState, payload: Dictionary = {}) -> void:
	var registry := _relic_effect_registry()
	if registry == null:
		return
	registry.fire_event(event_id, battle_state, payload)


# ═══════════════════════════════════════════════════════════════════════════
# 战斗启动
# ═══════════════════════════════════════════════════════════════════════════

func start_encounter(encounter_id: String, seed_value: int = 0, room_id: String = "") -> void:
	_ensure_services()
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
		_fire_relic_event("battle_start", s)
	)
	s.on_turn_start.connect(func(turn_index: int) -> void:
		_fire_relic_event("turn_start", s, {"turn_index": turn_index})
	)
	s.on_turn_end.connect(func(turn_index: int) -> void:
		_fire_relic_event("turn_end", s, {"turn_index": turn_index})
	)
	s.on_unit_die.connect(func(unit_uid: String, killer_uid: String, reason: String) -> void:
		_fire_relic_event("unit_die", s, {
			"unit_uid": unit_uid, "killer_uid": killer_uid, "reason": reason
		})
	)
	s.on_battle_end.connect(func(result: String) -> void:
		if result == "win":
			_fire_relic_event("battle_win", s, {"encounter_id": s.encounter_id})
	)


func select_action(action: String) -> void:
	if state != null and action.is_empty():
		OverloadRules.record_non_insert_action(state, action)
	selected_action = action
	_emit_changed()


# ═══════════════════════════════════════════════════════════════════════════
# 玩家行动（委托 BattleActionService）
# ═══════════════════════════════════════════════════════════════════════════

func try_move(target_pos: Vector2i) -> Dictionary:
	_ensure_services()
	return _action_svc.try_move(target_pos)


func try_attack(target_uid: String) -> Dictionary:
	_ensure_services()
	return _action_svc.try_attack(target_uid)


func try_attack_cell(target_pos: Vector2i) -> Dictionary:
	_ensure_services()
	return _action_svc.try_attack_cell(target_pos)


func try_extract(target_uid: String, slot_index: int) -> Dictionary:
	_ensure_services()
	return _action_svc.try_extract(target_uid, slot_index)


func try_insert(target_uid: String, slot_index: int) -> Dictionary:
	_ensure_services()
	return _action_svc.try_insert(target_uid, slot_index)


func try_trigger(target_uid: String, slot_index: int) -> Dictionary:
	_ensure_services()
	return _action_svc.try_trigger(target_uid, slot_index)


func try_extract_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	_ensure_services()
	return _action_svc.try_extract_tile(tile_pos, slot_index)


func try_insert_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	_ensure_services()
	return _action_svc.try_insert_tile(tile_pos, slot_index)


func try_trigger_tile(tile_pos: Vector2i, slot_index: int) -> Dictionary:
	_ensure_services()
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
	return _fail("当前操作不支持地块槽位")


func can_use_action(action: String) -> bool:
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return false
	if editor_unlimited_actions_enabled() and action in [Constants.ACTION_MOVE, Constants.ACTION_ATTACK]:
		return true
	if OverloadRules.blocks_player_manual_actions(state) and action != Constants.ACTION_END_TURN:
		return false
	match action:
		Constants.ACTION_MOVE:
			return not state.player_moved or StatusRules.has_extra_move(state.get_player())
		Constants.ACTION_ATTACK:
			var player := state.get_player()
			return player != null \
				and StatusRules.can_attack(player) \
				and (not state.player_acted or StatusRules.has_extra_attack(player))
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
	_ensure_services()
	_turn_svc.begin_enemy_phase()


func execute_single_enemy(enemy: UnitState) -> Dictionary:
	_ensure_services()
	return _turn_svc.execute_single_enemy(enemy)


func finish_enemy_phase() -> Dictionary:
	_ensure_services()
	return _turn_svc.finish_enemy_phase()


func get_sorted_enemies() -> Array:
	_ensure_services()
	return _turn_svc.get_sorted_enemies()


# ═══════════════════════════════════════════════════════════════════════════
# UI 查询（委托 BattleQueryService）
# ═══════════════════════════════════════════════════════════════════════════

func get_highlights(hover_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	_ensure_services()
	return _query_svc.get_highlights(hover_cell)


func get_cell_preview(cell: Vector2i) -> Dictionary:
	_ensure_services()
	return _query_svc.get_cell_preview(cell)


func get_action_hint() -> String:
	_ensure_services()
	return _query_svc.get_action_hint()


func get_tutorial_hint() -> String:
	_ensure_services()
	return _query_svc.get_tutorial_hint()


# ═══════════════════════════════════════════════════════════════════════════
# 编辑器 CLI（委托 BattleEditorCli）
# ═══════════════════════════════════════════════════════════════════════════

func run_editor_command(raw_command: String) -> Dictionary:
	if not _editor_available():
		return {"ok": false, "message": "battle editor is only available in debug mode"}
	_ensure_services()
	return _editor_cli.run(raw_command)


func run_editor_action(command_id: String, payload: Dictionary = {}) -> Dictionary:
	if not _editor_available():
		return {"ok": false, "message": "battle editor is only available in debug mode"}
	_ensure_services()
	return _editor_svc.execute(command_id, payload)


func _editor_available() -> bool:
	var settings: Node = Engine.get_main_loop().root.get_node_or_null("SettingsService")
	if settings != null:
		return OS.is_debug_build() and bool(settings.get_value("battle_editor_enabled"))
	return OS.is_debug_build()


func editor_unlimited_actions_enabled() -> bool:
	return editor_unlimited_actions and _editor_available()


func player_move_budget(player: UnitState) -> int:
	if player == null:
		return 0
	if editor_unlimited_actions_enabled():
		return Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	return player.move_points


# ═══════════════════════════════════════════════════════════════════════════
# 内部方法（供各 service 回调）
# ═══════════════════════════════════════════════════════════════════════════

func _check_battle_end() -> void:
	_ensure_services()
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
