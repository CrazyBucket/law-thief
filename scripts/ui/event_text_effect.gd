class_name EventTextEffect
extends RichTextEffect

var bbcode := "event_fx"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var kind := str(char_fx.env.get("kind", "accent"))
	var target := _color_for_kind(kind)
	var phase := char_fx.elapsed_time * _speed_for_kind(kind) + float(char_fx.relative_index) * 0.42
	var pulse := sin(phase) * 0.5 + 0.5
	char_fx.color = char_fx.color.lerp(target, 0.48 + pulse * 0.24)
	char_fx.offset.y += sin(phase * 0.78) * _motion_for_kind(kind)
	return true


func _color_for_kind(kind: String) -> Color:
	match kind:
		"gold":
			return Color("#f2cf6b")
		"danger":
			return Color("#e36c76")
		"heal":
			return Color("#72d98a")
		"cost":
			return Color("#d59a74")
		"arcane":
			return Color("#b9a0e8")
	return Color("#ddd6e9")


func _speed_for_kind(kind: String) -> float:
	return 2.2 if kind in ["danger", "gold"] else 1.55


func _motion_for_kind(kind: String) -> float:
	return 0.7 if kind in ["danger", "gold"] else 0.42
