class_name PartsUi
extends RefCounted
## List of the building parts on the Budynek tab: wall height, roof kind and roof height per part.

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


var parts_wrap: VBoxContainer


var parts_box: VBoxContainer


var parts_rows: Array = []

# ---- textures


const ROOF_KINDS := ["auto", "gable", "shed", "flat"]


const ROOF_KIND_NAMES := {"gable": "dwuspadowy", "shed": "pulpitowy", "flat": "płaski"}


func _refresh_parts_ui_if_needed() -> void:
	# Rebuild the rows only when the number of parts changed; otherwise just refresh the values
	# (rebuilding while a spin box is being dragged would drop the user's focus).
	if parts_box == null:
		return
	if parts_rows.size() != app.current_parts.size():
		_refresh_parts_ui()
	else:
		_sync_parts_ui()


func _mk_spin(minv: float, maxv: float, step: float, suffix: String) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = minv
	sp.max_value = maxv
	sp.step = step
	sp.suffix = suffix
	sp.custom_minimum_size.x = 120.0
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sp


func _refresh_parts_ui() -> void:
	if parts_box == null:
		return
	for c in parts_box.get_children():
		parts_box.remove_child(c)
		c.queue_free()
	parts_rows.clear()
	parts_wrap.visible = app.current_parts.size() > 1
	if app.current_parts.size() <= 1:
		return
	for i in range(app.current_parts.size()):
		var panel_c := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		panel_c.add_child(vb)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		vb.add_child(head)
		var title := Label.new()
		title.add_theme_color_override("font_color", Color("#7fb2ff"))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		if i > 0:
			var auto_btn := Button.new()
			auto_btn.text = "↺"
			auto_btn.tooltip_text = "Auto: wysokość i dach tej części wyliczane z części głównej."
			auto_btn.pressed.connect(func() -> void: _on_part_auto(i))
			head.add_child(auto_btn)
			var del_btn := Button.new()
			del_btn.text = "✕"
			del_btn.tooltip_text = "Usuń tę część z modelu."
			del_btn.pressed.connect(func() -> void: _on_part_remove(i))
			head.add_child(del_btn)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		vb.add_child(line)
		var wall := _mk_spin(1.0, 60.0, 0.1, " m")
		wall.tooltip_text = "Wysokość ścian"
		wall.custom_minimum_size.x = 96.0
		wall.value_changed.connect(func(v: float) -> void: _on_part_wall(i, v))
		line.add_child(wall)
		var roof := OptionButton.new()
		roof.tooltip_text = "Rodzaj dachu"
		roof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 0:
			roof.add_item("Dwuspadowy", 1)
			roof.add_item("Płaski", 3)
		else:
			roof.add_item("Auto", 0)
			roof.add_item("Dwuspadowy", 1)
			roof.add_item("Pulpitowy", 2)
			roof.add_item("Płaski", 3)
		roof.item_selected.connect(func(idx: int) -> void: _on_part_roof(i, roof.get_item_id(idx)))
		line.add_child(roof)
		var roof_h := _mk_spin(0.0, 40.0, 0.1, " m")
		roof_h.tooltip_text = "Wysokość dachu ponad okap"
		roof_h.custom_minimum_size.x = 96.0
		roof_h.value_changed.connect(func(v: float) -> void: _on_part_roof_h(i, v))
		line.add_child(roof_h)
		parts_box.add_child(panel_c)
		parts_rows.append({"title": title, "wall": wall, "roof": roof, "roof_h": roof_h})
	_sync_parts_ui()


func _sync_parts_ui() -> void:
	if parts_rows.size() != app.last_rt.size():
		return
	for i in range(parts_rows.size()):
		var row: Dictionary = parts_rows[i]
		var P: Dictionary = app.last_rt[i]
		var st = app._ring_stats(P["pts"])
		var main_tag := " (główna)" if i == 0 else ""
		row["title"].text = "Część %d%s – %.1f × %.1f m" % [i + 1, main_tag, st["length"], st["width"]]
		(row["wall"] as SpinBox).set_value_no_signal(P["wall_h"])
		(row["roof_h"] as SpinBox).set_value_no_signal(P["roof_h"])
		(row["roof_h"] as SpinBox).editable = P["roof_kind"] != "flat"
		var ob := row["roof"] as OptionButton
		var kind = str(app.current_parts[i].get("roof", "auto"))
		if i == 0:
			ob.select(ob.get_item_index(3 if P["roof_kind"] == "flat" else 1))
		else:
			ob.set_item_text(0, "Auto (%s)" % ROOF_KIND_NAMES.get(P["roof_kind"], ""))
			ob.select(ob.get_item_index(ROOF_KINDS.find(kind)))


func _on_part_wall(i: int, v: float) -> void:
	if i == 0:
		app.settings.set_value("model_wall_height", v)   # the main body is the sidebar's "Bryła" setting
	else:
		app.current_parts[i]["wall_h"] = v
		app._rebuild_current()


func _on_part_roof(i: int, id: int) -> void:
	if i == 0:
		app.settings.set_value("model_roof_type", "flat" if id == 3 else "gable")
	else:
		app.current_parts[i]["roof"] = ROOF_KINDS[id]
		app.current_parts[i]["roof_h"] = -1.0
		app._rebuild_current()


func _on_part_roof_h(i: int, v: float) -> void:
	if i == 0:
		app.settings.set_value("model_roof_height", v)
	else:
		app.current_parts[i]["roof_h"] = v
		app._rebuild_current()


func _on_part_auto(i: int) -> void:
	app.current_parts[i]["wall_h"] = -1.0
	app.current_parts[i]["roof"] = "auto"
	app.current_parts[i]["roof_h"] = -1.0
	app._rebuild_current()


func _on_part_remove(i: int) -> void:
	if i <= 0 or i >= app.current_parts.size():
		return
	app.current_parts.remove_at(i)
	app._rebuild_current()
	_refresh_parts_ui()
