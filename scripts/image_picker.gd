class_name ImagePicker
extends Window
## Own file browser with picture previews (Godot's native FileDialog shows no thumbnails).
##   [ folder path ] [↑] [Folder…] [Plik…]
##   [ grid of thumbnails ............ ] [ big preview + name + size ] [Użyj tej tekstury]
## Click = preview, double click / button = pick; double click on a folder enters it.
## Emits picked(path) with a res:// path for files inside the project, otherwise an absolute path.

signal picked(path: String)

const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "json"]
const THUMB := 150

var _dir := ""
var _path_edit: LineEdit
var _list: ItemList
var _preview: TextureRect
var _info: Label
var _use_btn: Button
var _native: FileDialog
var _native_dir: FileDialog
var _entries: Array = []      # [{name, path, dir}] parallel to the item list
var _selected := ""
var _gen := 0                 # bumps on every folder change, cancels running thumbnail loading
var _folder_icon: ImageTexture
var _file_icon: ImageTexture


func _init() -> void:
	title = "Wybierz teksturę"
	size = Vector2i(1180, 720)
	min_size = Vector2i(760, 480)
	transient = true
	exclusive = true
	visible = false
	close_requested.connect(hide)
	_build()


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(s, 10)
	bg.add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	m.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = "folder z teksturami"
	_path_edit.text_submitted.connect(func(t: String) -> void: open_dir(t))
	top.add_child(_path_edit)
	var up := Button.new()
	up.text = "↑ Wyżej"
	up.pressed.connect(func() -> void: open_dir(_dir.get_base_dir() if _dir != "res://" else _dir))
	top.add_child(up)
	var pick_dir := Button.new()
	pick_dir.text = "Folder…"
	pick_dir.tooltip_text = "Wybierz inny folder (okno systemowe)"
	pick_dir.pressed.connect(func() -> void: _native_dir.popup_centered_ratio(0.6))
	top.add_child(pick_dir)
	var pick_file := Button.new()
	pick_file.text = "Plik spoza listy…"
	pick_file.pressed.connect(func() -> void: _native.popup_centered_ratio(0.6))
	top.add_child(pick_file)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 560
	root.add_child(split)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.max_columns = 0
	_list.same_column_width = true
	_list.fixed_icon_size = Vector2i(THUMB, THUMB)
	_list.max_text_lines = 2
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_on_activated)
	split.add_child(_list)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(frame)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame.add_child(_preview)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = "Kliknij obraz, aby zobaczyć podgląd."
	right.add_child(_info)
	_use_btn = Button.new()
	_use_btn.text = "Użyj tej tekstury"
	_use_btn.custom_minimum_size.y = 40
	_use_btn.disabled = true
	_use_btn.pressed.connect(_confirm)
	right.add_child(_use_btn)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.pressed.connect(hide)
	right.add_child(cancel)

	_native = FileDialog.new()
	_native.access = FileDialog.ACCESS_FILESYSTEM
	_native.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_native.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga,*.json ; Obraz lub atlas JSON")
	_native.file_selected.connect(func(p: String) -> void: _emit(p))
	add_child(_native)
	_native_dir = FileDialog.new()
	_native_dir.access = FileDialog.ACCESS_FILESYSTEM
	_native_dir.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_native_dir.dir_selected.connect(func(p: String) -> void: open_dir(p))
	add_child(_native_dir)

	_folder_icon = _flat_icon(Color("#33507a"))
	_file_icon = _flat_icon(Color("#3a3f4a"))


static func _flat_icon(c: Color) -> ImageTexture:
	var img := Image.create(THUMB, THUMB, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## Opens the picker on the folder of `current` (or a fallback folder) and preselects that file.
func open_for(current: String, fallback_dir := "res://textures/samples") -> void:
	var start := fallback_dir
	var want := ""
	if current.strip_edges() != "":
		want = current
		start = current.get_base_dir()
	if start == "" or not DirAccess.dir_exists_absolute(_abs(start)):
		start = fallback_dir
	popup_centered()
	open_dir(start, want)


func open_dir(dir: String, select_file := "") -> void:
	dir = dir.strip_edges().replace("\\", "/")
	if dir == "" or not DirAccess.dir_exists_absolute(_abs(dir)):
		_info.text = "Nie ma takiego folderu: " + dir
		return
	_dir = dir
	_path_edit.text = dir
	_gen += 1
	var gen := _gen
	_list.clear()
	_entries.clear()
	_selected = ""
	_use_btn.disabled = true
	_preview.texture = null
	var dirs: Array = []
	for d in DirAccess.get_directories_at(_abs(dir)):
		if not d.begins_with("."):
			dirs.append(d)
	dirs.sort()
	var files: Array = []
	for f in DirAccess.get_files_at(_abs(dir)):
		if f.get_extension().to_lower() in EXTENSIONS and not f.ends_with(".import") and not f.ends_with(".atlas.json"):
			files.append(f)
	files.sort()
	for d in dirs:
		_entries.append({"name": d, "path": dir.path_join(d), "dir": true})
		_list.add_item("▸ " + d, _folder_icon)
	for f in files:
		_entries.append({"name": f, "path": dir.path_join(f), "dir": false})
		_list.add_item(f, _file_icon)
	_info.text = "%d obrazów w tym folderze." % files.size() if not files.is_empty() else "Brak obrazów w tym folderze."
	await _load_thumbs(gen, select_file)


func _load_thumbs(gen: int, select_file: String) -> void:
	for i in range(_entries.size()):
		if gen != _gen or not is_inside_tree():
			return
		var e: Dictionary = _entries[i]
		if e["dir"]:
			continue
		if str(e["name"]).get_extension().to_lower() != "json":
			var img := _load(str(e["path"]), THUMB * 2)
			if img != null:
				var k := float(THUMB) / float(maxi(img.get_width(), img.get_height()))
				img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_BILINEAR)
				_list.set_item_icon(i, ImageTexture.create_from_image(img))
		if select_file != "" and str(e["path"]) == select_file:
			_list.select(i)
			_list.ensure_current_is_visible()
			_on_selected(i)
		if i % 3 == 2:
			await get_tree().process_frame


## Loads an image from disk (also res:// files that are not imported) and shrinks it to max_side.
static func _load(path: String, max_side: int) -> Image:
	var img: Image = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res = load(path)   # imported project texture (also works in an exported build)
		if res is Texture2D:
			img = (res as Texture2D).get_image()
	if img == null:
		img = Image.new()
		if img.load(_abs(path)) != OK:
			return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	var side := maxi(img.get_width(), img.get_height())
	if side > max_side:
		var k := float(max_side) / float(side)
		img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_BILINEAR)
	return img


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p


func _on_selected(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	if e["dir"]:
		_selected = ""
		_use_btn.disabled = true
		_info.text = "Folder – kliknij dwukrotnie, aby wejść."
		return
	_selected = str(e["path"])
	_use_btn.disabled = false
	if str(e["name"]).get_extension().to_lower() == "json":
		_preview.texture = null
		_info.text = "%s\nAtlas JSON." % e["name"]
		return
	var full := Image.new()
	if full.load(_abs(_selected)) != OK:
		full = _load(_selected, 100000)
	var dims := "" if full == null else "%d × %d px" % [full.get_width(), full.get_height()]
	var prev := _load(_selected, 1400)
	_preview.texture = ImageTexture.create_from_image(prev) if prev != null else null
	var side_json := (_selected.get_basename() + ".atlas.json")
	var note := "\nPodział już zapisany (.atlas.json)." if FileAccess.file_exists(side_json) else ""
	_info.text = "%s\n%s%s" % [e["name"], dims, note]


func _on_activated(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	if _entries[i]["dir"]:
		open_dir(str(_entries[i]["path"]))
	else:
		_selected = str(_entries[i]["path"])
		_confirm()


func _confirm() -> void:
	if _selected != "":
		_emit(_selected)


func _emit(path: String) -> void:
	hide()
	picked.emit(ProjectSettings.localize_path(path))
