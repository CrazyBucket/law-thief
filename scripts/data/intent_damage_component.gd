class_name IntentDamageComponent
extends RefCounted

const CERTAINTY_DETERMINISTIC := "deterministic"
const CERTAINTY_CONDITIONAL := "conditional"

var source: String = "direct"
var damage_per_hit: int = 0
var instance_count: int = 1
# One entry represents one predicted damage application. Uids may repeat across beams or blasts.
var target_uids: Array[String] = []
var affected_cells: Array[Vector2i] = []
var certainty: String = CERTAINTY_DETERMINISTIC


static func create(
	p_source: String,
	p_damage_per_hit: int,
	p_instance_count: int = 1,
	p_target_uids: Array = [],
	p_affected_cells: Array = [],
	p_certainty: String = CERTAINTY_DETERMINISTIC
) -> IntentDamageComponent:
	var component := IntentDamageComponent.new()
	component.source = p_source
	component.damage_per_hit = maxi(0, p_damage_per_hit)
	component.instance_count = maxi(0, p_instance_count)
	for uid in p_target_uids:
		component.target_uids.append(str(uid))
	for cell in p_affected_cells:
		if cell is Vector2i:
			component.affected_cells.append(cell)
	component.certainty = p_certainty
	return component


func clone() -> IntentDamageComponent:
	return create(source, damage_per_hit, instance_count, target_uids, affected_cells, certainty)


func predicted_raw_damage() -> int:
	return damage_per_hit * target_uids.size()


func predicted_raw_damage_to(target_uid: String) -> int:
	return damage_per_hit * target_uids.count(target_uid)


func to_dict() -> Dictionary:
	return {
		"source": source,
		"damage_per_hit": damage_per_hit,
		"instance_count": instance_count,
		"target_uids": target_uids.duplicate(),
		"affected_cells": affected_cells.duplicate(),
		"certainty": certainty,
		"predicted_raw_damage": predicted_raw_damage(),
	}
