class_name EventTextFormatter
extends RefCounted

const KEYWORDS := [
	{"text": "永久销毁", "kind": "danger"},
	{"text": "鲜血", "kind": "danger"},
	{"text": "伤口", "kind": "danger"},
	{"text": "金币", "kind": "gold"},
	{"text": "宝石", "kind": "arcane"},
	{"text": "遗物", "kind": "arcane"},
	{"text": "治疗", "kind": "heal"},
	{"text": "恢复", "kind": "heal"},
]


static func body_bbcode(plain_text: String) -> String:
	var styled := _escape_bbcode(plain_text)
	for entry in KEYWORDS:
		var token := str(entry.get("text", ""))
		var kind := str(entry.get("kind", "accent"))
		styled = styled.replace(token, "[event_fx kind=%s]%s[/event_fx]" % [kind, token])
	return styled


static func result_bbcode(plain_text: String) -> String:
	var styled := _escape_bbcode(plain_text)
	styled = _replace_pattern(
		styled,
		"失去\\s*([0-9]+)\\s*HP",
		"[event_fx kind=danger]失去[/event_fx] [b][font_size=20][event_fx kind=danger]$1 HP[/event_fx][/font_size][/b]"
	)
	styled = _replace_pattern(
		styled,
		"恢复\\s*([0-9]+)\\s*HP",
		"[event_fx kind=heal]恢复[/event_fx] [b][font_size=20][event_fx kind=heal]$1 HP[/event_fx][/font_size][/b]"
	)
	styled = _replace_pattern(
		styled,
		"获得\\s*([0-9]+)\\s*金币",
		"[event_fx kind=gold]获得[/event_fx] [b][font_size=20][event_fx kind=gold]$1 金币[/event_fx][/font_size][/b]"
	)
	styled = _replace_pattern(
		styled,
		"支付\\s*([0-9]+)\\s*金币",
		"[event_fx kind=cost]支付[/event_fx] [b][font_size=20][event_fx kind=cost]$1 金币[/event_fx][/font_size][/b]"
	)
	return styled


static func _replace_pattern(source: String, pattern: String, replacement: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return source
	return regex.sub(source, replacement, true)


static func _escape_bbcode(source: String) -> String:
	return source.replace("[", "[lb]").replace("]", "[rb]")
