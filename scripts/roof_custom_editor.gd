class_name RoofCustomEditor
extends VBoxContainer
## Top view of the main part's outline: every edge has an arrow that points down the slope of its roof plane.
## Click an edge (or its arrow), set its slope in degrees or make it a gable wall. Changes show on the model at once.

signal finished(saved: bool)

var app
var pts := PackedVector2Array()
var slopes: Array = []        # degrees per edge, -1 = gable wall (no plane)
var cap := 0.0
var sel := 0
var _snapshot := {}
var _canvas: Control
var _ctl := {}
var _busy := false
var _timer: Timer
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _info: Label


func setup(main_scene) -> void:
	app = main_scene
	pts = app.last_rt[0]["pts"]
	for k in ["model_roof_custom", "model_roof_type", "model_roof_height", "model_roof_from_tex", "model_roof_gen"]:
		_snapshot[k] = app.settings.values[k]
	var cfg := RoofCustom.parse(app.settings.s("model_roof_custom"))
	slopes = (cfg.get("slopes", []) as Array).duplicate()
	if slopes.size() != pts.size():
		slopes = RoofCustom.default_slopes(pts, float(app.last_rt[0]["roof_h"]))
	cap = float(cfg.get("cap", 0.0))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.25
	_timer.timeout.connect(_apply)
	add_child(_timer)
	_build()
	_sync()
	if app.settings.s("model_roof_type") != "custom":
		_apply()      # opening this window means "I want a custom roof"


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Dach własny – kierunki spadków"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var hint := Label.new()
	hint.text = "Rzut z góry. Strzałka przy każdej krawędzi pokazuje, w którą stronę opada jej połać. Kliknij krawędź, żeby ją zaznaczyć, i ustaw spadek w stopniach albo zrób z niej ścianę szczytową (bez połaci). Kalenice i narożniki wychodzą same z przecięcia połaci. Kółko: zoom, środkowy przycisk: przesuwanie. Model zmienia się na bieżąco."
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
	_canvas.custom_minimum_size = Vector2(520, 420)
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_plan)
	_canvas.gui_input.connect(_input)
	body.add_child(_canvas)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var l := Label.new()
	l.text = "Zaznaczona krawędź"
	l.add_theme_font_size_override("font_size", 14)
	side.add_child(l)
	var gable := CheckBox.new()
	gable.text = "Ściana szczytowa (bez połaci)"
	gable.toggled.connect(func(on: bool) -> void:
		if _busy:
			return
		slopes[sel] = -1.0 if on else _default_deg()
		_changed())
	side.add_child(gable)
	_ctl["gable"] = gable
	var row := HBoxContainer.new()
	side.add_child(row)
	var rl := Label.new()
	rl.text = "Spadek połaci"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rl)
	var sb := SpinBox.new()
	sb.min_value = RoofCustom.MIN_DEG
	sb.max_value = RoofCustom.MAX_DEG
	sb.step = 0.5
	sb.suffix = " °"
	sb.custom_minimum_size.x = 120
	sb.value_changed.connect(func(v: float) -> void:
		if _busy:
			return
		slopes[sel] = v
		_changed())
	row.add_child(sb)
	_ctl["deg"] = sb
	var all := Button.new()
	all.text = "Ten sam spadek na wszystkich krawędziach"
	all.pressed.connect(func() -> void:
		var d: float = float(slopes[sel])
		if d < RoofCustom.MIN_DEG:
			return
		for i in range(slopes.size()):
			slopes[i] = d
		_changed())
	side.add_child(all)
	var capr := HBoxContainer.new()
	side.add_child(capr)
	var cl := Label.new()
	cl.text = "Ścięcie szczytu (płaski wierzch)"
	cl.tooltip_text = "0 = brak. Wartość > 0 ścina dach na tej wysokości nad okapem (dach z płaskim szczytem)."
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capr.add_child(cl)
	var cs := SpinBox.new()
	cs.min_value = 0.0
	cs.max_value = 30.0
	cs.step = 0.1
	cs.suffix = " m"
	cs.custom_minimum_size.x = 120
	cs.value_changed.connect(func(v: float) -> void:
		if _busy:
			return
		cap = v
		_changed())
	capr.add_child(cs)
	_ctl["cap"] = cs
	var reset := Button.new()
	reset.text = "Zeruj do kopertowego"
	reset.pressed.connect(func() -> void:
		slopes = RoofCustom.default_slopes(pts, 3.0 if float(app.settings.f("model_roof_height")) <= 0.1 else float(app.settings.f("model_roof_height")))
		cap = 0.0
		_changed())
	side.add_child(reset)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	side.add_child(_info)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 8)
	add_child(foot)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.pressed.connect(cancel_edit)
	foot.add_child(cancel)
	var ok := Button.new()
	ok.text = "Zapisz i zamknij"
	ok.theme_type_variation = "PrimaryButton"
	ok.custom_minimum_size = Vector2(150, 36)
	ok.pressed.connect(func() -> void:
		_apply()
		finished.emit(true))
	foot.add_child(ok)


func _default_deg() -> float:
	for d in slopes:
		if float(d) >= RoofCustom.MIN_DEG:
			return float(d)
	return 35.0


func _changed() -> void:
	_sync()
	_timer.start()


func _apply() -> void:
	app.roof_apply_settings({
		"model_roof_type": "custom", "model_roof_from_tex": false, "model_roof_gen": _gen_without_main(),
		"model_roof_custom": JSON.stringify({"slopes": slopes, "cap": cap}),
	})
	_sync()


func _gen_without_main() -> String:
	var keep: Array = []
	for e in RoofGen.list_from_json(app.settings.s("model_roof_gen")):
		if int(e.get("part", 0)) != 0:
			keep.append(e)
	return RoofGen.to_json(keep)


func _sync() -> void:
	_busy = true
	var d := float(slopes[sel])
	(_ctl["gable"] as CheckBox).button_pressed = d < RoofCustom.MIN_DEG
	(_ctl["deg"] as SpinBox).editable = d >= RoofCustom.MIN_DEG
	(_ctl["deg"] as SpinBox).value = maxf(d, RoofCustom.MIN_DEG)
	(_ctl["cap"] as SpinBox).value = cap
	var n_slope := 0
	for v in slopes:
		if float(v) >= RoofCustom.MIN_DEG:
			n_slope += 1
	var rise := 0.0
	if not app.last_rt.is_empty():
		rise = float(app.last_rt[0]["roof_h"])
	_info.text = "Krawędzie: %d, z połacią: %d. Kalenica %.2f m nad okapem.%s" % [pts.size(), n_slope, rise, "" if n_slope > 0 else " Brak połaci – dach zostaje płaski."]
	_busy = false
	_canvas.queue_redraw()


# ------------------------------------------------------------------------------------------------ view

func _box() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return Rect2(lo, hi - lo)


func _scale() -> float:
	var b := _box()
	var sz := _canvas.size - Vector2(120, 120)
	return minf(sz.x / maxf(b.size.x, 0.1), sz.y / maxf(b.size.y, 0.1)) * _zoom


func _to_px(p: Vector2) -> Vector2:
	var b := _box()
	return _canvas.size * 0.5 + (p - (b.position + b.size * 0.5)) * _scale() + _pan


func _edge_dist(px: Vector2, i: int) -> float:
	var a := _to_px(pts[i])
	var b := _to_px(pts[(i + 1) % pts.size()])
	var c := Geometry2D.get_closest_point_to_segment(px, a, b)
	var best := px.distance_to(c)
	var mid := (a + b) * 0.5
	var tip := mid + RoofCustom.inward(pts, i) * _arrow_len(i)
	best = minf(best, px.distance_to(Geometry2D.get_closest_point_to_segment(px, mid, tip)))
	return best


func _arrow_len(i: int) -> float:
	var d := float(slopes[i])
	return 18.0 + (clampf(d, 0.0, 85.0) / 85.0) * 46.0 if d >= RoofCustom.MIN_DEG else 0.0


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = minf(_zoom * 1.15, 8.0)
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = maxf(_zoom / 1.15, 0.3)
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var best := -1
			var bd := 26.0
			for i in range(pts.size()):
				var d := _edge_dist(mb.position, i)
				if d < bd:
					bd = d
					best = i
			if best >= 0:
				sel = best
				_sync()
	elif ev is InputEventMouseMotion and _panning:
		_pan += (ev as InputEventMouseMotion).relative
		_canvas.queue_redraw()


func _draw_plan() -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#141a24"))
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(_to_px(q))
	if poly.size() >= 3:
		_canvas.draw_colored_polygon(poly, Color(0.22, 0.26, 0.34, 0.9))
	# ridge / hip lines: where two planes meet
	var pl := RoofCustom.planes(pts, 0.0, {"slopes": slopes, "cap": cap})
	for i in range(pts.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var on := i == sel
		var gable := float(slopes[i]) < RoofCustom.MIN_DEG
		var col := Color("#ffd24a") if on else (Color("#7f8ba0") if gable else Color("#4fa8ff"))
		_canvas.draw_line(a, b, col, 4.0 if on else 2.5, true)
		var mid := (a + b) * 0.5
		if not gable:
			var tip := mid + RoofCustom.inward(pts, i) * _arrow_len(i)
			_canvas.draw_line(mid, tip, col, 2.5, true)
			var dir := (tip - mid).normalized()
			var side := Vector2(-dir.y, dir.x) * 5.0
			_canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10.0 + side, tip - dir * 10.0 - side]), col)
			_canvas.draw_string(font, mid + Vector2(6, -6) - RoofCustom.inward(pts, i) * 4.0, "%.0f°" % float(slopes[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		else:
			_canvas.draw_string(font, mid + Vector2(6, -6), "szczyt", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	if pl.is_empty():
		return
	# crests: sample the roof height on a grid and draw the cells where the highest plane changes
	var lo := _box().position
	var sz := _box().size
	var n := 70
	var last := PackedInt32Array()
	last.resize((n + 1) * (n + 1))
	var ids := {}
	for ix in range(n + 1):
		for iz in range(n + 1):
			var p := lo + Vector2(sz.x * ix / n, sz.y * iz / n)
			var k := -1
			var h := INF
			for j in range(pl.size()):
				var v := float(pl[j]["a"]) * p.x + float(pl[j]["b"]) * p.y + float(pl[j]["c"])
				if v < h:
					h = v
					k = j
			last[ix * (n + 1) + iz] = k if Geometry2D.is_point_in_polygon(p, pts) else -2
	var dot := Color(1.0, 0.6, 0.2, 0.9)
	for ix in range(n):
		for iz in range(n):
			var k0 := last[ix * (n + 1) + iz]
			if k0 < 0:
				continue
			var kr := last[(ix + 1) * (n + 1) + iz]
			var kd := last[ix * (n + 1) + iz + 1]
			if (kr >= 0 and kr != k0) or (kd >= 0 and kd != k0):
				_canvas.draw_circle(_to_px(lo + Vector2(sz.x * ix / n, sz.y * iz / n)), 2.4, dot)


func cancel_edit() -> void:
	for k in _snapshot.keys():
		app.settings.values[k] = _snapshot[k]
	app.roof_apply_settings(_snapshot.duplicate())
	finished.emit(false)
