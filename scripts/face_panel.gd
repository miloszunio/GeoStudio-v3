class_name FacePanel
extends PanelContainer
## Floating WYSIWYG panel in the 3D view, opened by clicking a surface of the model.
## Every control writes to the FaceStore and the model is rebuilt at once, so the change is seen
## on the surface itself. Tabs: Mapowanie (move / scale / turn / mirror the picture), Kawałek (other
## picture, or a piece of it repeated over the surface), Materiał (colour, gloss, relief),
## Bryła (raise or lower eaves and ridge of the building part the surface belongs to).

signal closed
signal open_editor

var faces: FaceStore
var host: Node                      # main: nudge_part(), set_part_heights()
var fid := ""
var info: Dictionary = {}

var _title: Label
var _tabs: TabContainer
var _rows: Array = []               # {sl, val, get, fmt, axis}
var _syncing := false
var _link_scale: CheckBox
var _region: OptionButton
var _tint: ColorPickerButton
var _flip: Array[CheckBox] = []
var _undo_btn: Button
var _redo_btn: Button
var _hint_tex: Label
var _roof_label: Label
var _wall_label: Label
var _normal_row: Control
var _inputs_tex: Array[Control] = []     # disabled when the model has no texture
var _preview: FacePreview
var _light: CheckBox
var _editor_btn: Button


func setup(store: FaceStore, main_node: Node) -> void:
	faces = store
	host = main_node
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.15, 0.94)
	sb.border_color = Color("#3d6aa8")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 15)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Zamknij (kliknięcie w puste miejsce też odznacza)"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)

	_preview = FacePreview.new()
	root.add_child(_preview)
	_editor_btn = Button.new()
	_editor_btn.text = "Edytor mapowania – całe okno…"
	_editor_btn.tooltip_text = "Duży podgląd obrazu z ramką wycinka (krawędzie i narożniki) oraz prostowanie zdjęcia."
	_editor_btn.pressed.connect(func() -> void: open_editor.emit())
	root.add_child(_editor_btn)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	# ---- Mapowanie
	var map := _page("Mapowanie")
	_hint_tex = Label.new()
	_hint_tex.text = "Ten model nie ma tekstury – mapowanie dotyczy tylko powierzchni z obrazem."
	_hint_tex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_tex.add_theme_color_override("font_color", Color("#e0b060"))
	map.add_child(_hint_tex)
	_row(map, "Przesuń ◀ ▶", -4.0, 4.0, 0.01, "%.2f m", func() -> float: return _arr("off", 0), func(v: float) -> void: _set_pair("off", 0, v), 0.0, "x")
	_row(map, "Przesuń ▲ ▼", -4.0, 4.0, 0.01, "%.2f m", func() -> float: return _arr("off", 1), func(v: float) -> void: _set_pair("off", 1, v), 0.0, "y")
	_row(map, "Skala szer.", 10.0, 400.0, 1.0, "%d %%", func() -> float: return _arr("scale", 0) * 100.0, func(v: float) -> void: _set_scale(0, v / 100.0), 5.0)
	_row(map, "Skala wys.", 10.0, 400.0, 1.0, "%d %%", func() -> float: return _arr("scale", 1) * 100.0, func(v: float) -> void: _set_scale(1, v / 100.0), 5.0)
	_link_scale = CheckBox.new()
	_link_scale.text = "Skala szerokości i wysokości razem"
	_link_scale.button_pressed = false
	map.add_child(_link_scale)
	_row(map, "Obrót", -180.0, 180.0, 1.0, "%d°", func() -> float: return float(faces.get_value(fid, "rot")), func(v: float) -> void: faces.set_field(fid, "rot", v), 15.0)
	var flips := HBoxContainer.new()
	map.add_child(flips)
	for ax in range(2):
		var cb := CheckBox.new()
		cb.text = "Odbij poziomo" if ax == 0 else "Odbij pionowo"
		cb.toggled.connect(func(on: bool) -> void:
			if _syncing:
				return
			var cur: Array = (faces.get_value(fid, "flip") as Array).duplicate()
			cur[ax] = on
			faces.set_field(fid, "flip", cur))
		flips.add_child(cb)
		_flip.append(cb)
	var rbtn := Button.new()
	rbtn.text = "Zeruj mapowanie tej powierzchni"
	rbtn.pressed.connect(func() -> void: faces.reset_face(fid, FaceStore.MAPPING_FIELDS))
	map.add_child(rbtn)

	# ---- Kawałek
	var piece := _page("Kawałek")
	var hl := Label.new()
	hl.text = "Weź inne zdjęcie albo wytnij z niego kawałek – zostanie powielony na całej powierzchni."
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.add_theme_color_override("font_color", Color("#aab6c7"))
	piece.add_child(hl)
	_region = OptionButton.new()
	_region.item_selected.connect(func(i: int) -> void:
		if _syncing:
			return
		faces.set_field(fid, "region", "" if i == 0 else _region.get_item_text(i)))
	piece.add_child(_region)
	for pair in [["Utnij z lewej", 0], ["Utnij z góry", 1], ["Utnij z prawej", 2], ["Utnij z dołu", 3]]:
		var idx: int = pair[1]
		_row(piece, pair[0], 0.0, 95.0, 1.0, "%d %%", func() -> float: return _crop_trim(idx), func(v: float) -> void: _set_crop_trim(idx, v), 5.0)
	var whole := Button.new()
	whole.text = "Cały obraz"
	whole.pressed.connect(func() -> void: faces.reset_face(fid, ["crop", "region"]))
	piece.add_child(whole)

	# ---- Materiał
	var mat := _page("Materiał")
	var trow := HBoxContainer.new()
	mat.add_child(trow)
	var tl := Label.new()
	tl.text = "Kolor (diffuse)"
	tl.custom_minimum_size.x = 104
	trow.add_child(tl)
	_tint = ColorPickerButton.new()
	_tint.edit_alpha = false
	_tint.custom_minimum_size = Vector2(120, 28)
	_tint.tooltip_text = "Mnoży się z kolorem zdjęcia: biały = bez zmian, ciemniejszy = przyciemnia, kolor = zabarwia."
	_tint.color_changed.connect(func(c: Color) -> void:
		if not _syncing:
			faces.set_field(fid, "tint", "#" + c.to_html(false)))
	trow.add_child(_tint)
	_row(mat, "Chropowatość", 0.0, 1.0, 0.01, "%.2f", func() -> float: return _mat("rough"), func(v: float) -> void: faces.set_field(fid, "rough", v), 0.05)
	_row(mat, "Połysk (specular)", 0.0, 1.0, 0.01, "%.2f", func() -> float: return _mat("spec"), func(v: float) -> void: faces.set_field(fid, "spec", v), 0.05)
	_row(mat, "Metaliczność", 0.0, 1.0, 0.01, "%.2f", func() -> float: return _mat("metal"), func(v: float) -> void: faces.set_field(fid, "metal", v), 0.05)
	_row(mat, "Relief (normal)", 0.0, 3.0, 0.05, "%.2f", func() -> float: return _mat("normal"), func(v: float) -> void: faces.set_field(fid, "normal", v), 0.1)
	_light = CheckBox.new()
	_light.text = "Część świecąca (emissive_light)"
	_light.tooltip_text = "Powierzchnia trafi do eksportu jako osobny węzeł z metadaną emissive_light = true (np. okna, lampy); w podglądzie świeci."
	_light.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			faces.set_field(fid, "light", on))
	mat.add_child(_light)
	var mreset := Button.new()
	mreset.text = "Domyślny materiał tej powierzchni"
	mreset.pressed.connect(func() -> void: faces.reset_face(fid, FaceStore.MATERIAL_FIELDS))
	mat.add_child(mreset)

	# ---- Bryła
	var body := _page("Bryła")
	var bl := Label.new()
	bl.text = "Wysokości całej bryły (części budynku), do której należy ta powierzchnia."
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.add_theme_color_override("font_color", Color("#aab6c7"))
	body.add_child(bl)
	_wall_label = Label.new()
	body.add_child(_wall_label)
	body.add_child(_nudge_row("Okap + dach w górę / w dół", 1.0, 0.0))
	_roof_label = Label.new()
	body.add_child(_roof_label)
	body.add_child(_nudge_row("Kalenica wyżej / niżej", 0.0, 1.0))
	body.add_child(_nudge_row("Ściany niżej, dach wyżej (przesuń okap)", 0.0, 0.0, true))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	root.add_child(foot)
	_undo_btn = Button.new()
	_undo_btn.text = "↶ Cofnij"
	_undo_btn.tooltip_text = "Ctrl+Z"
	_undo_btn.pressed.connect(func() -> void: faces.undo())
	foot.add_child(_undo_btn)
	_redo_btn = Button.new()
	_redo_btn.text = "↷ Ponów"
	_redo_btn.tooltip_text = "Ctrl+Y"
	_redo_btn.pressed.connect(func() -> void: faces.redo())
	foot.add_child(_redo_btn)
	var all := Button.new()
	all.text = "Zeruj wszystko"
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all.pressed.connect(func() -> void: faces.reset_face(fid))
	foot.add_child(all)
	faces.changed.connect(func(_i: String) -> void: _update_undo())


func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	sc.add_child(box)
	return box


## One labelled slider with ◀ ▶ buttons. Shift = ten times bigger steps. `axis` ("x"/"y") makes the
## range follow the size of the surface.
func _row(parent: Control, text: String, mn: float, mx: float, step: float, fmt: String, getter: Callable, setter: Callable, nudge := 0.0, axis := "") -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size.x = 104
	box.add_child(lab)
	var minus := Button.new()
	minus.text = "◀"
	box.add_child(minus)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.x = 80
	box.add_child(sl)
	var plus := Button.new()
	plus.text = "▶"
	box.add_child(plus)
	var val := Label.new()
	val.custom_minimum_size.x = 62
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(val)
	var n := nudge if nudge > 0.0 else step * 5.0
	minus.pressed.connect(func() -> void: _bump(sl, -n))
	plus.pressed.connect(func() -> void: _bump(sl, n))
	sl.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		if not _syncing:
			setter.call(v))
	_rows.append({"sl": sl, "val": val, "get": getter, "fmt": fmt, "axis": axis, "box": box})
	if parent.get_parent() != null and parent.get_parent().name in ["Mapowanie", "Kawałek"]:
		_inputs_tex.append(box)


func _bump(sl: HSlider, d: float) -> void:
	var k := 10.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	sl.value = clampf(sl.value + d * k, sl.min_value, sl.max_value)


func _nudge_row(text: String, dw: float, dr: float, eaves := false) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.text = text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lab)
	for pair in [["−1 dm", -0.1], ["+1 dm", 0.1]]:
		var b := Button.new()
		b.text = pair[0]
		var d: float = pair[1]
		b.pressed.connect(func() -> void:
			var k := 5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			if eaves:
				host.nudge_part(int(info.get("part", 0)), -d * k, d * k)   # eaves move, ridge stays where it is
			else:
				host.nudge_part(int(info.get("part", 0)), dw * d * k, dr * d * k))
		box.add_child(b)
	return box


# ------------------------------------------------------------------ values

func _arr(field: String, i: int) -> float:
	return float((faces.get_value(fid, field) as Array)[i])


func _set_pair(field: String, i: int, v: float) -> void:
	var cur: Array = (faces.get_value(fid, field) as Array).duplicate()
	cur[i] = snappedf(v, 0.001)
	faces.set_field(fid, field, cur)


func _set_scale(i: int, v: float) -> void:
	var cur: Array = (faces.get_value(fid, "scale") as Array).duplicate()
	cur[i] = v
	if _link_scale.button_pressed:
		cur[1 - i] = v
	faces.set_field(fid, "scale", cur)


func _mat(field: String) -> float:
	var v: float = faces.get_value(fid, field)
	return v if v >= 0.0 else float((info.get("defaults", {}) as Dictionary).get(field, 0.0))


func _crop_trim(i: int) -> float:
	var r: Array = faces.get_value(fid, "crop")
	match i:
		0: return r[0] * 100.0
		1: return r[1] * 100.0
		2: return (1.0 - r[0] - r[2]) * 100.0
		_: return (1.0 - r[1] - r[3]) * 100.0


func _set_crop_trim(i: int, pct: float) -> void:
	var r: Array = faces.get_value(fid, "crop")
	var l: float = r[0]
	var t: float = r[1]
	var rr: float = 1.0 - r[0] - r[2]
	var b: float = 1.0 - r[1] - r[3]
	var v := pct / 100.0
	match i:
		0: l = minf(v, 0.95 - rr)
		1: t = minf(v, 0.95 - b)
		2: rr = minf(v, 0.95 - l)
		_: b = minf(v, 0.95 - t)
	faces.set_field(fid, "crop", [l, t, 1.0 - l - rr, 1.0 - t - b])


# ------------------------------------------------------------------ showing

func show_face(id: String, face_info: Dictionary) -> void:
	fid = id
	info = face_info
	visible = true
	_title.text = str(info.get("title", id))
	var sz: Vector2 = info.get("size", Vector2(4, 3))
	_syncing = true       # changing a slider's range re-snaps its value: that is not a user edit
	for r in _rows:
		if r["axis"] == "x":
			(r["sl"] as HSlider).max_value = maxf(sz.x, 1.0)
			(r["sl"] as HSlider).min_value = -maxf(sz.x, 1.0)
		elif r["axis"] == "y":
			(r["sl"] as HSlider).max_value = maxf(sz.y, 1.0)
			(r["sl"] as HSlider).min_value = -maxf(sz.y, 1.0)
	_syncing = false
	_region.clear()
	_region.add_item("(automatycznie)")
	for k in info.get("regions", []):
		_region.add_item(str(k))
	sync()


## New data about the same surface (the model was rebuilt): refreshes values and preview only.
func update_info(face_info: Dictionary) -> void:
	info = face_info
	sync()


## Re-reads every value from the store (after undo, or after the model was rebuilt).
func sync() -> void:
	if fid == "":
		return
	_syncing = true
	for r in _rows:
		var v: float = (r["get"] as Callable).call()
		(r["sl"] as HSlider).set_value_no_signal(v)
		(r["val"] as Label).text = (r["fmt"] as String) % v
	var fl: Array = faces.get_value(fid, "flip")
	for i in range(2):
		_flip[i].set_pressed_no_signal(bool(fl[i]))
	var want: String = faces.get_value(fid, "region")
	_region.select(0)
	for i in range(1, _region.item_count):
		if _region.get_item_text(i) == want:
			_region.select(i)
	_tint.color = Color.html(str(faces.get_value(fid, "tint")))
	_light.set_pressed_no_signal(bool(faces.get_value(fid, "light")))
	var pv: Dictionary = info.get("preview", {})
	_preview.set_data(pv.get("tex", null), pv.get("poly", PackedVector2Array()), str(pv.get("message", "")), pv.get("openings", []))
	var textured: bool = bool(info.get("textured", false))
	_hint_tex.visible = not textured
	_editor_btn.disabled = not textured
	for c in _inputs_tex:
		_set_disabled(c, not textured)
	_region.disabled = not textured
	_wall_label.text = "Okap (wysokość ścian): %.2f m" % float(info.get("wall_h", 0.0))
	_roof_label.text = "Kalenica (wysokość dachu): %.2f m" % float(info.get("roof_h", 0.0))
	_syncing = false
	_update_undo()


func _set_disabled(c: Node, off: bool) -> void:
	if c is BaseButton:
		(c as BaseButton).disabled = off
	elif c is Slider:
		(c as Slider).editable = not off
	for ch in c.get_children():
		_set_disabled(ch, off)


func _update_undo() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = not faces.can_undo()
		_redo_btn.disabled = not faces.can_redo()
