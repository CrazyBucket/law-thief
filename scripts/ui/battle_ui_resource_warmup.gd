extends Node

const IntentIcons := preload("res://scripts/ui/intent_icons.gd")
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_scene.tscn"

const INTENT_TYPES: Array[String] = [
	"move", "melee_attack", "ranged_attack", "wait",
	"bomb_rat_plunder_wait", "bomb_rat_plunder_steal", "black_suicide",
	"explosion_attack", "charge_explode", "arc_attack", "poison_attack",
	"fire_attack", "ice_attack", "pull", "split_attack", "light_beam",
	"slam_attack", "trample", "lawless_attack", "lawless_move",
	"lawless_extract", "extract",
]

var _next_icon_index := 0
var _delay_frames := 2
var _scene_prefetch_started := false


func _ready() -> void:
	name = "BattleUiResourceWarmup"


func _process(_delta: float) -> void:
	if _delay_frames > 0:
		_delay_frames -= 1
		return
	if not _scene_prefetch_started:
		_scene_prefetch_started = true
		if DisplayServer.get_name() != "headless":
			var transition_manager := get_node_or_null("/root/TransitionManager")
			if transition_manager != null:
				transition_manager.call("prefetch_scene", BATTLE_SCENE_PATH)
	if _next_icon_index >= INTENT_TYPES.size():
		set_process(false)
		queue_free()
		return
	IntentIcons.get_icon(INTENT_TYPES[_next_icon_index])
	_next_icon_index += 1
