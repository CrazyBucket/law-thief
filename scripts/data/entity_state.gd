class_name EntityState
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")

var uid: String = ""
var entity_id: String = ""
var pos: Vector2i = Vector2i.ZERO
var prop_sprite: String = ""
var hp: int = -1        # -1 表示无敌（石块）
var max_hp: int = -1
var alive: bool = true

## 实体固有属性标签（由 entity_id 决定）
var tags: Array[String] = []


static func create(uid: String, entity_id: String, pos: Vector2i) -> EntityState:
	var e := EntityState.new()
	e.uid = uid
	e.entity_id = entity_id
	e.pos = pos
	e._init_from_def()
	return e


func _init_from_def() -> void:
	match entity_id:
		Constants.ENTITY_ROCK, Constants.ENTITY_PROP:
			hp = -1
			max_hp = -1
			tags = ["blocks_move", "blocks_projectile", "indestructible"]
		Constants.ENTITY_SPIKE:
			hp = -1
			max_hp = -1
			tags = ["hazard"]
		Constants.ENTITY_BARREL:
			hp = CombatConfig.barrel_hp()
			max_hp = CombatConfig.barrel_hp()
			tags = ["blocks_move", "blocks_projectile", "destructible", "explosive", "flammable"]


func is_indestructible() -> bool:
	return "indestructible" in tags


func blocks_movement() -> bool:
	return "blocks_move" in tags


func blocks_projectile() -> bool:
	return "blocks_projectile" in tags


func has_tag(tag: String) -> bool:
	return tag in tags


func take_damage(amount: int) -> int:
	if is_indestructible() or not alive or amount <= 0:
		return 0
	hp -= amount
	if hp <= 0:
		hp = 0
		alive = false
	return amount


func clone() -> EntityState:
	var entity := EntityState.new()
	entity.uid = uid
	entity.entity_id = entity_id
	entity.pos = pos
	entity.prop_sprite = prop_sprite
	entity.hp = hp
	entity.max_hp = max_hp
	entity.alive = alive
	entity.tags = tags.duplicate()
	return entity
