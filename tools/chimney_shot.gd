extends SceneTree
## Chimney editor + chimneys on the roof:  SHOT_DIR=... TEX=sheet.png LAYOUT=layout.json godot --path . --script res://tools/chimney_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1600, 950)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 10: await process_frame
	main.settings.reset_all()
	main._load_geojson("res://samples/sample_building.geojson")
	if OS.get_environment("LAYOUT") != "":
		main.settings.set_value("tex_sheet_layout", FileAccess.get_file_as_string(OS.get_environment("LAYOUT")))
	if OS.get_environment("TEX") != "":
		main.settings.set_value("tex_source", OS.get_environment("TEX"))
	for _i in 15: await process_frame
	main.tabs.current_tab = 1
	main.chimneys.open()
	for _i in 6: await process_frame
	var ed: ChimneyEditor = main.chimneys.window.find_children("*", "ChimneyEditor", true, false)[0]
	ed.items.append(main.chimneys.default_chimney())
	ed.sel = 0
	ed._after_edit()
	var c2: Dictionary = main.chimneys.default_chimney()
	c2["x"] = float(c2["x"]) - 4.0
	c2["w"] = 0.6
	c2["l"] = 0.9
	c2["h"] = 1.6
	ed._auto_part(c2)
	ed.items.append(c2)
	ed.sel = 1
	if OS.get_environment("MIRROR") != "":
		c2["mirror_x"] = true
		c2["mirror_y"] = OS.get_environment("MIRROR") == "xy"
	ed._after_edit()
	for _i in 8: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	root.get_texture().get_image().save_png(out.path_join("chim_ed.png"))
	var n := 0
	for ch in main.building_root.get_children():
		if String(ch.name).begins_with("Chimney"):
			n += 1
	print("chimney nodes: ", n, " setting: ", main.settings.s("model_chimneys").length(), " chars")
	main.chimneys.window.queue_free()
	for _i in 5: await process_frame
	main.settings.set_value("view_cam_yaw", 35.0)
	main.settings.set_value("view_cam_pitch", 28.0)
	main.rig._reset_camera()
	main.panel.select_tab("view", true)
	for _i in 12: await process_frame
	root.get_texture().get_image().save_png(out.path_join("chim_3d.png"))
	quit()
