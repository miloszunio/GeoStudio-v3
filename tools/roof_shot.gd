extends SceneTree
## Roof editor + asymmetric roof:  SHOT_DIR=... TEX=sheet.png godot --path . --script res://tools/roof_shot.gd
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
	main.settings.set_value("tex_slice_mode", "template")
	if OS.get_environment("LAYOUT") != "":
		main.settings.set_value("tex_sheet_layout", FileAccess.get_file_as_string(OS.get_environment("LAYOUT")))
	main.settings.set_value("tex_source", OS.get_environment("TEX"))
	for _i in 15: await process_frame
	main.tabs.current_tab = 1
	main.roofed.open()
	for _i in 10: await process_frame
	var ed: RoofEditor = main.roofed.window.find_children("*", "RoofEditor", true, false)[0]
	var out := OS.get_environment("SHOT_DIR")
	root.get_texture().get_image().save_png(out.path_join("roof_ed_1.png"))
	# asymmetric: ridge to the right, steeper right slope, bigger left eave
	ed.asym = true
	ed.shift_left = 1.2
	ed.ov_l = 1.0
	ed.ov_r = 0.4
	ed._sync_controls()
	ed._apply_now()
	for _i in 10: await process_frame
	print("roof_h ", main.last_rt[0]["roof_h"], " shift ", main.settings.f("model_roof_ridge_shift"), " angles ", ed._angle_l(), " ", ed._angle_r())
	root.get_texture().get_image().save_png(out.path_join("roof_ed_2.png"))
	main.roofed.window.queue_free()
	for _i in 5: await process_frame
	main.settings.set_value("view_cam_yaw", 90.0)
	main.settings.set_value("view_cam_pitch", 10.0)
	main.rig._reset_camera()
	main.panel.select_tab("view", true)
	for _i in 12: await process_frame
	root.get_texture().get_image().save_png(out.path_join("roof_3d.png"))
	# cancel restores
	quit()
