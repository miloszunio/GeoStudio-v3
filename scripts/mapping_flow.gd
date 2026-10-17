class_name MappingFlow
extends RefCounted
## Full-window mapping editor and the straightened photos it produces (stored in the project, loaded into the atlas).

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


## Scale of the texture sheet (px per metre) used to size straightened pictures.
func px_per_m() -> float:
	return app.settings.f("tex_px_per_m") * maxf(app.atlas.source_width, 1.0) / 4096.0 if app.atlas.loaded else app.settings.f("tex_px_per_m")


var rectified: Dictionary = {}    # key "rect/<name>" -> {file, source, quad, face}: straightened photos made in the mapping editor


var uv_window: Window


func open_uv_editor(fid: String) -> void:
	if fid == "" or not app._use_textures() or app.atlas.regions.is_empty():
		app._set_status("Edytor mapowania wymaga wczytanej tekstury.")
		return
	if is_instance_valid(uv_window):
		uv_window.queue_free()
	var win := Window.new()
	win.title = "Edytor mapowania"
	var scr = Vector2(app.get_viewport().get_visible_rect().size)
	win.size = Vector2i(int(maxf(scr.x * 0.9, 900.0)), int(maxf(scr.y * 0.88, 600.0)))
	win.transient = true
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var ed := UvEditor.new()
	ed.setup(app.atlas, app.faces, fid, app.face_info(fid), self)
	m.add_child(ed)
	ed.finished.connect(func(saved: bool) -> void:
		win.queue_free()
		if saved and app.project.is_open():
			app.projflow._save_project())
	win.close_requested.connect(func() -> void: ed.cancel_edit())
	win.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			ed.cancel_edit())
	app.add_child(win)
	win.popup_centered()
	uv_window = win


func _rectified_dir() -> String:
	var d = app.project.path("texture/rectified") if app.project.is_open() else ProjectSettings.globalize_path("user://rectified")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Saves a straightened picture as PNG, adds it to the app.atlas and remembers it for the app.project.
func add_rectified(base_name: String, img: Image, meta: Dictionary) -> String:
	var name := base_name
	var n := 1
	while rectified.has("rect/" + name) and not (rectified["rect/" + name].get("face", "") == meta.get("face", "x")):
		n += 1
		name = "%s_%d" % [base_name, n]
	var key := "rect/" + name
	var file := _rectified_dir().path_join(name + ".png")
	img.save_png(file)
	var entry := meta.duplicate()
	entry["file"] = app.project.relative(file) if app.project.is_open() else file
	rectified[key] = entry
	app.atlas.add_image_region(key, img)
	app.tex_materials.clear()
	app.face_materials.clear()
	app.atlasflow._publish_atlas_choices()
	return key


func _restore_rectified() -> void:
	for key in rectified.keys():
		var e: Dictionary = rectified[key]
		var f := str(e.get("file", ""))
		var abs_path = app.project.path(f) if (app.project.is_open() and not f.is_absolute_path()) else f
		if not FileAccess.file_exists(abs_path):
			continue
		var im := Image.load_from_file(abs_path)
		if im != null:
			app.atlas.add_image_region(str(key), im)
