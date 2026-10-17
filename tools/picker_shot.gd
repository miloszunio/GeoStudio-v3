extends SceneTree
## Screenshot of the texture picker window:  SHOT_DIR=... godot --path . --script res://tools/picker_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 10:
		await process_frame
	main._load_geojson("res://samples/sample_building.geojson")
	main.panel.select_tab("tex", true)
	main.panel._open_file_dialog("tex_source")
	for _i in 120:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("picker.png"))
	var pk: Window = main.panel._picker
	print("picker visible ", pk.visible, " items ", pk._list.item_count)
	quit()
