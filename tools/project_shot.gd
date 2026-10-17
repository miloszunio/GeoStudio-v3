extends SceneTree
## SHOT_DIR=... godot --path . --script res://tools/project_shot.gd   (needs a display)
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	var out := OS.get_environment("SHOT_DIR")
	root.get_texture().get_image().save_png(out.path_join("proj_dialog.png"))
	var dir := out.path_join("proj_demo")
	main.projflow._open_project(dir)
	main._load_geojson("res://samples/sample_building.geojson")
	main.settings.set_value("tex_source", OS.get_environment("TEX"))
	for _i in 20:
		await process_frame
	var r: String = main.projflow._save_render()
	print("render: ", r, " exists ", FileAccess.file_exists(r))
	main.panel.select_tab("building", true)
	for _i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("proj_building.png"))
	quit()
