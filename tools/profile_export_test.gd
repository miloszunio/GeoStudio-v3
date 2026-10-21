extends SceneTree
## Exports a model with every kind of emitter and prints what ended up in the glTF:
## xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/profile_export_test.gd
## Writes /tmp/profile_test.glb (and .gltf + .bin in /tmp/profile_gltf/) for an external validator.
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1400, 800)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	main.projflow._open_project(ProjectSettings.globalize_path("user://prof_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			(w as Window).hide()
	main.settings.set_value("meta_author", "Miłosz \"pol102\" Mindak")
	main.settings.set_value("meta_licence", "CC-BY-4.0")
	main.chimneys.save([ChimneyFlow.normalize({"x": 1.0, "z": 1.0, "h": 1.5})])
	var arr: Array = []
	for k in EmitterFlow.KINDS:
		arr.append(main.emitters.default_emitter(str(k[0])))
		main.emitters.save(arr)
	for _i in 4: await process_frame
	var info: Dictionary = main.exporter.export_info()
	var res: Dictionary = ModelExporter.export_glb(main.building_root, info, "/tmp/profile_test.glb")
	print("RESULT export ", res["ok"], " ", res["error"], " nodes ", res["nodes"])
	var j: Dictionary = ModelExporter.read_glb_json("/tmp/profile_test.glb")
	print("RESULT asset ", JSON.stringify(j["asset"]).substr(0, 1500))
	print("RESULT extensionsUsed ", j.get("extensionsUsed"))
	print("RESULT lights ", JSON.stringify(((j.get("extensions", {}) as Dictionary).get("KHR_lights_punctual", {}) as Dictionary).get("lights")))
	for nd in j["nodes"]:
		print("RESULT node ", nd.get("name"), " extras ", JSON.stringify(nd.get("extras", {})).substr(0, 420))
	for nm in ["particles_ogien1", "weather_deszcz1"]:
		var nd: Dictionary = {}
		for x in j["nodes"]:
			if x.get("name") == nm:
				nd = x
		var pf: Dictionary = nd.get("extras", {}).get("particle_fx", {})
		print("RESULT ", nm, " particle_fx keys ", pf.keys(), " layers ", (pf.get("layers", []) as Array).size(), " eaves ", ((pf.get("eaves", {}) as Dictionary).get("edges", []) as Array).size())
	print("RESULT fx dir ", DirAccess.get_files_at("/tmp/fx") if DirAccess.dir_exists_absolute("/tmp/fx") else "missing")
	print("RESULT materials ", (j.get("materials", []) as Array).size(), " names ", (j.get("materials", []) as Array).map(func(m): return m.get("name")))
	# .gltf + .bin
	DirAccess.make_dir_recursive_absolute("/tmp/profile_gltf")
	var r2: Dictionary = ModelExporter.export_glb(main.building_root, info, "/tmp/profile_gltf/profile_test.gltf")
	print("RESULT gltf export ", r2["ok"])
	quit()
