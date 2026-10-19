extends SceneTree
## Screenshots of the roof tab, custom roof editor and the generator: SHOT_DIR=... xvfb-run -a godot --path . --script res://tools/roof_types_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 10: await process_frame
	main.settings.reset_all()
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 8: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	main.panel.select_tab("roof", true)
	main.settings.set_value("model_roof_type", "custom")
	for _i in 6: await process_frame
	main.roofed.open_custom()
	for _i in 10: await process_frame
	var ed: RoofCustomEditor = main.roofed.window.find_children("*", "RoofCustomEditor", true, false)[0]
	ed.slopes[0] = -1.0
	ed.sel = 1
	ed._changed()
	for _i in 30: await process_frame
	root.get_texture().get_image().save_png(out.path_join("custom_roof.png"))
	ed.finished.emit(true)
	for _i in 4: await process_frame
	root.get_texture().get_image().save_png(out.path_join("custom_model.png"))
	main.settings.set_value("model_roof_type", "gable")
	for _i in 6: await process_frame
	main.roofed.open()
	for _i in 10: await process_frame
	var g: RoofGenEditor = main.roofed.window.find_children("*", "RoofGenEditor", true, false)[0]
	g.prof = [[0.0, 0.0], [g.span * 0.5, 4.5], [g.span, 0.0]]
	g._sync()
	for _i in 30: await process_frame
	print("RESULT ridge after live edit ", main.last_rt[0]["roof_h"])
	root.get_texture().get_image().save_png(out.path_join("gen_live.png"))
	quit()
