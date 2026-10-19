class_name RoofFlow
extends RefCounted
## Window with the roof editor (angle, asymmetry, overhangs).

var app
var window: Window


func _init(main_scene) -> void:
	app = main_scene


## The "Dach" window: draw the roof profile and press GENERUJ DACH.
func open() -> void:
	if app.last_rt.is_empty():
		app._set_status("Najpierw zbuduj model, potem narysujesz dach.")
		return
	if is_instance_valid(window):
		window.queue_free()
	var win := Window.new()
	win.title = "Dach – rysuj i generuj"
	var scr := Vector2(app.get_viewport().get_visible_rect().size)
	win.size = Vector2i(int(clampf(scr.x * 0.9, 980.0, 1600.0)), int(clampf(scr.y * 0.9, 640.0, 960.0)))
	win.transient = true
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var ed := RoofGenEditor.new()
	m.add_child(ed)
	ed.setup(app)
	ed.finished.connect(func(saved: bool) -> void:
		win.queue_free()
		if saved and app.project.is_open():
			app.projflow._save_project())
	win.close_requested.connect(func() -> void: win.queue_free())
	win.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			win.queue_free())
	app.add_child(win)
	win.popup_centered()
	window = win


## The old window: angle, asymmetry and overhangs of a plain gable roof.
func open_simple() -> void:
	if app.last_rt.is_empty():
		app._set_status("Najpierw zbuduj model, potem ustawisz dach.")
		return
	if is_instance_valid(window):
		window.queue_free()
	var win := Window.new()
	win.title = "Kąt i okap dachu"
	var scr := Vector2(app.get_viewport().get_visible_rect().size)
	win.size = Vector2i(int(clampf(scr.x * 0.85, 900.0, 1500.0)), int(clampf(scr.y * 0.85, 560.0, 900.0)))
	win.transient = true
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var ed := RoofEditor.new()
	m.add_child(ed)
	ed.setup(app)
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
	window = win
