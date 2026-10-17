extends SceneTree
## Screenshot of every sidebar tab:  SHOT_DIR=/tmp/x godot --path . --script res://tools/tabs_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 20:
		await process_frame
	var out := OS.get_environment("SHOT_DIR")
	main.place.edit.text = "Wolsztyn"
	main.place.fill_list([{"name": "Wolsztyn, gmina Wolsztyn, powiat wolsztyński, województwo wielkopolskie, Polska", "lat": 52.1, "lon": 16.2}, {"name": "Wolsztynek, powiat nowomiejski", "lat": 53.0, "lon": 19.0}], "Wyniki (2). Kliknij, aby przejść na mapie.")
	for id in main.panel.tab_ids():
		main.panel.select_tab(id, true)
		for _i in 12:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("tab_%s.png" % id))
	main.panel.select_tab("place", true)
	main.panel.open_advanced("place")
	for _i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("adv_place.png"))
	quit()
