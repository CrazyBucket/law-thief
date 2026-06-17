extends SceneTree


class DummyBoard:
	var explosions: Array = []
	var flashes: Array = []
	var redraw_count: int = 0

	func play_explosion(pos: Vector2i) -> void:
		explosions.append(pos)

	func play_gem_flash(pos: Vector2i, _gem_color: Color) -> void:
		flashes.append(pos)

	func queue_redraw() -> void:
		redraw_count += 1


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Battle Event Player Cluster Test ===")
	var host := Node.new()
	root.add_child(host)
	var board := DummyBoard.new()
	var player := BattleEventPlayer.new()
	player.setup(host, board, null, Callable(), func(_seconds: float) -> float: return 0.0)
	await player.play_events([
		{"type": "explode", "pos": Vector2i(4, 4)},
		{"type": "split_spawn", "pos": Vector2i(4, 5), "uid": "missing_clone"},
	])
	assert(board.explosions.size() == 1, "blast cluster should play the explosion")
	assert(board.flashes.size() == 1, "split spawn should be presented inside the blast cluster")
	assert(board.flashes[0] == Vector2i(4, 5), "split spawn flash should use the clone position")
	host.queue_free()
	print("BATTLE_EVENT_PLAYER_CLUSTER_TEST_PASS")
	quit()
