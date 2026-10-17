extends SceneTree
## Renders a main body + two annexes (needs xvfb). SHOT_DIR = output folder.
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 20:
		await process_frame
	var r := func(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(637000 + x0, 486000 + y0), Vector2(637000 + x1, 486000 + y0), Vector2(637000 + x1, 486000 + y1), Vector2(637000 + x0, 486000 + y1)])
	main.settings.set_value("model_wall_height", 6.0)
	main.settings.set_value("model_roof_height", 2.6)
	main.map_buildings = [
		{"ring": r.call(0, 0, 14, 7), "attrs": {}},
		{"ring": r.call(3, -3.1, 8, -0.15), "attrs": {}},
		{"ring": r.call(14.2, 1.5, 17, 5.5), "attrs": {}},
	]
	main.map_selected = 0
	main._on_add_neighbours()
	main._on_use_building_pressed()
	main.settings.set_value("view_cam_yaw", -25.0)
	main.settings.set_value("view_cam_pitch", -28.0)
	main.settings.set_value("view_cam_fit", 1.5)
	main.rig._reset_camera()
	main.panel.select_tab("place")
	main.tabs.current_tab = 1
	for _i in 40:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("parts_3d.png"))
	quit()
