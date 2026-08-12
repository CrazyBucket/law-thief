class_name BattleBoardAnimationState
extends RefCounted

var pulse_time: float = 0.0
var move_offsets: Dictionary = {}
var move_path_segments: Dictionary = {}
var move_path_segment_facings: Dictionary = {}
var strike_elapsed: Dictionary = {}
var hit_elapsed: Dictionary = {}
var walk_phase: Dictionary = {}
var idle_phase: Dictionary = {}
var parallel_move_remaining: int = 0
var held_gem_visual: Dictionary = {}
var hooked_gem_visual: Dictionary = {}
var inserting_gem_visuals: Array[Dictionary] = []
var masked_embedded_gems: Dictionary = {}


func clear_state_runtime() -> void:
	move_offsets.clear()
	move_path_segments.clear()
	move_path_segment_facings.clear()
	walk_phase.clear()
	idle_phase.clear()
	strike_elapsed.clear()
	hit_elapsed.clear()


func clear_gem_visuals() -> void:
	held_gem_visual.clear()
	hooked_gem_visual.clear()
	inserting_gem_visuals.clear()
	masked_embedded_gems.clear()
