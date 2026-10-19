class_name PanelEditor
extends VBoxContainer
## Window content: the canvas returned by GPT with a rectangle around every picture and a code for each (S1 long wall ...).
## Drag a rectangle to move it, its edges and corners to resize it, drag on an empty spot to add one.
## "Zapisz" keeps the panels, the sheet is laid out again from them.

signal finished(saved: bool)

const HANDLE := 7.0

var app
var path := ""
var info := {}
var panels: Array = []          # [{"code": String, "inner": Rect2i}]
var _tex: ImageTexture
var _img: Image
var _canvas: Control
var _list: ItemList
var _code_pick: OptionButton
var _status: Label
var _sel := -1
var _zoom := 1.0
var _origin := Vector2.ZERO
var _fitted := false
var _drag := ""                  # "", "move", "new", "pan", or edge letters: l r t b lt rt lb rb
var _drag_img := Vector2.ZERO
var _drag_rect := Rect2i()
var _drag_mouse := Vector2.ZERO
var _busy := false


func setup(main_scene, image_path: String, current: Array) -> void:
	app = main_scene
	path = image_path
	info = app.gpt.gpt_info()
	panels = []
	for p in current:
		panels.append({"code": str(p["code"]), "inner": p["inner"]})
	_img = Image.load_from_file(path)
	if _img != null and not _img.is_empty():
		_tex = ImageTexture.create_from_image(_img)
	_build()
	_refresh_list()


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Panele płótna od GPT – przyporządkowanie"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	var hint := Label.new()
	hint.text = "Każdy obraz (sektor arkusza albo ramka) dostaje kod (S1 długa ściana A … S5 dach). Przeciągnij prostokąt, żeby go przesunąć, krawędź lub róg – żeby zmienić rozmiar, puste miejsce – żeby dodać nowy. Kółko myszy: zoom, prawy przycisk: przesuwanie widoku."
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
	_canvas.custom_minimum_size = Vector2(560, 420)
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(func() -> void:
		_fitted = false
		_canvas.queue_redraw())
	body.add_child(_canvas)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 160
	_list.item_selected.connect(func(i: int) -> void: _select(i))
	side.add_child(_list)
	var lab := Label.new()
	lab.text = "Kod zaznaczonego panelu"
	side.add_child(lab)
	_code_pick = OptionButton.new()
	var ids: Array = [""]
	ids.append_array(PanelSheet.CODES)
	for c in ids:
		_code_pick.add_item(str(PanelSheet.LABELS.get(c, c)))
		_code_pick.set_item_metadata(_code_pick.get_item_count() - 1, c)
	_code_pick.item_selected.connect(_on_code_picked)
	side.add_child(_code_pick)
	var del := Button.new()
	del.text = "Usuń panel"
	del.pressed.connect(func() -> void:
		if _sel >= 0 and _sel < panels.size():
			panels.remove_at(_sel)
			_sel = -1
			_refresh_list())
	side.add_child(del)
	var redo := Button.new()
	redo.text = "Wykryj ramki ponownie"
	redo.tooltip_text = "Szuka czerwonych ramek w obrazie i przypisuje kody od nowa (ręczne poprawki przepadną)."
	redo.pressed.connect(_redetect)
	side.add_child(redo)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("#aab6c7"))
	side.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var ok := Button.new()
	ok.text = "Zapisz i ułóż arkusz"
	ok.theme_type_variation = "PrimaryButton"
	ok.custom_minimum_size.y = 38
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func() -> void: finished.emit(true))
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.custom_minimum_size.y = 38
	cancel.pressed.connect(func() -> void: finished.emit(false))
	row.add_child(cancel)


func _redetect() -> void:
	if _img == null:
		return
	panels = PanelSheet.detect_and_assign(_img, info)
	_sel = -1
	_refresh_list()
	if panels.is_empty():
		_status.text = "Nie znaleziono czerwonych ramek. Narysuj prostokąty ręcznie (przeciągnij po obrazie)."


func _refresh_list() -> void:
	_busy = true
	_list.clear()
	for i in range(panels.size()):
		var r: Rect2i = panels[i]["inner"]
		_list.add_item("%s   %d × %d px" % [PanelSheet.LABELS.get(str(panels[i]["code"]), "?"), r.size.x, r.size.y])
	if _sel >= 0 and _sel < panels.size():
		_list.select(_sel)
		for k in range(_code_pick.get_item_count()):
			if str(_code_pick.get_item_metadata(k)) == str(panels[_sel]["code"]):
				_code_pick.select(k)
	_busy = false
	var have := {}
	for p in panels:
		if str(p["code"]) != "":
			have[str(p["code"])] = true
	var miss: Array = []
	for c in ["S1", "S2", "S3", "S4", "S5"]:
		if not have.has(c):
			miss.append(c)
	var dup := panels.size() - have.size() - panels.filter(func(p: Dictionary) -> bool: return str(p["code"]) == "").size()
	_status.text = ("Brakuje: %s (program użyje podobnej ściany lub koloru zastępczego)." % ", ".join(miss)) if not miss.is_empty() else "Komplet S1–S5."
	if dup > 0:
		_status.text += " Uwaga: ten sam kod jest użyty %d razy – liczy się pierwszy." % dup
	_canvas.queue_redraw()


func _select(i: int) -> void:
	_sel = i
	_refresh_list()


func _on_code_picked(idx: int) -> void:
	if _busy or _sel < 0 or _sel >= panels.size():
		return
	panels[_sel]["code"] = str(_code_pick.get_item_metadata(idx))
	_refresh_list()


# ---- view ----------------------------------------------------------------------------------------------------

func _fit() -> void:
	if _tex == null:
		return
	var sz := _canvas.size
	_zoom = minf(sz.x / float(_tex.get_width()), sz.y / float(_tex.get_height()))
	_origin = (sz - Vector2(_tex.get_size()) * _zoom) * 0.5
	_fitted = true


func _to_screen(p: Vector2) -> Vector2:
	return _origin + p * _zoom


func _to_img(s: Vector2) -> Vector2:
	return (s - _origin) / _zoom


func _color_of(code: String) -> Color:
	var i := PanelSheet.CODES.find(code)
	if i < 0:
		return Color(0.7, 0.7, 0.7)
	return Color.from_hsv(float(i) / 8.0, 0.75, 1.0)


func _draw_canvas() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#10141b"))
	if _tex == null:
		_canvas.draw_string(ThemeDB.fallback_font, Vector2(20, 30), "Nie udało się wczytać obrazu.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		return
	if not _fitted:
		_fit()
	_canvas.draw_texture_rect(_tex, Rect2(_origin, Vector2(_tex.get_size()) * _zoom), false)
	var font := ThemeDB.fallback_font
	for i in range(panels.size()):
		var r: Rect2i = panels[i]["inner"]
		var sr := Rect2(_to_screen(Vector2(r.position)), Vector2(r.size) * _zoom)
		var col := _color_of(str(panels[i]["code"]))
		_canvas.draw_rect(sr, col, false, 3.0 if i == _sel else 2.0)
		var label := str(panels[i]["code"]) if str(panels[i]["code"]) != "" else "?"
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8
		_canvas.draw_rect(Rect2(sr.position, Vector2(w, 18)), Color(0, 0, 0, 0.75))
		_canvas.draw_string(font, sr.position + Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		if i == _sel:
			for hp in _handle_points(sr):
				_canvas.draw_rect(Rect2(hp[1] - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), col)


## [[mode, screen point], ...] of the eight handles.
func _handle_points(sr: Rect2) -> Array:
	var c := sr.get_center()
	return [["lt", sr.position], ["t", Vector2(c.x, sr.position.y)], ["rt", Vector2(sr.end.x, sr.position.y)],
		["r", Vector2(sr.end.x, c.y)], ["rb", sr.end], ["b", Vector2(c.x, sr.end.y)],
		["lb", Vector2(sr.position.x, sr.end.y)], ["l", Vector2(sr.position.x, c.y)]]


func _canvas_input(event: InputEvent) -> void:
	if _tex == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := _to_img(mb.position)
			_zoom = clampf(_zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.02, 8.0)
			_origin = mb.position - before * _zoom
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
			_drag_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin(mb.position)
			else:
				_end()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "pan":
			_origin += mm.position - _drag_mouse
			_drag_mouse = mm.position
			_canvas.queue_redraw()
		elif _drag != "":
			_move(mm.position)


func _begin(pos: Vector2) -> void:
	var ip := _to_img(pos)
	if _sel >= 0 and _sel < panels.size():
		var r: Rect2i = panels[_sel]["inner"]
		var sr := Rect2(_to_screen(Vector2(r.position)), Vector2(r.size) * _zoom)
		for hp in _handle_points(sr):
			if pos.distance_to(hp[1]) <= HANDLE + 3.0:
				_drag = str(hp[0])
				_drag_rect = r
				_drag_img = ip
				return
	for i in range(panels.size() - 1, -1, -1):
		var r2: Rect2i = panels[i]["inner"]
		if Rect2(r2).has_point(ip):
			_sel = i
			_drag = "move"
			_drag_rect = r2
			_drag_img = ip
			_refresh_list()
			return
	_drag = "new"
	_drag_img = ip
	_sel = -1
	panels.append({"code": _next_free_code(), "inner": Rect2i(Vector2i(ip), Vector2i(1, 1))})
	_sel = panels.size() - 1
	_drag_rect = panels[_sel]["inner"]
	_refresh_list()


func _next_free_code() -> String:
	var used := {}
	for p in panels:
		used[str(p["code"])] = true
	for c in PanelSheet.CODES:
		if not used.has(c):
			return c
	return ""


func _move(pos: Vector2) -> void:
	if _sel < 0 or _sel >= panels.size():
		return
	var ip := _to_img(pos)
	var d := Vector2i((ip - _drag_img).round())
	var r := _drag_rect
	var W := _img.get_width()
	var H := _img.get_height()
	match _drag:
		"move":
			r.position = Vector2i(clampi(r.position.x + d.x, 0, W - r.size.x), clampi(r.position.y + d.y, 0, H - r.size.y))
		"new":
			var a := Vector2i(_drag_img)
			var b := Vector2i(ip)
			r = Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(b.x - a.x), absi(b.y - a.y)))
		_:
			var x0 := r.position.x
			var y0 := r.position.y
			var x1 := r.end.x
			var y1 := r.end.y
			if _drag.contains("l"):
				x0 = clampi(x0 + d.x, 0, x1 - 8)
			if _drag.contains("r"):
				x1 = clampi(x1 + d.x, x0 + 8, W)
			if _drag.contains("t"):
				y0 = clampi(y0 + d.y, 0, y1 - 8)
			if _drag.contains("b"):
				y1 = clampi(y1 + d.y, y0 + 8, H)
			r = Rect2i(x0, y0, x1 - x0, y1 - y0)
	r = r.intersection(Rect2i(0, 0, W, H))
	panels[_sel]["inner"] = r
	_canvas.queue_redraw()


func _end() -> void:
	if _drag == "new" and _sel >= 0 and _sel < panels.size():
		var r: Rect2i = panels[_sel]["inner"]
		if r.size.x < 40 or r.size.y < 40:
			panels.remove_at(_sel)    # a click, not a rectangle
			_sel = -1
	_drag = ""
	_refresh_list()
