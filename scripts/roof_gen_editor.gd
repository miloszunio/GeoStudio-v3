class_name RoofGenEditor
extends VBoxContainer
## "Dach" window: draw the roof, then press GENERUJ DACH.
##   Side view (left): the gable picture with the roof profile on it. Drag the round vertices, double-click a line to add
##   a break (mansard), right-click a vertex to remove it. The yellow dots at the ends set how far the roof overhangs.
##   Plan view (right): the footprint with the ridge line. Drag the ridge sideways, drag its ends to stop it short of the
##   gable (a hipped end).
## Nothing changes in the model until GENERUJ DACH; Zamknij without it keeps the previous roof.

signal finished(saved: bool)

const HANDLE := 8.0

var app
var g: Dictionary = {}
var P: Dictionary = {}
var span := 8.0
var wall := 3.0
var left_is_pos := true
var prof: Array = []
var ov_l := 0.5
var ov_r := 0.5
var ov_g := 0.5
var ra := 0.0
var rb := 0.0
var sel := -1
var generated := false

var _snapshot := {}
var _side: Control
var _plan: Control
var _ctl := {}
var _drag := ""
var _busy := false
var _zoom := 1.0
var _pan := Vector2.ZERO
var _status: Label
var _pic := {}                   # the gable picture at true scale: {"tex", "hp" (picture height m), "eave" (m above ground), "apex" (m)}


func setup(main_scene) -> void:
	app = main_scene
	g = app.roof_gable_info()
	P = app.last_rt[0]
	span = maxf(float(g["span"]), 0.5)
	wall = float(g["wall_h"])
	left_is_pos = bool(g["left_is_pos"])
	for k in ["model_roof_height", "model_roof_from_tex", "model_roof_overhang", "model_roof_gable_same", "model_roof_over_gable",
			"model_roof_asym", "model_roof_ridge_shift", "model_roof_over_eave_b", "model_roof_gen"]:
		_snapshot[k] = app.settings.values[k]
	_measure_picture()
	_read_state()
	_build()
	_sync()


## The gable picture is shown at its TRUE scale (its width = the span of the gable wall, same scale in both directions),
## standing on the ground line, so the roof is drawn on the real photo and not on a stretched copy.
func _measure_picture() -> void:
	_pic = {}
	var key := str(g.get("key", ""))
	if key == "" or not app.atlas.regions.has(key):
		return
	var img: Image = app.atlas.regions[key]["img"]
	if img == null or img.get_width() < 8:
		return
	var mpp := span / float(img.get_width())
	_pic = {"tex": app.atlas.get_texture(key), "hp": float(img.get_height()) * mpp}
	var pp := RoofGen.picture_profile(img)
	if not pp.is_empty():
		_pic["eave"] = (float(img.get_height()) - float(pp["eave"])) * mpp
		_pic["apex"] = (float(img.get_height()) - float(pp["apex"])) * mpp


func _read_state() -> void:
	var found := {}
	for gen in RoofGen.list_from_json(app.settings.s("model_roof_gen")):
		if int(gen.get("part", 0)) == 0:
			found = gen
	generated = not found.is_empty()
	var a: float = app.settings.f("model_roof_overhang")
	var b: float = app.settings.f("model_roof_over_eave_b") if app.settings.b("model_roof_asym") else a
	ov_l = a if left_is_pos else b
	ov_r = b if left_is_pos else a
	ov_g = a if app.settings.b("model_roof_gable_same") else app.settings.f("model_roof_over_gable")
	if generated:
		var n := RoofGen.normalize(found, span)
		prof = n["prof"]
		ra = float(n["ra"])
		rb = float(n["rb"])
	else:
		var half := span * 0.5
		var sh: float = app.settings.f("model_roof_ridge_shift") if app.settings.b("model_roof_asym") else 0.0
		var apex := half + (-sh if left_is_pos else sh)
		var rh := maxf(float(g["roof_h"]), 0.5)
		if _pic.has("eave") and float(_pic["apex"]) - float(_pic["eave"]) > 0.3:
			rh = float(_pic["apex"]) - float(_pic["eave"])      # the rise measured on the photo
		prof = RoofGen.default_profile(span, rh, apex)
		ra = 0.0
		rb = 0.0


func _ridge_h() -> float:
	return RoofGen.ridge_height(prof)


func _single() -> bool:
	return RoofGen.single_ridge(prof)


# ------------------------------------------------------------------------------------------------ UI

func _build() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Dach – rysuj profil na zdjęciu szczytu i generuj"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var hint := Label.new()
	hint.text = "Rzut boczny: przeciągaj pomarańczowe wierzchołki, dwuklik na linii dodaje załamanie (dach mansardowy), prawy przycisk na wierzchołku usuwa go; niebieskie kropki na okapie (w górę/w dół) dopasowują wysokość dachu do zdjęcia; żółte – wysunięcie dachu. Rzut z góry: przeciągnij kalenicę w bok albo jej końce (walm). Kółko: zoom, środkowy przycisk: przesuwanie. Model zmieni się po kliknięciu GENERUJ DACH."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	add_child(hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.add_theme_constant_override("separation", 8)
	body.add_child(views)
	_side = _canvas("Rzut boczny (zdjęcie szczytu)", views, 3.0)
	_side.draw.connect(_draw_side)
	_side.gui_input.connect(_side_input)
	_plan = _canvas("Rzut z góry", views, 1.5)
	_plan.draw.connect(_draw_plan)
	_plan.gui_input.connect(_plan_input)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	_row(side, "top", "Wysokość kalenicy nad okapem", 0.1, 40.0, 0.05, " m", func(v: float) -> void: _set_peak(v))
	_row(side, "apex", "Kalenica – odległość od lewej krawędzi", 0.1, 60.0, 0.05, " m", func(v: float) -> void: _set_apex(v))
	_row(side, "ov_l", "Okap – lewa strona", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_l = v
		_sync())
	_row(side, "ov_r", "Okap – prawa strona", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_r = v
		_sync())
	_row(side, "ov_g", "Wysunięcie przy szczytach", 0.0, 3.0, 0.05, " m", func(v: float) -> void:
		ov_g = v
		_sync())
	_row(side, "ra", "Walm: kalenica cofnięta od szczytu 1", 0.0, 30.0, 0.1, " m", func(v: float) -> void:
		ra = v
		_sync())
	_row(side, "rb", "Walm: kalenica cofnięta od szczytu 2", 0.0, 30.0, 0.1, " m", func(v: float) -> void:
		rb = v
		_sync())
	var info := Label.new()
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info)
	_ctl["info"] = info
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	side.add_child(tools)
	var add := Button.new()
	add.text = "Dodaj załamanie połaci (mansarda)"
	add.pressed.connect(_add_break)
	tools.add_child(add)
	var rem := Button.new()
	rem.text = "Usuń zaznaczony wierzchołek"
	rem.pressed.connect(func() -> void: _remove_vertex(sel))
	tools.add_child(rem)
	var tex := Button.new()
	tex.text = "Kąt ze zdjęcia szczytu"
	tex.tooltip_text = "Ustawia wysokość kalenicy z zarysu dachu widocznego na zdjęciu szczytu (dach dwuspadowy)."
	tex.pressed.connect(func() -> void:
		if _pic.has("eave") and float(_pic["apex"]) - float(_pic["eave"]) > 0.3:
			prof = RoofGen.default_profile(span, snappedf(float(_pic["apex"]) - float(_pic["eave"]), 0.01), float((prof[1] as Array)[0]) if _single() else -1.0)
			ra = 0.0
			rb = 0.0
			_sync()
			return
		var r: float = app.atlas.estimate_roof_ratio(str(g["key"])) if str(g["key"]) != "" else -1.0
		if r > 0.0:
			prof = RoofGen.default_profile(span, snappedf(r * span, 0.01), float((prof[1] as Array)[0]) if _single() else -1.0)
			ra = 0.0
			rb = 0.0
			_sync())
	tools.add_child(tex)
	var fit := Button.new()
	fit.text = "Wysokość ścian ze zdjęcia"
	fit.tooltip_text = "Ustawia wysokość ścian do okapu na tę, którą widać na zdjęciu szczytu (różowa linia)."
	fit.pressed.connect(func() -> void:
		if _pic.has("eave"):
			app.set_part_heights(0, snappedf(float(_pic["eave"]), 0.01), maxf(_ridge_h(), 0.0))
			wall = float(_pic["eave"])
			_sync())
	tools.add_child(fit)
	var reset := Button.new()
	reset.text = "Zeruj do zwykłego dwuspadowego"
	reset.pressed.connect(func() -> void:
		prof = RoofGen.default_profile(span, _ridge_h())
		ra = 0.0
		rb = 0.0
		sel = -1
		_sync())
	tools.add_child(reset)
	var gen_btn := Button.new()
	gen_btn.text = "GENERUJ DACH"
	gen_btn.theme_type_variation = "PrimaryButton"
	gen_btn.custom_minimum_size.y = 46
	gen_btn.pressed.connect(generate)
	side.add_child(gen_btn)
	_ctl["gen"] = gen_btn
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("#aab6c7"))
	side.add_child(_status)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.alignment = BoxContainer.ALIGNMENT_END
	add_child(foot)
	var clear := Button.new()
	clear.text = "Wróć do prostego dachu"
	clear.tooltip_text = "Usuwa wygenerowany dach; model wraca do zwykłego dachu dwuspadowego z ustawień."
	clear.pressed.connect(clear_generated)
	foot.add_child(clear)
	var close := Button.new()
	close.text = "Zamknij"
	close.custom_minimum_size = Vector2(130, 36)
	close.pressed.connect(func() -> void: finished.emit(true))
	foot.add_child(close)


func _canvas(title: String, parent: Control, stretch: float) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = stretch
	parent.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#8794a6"))
	box.add_child(l)
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(420, 120)
	c.clip_contents = true
	box.add_child(c)
	return c


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


func _set_peak(v: float) -> void:
	var best := 1
	for i in range(1, prof.size() - 1):
		if float((prof[i] as Array)[1]) >= float((prof[best] as Array)[1]):
			best = i
	var old := float((prof[best] as Array)[1])
	var f := v / maxf(old, 0.01)
	for i in range(1, prof.size() - 1):
		(prof[i] as Array)[1] = maxf(float((prof[i] as Array)[1]) * f, RoofGen.MIN_H)     # the whole roof keeps its shape
	_sync()


func _set_apex(v: float) -> void:
	if _single():
		(prof[1] as Array)[0] = clampf(v, 0.1, span - 0.1)
		_sync()


func _add_break() -> void:
	# a new vertex in the middle of the longest segment
	var best := 0
	var best_len := 0.0
	for k in range(prof.size() - 1):
		var d := absf(float((prof[k + 1] as Array)[0]) - float((prof[k] as Array)[0]))
		if d > best_len:
			best_len = d
			best = k
	_insert_at(best, (float((prof[best] as Array)[0]) + float((prof[best + 1] as Array)[0])) * 0.5)


func _insert_at(seg: int, x: float) -> void:
	if prof.size() >= RoofGen.MAX_VERTS:
		return
	var p0: Array = prof[seg]
	var p1: Array = prof[seg + 1]
	var f := (x - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 1e-4)
	var y := float(p0[1]) + (float(p1[1]) - float(p0[1])) * f
	prof.insert(seg + 1, [x, maxf(y, RoofGen.MIN_H)])
	sel = seg + 1
	ra = 0.0
	rb = 0.0
	_sync()


func _remove_vertex(i: int) -> void:
	if i <= 0 or i >= prof.size() - 1 or prof.size() <= 3:
		return
	prof.remove_at(i)
	sel = -1
	_sync()


func _sync() -> void:
	_busy = true
	(_ctl["top"] as SpinBox).value = _ridge_h()
	(_ctl["apex"] as SpinBox).max_value = span
	(_ctl["apex"] as SpinBox).value = float((prof[1] as Array)[0]) if _single() else float((prof[_peak_index()] as Array)[0])
	(_ctl["apex"] as SpinBox).editable = _single()
	(_ctl["ov_l"] as SpinBox).value = ov_l
	(_ctl["ov_r"] as SpinBox).value = ov_r
	(_ctl["ov_g"] as SpinBox).value = ov_g
	var half_len := (_len() * 0.5)
	for k in ["ra", "rb"]:
		(_ctl[k] as SpinBox).max_value = half_len
		(_ctl[k] as SpinBox).editable = _single()
	(_ctl["ra"] as SpinBox).value = ra if _single() else 0.0
	(_ctl["rb"] as SpinBox).value = rb if _single() else 0.0
	var kinds := "dwuspadowy" if _single() and ra < 0.02 and rb < 0.02 else ("z walmem" if _single() else "łamany (%d połaci)" % (prof.size() - 1))
	(_ctl["info"] as Label).text = "Rozpiętość %.2f m, ściany %.2f m, kalenica na %.2f m. Dach %s." % [span, wall, wall + _ridge_h(), kinds]
	_busy = false
	_side.queue_redraw()
	_plan.queue_redraw()


func _peak_index() -> int:
	var best := 1
	for i in range(1, prof.size() - 1):
		if float((prof[i] as Array)[1]) > float((prof[best] as Array)[1]):
			best = i
	return best


func _len() -> float:
	var bb: Rect2 = P["bb"]
	return bb.size.x if bool(P["ridge_along_x"]) else bb.size.y


# ------------------------------------------------------------------------------------------------ apply

func generate() -> void:
	var gen := {"part": 0, "prof": prof, "ra": ra if _single() else 0.0, "rb": rb if _single() else 0.0}
	var list: Array = []
	for e in RoofGen.list_from_json(app.settings.s("model_roof_gen")):
		if int(e.get("part", 0)) != 0:
			list.append(e)
	list.append(RoofGen.normalize(gen, span))
	var a := ov_l if left_is_pos else ov_r      # side A is t > 0
	var b := ov_r if left_is_pos else ov_l
	app.roof_apply_settings({
		"model_roof_from_tex": false,
		"model_roof_height": snappedf(_ridge_h(), 0.01),
		"model_roof_asym": absf(a - b) > 0.001,
		"model_roof_ridge_shift": 0.0,
		"model_roof_overhang": snappedf(a, 0.01),
		"model_roof_over_eave_b": snappedf(b, 0.01),
		"model_roof_gable_same": false,
		"model_roof_over_gable": snappedf(ov_g, 0.01),
		"model_roof_gen": RoofGen.to_json(list),
	})
	generated = true
	_status.text = "Dach wygenerowany (%d połaci%s). Sprawdź w widoku 3D; zmień profil i kliknij ponownie, żeby poprawić." % [prof.size() - 1, ", walm" if (_single() and (ra > 0.02 or rb > 0.02)) else ""]
	app._set_status("Dach wygenerowany z profilu: kalenica %.2f m nad okapem." % _ridge_h())


func clear_generated() -> void:
	var list: Array = []
	for e in RoofGen.list_from_json(app.settings.s("model_roof_gen")):
		if int(e.get("part", 0)) != 0:
			list.append(e)
	app.roof_apply_settings({"model_roof_gen": RoofGen.to_json(list)})
	generated = false
	_status.text = "Wygenerowany dach usunięty – model ma zwykły dach dwuspadowy z ustawień."


# ------------------------------------------------------------------------------------------------ side view

func _side_view() -> Dictionary:
	var margin := 3.6
	var wm := span + 2.0 * margin
	var hm := maxf(wall + maxf(_ridge_h(), 0.5), float(_pic.get("hp", 0.0))) + 1.4
	var sz := _side.size
	var sc := minf(sz.x / wm, sz.y / hm) * _zoom
	var origin := Vector2(sz.x * 0.5 - (span * 0.5) * sc, sz.y - 0.5 * sc) + _pan
	return {"sc": sc, "o": origin}


func _to_px(p: Vector2) -> Vector2:
	var v := _side_view()
	return Vector2(float(v["o"].x) + p.x * float(v["sc"]), float(v["o"].y) - p.y * float(v["sc"]))


func _from_px(px: Vector2) -> Vector2:
	var v := _side_view()
	return Vector2((px.x - float(v["o"].x)) / float(v["sc"]), (float(v["o"].y) - px.y) / float(v["sc"]))


## Overhang ends of the roof on the picture (extension of the first / last slope).
func _end_points() -> Array:
	var p1: Array = prof[1]
	var pn: Array = prof[prof.size() - 2]
	var sl := float(p1[1]) / maxf(float(p1[0]), 1e-3)
	var sr := float(pn[1]) / maxf(span - float(pn[0]), 1e-3)
	return [Vector2(-ov_l, wall - sl * ov_l), Vector2(span + ov_r, wall - sr * ov_r)]


func _draw_side() -> void:
	var cs := _side.size
	_side.draw_rect(Rect2(Vector2.ZERO, cs), Color(0.09, 0.1, 0.13))
	var top := wall + _ridge_h()
	if not _pic.is_empty():
		top = float(_pic["hp"])                  # true scale: the photo keeps its own proportions
	var tl := _to_px(Vector2(0.0, top))
	var br := _to_px(Vector2(span, 0.0))
	if not _pic.is_empty():
		_side.draw_texture_rect(_pic["tex"], Rect2(tl, br - tl), false)
		if _pic.has("eave"):
			var ye := _to_px(Vector2(0.0, float(_pic["eave"]))).y
			_side.draw_line(Vector2(tl.x - 30.0, ye), Vector2(br.x + 30.0, ye), Color(1.0, 0.3, 0.9, 0.7), 1.0)
			_side.draw_string(ThemeDB.fallback_font, Vector2(br.x + 34.0, ye + 4.0), "okap na zdjęciu %.2f m" % float(_pic["eave"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.5, 0.95))
	else:
		_side.draw_rect(Rect2(tl, br - tl), Color(0.35, 0.33, 0.3))
		_side.draw_string(ThemeDB.fallback_font, tl + Vector2(12, 24), "(brak zdjęcia szczytu – wskaż płótno od GPT w kroku Tekstury)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	_side.draw_rect(Rect2(tl, br - tl), Color(1, 1, 1, 0.35), false, 1.0)
	# eave line
	var el := _to_px(Vector2(0.0, wall))
	var er := _to_px(Vector2(span, wall))
	var ends := _end_points()
	var pl := _to_px(ends[0])
	var pr := _to_px(ends[1])
	var x := minf(pl.x, el.x) - 20.0
	while x < maxf(pr.x, er.x) + 20.0:
		_side.draw_line(Vector2(x, el.y), Vector2(x + 7.0, el.y), Color(0.4, 0.9, 1.0), 2.0)
		x += 13.0
	_side.draw_line(el, _to_px(Vector2(0.0, 0.0)), Color(0.4, 0.9, 1.0, 0.8), 1.5)
	_side.draw_line(er, _to_px(Vector2(span, 0.0)), Color(0.4, 0.9, 1.0, 0.8), 1.5)
	# effective roof (lower envelope) in yellow, the drawn polyline thin
	var eff := RoofGen.effective_profile({"prof": prof}, span)
	var prev := pl
	for q in eff:
		var cur := _to_px(Vector2(float((q as Array)[0]), wall + float((q as Array)[1])))
		_side.draw_line(prev, cur, Color(1.0, 0.85, 0.2), 3.0, true)
		prev = cur
	_side.draw_line(prev, pr, Color(1.0, 0.85, 0.2), 3.0, true)
	for i in range(prof.size() - 1):
		_side.draw_line(_to_px(Vector2(float((prof[i] as Array)[0]), wall + float((prof[i] as Array)[1]))), _to_px(Vector2(float((prof[i + 1] as Array)[0]), wall + float((prof[i + 1] as Array)[1]))), Color(1.0, 0.5, 0.3, 0.8), 1.0)
	for i in range(prof.size()):
		var pt := _to_px(Vector2(float((prof[i] as Array)[0]), wall + float((prof[i] as Array)[1])))
		var end := i == 0 or i == prof.size() - 1
		_side.draw_circle(pt, HANDLE, Color(0, 0, 0, 0.55))
		_side.draw_circle(pt, HANDLE - 2.0, Color(0.4, 0.9, 1.0) if end else (Color(1.0, 1.0, 1.0) if i == sel else Color(1.0, 0.5, 0.3)))
	for e in ends:
		var ep := _to_px(e)
		_side.draw_circle(ep, HANDLE - 1.0, Color(0, 0, 0, 0.55))
		_side.draw_circle(ep, HANDLE - 3.0, Color(1.0, 0.85, 0.2))


func _vertex_at(px: Vector2) -> int:
	var best := -1
	var bd := HANDLE * 1.8
	for i in range(prof.size()):
		var d := _to_px(Vector2(float((prof[i] as Array)[0]), wall + float((prof[i] as Array)[1]))).distance_to(px)
		if d < bd:
			bd = d
			best = i
	return best


func _side_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.12, 0.4, 6.0)
			_side.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.12, 0.4, 6.0)
			_side.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_remove_vertex(_vertex_at(mb.position))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = ""
				if mb.double_click:
					_dblclick(mb.position)
					return
				var ends := _end_points()
				for k in range(2):
					if _to_px(ends[k]).distance_to(mb.position) < HANDLE * 1.8:
						_drag = "ovl" if k == 0 else "ovr"
				if _drag == "":
					var i := _vertex_at(mb.position)
					if i > 0 and i < prof.size() - 1:
						sel = i
						_drag = "v"
					elif i >= 0:
						sel = i
						_drag = "eave"      # the wall tops: fits the roof height to the picture
				_side.queue_redraw()
			else:
				_drag = ""
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag == "pan":
			_pan += mm.relative
			_side.queue_redraw()
			return
		if _drag == "":
			return
		var m := _from_px(mm.position)
		match _drag:
			"ovl":
				ov_l = clampf(-m.x, 0.0, 3.0)
			"ovr":
				ov_r = clampf(m.x - span, 0.0, 3.0)
			"eave":
				if not _pic.is_empty():
					return              # the photo is at true scale: draw the roof on it with the orange vertices
				# The picture always spans wall + roof, so the eave line sits at wall / (wall + rise) of its height.
				# Dragging it up or down until it meets the roof / wall edge of the photo gives the rise.
				var top := wall + _ridge_h()
				var f := clampf((top - m.y) / maxf(top, 0.01), 0.02, 0.9)
				_set_peak(clampf(wall * f / (1.0 - f), 0.1, 40.0))
				return
			"v":
				if sel > 0 and sel < prof.size() - 1:
					var lo := float((prof[sel - 1] as Array)[0]) + 0.1
					var hi := float((prof[sel + 1] as Array)[0]) - 0.1
					prof[sel] = [clampf(m.x, lo, maxf(hi, lo)), clampf(m.y - wall, RoofGen.MIN_H, 40.0)]
		_sync()


func _dblclick(px: Vector2) -> void:
	var m := _from_px(px)
	for k in range(prof.size() - 1):
		var x0 := float((prof[k] as Array)[0])
		var x1 := float((prof[k + 1] as Array)[0])
		if m.x > x0 + 0.1 and m.x < x1 - 0.1:
			_insert_at(k, m.x)
			return


# ------------------------------------------------------------------------------------------------ plan view

func _plan_view() -> Dictionary:
	var pts: PackedVector2Array = P["pts"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(1.0, 1.0)
	hi += Vector2(1.0, 1.0)
	var sz := _plan.size
	var sc := minf(sz.x / (hi.x - lo.x), sz.y / (hi.y - lo.y)) * 0.92
	var origin := (sz - (hi - lo) * sc) * 0.5 - lo * sc
	return {"sc": sc, "o": origin}


func _plan_px(p: Vector2) -> Vector2:
	var v := _plan_view()
	return Vector2(p) * float(v["sc"]) + (v["o"] as Vector2)


func _plan_from(px: Vector2) -> Vector2:
	var v := _plan_view()
	return (px - (v["o"] as Vector2)) / float(v["sc"])


func _ridge_across() -> float:
	var ax := float((prof[_peak_index()] as Array)[0])
	var t := (span * 0.5 - ax) if left_is_pos else (ax - span * 0.5)
	return float(P["ridge_mid"]) + t


func _ridge_pts() -> Array:
	var bb: Rect2 = P["bb"]
	var along_x: bool = P["ridge_along_x"]
	var s_lo := bb.position.x if along_x else bb.position.y
	var s_hi := bb.end.x if along_x else bb.end.y
	var c := _ridge_across()
	var a := s_lo + (ra if _single() else 0.0)
	var b := s_hi - (rb if _single() else 0.0)
	return [Vector2(a, c) if along_x else Vector2(c, a), Vector2(b, c) if along_x else Vector2(c, b)]


func _draw_plan() -> void:
	_plan.draw_rect(Rect2(Vector2.ZERO, _plan.size), Color(0.09, 0.1, 0.13))
	var pts: PackedVector2Array = P["pts"]
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(_plan_px(p))
	_plan.draw_colored_polygon(poly, Color(0.35, 0.33, 0.3, 0.55))
	poly.append(poly[0])
	_plan.draw_polyline(poly, Color(0.4, 0.9, 1.0), 2.0, true)
	var rp := _ridge_pts()
	var a := _plan_px(rp[0])
	var b := _plan_px(rp[1])
	var bb: Rect2 = P["bb"]
	var along_x: bool = P["ridge_along_x"]
	# hip rafters: from the corners to the ridge ends
	if _single() and (ra > 0.02 or rb > 0.02):
		var corners := [Vector2(bb.position.x, bb.position.y), Vector2(bb.end.x, bb.position.y), Vector2(bb.end.x, bb.end.y), Vector2(bb.position.x, bb.end.y)]
		for cpt in corners:
			var pa: Vector2 = rp[0]
			var pb: Vector2 = rp[1]
			var near_a: bool = (cpt.x - bb.get_center().x < 0.0) if along_x else (cpt.y - bb.get_center().y < 0.0)
			_plan.draw_line(_plan_px(cpt), _plan_px(pa if near_a else pb), Color(1.0, 0.85, 0.2, 0.7), 1.5, true)
	_plan.draw_line(a, b, Color(1.0, 0.85, 0.2), 3.0, true)
	var col := Color(1.0, 0.5, 0.3) if _single() else Color(0.6, 0.6, 0.6)
	for pt in [a, b]:
		_plan.draw_circle(pt, HANDLE, Color(0, 0, 0, 0.55))
		_plan.draw_circle(pt, HANDLE - 2.0, col)


func _plan_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = ""
				var rp := _ridge_pts()
				for k in range(2):
					if _plan_px(rp[k]).distance_to(mb.position) < HANDLE * 1.8 and _single():
						_drag = "ra" if k == 0 else "rb"
				if _drag == "":
					var a := _plan_px(rp[0])
					var b := _plan_px(rp[1])
					if _dist_to_seg(mb.position, a, b) < 10.0:
						_drag = "ridge"
			else:
				_drag = ""
	elif ev is InputEventMouseMotion and _drag in ["ra", "rb", "ridge"]:
		var m := _plan_from((ev as InputEventMouseMotion).position)
		var bb: Rect2 = P["bb"]
		var along_x: bool = P["ridge_along_x"]
		var s := m.x if along_x else m.y
		var across := m.y if along_x else m.x
		var s_lo := bb.position.x if along_x else bb.position.y
		var s_hi := bb.end.x if along_x else bb.end.y
		match _drag:
			"ra":
				ra = clampf(s - s_lo, 0.0, (s_hi - s_lo) * 0.5 - 0.05)
			"rb":
				rb = clampf(s_hi - s, 0.0, (s_hi - s_lo) * 0.5 - 0.05)
			"ridge":
				if _single():
					var t := across - float(P["ridge_mid"])
					var ax := (span * 0.5 - t) if left_is_pos else (span * 0.5 + t)
					(prof[1] as Array)[0] = clampf(ax, 0.1, span - 0.1)
		_sync()


static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func cancel_edit() -> void:
	app.roof_apply_settings(_snapshot)
	finished.emit(false)
