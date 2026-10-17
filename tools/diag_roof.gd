extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 10: await process_frame
	main.settings.reset_all()
	main._load_geojson("res://samples/sample_building.geojson")
	main.settings.set_value("tex_sheet_layout", FileAccess.get_file_as_string(OS.get_environment("LAYOUT")))
	main.settings.set_value("tex_slice_mode", "auto")
	main.settings.set_value("tex_source", OS.get_environment("TEX"))
	for _i in 20: await process_frame
	print("regions: ", main.atlas.regions.keys(), " template ", main.atlas.is_template)
	for fid in main.face_geo.keys():
		if ":roof" in fid:
			var g: Dictionary = main.face_geo[fid]
			print(fid, " key=", g["key"], " uv=", g["uv"], " pw=", g["pw"], " ph=", g["ph"])
			print("  preview poly: ", main.face_info(fid)["preview"].get("poly"))
			print("  mapping: ", main.faces.mapping(fid))
	print("roof_tile_m ", main.settings.f("tex_roof_tile_m"), " repeat ", main.settings.b("tex_roof_repeat"), " rotate ", main.settings.b("tex_roof_rotate"))
	quit()
