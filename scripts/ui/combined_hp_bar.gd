class_name CombinedHpBar
extends Control

var _hp := 0
var _max_hp := 1
var _shield := 0


func set_values(hp: int, max_hp: int, shield: int) -> void:
	_hp = hp
	_max_hp = maxi(max_hp, 1)
	_shield = maxi(shield, 0)
	queue_redraw()


func _draw() -> void:
	BattleUiTheme.draw_combined_hp_bar(self, Rect2(Vector2.ZERO, size), _hp, _max_hp, _shield)
