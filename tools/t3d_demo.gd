extends SceneTree
## Exports the sample building to T3D into $OUT and prints what was written (pivot, files). 
func _initialize() -> void:
	_run()
func _run() -> void:
	root.size = Vector2i(1200, 800)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	main.projflow._open_project(ProjectSettings.globalize_path("user://t3d_demo_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	var out := OS.get_environment("OUT")
	var res := T3dExporter.export(main.building_root, main.chimneys.export_list(), "Dom Demo", out, {"folder": "geostudio", "tex_max": 1024})
	print("RESULT ok=", res["ok"], " err=", res["error"], " pivot=", res.get("pivot"), " textures=", res["textures"])
	quit()
