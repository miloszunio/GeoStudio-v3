extends SceneTree
## Can the program be closed while the "save project as" dialog is open?
## xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/quit_dialog_test.gd
## Clicks the "✕ Zamknij" button (a) with no dialog (control) and (b) with the dialog open, and reports whether the click got through.
func _initialize() -> void:
	_run()

func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(e, false)
		for _i in 3: await process_frame

func _run() -> void:
	root.size = Vector2i(1400, 800)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	main.projflow._open_project(ProjectSettings.globalize_path("user://quit_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 8: await process_frame
	if OS.get_environment("STARTUP") != "":
		# start-up: the mandatory "Projekt" window is open and cannot be cancelled
		main.projflow._show_project_dialog(false)
		for _i in 6: await process_frame
		var pd: ProjectDialog = main.projflow.project_dialog
		print("RESULT start-up dialog visible ", pd.visible, ", its close button says '", pd._close_btn.text, "'")
		pd.quit_requested.connect(func() -> void: print("RESULT quit requested - the program closes"))
		pd.close_requested.emit()    # = the window's X
		await create_timer(2.0).timeout
		print("RESULT start-up: still running (cannot be closed!)")
		quit()
		return
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			print("RESULT open window at start: ", w.name, " ", w.get_class(), " title '", (w as Window).title, "'")
			(w as Window).hide()
	main.tabs.current_tab = 1
	for _i in 6: await process_frame
	var btn: Button = main.find_child("ZamknijAplikacje", true, false)
	print("RESULT button found ", btn != null, " visible ", btn.is_visible_in_tree() if btn else false)
	btn.pressed.connect(func() -> void: print("RESULT quit button pressed - the program closes"))
	var c := btn.get_global_rect().get_center()
	if OS.get_environment("DIALOG") == "":
		print("RESULT control (no dialog): clicking the quit button")
		await _click(c)
		await create_timer(2.0).timeout
		print("RESULT control: still running (click did not close it)")
		quit()
		return
	main.projflow.save_mgdot(true)
	for _i in 8: await process_frame
	print("RESULT dialog visible ", main.projflow._mgdot_dialog.visible, " exclusive ", main.projflow._mgdot_dialog.exclusive)
	await _click(c)
	await create_timer(2.0).timeout
	print("RESULT with the dialog open: still running, the quit button did not react (the program cannot be closed!)")
	quit()
