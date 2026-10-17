extends SceneTree
## Textured model screenshots:  SHOT_DIR=... TEX=path godot --path . --script res://tools/model_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1200, 800)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 10:
		await process_frame
	main.settings.reset_all()
	main.settings.set_value("model_roof_from_tex", true)
	main._load_geojson("res://samples/sample_building.geojson")
	main.settings.set_value("tex_slice_mode", "template")
	main.settings.set_value("tex_source", OS.get_environment("TEX"))
	for _i in 10:
		await process_frame
	main.tabs.current_tab = 1
	print("dbg use ", main._use_textures(), " key ", main._gable_key(), " ratio ", main.atlas.estimate_roof_ratio(main._gable_key()), " th ", main._tex_roof_height(6.0))
	print("roof_h ", main.roof_h_cur, " from_tex ", main.settings.b("model_roof_from_tex"), " enabled ", main.settings.b("tex_enabled"))
	for f in main.face_geo:
		print("FACE ", f, " ", main.face_geo[f])
	print("regions ", main.atlas.regions.keys(), " ppm ", main.settings.f("tex_px_per_m"))
	if OS.get_environment("NORELIEF") != "":
		main.settings.set_value("tex_relief_roof", 0.0)
		main._rebuild_current()
		for _i in 10: await process_frame
	if OS.get_environment("WALLS") != "":
		main._apply_walls_from_texture()
		for _i in 10: await process_frame
		print("WALLH ", main.settings.f("model_wall_height"), " ", main.status_label.text)
	var out := OS.get_environment("SHOT_DIR")
	for view in [[0.0, 12.0], [35.0, 25.0], [35.0, 60.0]]:
		main.settings.set_value("view_cam_yaw", view[0])
		main.settings.set_value("view_cam_pitch", view[1])
		main.rig._reset_camera()
		main.panel.select_tab("view", true)
		for _i in 12:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("model_%d.png" % int(view[0])))
	quit()
