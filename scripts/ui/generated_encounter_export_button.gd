class_name GeneratedEncounterExportButton
extends Button

var _controller: BattleController = null
var _export_path := ""


func _init() -> void:
	text = "导出地图"
	tooltip_text = "保存本场初始布局"
	custom_minimum_size = Vector2(88, 30)
	visible = false
	pressed.connect(_on_pressed)


func setup(controller: BattleController) -> void:
	_controller = controller
	sync_for_state(controller.state if controller != null else null)


func sync_for_state(state: GameState) -> void:
	visible = OS.is_debug_build() and state != null and not state.generated_encounter_blueprint.is_empty()
	disabled = not visible
	if _export_path.is_empty():
		text = "导出地图"
		tooltip_text = "保存本场初始布局"


func last_export_path() -> String:
	return _export_path


func _on_pressed() -> void:
	if _controller == null or _controller.state == null:
		return
	var result := _controller.run_editor_action("export_encounter", {"generated": true})
	if bool(result.get("ok", false)):
		_export_path = str(result.get("export_path", ""))
		text = "已导出"
		tooltip_text = _export_path
	else:
		text = "导出失败"
		tooltip_text = str(result.get("reason", "无法保存地图"))
