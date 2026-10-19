class_name ProjectFlow
extends RefCounted
## Project folder: open / create, save and restore the scene, write geo.txt and the ortho crop, render on quit.

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


var project_dialog: ProjectDialog


var _restoring = false               # true while a app.project is being loaded: app.settings changes do not rebuild


## Keys that belong to the application, not to a model: not stored in app.project.json.
const PROJECT_SKIP_PREFIXES := ["ui_", "svc_", "src_", "proj_", "map_start_"]


const NO_MODEL_TEXT := "Nie zbudowano jeszcze modelu.\nW kroku 1 (Miejsce) zaznacz budynek na mapie i kliknij „Zbuduj model 3D”."


func _project_ok() -> bool:
	return app.project.is_open() or not app.project_required


func _update_project_bar() -> void:
	if app.project_label == null:
		return
	if app.project.is_open():
		app.project_label.text = "Projekt: " + app.project.project_name()
		app.project_label.tooltip_text = app.project.dir
		app.project_label.remove_theme_color_override("font_color")
	else:
		app.project_label.text = "Brak projektu – wskaż folder"
		app.project_label.add_theme_color_override("font_color", Color("#ffc46b"))


func _show_project_dialog(can_cancel: bool, hint := "") -> void:
	if project_dialog == null:
		project_dialog = ProjectDialog.new()
		project_dialog.chosen.connect(_open_project)
		project_dialog.chosen_file.connect(open_mgdot)
		app.add_child(project_dialog)
	project_dialog.show_dialog(app.settings.s("ui_recent_projects"), can_cancel, hint, app.settings.s("ui_recent_mgdot"))


## Opens (or creates) a app.project folder, empties the scene and restores what the app.project holds.
func _open_project(folder: String) -> void:
	if app.project.is_open():
		_save_project()
		app.project.close()
	var err = app.project.open(folder)
	if err != "":
		app._set_status(err)
		_update_project_bar()
		_show_project_dialog(false, err)
		return
	app.settings.set_value("ui_last_project", app.project.dir)
	app.settings.set_value("ui_recent_projects", ProjectStore.push_recent(app.settings.s("ui_recent_projects"), app.project.dir))
	_clear_scene()
	_restore_project()
	_update_project_bar()
	app._update_building_label()
	app._update_steps()
	if not app.current_parts.is_empty():
		app.panel.select_tab("building", true)
		app._set_status("Projekt otwarty, model odtworzony: " + app.project.dir)
	else:
		app.panel.select_tab("place", true)
		app._set_status("Projekt: " + app.project.dir + " – zaznacz budynek na mapie.")


# ------------------------------------------------------------------ .mgdot (project file)

var _mgdot_dialog: FileDialog


## Save the project as one .mgdot file. Asks for the name the first time (or always with `save_as`).
func save_mgdot(save_as := false) -> void:
	if not app.project.is_open():
		app._set_status("Najpierw wskaż folder projektu.")
		return
	var last := str(app.project.data.get("mgdot_path", ""))
	if not save_as and last != "" and DirAccess.dir_exists_absolute(last.get_base_dir()):
		_write_mgdot(last)
		return
	if _mgdot_dialog == null:
		_mgdot_dialog = FileDialog.new()
		_mgdot_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_mgdot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_mgdot_dialog.title = "Zapisz projekt jako .mgdot"
		_mgdot_dialog.filters = PackedStringArray(["*.mgdot ; Projekt Photo-to-3D Studio"])
		_mgdot_dialog.file_selected.connect(func(p: String) -> void:
			_write_mgdot(p if p.get_extension().to_lower() == MgDot.EXT else p + "." + MgDot.EXT))
		app.add_child(_mgdot_dialog)
	_mgdot_dialog.current_dir = last.get_base_dir() if last != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_mgdot_dialog.current_file = (last.get_file() if last != "" else app.project.project_name() + "." + MgDot.EXT)
	_mgdot_dialog.popup_centered_ratio(0.6)


func _write_mgdot(path: String) -> void:
	app.project.data["mgdot_path"] = path
	_save_project()
	var thumb: Image = null
	if DisplayServer.get_name() != "headless" and app.subviewport != null and not app.current_parts.is_empty():
		thumb = app.subviewport.get_texture().get_image()
		if thumb != null and thumb.get_width() > 8:
			thumb.resize(480, int(480.0 * thumb.get_height() / thumb.get_width()), Image.INTERPOLATE_BILINEAR)
		else:
			thumb = null
	var prompt := ""
	if not app.last_rt.is_empty():
		prompt = GptPrompt.build(app.gpt.gpt_info())
	var summary := {"source": app.current_source, "floors": app.current_floors, "parts": app.current_parts.size()}
	var err := MgDot.pack(app.project.dir, path, {"thumbnail": thumb, "prompt": prompt, "summary": summary})
	if err != "":
		app._set_status(err)
		return
	app.settings.set_value("ui_recent_mgdot", ProjectStore.push_recent(app.settings.s("ui_recent_mgdot"), path))
	app.project.log_event("Zapisano plik projektu: " + path)
	app._set_status("Projekt zapisany: " + path)


## Opens a .mgdot: unpacks it to <file>_projekt (or reuses that folder when it is exactly this save) and opens it.
func open_mgdot(path: String) -> void:
	var msg := MgDot.check(path)
	if msg != "":
		app._set_status(msg)
		_show_project_dialog(app.project.is_open(), msg)
		return
	var wf := MgDot.work_folder(path)
	if not bool(wf["reuse"]):
		var err := MgDot.unpack(path, str(wf["dir"]))
		if err != "":
			app._set_status(err)
			return
	app.settings.set_value("ui_recent_mgdot", ProjectStore.push_recent(app.settings.s("ui_recent_mgdot"), path))
	_open_project(str(wf["dir"]))
	if app.project.is_open():
		app.project.data["mgdot_path"] = path
		app._set_status("Otwarto plik projektu: " + path)


## Empty scene: no building, no texture, no selection.
func _clear_scene() -> void:
	_restoring = true
	app.settings.set_value("tex_source", "")
	app.settings.set_value("tex_enabled", false)
	_restoring = false
	app._clear_building()
	app.faces.clear()
	app._select_face("")
	app.current_ring = []
	app.current_parts = []
	app.current_floors = 0
	app.current_source = "brak"
	app.map_sel_keys.clear()
	app.map_selected = -1
	app.atlasflow._load_atlas("", false)
	app.info_label.text = NO_MODEL_TEXT
	app.parts_ui._refresh_parts_ui_if_needed()
	app.map_canvas.queue_redraw()


func _restore_project() -> void:
	var d: Dictionary = app.project.data
	var snap: Dictionary = d.get("settings", {})
	var tex: Dictionary = d.get("texture", {})
	var tex_path = app.project.resolve(str(tex.get("file", "")))
	_restoring = true
	for k in snap.keys():
		if app.settings.defs.has(k) and k != "tex_source":
			app.settings.set_value(k, snap[k])
	app.settings.set_value("tex_source", tex_path if tex_path != "" and FileAccess.file_exists(tex_path) else "")
	var m: Dictionary = d.get("map", {})
	if m.has("center") and (m["center"] as Array).size() == 2:
		app.map_center = Vector2(float(m["center"][0]), float(m["center"][1]))
		app.map_mpp = float(m.get("mpp", app.map_mpp))
	_restoring = false
	app.atlasflow._load_atlas(app.settings.s("tex_source"), false)
	var items: Array = []
	for pr in d.get("parts", []):
		items.append({
			"raw": pr["raw"], "floors": int(pr.get("floors", 0)), "area": float(pr.get("area", 0.0)),
			"wall_h": float(pr.get("wall_h", -1.0)), "roof": str(pr.get("roof", "auto")), "roof_h": float(pr.get("roof_h", -1.0)),
		})
	if items.is_empty():
		return
	app.current_floors = int(d.get("floors", 0))
	app.faces.from_dict(d.get("faces", {}))
	app.mapping.rectified = d.get("rectified", {}) if typeof(d.get("rectified", {})) == TYPE_DICTIONARY else {}
	if app._build_parts(items, true):
		app.current_source = str(d.get("source", "projekt"))
		app._update_info()
	app._refresh_map()


func _save_project() -> void:
	if not app.project.is_open() or _restoring:
		return
	var snap := {}
	for k in app.settings.values.keys():
		var skip: bool = k == "tex_source"
		for pre in PROJECT_SKIP_PREFIXES:
			if str(k).begins_with(pre):
				skip = true
		if not skip:
			snap[k] = app.settings.values[k]
	var d: Dictionary = app.project.data
	d["settings"] = snap
	d["source"] = app.current_source
	d["floors"] = app.current_floors
	var parts_out: Array = []
	for pr in app.current_parts:
		var raw: Array = []
		for q in pr["raw"]:
			raw.append([float(q[0]), float(q[1])])
		parts_out.append({
			"raw": raw, "floors": int(pr.get("floors", 0)), "area": float(pr.get("area", 0.0)),
			"wall_h": float(pr.get("wall_h", -1.0)), "roof": str(pr.get("roof", "auto")), "roof_h": float(pr.get("roof_h", -1.0)),
		})
	if parts_out.is_empty():
		d.erase("parts")
	else:
		d["parts"] = parts_out
	if app.mapping.rectified.is_empty():
		d.erase("rectified")
	else:
		d["rectified"] = app.mapping.rectified
	d.erase("describe")
	if app.faces.faces.is_empty():
		d.erase("faces")
	else:
		d["faces"] = app.faces.to_dict()
	var tex_file = app.settings.s("tex_source")
	if tex_file != "":
		d["texture"] = {
			"file": app.project.relative(tex_file),
			"atlas": app.project.relative(app.atlas.sidecar_path) if app.atlas.sidecar_path != "" else "",
			"mode": app.atlas.sheet_mode, "regions": app.atlas.regions.size(),
		}
	else:
		d.erase("texture")
	d["map"] = {"center": [app.map_center.x, app.map_center.y], "mpp": app.map_mpp}
	app.project.save()


## Render of the 3D view -> renders/lastView_<timestamp>.png (older ones beyond the limit are removed).
func _save_render() -> String:
	if not app.project.is_open() or app.subviewport == null or app.current_parts.is_empty():
		return ""
	if DisplayServer.get_name() == "headless":
		return ""   # the dummy renderer has no pixels to read
	var img = app.subviewport.get_texture().get_image()
	if img == null or img.get_width() < 8:
		return ""
	return app.project.save_render(img, app.settings.i("proj_keep_renders"))


func _on_quit() -> void:
	if app.project.is_open():
		_save_render()
		_save_project()
		app.project.log_event("Program zamknięty")
	app.settings.save()
	app.get_tree().quit()


## app.geo.txt (readable) + app.geo.json (machine-readable) + app.geo/ortho.png (orthophoto crop) in the app.project.
## buildings: [{"ring": PackedVector2Array, "attrs": Dictionary}]
func _write_geo(source: String, buildings: Array) -> void:
	if not app.project.is_open() or buildings.is_empty():
		return
	var geographic := source.begins_with("plik")
	var ll = GeoportalClient.e2180_to_lonlat(app.map_center.x, app.map_center.y)
	var lines: Array[String] = []
	lines.append("Photo-to-3D Studio – dane z Geoportalu")
	lines.append("=======================================")
	lines.append("Zapisano:       " + ProjectStore.timestamp())
	lines.append("Projekt:        " + app.project.project_name())
	lines.append("Źródło:         " + source)
	if not geographic:
		lines.append("Układ:          EPSG:2180 (PUWG 1992), współrzędne E N w metrach")
		lines.append("Widok mapy:     E %.2f  N %.2f  (lon %.6f  lat %.6f), skala %.3f m/px" % [app.map_center.x, app.map_center.y, ll.x, ll.y, app.map_mpp])
		lines.append("Ortofotomapa:   %s  warstwa: %s" % [app.settings.s("svc_wms_url"), app.settings.s("svc_wms_layer")])
		lines.append("Obrysy (WFS):   %s  typy: %s" % [app.settings.s("svc_wfs_url"), app.settings.s("svc_wfs_typenames")])
	else:
		lines.append("Układ:          taki jak w pliku (lon/lat albo metry lokalne)")
	lines.append("Części budynku: %d" % buildings.size())
	var json_buildings: Array = []
	var all_pts := PackedVector2Array()
	var total_area := 0.0
	for n in range(buildings.size()):
		var b: Dictionary = buildings[n]
		var ring: PackedVector2Array = b["ring"]
		var st = app._ring_stats(ring)
		total_area += float(st["area"])
		all_pts.append_array(ring)
		var attrs: Dictionary = b.get("attrs", {})
		lines.append("")
		lines.append("[Część %d]%s" % [n + 1, " (największa = bryła główna)" if n == 0 else ""])
		lines.append("  Powierzchnia:  %.1f m²,  obwód: %.1f m,  wymiary: %.1f × %.1f m" % [st["area"], st["perimeter"], st["length"], st["width"]])
		var fl = app._floors_from_attrs(attrs)
		if fl > 0:
			lines.append("  Kondygnacje:   %d" % fl)
		if not geographic and ring.size() > 0:
			var c := Vector2.ZERO
			for q in ring:
				c += q
			c /= float(ring.size())
			var cll := GeoportalClient.e2180_to_lonlat(c.x, c.y)
			lines.append("  Środek:        E %.2f  N %.2f  (lon %.6f  lat %.6f)" % [c.x, c.y, cll.x, cll.y])
		if not attrs.is_empty():
			lines.append("  Atrybuty:")
			for k in attrs.keys():
				lines.append("    %s: %s" % [k, attrs[k]])
		lines.append("  Obrys (%s):" % ("x y" if geographic else "E N"))
		var ring_json: Array = []
		for i in range(ring.size()):
			lines.append("    %2d  %.3f  %.3f" % [i + 1, ring[i].x, ring[i].y])
			ring_json.append([ring[i].x, ring[i].y])
		json_buildings.append({"ring": ring_json, "attrs": attrs, "area_m2": st["area"], "floors": fl})
	var info := {
		"saved": ProjectStore.timestamp(), "source": source, "crs": "unknown" if geographic else "EPSG:2180",
		"map_center": [app.map_center.x, app.map_center.y], "map_mpp": app.map_mpp, "lonlat": [ll.x, ll.y],
		"services": {
			"wms": app.settings.s("svc_wms_url"), "wms_layer": app.settings.s("svc_wms_layer"),
			"wfs": app.settings.s("svc_wfs_url"), "wfs_typenames": app.settings.s("svc_wfs_typenames"),
		},
		"total_area_m2": total_area, "buildings": json_buildings,
	}
	if not geographic:
		var ortho := _save_ortho_crop(all_pts)
		if not ortho.is_empty():
			info["ortho"] = ortho
			lines.append("")
			lines.append("Wycinek ortofotomapy: %s  (zakres E N: %.1f %.1f – %.1f %.1f, %d × %d px)" % [
				ortho["file"], ortho["bbox"][0], ortho["bbox"][1], ortho["bbox"][2], ortho["bbox"][3], ortho["size"][0], ortho["size"][1]])
	app.project.write_text("geo.txt", "\n".join(lines) + "\n")
	app.project.write_json("geo.json", info)
	app.project.data["geo"] = {"source": source, "saved": info["saved"], "parts": buildings.size()}
	app.project.log_event("Zbudowano model (%s), części: %d, razem %.1f m²" % [source, buildings.size(), total_area])
	app.project.save()


## Crops the orthophoto currently on the map around the outlines (+ margin). Returns {} when there is none.
func _save_ortho_crop(pts: PackedVector2Array) -> Dictionary:
	if app.map_image == null or pts.is_empty() or app.map_image_rect.size.x <= 0.0:
		return {}
	var img = app.map_image.get_image()
	if img == null:
		return {}
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var margin := 15.0
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var r = app.map_image_rect
	lo = Vector2(maxf(lo.x, r.position.x), maxf(lo.y, r.position.y))
	hi = Vector2(minf(hi.x, r.end.x), minf(hi.y, r.end.y))
	if hi.x - lo.x < 1.0 or hi.y - lo.y < 1.0:
		return {}
	var w := float(img.get_width())
	var h := float(img.get_height())
	var px0 := int(floor((lo.x - r.position.x) / r.size.x * w))
	var px1 := int(ceil((hi.x - r.position.x) / r.size.x * w))
	var py0 := int(floor((r.end.y - hi.y) / r.size.y * h))     # image y runs downwards, northing upwards
	var py1 := int(ceil((r.end.y - lo.y) / r.size.y * h))
	var rect := Rect2i(px0, py0, maxi(px1 - px0, 1), maxi(py1 - py0, 1)).intersection(Rect2i(0, 0, int(w), int(h)))
	if rect.size.x < 8 or rect.size.y < 8:
		return {}
	var crop: Image = img.get_region(rect)
	DirAccess.make_dir_recursive_absolute(app.project.path("geo"))
	if crop.save_png(app.project.path("geo/ortho.png")) != OK:
		return {}
	var b0 := Vector2(r.position.x + float(rect.position.x) / w * r.size.x, r.end.y - float(rect.end.y) / h * r.size.y)
	var b1 := Vector2(r.position.x + float(rect.end.x) / w * r.size.x, r.end.y - float(rect.position.y) / h * r.size.y)
	return {"file": "geo/ortho.png", "bbox": [b0.x, b0.y, b1.x, b1.y], "size": [crop.get_width(), crop.get_height()]}
