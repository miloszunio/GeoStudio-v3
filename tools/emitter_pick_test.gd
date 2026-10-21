extends SceneTree
## Emitters: select by clicking the ball in the 3D view, drag a move arrow, list + delete. Screenshots to $SHOT_DIR.
func _initialize() -> void:
	_run()

func _click(main: Control, p: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p
	main.rig._on_viewport_gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p
	main.rig._on_viewport_gui_input(up)
	for _i in 3: await process_frame

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	var pd := ProjectSettings.globalize_path("user://pick_proj")
	if DirAccess.dir_exists_absolute(pd):
		OS.execute("rm", ["-rf", pd])
	main.projflow._open_project(pd)
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			(w as Window).hide()
	main.panel.select_tab("emit", true)
	var flow: EmitterFlow = main.emitters
	for k in ["light_point", "light_surface", "particle_fire", "weather_rain"]:
		(main.find_child("Add_" + k, true, false) as Button).pressed.emit()
		for _i in 3: await process_frame
	print("RESULT emitters ", flow.list().size(), " selected ", flow.selected)
	main.tabs.current_tab = 1
	main.settings.set_value("view_cam_min_dist", 1.0)
	main.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	main.orbit_root.position = Vector3(0, 1.5, -2)
	main.rig.orbit_yaw = deg_to_rad(190.0)
	main.rig.orbit_pitch = deg_to_rad(-12.0)
	main.rig.orbit_distance = 9.0
	main.rig._update_camera_transform()
	for _i in 10: await process_frame
	# select every emitter by clicking its ball
	var ok_all := true
	for e in flow.list():
		flow.select("")      # the arrows of a selected emitter have priority over the balls under them
		var wp := flow.pick_position(e)
		var sp: Vector2 = main.camera.unproject_position(wp)
		await _click(main, sp)
		var good := flow.selected == str(e["id"])
		ok_all = ok_all and good
		print("RESULT click ", e["id"], " at ", sp, " -> selected ", flow.selected, " ", good)
	print("RESULT all clicks ok ", ok_all)
	# drag the green (Y) arrow of the point light up
	flow.select("swiatlo1")
	for _i in 4: await process_frame
	var e1 := flow.find_emitter("swiatlo1")
	var p0 := flow.pick_position(e1)
	var unit: float = EmitterGizmo.unit(main.camera, p0)
	var a_screen: Vector2 = main.camera.unproject_position(p0 + Vector3.UP * unit * 0.6)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a_screen
	main.rig._on_viewport_gui_input(down)
	print("RESULT drag started ", main.emitter_pick.dragging)
	var target: Vector2 = a_screen + Vector2(0, -60)
	var mm := InputEventMouseMotion.new()
	mm.position = target
	mm.relative = Vector2(0, -60)
	main.rig._on_viewport_gui_input(mm)
	for _i in 3: await process_frame
	await _shotf(main, "pick_drag.png")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = target
	main.rig._on_viewport_gui_input(up)
	for _i in 5: await process_frame
	var p1 := flow.pick_position(flow.find_emitter("swiatlo1"))
	print("RESULT moved ", p0, " -> ", p1, " (up by ", p1.y - p0.y, ")")
	await _shotf(main, "pick_sel.png")
	# delete via the list
	var n0 := flow.list().size()
	var del: Button = main.find_child("Del_0", true, false)
	del.pressed.emit()
	for _i in 4: await process_frame
	print("RESULT delete ", n0, " -> ", flow.list().size())
	# duplicate
	flow.duplicate_emitter(flow.list()[0]["id"])
	for _i in 4: await process_frame
	print("RESULT duplicate -> ", flow.list().size(), " selected ", flow.selected)
	# click on empty background deselects
	await _click(main, Vector2(1500, 150))
	print("RESULT after empty click selected '", flow.selected, "'")
	quit()

func _shotf(main: Control, name: String) -> void:
	for _i in 6: await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name))
