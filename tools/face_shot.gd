extends SceneTree
## Screenshot of the surface correction panel:  SHOT_DIR=/tmp/x godot --path . --script res://tools/face_shot.gd
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
	var out := OS.get_environment("SHOT_DIR")
	var id := ""
	for gy in range(1, 20):
		for gx in range(1, 20):
			var pid: String = main._pick_face(Vector2(main.subviewport.size.x * gx / 20.0, main.subviewport.size.y * gy / 20.0))
			if pid.begins_with("p0:w") and id == "":
				id = pid
	main._select_face(id)
	main.faces.set_field(id, "off", [0.4, 0.0])
	main.faces.set_field(id, "scale", [1.5, 1.5])
	for _i in 15: await process_frame
	print("selected ", id)
	root.get_texture().get_image().save_png(out.path_join("face_panel.png"))
	main._select_face("p0:roofA")
	for _i in 8: await process_frame
	root.get_texture().get_image().save_png(out.path_join("face_roof.png"))
	quit()
