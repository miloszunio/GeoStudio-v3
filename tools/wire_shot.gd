extends SceneTree
## Edge / vertex overlay screenshot:  SHOT_DIR=... xvfb-run -a godot --path . --script res://tools/wire_shot.gd
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
	main.panel.select_tab("view", true)
	main.settings.set_value("view_wireframe", true)
	main.settings.set_value("view_vertices", true)
	for _i in 8: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	root.get_texture().get_image().save_png(out.path_join("wire.png"))
	var h = main.building_root.get_node_or_null("EdgeOverlay")
	print("overlay ", h, " children ", h.get_child_count() if h else -1)
	quit()
