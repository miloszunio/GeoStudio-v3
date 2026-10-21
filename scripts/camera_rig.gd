class_name CameraRig
extends RefCounted
## Orbit camera of the 3D view: rotate, zoom, pan (middle button), preset views and full-screen switch.

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


const PITCH_MIN := -1.5707   # app.camera safety limits (radians)


const PITCH_MAX := 0.15


var orbit_yaw := 0.65


var orbit_pitch := -0.35


var orbit_distance := 28.0


var dragging := false


var panning := false


var preset_bar: HBoxContainer

# ---- model state


func _place_preset_bar() -> void:
	if preset_bar != null:
		preset_bar.offset_right = -382.0 if (app.face_panel != null and app.face_panel.visible) else -10.0


## Preset views: orthographic, straight onto one side of the model, or from above.
const VIEW_PRESETS := [
	["Góra", 0.0, -90.0], ["Przód", 0.0, 0.0], ["Tył", 180.0, 0.0], ["Lewo", 270.0, 0.0], ["Prawo", 90.0, 0.0],
]


func _build_preset_bar() -> void:
	preset_bar = HBoxContainer.new()
	preset_bar.name = "WidokiPrzyciski"
	preset_bar.add_theme_constant_override("separation", 4)
	preset_bar.anchor_left = 1.0
	preset_bar.anchor_right = 1.0
	preset_bar.anchor_top = 1.0
	preset_bar.anchor_bottom = 1.0
	preset_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	preset_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	preset_bar.offset_right = -10.0
	preset_bar.offset_bottom = -10.0
	for v in VIEW_PRESETS:
		var b := Button.new()
		b.text = str(v[0])
		b.tooltip_text = "Widok prostopadły (rzut ortogonalny): %s" % str(v[0]).to_lower()
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_view_preset.bind(float(v[1]), float(v[2])))
		preset_bar.add_child(b)
	var persp := Button.new()
	persp.text = "3D"
	persp.tooltip_text = "Wróć do widoku perspektywicznego"
	persp.focus_mode = Control.FOCUS_NONE
	persp.pressed.connect(func() -> void:
		app.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_reset_camera())
	preset_bar.add_child(persp)
	for tool in [["Dach…", "Okno kąta i okapu dachu", "roof"], ["Kominy…", "Generator kominów", "chimney"]]:
		var tb := Button.new()
		tb.name = "Przycisk_" + str(tool[2])
		tb.text = str(tool[0])
		tb.tooltip_text = str(tool[1])
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func() -> void:
			if str(tool[2]) == "roof":
				app.roofed.open()
			else:
				app.chimneys.open())
		preset_bar.add_child(tb)
	var quit := Button.new()
	quit.name = "ZamknijAplikacje"
	quit.text = "✕ Zamknij"
	quit.tooltip_text = "Zapisz projekt (jeśli jest otwarty) i zamknij aplikację"
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func() -> void: app.quit_app())
	preset_bar.add_child(quit)
	app.view_holder.add_child(preset_bar)


func _view_preset(yaw_deg: float, pitch_deg: float) -> void:
	if not is_instance_valid(app.camera):
		return
	app.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	app.orbit_root.position = app.current_bounds.get_center()
	orbit_yaw = deg_to_rad(yaw_deg)
	orbit_pitch = deg_to_rad(pitch_deg)
	var extent = maxf(maxf(app.current_bounds.size.x, app.current_bounds.size.z), app.current_bounds.size.y)
	orbit_distance = clampf(maxf(extent * app.settings.f("view_cam_fit"), 12.0), app.settings.f("view_cam_min_dist"), app.settings.f("view_cam_max_dist"))
	_update_camera_transform()


func _reset_camera() -> void:
	if not is_instance_valid(app.camera):
		return
	app.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	app.orbit_root.position = app.current_bounds.get_center()
	orbit_yaw = deg_to_rad(app.settings.f("view_cam_yaw"))
	orbit_pitch = deg_to_rad(app.settings.f("view_cam_pitch"))
	orbit_distance = maxf(maxf(app.current_bounds.size.x, app.current_bounds.size.z) * app.settings.f("view_cam_fit"), 12.0)
	orbit_distance = clampf(orbit_distance, app.settings.f("view_cam_min_dist"), app.settings.f("view_cam_max_dist"))
	_update_camera_transform()


func _update_camera_transform() -> void:
	if not is_instance_valid(app.camera):
		return
	orbit_pitch = clampf(orbit_pitch, PITCH_MIN, PITCH_MAX)
	orbit_distance = clampf(orbit_distance, app.settings.f("view_cam_min_dist"), app.settings.f("view_cam_max_dist"))
	var dir := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		-sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	)
	app.camera.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), dir * orbit_distance)
	if app.camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		app.camera.size = 2.0 * orbit_distance * tan(deg_to_rad(app.camera.fov) * 0.5)    # same framing as the perspective view


func _toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


var _press_pos := Vector2.ZERO


var _press_moved := 0.0


func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if app.emitter_pick.press(mb.position):
					return                                           # an emitter's move arrow was grabbed
				_press_pos = mb.position
				_press_moved = 0.0
			elif app.emitter_pick.dragging:
				app.emitter_pick.release()
				return
			elif _press_moved < 5.0:
				if not app.emitter_pick.click(mb.position):       # a click, not a drag: an emitter, else the surface
					app._select_face(app._pick_face(mb.position))
			dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance *= 1.0 - app.settings.f("view_cam_zoom_step")
			_update_camera_transform()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance *= 1.0 + app.settings.f("view_cam_zoom_step")
			_update_camera_transform()
	elif event is InputEventMouseMotion and app.emitter_pick.dragging:
		app.emitter_pick.motion((event as InputEventMouseMotion).position)
	elif event is InputEventMouseMotion and panning:
		var pm := event as InputEventMouseMotion
		var per_px = 2.0 * orbit_distance * tan(deg_to_rad(app.camera.fov) * 0.5) / maxf(app.viewport_container.size.y, 1.0)
		app.orbit_root.position += (-app.camera.global_transform.basis.x * pm.relative.x + app.camera.global_transform.basis.y * pm.relative.y) * per_px
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		_press_moved += mm.relative.length()
		if app.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _press_moved > 5.0:
			app.camera.projection = Camera3D.PROJECTION_PERSPECTIVE      # rotating leaves the flat preset view
		var speed = app.settings.f("view_cam_rot_speed")
		orbit_yaw -= mm.relative.x * speed
		orbit_pitch -= mm.relative.y * speed
		_update_camera_transform()
