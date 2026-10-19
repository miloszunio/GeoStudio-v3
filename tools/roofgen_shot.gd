extends SceneTree
## GPT canvas -> panels -> roof generator:  SHOT_DIR=... CANVAS=canvas.png xvfb-run -a godot --path . --script res://tools/roofgen_shot.gd
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
	for _i in 6: await process_frame
	main.settings.set_value("tex_source", OS.get_environment("CANVAS"))
	for _i in 20: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	print("regions ", main.atlas.regions.keys(), " template ", main.atlas.is_template, " ppm ", main.settings.f("tex_px_per_m"))
	main.panel.select_tab("tex", true)
	for _i in 6: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_tex.png"))
	main.panel.select_tab("roof", true)
	for _i in 6: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_rooftab.png"))
	main.panel.select_tab("tex", true)
	main.panel.open_section("tex_source")
	for _i in 4: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_tex2.png"))
	main.atlasflow.open_panel_editor()
	for _i in 10: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_panels.png"))
	for w in main.get_children():
		if w is Window and w.title.begins_with("Panele"):
			w.queue_free()
	for _i in 4: await process_frame
	main.roofed.open()
	for _i in 10: await process_frame
	var ed: RoofGenEditor = main.roofed.window.find_children("*", "RoofGenEditor", true, false)[0]
	root.get_texture().get_image().save_png(out.path_join("v3_roof_1.png"))
	# draw a mansard-ish roof with a hipped end
	ed.prof = [[0.0, 0.0], [ed.span * 0.22, 2.2], [ed.span * 0.5, 3.0], [ed.span * 0.78, 2.2], [ed.span, 0.0]]
	ed.ov_l = 0.6
	ed.ov_r = 0.6
	ed._sync()
	ed.generate()
	for _i in 10: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_roof_2.png"))
	ed.prof = RoofGen.default_profile(ed.span, 3.0, ed.span * 0.5)
	ed.ra = 1.5
	ed.rb = 0.0
	ed._sync()
	ed.generate()
	for _i in 10: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_roof_3.png"))
	main.roofed.window.queue_free()
	for _i in 5: await process_frame
	main.panel.select_tab("view", true)
	main.settings.set_value("view_cam_yaw", 35.0)
	main.settings.set_value("view_cam_pitch", -25.0)
	main.rig._reset_camera()
	for _i in 12: await process_frame
	root.get_texture().get_image().save_png(out.path_join("v3_3d.png"))
	quit()
