extends SceneTree

const CRITICAL_SCRIPTS: Array[String] = [
	"res://scripts/ui/battle_scene.gd",
	"res://scripts/ui/adventure_map_scene.gd",
	"res://scripts/ui/isometric_board.gd",
	"res://scripts/main/main_root.gd",
]

const CRITICAL_SCENES: Array[String] = [
	"res://scenes/battle/battle_scene.tscn",
	"res://scenes/map/adventure_map.tscn",
]

const OPERATOR_SCAN_DIRS: Array[String] = [
	"res://scripts/ui",
	"res://scripts/main",
	"res://scripts/battle",
	"res://scripts/services",
	"res://scripts/rules",
]

var _failed := false
var _scene_queue: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== UI Compile Test ===")
	for path in CRITICAL_SCRIPTS:
		_check_script(path)
		if _failed:
			quit(1)
			return
	_check_invalid_operators()
	if _failed:
		quit(1)
		return
	_scene_queue = CRITICAL_SCENES.duplicate()
	_boot_next_scene()


func _check_script(path: String) -> void:
	var res: Resource = load(path)
	if res == null:
		_fail("script load returned null: %s" % path)
		return
	if res is GDScript:
		var err: Error = (res as GDScript).reload()
		if err != OK:
			_fail("script compile error (%d): %s" % [err, path])
			return
	print("  [OK] script %s" % path)


func _boot_next_scene() -> void:
	if _failed:
		quit(1)
		return
	if _scene_queue.is_empty():
		print("UI_COMPILE_TEST_PASS")
		quit(0)
		return
	var path: String = _scene_queue.pop_front()
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_fail("scene load returned null: %s" % path)
		_boot_next_scene()
		return
	var node: Node = packed.instantiate()
	if node == null:
		_fail("scene instantiate failed: %s" % path)
		_boot_next_scene()
		return
	root.add_child(node)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.one_shot = true
	timer.timeout.connect(func() -> void:
		_validate_scene(path, node)
		node.queue_free()
		timer.queue_free()
		_boot_next_scene()
	)
	root.add_child(timer)
	timer.start()


func _validate_scene(path: String, node: Node) -> void:
	if node.get_script() == null:
		_fail("scene root has no script: %s" % path)
		return
	match path:
		"res://scenes/battle/battle_scene.tscn":
			if not node.has_node("BoardLayer/IsometricBoard"):
				_fail("battle scene missing IsometricBoard")
				return
			if not node.has_node("HudLayer/StatusPanel/VBox/HeaderRow/Info/ShieldRow"):
				_fail("battle scene missing ShieldRow")
				return
		"res://scenes/map/adventure_map.tscn":
			if not node.has_node("BoardLayer/IsometricBoard"):
				_fail("adventure map missing IsometricBoard")
				return
	print("  [OK] scene boot %s" % path)


func _check_invalid_operators() -> void:
	for dir_path in OPERATOR_SCAN_DIRS:
		_scan_gd_scripts(dir_path)
		if _failed:
			return
	print("  [OK] no invalid ===/!== operators")


func _scan_gd_scripts(dir_path: String) -> void:
	if _failed:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_gd_scripts(full)
			continue
		if not entry.ends_with(".gd"):
			continue
		_scan_file_operators(full)
	dir.list_dir_end()


func _scan_file_operators(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var lines: PackedStringArray = file.get_as_text().split("\n")
	for i in range(lines.size()):
		var line: String = lines[i].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if _line_has_invalid_operator(line):
			_fail("invalid JS operator in %s:%d -> %s" % [path, i + 1, line])
			return


func _line_has_invalid_operator(line: String) -> bool:
	var code := _strip_string_literals(line)
	return code.contains("!==") or code.contains("===")


func _strip_string_literals(line: String) -> String:
	var result := ""
	var in_string := false
	var i := 0
	while i < line.length():
		var ch: String = line.substr(i, 1)
		if ch == "\"":
			in_string = not in_string
			i += 1
			continue
		if not in_string:
			result += ch
		i += 1
	return result


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
