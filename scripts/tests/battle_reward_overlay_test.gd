extends SceneTree

const _Overlay = preload("res://scripts/ui/battle_reward_overlay.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var layout := {
		"fallback_viewport_width": 200.0,
		"scroll_viewport_ratio": 0.5,
		"scroll_max_width": 150.0,
		"scroll_edge_pad": 4.0,
		"scroll_hover_pad": 12.0,
		"scroll_bar_reserve": 6.0,
		"card_separation": 10.0,
		"action_button_width": 72.0,
		"action_button_height": 28.0,
		"content_separation": 8,
	}
	var host := Control.new()
	var cards_row := HBoxContainer.new()
	cards_row.add_child(_card(Vector2(100, 50)))
	cards_row.add_child(_card(Vector2(100, 50)))

	var metrics := _Overlay.scroll_metrics(host, cards_row, layout)
	assert(bool(metrics.get("needs_horizontal_scroll", false)))
	assert(is_equal_approx(float(metrics.get("width", 0.0)), 100.0))
	assert(metrics.get("size", Vector2.ZERO) == Vector2(100, 68))

	var scroll := _Overlay.wrap_cards_scroll(cards_row, layout, metrics)
	assert(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	assert(scroll.get_child_count() == 1)

	var action := _Overlay.build_action_button(layout, "跳过", Callable(self, "_no_op"), 100.0)
	var button := action.get_child(0) as Button
	assert(button.text == "跳过")
	assert(button.custom_minimum_size == Vector2(72, 28))

	var shell := _Overlay.begin_shell(layout, 7)
	var canvas := shell.get("canvas", null) as CanvasLayer
	assert(canvas != null and canvas.layer == 7)
	assert(shell.get("vbox", null) is VBoxContainer)
	canvas.free()
	action.free()
	scroll.free()
	host.free()
	print("BATTLE_REWARD_OVERLAY_TEST_PASS")
	quit()


func _card(size: Vector2) -> Control:
	var card := Control.new()
	card.custom_minimum_size = size
	return card


func _no_op() -> void:
	pass
