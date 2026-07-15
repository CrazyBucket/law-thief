extends SceneTree

const _Resolver = preload("res://scripts/services/encounter_enemy_resolver.gd")

var _domains: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var encounter := {
		"enemies": [{"def_id": "unit_fixed", "pos": Vector2i(1, 1)}],
		"enemy_groups": [{
			"weight": 2.0,
			"enemies": [{"def_id": "unit_group", "pos": Vector2i(2, 1)}],
		}],
		"random_enemies": [{
			"pos": Vector2i(3, 1),
			"candidates": ["unit_string", {"def_id": "unit_weighted", "weight": 3.0}],
		}],
	}
	var resolved := _Resolver.resolve(encounter, "resolver_fixture", Callable(self, "_pick_last"))
	assert(resolved.size() == 3)
	assert(str(resolved[0].get("def_id", "")) == "unit_fixed")
	assert(str(resolved[1].get("def_id", "")) == "unit_group")
	assert(str(resolved[2].get("def_id", "")) == "unit_weighted")
	assert(resolved[2].get("pos", Vector2i.ZERO) == Vector2i(3, 1))
	assert(not resolved[2].has("weight"))
	assert(_domains == ["encounter_group_resolver_fixture", "encounter_random_enemy_resolver_fixture_0"])
	resolved[0]["def_id"] = "mutated"
	assert(str((encounter["enemies"] as Array)[0].get("def_id", "")) == "unit_fixed")
	print("ENCOUNTER_ENEMY_RESOLVER_TEST_PASS")
	quit()


func _pick_last(domain: String, candidates: Array, _weights: Array) -> Variant:
	_domains.append(domain)
	return candidates[candidates.size() - 1] if not candidates.is_empty() else null
