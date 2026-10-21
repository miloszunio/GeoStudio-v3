extends SceneTree
## Surroundings: screenshots from several cameras. Env: SEASON (summer|spring|autumn), CAMS "yaw,pitch,dist,dy;...", FX (emitter kinds, optional), WIND (m/s).
## SHOT_DIR=/tmp/x xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/scenery_shot.gd
func _initialize() -> void:
	_run()

func _shot(name: String) -> void:
	for _i in 40: await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name))

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	main.projflow._open_project(ProjectSettings.globalize_path("user://sc_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			(w as Window).hide()
	if OS.get_environment("SEASON") != "":
		main.settings.set_value("view_env_season", OS.get_environment("SEASON"))
	if OS.get_environment("WIND") != "":
		main.settings.set_value("fx_wind_speed", float(OS.get_environment("WIND")))
	main.chimneys.save([ChimneyFlow.normalize({"x": 1.0, "z": 1.0, "h": 1.5})])
	if OS.get_environment("FX") != "":
		var arr: Array = []
		for k in OS.get_environment("FX").split(","):
			arr.append(main.emitters.default_emitter(k))
		main.emitters.save(arr)
	main.tabs.current_tab = 1
	var t0 := Time.get_ticks_msec()
	main.scenery.apply()
	print("RESULT scenery build ", Time.get_ticks_msec() - t0, " ms; children ", main.scenery.get_child_count())
	for ch in main.scenery.get_children():
		if ch is MultiMeshInstance3D:
			print("RESULT   ", ch.name, " instances ", (ch as MultiMeshInstance3D).multimesh.instance_count)
	main.settings.set_value("view_cam_min_dist", 1.0)
	main.settings.set_value("view_cam_max_dist", 3000.0)
	var cams := OS.get_environment("CAMS").split(";")
	var n := 0
	for c in cams:
		var v := c.split(",")
		main.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		main.orbit_root.position = Vector3(0, float(v[3]), 0)
		main.rig.orbit_yaw = deg_to_rad(float(v[0]))
		main.rig.orbit_pitch = deg_to_rad(float(v[1]))
		main.rig.orbit_distance = float(v[2])
		main.rig._update_camera_transform()
		await _shot("sc_%d.png" % n)
		n += 1
	quit()
