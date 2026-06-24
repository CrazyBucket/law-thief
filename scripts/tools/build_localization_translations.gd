extends SceneTree

const CSV_PATH := "res://localization/strings.csv"
const LOCALES := {
	"zh_CN": 1,
	"en_US": 2,
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert(file != null, "localization csv should open")
	var translations := {}
	for locale in LOCALES.keys():
		var translation := Translation.new()
		translation.locale = locale
		translations[locale] = translation
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3 or str(row[0]).is_empty():
			continue
		var key := str(row[0])
		for locale in LOCALES.keys():
			var column: int = LOCALES[locale]
			(translations[locale] as Translation).add_message(key, str(row[column]))
	for locale in translations.keys():
		var path := "res://localization/strings.%s.translation" % locale
		var err := ResourceSaver.save(translations[locale], path)
		assert(err == OK, "translation should save: %s err=%d" % [path, err])
		print("LOCALIZATION_TRANSLATION_BUILT %s" % path)
	quit(0)
