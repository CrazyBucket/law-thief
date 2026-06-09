extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run State Round Trip Test ===")
	var run := RunState.create(11, 22)
	run.resources = {"gold": 17}
	run.resource_ledger = [{"resource_id": "gold", "after": 17}]
	run.room_states = {
		"chapter_1:0_0": {
			"status": "RESOLVED",
			"room_type": "REST_SITE",
			"snapshot": {},
			"transactions": [{"transaction_id": "chapter_1:0_0:resolve"}],
			"result": {"summary": "ok"},
		}
	}
	run.run_phase = "ROOM"
	run.pending_decision = {"type": "room", "room_id": "chapter_1:0_0"}
	var restored := RunState.from_dict(run.export_dict())
	assert(int(restored.resources.get("gold", 0)) == 17, "gold should round-trip")
	assert(str(restored.run_phase) == "ROOM", "run_phase should round-trip")
	assert(str(restored.pending_decision.get("room_id", "")) == "chapter_1:0_0", "pending decision should round-trip")
	assert(str(restored.room_states.get("chapter_1:0_0", {}).get("status", "")) == "RESOLVED", "room state should round-trip")

	var legacy := RunState.from_dict({
		"master_seed": 1,
		"map_seed": 2,
		"resolved_rooms": {
			"3_4": {
				"room_type": "EVENT",
				"summary": "legacy",
			}
		},
	})
	assert(str(legacy.room_states.get("3_4", {}).get("status", "")) == "RESOLVED", "legacy resolved rooms should migrate to room_states")
	print("RUN_STATE_ROUND_TRIP_TEST_PASS")
	quit()
