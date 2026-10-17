extends SceneTree
# End-to-end run against the local mock Geoportal (tools/mock_geoportal.py), no internet needed:
#   python3 tools/mock_geoportal.py &
#   godot --path . --script res://tools/e2e_mock.gd        (needs a display; xvfb-run works)
# It points the app's service settings at http://127.0.0.1:8765, clicks a building on the map,
# builds the model and saves screenshots to $SHOT_DIR (default: the user:// folder).
var fails := 0
func ok(c: bool, l: String) -> void:
	print(("  PASS  " if c else "  FAIL  "), l)
	if not c: fails += 1

func _shot(name: String) -> String:
	var dir := OS.get_environment("SHOT_DIR")
	return (dir if dir != "" else ProjectSettings.globalize_path("user://")).path_join(name)


func _initialize() -> void:
	_run()

func _run() -> void:
	var cfg := {"version": 1, "values": {
		"svc_wms_url": "http://127.0.0.1:8765/wms", "svc_geocode_url": "http://127.0.0.1:8765/geocode", "svc_wfs_url": "http://127.0.0.1:8765/wfs",
		"map_start_mpp": 0.15, "map_start_lat": 52.2297, "map_start_lon": 21.0122}}
	var fh := FileAccess.open(AppSettings.SAVE_PATH, FileAccess.WRITE)
	fh.store_string(JSON.stringify(cfg)); fh.close()

	GeoCache.new().clear()   # results of earlier runs would hide the variant probing
	root.size = Vector2i(1600, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	var t := 0.0
	while t < 20.0 and (main.map_buildings.is_empty() or main.map_busy):
		await create_timer(0.2).timeout
		t += 0.2
	for _i in 10: await process_frame
	print("buildings fetched: ", main.map_buildings.size(), "  status: ", main.status_label.text)
	ok(main.map_image != null, "ortho basemap fetched over HTTP and decoded")
	ok(main.map_buildings.size() == 4, "4 buildings parsed from WFS GML")
	ok(main.geo._wfs_variant == 0, "WFS variant A (URN, N/E order) worked first try")
	var b0: PackedVector2Array = main.map_buildings[0]["ring"]
	var c := Vector2.ZERO
	for p in b0: c += p
	c /= b0.size()
	ok(absf(c.x - 637382.0) < 1.0 and absf(c.y - 486757.0) < 1.0, "axis order resolved: centroid %s" % c)

	# place search
	var places: Array = await main.geo.search_places("Nowa Wieś")
	ok(places.size() == 2 and absf(float(places[0]["lat"]) - 52.0146) < 1e-6, "place search parses geocoder answer")
	main.place.edit.text = "Nowa Wieś"
	main.place.search()
	for _i in 60:
		await process_frame
		if main.place.list.item_count > 0 and main.place.entries.size() == 2:
			break
	ok(main.place.list.item_count == 2, "search results listed in the sidebar")

	# cache: same view again must come from disk, no new downloads
	var first_dl: int = main.geo.last_stats["downloaded"]
	ok(first_dl > 0 or main.geo.last_stats["from_cache"] > 0, "tiles loaded (downloaded %d)" % first_dl)
	var again: Dictionary = await main.geo.fetch_basemap_tiled(main.map_image_rect.grow(-1.0), main.map_mpp)
	ok(not again.is_empty() and main.geo.last_stats["downloaded"] == 0, "second view served from cache only")
	var bcells: Array = await main.geo.fetch_buildings_cached(Rect2(main.map_image_rect.position, main.map_image_rect.size))
	ok(bcells.size() >= 4, "cached building cells give %d buildings" % bcells.size())

	# click the first building (as a user would) and screenshot the map
	var screen: Vector2 = main._world_to_screen(c)
	main._pick_building(screen)
	for _i in 5: await process_frame
	ok(main.map_selected >= 0, "click on the map selected a building")
	ok(not main.use_btn.disabled, "'build model' button enabled")
	print("label: ", main.building_label.text.replace("\n", " | "))
	root.get_texture().get_image().save_png(_shot("e2e_map.png"))

	main.use_btn.pressed.emit()
	for _i in 30: await process_frame
	ok(main.tabs.current_tab == 1, "switched to 3D tab")
	ok(is_instance_valid(main.building_root), "3D model exists")
	print("model bounds: ", main.current_bounds, " rot=", snappedf(main.footprint_rotation_deg, 0.1))
	root.get_texture().get_image().save_png(_shot("e2e_3d.png"))

	# a 3-storey building -> wall height from floors; pick B2
	main.tabs.current_tab = 0
	var b1: PackedVector2Array = main.map_buildings[1]["ring"]
	var c1 := Vector2.ZERO
	for p in b1: c1 += p
	c1 /= b1.size()
	main._pick_building(main._world_to_screen(c1))
	main.use_btn.pressed.emit()
	for _i in 30: await process_frame
	ok(absf(main.wall_h_cur - 9.0) < 0.01, "3 floors -> wall height %.1f" % main.wall_h_cur)
	root.get_texture().get_image().save_png(_shot("e2e_3d_b.png"))

	# "Testuj usługi" against the mock
	var report: String = await main.geo.diagnose()
	print(report)
	ok(report.contains("ewns:budynki") and report.contains("Raster"), "service test lists WFS types and WMS layers")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))
	print("E2E RESULT: ", fails, " failed")
	quit(1 if fails > 0 else 0)
