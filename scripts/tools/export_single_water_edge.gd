extends SceneTree

const WaterLayerClass := preload("res://scripts/map/water_layer.gd")

const OUTPUT := "/tmp/law_thief_single_edge.png"


func _initialize() -> void:
	var top_sheet := Image.load_from_file("res://assets/tiles/waterEdgeTop.generated.png")
	var right_sheet := Image.load_from_file("res://assets/tiles/waterEdgeRight.generated.png")
	if top_sheet == null or right_sheet == null:
		push_error("failed to load water edge sheets")
		quit(1)
		return
	var composed := WaterLayerClass.compose_edge_image(top_sheet, right_sheet, Vector4i(5, 5, 5, 5))
	var error := composed.save_png(OUTPUT)
	if error != OK:
		push_error("failed to save single water edge")
		quit(1)
		return
	print("EXPORT_SINGLE_WATER_EDGE_PASS %s" % OUTPUT)
	quit()
