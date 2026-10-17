class_name AtlasFlow
extends RefCounted
## Texture source and photo library: slicing options, loading the atlas, slice preview, importing photos, exporting normal maps.

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


func _library_dirs() -> Array[String]:
	var dirs: Array[String] = []
	if not app.settings.b("tex_library_enabled"):
		return dirs
	var user_dir = app.settings.s("tex_library_dir").strip_edges()
	if user_dir != "":
		DirAccess.make_dir_recursive_absolute(user_dir if not user_dir.begins_with("user://") and not user_dir.begins_with("res://") else ProjectSettings.globalize_path(user_dir))
		dirs.append(ProjectSettings.globalize_path(user_dir) if user_dir.begins_with("user://") or user_dir.begins_with("res://") else user_dir)
	var proj_dir := ProjectSettings.globalize_path("res://textures/library")
	if DirAccess.dir_exists_absolute(proj_dir) and not (proj_dir in dirs):
		dirs.append(proj_dir)
	return dirs


var loading_tex := false


func _slice_opts() -> Dictionary:
	return {
		"mode": app.settings.s("tex_slice_mode"), "sensitivity": app.settings.f("tex_slice_sensitivity"),
		"min_area": app.settings.f("tex_slice_min_area"), "gap": app.settings.f("tex_slice_gap"),
		"layout": SheetLayout.from_json(app.settings.s("tex_sheet_layout")),
	}


## The texture source changed: the old drop-down choices point at regions that no longer exist,
## so they are all reset to "automatic" before the new regions are listed.
func _on_texture_source_changed(force_slice := false) -> void:
	var src = app.settings.s("tex_source")
	if app.project.is_open() and src != "" and src.get_extension().to_lower() != "json" and not app.project.inside(src):
		var local = app.project.import_file(src, "texture")   # the app.project keeps its own copy (and the cut next to it)
		if local != src:
			loading_tex = true
			app.settings.set_value("tex_source", local)
			loading_tex = false
	loading_tex = true
	for k in ["tex_wall_all", "tex_long_a", "tex_long_b", "tex_gable_a", "tex_gable_b", "tex_roof"]:
		app.settings.set_value(k, "auto")
	app.settings.set_value("tex_variant", 0)
	loading_tex = false
	_load_atlas(app.settings.s("tex_source"), false, force_slice)
	if app.atlas.loaded and app.settings.s("tex_source") != "":
		loading_tex = true
		app.settings.set_value("tex_enabled", true)
		loading_tex = false
	app._rebuild_current()


## Texture source (an app.atlas JSON, a sheet that gets cut into panels, or one photo) and the photo
## library end up in the same TextureAtlas, so every drop-down below offers both.
func _load_atlas(path: String, rebuild: bool, force_slice := false) -> void:
	var err = app.atlas.load_source(path, _slice_opts(), force_slice)
	var src_count = app.atlas.regions.size()
	var lib_count := 0
	for d in _library_dirs():
		lib_count += app.atlas.add_folder(d)
	app.tex_materials.clear()
	app.face_materials.clear()
	app.mapping._restore_rectified()
	_publish_atlas_choices()
	if not app.atlas.loaded:
		app._set_status(err if err != "" else "Brak tekstury. Wskaż obraz w „Źródło tekstury” lub dodaj zdjęcia do biblioteki.")
		return
	var how := ""
	match app.atlas.sheet_mode:
		"sheet": how = "arkusz pocięty na %d regionów" % src_count
		"single": how = "jedna tekstura"
		"json": how = "atlas z JSON, %d regionów" % src_count
	var msg := "Tekstury: %s" % (how if how != "" else "tylko biblioteka")
	if lib_count > 0:
		msg += " + %d zdjęć z biblioteki" % lib_count
	if app.atlas.sidecar_path != "" and app.atlas.sheet_mode == "sheet":
		msg += ". Podział zapisano: " + ProjectSettings.globalize_path(app.atlas.sidecar_path)
	if err != "":
		msg += " (" + err + ")"
	app._set_status(msg)
	app._update_steps()
	if src_count > 0 and not loading_tex and app.panel != null:
		app.panel.open_section("tex_assign")
	if rebuild:
		app._rebuild_current()


## Window with the source image and a frame + name around every region.
func _show_slice_preview() -> void:
	if app.atlas.sheet_tex == null:
		app._set_status("Najpierw wczytaj obraz tekstury (podgląd dotyczy źródła, nie biblioteki zdjęć).")
		return
	var win := Window.new()
	win.title = "Podział tekstury na regiony"
	win.size = Vector2i(900, 900)
	win.transient = true
	win.exclusive = false
	win.close_requested.connect(win.queue_free)
	var ctl := Control.new()
	ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(ctl)
	var tex = app.atlas.sheet_tex
	var regs: Dictionary = {}
	for key in app.atlas.regions.keys():
		if str(app.atlas.regions[key].get("source", "")) == "atlas":
			regs[key] = app.atlas.regions[key]["rect"]
	ctl.draw.connect(func() -> void:
		var area := ctl.size
		var k := minf(area.x / tex.get_width(), area.y / tex.get_height())
		var origin := (area - Vector2(tex.get_size()) * k) * 0.5
		ctl.draw_rect(Rect2(Vector2.ZERO, area), Color("#10141b"))
		ctl.draw_texture_rect(tex, Rect2(origin, Vector2(tex.get_size()) * k), false)
		# regions are in source-image pixels; the preview texture may be smaller
		var scale_src = float(tex.get_width()) / maxf(app.atlas.source_width, 1.0)
		var font := ThemeDB.fallback_font
		for key in regs.keys():
			var rr: Rect2i = regs[key]
			var box := Rect2(origin + Vector2(rr.position) * scale_src * k, Vector2(rr.size) * scale_src * k)
			ctl.draw_rect(box, Color(0.3, 1.0, 0.4, 0.9), false, 2.0)
			var label := str(key)
			ctl.draw_rect(Rect2(box.position, Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 6, 17)), Color(0, 0, 0, 0.7))
			ctl.draw_string(font, box.position + Vector2(3, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1.0, 0.7)))
	app._closable(win, ctl)
	app.add_child(win)
	win.popup_centered()
	ctl.queue_redraw()


func _region_options(keys: Array, first: Array) -> Array:
	var opts: Array = [first]
	for region_key in keys:
		var label := str(region_key).replace("_", " ")
		if str(app.atlas.regions[region_key].get("source", "")) == "library":
			label = str(region_key).trim_prefix("foto/")
		opts.append([str(region_key), label, app.atlas.regions[region_key].get("thumb")])
	return opts


## Fills the per-face texture drop-downs (with thumbnails) from everything the app.atlas now holds.
func _publish_atlas_choices() -> void:
	var targets := {
		"tex_long_a": "facade_long", "tex_long_b": "facade_long",
		"tex_gable_a": "facade_gable", "tex_gable_b": "facade_gable",
		"tex_roof": "roof",
	}
	for key in targets.keys():
		app.settings.set_options(key, _region_options(app.atlas.keys_for_role(targets[key]), ["auto", "Automatycznie"]))
	var all_facades: Array = app.atlas.keys_for_role("facade_long")
	for k in app.atlas.keys_for_role("facade_gable"):
		if not (k in all_facades):
			all_facades.append(k)
	all_facades.sort()
	app.settings.set_options("tex_wall_all", _region_options(all_facades, ["auto", "Nie (dobierz według ściany)"]))


var import_dialog: FileDialog


func _open_import_dialog() -> void:
	if import_dialog == null:
		import_dialog = FileDialog.new()
		import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		import_dialog.title = "Wybierz zdjęcia do biblioteki tekstur"
		import_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga ; Zdjęcia")
		import_dialog.files_selected.connect(_import_photos)
		app.add_child(import_dialog)
	import_dialog.popup_centered_ratio(0.6)


func _import_photos(paths: PackedStringArray) -> void:
	var dirs := _library_dirs()
	if dirs.is_empty():
		app._set_status("Włącz „Używaj biblioteki zdjęć”, aby importować.")
		return
	var copied := 0
	for p in paths:
		var target: String = dirs[0].path_join(p.get_file())
		if FileAccess.file_exists(target):
			continue
		if DirAccess.copy_absolute(p, target) == OK:
			copied += 1
	_load_atlas(app.settings.s("tex_source"), true)
	app._set_status("Dodano %d zdjęć do biblioteki: %s" % [copied, dirs[0]])


## Writes albedo + generated normal map (PNG) of every texture in use, for other 3D programs.
func _export_normals() -> void:
	var dirs := _library_dirs()
	var base: String = dirs[0] if not dirs.is_empty() else ProjectSettings.globalize_path("user://")
	var out := base.path_join("_export")
	DirAccess.make_dir_recursive_absolute(out)
	var n := 0
	for ck in app.tex_materials.keys():
		var m: StandardMaterial3D = app.tex_materials[ck]
		if m.albedo_texture == null:
			continue
		var name := str(ck).replace("roof:", "dach_").replace("foto/", "").replace("/", "_")
		(m.albedo_texture as Texture2D).get_image().save_png(out.path_join(name + "_albedo.png"))
		if m.normal_texture != null:
			(m.normal_texture as Texture2D).get_image().save_png(out.path_join(name + "_normal.png"))
		n += 1
	app._set_status("Wyeksportowano %d tekstur z normal mapami do: %s" % [n, out] if n > 0 else "Najpierw zbuduj model, aby wiedzieć, które tekstury są użyte.")
