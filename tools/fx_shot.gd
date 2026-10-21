extends SceneTree
## Effects: every particle kind + rain on the sample building, screenshots after the effects have run for a while.
## SHOT_DIR=/tmp/x xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/fx_shot.gd
func _initialize() -> void:
	_run()

func _shot(name: String) -> void:
	for _i in 30: await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name))

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	main.projflow._open_project(ProjectSettings.globalize_path("user://fx_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			(w as Window).hide()
	main.chimneys.save([ChimneyFlow.normalize({"x": 1.0, "z": 1.0, "h": 1.5})])
	var which := OS.get_environment("FX").split(",")
	var arr: Array = []
	for k in which:
		arr.append(main.emitters.default_emitter(k))
		main.emitters.save(arr)
	main.tabs.current_tab = 1
	for _i in 6: await process_frame
	var t0 := Time.get_ticks_msec()
	main.settings.set_value("view_cam_min_dist", 1.0)
	var e0: Dictionary = main.emitters.list()[0]
	var tp: Vector3 = main.emitters.position_of(e0)
	print("RESULT emitter0 ", e0["id"], " at ", tp)
	var cams := OS.get_environment("CAMS").split(";")
	var n := 0
	for c in cams:
		var v := c.split(",")     # yaw, pitch, dist, dy
		main.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		main.orbit_root.position = tp + Vector3(0, float(v[3]), 0)
		main.rig.orbit_yaw = deg_to_rad(float(v[0]))
		main.rig.orbit_pitch = deg_to_rad(float(v[1]))
		main.rig.orbit_distance = float(v[2])
		main.rig._update_camera_transform()
		await _shot("fx_%d.png" % n)
		n += 1
	print("RESULT frames done ", Time.get_ticks_msec() - t0, " ms; children ", main.building_root.get_parent().get_node("EmitterGizmos").get_child_count())
	quit()
