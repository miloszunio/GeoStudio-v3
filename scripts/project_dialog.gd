class_name ProjectDialog
extends Window
## Start window: pick or create the project folder. Nothing can be built before a project exists,
## because everything (Geoportal data, texture copy, cut, renders, exports) is stored there.

signal chosen(folder: String)
signal chosen_file(path: String)

var _recent: ItemList
var _info: Label
var _folder_dialog: FileDialog
var _can_cancel := false
var _recent_paths: Array = []
var _files: ItemList
var _file_dialog: FileDialog
var _file_paths: Array = []


func _init() -> void:
	title = "Projekt"
	size = Vector2i(760, 520)
	min_size = Vector2i(620, 420)
	transient = true
	exclusive = true
	visible = false
	close_requested.connect(_on_close)
	_build()


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(s, 16)
	bg.add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	m.add_child(root)

	var head := Label.new()
	head.text = "Folder projektu"
	head.add_theme_font_size_override("font_size", 20)
	root.add_child(head)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("#aab6c7"))
	intro.text = "Wskaż albo utwórz folder dla jednego budynku (lub grupy). Trafią do niego: dane z Geoportalu (geo.txt), " \
		+ "wycinek ortofotomapy, kopia tekstury z jej podziałem (.atlas.json), render z chwili zamknięcia programu, " \
		+ "eksporty i dziennik zdarzeń. Folder można przenosić i archiwizować w całości."
	root.add_child(intro)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var pick := Button.new()
	pick.text = "Wskaż lub utwórz folder…"
	pick.theme_type_variation = "PrimaryButton"
	pick.custom_minimum_size.y = 40
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.pressed.connect(func() -> void: _folder_dialog.popup_centered_ratio(0.6))
	row.add_child(pick)

	var pick_file := Button.new()
	pick_file.text = "Otwórz plik projektu (.mgdot)…"
	pick_file.custom_minimum_size.y = 40
	pick_file.pressed.connect(func() -> void: _file_dialog.popup_centered_ratio(0.6))
	row.add_child(pick_file)

	var fl := Label.new()
	fl.text = "Ostatnie pliki .mgdot"
	root.add_child(fl)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.fixed_icon_size = Vector2i(96, 54)
	_files.item_activated.connect(func(i: int) -> void: _choose_file(str(_file_paths[i])))
	root.add_child(_files)
	var rl := Label.new()
	rl.text = "Ostatnie foldery projektów"
	root.add_child(rl)
	_recent = ItemList.new()
	_recent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recent.item_activated.connect(func(i: int) -> void: _choose(str(_recent_paths[i])))
	root.add_child(_recent)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_info)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	var open := Button.new()
	open.text = "Otwórz zaznaczony"
	open.pressed.connect(func() -> void:
		var sel := _recent.get_selected_items()
		if not sel.is_empty():
			_choose(str(_recent_paths[sel[0]])))
	bottom.add_child(open)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var cancel := Button.new()
	cancel.text = "Zamknij"
	cancel.pressed.connect(_on_close)
	bottom.add_child(cancel)

	_folder_dialog = FileDialog.new()
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.title = "Folder projektu (można utworzyć nowy)"
	_folder_dialog.dir_selected.connect(_choose)
	add_child(_folder_dialog)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Otwórz projekt .mgdot"
	_file_dialog.filters = PackedStringArray(["*.mgdot ; Projekt Photo-to-3D Studio"])
	_file_dialog.file_selected.connect(_choose_file)
	add_child(_file_dialog)


## can_cancel: false at start-up (a project is mandatory), true when switching projects.
func show_dialog(recent_stored: String, can_cancel: bool, hint := "", recent_files_stored := "") -> void:
	_can_cancel = can_cancel
	_recent_paths = ProjectStore.recent_list(recent_stored)
	_recent.clear()
	for p in _recent_paths:
		var meta := _peek(str(p))
		_recent.add_item("%s\n%s" % [meta, p])
	_files.clear()
	_file_paths = ProjectStore.recent_files(recent_files_stored)
	for p in _file_paths:
		var m := MgDot.read_manifest(str(p))
		var idx := _files.add_item("%s  (zapisano %s)\n%s" % [m.get("name", str(p).get_file()), m.get("saved", "?"), p])
		var th := MgDot.thumbnail(str(p))
		if th != null:
			th.resize(96, 54, Image.INTERPOLATE_BILINEAR)
			_files.set_item_icon(idx, ImageTexture.create_from_image(th))
	_info.text = hint if hint != "" else ("Brak poprzednich projektów – utwórz pierwszy." if _recent_paths.is_empty() and _file_paths.is_empty() else "")
	if not _folder_dialog.current_dir:
		_folder_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	popup_centered()


static func _peek(folder: String) -> String:
	var f := folder.path_join(ProjectStore.FILE)
	if FileAccess.file_exists(f):
		var d = JSON.parse_string(FileAccess.get_file_as_string(f))
		if typeof(d) == TYPE_DICTIONARY:
			return "%s  (zapisano %s)" % [d.get("name", folder.get_file()), d.get("updated", "?")]
	return folder.get_file()


func _choose(folder: String) -> void:
	hide()
	chosen.emit(ProjectStore.norm(folder))


func _choose_file(path: String) -> void:
	hide()
	chosen_file.emit(path)


func _on_close() -> void:
	if _can_cancel:
		hide()
	else:
		_info.text = "Najpierw wskaż folder projektu – bez niego nie ma gdzie zapisać danych."
