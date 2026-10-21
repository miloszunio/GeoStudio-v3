extends SceneTree
## Emitters tab: adds every kind, checks markers / metadata / project round trip, saves screenshots.
## SHOT_DIR=/tmp/x xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/emitters_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 8: await process_frame
	var out := OS.get_environment("SHOT_DIR")
	main.projflow._open_project(ProjectSettings.globalize_path("user://emit_proj"))
	main._load_geojson("res://samples/sample_building.geojson")
	for _i in 10: await process_frame
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			(w as Window).hide()
	main.panel.select_tab("emit", true)
	for _i in 6: await process_frame
	for k in EmitterFlow.KINDS:
		var b: Button = main.find_child("Add_" + str(k[0]), true, false)
		if b == null:
			print("RESULT FAIL missing button ", k[0])
			continue
		b.pressed.emit()
		for _i in 2: await process_frame
	print("RESULT emitters ", main.emitters.list().size(), " channels ", main.emitters.channels().size())
	main.chimneys.save([ChimneyFlow.normalize({"x": 1.0, "z": 1.0, "h": 1.5})])
	for _i in 6: await process_frame
	var gz: Node = main.building_root.get_parent().get_node_or_null("EmitterGizmos")
	print("RESULT gizmos ", gz.get_child_count() if gz else -1, " (expected 6 incl. smoke)")
	for g in gz.get_children():
		var mi: MeshInstance3D = g.get_child(0)
		print("RESULT gizmo ", g.name, " pos ", g.position, " visible ", g.is_visible_in_tree(), " aabb ", mi.get_aabb().size)
	print("RESULT building bb ", main.last_rt[0]["bb"], " wall_h ", main.last_rt[0]["wall_h"], " roof_h ", main.last_rt[0]["roof_h"])
	print("RESULT meta emitters ", main.emitters.export_list().size(), " ", JSON.stringify(main.emitters.export_list()[0]))
	print("RESULT first channel ", JSON.stringify(main.emitters.channel_export_list()))
	main.tabs.current_tab = 1
	for _i in 8: await process_frame
	root.get_texture().get_image().save_png(out.path_join("emitters_3d.png"))
	main.rig._view_preset(180.0, 25.0)
	for _i in 8: await process_frame
	root.get_texture().get_image().save_png(out.path_join("emitters_front.png"))
	main.rig._view_preset(0.0, 90.0)
	for _i in 8: await process_frame
	root.get_texture().get_image().save_png(out.path_join("emitters_top.png"))
	main.panel.select_tab("emit", true)
	for _i in 6: await process_frame
	root.get_texture().get_image().save_png(out.path_join("emitters_tab.png"))
	# project round trip
	var f := ProjectSettings.globalize_path("user://emit_proj.mgdot")
	main.projflow._write_mgdot(f)
	main.settings.set_value("model_emitters", "[]")
	main.projflow.open_mgdot(f)
	for _i in 10: await process_frame
	print("RESULT after .mgdot round trip emitters ", main.emitters.list().size())
	quit()
