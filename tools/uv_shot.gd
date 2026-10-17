extends SceneTree
## Screenshot of the full-window mapping editor. SHOT_DIR=/tmp/x
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 15: await process_frame
	main._create_sample_building()
	main.settings.set_value("tex_source", "res://textures/samples/kamienica_ceglana.png")
	main.tabs.current_tab = 1
	for _i in 20: await process_frame
	main._select_face("p0:w3")
	for _i in 5: await process_frame
	main.mapping.open_uv_editor("p0:w3")
	for _i in 10: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	root.get_texture().get_image().save_png(out.path_join("uv_crop.png"))
	main.mapping.uv_window.get_child(0).get_child(0).get_child(0)._set_mode("rectify")
	for _i in 6: await process_frame
	root.get_texture().get_image().save_png(out.path_join("uv_rect.png"))
	quit()
