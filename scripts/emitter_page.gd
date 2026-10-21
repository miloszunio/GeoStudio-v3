class_name EmitterPage
extends VBoxContainer
## The "Emitery" tab: buttons that add every kind of emitter, the list of emitters with their parameters, and the channels
## that switch them. All edits go straight to the hidden settings (EmitterFlow), so the markers in the 3D view follow at once.

var app
var flow: EmitterFlow
var _list: VBoxContainer
var _channels_box: VBoxContainer
var _editing := false       # our own edit: the settings signal must not rebuild the rows under the user's cursor

## Per-kind parameter rows: [key, label, type, min, max, step, suffix]; keys with a "." are an index into an array (rect.0 ...).
const COMMON_SURFACE := [
	["part", "Bryła (0 = główna)", "int", 0, 20, 1, ""],
	["wall", "Ściana nr (od 1)", "wall", 0, 99, 1, ""],
	["rect.0", "Od początku ściany", "float", 0.0, 100.0, 0.05, " m"],
	["rect.1", "Wysokość dolnej krawędzi", "float", 0.0, 50.0, 0.05, " m"],
	["rect.2", "Szerokość", "float", 0.05, 50.0, 0.05, " m"],
	["rect.3", "Wysokość", "float", 0.05, 50.0, 0.05, " m"],
]
const POS_ROWS := [
	["pos.0", "Położenie X", "float", -500.0, 500.0, 0.1, " m"],
	["pos.1", "Wysokość Y", "float", -50.0, 200.0, 0.1, " m"],
	["pos.2", "Położenie Z", "float", -500.0, 500.0, 0.1, " m"],
]
const AIM_ROWS := [
	["yaw", "Azymut", "float", -360.0, 360.0, 1.0, "°"],
	["pitch", "Nachylenie (+90 = w górę, −90 = w dół)", "float", -90.0, 90.0, 1.0, "°"],
]
const DIR_ROWS := [
	["yaw", "Azymut", "float", -360.0, 360.0, 1.0, "°"],
	["pitch", "Nachylenie (+90 = w górę, −90 = w dół)", "float", -90.0, 90.0, 1.0, "°"],
	["cone", "Kąt stożka", "float", 1.0, 360.0, 1.0, "°"],
]
const PARTICLE_ROWS := [
	["chimney", "Na kominie nr (0 = wolna pozycja)", "int", 0, 50, 1, ""],
	["ps.rate", "Cząstek na sekundę", "float", 0.0, 2000.0, 1.0, ""],
	["ps.max_particles", "Maks. cząstek", "int", 1, 5000, 10, ""],
	["ps.lifetime.0", "Czas życia, min", "float", 0.05, 120.0, 0.1, " s"],
	["ps.lifetime.1", "Czas życia, maks", "float", 0.05, 120.0, 0.1, " s"],
	["ps.speed.0", "Prędkość, min", "float", 0.0, 100.0, 0.1, " m/s"],
	["ps.speed.1", "Prędkość, maks", "float", 0.0, 100.0, 0.1, " m/s"],
	["ps.size.0", "Rozmiar, min", "float", 0.0, 20.0, 0.01, " m"],
	["ps.size.1", "Rozmiar, maks", "float", 0.0, 20.0, 0.01, " m"],
	["ps.cone_angle", "Półkąt stożka", "float", 0.0, 3.14, 0.01, " rad"],
	["ps.growth", "Przyrost rozmiaru", "float", -5.0, 5.0, 0.05, " m/s"],
	["ps.acceleration.1", "Przyspieszenie w pionie (−9,81 = grawitacja)", "float", -50.0, 50.0, 0.05, " m/s²"],
	["ps.drag", "Opór", "float", 0.0, 20.0, 0.05, " 1/s"],
]


func setup(main_scene) -> void:
	app = main_scene
	flow = app.emitters
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#aab6c7"))
	hint.text = "Kanał to nazwane wejście, którym steruje się grupą emiterów (np. kanał „swiatla” zapala wszystkie okna naraz). Silnik decyduje, kiedy i jak go użyć."
	add_child(hint)

	var head := Label.new()
	head.text = "Dodaj emiter"
	head.add_theme_font_size_override("font_size", 15)
	add_child(head)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for k in EmitterFlow.KINDS:
		var b := Button.new()
		b.text = "＋ " + str(k[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.name = "Add_" + str(k[0])
		b.pressed.connect(_add.bind(str(k[0])))
		grid.add_child(b)

	var h2 := Label.new()
	h2.text = "Emitery na modelu"
	h2.add_theme_font_size_override("font_size", 15)
	add_child(h2)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)

	var h3 := Label.new()
	h3.text = "Kanały sterowania"
	h3.add_theme_font_size_override("font_size", 15)
	add_child(h3)
	_channels_box = VBoxContainer.new()
	_channels_box.add_theme_constant_override("separation", 6)
	add_child(_channels_box)

	app.settings.changed.connect(func(key: String) -> void:
		if (key == EmitterFlow.KEY or key == EmitterFlow.KEY_CH) and not _editing:
			refresh())
	refresh()


func _add(kind: String) -> void:
	var arr := flow.list()
	arr.append(flow.default_emitter(kind))
	flow.save(arr)
	refresh()


func refresh() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	var arr := flow.list()
	if arr.is_empty():
		var none := Label.new()
		none.text = "Brak emiterów. Użyj przycisków powyżej."
		none.add_theme_color_override("font_color", Color("#8794a6"))
		_list.add_child(none)
	for i in range(arr.size()):
		_list.add_child(_row(i, arr[i]))
	_refresh_channels()


func _refresh_channels() -> void:
	for ch in _channels_box.get_children():
		_channels_box.remove_child(ch)
		ch.queue_free()
	var chs := flow.channels()
	if chs.is_empty():
		var none := Label.new()
		none.text = "Kanały powstają same, gdy wpiszesz nazwę kanału przy emiterze."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_color_override("font_color", Color("#8794a6"))
		_channels_box.add_child(none)
		return
	for ci in range(chs.size()):
		var c: Dictionary = chs[ci]
		var box := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		box.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var name_l := Label.new()
		name_l.text = str(c["id"])
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_l)
		var type_o := OptionButton.new()
		type_o.add_item("włącz/wyłącz (switch)")
		type_o.add_item("poziom 0…1 (level)")
		type_o.selected = 0 if str(c["type"]) == "switch" else 1
		type_o.item_selected.connect(func(idx: int) -> void: _edit_channel(ci, "type", "switch" if idx == 0 else "level"))
		top.add_child(type_o)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Usuń kanał (emitery zostają, ale wskazują kanał, który znów powstanie)"
		del.pressed.connect(func() -> void:
			var a2 := flow.channels()
			a2.remove_at(ci)
			flow.save_channels(a2)
			_refresh_channels())
		top.add_child(del)
		var g := GridContainer.new()
		g.columns = 2
		v.add_child(g)
		for spec in [["default", "Stan początkowy", 0.0, 1.0, 0.05, ""], ["ramp_up", "Narastanie", 0.0, 3600.0, 0.1, " s"], ["ramp_down", "Opadanie", 0.0, 3600.0, 0.1, " s"]]:
			var lb := Label.new()
			lb.text = str(spec[1])
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(lb)
			var sp := SpinBox.new()
			sp.min_value = float(spec[2])
			sp.max_value = float(spec[3])
			sp.step = float(spec[4])
			sp.suffix = str(spec[5])
			sp.value = float(c[spec[0]])
			sp.value_changed.connect(func(val: float) -> void: _edit_channel(ci, str(spec[0]), val))
			g.add_child(sp)
		_channels_box.add_child(box)


func _edit_channel(ci: int, key: String, value: Variant) -> void:
	var chs := flow.channels()
	if ci >= chs.size():
		return
	chs[ci][key] = value
	_editing = true
	flow.save_channels(chs)
	_editing = false


func _row(i: int, e: Dictionary) -> Control:
	var kind := str(e["kind"])
	var panel := PanelContainer.new()
	panel.name = "Emitter_%d" % i
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = EmitterFlow.kind_label(kind)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("#9fd0ff"))
	top.add_child(title)
	var del := Button.new()
	del.text = "✕"
	del.tooltip_text = "Usuń ten emiter"
	del.pressed.connect(func() -> void:
		var a2 := flow.list()
		a2.remove_at(i)
		flow.save(a2)
		refresh())
	top.add_child(del)

	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	v.add_child(g)
	_text_row(g, i, "id", "Nazwa", str(e["id"]))
	_text_row(g, i, "channel", "Kanał", str(e["channel"]))
	var rows: Array = []
	match kind:
		"light_surface":
			rows = COMMON_SURFACE
		"light_point":
			rows = POS_ROWS + [["range", "Zasięg", "float", 0.1, 1000.0, 0.5, " m"]]
		"light_spot":
			rows = POS_ROWS + DIR_ROWS + [["range", "Zasięg", "float", 0.1, 1000.0, 0.5, " m"]]
		"audio_omni":
			rows = POS_ROWS + [["range", "Zasięg", "float", 0.1, 1000.0, 0.5, " m"]]
		"audio_dir":
			rows = POS_ROWS + DIR_ROWS + [["range", "Zasięg", "float", 0.1, 1000.0, 0.5, " m"]]
		"particle_smoke", "particle_fire", "particle_water", "particle_steam":
			rows = [PARTICLE_ROWS[0]] + POS_ROWS + AIM_ROWS + PARTICLE_ROWS.slice(1)
	for spec in rows:
		_num_row(g, i, e, spec)
	if EmitterFlow.kind_group(kind) == "light":
		var lb := Label.new()
		lb.text = "Kolor po zapaleniu"
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(lb)
		var cp := ColorPickerButton.new()
		cp.color = Color(str(e["colour"]))
		cp.custom_minimum_size = Vector2(80, 26)
		cp.color_changed.connect(func(c: Color) -> void: _edit(i, "colour", "#" + c.to_html(false)))
		g.add_child(cp)
	if EmitterFlow.kind_group(kind) == "light":
		_num_row(g, i, e, ["strength", "Jasność / intensywność", "float", 0.0, 100.0, 0.1, ""])
	return panel


func _text_row(g: GridContainer, i: int, key: String, label: String, value: String) -> void:
	var lb := Label.new()
	lb.text = label
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(lb)
	var le := LineEdit.new()
	le.text = value
	le.custom_minimum_size = Vector2(130, 0)
	le.text_submitted.connect(func(t: String) -> void: _edit(i, key, t.strip_edges(), key == "channel"))
	le.focus_exited.connect(func() -> void: _edit(i, key, le.text.strip_edges(), key == "channel"))
	g.add_child(le)


func _num_row(g: GridContainer, i: int, e: Dictionary, spec: Array) -> void:
	var key := str(spec[0])
	var lb := Label.new()
	lb.text = str(spec[1])
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.add_child(lb)
	var sp := SpinBox.new()
	sp.min_value = float(spec[3])
	sp.max_value = float(spec[4])
	sp.step = float(spec[5])
	sp.suffix = str(spec[6])
	sp.custom_minimum_size = Vector2(130, 0)
	var is_wall := str(spec[2]) == "wall"
	if is_wall:
		sp.min_value = 1
		sp.max_value = maxi(flow.wall_count(int(e["part"])), 1)
		sp.value = int(e["wall"]) + 1
	else:
		sp.value = _num(e, key)
	sp.value_changed.connect(func(val: float) -> void:
		if is_wall:
			_edit(i, "wall", int(val) - 1)
		elif str(spec[2]) == "int":
			_edit(i, key, int(val), key == "part")
		else:
			_edit(i, key, val))
	g.add_child(sp)


## Reads a value by a dotted path ("rect.2", "ps.lifetime.0", "ps.rate").
static func _num(e: Dictionary, key: String) -> float:
	var cur: Variant = e
	for part in key.split("."):
		if typeof(cur) == TYPE_ARRAY:
			cur = (cur as Array)[int(part)]
		elif typeof(cur) == TYPE_DICTIONARY:
			cur = (cur as Dictionary).get(part, 0.0)
	return float(cur)


## Writes a value by a dotted path; returns false when nothing changed.
static func _set_path(e: Dictionary, key: String, value: Variant) -> bool:
	var parts := key.split(".")
	var cur: Variant = e
	for i in range(parts.size() - 1):
		var part := parts[i]
		if typeof(cur) == TYPE_ARRAY:
			cur = (cur as Array)[int(part)]
		else:
			cur = (cur as Dictionary)[part]
	var last := parts[parts.size() - 1]
	if typeof(cur) == TYPE_ARRAY:
		var arr: Array = cur
		if arr[int(last)] == value:
			return false
		arr[int(last)] = value
	else:
		var d: Dictionary = cur
		if d.get(last) == value:
			return false
		d[last] = value
	return true


## Writes one value into emitter i. `rebuild`: the row must be built again (e.g. the wall count depends on the part).
func _edit(i: int, key: String, value: Variant, rebuild := false) -> void:
	var arr := flow.list()
	if i >= arr.size():
		return
	if not _set_path(arr[i], key, value):
		return
	_editing = true
	flow.save(arr)
	_editing = false
	if rebuild:
		refresh()
	else:
		_refresh_channels()
