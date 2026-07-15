class_name BattleRewardUiConfigValidator
extends RefCounted


static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var settlement_keys := [
		"canvas_layer", "panel_width", "panel_margin", "content_separation", "row_separation",
		"row_width", "row_height", "row_action_width", "row_action_height",
		"continue_button_width", "continue_button_height",
	]
	var reward_overlay_keys := [
		"canvas_layer", "content_separation", "card_separation", "scroll_max_width",
		"scroll_viewport_ratio", "scroll_hover_pad", "scroll_bar_reserve", "scroll_edge_pad",
		"action_button_width", "action_button_height", "fallback_viewport_width",
	]
	var card_kinds := {
		"relic": ["width", "height", "desc_width", "desc_height", "icon_size", "pick_button_height"],
		"gem": ["width", "height", "icon_size", "pick_button_height"],
		"dropped_gem": ["width", "height", "icon_size", "pick_button_height"],
		"slot_embed": ["width", "height", "pick_button_height"],
	}
	errors.append_array(_validate_layout_section(config, "settlement", settlement_keys))
	errors.append_array(_validate_layout_section(config, "reward_overlay", reward_overlay_keys))
	var cards: Variant = config.get("cards", {})
	if not cards is Dictionary:
		errors.append("battle_reward_ui_config.cards should be object")
	else:
		for card_kind in card_kinds.keys():
			var prefix := "battle_reward_ui_config.cards.%s" % str(card_kind)
			var raw_card: Variant = (cards as Dictionary).get(card_kind, null)
			if not raw_card is Dictionary:
				errors.append("%s missing" % prefix)
				continue
			for key in card_kinds[card_kind]:
				var field_prefix := "%s.%s" % [prefix, str(key)]
				var raw_value: Variant = (raw_card as Dictionary).get(key, null)
				if raw_value == null:
					errors.append("%s missing" % field_prefix)
				else:
					errors.append_array(_validate_positive_number(field_prefix, raw_value))
	var ratio_section: Variant = config.get("reward_overlay", null)
	if ratio_section is Dictionary:
		var ratio_value: Variant = (ratio_section as Dictionary).get("scroll_viewport_ratio", null)
		if ratio_value is int or ratio_value is float:
			var ratio := float(ratio_value)
			if ratio <= 0.0 or ratio > 1.0:
				errors.append("battle_reward_ui_config.reward_overlay.scroll_viewport_ratio should be in (0, 1]")
	return errors


static func _validate_layout_section(config: Dictionary, section: String, keys: Array) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "battle_reward_ui_config.%s" % section
	var raw_section: Variant = config.get(section, null)
	if not raw_section is Dictionary:
		errors.append("%s missing" % prefix)
		return errors
	var section_dict := raw_section as Dictionary
	for key in keys:
		var field_prefix := "%s.%s" % [prefix, str(key)]
		if not section_dict.has(key):
			errors.append("%s missing" % field_prefix)
		else:
			errors.append_array(_validate_positive_number(field_prefix, section_dict[key]))
	return errors


static func _validate_positive_number(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is int and not value is float:
		errors.append("%s should be number" % prefix)
	elif float(value) <= 0.0:
		errors.append("%s should be positive" % prefix)
	return errors
