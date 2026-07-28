class_name StatusConfigValidator
extends RefCounted

const ENTRY_KEYS := {
	"poison": true,
	"burning": true,
	"armor": true,
	"shield": true,
	"rooted": true,
	"exposed": true,
	"lawless": true,
	"bomb_rat_plunder": true,
	"paralyzed": true,
	"frozen": true,
	"slowed": true,
	"wet": true,
	"sluggish": true,
	"vulnerable": true,
	"disarmed": true,
	"weak": true,
	"light_exposed": true,
	"blinded": true,
	"counter_mark": true,
	"extra_attack": true,
	"extra_move": true,
}

const FIELD_KEYS := {
	"default_stacks": true,
	"default_duration": true,
	"damage_taken_mult": true,
	"attack_damage_mult": true,
	"min_move_points": true,
	"firelike_stack_mult": true,
	"attack_bonus": true,
}


static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for required_entry_id in ENTRY_KEYS.keys():
		if not config.has(required_entry_id):
			errors.append("status_config.%s missing" % required_entry_id)
	for entry_id in config.keys():
		if not ENTRY_KEYS.has(str(entry_id)):
			errors.append("status_config.%s is unknown" % str(entry_id))
			continue
		var entry: Variant = config[entry_id]
		if not entry is Dictionary:
			errors.append("status_config.%s should be object" % str(entry_id))
			continue
		for field_id in (entry as Dictionary).keys():
			var key_id := str(field_id)
			if not FIELD_KEYS.has(key_id):
				errors.append("status_config.%s.%s is unknown" % [str(entry_id), key_id])
				continue
			if not _is_number((entry as Dictionary)[field_id]):
				errors.append("status_config.%s.%s should be number" % [str(entry_id), key_id])
		for required_field_id in ["default_stacks", "default_duration"]:
			if not (entry as Dictionary).has(required_field_id):
				errors.append("status_config.%s.%s missing" % [str(entry_id), required_field_id])
		var extra_required_fields: Array = []
		match str(entry_id):
			"burning":
				extra_required_fields = ["firelike_stack_mult"]
			"slowed":
				extra_required_fields = ["min_move_points"]
			"vulnerable":
				extra_required_fields = ["damage_taken_mult"]
			"frozen":
				extra_required_fields = ["damage_taken_mult"]
			"weak":
				extra_required_fields = ["attack_damage_mult"]
			"lawless":
				extra_required_fields = ["attack_bonus"]
		for required_field_id in extra_required_fields:
			if not (entry as Dictionary).has(required_field_id):
				errors.append("status_config.%s.%s missing" % [str(entry_id), required_field_id])
		for integer_field_id in ["default_stacks", "default_duration", "min_move_points", "attack_bonus"]:
			if not (entry as Dictionary).has(integer_field_id):
				continue
			var integer_value: Variant = (entry as Dictionary)[integer_field_id]
			if _is_number(integer_value) and not _is_non_negative_integer(integer_value):
				errors.append("status_config.%s.%s should be a non-negative integer" % [str(entry_id), integer_field_id])
		for multiplier_field_id in ["firelike_stack_mult", "damage_taken_mult", "attack_damage_mult"]:
			if not (entry as Dictionary).has(multiplier_field_id):
				continue
			var multiplier: Variant = (entry as Dictionary)[multiplier_field_id]
			if _is_number(multiplier) and float(multiplier) <= 0.0:
				errors.append("status_config.%s.%s should be positive" % [str(entry_id), multiplier_field_id])
	return errors


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_non_negative_integer(value: Variant) -> bool:
	return _is_number(value) and int(value) == float(value) and int(value) >= 0
