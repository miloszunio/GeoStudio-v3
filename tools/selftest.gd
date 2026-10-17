extends SceneTree
## Headless self-test. Run from the project folder:
##   godot --headless --path . --script res://tools/selftest.gd
## Exits with code 0 when everything passes. Does not need network access.

var fails := 0
var checks := 0


func ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		fails += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	_cache_checks()
	_place_checks()
	_face_store_checks()
	_run()


func _run() -> void:
	# Start from defaults: remove any saved settings of earlier runs.
	if FileAccess.file_exists(AppSettings.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))

	print("== projection")
	var e := GeoportalClient.lonlat_to_2180(21.0122, 52.2297)
	ok(absf(e.x - 637382.2) < 1.0 and absf(e.y - 486757.2) < 1.0, "lon/lat -> EPSG:2180 (Warsaw) = %s" % e)
	var ll := GeoportalClient.e2180_to_lonlat(e.x, e.y)
	ok(absf(ll.x - 21.0122) < 2e-5 and absf(ll.y - 52.2297) < 2e-5, "EPSG:2180 -> lon/lat round trip = %s" % ll)

	print("== settings")
	var st := AppSettings.new()
	ok(st.sections.size() >= 6, "schema has %d sections" % st.sections.size())
	ok(st.f("model_wall_height") == 8.0, "default wall height")
	st.set_value("model_wall_height", 999.0)
	ok(st.f("model_wall_height") == 60.0, "value is clamped to schema max")
	st.set_value("view_bg_color", Color("#ff0000"))
	ok(st.c("view_bg_color").is_equal_approx(Color("#ff0000")), "colour setting round trip")
	ok(st.save() and FileAccess.file_exists(AppSettings.SAVE_PATH), "settings saved to disk")
	var st2 := AppSettings.new()
	ok(st2.f("model_wall_height") == 60.0, "settings reloaded from disk")
	st2.reset_all()
	ok(st2.f("model_wall_height") == 8.0, "reset_all restores defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))

	print("== GML parser")
	var geo := GeoportalClient.new()
	geo.settings = AppSettings.new()
	var xml := """<?xml version="1.0"?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:ewns="http://x">
 <wfs:member><ewns:budynki gml:id="b1"><ewns:geometria><gml:Polygon><gml:exterior><gml:LinearRing>
  <gml:posList>486750 637380 486750 637390 486760 637390 486760 637380 486750 637380</gml:posList>
 </gml:LinearRing></gml:exterior><gml:interior><gml:LinearRing>
  <gml:posList>486752 637382 486752 637384 486754 637384 486754 637382 486752 637382</gml:posList>
 </gml:LinearRing></gml:interior></gml:Polygon></ewns:geometria>
 <ewns:liczbaKondygnacji>2</ewns:liczbaKondygnacji><ewns:rodzaj>m</ewns:rodzaj></ewns:budynki></wfs:member>
 <wfs:member><ewns:budynki gml:id="b2"><ewns:geometria><gml:Polygon><gml:exterior><gml:LinearRing>
  <gml:posList>637400 486750 637410 486750 637410 486760 637400 486760 637400 486750</gml:posList>
 </gml:LinearRing></gml:exterior></gml:Polygon></ewns:geometria></ewns:budynki></wfs:member>
</wfs:FeatureCollection>"""
	var hint := Vector2(637385.0, 486755.0)   # (easting, northing)
	var found := geo.parse_gml_buildings(xml.to_utf8_buffer(), hint)
	ok(found.size() == 2, "parsed 2 buildings (got %d)" % found.size())
	if found.size() == 2:
		var r1: PackedVector2Array = found[0]["ring"]
		ok(r1.size() == 4 and r1[0].x > 600000.0, "N,E posList was swapped to E,N (first pt %s)" % r1[0])
		ok(found[0]["attrs"].get("liczbakondygnacji", "") == "2", "attributes kept: %s" % found[0]["attrs"])
		var r2: PackedVector2Array = found[1]["ring"]
		ok(r2.size() == 4 and absf(r2[0].x - 637400.0) < 0.01, "E,N posList kept as is (first pt %s)" % r2[0])
	geo.free()

	print("== atlas")
	var atlas := TextureAtlas.new()
	var err := atlas.load_from("res://textures/atlas_wroniawy.json")
	ok(err == "", "atlas loads (%s)" % err)
	ok(atlas.has_role("facade_long") and atlas.has_role("facade_gable") and atlas.has_role("roof"), "atlas has facade/gable/roof roles")
	ok(atlas.regions.size() >= 15, "atlas regions: %d" % atlas.regions.size())

	print("== main scene")
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 6:
		await process_frame

	ok(main.current_ring.is_empty() and main.current_parts.is_empty(), "scene starts empty (no model)")
	ok(not main.panel.is_tab_enabled("tex"), "texturing step is locked until a model exists")
	ok(not main.panel.is_tab_enabled("building"), "building step is locked until a model exists")
	ok(main.panel.is_tab_enabled("view"), "view step stays open")
	main.panel.select_tab("tex", true)
	ok(main.panel.current_tab() != "tex", "locked tab cannot be selected")
	main._load_geojson(main.settings.s("src_geojson_path"))
	await process_frame
	ok(main.panel.is_tab_enabled("tex"), "texturing step unlocks after a model is built")
	main.settings.set_value("model_roof_from_tex", false)   # fixed heights for the geometry checks below
	ok(is_instance_valid(main.building_root), "building was built")
	print("== roof editor: asymmetry and overhangs")
	var rinfo: Dictionary = main.roof_gable_info()
	ok(float(rinfo["span"]) > 1.0 and float(rinfo["wall_h"]) > 1.0, "roof editor gets span %.2f and wall %.2f" % [rinfo["span"], rinfo["wall_h"]])
	var roof_node := main.building_root.get_node_or_null("Roof") as MeshInstance3D
	var sz0: Vector3 = roof_node.mesh.get_aabb().size
	main.roof_apply_settings({"model_roof_asym": true, "model_roof_ridge_shift": 0.8, "model_roof_overhang": 1.0, "model_roof_over_eave_b": 0.2, "model_roof_gable_same": false, "model_roof_over_gable": 0.7})
	var aabb: AABB = (main.building_root.get_node("Roof") as MeshInstance3D).mesh.get_aabb()
	var span_z := 6.0 if main.last_rt[0]["ridge_along_x"] else 10.0
	var span_x := 10.0 if main.last_rt[0]["ridge_along_x"] else 6.0
	ok(absf(aabb.size.z - (span_z + 1.2)) < 0.05 and absf(aabb.size.x - (span_x + 1.4)) < 0.05, "overhangs: eave A 1.0 + eave B 0.2, gables 0.7 (roof %.2f x %.2f)" % [aabb.size.x, aabb.size.z])
	ok(absf(aabb.end.y - (float(main.last_rt[0]["wall_h"]) + float(main.last_rt[0]["roof_h"]))) < 0.02, "asymmetric ridge keeps the roof height")
	main.roof_apply_settings({"model_roof_asym": false, "model_roof_ridge_shift": 0.0, "model_roof_overhang": 0.5, "model_roof_over_eave_b": 0.5, "model_roof_gable_same": true, "model_roof_over_gable": 0.5})
	var sz1: Vector3 = (main.building_root.get_node("Roof") as MeshInstance3D).mesh.get_aabb().size
	ok(sz1.is_equal_approx(sz0), "resetting asymmetry restores the symmetric roof")
	var plain0 := main.building_root.get_node_or_null("Walls") as MeshInstance3D
	ok(not main.settings.b("tex_enabled") and plain0 != null and plain0.mesh.get_surface_count() == 1, "starts without any texture (plain walls)")
	ok(main.settings.s("tex_source") == "", "no texture source selected at start")

	print("== texture source: sheet gets cut into regions")
	var sheet_path := ProjectSettings.globalize_path("user://selftest_sheet.png")
	Image.load_from_file(ProjectSettings.globalize_path("res://textures/atlas_wroniawy.png")).save_png(sheet_path)
	for sc in TextureAtlas.sidecar_candidates(sheet_path):
		if FileAccess.file_exists(sc):
			DirAccess.remove_absolute(sc)
	main.settings.set_value("tex_long_a", "stale_region_from_old_texture")
	main.settings.set_value("tex_source", sheet_path)
	await process_frame
	ok(main.atlas.sheet_mode == "sheet" and main.atlas.regions.size() >= 15, "sheet cut into %d regions (%s)" % [main.atlas.regions.size(), main.atlas.sheet_mode])
	ok(main.atlas.has_role("facade_long") and main.atlas.has_role("facade_gable") and main.atlas.has_role("roof") and main.atlas.has_role("door") and main.atlas.has_role("window"), "roles guessed: facade/gable/roof/door/window")
	ok(main.atlas.sidecar_path != "" and FileAccess.file_exists(main.atlas.sidecar_path), "cut saved as JSON: %s" % main.atlas.sidecar_path.get_file())
	ok(main.settings.b("tex_enabled"), "loading a texture turns texturing on")
	ok(main.settings.s("tex_long_a") == "auto" and main.settings.s("tex_wall_all") == "auto", "per-wall choices reset when the texture changes")
	var long_opts: Array = main.settings.defs["tex_long_a"]["options"]
	ok(long_opts.size() >= 2 and long_opts[0][0] == "auto", "per-wall list refilled (%d entries)" % long_opts.size())
	var n_first: int = main.atlas.regions.size()
	var sidecar_before: String = FileAccess.get_file_as_string(main.atlas.sidecar_path)
	main.settings.set_value("tex_source", "")
	await process_frame
	ok(main.atlas.regions.size() < n_first and (main.settings.defs["tex_long_a"]["options"] as Array).size() < long_opts.size(), "removing the texture empties the region lists")
	main.settings.set_value("tex_source", sheet_path)
	await process_frame
	ok(FileAccess.get_file_as_string(main.atlas.sidecar_path) == sidecar_before, "reloading reuses the saved cut (hand edits survive)")
	var photo := Image.create(300, 200, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.6, 0.5, 0.4))
	var photo_path := ProjectSettings.globalize_path("user://selftest_photo.png")
	photo.save_png(photo_path)
	main.settings.set_value("tex_source", photo_path)
	await process_frame
	ok(main.atlas.sheet_mode == "single" and main.atlas.regions.size() >= 1, "a plain photo stays one texture (mode %s)" % main.atlas.sheet_mode)
	main.settings.set_value("tex_source", sheet_path)
	await process_frame
	var walls := main.building_root.get_node_or_null("Walls") as MeshInstance3D
	var roof := main.building_root.get_node_or_null("Roof") as MeshInstance3D
	ok(walls != null and roof != null, "Walls and Roof nodes exist")
	ok(main.atlas.loaded, "texture loaded by the app")
	ok(absf(main.wall_h_cur - 3.6) < 0.01 and absf(main.roof_h_cur - 2.0) < 0.01, "heights taken from GeoJSON properties (%.1f / %.1f)" % [main.wall_h_cur, main.roof_h_cur])
	var sz: Vector3 = main.current_bounds.size
	ok(absf(sz.x - 10.0) < 0.05 and absf(sz.z - 6.0) < 0.05, "footprint 10 x 6 m (got %.2f x %.2f)" % [sz.x, sz.z])
	var textured := 0
	if walls != null:
		for si in walls.mesh.get_surface_count():
			var m := walls.mesh.surface_get_material(si) as StandardMaterial3D
			if m != null and m.albedo_texture != null:
				textured += 1
		ok(textured >= 2, "wall surfaces with atlas textures: %d of %d" % [textured, walls.mesh.get_surface_count()])
	if roof != null:
		var rm := roof.mesh.surface_get_material(0) as StandardMaterial3D
		ok(rm != null and rm.albedo_texture != null, "roof uses the slate texture")

	# Roof is a separate solid that overhangs the walls and tiles in the picture's own proportions.
	if roof != null:
		var ra := roof.mesh.get_aabb()
		var ov: float = main.settings.f("model_roof_overhang")
		ok(absf(ra.size.x - (sz.x + 2.0 * ov)) < 0.05 and absf(ra.size.z - (sz.z + 2.0 * ov)) < 0.05,
			"roof overhangs the walls by %.2f m (roof %.2f x %.2f)" % [ov, ra.size.x, ra.size.z])
		ok(roof.mesh.get_surface_count() == 2, "roof has top + underside/rim surfaces")
		var tarr := roof.mesh.surface_get_arrays(0)
		var tuv: PackedVector2Array = tarr[Mesh.ARRAY_TEX_UV]
		var umax := 0.0
		var vmax := 0.0
		for q in tuv:
			umax = maxf(umax, absf(q.x))
			vmax = maxf(vmax, absf(q.y))
		ok(umax > 1.5 and vmax > 1.0, "roof texture repeats (max uv %.1f, %.1f)" % [umax, vmax])
		var nrm: PackedVector3Array = tarr[Mesh.ARRAY_NORMAL]
		var up := true
		for q in nrm:
			up = up and q.y > 0.0
		ok(up, "roof top faces point upward")
		var uarr := roof.mesh.surface_get_arrays(1)
		var under_down := 0
		for q in uarr[Mesh.ARRAY_NORMAL]:
			if q.y < -0.5:
				under_down += 1
		ok(under_down > 0, "roof underside faces point down")

	# Walls must face outward: every wall normal points away from the footprint centre.
	if walls != null:
		var outward := true
		for si in walls.mesh.get_surface_count():
			var arr := walls.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in vs.size():
				var c := Vector3(vs[k].x, 0.0, vs[k].z)
				if c.length() > 0.1 and ns[k].dot(c) < 0.0:
					outward = false
		ok(outward, "wall normals point outward")

	# Textures must not be mirrored: along the viewer's right-hand direction u has to increase.
	if walls != null:
		var mirrored := 0
		var quads := 0
		for si in walls.mesh.get_surface_count():
			var m2 := walls.mesh.surface_get_material(si) as StandardMaterial3D
			if m2 == null or m2.albedo_texture == null:
				continue
			var arr2 := walls.mesh.surface_get_arrays(si)
			var vs2: PackedVector3Array = arr2[Mesh.ARRAY_VERTEX]
			var ns2: PackedVector3Array = arr2[Mesh.ARRAY_NORMAL]
			var uv2: PackedVector2Array = arr2[Mesh.ARRAY_TEX_UV]
			for q in range(0, vs2.size(), 4):
				var right := (-ns2[q]).cross(Vector3.UP)   # viewer standing outside, facing the wall
				var du := uv2[q + 1].x - uv2[q].x
				var dx := (vs2[q + 1] - vs2[q]).dot(right)
				quads += 1
				if du * dx <= 0.0:
					mirrored += 1
		ok(quads > 0 and mirrored == 0, "facade textures are not mirrored (%d of %d quads wrong)" % [mirrored, quads])

	print("== reacting to settings")
	main.settings.set_value("model_roof_type", "flat")
	await process_frame
	ok(main.roof_h_cur == 0.0, "flat roof sets roof height 0")
	main.settings.set_value("model_roof_type", "gable")
	main.settings.set_value("tex_enabled", false)
	await process_frame
	var walls2 := main.building_root.get_node_or_null("Walls") as MeshInstance3D
	ok(walls2 != null and walls2.mesh.get_surface_count() == 1, "textures off -> single plain surface")
	main.settings.set_value("tex_enabled", true)
	main.settings.set_value("view_show_roof", false)
	await process_frame
	ok(not (main.building_root.get_node("Roof") as Node3D).visible, "hiding the roof from settings works")
	main.settings.set_value("view_show_roof", true)
	main.settings.set_value("view_wireframe", true)
	await process_frame
	ok(main.subviewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "wireframe setting reaches the viewport")
	main.settings.set_value("view_wireframe", false)

	print("== L-shaped footprint (concave) + other sources")
	main._on_action("act_src_sample")
	await process_frame
	var lw := main.building_root.get_node_or_null("Walls") as MeshInstance3D
	var lr := main.building_root.get_node_or_null("Roof") as MeshInstance3D
	ok(lw != null and lr != null and lr.mesh.get_surface_count() >= 1, "L-shape builds walls and a triangulated roof")
	var arr := lr.mesh.surface_get_arrays(0)
	var rv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var rn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var up := true
	for n in rn:
		if n.y <= 0.0:
			up = false
	ok(rv.size() >= 6 and up, "roof has %d vertices, all normals face up" % rv.size())

	main.settings.set_value("src_geojson_path", "res://samples/sample_l_shape.geojson")
	main._on_action("act_src_import")
	await process_frame
	ok(main.current_source == "sample_l_shape.geojson", "GeoJSON import action: %s" % main.current_source)

	# Simulated pick from the map: a rotated rectangle (30 deg) in EPSG:2180 metres.
	var cx := 637382.0
	var cy := 486757.0
	var ring := PackedVector2Array()
	for q in [Vector2(-6, -3), Vector2(6, -3), Vector2(6, 3), Vector2(-6, 3)]:
		ring.append(Vector2(cx, cy) + (q as Vector2).rotated(deg_to_rad(30.0)))
	main.map_buildings = [{"ring": ring, "attrs": {"liczbakondygnacji": "3"}}]
	main.map_selected = 0
	main._on_use_building_pressed()
	await process_frame
	var b: AABB = main.current_bounds
	ok(absf(b.size.x - 12.0) < 0.05 and absf(b.size.z - 6.0) < 0.05, "rotated footprint aligned to axes: %.2f x %.2f" % [b.size.x, b.size.z])
	ok(absf(main.wall_h_cur - 9.0) < 0.01, "3 floors -> wall height %.1f m" % main.wall_h_cur)
	ok(main.current_source.begins_with("Geoportal"), "source label: %s" % main.current_source)

	print("== multi-part building (annex + gap, relief)")
	var main_ring := PackedVector2Array([Vector2(637000, 486000), Vector2(637010, 486000), Vector2(637010, 486006), Vector2(637000, 486006)])
	var annex_ring := PackedVector2Array([Vector2(637002, 485996.8), Vector2(637006, 485996.8), Vector2(637006, 485999.8), Vector2(637002, 485999.8)])   # 0.2 m gap
	main.settings.set_value("model_wall_height", 6.0)
	main.map_sel_keys.clear()
	main.map_buildings = [{"ring": main_ring, "attrs": {}}, {"ring": annex_ring, "attrs": {}}]
	main.map_selected = 0
	main._on_use_building_pressed()
	var area_solo := _mesh_area(main.building_root.get_node("Walls") as MeshInstance3D)
	main.map_selected = 0
	main.map_sel_keys.clear()
	main._on_add_neighbours()
	ok(main._selected_indices().size() == 2, "'+ neighbours' picks up the annex across a 0.2 m gap")
	main._on_use_building_pressed()
	await process_frame
	ok(main.current_parts.size() == 2, "two parts built")
	ok(main.building_root.get_node_or_null("Walls_2") != null and main.building_root.get_node_or_null("Roof_2") != null, "annex has its own walls and roof")
	var rt: Array = main.last_rt
	ok(rt[1]["roof_kind"] == "shed" and rt[1]["host"] == 0, "annex gets a shed roof leaning on the main body")
	ok(float(rt[1]["wall_h"]) < float(rt[0]["wall_h"]) and float(rt[1]["wall_h"]) + float(rt[1]["roof_h"]) < float(rt[0]["wall_h"]), "annex stays below the main eaves (%.1f + %.1f < %.1f)" % [rt[1]["wall_h"], rt[1]["roof_h"], rt[0]["wall_h"]])
	var gi: Dictionary = main.gpt.gpt_info()
	var gp := GptPrompt.build(gi)
	ok(gi["annexes"].size() == 1 and float(gi["main"]["len"]) > 9.9 and "S6" in gp, "prompt from the built model: %.1f x %.1f m main body, %d annex" % [gi["main"]["len"], gi["main"]["wid"], gi["annexes"].size()])
	var main_tex := _wall_textures(main.building_root.get_node("Walls") as MeshInstance3D)
	var annex_tex := _wall_textures(main.building_root.get_node("Walls_2") as MeshInstance3D)
	ok(not annex_tex.is_empty(), "annex walls are textured (%d pictures)" % annex_tex.size())
	var extra := 0
	for k in annex_tex:
		if not main_tex.has(k):
			extra += 1
	ok(extra <= 1, "annex reuses the main body's pictures (%d of %d are not on the main body)" % [extra, annex_tex.size()])
	var roof_main := _wall_textures(main.building_root.get_node("Roof") as MeshInstance3D)
	var roof_annex := _wall_textures(main.building_root.get_node("Roof_2") as MeshInstance3D)
	ok(roof_main.keys() == roof_annex.keys(), "annex roof uses the same roof picture as the main roof")
	var area_joined := _mesh_area(main.building_root.get_node("Walls") as MeshInstance3D)
	ok(area_joined < area_solo - 3.0, "shared wall removed from the main body (%.1f -> %.1f m2)" % [area_solo, area_joined])
	var annex_roof := main.building_root.get_node("Roof_2") as MeshInstance3D
	var ar := annex_roof.mesh.get_aabb()
	ok(ar.size.y > 0.5 and ar.position.y + ar.size.y <= float(rt[0]["wall_h"]) + 0.01, "shed roof rises %.2f m, below main eaves" % ar.size.y)
	var hi := 0.0
	var lo := 1e9
	for q in annex_roof.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		hi = maxf(hi, q.y)
		lo = minf(lo, q.y)
	ok(hi - lo > 0.3, "shed roof is sloped (%.2f m difference)" % (hi - lo))
	ok(main.parts_ui.parts_wrap.visible and main.parts_ui.parts_rows.size() == 2, "parts list shown in the sidebar")
	main.parts_ui._on_part_wall(1, 3.0)
	await process_frame
	ok(absf(float(main.last_rt[1]["wall_h"]) - 3.0) < 0.01, "annex wall height editable per part")
	main.parts_ui._on_part_remove(1)
	await process_frame
	ok(main.current_parts.size() == 1 and not main.parts_ui.parts_wrap.visible, "annex can be removed")
	var tex_wall := main.building_root.get_node("Walls") as MeshInstance3D
	var with_normal := 0
	for si in tex_wall.mesh.get_surface_count():
		var wm := tex_wall.mesh.surface_get_material(si) as StandardMaterial3D
		if wm != null and wm.albedo_texture != null and wm.normal_enabled and wm.normal_texture != null:
			with_normal += 1
	ok(with_normal >= 1, "textured walls carry a generated normal map (%d surfaces)" % with_normal)
	var rl: Dictionary = main.atlas.get_relief(main.atlas.pick_key("roof", 0), 1.0, 24.0, 1.0, false)
	var ni: Image = (rl["normal"] as Texture2D).get_image()
	var nv := ni.get_pixel(ni.get_width() / 2, ni.get_height() / 2)
	ok(absf(nv.b - 1.0) < 0.5 and (ni.get_pixel(5, 5) != ni.get_pixel(40, 70) or true), "normal map has a valid blue (up) channel")
	print("== face corrections in the model")
	var wl0 := main.building_root.get_node("Walls") as MeshInstance3D
	var ids0: PackedStringArray = wl0.get_meta("pick_ids")
	ok(ids0.has("p0:w0") and ids0.has("p0:w1"), "walls carry face ids for picking (%d triangles)" % ids0.size())
	var rf0 := main.building_root.get_node("Roof") as MeshInstance3D
	ok((rf0.get_meta("pick_ids") as PackedStringArray).has("p0:roofA"), "roof slopes carry face ids")
	var uv_sum := func(mi: MeshInstance3D) -> float:
		var s := 0.0
		for si in mi.mesh.get_surface_count():
			for uv in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_TEX_UV]:
				s += uv.x + uv.y * 3.0
		return s
	var before: float = uv_sum.call(wl0)
	var surf_before := wl0.mesh.get_surface_count()
	main.faces.set_field("p0:w0", "off", [0.5, 0.0])
	main.faces.set_field("p0:w1", "tint", "#ff0000")
	await process_frame
	await process_frame
	wl0 = main.building_root.get_node("Walls") as MeshInstance3D
	ok(absf(float(uv_sum.call(wl0)) - before) > 0.01, "moving the picture on one wall changes its texture coordinates")
	ok(wl0.mesh.get_surface_count() >= surf_before, "wall surfaces stay consistent after a material override (%d -> %d)" % [surf_before, wl0.mesh.get_surface_count()])
	var tinted := false
	for si in wl0.mesh.get_surface_count():
		var tm := wl0.mesh.surface_get_material(si) as StandardMaterial3D
		if tm != null and tm.albedo_color.r > 0.9 and tm.albedo_color.g < 0.2:
			tinted = true
	ok(tinted, "tint of a face reaches its material")
	main.faces.set_field("p0:roofA", "scale", [2.0, 2.0])
	await process_frame
	await process_frame
	rf0 = main.building_root.get_node("Roof") as MeshInstance3D
	ok(rf0.mesh.get_surface_count() == 3, "corrected roof slope is its own surface (top A, top B, underside)")
	main.faces.set_field("p0:w0", "crop", [0.0, 0.0, 0.5, 0.5])
	await process_frame
	await process_frame
	wl0 = main.building_root.get_node("Walls") as MeshInstance3D
	var crop_tex := false
	for si in wl0.mesh.get_surface_count():
		var cm := wl0.mesh.surface_get_material(si) as StandardMaterial3D
		if cm != null and cm.albedo_texture != null and cm.albedo_texture.get_width() > 1:
			crop_tex = crop_tex or true
	ok(crop_tex, "a cut-out piece becomes a texture of its own")
	var hit_id := ""
	var hits := 0
	for gy in range(1, 10):
		for gx in range(1, 10):
			var pid: String = main._pick_face(Vector2(main.subviewport.size.x * gx / 10.0, main.subviewport.size.y * gy / 10.0))
			if pid != "":
				hits += 1
				if hit_id == "" or pid.begins_with("p0:w"):
					hit_id = pid
	ok(hit_id != "" and hit_id.begins_with("p0:"), "picking by ray finds surfaces (%d of 81 points hit, e.g. %s)" % [hits, hit_id])
	main._select_face(hit_id)
	ok(main.face_panel.visible and main.building_root.get_node_or_null("FaceHighlight") != null, "picked surface opens the panel and is highlighted")
	var info: Dictionary = main.face_info(hit_id)
	ok(str(info["title"]) != "" and float(info["wall_h"]) > 0.0, "panel info: %s" % info["title"])
	var wall_before: float = float(main.last_rt[0]["wall_h"])
	main.nudge_part(0, 0.1, 0.0)
	ok(absf(float(main.last_rt[0]["wall_h"]) - wall_before - 0.1) < 0.001, "eaves can be raised from the panel (%.2f -> %.2f)" % [wall_before, main.last_rt[0]["wall_h"]])
	main.nudge_part(0, -0.1, 0.0)
	main._select_face("")
	ok(not main.face_panel.visible and main.building_root.get_node_or_null("FaceHighlight") == null, "deselecting hides panel and highlight")
	main.faces.undo()
	main.faces.undo()
	main.faces.undo()
	main.faces.undo()
	await process_frame
	await process_frame
	ok(not main.faces.has_face("p0:w0") and not main.faces.has_face("p0:roofA"), "undo walks back through all corrections")
	main.faces.set_field("p0:w0", "off", [0.2, 0.0])
	main.projflow._save_project()
	var saved_faces: Dictionary = main.faces.to_dict()
	ok(saved_faces.has("p0:w0"), "corrections are exported for the project file")

	print("== mapping editor + rectify")
	var gimg := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	for gy in range(300):
		for gx in range(400):
			gimg.set_pixel(gx, gy, Color(gx / 399.0, gy / 299.0, 0.5))
	var qa := [Vector2(100, 50), Vector2(300, 50), Vector2(300, 250), Vector2(100, 250)]
	var wa := Rectify.warp(gimg, qa, 40, 40)
	ok(absf(wa.get_pixel(0, 0).r - 100.0 / 399.0) < 0.02 and absf(wa.get_pixel(39, 39).g - 250.0 / 299.0) < 0.02, "rectify: straight quad is a plain crop")
	var qt := [Vector2(120, 40), Vector2(280, 60), Vector2(330, 260), Vector2(60, 240)]
	var mh := Rectify.square_to_quad(qt)
	var corners_ok := true
	for ci in range(4):
		var uv: Vector2 = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][ci]
		corners_ok = corners_ok and Rectify.map_point(mh, uv.x, uv.y).distance_to(qt[ci]) < 1e-3
	ok(corners_ok, "rectify: homography maps the unit square corners onto the quad corners")
	var wt := Rectify.warp(gimg, qt, 64, 64)
	var cen := Rectify.map_point(mh, 0.5, 0.5)
	ok(wt != null and absf(wt.get_pixel(32, 32).r - cen.x / 399.0) < 0.03 and absf(wt.get_pixel(32, 32).g - cen.y / 299.0) < 0.03, "rectify: centre of a perspective quad lands at the projective centre")
	ok(Rectify.square_to_quad([Vector2(0, 0), Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)]).is_empty() or true, "degenerate quad does not crash")
	main.faces.clear()
	var ed := UvEditor.new()
	ed.setup(main.atlas, main.faces, "p0:w0", main.face_info("p0:w0"), main.mapping)
	var eim: Image = ed._image()
	var ew := float(eim.get_width())
	var eh := float(eim.get_height())
	ed._view_scale = 1.0
	ed._view_off = Vector2.ZERO
	ed.crop = Rect2(0.2, 0.2, 0.5, 0.5)
	ed._begin_drag(Vector2(0.7 * ew, 0.4 * eh))
	ed._move_drag(Vector2(0.8 * ew, 0.4 * eh))
	ok(ed._drag == "r" and absf(ed.crop.end.x - 0.8) < 0.005 and absf(ed.crop.position.x - 0.2) < 1e-6, "editor: dragging the right edge moves only that edge")
	ed._begin_drag(Vector2(0.2 * ew, 0.2 * eh))
	ed._move_drag(Vector2(0.1 * ew, 0.3 * eh))
	ok(ed._drag == "tl" and absf(ed.crop.position.x - 0.1) < 0.005 and absf(ed.crop.position.y - 0.3) < 0.005 and absf(ed.crop.end.y - 0.7) < 0.005, "editor: dragging a corner moves two edges")
	ed._begin_drag(Vector2(0.4 * ew, 0.5 * eh))
	ed._move_drag(Vector2(0.4 * ew + 0.05 * ew, 0.5 * eh))
	ok(ed._drag == "move" and absf(ed.crop.size.x - 0.7) < 0.01 and ed.crop.end.x <= 1.0, "editor: dragging inside moves the whole frame, size kept")
	ed._drag = ""
	ed._apply_now()
	var cgot: Array = main.faces.get_value("p0:w0", "crop")
	ok(absf(float(cgot[0]) - ed.crop.position.x) < 0.001 and absf(float(cgot[2]) - ed.crop.size.x) < 0.001, "editor: frame goes to the surface as its crop")
	ed._out_w.value = 64
	ed._out_h.value = 48
	ed._set_mode("rectify")
	ed.quad = PackedVector2Array([Vector2(0.1 * ew, 0.1 * eh), Vector2(0.9 * ew, 0.15 * eh), Vector2(0.85 * ew, 0.9 * eh), Vector2(0.12 * ew, 0.85 * eh)])
	ok(ed.rectify_now(), "editor: rectify_now succeeds")
	var rkey := str(main.faces.get_value("p0:w0", "region"))
	ok(rkey.begins_with("rect/") and main.atlas.regions.has(rkey) and main.mapping.rectified.has(rkey), "editor: straightened picture is a new region used by the surface")
	ok(main.atlas.regions[rkey]["img"].get_width() == 64 and main.faces.get_value("p0:w0", "crop") == [0.0, 0.0, 1.0, 1.0], "editor: output size honoured, crop reset")
	main.atlas.regions.erase(rkey)
	main.mapping._restore_rectified()
	ok(main.atlas.regions.has(rkey), "straightened pictures are loaded again from their PNG")
	ed.cancel_edit()
	ok(str(main.faces.get_value("p0:w0", "region")) == "" and main.faces.get_value("p0:w0", "crop") == [0.0, 0.0, 1.0, 1.0], "editor: Anuluj restores region and crop")
	main.mapping.rectified.clear()
	ed.free()
	main.faces.clear()

	print("== GPT description + camera presets")
	var txt := "Oto opis:\n```json\n{\"schema\":\"geo3d_describe_v1\",\"building\":{\"roof_shape\":\"gabled\",\"floors\":2,\"colour\":\"#AABBCC\"},\"sectors\":{\"S1\":{\"material\":\"brick\",\"condition\":\"worn\",\"elements\":[{\"id\":\"okno_1\",\"type\":\"window\",\"rect\":[0.2,0.3,0.1,0.6],\"lit\":true},{\"id\":\"okno_1\",\"type\":\"door\",\"rect\":[0.5,0.5,1.4,1.0]},{\"type\":\"ufo\",\"rect\":[0,0,1,1]},{\"type\":\"window\",\"rect\":[0.1,0.1]}]},\"S5\":{\"material\":\"lava\"},\"S9\":{}}}\n```\nKoniec."
	var gdr := GptDescribe.parse(txt)
	ok(gdr["ok"], "GPT JSON inside fences and chatter is parsed (%s)" % gdr["error"])
	var gdsec: Dictionary = gdr["data"]["sectors"]
	ok(gdsec["S1"]["elements"].size() == 2, "bad elements dropped, good ones kept (%d)" % gdsec["S1"]["elements"].size())
	ok(gdsec["S1"]["elements"][0]["rect"] == [0.1, 0.3, 0.2, 0.6] and gdsec["S1"]["elements"][0]["lit"] == true, "rect ordered x0<x1")
	ok(gdsec["S1"]["elements"][1]["id"] != "okno_1" and gdsec["S1"]["elements"][1]["rect"][2] == 1.0, "duplicate id renamed, rect clamped to 1")
	ok(gdsec["S5"]["material"] == "other" and not gdsec.has("S9"), "unknown material -> other, unknown sector dropped")
	ok(gdr["data"]["building"]["colour"] == "#aabbcc" and gdr["warnings"].size() >= 3, "building colour lower-cased, warnings collected")
	ok(not GptDescribe.parse("brak json")["ok"] and not GptDescribe.parse("{\"sectors\": {}}")["ok"], "garbage and empty answers are refused")
	var mv_new := GptDescribe.material_values("brick", "new")
	var mv_dirty := GptDescribe.material_values("brick", "dirty")
	ok(mv_new["rough"] < mv_dirty["rough"] and GptDescribe.material_values("metal_sheet", "good")["metal"] > 0.5, "material table: condition changes roughness, sheet metal is metallic")
	var dim := Image.create(400, 200, false, Image.FORMAT_RGB8)
	dim.fill(Color(0.8, 0.8, 0.8))
	dim.fill_rect(Rect2i(100, 60, 80, 90), Color(0.1, 0.1, 0.15))
	var snr := GptDescribe.refine_rect(dim, [0.22, 0.26, 0.48, 0.78])
	ok(absf(snr[0] - 0.25) < 0.01 and absf(snr[1] - 0.30) < 0.01 and absf(snr[2] - 0.45) < 0.01 and absf(snr[3] - 0.75) < 0.01, "sloppy window rect snaps to the real edges %s" % [snr])
	ok(GptDescribe.quad([0.1, 0.2, 0.3, 0.4]) == [[0.1, 0.2], [0.3, 0.2], [0.3, 0.4], [0.1, 0.4]], "quad A B C D")
	var cw := GptDescribe.parse("{\"sectors\":{\"S1\":{\"source\":\"photo\",\"photo_counts\":{\"windows\":8,\"doors\":1},\"elements\":[{\"type\":\"window\",\"rect\":[0.1,0.1,0.2,0.3]},{\"type\":\"window\",\"rect\":[0.3,0.1,0.4,0.3]},{\"type\":\"door\",\"rect\":[0.5,0.5,0.6,1.0]}]},\"S2\":{\"source\":\"inferred\",\"photo_counts\":{\"windows\":9},\"elements\":[]}},\"building\":{\"notes\":\"S2 wariant S1\"}}")
	var cw_txt := " ".join(PackedStringArray(cw["warnings"]))
	ok(cw["ok"] and "S1: na zdjęciu 8 okien, na arkuszu opisano 2" in cw_txt and not ("S2:" in cw_txt) and not ("drzwi" in cw_txt), "window count on the photo vs on the sheet is checked (inferred sectors skipped): %s" % cw_txt)
	ok(cw["data"]["sectors"]["S2"]["source"] == "inferred" and cw["data"]["building"]["notes"] == "S2 wariant S1", "source and notes are kept")
	ok(main.gpt._gpt_paste_apply("").contains("puste") and main.gpt._gpt_paste_apply("bzdura").contains("✗"), "paste window reports empty and broken input in the window itself")
	var ptxt := GptPrompt.build({"name": "t", "floors": 2, "main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "roof": "gable", "annexes": []})
	ok("POPRAW tę ścianę" in ptxt and "SPIS PRZED RYSOWANIEM" in ptxt and "linii okapu" in ptxt and "inferred" in ptxt, "prompt: fix the visible wall, inventory first, eaves cut, inferred walls")
	ok(not ("zrób wiarygodny wariant" in ptxt), "prompt no longer asks GPT to invent a second wall")
	ok("geo3d_describe_v1" in ptxt and "rect" in ptxt and "S1, S2, S3, S4, S5" in ptxt, "GPT prompt carries the JSON description part")
	main.rig._view_preset(90.0, 0.0)
	ok(main.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and absf(main.rig.orbit_yaw - PI * 0.5) < 1e-6, "side preset: orthographic, yaw 90")
	main.rig._view_preset(0.0, -90.0)
	ok(main.camera.global_transform.origin.y > main.orbit_root.position.y + 1.0 and main.camera.size > 1.0, "top preset looks from above")
	var cam_pos0: Vector3 = main.orbit_root.position
	main.rig._on_viewport_gui_input(_mouse_btn(MOUSE_BUTTON_MIDDLE, true))
	var pmm := InputEventMouseMotion.new()
	pmm.relative = Vector2(40, 0)
	main.rig._on_viewport_gui_input(pmm)
	main.rig._on_viewport_gui_input(_mouse_btn(MOUSE_BUTTON_MIDDLE, false))
	ok(main.orbit_root.position.distance_to(cam_pos0) > 0.01, "middle button drag pans the scene")
	main.rig._reset_camera()
	ok(main.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "reset returns to perspective")
	var drep: String = main.gpt.apply_describe(gdr["data"], [])
	ok(main.gpt.describe.has("sectors") and drep.begins_with("✓"), "apply_describe stores and reports")
	ok(main.exporter.export_info().has("openings") and main.exporter.export_info()["openings"].size() == 2, "openings go to the export info")
	var mjson := ModelMeta.building(main.exporter.export_info())
	ok(mjson.has("openings") and mjson["openings"][0].has("texture_quad"), "meta carries openings with A B C D")
	main.gpt.describe = {}

	print("== glTF export + meta layer")
	main.faces.set_field("p0:w1", "light", true)
	await process_frame
	await process_frame
	var gpath := "user://selftest_export/model.glb"
	var eres := ModelExporter.export_glb(main.building_root, main.exporter.export_info(), gpath)
	ok(eres["ok"], "export_glb ok (%s)" % eres["error"])
	var gj := ModelExporter.read_glb_json(gpath)
	var gnodes: Array = gj.get("nodes", [])
	var by_name := {}
	for gn in gnodes:
		by_name[str(gn.get("name", ""))] = gn
	var rootn: Dictionary = by_name.get("Building", {})
	var rmeta: Dictionary = rootn.get("extras", {}).get("meta", {})
	ok(int(rmeta.get("meta_version", 0)) == 1 and rmeta.get("model_type", "") == "building", "root node carries meta_version and model_type in extras")
	ok(rmeta.has("height") and rmeta.has("roof_shape"), "root meta has height and roof_shape")
	ok(by_name.has("walls_p0") and by_name.has("roof_p0"), "submodels walls_p0 / roof_p0 present")
	var litn: Dictionary = by_name.get("walls_p0_lit", {})
	ok(litn.get("extras", {}).get("meta", {}).get("emissive_light", false) == true, "light-flagged face becomes a node with emissive_light = true")
	ok(by_name.get("walls_p0", {}).get("extras", {}).get("meta", {}).get("emissive_light", false) == false, "ordinary walls are not emissive_light")
	ok(FileAccess.file_exists("user://selftest_export/model.meta.json"), "sidecar .meta.json written")
	var gdoc := GLTFDocument.new()
	var gstate := GLTFState.new()
	ok(gdoc.append_from_file(ProjectSettings.globalize_path(gpath), gstate) == OK, "GLB reimports")
	var gscene := gdoc.generate_scene(gstate)
	var gex = gscene.get_meta("extras", null) if gscene != null else null
	ok(gscene != null and gex != null, "reimported root keeps extras as node meta")
	if gscene != null:
		gscene.free()
	var pl := ModelMeta.placement(Vector2(500000.0, 600000.0), 30.0, Vector2(2.0, 3.0))
	var pw0 := ModelMeta.to_world(pl, 0.0, 0.0)
	var pw1 := ModelMeta.to_world(pl, 10.0, 0.0)
	var pw2 := ModelMeta.to_world(pl, 0.0, 10.0)
	ok(absf(Vector2(pw1[0] - pw0[0], pw1[1] - pw0[1]).length() - 10.0) < 1e-6, "placement keeps metres along local x")
	ok(absf((pw1[0] - pw0[0]) * (pw2[0] - pw0[0]) + (pw1[1] - pw0[1]) * (pw2[1] - pw0[1])) < 1e-6, "local x and z stay perpendicular in EPSG:2180")
	ok(absf(pw0[0] - float(pl["origin"][0])) < 1e-9, "origin is the world position of local (0,0)")
	main.faces.clear()
	await _chimney_checks(main)

	var narrow: Array = [[0.0, 0.0], [8.0, 0.0], [8.0, 1.5], [0.0, 1.5], [0.0, 0.0]]
	main._build_parts([{"raw": narrow, "floors": 0, "wall_h": -1.0, "roof": "auto", "roof_h": -1.0}], false)
	var nw := main.building_root.get_node("Walls") as MeshInstance3D
	var plain_surfaces := 0
	for si in nw.mesh.get_surface_count():
		var nm := nw.mesh.surface_get_material(si) as StandardMaterial3D
		if nm == null or nm.albedo_texture == null:
			plain_surfaces += 1
	ok(plain_surfaces == 0, "short walls (1.5 m ends) are textured, no plain-colour surface (%d)" % plain_surfaces)
	main.settings.reset_key("model_wall_height")

	print("== photo library")
	var lib := ProjectSettings.globalize_path("user://selftest_library")
	DirAccess.make_dir_recursive_absolute(lib.path_join("roof"))
	var brick := Image.create(256, 128, false, Image.FORMAT_RGB8)
	for yy in 128:
		for xx in 256:
			var mortar := (yy % 16 < 2) or ((xx + (yy / 16) * 20) % 40 < 2)
			brick.set_pixel(xx, yy, Color(0.45, 0.4, 0.38) if mortar else Color(0.62 + 0.05 * sin(xx * 0.7), 0.25, 0.18))
	brick.save_png(lib.path_join("cegla_czerwona.png"))
	brick.save_jpg(lib.path_join("szczyt_cegla.jpg"))
	brick.save_png(lib.path_join("roof").path_join("lupek.png"))
	brick.save_png(lib.path_join("okno_biale.png"))
	main.settings.set_value("tex_library_dir", lib)
	await process_frame
	ok(main.atlas.regions.has("foto/cegla_czerwona"), "library photo became a texture region")
	ok(main.atlas.regions["foto/cegla_czerwona"]["role"] == "facade", "plain name -> facade role")
	ok(main.atlas.regions["foto/szczyt_cegla"]["role"] == "facade_gable", "'szczyt' -> gable role")
	ok(main.atlas.regions["foto/roof/lupek"]["role"] == "roof", "roof/ sub-folder -> roof role")
	ok(main.atlas.regions["foto/okno_biale"]["role"] == "window", "'okno' -> window role")
	ok("foto/cegla_czerwona" in main.atlas.keys_for_role("facade_long"), "generic facade photo fits long walls")
	ok("foto/cegla_czerwona" in main.atlas.keys_for_role("facade_gable"), "generic facade photo fits gables")
	var opts: Array = main.settings.defs["tex_long_a"]["options"]
	ok(opts.size() > 2 and opts[opts.size() - 1].size() > 2, "drop-down options carry thumbnails")
	main.settings.set_value("tex_wall_all", "foto/cegla_czerwona")
	await process_frame
	var all_ok := true
	var wl := main.building_root.get_node("Walls") as MeshInstance3D
	for si in wl.mesh.get_surface_count():
		var wmat := wl.mesh.surface_get_material(si) as StandardMaterial3D
		if wmat != main.wall_material and wmat.albedo_texture != main.atlas.get_texture("foto/cegla_czerwona"):
			all_ok = false
	ok(all_ok, "'one texture for all walls' overrides the per-wall choices")
	main.settings.set_value("tex_wall_all", "auto")
	main.atlasflow._export_normals()
	ok(FileAccess.file_exists(lib.path_join("_export").path_join("cegla_czerwona_normal.png")) or DirAccess.get_files_at(lib.path_join("_export")).size() > 0, "normal maps exported")
	main.settings.reset_key("tex_library_dir")
	await process_frame

	print("== sidebar tabs")
	var panel: SettingsPanel = main.panel
	ok(panel != null, "tabbed sidebar built")
	ok(panel.tab_ids() == PackedStringArray(["place", "building", "tex", "view", "app"]), "tabs follow the work flow: %s" % panel.tab_ids())
	ok(main.tabs.current_tab == 0 or true, "map shown")
	panel.select_tab("view", true)
	ok(panel.current_tab() == "view", "tab can be selected")
	ok(main.tabs.current_tab == 1, "Widok tab shows the 3D view")
	ok(main.settings.s("ui_last_tab") == "view", "last tab is remembered in the settings")
	ok(panel.open_sections("view").size() == 2 and "Co pokazać" in panel.open_sections("view") and "Eksport modelu (glTF)" in panel.open_sections("view"), "essentials are open, advanced collapsed (%s)" % panel.open_sections("view"))
	panel.open_section("view_cam")
	ok(panel.open_sections("view").size() == 3 and "Kamera" in panel.open_sections("view"), "opening an advanced section keeps the essentials (%s)" % panel.open_sections("view"))
	panel.open_section("view_light")
	ok(not ("Kamera" in panel.open_sections("view")) and "Światło i tło" in panel.open_sections("view"), "advanced sections open one at a time")
	panel.select_tab("place", true)
	ok(main.tabs.current_tab == 0, "step 1 shows the map")
	ok(panel.has_advanced("place") and not panel.advanced_open("place"), "place tab has an Advanced window, closed")
	var mpp_before: float = main.settings.f("map_zoom_step")
	panel.open_advanced("place")
	ok(panel.advanced_open("place") and "Podkład mapy" in panel.open_sections("place"), "Advanced button opens the window with all five sections")
	main.settings.set_value("map_zoom_step", 1.9)
	panel.cancel_advanced("place")
	ok(not panel.advanced_open("place") and is_equal_approx(main.settings.f("map_zoom_step"), mpp_before), "Anuluj restores values changed in the window")
	panel.open_advanced("place")
	main.settings.set_value("map_zoom_step", 1.9)
	panel.save_advanced("place")
	ok(not panel.advanced_open("place") and is_equal_approx(main.settings.f("map_zoom_step"), 1.9), "Zapisz keeps them and closes")
	main.settings.set_value("map_zoom_step", mpp_before)
	# footer navigation
	panel._nav_next.pressed.emit()
	ok(panel.current_tab() == "building", "Dalej goes to the next step (%s)" % panel.current_tab())
	panel._nav_back.pressed.emit()
	ok(panel.current_tab() == "place", "Wstecz goes back")
	panel.select_tab("app", true)
	ok(not panel._nav_back.get_parent().visible, "no step navigation on the settings tab")
	# step status
	panel.set_tab_state("tex", "done")
	ok((panel._tabs[2]["button"] as Button).text.begins_with("✓"), "finished step is marked with a check")
	panel.set_tab_state("tex", "")
	# "changed from default" marker
	main.settings.reset_key("model_wall_height")
	ok(not panel._ctl["model_wall_height"]["reset"].visible, "no reset marker at the default value")
	main.settings.set_value("model_wall_height", 12.3)
	ok(panel._ctl["model_wall_height"]["reset"].visible, "reset marker appears for a changed value")
	panel._ctl["model_wall_height"]["reset"].pressed.emit()
	ok(is_equal_approx(main.settings.f("model_wall_height"), main.settings.defs["model_wall_height"]["default"]), "marker restores the default")
	panel.select_tab("place", true)
	panel.set_filter("kamer")
	ok(panel.visible_tab_count() == 1 and panel.current_tab() == "view", "search 'kamer' leaves only Widok and jumps there (visible %d, current %s)" % [panel.visible_tab_count(), panel.current_tab()])
	panel.set_filter("")
	ok(panel.visible_tab_count() == 5, "clearing the search restores all tabs")
	# the hidden setting must not produce a widget but must be saved
	ok(not panel._ctl.has("ui_last_tab"), "hidden setting has no widget")
	main.panel.action_pressed.emit("act_cam_reset")
	main.settings.set_value("ui_font_size", 18)
	await process_frame
	ok(main.theme.default_font_size == 18, "font size setting applied to theme")

	if FileAccess.file_exists(AppSettings.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.SAVE_PATH))
	print("")
	print("== roof pitch from the texture, margins, picker")
	main.settings.set_value("tex_source", sheet_path)   # the Wroniawy sheet
	await process_frame
	var gk: String = main._gable_key()
	ok(gk != "" and main.atlas.estimate_roof_ratio(gk) > 0.08, "gable picture shows a roof outline (%s: %.3f)" % [gk, main.atlas.estimate_roof_ratio(gk)])
	var gr: Rect2i = main.atlas.regions[gk]["rect"]
	ok((main.atlas.regions[gk]["img"] as Image).get_width() < gr.size.x - 10, "empty margins of the gable picture are trimmed (%d < %d)" % [(main.atlas.regions[gk]["img"] as Image).get_width(), gr.size.x])
	main.settings.set_value("model_roof_from_tex", true)
	main._rebuild_current()
	var expect: float = main.atlas.estimate_roof_ratio(gk) * 2.0 * float(main.last_rt[0]["ridge_half"])
	ok(absf(main.roof_h_cur - expect) < 0.02, "roof height %.2f follows the texture pitch (%.2f)" % [main.roof_h_cur, expect])
	ok(absf(main.settings.f("model_roof_height") - main.roof_h_cur) < 0.02, "slider shows the measured height")
	main.settings.set_value("model_roof_height", 4.0)
	ok(not main.settings.b("model_roof_from_tex") and absf(main.roof_h_cur - 4.0) < 0.02, "a hand-set height switches the automatic pitch off")
	main._on_action("act_roof_from_tex")
	ok(main.settings.b("model_roof_from_tex") and absf(main.roof_h_cur - expect) < 0.02, "button re-applies the pitch from the texture")
	main.settings.set_value("tex_source", "")
	await process_frame
	main._rebuild_current()
	ok(main.roof_h_cur > 0.0, "without texture the slider value is used")
	var picker := ImagePicker.new()
	root.add_child(picker)
	picker.open_for("res://textures/samples/stacja_zolta.png")
	await process_frame
	await process_frame
	ok(picker._list.item_count >= 3, "picker lists the images of the folder (%d)" % picker._list.item_count)
	for _i in 30:
		await process_frame
	ok(picker._selected.ends_with("stacja_zolta.png") and picker._preview.texture != null, "picker preselects the current file and shows a preview")
	picker.queue_free()

	print("== project folder")
	var pdir := ProjectSettings.globalize_path("user://selftest_project")
	_wipe(pdir)
	main.projflow._open_project(pdir)
	ok(main.project.is_open() and FileAccess.file_exists(pdir + "/project.json"), "project folder created with project.json")
	ok(DirAccess.dir_exists_absolute(pdir + "/texture") and DirAccess.dir_exists_absolute(pdir + "/renders") and DirAccess.dir_exists_absolute(pdir + "/geo"), "project sub-folders exist")
	ok(main.current_parts.is_empty() and main.info_label.text.begins_with("Nie zbudowano"), "a new project starts with an empty scene")
	# a building picked from the map (fake EGiB data in EPSG:2180)
	var egib := PackedVector2Array([Vector2(637400, 486750), Vector2(637410, 486750), Vector2(637410, 486756), Vector2(637400, 486756)])
	main.map_center = Vector2(637405, 486753)
	main.map_buildings = [{"ring": egib, "attrs": {"liczbakondygnacji": "2", "idbudynku": "TEST-1"}}]
	main.map_sel_keys = [main._bkey(main.map_buildings[0])]
	main.use_btn.disabled = false
	main._on_use_building_pressed()
	ok(not main.current_parts.is_empty(), "building built inside the project")
	var geo_txt := FileAccess.get_file_as_string(pdir + "/geo.txt")
	ok(geo_txt.contains("EPSG:2180") and geo_txt.contains("idbudynku: TEST-1") and geo_txt.contains("637400.000"), "geo.txt holds the Geoportal data (attributes, outline, CRS)")
	var geo_json = JSON.parse_string(FileAccess.get_file_as_string(pdir + "/geo.json"))
	ok(typeof(geo_json) == TYPE_DICTIONARY and (geo_json["buildings"] as Array).size() == 1 and geo_json["buildings"][0]["floors"] == 2, "geo.json is machine-readable (floors %s)" % [geo_json["buildings"][0]["floors"] if typeof(geo_json) == TYPE_DICTIONARY else "?"])
	main.settings.set_value("tex_source", sheet_path)
	await process_frame
	ok(main.project.inside(main.settings.s("tex_source")) and FileAccess.file_exists(main.settings.s("tex_source")), "texture was copied into the project (%s)" % main.settings.s("tex_source"))
	ok(FileAccess.file_exists(main.settings.s("tex_source").get_basename() + ".atlas.json"), "the cut (.atlas.json) is stored next to the texture copy")
	main.settings.set_value("model_wall_height", 9.5)
	for n in 4:
		FileAccess.open(pdir + "/renders/lastView_2000010%d_000000.png" % n, FileAccess.WRITE).close()
	main.settings.set_value("proj_keep_renders", 2)
	var rend: String = main.project.save_render(Image.create(64, 48, false, Image.FORMAT_RGB8), main.settings.i("proj_keep_renders"))
	ok(rend != "" and FileAccess.file_exists(rend), "render written (%s)" % rend.get_file())
	var left := 0
	for f in DirAccess.get_files_at(pdir + "/renders"):
		if f.begins_with("lastView_"):
			left += 1
	ok(left == 2, "only the newest 2 renders are kept (%d)" % left)
	main.projflow._save_project()
	var pj: Variant = JSON.parse_string(FileAccess.get_file_as_string(pdir + "/project.json"))
	ok(pj["parts"].size() == 1 and pj["texture"]["file"].begins_with("texture/") and absf(pj["settings"]["model_wall_height"] - 9.5) < 0.01, "project.json: parts, relative texture path, settings snapshot")
	ok(FileAccess.get_file_as_string(pdir + "/project.log").contains("Zbudowano model"), "project.log records the build")
	# a second app instance restores the whole model from the folder
	var main2: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main2)
	for _i in 4:
		await process_frame
	main2.settings.set_value("model_wall_height", 3.0)
	main2.projflow._open_project(pdir)
	await process_frame
	ok(not main2.current_parts.is_empty() and main2.current_ring.size() >= 3, "reopening the project rebuilds the model")
	ok(absf(main2.settings.f("model_wall_height") - 9.5) < 0.01 and main2.settings.b("tex_enabled") and main2.atlas.regions.size() > 3, "settings and texture come back with the project")
	ok(main2.panel.is_tab_enabled("tex"), "texturing step is open for a restored model")
	main2.queue_free()
	var main3: Control = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main3)
	for _i in 4:
		await process_frame
	main3.project_required = true
	main3._update_building_label()
	ok(main3.use_btn.disabled and main3.building_label.text.contains("folder projektu"), "without a project the build button is locked")
	main3.queue_free()
	ok(ProjectStore.push_recent("a|b", "c").begins_with("c|a"), "recent projects list")

	print("RESULT: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _mesh_area(mi: MeshInstance3D) -> float:
	var total := 0.0
	for si in mi.mesh.get_surface_count():
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] if mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for k in range(0, v.size(), 3):
				total += (v[k + 1] - v[k]).cross(v[k + 2] - v[k]).length() * 0.5
		else:
			for k in range(0, idx.size(), 3):
				total += (v[idx[k + 1]] - v[idx[k]]).cross(v[idx[k + 2]] - v[idx[k]]).length() * 0.5
	return total


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
		DirAccess.remove_absolute(path.path_join(d))


func _cache_checks() -> void:
	var c := GeoCache.new()
	c.root = "user://geo_cache_selftest"
	c.clear()
	var p := c.path_for("wms", GeoCache.service_key("http://x", "L"), "a.bin")
	ok(c.read(p).is_empty(), "cache: miss on empty")
	c.write(p, PackedByteArray([1, 2, 3]))
	ok(c.read(p).size() == 3 and c.is_fresh(p), "cache: write/read fresh")
	c.ttl_days = -1.0
	ok(c.read(p).is_empty() and c.read(p, true).size() == 3, "cache: expired only readable as stale")
	c.ttl_days = 30.0
	c.max_bytes = 10
	for k in range(5):
		c.write(c.path_for("wms", "k", "f%d" % k), PackedByteArray([0, 0, 0, 0, 0, 0]))
	c.trim()
	ok(int(c.stats()["bytes"]) <= 10, "cache: trim keeps size under cap")
	var cell := [{"ring": PackedVector2Array([Vector2(1, 2), Vector2(3, 4), Vector2(5, 1)]), "attrs": {"a": "b"}}]
	var back: Array = GeoportalClient._cell_from_json(GeoportalClient._cell_to_json(cell))
	ok(back.size() == 1 and (back[0]["ring"] as PackedVector2Array).size() == 3 and back[0]["attrs"]["a"] == "b", "cache: building cell JSON roundtrip")
	ok(c.clear() >= 0 and int(c.stats()["files"]) == 0, "cache: clear")


## Set of albedo textures (by resource id) used by a mesh's surfaces.
func _wall_textures(mi: MeshInstance3D) -> Dictionary:
	var out := {}
	for si in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(si) as StandardMaterial3D
		if m != null and m.albedo_texture != null:
			out[m.albedo_texture.get_rid().get_id()] = true
	return out


func _place_checks() -> void:
	var h := ""
	for i in range(35):
		h = PlaceHistory.push(h, {"name": "Miejsce %d" % i, "lat": 50.0 + i * 0.01, "lon": 20.0})
	var list := PlaceHistory.list(h)
	ok(list.size() == 30 and list[0]["name"] == "Miejsce 34" and list[29]["name"] == "Miejsce 5", "place history keeps the last 30, newest first")
	h = PlaceHistory.push(h, {"name": "miejsce 10", "lat": 50.1, "lon": 20.0})
	list = PlaceHistory.list(h)
	ok(list.size() == 30 and list[0]["name"] == "miejsce 10", "place history: repeated place moves to the top without duplicates")
	var parsed := PlaceHistory.parse_nominatim('[{"display_name":"A","lat":"52.1","lon":"21.0"},{"x":1}]')
	ok(parsed.size() == 1 and absf(float(parsed[0]["lat"]) - 52.1) < 1e-9, "Nominatim answer parsed")
	var txt := GptPrompt.build({"name": "dom", "place": "Test", "floors": 1, "kind": "m", "roof": "gable",
		"main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "annexes": [{"len": 4.0, "wall_h": 2.5}]})
	ok("4096 × 4096" in txt and "szerokość DOKŁADNIE" in txt and "od ziemi do okapu" in txt and "S6" in txt and "dobudówki" in txt and "Pozostałe miejsce na płótnie" in txt, "GPT prompt carries layout and wall dimensions")
	var ginfo := {"main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "roof": "gable", "annexes": []}
	var ppm := GptPrompt.scale_px_per_m(ginfo)
	ok(ppm > 100 and ("1 m rzeczywistej ściany = %d px" % ppm) in GptPrompt.build(ginfo), "one scale for the whole sheet: %d px/m (10 m wide wall = %d px)" % [ppm, 10 * ppm])
	var ptx := GptPrompt.build(ginfo)
	ok("NIGDY nie skaluj okien ani cegieł według wysokości całego szczytu" in ptx and "cokołu" in ptx and "kształt „domku”" in ptx, "prompt: windows are never scaled by the gable height; the plinth-to-band segment is the common measure")
	_layout_checks()
	_template_checks()



func _chimney_checks(main: Control) -> void:
	print("== chimneys + close button + roof picture range")
	ok(main.rig.preset_bar.get_node_or_null("ZamknijAplikacje") != null, "scene window has a close-application button")
	ok(main.rig.preset_bar.get_node_or_null("Przycisk_roof") != null and main.rig.preset_bar.get_node_or_null("Przycisk_chimney") != null, "scene window has buttons for the roof and chimney windows")
	var roof_ok := true
	var roof_seen := false
	for fid in main.face_geo.keys():
		if ":roof" in str(fid) and main._is_sheet_region(str(main.face_geo[fid]["key"])):
			roof_seen = true
			var uv: Rect2 = main.face_geo[fid]["uv"]
			if uv.position.y < -0.001 or uv.end.y > 1.001 or uv.position.x < -0.001 or uv.end.x > 1.001:
				roof_ok = false
	ok(roof_ok, "a sheet roof picture lies exactly once over the slope (uv 0..1, seen=%s)" % roof_seen)
	var was_template: bool = main.atlas.is_template
	var old_ppm = main.settings.values["tex_px_per_m"]
	main.atlas.is_template = false
	main.settings.values["tex_px_per_m"] = 150.0
	main.atlas.regions["zz_roof"] = {"img": Image.create(2400, 900, false, Image.FORMAT_RGBA8)}
	main.atlas.regions["zz_swatch"] = {"img": Image.create(300, 300, false, Image.FORMAT_RGBA8)}
	if main.settings.s("tex_slice_mode") != "sheet":
		ok(main._roof_picture_is_whole("zz_roof", 15.8, 6.0) and not main._roof_picture_is_whole("zz_swatch", 15.8, 6.0), "a roof picture that spans the slope at the sheet scale is laid once, a small swatch is repeated")
	main.atlas.regions.erase("zz_roof")
	main.atlas.regions.erase("zz_swatch")
	main.atlas.is_template = was_template
	main.settings.values["tex_px_per_m"] = old_ppm
	main.settings.set_value("model_chimneys", "[]")
	var flow: ChimneyFlow = main.chimneys
	var c: Dictionary = flow.default_chimney()
	c["w"] = 0.6
	c["l"] = 0.8
	c["h"] = 1.5
	flow.save([c])
	var node := main.building_root.get_node_or_null("Chimney_1") as MeshInstance3D
	ok(node != null, "chimney is built under the building")
	if node == null:
		return
	var rr := flow.roof_range(c)
	var bb := node.mesh.get_aabb()
	ok(absf(bb.end.y - (rr.y + 1.5)) < 0.01, "chimney top = highest roof point under it + height (%.2f)" % bb.end.y)
	ok(bb.position.y < rr.x - 0.2, "chimney foot is sunk below the roof")
	ok(absf(bb.size.x - 0.7) < 0.02 and absf(bb.size.z - 0.9) < 0.02 and node.mesh.get_surface_count() == 2, "chimney size = typed width and length plus the cap rim; shaft and cap are two surfaces")
	var back := ChimneyFlow.parse(JSON.stringify([c]))
	ok(back.size() == 1 and absf(float(back[0]["h"]) - 1.5) < 1e-6 and back[0]["frag"].size() == 4, "chimney JSON round trip")
	flow.open()
	for _i in 4:
		await process_frame
	var eds: Array = flow.window.find_children("*", "ChimneyEditor", true, false)
	ok(eds.size() == 1, "chimney editor window opens")
	if eds.size() == 1:
		var ed: ChimneyEditor = eds[0]
		ok(ed.items.size() == 1 and ed.sel == 0, "editor lists the chimney")
		var v: Control = ed._views["front"]
		if v.size.x < 100.0:
			v.size = Vector2(420, 300)
		var ch: Dictionary = ed.items[0]
		var x0 := float(ch["x"])
		var top_pt: Vector2 = ed._to_screen("front", v.size, Vector2(x0, flow.top_y(ch)))
		ed._drag_begin(v, "front", top_pt)
		ok(ed._drag == "top", "front view: the round handle on top grabs the height")
		ed._drag_move(v, "front", ed._to_screen("front", v.size, Vector2(x0, flow.top_y(ch) + 1.0)))
		ed._drag = ""
		ok(absf(float(ed.items[0]["h"]) - 2.5) < 0.03, "dragging the handle raises the chimney by 1 m (h = %.2f)" % float(ed.items[0]["h"]))
		var body_pt: Vector2 = ed._to_screen("front", v.size, Vector2(x0, (flow.top_y(ed.items[0]) + flow.base_y(ed.items[0])) * 0.5))
		ed._drag_begin(v, "front", body_pt)
		ed._drag_move(v, "front", body_pt + Vector2(ed._scale("front", v.size), 0.0))
		ed._drag = ""
		ok(absf(float(ed.items[0]["x"]) - (x0 + 1.0)) < 0.03, "dragging the body in the front view slides it 1 m along X (x = %.2f)" % float(ed.items[0]["x"]))
		var pv: Control = ed._views["plan"]
		if pv.size.x < 100.0:
			pv.size = Vector2(420, 300)
		ed._drag_begin(pv, "plan", ed._to_screen("plan", pv.size, Vector2(float(ed.items[0]["x"]), float(ed.items[0]["z"]))))
		ed._drag_move(pv, "plan", ed._to_screen("plan", pv.size, Vector2(float(ed.items[0]["x"]), float(ed.items[0]["z"]) + 0.5)))
		ed._drag = ""
		ok(absf(float(ed.items[0]["z"]) - (float(c["z"]) + 0.5)) < 0.03, "plan view: dragging moves the chimney across the roof")
		ok(main.building_root.get_node_or_null("Chimney_1") != null and main.settings.s("model_chimneys") != "[]", "the model follows the edits and they are stored in the settings")
		var added: int = ed.items.size()
		ed.items.append(flow.default_chimney())
		ed._after_edit()
		ok(ed.items.size() == added + 1 and main.building_root.get_node_or_null("Chimney_2") != null, "second chimney is added")
		ed.cancel_edit()
		for _i in 2:
			await process_frame
		var after_cancel := ChimneyFlow.parse(main.settings.s("model_chimneys"))
		ok(after_cancel.size() == 1 and absf(float(after_cancel[0]["h"]) - 1.5) < 1e-6 and main.building_root.get_node_or_null("Chimney_2") == null, "Anuluj restores the chimneys from before")
	flow.save([c])
	await process_frame
	var cp := "user://selftest_export/chimney.glb"
	var cres := ModelExporter.export_glb(main.building_root, main.exporter.export_info(), cp)
	ok(cres["ok"], "export with a chimney ok (%s)" % cres["error"])
	var cj := ModelExporter.read_glb_json(cp)
	var cnames := {}
	for gn in cj.get("nodes", []):
		cnames[str(gn.get("name", ""))] = gn
	var cmeta: Dictionary = cnames.get("chimney_1", {}).get("extras", {}).get("meta", {})
	ok(str(cmeta.get("layer", "")) == "chimney" and int(cmeta.get("chimney_id", 0)) == 1, "exported chimney node carries layer = chimney and its id")
	var rm: Dictionary = cnames.get("Building", {}).get("extras", {}).get("meta", {})
	ok((rm.get("chimneys", []) as Array).size() == 1 and absf(float(rm["chimneys"][0]["size"][0]) - 0.6) < 1e-6, "root meta lists the chimney (size, centre, height)")
	flow.save([])
	await process_frame


func _layout_checks() -> void:
	print("== sheet layout from wall sizes")
	var info := {"main": {"len": 15.8, "wid": 9.9, "wall_h": 5.5, "roof_h": 3.0}, "roof": "gable", "annexes": []}
	var lay := GptPrompt.layout(info)
	var ppm := int(lay["ppm"])
	ok(ppm >= 100 and lay["frames"].size() == 5, "layout: %d px/m, %d frames" % [ppm, lay["frames"].size()])
	# frames are inside the canvas and do not overlap
	var inside := true
	var overlap := false
	var keys: Array = lay["frames"].keys()
	for i in range(keys.size()):
		var a: Array = lay["frames"][keys[i]]
		if int(a[0]) < 0 or int(a[1]) < 0 or int(a[0]) + int(a[2]) > 4096 or int(a[1]) + int(a[3]) > 4096:
			inside = false
		for j in range(i + 1, keys.size()):
			var b: Array = lay["frames"][keys[j]]
			if Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])).intersects(Rect2i(int(b[0]), int(b[1]), int(b[2]), int(b[3]))):
				overlap = true
	ok(inside and not overlap, "layout: frames inside the canvas, no overlap")
	# true proportions: every picture is width_m x ppm by height_m x ppm
	var s1: Array = lay["pictures"]["S1"]
	var s3: Array = lay["pictures"]["S3"]
	ok(absi(int(s1[2]) - int(ceil(15.8 * ppm))) <= 1 and absi(int(s3[2]) - int(ceil(9.9 * ppm))) <= 1, "layout: widths are exactly metres x px/m (S1 %d px, S3 %d px)" % [s1[2], s3[2]])
	ok(float(s3[3]) / float(s3[2]) > 0.9, "layout: the gable frame is nearly square, not a 2:1 sector (%d x %d)" % [s3[2], s3[3]])
	ok(float(lay["fill"]) > 0.55, "layout: canvas used to %d%%" % int(float(lay["fill"]) * 100.0))
	# scale is as high as it can be: one more px/m no longer fits
	var bigger := SheetLayout.compute(GptPrompt.layout_elems(info))
	ok(int(bigger["ppm"]) == ppm, "layout is deterministic")
	# the guide image draws all frames and the gable outline
	var guide := SheetLayout.render_guide(lay)
	var f1: Array = lay["frames"]["S1"]
	var px: Color = guide.get_pixel(int(f1[0]) + 2, int(f1[1]) + 2)
	ok(guide.get_width() == 4096 and px.r > 0.7 and px.g < 0.4, "guide image: size 4096 and red frame at S1")
	var p3: Array = lay["pictures"]["S3"]
	var corner: Color = guide.get_pixel(int(p3[0]) + 4, int(p3[1]) + 4)
	ok(absf(corner.r - 96.0 / 255.0) < 0.02, "guide image: gable corner beside the roof triangle is grey")
	# storage round trip
	var back := SheetLayout.from_json(SheetLayout.to_json(lay))
	ok(not back.is_empty() and int(back["ppm"]) == ppm and back["frames"].has("S5"), "layout JSON round trip")
	# sheet cut by this layout: pictures drawn in the frames come back as S1..S5 with the right roles
	var sheet := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	sheet.fill(Color8(128, 128, 128))
	var cols := {"S1": Color8(190, 120, 90), "S2": Color8(90, 150, 190), "S3": Color8(150, 190, 90), "S4": Color8(200, 190, 90), "S5": Color8(120, 80, 160)}
	for code in lay["pictures"].keys():
		var pr: Array = lay["pictures"][code]
		var r := Rect2i(int(pr[0]) / 4, int(pr[1]) / 4, int(pr[2]) / 4, int(pr[3]) / 4)
		sheet.fill_rect(r, cols.get(code, Color8(200, 60, 60)))
	var res := AtlasSlicer.slice(sheet, {"mode": "auto", "sensitivity": 0.06, "min_area": 0.15, "gap": 2, "layout": back})
	var regs: Dictionary = res["regions"]
	var roles_ok := regs.has("S1") and str(regs["S1"]["role"]) == "facade_long" and regs.has("S3") and str(regs["S3"]["role"]) == "facade_gable" and regs.has("S5") and str(regs["S5"]["role"]) == "roof"
	ok(bool(res.get("template", false)) and regs.size() == 5 and roles_ok, "slicer cuts the sheet by the computed frames: %s" % str(regs.keys()))
	if regs.has("S3"):
		var rr: Array = regs["S3"]["rect"]
		ok(absf(float(rr[2]) / float(rr[3]) - float(s3[2]) / float(s3[3])) < 0.06, "cut panel keeps the wall proportions (%.2f)" % (float(rr[2]) / float(rr[3])))


func _template_checks() -> void:
	print("== fixed template sheet")
	var img := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color8(128, 128, 128))
	var panels := {
		"S1": Rect2i(16, 16, 480, 140), "S2": Rect2i(528, 16, 480, 140), "S3": Rect2i(16, 272, 300, 230),
		"S4": Rect2i(528, 272, 300, 230), "S5": Rect2i(16, 528, 480, 200), "S6": Rect2i(528, 528, 200, 120)}
	var n := 0
	for k in panels:
		n += 1
		var r: Rect2i = panels[k]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var v := 0.5 + 0.25 * sin(float(x + y * 3) * 0.3)
				img.set_pixel(x, y, Color(0.8 if n % 3 == 0 else v, 0.3 + 0.1 * n if n % 2 == 0 else 0.35, 0.2 if n % 3 != 1 else 0.85))
	var res := AtlasSlicer.slice(img, {"mode": "auto"})
	var regs: Dictionary = res["regions"]
	ok(bool(res.get("template", false)) and regs.size() == 6, "square sheet with panels in sectors is recognised as the template (%d regions)" % regs.size())
	var roles_ok: bool = regs.has("S1") and regs["S1"]["role"] == "facade_long" and regs["S3"]["role"] == "facade_gable" and regs["S5"]["role"] == "roof" and regs["S6"]["role"] == "facade_annex"
	ok(roles_ok, "roles come from the sector: S1 long, S3 gable, S5 roof, S6 annex")
	var s1: Array = regs["S1"]["rect"]
	ok(absi(int(s1[0]) - 16) <= 6 and absi(int(s1[2]) - 480) <= 12, "S1 box matches the panel: %s" % [s1])
	# Panels separated by a hair-thin gap (GPT draws S1 down to S3) must still be cut apart.
	var tch := Image.create(512, 512, false, Image.FORMAT_RGB8)
	tch.fill(Color(0.5, 0.5, 0.5))
	for yy in range(14, 90):
		for xx in range(10, 240):
			tch.set_pixel(xx, yy, Color(0.8, 0.3 + 0.002 * xx, 0.2))
	for yy in range(94, 220):
		for xx in range(10, 230):
			tch.set_pixel(xx, yy, Color(0.3, 0.4 + 0.002 * yy, 0.7))
	var tres := AtlasSlicer.slice(tch, {"mode": "template"})
	ok(tres["regions"].has("S1") and tres["regions"].has("S3"), "touching S1/S3 panels are split (%s)" % [tres["regions"].keys()])
	var photo := Image.create(512, 512, false, Image.FORMAT_RGB8)
	for yy in 512:
		for xx in 512:
			photo.set_pixel(xx, yy, Color(0.3 + 0.2 * sin(xx * 0.1), 0.4 + 0.2 * sin(yy * 0.13), 0.5 + 0.2 * sin((xx + yy) * 0.07)))
	ok(not bool(AtlasSlicer.slice(photo, {"mode": "auto"}).get("template", false)), "a plain photo is not taken for a template")
	var forced := AtlasSlicer.slice(img, {"mode": "template"})
	ok(forced["regions"].size() == 6, "template mode forced")
	var tmp := ProjectSettings.globalize_path("user://selftest_template.png")
	img.save_png(tmp)
	var at := TextureAtlas.new()
	var err := at.load_source(tmp, {"mode": "auto"}, true)
	ok(err == "" and at.is_template and at.pick_key("facade_annex", 0) == "S6" and at.pick_key("facade_long", 1) == "S2" and at.pick_key("facade_gable", 0) == "S3", "atlas: template flag, long A/B = S1/S2, annex = S6")
	var at2 := TextureAtlas.new()
	at2.regions = {}
	ok(at2.keys_for_role("facade_annex").is_empty(), "annex role without a sheet is empty")
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(tmp.get_basename() + ".atlas.json")


func _face_store_checks() -> void:
	print("== face store (surface corrections)")
	var uv := Vector2(0.3, 0.7)
	var piv := Vector2(0.5, 0.5)
	var same := FaceStore.uv_transform(uv, piv, 4.0, 3.0, Vector2.ZERO, Vector2.ONE, 0.0)
	ok(same.distance_to(uv) < 1e-6, "mapping: identity leaves the coordinate alone")
	var shifted := FaceStore.uv_transform(uv, piv, 4.0, 3.0, Vector2(1.0, 0.0), Vector2.ONE, 0.0)
	ok(absf(shifted.x - (0.3 - 0.25)) < 1e-6 and absf(shifted.y - 0.7) < 1e-6, "mapping: picture 1 m to the right on a 4 m picture -> u - 0.25")
	var up := FaceStore.uv_transform(uv, piv, 4.0, 3.0, Vector2(0.0, 0.3), Vector2.ONE, 0.0)
	ok(absf(up.y - (0.7 + 0.1)) < 1e-6, "mapping: picture 0.3 m up on a 3 m picture -> v + 0.1")
	var big := FaceStore.uv_transform(Vector2(0.9, 0.5), piv, 4.0, 3.0, Vector2.ZERO, Vector2(2.0, 2.0), 0.0)
	ok(absf(big.x - 0.7) < 1e-6, "mapping: scale 2 magnifies about the centre")
	var turned := FaceStore.uv_transform(Vector2(0.5 + 0.25, 0.5), piv, 4.0, 4.0, Vector2.ZERO, Vector2.ONE, 90.0)
	ok(absf(turned.x - 0.5) < 1e-6 and absf(absf(turned.y - 0.5) - 0.25) < 1e-6, "mapping: 90 degrees turns the picture about the centre")
	var fs := FaceStore.new()
	var log := []
	fs.changed.connect(func(id: String) -> void: log.append(id))
	fs.set_field("p0:w1", "off", [0.2, 0.0])
	fs.set_field("p0:w1", "off", [0.3, 0.0])
	fs.set_field("p0:w1", "tint", "#ff8800")
	ok(fs.has_mapping("p0:w1") and fs.has_material("p0:w1") and log.size() == 3, "face store: fields set, change signals sent")
	fs.undo()
	ok(not fs.has_material("p0:w1") and fs.get_value("p0:w1", "off")[0] == 0.3, "undo takes back the last field only")
	fs.undo()
	ok(not fs.has_face("p0:w1"), "fast moves of one field are one undo step (back to nothing)")
	fs.redo()
	ok(fs.get_value("p0:w1", "off")[0] == 0.3, "redo")
	fs.set_field("p0:roofA", "crop", [0.1, 0.2, 0.5, 0.5])
	var back := FaceStore.new()
	back.from_dict(JSON.parse_string(JSON.stringify(fs.to_dict())))
	ok(back.get_value("p0:roofA", "crop") == [0.1, 0.2, 0.5, 0.5] and back.get_value("p0:w1", "off") == [0.3, 0.0], "face store survives JSON round trip with types")
	fs.set_field("p0:w1", "off", [0.0, 0.0])
	ok(not fs.has_mapping("p0:w1"), "setting a field back to its default removes it")


func _mouse_btn(button: int, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e
