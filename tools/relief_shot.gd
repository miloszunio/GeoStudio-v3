extends SceneTree
## Renders the sample building with relief off / on at a low sun (needs xvfb). SHOT_DIR = output folder.
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 20:
		await process_frame
	main.tabs.current_tab = 1
	main.settings.set_value("view_sun_altitude", 14.0)
	main.settings.set_value("view_cam_pitch", -8.0)
	main.settings.set_value("view_cam_yaw", 20.0)
	main.settings.set_value("view_sun_azimuth", 40.0)
	main.settings.set_value("view_cam_fit", 0.9)
	main.rig._reset_camera()
	var out := OS.get_environment("SHOT_DIR")
	main.settings.set_value("tex_relief_wall", 2.5)
	main.settings.set_value("tex_relief_roof", 3.0)
	for variant in ["off", "on"]:
		main.settings.set_value("tex_relief_enabled", variant == "on")
		for _i in 40:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("relief_%s.png" % variant))
	quit()
