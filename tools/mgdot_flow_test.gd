extends SceneTree
## Save a project as .mgdot and open it again through the real flow: xvfb-run -a godot --path . --script res://tools/mgdot_flow_test.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1400, 800)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	var d := ProjectSettings.globalize_path("user://flow_proj")
	main.projflow._open_project(d)
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 8: await process_frame
	main.settings.set_value("model_wall_height", 6.5)
	var f := ProjectSettings.globalize_path("user://flow_proj.mgdot")
	main.projflow._write_mgdot(f)
	print("RESULT saved ", FileAccess.file_exists(f), " manifest ", MgDot.read_manifest(f).get("name"), " parts ", MgDot.read_manifest(f).get("summary"))
	main.settings.set_value("model_wall_height", 3.0)
	main.projflow.open_mgdot(f)
	for _i in 8: await process_frame
	print("RESULT reopened wall_h ", main.settings.f("model_wall_height"), " parts ", main.current_parts.size(), " project ", main.project.dir)
	quit()
