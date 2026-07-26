class_name BattlePresentationPlanner
extends RefCounted

## 战斗事件在进入 renderer 前必须先编译为 beat。
## 每个 beat 都显式声明串行/并发策略，以及 visual / impact / aftermath 边界。

const MODE_SERIAL := "serial"
const MODE_PARALLEL := "parallel"

## A beat's concurrency mode answers which visuals start together. Its barrier answers when
## the next causal beat may start; these are separate decisions.
const BARRIER_NONE := "none"
const BARRIER_IMPACT := "impact"
const BARRIER_COMPLETE := "complete"

const _POLICIES: Dictionary = {
	"projectile": {"kind": "projectile", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"projectile_deflect": {"kind": "projectile", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"explode": {"kind": "blast", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"light_beam": {"kind": "light_beam", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"arc": {"kind": "electrical", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"lightning": {"kind": "electrical", "mode": MODE_PARALLEL, "barrier": BARRIER_IMPACT},
	"damage": {"kind": "damage", "mode": MODE_PARALLEL, "barrier": BARRIER_NONE},
	"impact_charge": {"kind": "impact", "mode": MODE_PARALLEL, "barrier": BARRIER_COMPLETE},
	"move_step": {"kind": "move", "mode": "auto", "barrier": BARRIER_COMPLETE},
	"displacement_impact": {"kind": "move", "mode": "auto", "barrier": BARRIER_COMPLETE},
	"poison_burst": {"kind": "area_fx", "mode": MODE_PARALLEL, "barrier": BARRIER_NONE},
	"fire_burst": {"kind": "area_fx", "mode": MODE_PARALLEL, "barrier": BARRIER_NONE},
	"frost_pulse": {"kind": "area_fx", "mode": MODE_PARALLEL, "barrier": BARRIER_NONE},
	"split_spawn": {"kind": "split_spawn", "mode": MODE_PARALLEL, "barrier": BARRIER_NONE},
	"gem_flash": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"gem_transfer": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"miss": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"toxic_smoke": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"entity_destroyed": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"trample_start": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"die": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_COMPLETE},
	"spawn": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"transform": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"status": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"heal": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_NONE},
	"knockback": {"kind": "single", "mode": MODE_SERIAL, "barrier": BARRIER_COMPLETE},
}


static func build(events: Array) -> Dictionary:
	var beats: Array[Dictionary] = []
	var violations: Array[String] = []
	var i := 0
	while i < events.size():
		var event = events[i]
		if not event is Dictionary:
			violations.append("[%d] presentation event is not a Dictionary" % i)
			i += 1
			continue
		var event_type := str(event.get("type", ""))
		if not _POLICIES.has(event_type):
			violations.append(
				"[%d] event type '%s' has no presentation policy; declare serial/parallel behavior before playback"
				% [i, event_type]
			)
			beats.append(_single_beat(event, i))
			i += 1
			continue
		match str(_POLICIES[event_type].get("kind", "single")):
			"impact":
				var impact_result := _build_impact_beat(events, i)
				beats.append(impact_result.beat)
				i = impact_result.next_index
			"projectile":
				var projectile_result := _build_projectile_beat(events, i)
				beats.append(projectile_result.beat)
				i = projectile_result.next_index
			"blast":
				var blast_result := _build_blast_beat(events, i)
				beats.append(blast_result.beat)
				i = blast_result.next_index
			"light_beam":
				var beam_result := _build_visual_impact_beat(events, i, ["light_beam"], "light_beam")
				beats.append(beam_result.beat)
				i = beam_result.next_index
			"electrical":
				var electrical_result := _build_visual_impact_beat(events, i, ["arc", "lightning"], "electrical")
				beats.append(electrical_result.beat)
				i = electrical_result.next_index
			"damage":
				var damages := _collect_types(events, i, ["damage"])
				beats.append(_beat("damage", MODE_PARALLEL, [], damages.items, [], i, damages.next_index))
				i = damages.next_index
			"move":
				var moves := _collect_motion_beat(events, i)
				var move_mode := MODE_PARALLEL if _moves_are_parallel(moves.items) else MODE_SERIAL
				beats.append(_beat("move", move_mode, moves.items, [], [], i, moves.next_index))
				i = moves.next_index
			"area_fx":
				var area_fx := _collect_types(events, i, [event_type])
				beats.append(_beat("area_fx", MODE_PARALLEL, area_fx.items, [], [], i, area_fx.next_index))
				i = area_fx.next_index
			"split_spawn":
				var spawns := _collect_types(events, i, ["split_spawn"])
				beats.append(_beat("split_spawn", MODE_PARALLEL, spawns.items, [], [], i, spawns.next_index))
				i = spawns.next_index
			_:
				beats.append(_single_beat(event, i))
				i += 1
	return {"beats": beats, "violations": violations}


static func registered_event_types() -> Array[String]:
	var result: Array[String] = []
	for event_type in _POLICIES.keys():
		result.append(str(event_type))
	result.sort()
	return result


static func has_policy(event_type: String) -> bool:
	return _POLICIES.has(event_type)


static func policy_for(event_type: String) -> Dictionary:
	return (_POLICIES.get(event_type, {}) as Dictionary).duplicate(true)


static func _build_projectile_beat(events: Array, start: int) -> Dictionary:
	var visuals := _collect_types(events, start, ["projectile", "projectile_deflect"])
	var impacts := _collect_types(events, visuals.next_index, ["damage"])
	return {
		"beat": _beat("projectile", MODE_PARALLEL, visuals.items, impacts.items, [], start, impacts.next_index),
		"next_index": impacts.next_index,
	}


static func _build_impact_beat(events: Array, start: int) -> Dictionary:
	var charge: Dictionary = events[start]
	var charge_uid := str(charge.get("uid", ""))
	var charge_motions: Array = []
	var i := start + 1
	while i < events.size():
		var event_type := str(events[i].get("type", ""))
		if event_type not in ["move_step", "displacement_impact"] \
		or str(events[i].get("uid", "")) != charge_uid:
			break
		charge_motions.append(events[i])
		i += 1
	var impacts: Array = []
	while i < events.size() and str(events[i].get("type", "")) == "damage":
		impacts.append(events[i])
		i += 1
	var impact_motions: Array = []
	while i < events.size() and str(events[i].get("type", "")) in ["move_step", "displacement_impact"]:
		impact_motions.append(events[i])
		i += 1
	var beat := _beat("impact", MODE_PARALLEL, [charge], impacts, [], start, i, impact_motions)
	beat["charge_motions"] = charge_motions
	return {"beat": beat, "next_index": i}


static func _build_visual_impact_beat(
	events: Array,
	start: int,
	visual_types: Array,
	kind: String
) -> Dictionary:
	var visuals := _collect_types(events, start, visual_types)
	var impacts := _collect_types(events, visuals.next_index, ["damage"])
	return {
		"beat": _beat(kind, MODE_PARALLEL, visuals.items, impacts.items, [], start, impacts.next_index),
		"next_index": impacts.next_index,
	}


static func _build_blast_beat(events: Array, start: int) -> Dictionary:
	var visuals: Array = []
	var impacts: Array = []
	var impact_motions: Array = []
	var aftermath: Array = []
	var i := start
	while i < events.size():
		var event_type := str(events[i].get("type", ""))
		if event_type == "explode":
			visuals.append(events[i])
		elif event_type == "damage":
			impacts.append(events[i])
		elif event_type in ["move_step", "displacement_impact"]:
			impact_motions.append(events[i])
		elif event_type in ["poison_burst", "fire_burst", "frost_pulse", "split_spawn"]:
			aftermath.append(events[i])
		else:
			break
		i += 1
	return {
		"beat": _beat("blast", MODE_PARALLEL, visuals, impacts, aftermath, start, i, impact_motions),
		"next_index": i,
	}


static func _collect_types(events: Array, start: int, types: Array) -> Dictionary:
	var items: Array = []
	var i := start
	while i < events.size() and str(events[i].get("type", "")) in types:
		items.append(events[i])
		i += 1
	return {"items": items, "next_index": i}


static func _collect_motion_beat(events: Array, start: int) -> Dictionary:
	var items: Array = []
	var first: Dictionary = events[start]
	var first_forced := bool(first.get("forced", false)) \
		or str(first.get("type", "")) == "displacement_impact"
	var first_uid := str(first.get("uid", ""))
	var first_source_uid := str(first.get("source_uid", ""))
	var i := start
	while i < events.size():
		var event: Dictionary = events[i]
		var event_type := str(event.get("type", ""))
		if event_type not in ["move_step", "displacement_impact"]:
			break
		var event_forced := bool(event.get("forced", false)) or event_type == "displacement_impact"
		if event_forced != first_forced:
			break
		if first_forced:
			if str(event.get("source_uid", "")) != first_source_uid:
				break
		elif str(event.get("uid", "")) != first_uid:
			break
		items.append(event)
		i += 1
	return {"items": items, "next_index": i}


static func _moves_are_parallel(events: Array) -> bool:
	if events.size() <= 1:
		return false
	var first_uid := str(events[0].get("uid", ""))
	for event in events:
		if str(event.get("uid", "")) != first_uid:
			return true
	return false


static func _single_beat(event: Dictionary, index: int) -> Dictionary:
	return _beat("single", MODE_SERIAL, [event], [], [], index, index + 1)


static func _beat(
	kind: String,
	mode: String,
	visuals: Array,
	impacts: Array,
	aftermath: Array,
	start: int,
	next_index: int,
	impact_motions: Array = []
) -> Dictionary:
	var representative: Dictionary = {}
	if not visuals.is_empty():
		representative = visuals[0]
	elif not impacts.is_empty():
		representative = impacts[0]
	var event_type := str(representative.get("type", ""))
	var barrier := str(_POLICIES.get(event_type, {}).get("barrier", BARRIER_COMPLETE))
	if not impact_motions.is_empty():
		barrier = BARRIER_COMPLETE
	return {
		"kind": kind,
		"mode": mode,
		"barrier": barrier,
		"visuals": visuals,
		"impacts": impacts,
		"impact_motions": impact_motions,
		"aftermath": aftermath,
		"source_start": start,
		"source_end": next_index,
	}
