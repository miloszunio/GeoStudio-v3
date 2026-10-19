class_name GptFlow
extends RefCounted
## Everything about the ChatGPT round trip: the prompt window, (the answer is just the canvas image, which the texturing step picks up).

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


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
	if app.project.is_open():
		app.project.write_text("texture/prompt_gpt.txt", text)
		app.project.log_event("Wygenerowano prompt dla GPT")
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
	var hint := Label.new()
	hint.text = "Wklej do ChatGPT razem ze zdjęciami budynku. Gotowe płótno zapisz na dysku i wskaż w kroku „Płótno od GPT”."
	hint.add_theme_color_override("font_color", Color("#aab6c7"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	app._closable(win, row)
	app.add_child(win)
	win.popup_centered()
	gpt_window = win


var gpt_window: Window
