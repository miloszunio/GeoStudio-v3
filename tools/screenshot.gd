extends SceneTree
## Renders the app (needs a display or xvfb) and saves PNGs next to the project:
##   godot --path . --script res://tools/screenshot.gd
## Output: user:// shot_3d.png and shot_map.png (path is printed).

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
	for _i in 30:
		await process_frame
	var out := OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else ProjectSettings.globalize_path("user://")
	root.get_texture().get_image().save_png(out.path_join("shot_3d.png"))
	main.tabs.current_tab = 0
	for _i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("shot_map.png"))
	print("saved to ", out)
	quit()
