class_name StateDiff
extends RefCounted


static func between(before: Dictionary, after: Dictionary) -> Dictionary:
	return {
		"units": _collection_diff(before.get("units", []), after.get("units", []), "uid"),
		"gems": _collection_diff(before.get("gems", []), after.get("gems", []), "uid"),
		"tiles": _collection_diff(before.get("tiles", []), after.get("tiles", []), "pos"),
		"entities": _collection_diff(before.get("entities", []), after.get("entities", []), "uid"),
		"result": _value_diff(before.get("result"), after.get("result")),
	}


static func _collection_diff(before: Array, after: Array, id_field: String) -> Dictionary:
	var before_by_id := _index(before, id_field)
	var after_by_id := _index(after, id_field)
	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	var ids := before_by_id.keys()
	for id in after_by_id.keys():
		if id not in ids:
			ids.append(id)
	ids.sort()
	for id in ids:
		if not before_by_id.has(id):
			added.append(after_by_id[id])
		elif not after_by_id.has(id):
			removed.append(before_by_id[id])
		elif before_by_id[id] != after_by_id[id]:
			changed.append({
				"id": id,
				"before": before_by_id[id],
				"after": after_by_id[id],
			})
	return {"added": added, "removed": removed, "changed": changed}


static func _index(items: Array, id_field: String) -> Dictionary:
	var out := {}
	for item: Dictionary in items:
		out[_stable_id(item.get(id_field))] = item
	return out


static func _stable_id(value: Variant) -> String:
	if value is Dictionary:
		return JSON.stringify(value)
	return str(value)


static func _value_diff(before: Variant, after: Variant) -> Variant:
	if before == after:
		return null
	return {"before": before, "after": after}
