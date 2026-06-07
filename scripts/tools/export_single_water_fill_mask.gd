extends SceneTree

const WaterLayerClass := preload("res://scripts/map/water_layer.gd")

const OUTPUT := "/tmp/law_thief_single_fill_mask.png"


func _initialize() -> void:
	var top_sheet := Image.load_from_file("res://assets/tiles/waterMaskTop.generated.png")
	var right_sheet := Image.load_from_file("res://assets/tiles/waterMaskRight.generated.png")
	if top_sheet == null or right_sheet == null:
		push_error("failed to load water mask sheets")
		quit(1)
		return
	var image := WaterLayerClass.compose_fill_image(top_sheet, right_sheet, Vector4i(5, 5, 5, 5))
	var error := image.save_png(OUTPUT)
	if error != OK:
		push_error("failed to save single water fill mask")
		quit(1)
		return
	print("EXPORT_SINGLE_WATER_FILL_MASK_PASS %s" % OUTPUT)
	quit()
