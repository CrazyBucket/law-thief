class_name PersistencePathPolicy
extends RefCounted

const SAVE_ROOT_ENV := "LAW_THIEF_SAVE_ROOT"
const DEFAULT_SETTINGS_PATH := "user://settings.json"
const AUTOMATION_ROOT := "res://artifacts/verify/userdata/standalone"


static func save_root() -> String:
	return resolve_save_root(
		OS.get_environment(SAVE_ROOT_ENV),
		OS.get_cmdline_args(),
		OS.get_process_id()
	)


static func settings_path() -> String:
	var root := save_root()
	return DEFAULT_SETTINGS_PATH if root.is_empty() else _join_path(root, "settings.json")


static func resolve_save_root(explicit_root: String, args: PackedStringArray, process_id: int) -> String:
	var normalized_explicit := _normalize_root(explicit_root)
	if not normalized_explicit.is_empty():
		return normalized_explicit
	var script_path := script_path_from_args(args)
	if not is_automation_script(script_path):
		return ""
	var scope := script_path.get_file().get_basename().replace("-", "_")
	var sandbox := "%s/%s_%d/save" % [AUTOMATION_ROOT, scope, process_id]
	return ProjectSettings.globalize_path(sandbox)


static func script_path_from_args(args: PackedStringArray) -> String:
	for index in range(args.size()):
		var argument := str(args[index])
		if argument == "--script" and index + 1 < args.size():
			return str(args[index + 1]).replace("\\", "/")
		if argument.begins_with("--script="):
			return argument.trim_prefix("--script=").replace("\\", "/")
	return ""


static func is_automation_script(script_path: String) -> bool:
	var normalized := script_path.replace("\\", "/")
	return (
		normalized.begins_with("res://scripts/tests/")
		or normalized.begins_with("res://scripts/tools/")
		or normalized.contains("/scripts/tests/")
		or normalized.contains("/scripts/tools/")
	)


static func _normalize_root(path: String) -> String:
	return path.strip_edges().trim_suffix("/").trim_suffix("\\")


static func _join_path(base_path: String, relative_path: String) -> String:
	var normalized_base := _normalize_root(base_path)
	if normalized_base.is_empty():
		return relative_path
	return "%s/%s" % [normalized_base, relative_path.trim_prefix("/").trim_prefix("\\")]
