class_name ChimneyEditor
extends VBoxContainer
## Chimney editor window. Three views of the roof share one set of chimneys:
##   - plan (from above): click or drag to put the selected chimney on the roof,
##   - front / side elevations: drag the body to slide it along the roof, drag the round handle on top to change its height.
## Width, length, height and position can also be typed. The shaft is textured with a repeated cut-out of a wall
## picture: pick the region and drag a rectangle on its preview. The model behind the window follows at once.
## Zapisz keeps the chimneys, Anuluj restores what was there.

signal finished(saved: bool)

const HANDLE := 9.0
const GRID := 60
const MODES := ["plan", "front", "side"]

var app
var flow: ChimneyFlow
var items: Array = []
var sel := -1
var _snapshot := ""
var _ctl := {}
var _busy := false
var _views := {}                 # mode -> Control
var _zoom := {"plan": 1.0, "front": 1.0, "side": 1.0}
var _drag := ""                  # "", "move" or "top"
var _drag_off := Vector2.ZERO
var _list: ItemList
var _frag_view: Control
var _frag_drag := false
var _frag_a := Vector2.ZERO
var _bx0 := 0.0
var _bx1 := 1.0
var _bz0 := 0.0
var _bz1 := 1.0
var _ymax_roof := 4.0
var _sil: Array = []             # per part {"front": PackedVector2Array (x, y), "side": PackedVector2Array (z, y)}


func setup(main_scene, f: ChimneyFlow) -> void:
	app = main_scene
	flow = f
	_snapshot = app.settings.s(ChimneyFlow.KEY)
	items = flow.list()
	sel = 0 if not items.is_empty() else -1
	_compute_geometry()
	_build()
	_refresh_list()
	_sync_controls()


# ---------------------------------------------------------------------------------------------- geometry of the roof

func _compute_geometry() -> void:
	var first := true
	_sil.clear()
	for i in range(app.last_rt.size()):
		var P: Dictionary = app.last_rt[i]
		var bb: Rect2 = P["bb"]
		if first:
			_bx0 = bb.position.x
			_bx1 = bb.end.x
			_bz0 = bb.position.y
			_bz1 = bb.end.y
			first = false
		else:
			_bx0 = minf(_bx0, bb.position.x)
			_bx1 = maxf(_bx1, bb.end.x)
			_bz0 = minf(_bz0, bb.position.y)
			_bz1 = maxf(_bz1, bb.end.y)
		_ymax_roof = maxf(_ymax_roof if i > 0 else 0.0, float(P["wall_h"]) + float(P["roof_h"]))
		# silhouettes: highest roof point in every column (front) and row (side) of the footprint
		var pts: PackedVector2Array = P["pts"]
		var qs := PackedVector2Array()
		var ix_list: Array = []
		for ix in range(GRID):
			for iz in range(GRID):
				var q := Vector2(bb.position.x + (float(ix) + 0.5) / GRID * bb.size.x, bb.position.y + (float(iz) + 0.5) / GRID * bb.size.y)
				if Geometry2D.is_point_in_polygon(q, pts):
					qs.append(q)
					ix_list.append(Vector2i(ix, iz))
		var ys: PackedFloat32Array = app.roof_y_batch(i, qs)
		var cols := PackedFloat32Array()
		cols.resize(GRID)
		cols.fill(-1e9)
		var rows := PackedFloat32Array()
		rows.resize(GRID)
		rows.fill(-1e9)
		for k in range(ys.size()):
			var ij: Vector2i = ix_list[k]
			cols[ij.x] = maxf(cols[ij.x], ys[k])
			rows[ij.y] = maxf(rows[ij.y], ys[k])
		var front := PackedVector2Array()
		var side := PackedVector2Array()
		for g in range(GRID):
			if cols[g] > -1e8:
				front.append(Vector2(bb.position.x + (float(g) + 0.5) / GRID * bb.size.x, cols[g]))
			if rows[g] > -1e8:
				side.append(Vector2(bb.position.y + (float(g) + 0.5) / GRID * bb.size.y, rows[g]))
		_sil.append({"front": front, "side": side})


func _ymax() -> float:
	var y := _ymax_roof
	for c in items:
		y = maxf(y, flow.top_y(c))
	return y + 1.0


func _view_bounds(mode: String) -> Rect2:
	match mode:
		"plan":
			return Rect2(_bx0 - 1.0, _bz0 - 1.0, _bx1 - _bx0 + 2.0, _bz1 - _bz0 + 2.0)
		"front":
			return Rect2(_bx0 - 1.0, -0.4, _bx1 - _bx0 + 2.0, _ymax() + 0.4)
		_:
			return Rect2(_bz0 - 1.0, -0.4, _bz1 - _bz0 + 2.0, _ymax() + 0.4)


func _scale(mode: String, size: Vector2) -> float:
	var b := _view_bounds(mode)
	return minf(size.x / maxf(b.size.x, 0.1), size.y / maxf(b.size.y, 0.1)) * float(_zoom[mode]) * 0.96


## View space: plan (x, z), elevations (horizontal axis, height). Elevations have y up.
func _to_screen(mode: String, size: Vector2, wp: Vector2) -> Vector2:
	var c := _view_bounds(mode).get_center()
	var s := _scale(mode, size)
	if mode == "plan":
		return (wp - c) * s + size * 0.5
	return Vector2((wp.x - c.x) * s, -(wp.y - c.y) * s) + size * 0.5


func _from_screen(mode: String, size: Vector2, sp: Vector2) -> Vector2:
	var c := _view_bounds(mode).get_center()
	var s := _scale(mode, size)
	if mode == "plan":
		return (sp - size * 0.5) / s + c
	return Vector2((sp.x - size.x * 0.5) / s + c.x, -(sp.y - size.y * 0.5) / s + c.y)


## Centre of a chimney in view space (elevations: only x is the horizontal position).
func _centre(mode: String, c: Dictionary) -> Vector2:
	match mode:
		"plan":
			return Vector2(float(c["x"]), float(c["z"]))
		"front":
			return Vector2(float(c["x"]), 0.0)
		_:
			return Vector2(float(c["z"]), 0.0)


func _view_rect(mode: String, c: Dictionary) -> Rect2:
	var cx := float(c["x"])
	var cz := float(c["z"])
	var w := float(c["w"])
	var l := float(c["l"])
	if mode == "plan":
		return Rect2(cx - w * 0.5, cz - l * 0.5, w, l)
	var rr := flow.roof_range(c)
	var top := rr.y + float(c["h"])
	var base := rr.x - ChimneyFlow.SINK
	if mode == "front":
		return Rect2(cx - w * 0.5, base, w, top - base)
	return Rect2(cz - l * 0.5, base, l, top - base)


# ---------------------------------------------------------------------------------------------- UI

func _build() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Kominy"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var hint := Label.new()
	hint.text = "Rzut z góry: kliknij lub przeciągnij komin, żeby go ustawić na dachu. Rzuty z przodu i z boku: przeciągaj korpus, żeby przesuwać komin po dachu, a okrągły uchwyt na górze zmienia wysokość. Wymiary i położenie można też wpisać. Kółko myszy: zoom."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	add_child(hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)

	# left: the list of chimneys
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void:
		sel = i
		_sync_controls()
		_redraw())
	left.add_child(_list)
	var add := Button.new()
	add.text = "Dodaj komin"
	add.pressed.connect(func() -> void:
		var c := flow.default_chimney()
		items.append(c)
		sel = items.size() - 1
		_after_edit())
	left.add_child(add)
	var dup := Button.new()
	dup.text = "Powiel zaznaczony"
	dup.pressed.connect(func() -> void:
		if sel < 0:
			return
		var c: Dictionary = (items[sel] as Dictionary).duplicate(true)
		c["x"] = float(c["x"]) + 0.9
		items.append(c)
		sel = items.size() - 1
		_auto_part(c)
		_after_edit())
	left.add_child(dup)
	var del := Button.new()
	del.text = "Usuń zaznaczony"
	del.pressed.connect(func() -> void:
		if sel < 0:
			return
		items.remove_at(sel)
		sel = mini(sel, items.size() - 1)
		_after_edit())
	left.add_child(del)

	# middle: plan + two elevations
	var mid := HBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	body.add_child(mid)
	var plan := _make_view("plan")
	plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan.custom_minimum_size = Vector2(380, 320)
	mid.add_child(plan)
	var elev := VBoxContainer.new()
	elev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elev.add_theme_constant_override("separation", 8)
	mid.add_child(elev)
	for mode in ["front", "side"]:
		var v := _make_view(mode)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size = Vector2(300, 150)
		elev.add_child(v)

	# right: numbers + texture
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 320
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	_row(side, "w", "Szerokość (oś X)", 0.1, 6.0, 0.01, " m")
	_row(side, "l", "Długość (oś Z)", 0.1, 6.0, 0.01, " m")
	_row(side, "h", "Wysokość nad dachem", 0.0, 12.0, 0.01, " m")
	_row(side, "x", "Położenie X", -500.0, 500.0, 0.01, " m")
	_row(side, "z", "Położenie Z", -500.0, 500.0, 0.01, " m")
	var cap := CheckBox.new()
	cap.text = "Betonowa czapka"
	cap.toggled.connect(func(on: bool) -> void:
		if _busy or sel < 0:
			return
		items[sel]["cap"] = on
		_after_edit())
	side.add_child(cap)
	_ctl["cap"] = cap
	var info := Label.new()
	info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info)
	_ctl["info"] = info
	side.add_child(HSeparator.new())
	var tl := Label.new()
	tl.text = "Tekstura korpusu (powielany fragment ściany)"
	side.add_child(tl)
	var opt := OptionButton.new()
	opt.item_selected.connect(func(i: int) -> void:
		if _busy or sel < 0:
			return
		items[sel]["tex"] = str(opt.get_item_metadata(i))
		_after_edit())
	side.add_child(opt)
	_ctl["tex"] = opt
	_frag_view = Control.new()
	_frag_view.custom_minimum_size = Vector2(300, 150)
	_frag_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frag_view.clip_contents = true
	_frag_view.draw.connect(_draw_frag)
	_frag_view.gui_input.connect(_frag_input)
	side.add_child(_frag_view)
	var fh := Label.new()
	fh.text = "Przeciągnij prostokąt na obrazie – ten fragment będzie się powtarzał na ścianach komina."
	fh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fh.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	side.add_child(fh)
	_row(side, "tscale", "Wielkość fragmentu (skala)", 0.1, 10.0, 0.05, "×")

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


func _make_view(mode: String) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.clip_contents = true
	c.draw.connect(_draw_view.bind(c, mode))
	c.gui_input.connect(_view_input.bind(c, mode))
	_views[mode] = c
	return c


func _row(parent: Control, id: String, label: String, lo: float, hi: float, step: float, suffix: String) -> void:
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
	sb.custom_minimum_size.x = 120
	sb.value_changed.connect(func(v: float) -> void:
		if _busy or sel < 0:
			return
		items[sel][id] = v
		if id == "x" or id == "z":
			_auto_part(items[sel])
		_after_edit(false))
	line.add_child(sb)
	_ctl[id] = sb


func _redraw() -> void:
	for m in _views.keys():
		(_views[m] as Control).queue_redraw()
	if is_instance_valid(_frag_view):
		_frag_view.queue_redraw()


func _refresh_list() -> void:
	_list.clear()
	for i in range(items.size()):
		var c: Dictionary = items[i]
		_list.add_item("Komin %d – %.2f × %.2f × %.2f m" % [i + 1, float(c["w"]), float(c["l"]), float(c["h"])])
	if sel >= 0 and sel < items.size():
		_list.select(sel)


func _sync_controls() -> void:
	_busy = true
	var have := sel >= 0 and sel < items.size()
	for id in ["w", "l", "h", "x", "z", "tscale"]:
		var sb := _ctl[id] as SpinBox
		sb.editable = have
		if have:
			sb.value = float(items[sel][id])
	(_ctl["cap"] as CheckBox).disabled = not have
	(_ctl["cap"] as CheckBox).button_pressed = bool(items[sel]["cap"]) if have else false
	var opt := _ctl["tex"] as OptionButton
	opt.disabled = not have
	opt.clear()
	opt.add_item("automatycznie (ściana długa arkusza)")
	opt.set_item_metadata(0, "auto")
	var keys: Array = app.atlas.regions.keys()
	keys.sort()
	for k in keys:
		opt.add_item(str(k))
		opt.set_item_metadata(opt.item_count - 1, str(k))
	if have:
		for i in range(opt.item_count):
			if str(opt.get_item_metadata(i)) == str(items[sel]["tex"]):
				opt.select(i)
	var info := _ctl["info"] as Label
	if have:
		var c: Dictionary = items[sel]
		var rr := flow.roof_range(c)
		info.text = "Wierzch komina: %.2f m nad ziemią (kalenica %.2f m). Dolna krawędź schowana %.2f m pod dachem. Bryła: %s." % [
			rr.y + float(c["h"]), _ymax_roof, ChimneyFlow.SINK, "główna" if int(c["part"]) == 0 else "dobudówka %d" % int(c["part"])]
	else:
		info.text = "Brak kominów – dodaj pierwszy przyciskiem po lewej."
	_busy = false


## Saves the chimneys (the model rebuilds itself) and refreshes everything the window shows.
func _after_edit(sync := true) -> void:
	flow.save(items)
	_refresh_list()
	if sync:
		_sync_controls()
	else:
		var have := sel >= 0 and sel < items.size()
		if have:
			var rr := flow.roof_range(items[sel])
			(_ctl["info"] as Label).text = "Wierzch komina: %.2f m nad ziemią (kalenica %.2f m). Dolna krawędź schowana %.2f m pod dachem." % [rr.y + float(items[sel]["h"]), _ymax_roof, ChimneyFlow.SINK]
	_redraw()


## The part (main body or annex) whose roof the chimney stands on: the highest one under its centre.
func _auto_part(c: Dictionary) -> void:
	var p := Vector2(float(c["x"]), float(c["z"]))
	var best := -1
	var best_y := -1e9
	for i in range(app.last_rt.size()):
		var pts: PackedVector2Array = app.last_rt[i]["pts"]
		if Geometry2D.is_point_in_polygon(p, pts):
			var ys: PackedFloat32Array = app.roof_y_batch(i, PackedVector2Array([p]))
			if not ys.is_empty() and ys[0] > best_y:
				best_y = ys[0]
				best = i
	if best >= 0:
		c["part"] = best


# ---------------------------------------------------------------------------------------------- drawing

func _draw_view(c: Control, mode: String) -> void:
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.09, 0.11, 0.15))
	var font := ThemeDB.fallback_font
	var label := {"plan": "Rzut z góry (X →, Z ↓)", "front": "Rzut z przodu (X →)", "side": "Rzut z boku (Z →)"}
	if mode == "plan":
		for i in range(app.last_rt.size()):
			var pts: PackedVector2Array = app.last_rt[i]["pts"]
			var sp := PackedVector2Array()
			for q in pts:
				sp.append(_to_screen(mode, sz, q))
			if sp.size() >= 3:
				c.draw_colored_polygon(sp, Color(0.45, 0.5, 0.6, 0.35))
				var closed := sp.duplicate()
				closed.append(sp[0])
				c.draw_polyline(closed, Color(0.65, 0.72, 0.85), 2.0)
			var info: Dictionary = app.roof_ridge_info(i)
			if bool(info["has"]):
				var bb: Rect2 = app.last_rt[i]["bb"]
				var a := Vector2(bb.position.x, float(info["mid"])) if bool(info["along_x"]) else Vector2(float(info["mid"]), bb.position.y)
				var b := Vector2(bb.end.x, float(info["mid"])) if bool(info["along_x"]) else Vector2(float(info["mid"]), bb.end.y)
				c.draw_dashed_line(_to_screen(mode, sz, a), _to_screen(mode, sz, b), Color(1.0, 0.55, 0.25), 2.0, 8.0)
	else:
		var g0 := _to_screen(mode, sz, Vector2(_view_bounds(mode).position.x, 0.0))
		var g1 := _to_screen(mode, sz, Vector2(_view_bounds(mode).end.x, 0.0))
		c.draw_line(g0, g1, Color(0.5, 0.55, 0.45), 2.0)
		for sil in _sil:
			var poly: PackedVector2Array = sil["front" if mode == "front" else "side"]
			if poly.size() < 2:
				continue
			var sp := PackedVector2Array()
			sp.append(_to_screen(mode, sz, Vector2(poly[0].x, 0.0)))
			for q in poly:
				sp.append(_to_screen(mode, sz, q))
			sp.append(_to_screen(mode, sz, Vector2(poly[poly.size() - 1].x, 0.0)))
			c.draw_colored_polygon(sp, Color(0.45, 0.5, 0.6, 0.35))
			var line := PackedVector2Array()
			for q in poly:
				line.append(_to_screen(mode, sz, q))
			c.draw_polyline(line, Color(1.0, 0.55, 0.25), 2.0)
	for k in range(items.size()):
		var ch: Dictionary = items[k]
		var r := _view_rect(mode, ch)
		var a := _to_screen(mode, sz, r.position)
		var b := _to_screen(mode, sz, r.end)
		var sr := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(b.x - a.x), absf(b.y - a.y)))
		var on := k == sel
		c.draw_rect(sr, Color(0.95, 0.62, 0.2, 0.9) if on else Color(0.72, 0.42, 0.3, 0.85))
		c.draw_rect(sr, Color(1, 1, 1) if on else Color(0.2, 0.1, 0.08), false, 2.0)
		if mode == "plan":
			c.draw_string(font, sr.position + Vector2(3, -4), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.95))
		elif on:
			var top_pt := _to_screen(mode, sz, Vector2(_centre(mode, ch).x, r.end.y))
			c.draw_circle(top_pt, HANDLE, Color(0.35, 0.8, 1.0))
			c.draw_arc(top_pt, HANDLE, 0.0, TAU, 20, Color(1, 1, 1), 2.0)
	c.draw_string(font, Vector2(8, 18), str(label[mode]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.9))


func _frag_img_rect() -> Rect2:
	if sel < 0 or sel >= items.size():
		return Rect2()
	var key := flow._region_key(items[sel])
	if key == "":
		return Rect2()
	var tex: Texture2D = app.atlas.get_texture(key)
	if tex == null:
		return Rect2()
	var sz := _frag_view.size
	var ts := Vector2(tex.get_width(), tex.get_height())
	var s := minf(sz.x / ts.x, sz.y / ts.y)
	var rs := ts * s
	return Rect2((sz - rs) * 0.5, rs)


func _draw_frag() -> void:
	var sz := _frag_view.size
	_frag_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.09, 0.11, 0.15))
	var ir := _frag_img_rect()
	if ir.size.x <= 0.0:
		_frag_view.draw_string(ThemeDB.fallback_font, Vector2(10, 24), "Brak wczytanej tekstury – komin dostanie kolor ceglany.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.9))
		return
	var key := flow._region_key(items[sel])
	_frag_view.draw_texture_rect(app.atlas.get_texture(key), ir, false)
	var f: Array = items[sel]["frag"]
	var fr := Rect2(ir.position + Vector2(float(f[0]), float(f[1])) * ir.size, Vector2(float(f[2]), float(f[3])) * ir.size)
	_frag_view.draw_rect(fr, Color(1.0, 0.85, 0.2, 0.25))
	_frag_view.draw_rect(fr, Color(1.0, 0.85, 0.2), false, 2.0)


# ---------------------------------------------------------------------------------------------- input

func _view_input(ev: InputEvent, c: Control, mode: String) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom[mode] = clampf(float(_zoom[mode]) * 1.15, 0.4, 6.0)
			c.queue_redraw()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom[mode] = clampf(float(_zoom[mode]) / 1.15, 0.4, 6.0)
			c.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_begin(c, mode, mb.position)
			else:
				_drag = ""
	elif ev is InputEventMouseMotion and _drag != "":
		_drag_move(c, mode, (ev as InputEventMouseMotion).position)


func _drag_begin(c: Control, mode: String, pos: Vector2) -> void:
	var wp := _from_screen(mode, c.size, pos)
	if mode != "plan" and sel >= 0 and sel < items.size():
		var ch: Dictionary = items[sel]
		var top_pt := _to_screen(mode, c.size, Vector2(_centre(mode, ch).x, flow.top_y(ch)))
		if pos.distance_to(top_pt) <= HANDLE + 5.0:
			_drag = "top"
			return
	var hit := -1
	if sel >= 0 and sel < items.size() and _view_rect(mode, items[sel]).grow(0.05).has_point(wp):
		hit = sel
	else:
		for k in range(items.size() - 1, -1, -1):
			if _view_rect(mode, items[k]).grow(0.05).has_point(wp):
				hit = k
				break
	if hit >= 0:
		sel = hit
		_drag = "move"
		_drag_off = wp - _centre(mode, items[hit])
		_sync_controls()
		_refresh_list()
		_redraw()
	elif sel >= 0 and sel < items.size():
		_drag = "move"
		_drag_off = Vector2.ZERO
		_drag_move(c, mode, pos)


func _drag_move(c: Control, mode: String, pos: Vector2) -> void:
	if sel < 0 or sel >= items.size():
		return
	var wp := _from_screen(mode, c.size, pos)
	var ch: Dictionary = items[sel]
	if _drag == "move":
		var q := wp - _drag_off
		match mode:
			"plan":
				ch["x"] = snappedf(q.x, 0.01)
				ch["z"] = snappedf(q.y, 0.01)
			"front":
				ch["x"] = snappedf(wp.x - _drag_off.x, 0.01)
			_:
				ch["z"] = snappedf(wp.x - _drag_off.x, 0.01)
		_auto_part(ch)
	elif _drag == "top":
		var rr := flow.roof_range(ch)
		ch["h"] = clampf(snappedf(wp.y - rr.y, 0.01), 0.0, 12.0)
	_after_edit()


func _frag_input(ev: InputEvent) -> void:
	if sel < 0 or sel >= items.size():
		return
	var ir := _frag_img_rect()
	if ir.size.x <= 0.0:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		_frag_drag = mb.pressed
		if mb.pressed:
			_frag_a = ((mb.position - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
	elif ev is InputEventMouseMotion and _frag_drag:
		var b := (((ev as InputEventMouseMotion).position - ir.position) / ir.size).clamp(Vector2.ZERO, Vector2.ONE)
		var lo := Vector2(minf(_frag_a.x, b.x), minf(_frag_a.y, b.y))
		var sz := Vector2(absf(b.x - _frag_a.x), absf(b.y - _frag_a.y))
		if sz.x >= 0.02 and sz.y >= 0.02:
			items[sel]["frag"] = [lo.x, lo.y, sz.x, sz.y]
			_after_edit(false)


# ---------------------------------------------------------------------------------------------- finish

func cancel_edit() -> void:
	flow.save(ChimneyFlow.parse(_snapshot))
	finished.emit(false)


func save_edit() -> void:
	flow.save(items)
	finished.emit(true)
