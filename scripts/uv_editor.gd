class_name UvEditor
extends VBoxContainer
## Full-window mapping editor (like the Unwrap UVW window in 3ds Max) for ONE surface.
##   Wycinek      - the picture is shown whole; the frame is the piece laid on the surface. Drag a corner or an edge
##                  of the frame (or the whole frame); the model behind the window follows at once.
##   Prostowanie  - four corners are put on a photographed wall; "Prostuj" cuts them out as a flat picture
##                  (perspective removed) and the surface uses it.
## Zapisz keeps what was done, Anuluj puts the surface back as it was when the window opened.

signal finished(saved: bool)

const HANDLE := 9.0
const MIN_FRAC := 0.03
const APPLY_GAP_MSEC := 90

var atlas: TextureAtlas
var faces: FaceStore
var fid := ""
var host: Object                  # the MappingFlow: add_rectified(name, img, meta) -> String, px_per_m()
var info: Dictionary = {}

var mode := "crop"
var region_key := ""
var crop := Rect2(0, 0, 1, 1)     # fraction of the picture: x, y, w, h
var quad := PackedVector2Array()  # in picture pixels, TL TR BR BL
var _snapshot := {}

var _canvas: Control
var _picker: OptionButton
var _mode_crop: Button
var _mode_rect: Button
var _out_w: SpinBox
var _out_h: SpinBox
var _rect_row: Control
var _status: Label
var _view_scale := 1.0
var _view_off := Vector2.ZERO
var _drag := ""           # "", "pan", "move", "l", "r", "t", "b", "tl", "tr", "bl", "br", "q0".."q3"
var _drag_start := Vector2.ZERO
var _drag_crop := Rect2()
var _drag_quad := PackedVector2Array()
var _last_apply := 0
var _pending := false
var _keys: Array = []


func setup(a: TextureAtlas, store: FaceStore, face_id: String, face_info: Dictionary, host_node: Object) -> void:
	atlas = a
	faces = store
	fid = face_id
	info = face_info
	host = host_node
	_snapshot = {"region": faces.get_value(fid, "region"), "crop": (faces.get_value(fid, "crop") as Array).duplicate()}
	var base: String = str(info.get("base_key", ""))
	region_key = str(faces.get_value(fid, "region"))
	if region_key == "" or not atlas.regions.has(region_key):
		region_key = base
	if region_key == "" or not atlas.regions.has(region_key):
		var ks: Array = atlas.regions.keys()
		ks.sort()
		region_key = str(ks[0]) if not ks.is_empty() else ""
	var c: Array = faces.get_value(fid, "crop")
	crop = Rect2(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	_build()
	_load_image_state()
	_fit()


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	var title := Label.new()
	title.text = str(info.get("title", fid))
	title.add_theme_font_size_override("font_size", 16)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var group := ButtonGroup.new()
	_mode_crop = Button.new()
	_mode_crop.text = "Wycinek"
	_mode_crop.toggle_mode = true
	_mode_crop.button_group = group
	_mode_crop.button_pressed = true
	_mode_crop.pressed.connect(func() -> void: _set_mode("crop"))
	top.add_child(_mode_crop)
	_mode_rect = Button.new()
	_mode_rect.text = "Prostowanie zdjęcia"
	_mode_rect.toggle_mode = true
	_mode_rect.button_group = group
	_mode_rect.pressed.connect(func() -> void: _set_mode("rectify"))
	top.add_child(_mode_rect)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var l := Label.new()
	l.text = "Obraz:"
	bar.add_child(l)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.x = 260
	_keys = atlas.regions.keys()
	_keys.sort()
	for k in _keys:
		_picker.add_item(str(k))
	_picker.item_selected.connect(_on_pick)
	bar.add_child(_picker)
	var fit := Button.new()
	fit.text = "Dopasuj widok"
	fit.pressed.connect(_fit)
	bar.add_child(fit)
	var whole := Button.new()
	whole.text = "Cały obraz"
	whole.tooltip_text = "Wycinek = cały obraz"
	whole.pressed.connect(func() -> void:
		crop = Rect2(0, 0, 1, 1)
		_apply_now()
		_canvas.queue_redraw())
	bar.add_child(whole)
	_rect_row = HBoxContainer.new()
	_rect_row.add_theme_constant_override("separation", 6)
	bar.add_child(_rect_row)
	var ol := Label.new()
	ol.text = "Wynik (px):"
	_rect_row.add_child(ol)
	_out_w = SpinBox.new()
	_out_w.min_value = 64
	_out_w.max_value = 3000
	_out_w.step = 8
	_rect_row.add_child(_out_w)
	var x := Label.new()
	x.text = "×"
	_rect_row.add_child(x)
	_out_h = SpinBox.new()
	_out_h.min_value = 64
	_out_h.max_value = 3000
	_out_h.step = 8
	_rect_row.add_child(_out_h)
	var go := Button.new()
	go.text = "Prostuj i użyj na tej ścianie"
	go.theme_type_variation = "PrimaryButton"
	go.pressed.connect(rectify_now)
	_rect_row.add_child(go)
	_rect_row.visible = false

	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(400, 300)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_input)
	_canvas.resized.connect(_fit)
	add_child(_canvas)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	add_child(foot)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Color("#aab6c7"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_status)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.custom_minimum_size = Vector2(130, 38)
	cancel.pressed.connect(cancel_edit)
	foot.add_child(cancel)
	var save := Button.new()
	save.text = "Zapisz"
	save.theme_type_variation = "PrimaryButton"
	save.custom_minimum_size = Vector2(130, 38)
	save.pressed.connect(save_edit)
	foot.add_child(save)
	_set_mode("crop")


func _set_mode(m: String) -> void:
	mode = m
	_mode_crop.set_pressed_no_signal(m == "crop")
	_mode_rect.set_pressed_no_signal(m == "rectify")
	_rect_row.visible = m == "rectify"
	_status.text = "Przeciągaj narożniki, krawędzie lub całą ramkę. Kółko myszy: zoom, środkowy przycisk: przesuwanie widoku." if m == "crop" else "Ustaw cztery narożniki na ścianie (lewy górny, prawy górny, prawy dolny, lewy dolny), potem „Prostuj”. Zdjęcie źródłowe wybierz na liście."
	if m == "rectify" and quad.size() != 4:
		_default_quad()
	_canvas.queue_redraw()


func _image() -> Image:
	return atlas.regions[region_key]["img"] if atlas.regions.has(region_key) else null


func _load_image_state() -> void:
	var i := _keys.find(region_key)
	if i >= 0:
		_picker.select(i)
	_default_quad()
	_update_out_size()


func _default_quad() -> void:
	var im := _image()
	if im == null:
		return
	var w := float(im.get_width())
	var h := float(im.get_height())
	quad = PackedVector2Array([Vector2(w * 0.1, h * 0.1), Vector2(w * 0.9, h * 0.1), Vector2(w * 0.9, h * 0.9), Vector2(w * 0.1, h * 0.9)])


## Suggested size of the straightened picture: the wall in metres times the scale of the sheet.
func _update_out_size() -> void:
	var size: Vector2 = info.get("size", Vector2(10, 3))
	var ppm := 0.0
	if host != null and host.has_method("px_per_m"):
		ppm = float(host.px_per_m())
	if ppm <= 0.0:
		ppm = 150.0
	var w := size.x * ppm
	var h := size.y * ppm
	var k := minf(1.0, 2048.0 / maxf(w, 1.0))
	_out_w.value = snappedf(w * k, 8.0)
	_out_h.value = snappedf(h * k, 8.0)


func _on_pick(i: int) -> void:
	region_key = str(_keys[i])
	if mode == "crop":
		crop = Rect2(0, 0, 1, 1)
		faces.set_field(fid, "region", region_key)
		faces.set_field(fid, "crop", [0.0, 0.0, 1.0, 1.0])
	_default_quad()
	_fit()


# ------------------------------------------------------------------ view

func _fit() -> void:
	var im := _image()
	if im == null or _canvas == null:
		return
	var area := _canvas.size
	if area.x < 10.0 or area.y < 10.0:
		return
	_view_scale = minf(area.x / float(im.get_width()), area.y / float(im.get_height())) * 0.96
	_view_off = (area - Vector2(im.get_size()) * _view_scale) * 0.5
	_canvas.queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return _view_off + p * _view_scale


func _to_image(p: Vector2) -> Vector2:
	return (p - _view_off) / _view_scale


func _crop_px() -> Rect2:
	var im := _image()
	var s := Vector2(im.get_size())
	return Rect2(crop.position * s, crop.size * s)


func _draw() -> void:
	var im := _image()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#0c0f14"))
	if im == null:
		_canvas.draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Brak obrazu. Wczytaj teksturę w kroku 3.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#aab6c7"))
		return
	var tex: Texture2D = atlas.regions[region_key]["tex"]
	var full := Rect2(_to_screen(Vector2.ZERO), Vector2(im.get_size()) * _view_scale)
	_canvas.draw_texture_rect(tex, full, false)
	if mode == "crop":
		var cr := _crop_px()
		var sr := Rect2(_to_screen(cr.position), cr.size * _view_scale)
		var dim := Color(0, 0, 0, 0.55)
		_canvas.draw_rect(Rect2(full.position, Vector2(full.size.x, sr.position.y - full.position.y)), dim)
		_canvas.draw_rect(Rect2(Vector2(full.position.x, sr.end.y), Vector2(full.size.x, full.end.y - sr.end.y)), dim)
		_canvas.draw_rect(Rect2(Vector2(full.position.x, sr.position.y), Vector2(sr.position.x - full.position.x, sr.size.y)), dim)
		_canvas.draw_rect(Rect2(Vector2(sr.end.x, sr.position.y), Vector2(full.end.x - sr.end.x, sr.size.y)), dim)
		_canvas.draw_rect(sr, Color(1.0, 0.85, 0.2), false, 2.0)
		for hp in _crop_handles(sr).values():
			_canvas.draw_rect(Rect2(hp - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), Color(1.0, 0.85, 0.2))
		_canvas.draw_string(ThemeDB.fallback_font, sr.position + Vector2(4, 16), "%d × %d px" % [int(cr.size.x), int(cr.size.y)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.6))
	else:
		var pts := PackedVector2Array()
		for q in quad:
			pts.append(_to_screen(q))
		if pts.size() == 4:
			var closed := pts.duplicate()
			closed.append(pts[0])
			_canvas.draw_colored_polygon(pts, Color(0.2, 0.8, 1.0, 0.15))
			_canvas.draw_polyline(closed, Color(0.3, 0.85, 1.0), 2.0)
			var names := ["TL", "TR", "BR", "BL"]
			for i in range(4):
				_canvas.draw_circle(pts[i], HANDLE, Color(0.3, 0.85, 1.0))
				_canvas.draw_string(ThemeDB.fallback_font, pts[i] + Vector2(10, -8), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.95, 1.0))


func _crop_handles(sr: Rect2) -> Dictionary:
	var c := sr.get_center()
	return {
		"tl": sr.position, "tr": Vector2(sr.end.x, sr.position.y), "bl": Vector2(sr.position.x, sr.end.y), "br": sr.end,
		"t": Vector2(c.x, sr.position.y), "b": Vector2(c.x, sr.end.y), "l": Vector2(sr.position.x, c.y), "r": Vector2(sr.end.x, c.y),
	}


# ------------------------------------------------------------------ mouse

func _input(event: InputEvent) -> void:
	if _image() == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
			_drag_start = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(mb.position)
			else:
				if _drag != "" and _drag != "pan":
					_apply_now()
				_drag = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "pan":
			_view_off += mm.relative
			_canvas.queue_redraw()
		elif _drag != "":
			_move_drag(mm.position)


func _zoom(at: Vector2, k: float) -> void:
	var before := _to_image(at)
	_view_scale = clampf(_view_scale * k, 0.02, 40.0)
	_view_off = at - before * _view_scale
	_canvas.queue_redraw()


func _begin_drag(p: Vector2) -> void:
	_drag_start = _to_image(p)
	_drag = ""
	if mode == "crop":
		var cr := _crop_px()
		var sr := Rect2(_to_screen(cr.position), cr.size * _view_scale)
		var hs := _crop_handles(sr)
		for k in ["tl", "tr", "bl", "br", "t", "b", "l", "r"]:
			if (hs[k] as Vector2).distance_to(p) <= HANDLE + 4.0:
				_drag = k
				break
		if _drag == "":
			var near := 7.0
			if absf(p.x - sr.position.x) < near and p.y > sr.position.y and p.y < sr.end.y:
				_drag = "l"
			elif absf(p.x - sr.end.x) < near and p.y > sr.position.y and p.y < sr.end.y:
				_drag = "r"
			elif absf(p.y - sr.position.y) < near and p.x > sr.position.x and p.x < sr.end.x:
				_drag = "t"
			elif absf(p.y - sr.end.y) < near and p.x > sr.position.x and p.x < sr.end.x:
				_drag = "b"
			elif sr.has_point(p):
				_drag = "move"
		_drag_crop = crop
	else:
		for i in range(quad.size()):
			if _to_screen(quad[i]).distance_to(p) <= HANDLE + 5.0:
				_drag = "q%d" % i
				break
		_drag_quad = quad.duplicate()


func _move_drag(p: Vector2) -> void:
	var im := _image()
	var s := Vector2(im.get_size())
	var d := (_to_image(p) - _drag_start)
	if mode == "crop":
		var df := d / s
		var r := _drag_crop
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		if _drag == "move":
			var nx := clampf(x0 + df.x, 0.0, 1.0 - r.size.x)
			var ny := clampf(y0 + df.y, 0.0, 1.0 - r.size.y)
			x1 = nx + r.size.x
			y1 = ny + r.size.y
			x0 = nx
			y0 = ny
		else:
			if _drag.contains("l"):
				x0 = clampf(x0 + df.x, 0.0, x1 - MIN_FRAC)
			if _drag.contains("r"):
				x1 = clampf(x1 + df.x, x0 + MIN_FRAC, 1.0)
			if _drag.contains("t"):
				y0 = clampf(y0 + df.y, 0.0, y1 - MIN_FRAC)
			if _drag.contains("b"):
				y1 = clampf(y1 + df.y, y0 + MIN_FRAC, 1.0)
		crop = Rect2(x0, y0, x1 - x0, y1 - y0)
		_apply_throttled()
	elif _drag.begins_with("q"):
		var i := int(_drag.substr(1))
		var np := (_drag_quad[i] + d).clamp(Vector2.ZERO, s)
		quad[i] = np
	_canvas.queue_redraw()


## The model behind the window follows the frame, at most every ~90 ms.
func _apply_throttled() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_apply >= APPLY_GAP_MSEC or not is_inside_tree():
		_apply_now()
	else:
		_pending = true
		get_tree().create_timer(APPLY_GAP_MSEC / 1000.0).timeout.connect(func() -> void:
			if _pending:
				_apply_now())


func _apply_now() -> void:
	_pending = false
	_last_apply = Time.get_ticks_msec()
	if region_key != "":
		faces.set_field(fid, "region", region_key)
	faces.set_field(fid, "crop", [snappedf(crop.position.x, 0.0001), snappedf(crop.position.y, 0.0001), snappedf(crop.size.x, 0.0001), snappedf(crop.size.y, 0.0001)])


# ------------------------------------------------------------------ rectify / finish

## Cuts the quad out of the picture as a flat image and gives it to the surface.
func rectify_now() -> bool:
	var im := _image()
	if im == null or quad.size() != 4:
		return false
	var out := Rectify.warp(im, Array(quad), int(_out_w.value), int(_out_h.value))
	if out == null:
		_status.text = "Narożniki są ustawione nieprawidłowo (czworokąt zdegenerowany)."
		return false
	var meta := {"source": region_key, "quad": [[quad[0].x, quad[0].y], [quad[1].x, quad[1].y], [quad[2].x, quad[2].y], [quad[3].x, quad[3].y]], "face": fid}
	var key: String = host.add_rectified("rect_%s" % fid.replace(":", "_"), out, meta)
	_keys = atlas.regions.keys()
	_keys.sort()
	_picker.clear()
	for k in _keys:
		_picker.add_item(str(k))
	region_key = key
	crop = Rect2(0, 0, 1, 1)
	_picker.select(_keys.find(key))
	_apply_now()
	_set_mode("crop")
	_fit()
	_status.text = "Zapisano wyprostowany obraz „%s” i ustawiono go na tej powierzchni." % key
	return true


func save_edit() -> void:
	_apply_now()
	finished.emit(true)


func cancel_edit() -> void:
	faces.set_field(fid, "region", _snapshot["region"])
	faces.set_field(fid, "crop", _snapshot["crop"])
	finished.emit(false)
