class_name GptFlow
extends RefCounted
## Everything about the ChatGPT round trip: the prompt window, the paste window for the JSON answer, applying the description (materials, openings) to the model, and the data the export takes from it.

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


var describe: Dictionary = {}     # GptDescribe data (validated), applied to the surfaces of the sheet


## Data for GptPrompt from the built model (sizes in metres) and the EGiB attributes.
func gpt_info() -> Dictionary:
	var info = {"name": app.project.project_name() if app.project.is_open() else "", "place": "", "floors": app.current_floors,
		"kind": "", "roof": "gable", "main": {}, "annexes": []}
	var ll = GeoportalClient.e2180_to_lonlat(app.map_center.x, app.map_center.y)
	info["place"] = "%.5f N, %.5f E" % [ll.y, ll.x]
	if app.place.edit != null and app.place.edit.text.strip_edges() != "":
		info["place"] = "%s (%s)" % [app.place.edit.text.strip_edges(), info["place"]]
	for a in app.current_attrs:
		for k in (a as Dictionary).keys():
			if str(k).to_lower().begins_with("rodzaj") and info["kind"] == "":
				info["kind"] = str(a[k])
	for P in app.last_rt:
		var bb: Rect2 = P["bb"]
		var along_x: bool = P["ridge_along_x"]
		var len_m := bb.size.x if along_x else bb.size.y
		var wid_m := bb.size.y if along_x else bb.size.x
		if int(P["index"]) == 0:
			info["roof"] = str(P["roof_kind"])
			info["main"] = {"len": len_m, "wid": wid_m, "wall_h": P["wall_h"], "roof_h": P["roof_h"]}
		else:
			(info["annexes"] as Array).append({"len": maxf(bb.size.x, bb.size.y), "wall_h": P["wall_h"]})
	return info


func _show_gpt_prompt() -> void:
	if app.last_rt.is_empty() or app.current_ring.is_empty():
		app._set_status("Najpierw zbuduj model (krok 1) – prompt używa wymiarów ścian z ewidencji.")
		return
	var ginfo := gpt_info()
	var text := GptPrompt.build(ginfo)
	var lay := GptPrompt.layout(ginfo)
	app.settings.set_value("tex_px_per_m", float(lay["ppm"]))   # the sheet will be drawn at this scale
	app.settings.set_value("tex_sheet_layout", SheetLayout.to_json(lay))   # the sheet is cut back by these frames
	var guide_path := _save_guide(lay)
	if app.project.is_open():
		app.project.write_text("texture/prompt_gpt.txt", text)
		app.project.log_event("Wygenerowano prompt dla GPT (%d px/m, wypełnienie płótna %d%%)" % [int(lay["ppm"]), int(round(float(lay["fill"]) * 100.0))])
	var win := Window.new()
	win.title = "Prompt dla GPT"
	win.size = Vector2i(900, 700)
	win.transient = true
	win.exclusive = false
	win.close_requested.connect(win.queue_free)
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)
	var edit := TextEdit.new()
	edit.text = text
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var copy := Button.new()
	copy.text = "Kopiuj do schowka"
	copy.theme_type_variation = "PrimaryButton"
	copy.custom_minimum_size.y = 38
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(edit.text)
		copy.text = "Skopiowano ✓")
	row.add_child(copy)
	var guide_btn := Button.new()
	guide_btn.text = "Pokaż obraz-szablon"
	guide_btn.custom_minimum_size.y = 38
	guide_btn.disabled = guide_path == ""
	guide_btn.tooltip_text = "Plik PNG z ramkami S1…: dołącz go do wiadomości dla GPT razem ze zdjęciami."
	guide_btn.pressed.connect(func() -> void: OS.shell_open(guide_path.get_base_dir()))
	row.add_child(guide_btn)
	var hint := Label.new()
	hint.text = "Wklej do ChatGPT razem ze zdjęciami i obrazem-szablonem (%d px/m, płótno wykorzystane w %d%%)." % [int(lay["ppm"]), int(round(float(lay["fill"]) * 100.0))]
	hint.add_theme_color_override("font_color", Color("#aab6c7"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	app._closable(win, row)
	app.add_child(win)
	win.popup_centered()
	gpt_window = win


var gpt_window: Window


## Draws the guide image for this layout and saves it (project folder, otherwise the user folder). Returns the path or "".
func _save_guide(lay: Dictionary) -> String:
	if int(lay["ppm"]) <= 0:
		return ""
	var img := SheetLayout.render_guide(lay)
	var path := ""
	if app.project.is_open():
		path = app.project.path("texture/szablon_arkusza.png")
	else:
		path = ProjectSettings.globalize_path("user://szablon_arkusza.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img.save_png(path) != OK:
		return ""
	return path


func _show_gpt_paste() -> void:
	var win := Window.new()
	win.title = "Wklej opis od GPT (JSON)"
	win.size = Vector2i(860, 680)
	win.transient = true
	win.close_requested.connect(win.queue_free)
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)
	var intro := Label.new()
	intro.text = "Wklej tu całą odpowiedź GPT (Ctrl+V) albo samą część JSON. Program sam znajdzie blok JSON."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("#aab6c7"))
	col.add_child(intro)
	var edit := TextEdit.new()
	edit.placeholder_text = "Wklej tutaj…"
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	col.add_child(edit)
	var count := Label.new()
	count.text = "Nic nie wklejono."
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", Color("#8794a6"))
	edit.text_changed.connect(func() -> void:
		count.text = "Wklejono: %d znaków, %d linii." % [edit.text.length(), edit.get_line_count()] if edit.text != "" else "Nic nie wklejono.")
	col.add_child(count)
	var report := RichTextLabel.new()
	report.bbcode_enabled = true
	report.fit_content = false
	report.scroll_active = true
	report.custom_minimum_size.y = 130
	col.add_child(report)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var from_clip := Button.new()
	from_clip.text = "Wklej ze schowka"
	from_clip.custom_minimum_size.y = 38
	from_clip.pressed.connect(func() -> void:
		edit.text = DisplayServer.clipboard_get()
		edit.text_changed.emit())
	row.add_child(from_clip)
	var go := Button.new()
	go.text = "Sprawdź i zastosuj"
	go.theme_type_variation = "PrimaryButton"
	go.custom_minimum_size.y = 38
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func() -> void:
		report.text = _gpt_paste_apply(edit.text))
	row.add_child(go)
	app._closable(win, row)
	app.add_child(win)
	win.popup_centered()
	edit.grab_focus()


## Parses the pasted text and applies it; returns BBCode for the report area of the window.
func _gpt_paste_apply(text: String) -> String:
	if text.strip_edges() == "":
		return "[color=#f0b35a]Pole jest puste – wklej odpowiedź GPT.[/color]"
	var res := GptDescribe.parse(text)
	if not res["ok"]:
		return "[color=#ff7b7b]✗ %s[/color]" % str(res["error"])
	if app.settings.s("tex_source") == "":
		return "[color=#f0b35a]JSON jest poprawny, ale nie ma jeszcze obrazu arkusza. Wskaż go w kroku „1. Źródło tekstury” i kliknij tu ponownie.[/color]"
	if not app.atlas.is_template:
		app.settings.set_value("tex_slice_mode", "template")      # cut the sheet by the S1-S8 template instead of free panels
		app.atlasflow._load_atlas(app.settings.s("tex_source"), true)
		if not app.atlas.is_template:
			return "[color=#ff7b7b]✗ Obraz nie układa się w ramki S1–S8 z promptu (ani w starą siatkę 2×4). Sprawdź „Podgląd cięcia na regiony…” albo użyj arkusza wygenerowanego z aktualnego promptu i obrazu-szablonu.[/color]"
	return apply_describe_bbcode(res["data"], res["warnings"])


## Stores the described sheet, snaps openings to edges, sets roughness/metal/specular on the surfaces.
func apply_describe(data: Dictionary, warnings: Array = []) -> String:
	describe = data.duplicate(true)
	var n_open := 0
	for code in describe["sectors"].keys():
		var sec: Dictionary = describe["sectors"][code]
		var reg: Dictionary = app.atlas.region(code)
		for e in sec["elements"]:
			e["rect_gpt"] = (e["rect"] as Array).duplicate()
			if not reg.is_empty() and reg.has("img"):
				e["rect"] = GptDescribe.refine_rect(reg["img"], e["rect"])
			n_open += 1
	var n_face := 0
	for fid in app.face_geo.keys():
		var sec_code = app._sector_of(str(app.face_geo[fid]["key"]))
		if not describe["sectors"].has(sec_code):
			continue
		var mv := GptDescribe.material_values(str(describe["sectors"][sec_code]["material"]), str(describe["sectors"][sec_code]["condition"]))
		for f in ["rough", "metal", "spec"]:
			app.faces.set_field(fid, f, snappedf(float(mv[f]), 0.01))
		n_face += 1
	if app.project.is_open():
		app.project.log_event("Opis GPT: %d sektorów, %d otworów" % [describe["sectors"].size(), n_open])
		app.projflow._save_project()
	var msg := "✓ Zastosowano: %d sektorów, %d okien/drzwi, materiał ustawiony na %d powierzchniach." % [describe["sectors"].size(), n_open, n_face]
	if not warnings.is_empty():
		msg += "\nUwagi: " + " ".join(PackedStringArray(warnings))
	app._set_status(msg.replace("\n", " "))
	return msg


func apply_describe_bbcode(data: Dictionary, warnings: Array) -> String:
	var plain := apply_describe(data, [])
	var out := "[color=#6fd08c]%s[/color]" % plain.get_slice("\n", 0)
	var inferred: Array = []
	for code in describe["sectors"].keys():
		if str(describe["sectors"][code].get("source", "photo")) == "inferred":
			inferred.append(code)
	if not inferred.is_empty():
		out += "\n[color=#aab6c7]Sektory wywnioskowane (bez zdjęcia):[/color] " + ", ".join(PackedStringArray(inferred))
	var notes := str(describe.get("building", {}).get("notes", ""))
	if notes != "":
		out += "\n[color=#f0b35a]Uwagi GPT:[/color] " + notes
	for w in warnings:
		out += "\n[color=#f0b35a]![/color] " + str(w)
	return out


## Openings with their place on the texture and (where the picture is shown once) on the wall in metres.
func describe_openings() -> Array:
	var out: Array = []
	if describe.is_empty():
		return out
	for code in describe["sectors"].keys():
		for e in describe["sectors"][code]["elements"]:
			var r: Array = e["rect"]
			var entry := {"id": e["id"], "type": e["type"], "sector": code, "texture_rect": r, "texture_quad": GptDescribe.quad(r)}
			if bool(e["lit"]):
				entry["emissive_light"] = true
			var faces_hit: Array = []
			for fid in app.face_geo.keys():
				var g: Dictionary = app.face_geo[fid]
				if str(g["key"]) != code or ":roof" in str(fid):
					continue
				var uv: Rect2 = g["uv"]
				if uv.size.x > 1.01:
					continue    # the picture repeats on this wall: no unique place
				var fi = app.face_info(fid)
				var len_m: float = (fi["size"] as Vector2).x
				var hm: float = (fi["size"] as Vector2).y
				var rr: Array = r
				faces_hit.append({"face": fid, "wall_rect_m": [
					snappedf((float(rr[0]) - uv.position.x) / uv.size.x * len_m, 0.01),
					snappedf((uv.end.y - float(rr[3])) / uv.size.y * hm, 0.01),
					snappedf((float(rr[2]) - uv.position.x) / uv.size.x * len_m, 0.01),
					snappedf((uv.end.y - float(rr[1])) / uv.size.y * hm, 0.01)]})
			if not faces_hit.is_empty():
				entry["on_walls"] = faces_hit
			out.append(entry)
	return out


func describe_surfaces() -> Array:
	var out: Array = []
	if describe.is_empty():
		return out
	var ids: Array = app.face_geo.keys()
	ids.sort()
	for fid in ids:
		var code = app._sector_of(str(app.face_geo[fid]["key"]))
		if describe["sectors"].has(code):
			out.append({"face": fid, "sector": code, "material": describe["sectors"][code]["material"], "condition": describe["sectors"][code]["condition"], "source": describe["sectors"][code].get("source", "photo")})
	return out
