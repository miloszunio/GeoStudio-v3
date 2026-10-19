class_name SettingsPanel
extends VBoxContainer
## Sidebar generated from AppSettings.tabs / AppSettings.sections, laid out as a work-flow:
##   [ 1 Miejsce | 2 Budynek | 3 Tekstury | 4 Widok | ⚙ Ustawienia ]   <- one row, a step is marked ✓ when done
##   [ search box ]
##   [ heading + one-line instruction of the tab, optional custom header, then the sections ]
##   [ ← Wstecz            Dalej → ]                                    <- always visible, outside the scroll area
## Essential sections ("pinned") are always open; advanced ones are collapsed and open one at a time.
## A value that differs from its default gets a "↺" button that restores it.
## Emits action_pressed(id) for button items and tab_changed(id) when the user picks a tab.

signal action_pressed(action_id: String)
signal tab_changed(tab_id: String)

var settings: AppSettings

var _ctl: Dictionary = {}     # key -> {"kind", "main", "spin", "slider", "values"}
var _rows: Array = []         # [{"row": Control, "text": String, "sec": int, "tab": int}]
var _secs: Array = []         # [{"box", "content", "header", "title", "open", "tab", "single"}]
var _tabs: Array = []         # [{"id", "title", "step", "state", "button", "scroll", "box"}]
var _filter := ""
var _syncing := false
var _current := ""
var _strip: HBoxContainer
var _nav_back: Button
var _nav_next: Button
var _nav_hint: Label
var _stack: MarginContainer
var _file_dialog: FileDialog
var _file_key := ""
var _picker: ImagePicker
var _adv: Dictionary = {}     # tab index -> {"holder": VBoxContainer, "window": Window, "button": Button, "snapshot": Dictionary, "keys": Array}


## custom_pages: tab id -> Control that is placed at the top of that tab's page
## (used for the "start" tab, which holds app-specific widgets instead of settings).
func setup(s: AppSettings, custom_pages: Dictionary = {}) -> void:
	settings = s
	add_theme_constant_override("separation", 8)

	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 3)
	add_child(_strip)

	var search := LineEdit.new()
	search.placeholder_text = "Szukaj ustawienia…"
	search.clear_button_enabled = true
	search.text_changed.connect(set_filter)
	add_child(search)

	_stack = MarginContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_stack)

	var group := ButtonGroup.new()
	for t in settings.tabs:
		var id: String = t["id"]
		var btn := Button.new()
		btn.tooltip_text = str(t.get("heading", ""))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 46)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 13)
		btn.toggle_mode = true
		btn.button_group = group
		btn.theme_type_variation = "TabButton"
		btn.pressed.connect(func() -> void: select_tab(id, true))
		_strip.add_child(btn)

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.visible = false
		_stack.add_child(scroll)
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 2)
		scroll.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		margin.add_child(box)
		var head := Label.new()
		head.text = str(t.get("heading", t["title"]))
		head.add_theme_font_size_override("font_size", 17)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(head)
		var instr := Label.new()
		instr.text = str(t.get("tip", ""))
		instr.add_theme_color_override("font_color", Color("#aab6c7"))
		instr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		instr.visible = instr.text != ""
		box.add_child(instr)
		if custom_pages.has(id):
			box.add_child(custom_pages[id] as Control)
		_tabs.append({"id": id, "title": str(t["title"]), "step": int(t.get("step", 0)), "state": "", "enabled": true,
			"heading": str(t.get("heading", "")), "button": btn,
			"scroll": scroll, "box": box})
		_update_tab_button(_tabs.size() - 1)

	for sec in settings.sections:
		_add_section(sec, bool(sec.get("pinned", false)))
	for ti in _adv.keys():
		_finish_advanced(int(ti))

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	add_child(nav)
	_nav_back = Button.new()
	_nav_back.pressed.connect(func() -> void: _step(-1))
	nav.add_child(_nav_back)
	_nav_hint = Label.new()
	_nav_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_hint.add_theme_font_size_override("font_size", 12)
	_nav_hint.add_theme_color_override("font_color", Color("#8794a6"))
	nav.add_child(_nav_hint)
	_nav_next = Button.new()
	_nav_next.pressed.connect(func() -> void: _step(1))
	nav.add_child(_nav_next)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Wybierz plik"
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	settings.changed.connect(_on_setting_changed)
	settings.options_changed.connect(_fill_choice)
	_refresh_visibility()

	var last := settings.s("ui_last_tab")
	select_tab(last if _tab_index(last) >= 0 else str(_tabs[0]["id"]), false)


# ------------------------------------------------------------------ public helpers

func select_tab(id: String, user := false) -> void:
	var ti := _tab_index(id)
	if ti < 0 or not bool(_tabs[ti].get("enabled", true)):
		return
	for t in _tabs:
		var on: bool = t["id"] == id
		(t["scroll"] as Control).visible = on
		(t["button"] as Button).set_pressed_no_signal(on)
	var changed_now := _current != id
	_current = id
	_update_nav()
	if user:
		settings.set_value("ui_last_tab", id)
		if changed_now:
			tab_changed.emit(id)


## A disabled step cannot be opened (e.g. texturing before a model exists); `why` is shown as its tooltip.
func set_tab_enabled(id: String, enabled: bool, why := "") -> void:
	var i := _tab_index(id)
	if i < 0:
		return
	_tabs[i]["enabled"] = enabled
	var btn := _tabs[i]["button"] as Button
	btn.disabled = not enabled
	btn.tooltip_text = str(_tabs[i].get("heading", "")) if enabled else why
	if not enabled and _current == id:
		select_tab(str(_tabs[0]["id"]), true)
	_update_nav()


func is_tab_enabled(id: String) -> bool:
	var i := _tab_index(id)
	return i >= 0 and bool(_tabs[i].get("enabled", true))


## state: "" (not done yet) | "done" (shows ✓) | "warn" (shows !)
func set_tab_state(id: String, state: String) -> void:
	var i := _tab_index(id)
	if i >= 0 and _tabs[i]["state"] != state:
		_tabs[i]["state"] = state
		_update_tab_button(i)


func tab_state(id: String) -> String:
	var i := _tab_index(id)
	return str(_tabs[i]["state"]) if i >= 0 else ""


## Opens one collapsed section of a tab (and closes the other collapsible ones).
func open_section(section_id: String) -> void:
	for n in range(_secs.size()):
		if _secs[n]["id"] == section_id and bool(_secs[n].get("adv", false)):
			open_advanced(str(_tabs[_secs[n]["tab"]]["id"]))
			return
		if _secs[n]["id"] == section_id and not bool(_secs[n]["single"]):
			_secs[n]["open"] = false
			_toggle_section(n)
			return


func current_tab() -> String:
	return _current


func tab_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _tabs:
		out.append(str(t["id"]))
	return out


func visible_tab_count() -> int:
	var n := 0
	for t in _tabs:
		if (t["button"] as Control).visible:
			n += 1
	return n


## Titles of the sections currently open in a tab (a tab with a single section reports it as open).
func open_sections(tab_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ti := _tab_index(tab_id)
	for s in _secs:
		if s["tab"] == ti and bool(s["open"]) and (not bool(s.get("adv", false)) or advanced_open(tab_id)):
			out.append(str(s["title"]))
	return out


func set_filter(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	_refresh_visibility()


# ------------------------------------------------------------------ building

func _update_tab_button(i: int) -> void:
	var t: Dictionary = _tabs[i]
	var mark := "⚙"
	if int(t["step"]) > 0:
		mark = str(t["step"])
	match str(t["state"]):
		"done":
			mark = "✓"
		"warn":
			mark = "!"
	(t["button"] as Button).text = "%s\n%s" % [mark, t["title"]]
	var col := Color("#6fd08c") if t["state"] == "done" else (Color("#f0b35a") if t["state"] == "warn" else Color("#cfd6e0"))
	(t["button"] as Button).add_theme_color_override("font_color", col)


## Flow tabs only: the neighbours in the work-flow order.
func _flow_ids() -> Array:
	var out := []
	for t in _tabs:
		if int(t["step"]) > 0:
			out.append(t["id"])
	return out


func _step(dir: int) -> void:
	var flow := _flow_ids()
	var i := flow.find(_current)
	if i < 0:
		return
	var j := clampi(i + dir, 0, flow.size() - 1)
	select_tab(str(flow[j]), true)


func _update_nav() -> void:
	if _nav_back == null:
		return
	var flow := _flow_ids()
	var i := flow.find(_current)
	var in_flow := i >= 0
	_nav_back.get_parent().visible = in_flow
	if not in_flow:
		return
	_nav_back.disabled = i == 0
	_nav_back.text = "← " + (str(_tabs[_tab_index(str(flow[i - 1]))]["title"]) if i > 0 else "Wstecz")
	_nav_next.disabled = i == flow.size() - 1 or not is_tab_enabled(str(flow[mini(i + 1, flow.size() - 1)]))
	_nav_next.text = (str(_tabs[_tab_index(str(flow[i + 1]))]["title"]) if i < flow.size() - 1 else "Koniec") + " →"
	_nav_hint.text = "krok %d z %d" % [i + 1, flow.size()]


func _tab_index(id: String) -> int:
	for n in range(_tabs.size()):
		if _tabs[n]["id"] == id:
			return n
	return -1


func _add_section(sec: Dictionary, single: bool) -> void:
	var tab_i := _tab_index(str(sec["tab"]))
	if tab_i < 0:
		push_warning("SettingsPanel: section '%s' points to unknown tab '%s'" % [sec["id"], sec["tab"]])
		return
	var index := _secs.size()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var advanced := bool(sec.get("advanced", false))    # these sections live in the "Zaawansowane" window of the tab
	if advanced:
		single = true
		if not _adv.has(tab_i):
			_adv[tab_i] = {"holder": VBoxContainer.new(), "window": null, "button": null, "snapshot": {}, "keys": []}
			((_adv[tab_i]["holder"]) as VBoxContainer).add_theme_constant_override("separation", 14)
		(_adv[tab_i]["holder"] as Control).add_child(box)
	else:
		(_tabs[tab_i]["box"] as Control).add_child(box)

	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.tooltip_text = str(sec.get("tip", ""))
	header.add_theme_font_size_override("font_size", 15 if single else 14)
	header.flat = single
	header.disabled = single
	if not single:
		header.theme_type_variation = "HeaderButton"
	header.add_theme_color_override("font_disabled_color", Color("#78b7ff"))
	box.add_child(header)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 0 if single else 8)
	box.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	_secs.append({
		"box": box, "content": margin, "header": header, "title": str(sec["title"]),
		"id": str(sec["id"]), "open": single or not bool(sec["collapsed"]), "tab": tab_i, "single": single, "adv": advanced,
	})
	header.pressed.connect(func() -> void: _toggle_section(index))

	var tip_text := str(sec.get("tip", ""))
	if tip_text != "":
		var hint := Label.new()
		hint.text = tip_text
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color("#8794a6"))
		content.add_child(hint)

	for d in sec["items"]:
		if bool(d.get("hidden", false)):
			continue
		var row := _add_item(content, d)
		if advanced and str(d["type"]) != "button":
			(_adv[tab_i]["keys"] as Array).append(str(d["key"]))
		var text := (str(d["label"]) + " " + str(d.get("tip", ""))).to_lower()
		_rows.append({"row": row, "text": text, "sec": index, "tab": tab_i})

	var reset := Button.new()
	reset.text = "↺ Przywróć domyślne tej sekcji"
	reset.visible = advanced
	reset.theme_type_variation = "HeaderButton"
	reset.alignment = HORIZONTAL_ALIGNMENT_LEFT
	reset.add_theme_font_size_override("font_size", 12)
	var sec_id: String = sec["id"]
	reset.pressed.connect(func() -> void: settings.reset_section(sec_id))
	content.add_child(reset)


## Button on the tab's page + the window that holds its advanced sections.
func _finish_advanced(tab_i: int) -> void:
	var a: Dictionary = _adv[tab_i]
	var btn := Button.new()
	btn.text = "⚙  Zaawansowane…"
	btn.custom_minimum_size.y = 40
	btn.tooltip_text = "Rzadziej używane ustawienia tej karty w osobnym oknie (Zapisz / Anuluj)."
	btn.pressed.connect(func() -> void: open_advanced(str(_tabs[tab_i]["id"])))
	(_tabs[tab_i]["box"] as Control).add_child(btn)
	a["button"] = btn

	var win := Window.new()
	win.title = "Zaawansowane – " + str(_tabs[tab_i]["title"])
	win.size = Vector2i(640, 720)
	win.min_size = Vector2i(420, 360)
	win.transient = true
	win.visible = false
	win.close_requested.connect(func() -> void: cancel_advanced(str(_tabs[tab_i]["id"])))
	win.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			cancel_advanced(str(_tabs[tab_i]["id"])))
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	m.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("margin_right", 10)
	scroll.add_child(inner)
	(a["holder"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(a["holder"] as Control)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.custom_minimum_size = Vector2(130, 38)
	cancel.pressed.connect(func() -> void: cancel_advanced(str(_tabs[tab_i]["id"])))
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Zapisz"
	save.theme_type_variation = "PrimaryButton"
	save.custom_minimum_size = Vector2(130, 38)
	save.pressed.connect(func() -> void: save_advanced(str(_tabs[tab_i]["id"])))
	row.add_child(save)
	add_child(win)
	a["window"] = win


func has_advanced(tab_id: String) -> bool:
	return _adv.has(_tab_index(tab_id))


func advanced_open(tab_id: String) -> bool:
	var ti := _tab_index(tab_id)
	return _adv.has(ti) and (_adv[ti]["window"] as Window).visible


## Opens the window and remembers the current values, so Anuluj can restore them.
func open_advanced(tab_id: String) -> void:
	var ti := _tab_index(tab_id)
	if not _adv.has(ti):
		return
	var a: Dictionary = _adv[ti]
	var snap := {}
	for k in a["keys"]:
		snap[k] = settings.values.get(k)
	a["snapshot"] = snap
	(a["window"] as Window).popup_centered()


## Zapisz: the values are already in use (they applied while editing); this makes them permanent.
func save_advanced(tab_id: String) -> void:
	var ti := _tab_index(tab_id)
	if not _adv.has(ti):
		return
	settings.save()
	(_adv[ti]["window"] as Window).hide()


## Anuluj (also Esc and the window's X): puts the values back as they were when the window opened.
func cancel_advanced(tab_id: String) -> void:
	var ti := _tab_index(tab_id)
	if not _adv.has(ti):
		return
	var a: Dictionary = _adv[ti]
	var snap: Dictionary = a["snapshot"]
	for k in snap.keys():
		if settings.values.get(k) != snap[k]:
			settings.set_value(k, snap[k])
	(a["window"] as Window).hide()


## Accordion: opening a section closes the other sections of the same tab.
func _toggle_section(index: int) -> void:
	var now_open: bool = not bool(_secs[index]["open"])
	_secs[index]["open"] = now_open
	if now_open:
		for n in range(_secs.size()):
			if n != index and _secs[n]["tab"] == _secs[index]["tab"] and not bool(_secs[n]["single"]):
				_secs[n]["open"] = false
	_refresh_visibility()


func _label(text: String, tip: String) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _add_item(parent: Control, d: Dictionary) -> Control:
	var key: String = d["key"]
	var kind: String = d["type"]
	var tip: String = str(d.get("tip", ""))
	var text: String = d["label"]
	var current: Variant = settings.values.get(key)

	if kind == "button":
		var btn := Button.new()
		btn.text = text
		btn.tooltip_text = tip
		btn.pressed.connect(func() -> void: action_pressed.emit(key))
		parent.add_child(btn)
		return btn

	if kind == "bool":
		var cbrow := HBoxContainer.new()
		parent.add_child(cbrow)
		var cb := CheckBox.new()
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.text = text
		cb.tooltip_text = tip
		cb.button_pressed = bool(current)
		cb.toggled.connect(func(on: bool) -> void: _user_set(key, on))
		cbrow.add_child(cb)
		_ctl[key] = {"kind": kind, "main": cb}
		cbrow.add_child(_make_reset(key))
		return cbrow

	if kind == "color":
		var hb := HBoxContainer.new()
		parent.add_child(hb)
		var l := _label(text, tip)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(64, 26)
		cp.edit_alpha = false
		cp.color = Color.html(str(current))
		cp.tooltip_text = tip
		cp.color_changed.connect(func(col: Color) -> void: _user_set(key, col))
		hb.add_child(cp)
		_ctl[key] = {"kind": kind, "main": cp}
		hb.add_child(_make_reset(key))
		return hb

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	var lrow := HBoxContainer.new()
	row.add_child(lrow)
	var lab := _label(text, tip)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(lab)

	match kind:
		"float", "int":
			var hb2 := HBoxContainer.new()
			hb2.add_theme_constant_override("separation", 8)
			row.add_child(hb2)
			var has_range: bool = d.has("min") and d.has("max")
			var step: float = float(d.get("step", 1.0 if kind == "int" else 0.1))
			var slider: HSlider = null
			if has_range and bool(d.get("slider", true)):
				slider = HSlider.new()
				slider.min_value = float(d["min"])
				slider.max_value = float(d["max"])
				slider.step = step
				slider.value = float(current)
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				slider.custom_minimum_size.x = 70
				slider.tooltip_text = tip
				slider.value_changed.connect(func(val: float) -> void: _user_set(key, val))
				hb2.add_child(slider)
			var spin := SpinBox.new()
			spin.min_value = float(d.get("min", -1000000.0))
			spin.max_value = float(d.get("max", 1000000.0))
			spin.step = step
			spin.rounded = kind == "int"
			spin.value = float(current)
			spin.suffix = str(d.get("suffix", ""))
			spin.tooltip_text = tip
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL if slider == null else Control.SIZE_SHRINK_END
			# Wide enough for the value plus its unit, otherwise the text field clips the digits.
			spin.custom_minimum_size.x = clampf(78.0 + str(d.get("suffix", "")).length() * 8.0, 112.0, 200.0)
			spin.value_changed.connect(func(val: float) -> void: _user_set(key, val))
			hb2.add_child(spin)
			var entry := {"kind": kind, "spin": spin}
			if slider != null:
				entry["slider"] = slider
			_ctl[key] = entry
		"string":
			var le := LineEdit.new()
			le.text = str(current)
			le.tooltip_text = tip
			le.text_submitted.connect(func(t: String) -> void: _user_set(key, t))
			le.focus_exited.connect(func() -> void: _user_set(key, le.text))
			row.add_child(le)
			_ctl[key] = {"kind": kind, "main": le}
		"path":
			var hb3 := HBoxContainer.new()
			row.add_child(hb3)
			var pe := LineEdit.new()
			pe.text = str(current)
			pe.tooltip_text = tip
			pe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pe.text_submitted.connect(func(t: String) -> void: _user_set(key, t))
			pe.focus_exited.connect(func() -> void: _user_set(key, pe.text))
			hb3.add_child(pe)
			var browse := Button.new()
			var with_picker: bool = bool(settings.defs[key].get("picker", false))
			browse.text = "Wybierz z podglądem…" if with_picker else "…"
			browse.tooltip_text = "Okno z miniaturami i dużym podglądem" if with_picker else ("Wybierz folder" if settings.defs[key].get("dir", false) else "Wybierz plik")
			browse.pressed.connect(func() -> void: _open_file_dialog(key))
			if with_picker:
				row.add_child(browse)
			else:
				hb3.add_child(browse)
			_ctl[key] = {"kind": kind, "main": pe}
		"choice":
			var ob := OptionButton.new()
			ob.tooltip_text = tip
			ob.fit_to_longest_item = false
			ob.clip_text = true
			ob.item_selected.connect(func(idx: int) -> void:
				if _syncing:
					return
				var vals: Array = _ctl[key]["values"]
				if idx >= 0 and idx < vals.size():
					settings.set_value(key, str(vals[idx][0])))
			row.add_child(ob)
			_ctl[key] = {"kind": kind, "main": ob, "values": []}
			_fill_choice(key)
	lrow.add_child(_make_reset(key))
	return row


# ------------------------------------------------------------------ syncing

## Small "↺" button next to a control; visible only while the value differs from the default.
func _make_reset(key: String) -> Button:
	var b := Button.new()
	b.text = "↺"
	b.theme_type_variation = "HeaderButton"
	b.tooltip_text = "Zmieniono względem domyślnej – kliknij, aby przywrócić"
	b.add_theme_color_override("font_color", Color("#ffc46b"))
	b.add_theme_color_override("font_hover_color", Color("#ffc46b"))
	b.pressed.connect(func() -> void: settings.reset_key(key))
	_show_reset(b, not _is_default(key))
	(_ctl[key] as Dictionary)["reset"] = b
	return b


## The button always keeps its place (invisible, not clickable) so that rows do not jump when a value changes.
func _show_reset(b: Control, on: bool) -> void:
	b.modulate.a = 1.0 if on else 0.0
	b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _is_default(key: String) -> bool:
	return settings.values.get(key) == settings.defs[key]["default"]


func _update_reset(key: String) -> void:
	if _ctl.has(key) and _ctl[key].has("reset"):
		_show_reset(_ctl[key]["reset"] as Control, not _is_default(key))

func _user_set(key: String, value: Variant) -> void:
	if _syncing:
		return
	settings.set_value(key, value)


func _on_setting_changed(key: String) -> void:
	if not _ctl.has(key):
		return
	_update_reset(key)
	var c: Dictionary = _ctl[key]
	var val: Variant = settings.values.get(key)
	_syncing = true
	match str(c["kind"]):
		"float", "int":
			(c["spin"] as SpinBox).set_value_no_signal(float(val))
			if c.has("slider"):
				(c["slider"] as HSlider).set_value_no_signal(float(val))
		"bool":
			(c["main"] as CheckBox).set_pressed_no_signal(bool(val))
		"string", "path":
			var le := c["main"] as LineEdit
			if le.text != str(val):
				le.text = str(val)
		"color":
			(c["main"] as ColorPickerButton).color = Color.html(str(val))
		"choice":
			_fill_choice(key)
	_syncing = false


func _fill_choice(key: String) -> void:
	if not _ctl.has(key) or str(_ctl[key]["kind"]) != "choice":
		return
	var c: Dictionary = _ctl[key]
	var ob := c["main"] as OptionButton
	var opts: Array = (settings.defs[key].get("options", []) as Array).duplicate(true)
	var cur := settings.s(key)
	var idx := -1
	for n in range(opts.size()):
		if str(opts[n][0]) == cur:
			idx = n
			break
	if idx == -1:
		opts.append([cur, "%s (niedostępne)" % cur])
		idx = opts.size() - 1
	c["values"] = opts
	var was := _syncing
	_syncing = true
	ob.clear()
	ob.get_popup().add_theme_constant_override("icon_max_width", 72)
	ob.add_theme_constant_override("icon_max_width", 40)
	for o in opts:
		if o.size() > 2 and o[2] is Texture2D:
			ob.add_icon_item(o[2], str(o[1]))
		else:
			ob.add_item(str(o[1]))
	ob.select(idx)
	_syncing = was


# ------------------------------------------------------------------ files

func _open_file_dialog(key: String) -> void:
	_file_key = key
	if bool(settings.defs[key].get("picker", false)):
		if _picker == null:
			_picker = ImagePicker.new()
			_picker.picked.connect(_on_file_selected)
			add_child(_picker)
		_picker.open_for(settings.s(key))
		return
	_file_dialog.clear_filters()
	var dir_mode: bool = settings.defs[key].get("dir", false)
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if dir_mode else FileDialog.FILE_MODE_OPEN_FILE
	for flt in settings.defs[key].get("filters", []):
		_file_dialog.add_filter(str(flt))
	var cur := settings.s(key)
	var start := cur if not cur.begins_with("res://") else ProjectSettings.globalize_path(cur)
	if start.get_base_dir() != "":
		_file_dialog.current_dir = start.get_base_dir()
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _file_key == "":
		return
	# Files inside the project become res:// paths so the setting survives moving the project.
	settings.set_value(_file_key, ProjectSettings.localize_path(path))
	_file_key = ""


# ------------------------------------------------------------------ search / visibility

func _refresh_visibility() -> void:
	var sec_counts: Array = []
	for _s in _secs:
		sec_counts.append(0)
	var tab_counts: Array = []
	for _t in _tabs:
		tab_counts.append(0)
	for r in _rows:
		var vis: bool = _filter == "" or str(r["text"]).contains(_filter)
		(r["row"] as Control).visible = vis
		if vis:
			sec_counts[r["sec"]] += 1
			tab_counts[r["tab"]] += 1

	for n in range(_secs.size()):
		var s: Dictionary = _secs[n]
		var any: bool = sec_counts[n] > 0
		var single: bool = s["single"]
		(s["box"] as Control).visible = any
		(s["content"] as Control).visible = any and (single or bool(s["open"]) or _filter != "")
		(s["header"] as Button).text = str(s["title"]) if single else (("▾  " if s["open"] else "▸  ") + str(s["title"]))

	for ti in _adv.keys():
		var n_hits := 0
		for r in _rows:
			if r["tab"] == ti and _secs[r["sec"]].get("adv", false) and (r["row"] as Control).visible:
				n_hits += 1
		(_adv[ti]["button"] as Button).text = "⚙  Zaawansowane…" if _filter == "" else "⚙  Zaawansowane… (pasuje: %d)" % n_hits
		(_adv[ti]["button"] as Button).visible = _filter == "" or n_hits > 0

	# While searching, only tabs with matches stay in the strip; jump to the first one if needed.
	var first_visible := -1
	for n in range(_tabs.size()):
		var show_tab: bool = _filter == "" or tab_counts[n] > 0
		(_tabs[n]["button"] as Control).visible = show_tab
		if show_tab and first_visible < 0:
			first_visible = n
	if _filter != "" and _current != "":
		var cur_i := _tab_index(_current)
		if cur_i >= 0 and not (_tabs[cur_i]["button"] as Control).visible and first_visible >= 0:
			select_tab(str(_tabs[first_visible]["id"]), false)
