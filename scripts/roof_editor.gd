class_name RoofEditor
extends VBoxContainer
## Roof editor window: the gable picture with the roof drawn over it, handles to drag, numbers on the side.
##   - the dashed eave line (left handle) sets the roof height,
##   - the yellow roof line ends set how far the roof sticks out beyond the walls,
##   - with "Dach asymetryczny" the apex can be dragged sideways (and the two slopes have their own angle and overhang).
## The model behind the window follows at once. Zapisz keeps it, Anuluj restores what was there.

signal finished(saved: bool)

const KEYS := ["model_roof_height", "model_roof_from_tex", "model_roof_overhang", "model_roof_gable_same", "model_roof_over_gable",
	"model_roof_asym", "model_roof_ridge_shift", "model_roof_over_eave_b"]
const APPLY_GAP_MSEC := 90
const HANDLE := 9.0

var app
var g: Dictionary = {}          # app.roof_gable_info()
var _snapshot := {}
var _canvas: Control
var _ctl := {}
var _drag := ""
var _last_apply := 0
var _pending := false
var _busy := false              # while the controls are filled in programmatically

# editor state (metres, left / right as seen on the picture)
var rh := 3.0
var shift_left := 0.0           # apex distance from the middle, positive = towards the picture's right
var asym := false
var ov_l := 0.5
var ov_r := 0.5
var ov_g := 0.5
var gable_same := true


func setup(main_scene) -> void:
	app = main_scene
	g = app.roof_gable_info()
	for k in KEYS:
		_snapshot[k] = app.settings.values[k]
	_read_state()
	_build()
	_sync_controls()


func _w() -> float:
	return maxf(float(g["span"]), 0.5)


func _wall() -> float:
	return float(g["wall_h"])


## Settings -> state seen from the picture (left / right). Side A of the model is the t > 0 side.
func _read_state() -> void:
	rh = maxf(float(g["roof_h"]), 0.0)
	asym = app.settings.b("model_roof_asym")
	var half := _w() * 0.5
	var sh: float = clampf(app.settings.f("model_roof_ridge_shift"), -0.85 * half, 0.85 * half) if asym else 0.0
	# ridge at t = +sh (side A is t > 0): the picture's left is side A when left_is_pos
	shift_left = -sh if bool(g["left_is_pos"]) else sh
	# apex x on the picture = half + shift_left  (shift_left > 0 -> towards the right)
	var a: float = app.settings.f("model_roof_overhang")
	var b: float = app.settings.f("model_roof_over_eave_b") if asym else a
	ov_l = a if bool(g["left_is_pos"]) else b
	ov_r = b if bool(g["left_is_pos"]) else a
	gable_same = app.settings.b("model_roof_gable_same")
	ov_g = app.settings.f("model_roof_over_gable")


func _apex_x() -> float:
	return _w() * 0.5 + shift_left


func _half_l() -> float:
	return maxf(_apex_x(), 0.05)


func _half_r() -> float:
	return maxf(_w() - _apex_x(), 0.05)


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Kąt i okap dachu – główna bryła"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var hint := Label.new()
	hint.text = "Niebieski uchwyt (okap) – dopasowuje dach do zdjęcia. Pomarańczowy (kalenica) w górę/w dół – wysokość kalenicy, a z asymetrią także w bok. Końce żółtej linii – wysunięcie dachu. Kółko myszy: zoom."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	add_child(hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(520, 360)
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	body.add_child(_canvas)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	_row(side, "h", "Wysokość dachu ponad okap", 0.0, 40.0, 0.05, " m", func(v: float) -> void:
		rh = v
		_changed())
	_row(side, "top", "Wysokość kalenicy nad ziemią", 0.5, 60.0, 0.05, " m", func(v: float) -> void:
		rh = clampf(v - _wall(), 0.0, 40.0)
		_changed())
	_check(side, "asym", "Dach asymetryczny", func(on: bool) -> void:
		asym = on
		if not on:
			shift_left = 0.0
			ov_r = ov_l
		_sync_controls()
		_changed())
	_row(side, "ang_l", "Kąt lewej połaci", 1.0, 80.0, 0.5, " °", func(v: float) -> void:
		_set_angles(v, _angle_r() if asym else v)
		_changed())
	_row(side, "ang_r", "Kąt prawej połaci", 1.0, 80.0, 0.5, " °", func(v: float) -> void:
		_set_angles(_angle_l() if asym else v, v)
		_changed())
	_row(side, "shift", "Przesunięcie kalenicy (w prawo +)", -10.0, 10.0, 0.05, " m", func(v: float) -> void:
		shift_left = clampf(v, -0.85 * _w() * 0.5, 0.85 * _w() * 0.5)
		_changed())
	var sep := HSeparator.new()
	side.add_child(sep)
	_row(side, "ov_l", "Okap – lewa strona", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_l = v
		if not asym:
			ov_r = v
		_changed())
	_row(side, "ov_r", "Okap – prawa strona", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_r = v
		_changed())
	_check(side, "gsame", "Szczyty wysunięte tak jak okap", func(on: bool) -> void:
		gable_same = on
		_sync_controls()
		_changed())
	_row(side, "ov_g", "Wysunięcie przy szczytach", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_g = v
		_changed())
	var info := Label.new()
	info.name = "info"
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info)
	_ctl["info"] = info
	var tools := HBoxContainer.new()
	side.add_child(tools)
	var from_tex := Button.new()
	from_tex.text = "Z tekstury"
	from_tex.tooltip_text = "Wysokość dachu z nachylenia widocznego na zdjęciu szczytu"
	from_tex.pressed.connect(func() -> void:
		var tr: float = app.atlas.estimate_roof_ratio(str(g["key"])) if str(g["key"]) != "" else -1.0
		if tr > 0.0:
			rh = snappedf(tr * _w(), 0.01)
			_sync_controls()
			_changed())
	tools.add_child(from_tex)
	var reset := Button.new()
	reset.text = "Zeruj asymetrię i okapy"
	reset.pressed.connect(func() -> void:
		asym = false
		shift_left = 0.0
		ov_l = 0.5
		ov_r = 0.5
		ov_g = 0.5
		gable_same = true
		_sync_controls()
		_changed())
	tools.add_child(reset)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.alignment = BoxContainer.ALIGNMENT_END
	add_child(foot)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.custom_minimum_size = Vector2(130, 36)
	cancel.pressed.connect(cancel_edit)
	foot.add_child(cancel)
	var save := Button.new()
	save.text = "Zapisz"
	save.custom_minimum_size = Vector2(130, 36)
	save.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	save.pressed.connect(save_edit)
	foot.add_child(save)


func _row(parent: Control, id: String, label: String, lo: float, hi: float, step: float, suffix: String, cb: Callable) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.suffix = suffix
	sb.custom_minimum_size.x = 110
	sb.value_changed.connect(func(v: float) -> void:
		if not _busy:
			cb.call(v))
	line.add_child(sb)
	_ctl[id] = sb
	_ctl[id + "_row"] = line


func _check(parent: Control, id: String, label: String, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = label
	c.toggled.connect(func(on: bool) -> void:
		if not _busy:
			cb.call(on))
	parent.add_child(c)
	_ctl[id] = c


func _angle_l() -> float:
	return rad_to_deg(atan2(rh, _half_l()))


func _angle_r() -> float:
	return rad_to_deg(atan2(rh, _half_r()))


## Two slope angles on a fixed span fix both the height and the ridge position.
func _set_angles(al: float, ar: float) -> void:
	var tl := tan(deg_to_rad(clampf(al, 1.0, 80.0)))
	var tr := tan(deg_to_rad(clampf(ar, 1.0, 80.0)))
	rh = _w() / (1.0 / tl + 1.0 / tr)
	var hl := rh / tl
	shift_left = hl - _w() * 0.5 if asym else 0.0
	if not asym:
		shift_left = 0.0
		rh = tl * _w() * 0.5
	_sync_controls()


func _sync_controls() -> void:
	_busy = true
	(_ctl["h"] as SpinBox).value = rh
	(_ctl["top"] as SpinBox).value = _wall() + rh
	(_ctl["asym"] as CheckBox).button_pressed = asym
	(_ctl["ang_l"] as SpinBox).value = _angle_l()
	(_ctl["ang_r"] as SpinBox).value = _angle_r()
	(_ctl["ang_r"] as SpinBox).editable = asym
	(_ctl["shift"] as SpinBox).value = shift_left
	(_ctl["shift"] as SpinBox).editable = asym
	(_ctl["ov_l"] as SpinBox).value = ov_l
	(_ctl["ov_r"] as SpinBox).value = ov_r
	(_ctl["ov_r"] as SpinBox).editable = asym
	(_ctl["gsame"] as CheckBox).button_pressed = gable_same
	(_ctl["ov_g"] as SpinBox).value = ov_l if gable_same else ov_g
	(_ctl["ov_g"] as SpinBox).editable = not gable_same
	(_ctl["info"] as Label).text = "Rozpiętość %.2f m, ściany %.2f m, kalenica na %.2f m. Nachylenie: lewa %.1f°, prawa %.1f°." % [_w(), _wall(), _wall() + rh, _angle_l(), _angle_r()]
	_busy = false
	_canvas.queue_redraw()


func _changed() -> void:
	_sync_controls()
	var now := Time.get_ticks_msec()
	if now - _last_apply >= APPLY_GAP_MSEC:
		_apply_now()
	elif not _pending:
		_pending = true
		get_tree().create_timer(APPLY_GAP_MSEC / 1000.0).timeout.connect(func() -> void:
			_pending = false
			_apply_now())


func _apply_now() -> void:
	if not is_inside_tree():
		return
	_last_apply = Time.get_ticks_msec()
	var s = app.settings
	var lp: bool = bool(g["left_is_pos"])
	var a := ov_l if lp else ov_r
	var b := ov_r if lp else ov_l
	var sh_t := (-shift_left if lp else shift_left)
	# One rebuild: write everything but the last key silently where possible.
	app.roof_apply_settings({
		"model_roof_from_tex": false,
		"model_roof_height": snappedf(rh, 0.01),
		"model_roof_asym": asym,
		"model_roof_ridge_shift": snappedf(sh_t, 0.01) if asym else 0.0,
		"model_roof_overhang": snappedf(a, 0.01),
		"model_roof_over_eave_b": snappedf(b if asym else a, 0.01),
		"model_roof_gable_same": gable_same,
		"model_roof_over_gable": snappedf(ov_g if not gable_same else a, 0.01),
	})


func cancel_edit() -> void:
	app.roof_apply_settings(_snapshot)
	finished.emit(false)


func save_edit() -> void:
	_apply_now()
	finished.emit(true)


# ------------------------------------------------------------------ canvas
var _zoom := 1.0
var _pan := Vector2.ZERO


func _view() -> Dictionary:
	# metres -> pixels; x from -(overhang margin) to span + margin, y from ground to apex + margin
	var margin := 3.6
	var wm := _w() + 2.0 * margin
	var hm := _wall() + maxf(rh, 0.5) + 1.4
	var sz := _canvas.size
	var sc := minf(sz.x / wm, sz.y / hm) * _zoom
	var origin := Vector2(sz.x * 0.5 - (_w() * 0.5) * sc, sz.y - 0.5 * sc) + _pan   # px of (x = 0, y = 0)
	return {"sc": sc, "o": origin}


func _to_px(p: Vector2) -> Vector2:
	var v := _view()
	return Vector2(float(v["o"].x) + p.x * float(v["sc"]), float(v["o"].y) - p.y * float(v["sc"]))


func _from_px(px: Vector2) -> Vector2:
	var v := _view()
	return Vector2((px.x - float(v["o"].x)) / float(v["sc"]), (float(v["o"].y) - px.y) / float(v["sc"]))


func _geom() -> Dictionary:
	var top := _wall() + rh
	var sl_l := rh / _half_l()
	var sl_r := rh / _half_r()
	var gl := ov_l
	var gr := ov_r
	return {
		"apex": Vector2(_apex_x(), top),
		"eave_l": Vector2(0.0, _wall()), "eave_r": Vector2(_w(), _wall()),
		"end_l": Vector2(-gl, _wall() - sl_l * gl), "end_r": Vector2(_w() + gr, _wall() - sl_r * gr),
	}


func _draw_canvas() -> void:
	var cs := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, cs), Color(0.09, 0.1, 0.13))
	var tl := _to_px(Vector2(0.0, _wall() + rh))
	var br := _to_px(Vector2(_w(), 0.0))
	var key := str(g["key"])
	if key != "" and app.atlas.regions.has(key):
		_canvas.draw_texture_rect(app.atlas.get_texture(key), Rect2(tl, br - tl), false)
	else:
		_canvas.draw_rect(Rect2(tl, br - tl), Color(0.35, 0.33, 0.3))
		_canvas.draw_string(ThemeDB.fallback_font, tl + Vector2(12, 24), "(brak zdjęcia szczytu – widać tylko obrys)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	_canvas.draw_rect(Rect2(tl, br - tl), Color(1, 1, 1, 0.35), false, 1.0)
	var gm := _geom()
	var col := Color(1.0, 0.85, 0.2)
	var a := _to_px(gm["apex"])
	var pl := _to_px(gm["end_l"])
	var pr := _to_px(gm["end_r"])
	_canvas.draw_line(pl, a, col, 3.0, true)
	_canvas.draw_line(a, pr, col, 3.0, true)
	# eave line (dashed) between the wall tops and out to the overhang ends
	var el := _to_px(gm["eave_l"])
	var er := _to_px(gm["eave_r"])
	var x := minf(pl.x, el.x) - 20.0
	while x < maxf(pr.x, er.x) + 20.0:
		_canvas.draw_line(Vector2(x, el.y), Vector2(x + 7.0, el.y), Color(0.4, 0.9, 1.0), 2.0)
		x += 13.0
	# wall outline below the eave
	_canvas.draw_line(el, _to_px(Vector2(0.0, 0.0)), Color(0.4, 0.9, 1.0, 0.8), 1.5)
	_canvas.draw_line(er, _to_px(Vector2(_w(), 0.0)), Color(0.4, 0.9, 1.0, 0.8), 1.5)
	for h in _handles():
		var pt := _to_px(h["p"])
		_canvas.draw_circle(pt, HANDLE, Color(0, 0, 0, 0.55))
		_canvas.draw_circle(pt, HANDLE - 2.0, h["col"])
	_canvas.draw_string(ThemeDB.fallback_font, a + Vector2(12, -8), "%.1f° / %.1f°" % [_angle_l(), _angle_r()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _handles() -> Array:
	var gm := _geom()
	var hs: Array = [
		{"id": "eave", "p": Vector2(-0.0, _wall()), "col": Color(0.4, 0.9, 1.0)},
		{"id": "ovl", "p": gm["end_l"], "col": Color(1.0, 0.85, 0.2)},
		{"id": "ovr", "p": gm["end_r"], "col": Color(1.0, 0.85, 0.2)},
	]
	hs.append({"id": "apex", "p": gm["apex"], "col": Color(1.0, 0.5, 0.3)})   # up / down = ridge height, sideways (asymmetric roof) = ridge position
	return hs


func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.12, 0.4, 6.0)
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.12, 0.4, 6.0)
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = ""
				var best := HANDLE * 1.8
				for h in _handles():
					var d := _to_px(h["p"]).distance_to(mb.position)
					if d < best:
						best = d
						_drag = str(h["id"])
			else:
				_drag = ""
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag == "pan":
			_pan += mm.relative
			_canvas.queue_redraw()
			return
		if _drag == "":
			return
		var m := _from_px(mm.position)
		match _drag:
			"eave":
				# The picture always fills wall + roof. The line is dragged to where the roof meets the wall on the
				# picture: its distance from the top, as a share of the picture height, is rise / (wall + rise).
				var top := _wall() + rh
				var f := clampf((top - m.y) / maxf(top, 0.01), 0.02, 0.9)
				rh = clampf(_wall() * f / (1.0 - f), 0.0, 40.0)
			"ovl":
				ov_l = clampf(-m.x, 0.0, 3.0)
				if not asym:
					ov_r = ov_l
			"ovr":
				ov_r = clampf(m.x - _w(), 0.0, 3.0)
				if not asym:
					ov_l = ov_r
			"apex":
				rh = clampf(m.y - _wall(), 0.0, 40.0)
				if asym:
					shift_left = clampf(m.x - _w() * 0.5, -0.85 * _w() * 0.5, 0.85 * _w() * 0.5)
		_changed()
