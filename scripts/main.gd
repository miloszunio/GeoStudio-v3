extends Control
## Photo-to-3D Studio prototype v2.1
## Flow: Geoportal map -> click a building (EGiB footprint) -> 3D model -> atlas auto-texturing.
## Every tunable value lives in AppSettings and is edited in the left sidebar (SettingsPanel).
## Project files needed: main_v2.gd (root Control), app_settings.gd, settings_panel.gd,
## geoportal_client.gd, texture_atlas.gd.

const SAMPLE_SOURCE_NAME := "przykładowy obrys L"
const SAMPLE_RING := [
	[-8.0, -5.0], [8.0, -5.0], [8.0, 5.0], [3.0, 5.0],
	[3.0, 8.0], [-8.0, 8.0], [-8.0, -5.0]
]

var gpt: GptFlow
var exporter: ExportFlow
var mapping: MappingFlow
var rig: CameraRig
var place: PlaceSearch
var parts_ui: PartsUi
var projflow: ProjectFlow
var roofed: RoofFlow
var chimneys: ChimneyFlow
var atlasflow: AtlasFlow

var settings: AppSettings
var panel: SettingsPanel
var save_timer: Timer
var ui_theme: Theme

# ---- UI / 3D nodes
var tabs: TabContainer
var viewport_container: SubViewportContainer
var subviewport: SubViewport
var camera: Camera3D
var orbit_root: Node3D
var building_root: Node3D
var env: Environment
var sun: DirectionalLight3D
var ground: MeshInstance3D
var ground_mat: StandardMaterial3D
var grid_mesh: MeshInstance3D
var grid_mat: StandardMaterial3D
var status_label: Label
var info_label: Label
var diag_label: Label
var coord_edit: LineEdit
var building_label: Label
var use_btn: Button
var add_nb_btn: Button
var confirm_dialog: ConfirmationDialog
var wall_material: StandardMaterial3D
var roof_material: StandardMaterial3D

var current_bounds := AABB(Vector3(-5, 0, -4), Vector3(10, 8, 8))
var current_source := "brak"
var current_ring: Array = []
var current_floors := 0
var current_is_geographic := false
var footprint_rotation_deg := 0.0
var wall_h_cur := 8.0
var roof_h_cur := 3.0
var ridge_along_x := true
var ridge_mid := 0.0
var ridge_half := 1.0
var half_pos := 1.0               # distance ridge -> eave on the t > 0 side (asymmetric roofs: differs from half_neg)
var half_neg := 1.0
var ridge_shift := 0.0            # ridge offset from the middle of the span (m, t > 0 = side A)
var roof_mode := "gable"          # "gable" (also flat when roof_h_cur = 0), "shed" or "planes" (generated roof, see RoofGen)
var roof_planes: Array = []        # planes of a generated roof: [{"a","b","c","label","end"}]
var shed_axis := 0                # shed roofs fall along x (0) or z/y (1) ...
var shed_sign := 1                # ... towards + (1) or - (-1) of that axis
var shed_lo := 0.0
var shed_span := 1.0
var part_variant := 0             # kept for saved projects; all parts now share one texture set
var part_is_annex := false        # current part leans on another one (shed roof): uses the long-wall photos
var tex_main_wall_h := 3.0        # main body size = scale reference for the photos on every part
var tex_main_roof_h := 0.0

# ---- building parts (EGiB often cuts one building into several polygons)
var current_parts: Array = []     # [{raw, floors, wall_h (-1 = auto), roof ("auto"|...), roof_h (-1 = auto)}]
var current_attrs: Array = []      # EGiB attributes of the buildings the model was built from
var last_rt: Array = []           # resolved per-part parameters of the last build
var map_sel_keys: Array = []      # selected buildings, by a stable key (survives map refresh)
var atlas := TextureAtlas.new()
var tex_materials: Dictionary = {}
var faces := FaceStore.new()                 # corrections of single surfaces (see FaceStore)
var face_geo: Dictionary = {}                # face id -> uv window of the surface, for the panel preview
var footprint_src_center := Vector2.ZERO     # centre of the source outline (EPSG:2180 metres), for the model placement
var footprint_local_center := Vector2.ZERO   # centre removed after rotating the outline
var face_materials: Dictionary = {}          # signature -> StandardMaterial3D with per-face overrides
var selected_face := ""                      # id of the surface picked in the 3D view
var face_panel: FacePanel
var view_holder: Control
var _faces_dirty := false

# ---- Geoportal map state (EPSG:2180: x = easting, y = northing)
var geo: GeoportalClient
var map_canvas: Control
var map_timer: Timer
var project := ProjectStore.new()
var project_required := true          # tools / tests that run without a project set this to false
var project_label: Label
var map_center := Vector2.ZERO
var map_mpp := 0.5                     # metres per screen pixel
var map_image: Texture2D
var map_image_rect := Rect2()
var map_buildings: Array = []
var map_selected := -1
var map_ortho_failed := false
var map_busy := false
var map_pending := false
var map_press_pos := Vector2.ZERO
var map_pressing := false
var map_moved := false
var diag_lines: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	settings = AppSettings.new()
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.6
	save_timer.timeout.connect(func() -> void:
		settings.save()
		projflow._save_project())
	add_child(save_timer)

	geo = GeoportalClient.new()
	geo.settings = settings
	add_child(geo)
	geo.log_message.connect(_on_geo_log)

	map_timer = Timer.new()
	map_timer.one_shot = true
	map_timer.wait_time = settings.f("map_refresh_delay")
	map_timer.timeout.connect(_refresh_map)
	add_child(map_timer)

	if DisplayServer.get_name() == "headless":
		project_required = false
	get_tree().auto_accept_quit = false    # closing the window goes through projflow._on_quit() (render + save)
	gpt = GptFlow.new(self)
	exporter = ExportFlow.new(self)
	mapping = MappingFlow.new(self)
	rig = CameraRig.new(self)
	place = PlaceSearch.new(self)
	parts_ui = PartsUi.new(self)
	projflow = ProjectFlow.new(self)
	roofed = RoofFlow.new(self)
	chimneys = ChimneyFlow.new(self)
	atlasflow = AtlasFlow.new(self)
	_apply_ui_theme()
	_build_ui()
	_build_viewport()
	_setup_materials()
	_apply_view(true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.b("app_fullscreen") else DisplayServer.WINDOW_MODE_MAXIMIZED)

	map_center = GeoportalClient.lonlat_to_2180(settings.f("map_start_lon"), settings.f("map_start_lat"))
	map_mpp = settings.f("map_start_mpp")

	# Every session starts with an empty scene: no model and no texture (the library, if any, is still listed).
	settings.set_value("tex_source", "")
	settings.set_value("tex_enabled", false)
	atlasflow._load_atlas("", false)
	panel.select_tab("place", false)
	_update_steps()

	settings.changed.connect(_on_setting_changed)   # connect last: setup above must not trigger rebuilds
	projflow._update_project_bar()
	_update_building_label()
	await get_tree().process_frame
	_refresh_map()
	if project_required and not project.is_open():
		projflow._show_project_dialog(false)


# ================================================================== UI

func _apply_ui_theme() -> void:
	if ui_theme == null:
		ui_theme = Theme.new()
	ui_theme.default_font_size = settings.i("ui_font_size")
	_style_buttons(ui_theme)
	theme = ui_theme


## Buttons must stand out from labels and fields: a filled, bordered, high-contrast look
## (steel blue for actions, green for the main action, dark slate for tabs and section headers).
static func _box(bg: Color, border: Color, bottom := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_width_bottom = bottom
	sb.border_color = border
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## 18 px tick box: an outlined square, or a filled one with a tick.
static func _check_icon(on: bool, col: Color) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var edge := x < 3 or y < 3 or x > n - 4 or y > n - 4
			if on or edge:
				img.set_pixel(x, y, col)
	if on:
		var tick: Array = [Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12), Vector2i(8, 11), Vector2i(9, 10), Vector2i(10, 9), Vector2i(11, 8), Vector2i(12, 7), Vector2i(13, 6)]
		for p in tick:
			for d in [Vector2i(0, 0), Vector2i(0, 1)]:
				img.set_pixelv(p + d, Color.WHITE)
	return ImageTexture.create_from_image(img)


static func _style_set(th: Theme, type_name: String, base: String, normal: Color, hover: Color, pressed: Color, border: Color, text: Color) -> void:
	th.set_type_variation(type_name, base) if type_name != base else null
	th.set_stylebox("normal", type_name, _box(normal, border))
	th.set_stylebox("hover", type_name, _box(hover, border.lightened(0.25)))
	th.set_stylebox("pressed", type_name, _box(pressed, border.lightened(0.35), 3))
	th.set_stylebox("hover_pressed", type_name, _box(pressed.lightened(0.08), border.lightened(0.35), 3))
	th.set_stylebox("disabled", type_name, _box(Color("#20252d"), Color("#2c333e")))
	var focus := _box(Color(0, 0, 0, 0), Color("#a9d2ff"))
	focus.draw_center = false
	th.set_stylebox("focus", type_name, focus)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(c, type_name, text)
	th.set_color("font_disabled_color", type_name, Color("#6b7480"))


func _style_buttons(th: Theme) -> void:
	var white := Color("#ffffff")
	_style_set(th, "Button", "Button", Color("#2d6aa3"), Color("#3a7fc0"), Color("#1f4f7f"), Color("#5a9ad6"), white)
	_style_set(th, "OptionButton", "OptionButton", Color("#2a3140"), Color("#364156"), Color("#364156"), Color("#5d6f8c"), white)
	for plain in ["CheckBox", "CheckButton"]:   # check boxes inherit from Button but must stay plain
		for st in ["normal", "pressed", "disabled"]:
			th.set_stylebox(st, plain, _box(Color("#171c25"), Color("#2b3443")))
		for st in ["hover", "hover_pressed"]:
			th.set_stylebox(st, plain, _box(Color("#212a38"), Color("#4a5a75")))
		th.set_color("font_color", plain, Color("#e6ebf2"))
		th.set_color("font_hover_color", plain, Color("#ffffff"))
		th.set_color("font_pressed_color", plain, Color("#e6ebf2"))
		th.set_color("font_hover_pressed_color", plain, Color("#ffffff"))
		th.set_color("font_focus_color", plain, Color("#e6ebf2"))
	var box_off := _check_icon(false, Color("#8ea2c0"))
	var box_on := _check_icon(true, Color("#3a8fe0"))
	for plain in ["CheckBox", "CheckButton"]:
		th.set_icon("unchecked", plain, box_off)
		th.set_icon("checked", plain, box_on)
		th.set_icon("unchecked_disabled", plain, _check_icon(false, Color("#4a5160")))
		th.set_icon("checked_disabled", plain, _check_icon(true, Color("#4a5160")))
	th.add_type("TabButton")
	_style_set(th, "TabButton", "Button", Color("#1b212b"), Color("#273141"), Color("#17406b"), Color("#3a4860"), Color("#d4dbe6"))
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = th.get_stylebox(st, "TabButton")
		sb.content_margin_left = 2
		sb.content_margin_right = 2
	th.get_stylebox("pressed", "TabButton").border_color = Color("#78b7ff")
	th.set_color("font_pressed_color", "TabButton", white)
	th.set_color("font_hover_pressed_color", "TabButton", white)
	th.add_type("HeaderButton")
	_style_set(th, "HeaderButton", "Button", Color("#262d3a"), Color("#323b4d"), Color("#323b4d"), Color("#4a5873"), Color("#e6ecf5"))
	th.add_type("PrimaryButton")
	_style_set(th, "PrimaryButton", "Button", Color("#2a7a4b"), Color("#349a5e"), Color("#1d5c38"), Color("#5cc48a"), white)
	th.set_color("font_disabled_color", "PrimaryButton", Color("#7f8c84"))


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#10141b")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var body := HSplitContainer.new()   # drag the divider to resize the sidebar
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)

	# ---------------- left sidebar: title + tabbed settings (see settings_panel.gd)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 380
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sidebar)
	var margin := MarginContainer.new()
	for side_name in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side_name, 8)
	sidebar.add_child(margin)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	margin.add_child(sv)

	var title := Label.new()
	title.text = "PHOTO-TO-3D STUDIO"
	title.add_theme_font_size_override("font_size", settings.i("ui_font_size") + 6)
	sv.add_child(title)

	var pbar := HBoxContainer.new()
	pbar.add_theme_constant_override("separation", 6)
	sv.add_child(pbar)
	project_label = Label.new()
	project_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	project_label.clip_text = true
	project_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pbar.add_child(project_label)
	var proj_btn := Button.new()
	proj_btn.text = "Projekt…"
	proj_btn.tooltip_text = "Zmień lub utwórz folder projektu"
	proj_btn.pressed.connect(func() -> void: projflow._show_project_dialog(project.is_open()))
	pbar.add_child(proj_btn)

	panel = SettingsPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(panel)
	panel.setup(settings, {"place": _build_place_page(), "building": _build_building_page(), "app": _build_app_page()})
	panel.action_pressed.connect(_on_action)
	panel.tab_changed.connect(_on_sidebar_tab)
	_update_building_label()

	# ---------------- right side: map / 3D tabs + status bar
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	body.add_child(right)

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)

	map_canvas = Control.new()
	map_canvas.name = "Mapa Geoportal"
	map_canvas.clip_contents = true
	map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	map_canvas.draw.connect(_on_map_draw)
	map_canvas.gui_input.connect(_on_map_gui_input)
	map_canvas.resized.connect(map_canvas.queue_redraw)
	tabs.add_child(map_canvas)

	view_holder = Control.new()
	view_holder.name = "Model 3D"
	tabs.add_child(view_holder)
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "Scena"
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container.gui_input.connect(rig._on_viewport_gui_input)
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_holder.add_child(viewport_container)
	face_panel = FacePanel.new()
	face_panel.setup(faces, self)
	face_panel.visible = false
	face_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face_panel.anchor_left = 1.0
	face_panel.offset_left = -372.0
	face_panel.offset_right = -10.0
	face_panel.offset_top = 10.0
	face_panel.offset_bottom = -10.0
	face_panel.closed.connect(func() -> void: _select_face(""))
	face_panel.open_editor.connect(func() -> void: mapping.open_uv_editor(selected_face))
	view_holder.add_child(face_panel)
	faces.changed.connect(_on_faces_changed)
	rig._build_preset_bar()

	var footer := PanelContainer.new()
	footer.custom_minimum_size.y = 38
	right.add_child(footer)
	status_label = Label.new()
	status_label.text = "Start..."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status_label)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Przywrócić ustawienia domyślne?"
	confirm_dialog.dialog_text = "Wszystkie ustawienia wrócą do wartości domyślnych."
	confirm_dialog.confirmed.connect(func() -> void:
		_roof_internal = true   # resetting the roof height must not count as a manual override
		settings.reset_all()
		_roof_internal = false
		_rebuild_current()
		_set_status("Przywrócono ustawienia domyślne."))
	add_child(confirm_dialog)


## Header of tab 1 "Miejsce": find a place, pick the building(s), build the model.
func _card(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#161b24")
	sb.border_color = Color("#2b3443")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	_add_heading(v, title)
	return v


func _build_place_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- 1. search a place
	var s1 := _card(box, "Szukaj miejsca")
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	s1.add_child(srow)
	place.edit = LineEdit.new()
	place.edit.placeholder_text = "miejscowość, ulica, adres…"
	place.edit.clear_button_enabled = true
	place.edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.edit.text_submitted.connect(func(_t: String) -> void: place.search())
	srow.add_child(place.edit)
	var place_btn := Button.new()
	place_btn.text = "Szukaj"
	place_btn.pressed.connect(place.search)
	srow.add_child(place_btn)
	place.caption = Label.new()           # caption of the list below: "Wyniki" / "Ostatnie wyszukiwania"
	place.caption.add_theme_color_override("font_color", Color("#aab6c7"))
	place.caption.add_theme_font_size_override("font_size", 12)
	place.caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s1.add_child(place.caption)
	place.list = ItemList.new()
	place.list.visible = false
	place.list.auto_height = true
	place.list.max_columns = 1
	place.list.max_text_lines = 3
	place.list.same_column_width = true
	place.list.fixed_column_width = 316
	place.list.icon_mode = ItemList.ICON_MODE_LEFT
	place.list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place.list.item_selected.connect(place.choose)
	s1.add_child(place.list)
	place.show_history()

	# --- 2. coordinates
	var s2 := _card(box, "Współrzędne")
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	s2.add_child(crow)
	coord_edit = LineEdit.new()
	coord_edit.text = "%.4f, %.4f" % [settings.f("map_start_lat"), settings.f("map_start_lon")]
	coord_edit.placeholder_text = "szerokość, długość (np. 52.2297, 21.0122)"
	coord_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coord_edit.text_submitted.connect(func(_t: String) -> void: _on_goto_pressed())
	crow.add_child(coord_edit)
	var goto_btn := Button.new()
	goto_btn.text = "Idź"
	goto_btn.tooltip_text = "Przejdź do współrzędnych"
	goto_btn.pressed.connect(_on_goto_pressed)
	crow.add_child(goto_btn)

	# --- 3. selected building
	var s3 := _card(box, "Zaznaczony budynek")
	building_label = Label.new()
	building_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s3.add_child(building_label)
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 6)
	s3.add_child(sel_row)
	add_nb_btn = Button.new()
	add_nb_btn.text = "+ Sąsiednie części"
	add_nb_btn.tooltip_text = "Dodaje do zaznaczenia poligony stykające się z wybranymi (EGiB potrafi pociąć jeden budynek na kilka części). Ctrl/Shift + klik dodaje lub usuwa pojedynczy poligon."
	add_nb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_nb_btn.pressed.connect(_on_add_neighbours)
	sel_row.add_child(add_nb_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Wyczyść"
	clear_btn.pressed.connect(func() -> void:
		map_sel_keys.clear()
		map_selected = -1
		_update_building_label()
		map_canvas.queue_redraw())
	sel_row.add_child(clear_btn)

	use_btn = Button.new()
	use_btn.text = "Zbuduj model 3D z zaznaczenia  →"
	use_btn.theme_type_variation = "PrimaryButton"
	use_btn.custom_minimum_size.y = 44
	use_btn.disabled = true
	use_btn.pressed.connect(_on_use_building_pressed)
	box.add_child(use_btn)
	return box


## Header of tab 2 "Budynek": what was built, and the per-part list for multi-part buildings.
func _build_building_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.text = "Nie zbudowano jeszcze modelu.\nW kroku 1 (Miejsce) zaznacz budynek na mapie i kliknij „Zbuduj model 3D”."
	box.add_child(info_label)

	parts_ui.parts_wrap = VBoxContainer.new()
	parts_ui.parts_wrap.add_theme_constant_override("separation", 6)
	parts_ui.parts_wrap.visible = false
	box.add_child(parts_ui.parts_wrap)
	_add_heading(parts_ui.parts_wrap, "Części budynku")
	var parts_hint := Label.new()
	parts_hint.text = "w każdym wierszu: wysokość ścian · rodzaj dachu · wysokość dachu"
	parts_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parts_hint.add_theme_color_override("font_color", Color("#aab6c7"))
	parts_ui.parts_wrap.add_child(parts_hint)
	parts_ui.parts_box = VBoxContainer.new()
	parts_ui.parts_box.add_theme_constant_override("separation", 8)
	parts_ui.parts_wrap.add_child(parts_ui.parts_box)
	return box


## Header of the settings tab: result of the Geoportal connection test.
func _build_app_page() -> Control:
	diag_label = Label.new()
	diag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diag_label.add_theme_color_override("font_color", Color("#aab6c7"))
	return diag_label


## Marks the finished steps in the tab strip (called after every change of the model / texture state).
func _update_steps() -> void:
	if panel == null:
		return
	var built := current_ring.size() >= 3 and not current_parts.is_empty()
	panel.set_tab_state("place", "done" if built else "")
	panel.set_tab_state("building", "done" if built else "")
	panel.set_tab_enabled("building", built, "Najpierw zbuduj model w kroku 1 (zaznacz budynek na mapie i kliknij „Zbuduj model 3D”).")
	panel.set_tab_enabled("tex", built, "Najpierw zbuduj model w kroku 1 (zaznacz budynek na mapie i kliknij „Zbuduj model 3D”).")
	panel.set_tab_enabled("roof", built, "Najpierw zbuduj model w kroku 1 (zaznacz budynek na mapie i kliknij „Zbuduj model 3D”).")
	panel.set_tab_state("tex", "done" if settings.b("tex_enabled") and atlas != null and atlas.regions.size() > 0 else "")


## Picking a sidebar tab also shows the matching view: step 1 -> map, the other steps -> 3D.
func _on_sidebar_tab(id: String) -> void:
	match id:
		"place":
			tabs.current_tab = 0
		"building", "tex", "roof", "view":
			tabs.current_tab = 1


func _build_viewport() -> void:
	subviewport = SubViewport.new()
	subviewport.own_world_3d = true
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(subviewport)

	var world := WorldEnvironment.new()
	env = Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	subviewport.add_child(world)

	sun = DirectionalLight3D.new()
	subviewport.add_child(sun)

	ground = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.position.y = -0.05
	ground_mat = StandardMaterial3D.new()
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	subviewport.add_child(ground)

	grid_mesh = MeshInstance3D.new()
	grid_mat = StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.vertex_color_use_as_albedo = true
	grid_mesh.material_override = grid_mat
	grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	subviewport.add_child(grid_mesh)

	orbit_root = Node3D.new()
	subviewport.add_child(orbit_root)
	camera = Camera3D.new()
	camera.current = true
	orbit_root.add_child(camera)
	rig._reset_camera()


func _setup_materials() -> void:
	wall_material = StandardMaterial3D.new()
	roof_material = StandardMaterial3D.new()
	_apply_plain_materials()


func _apply_plain_materials() -> void:
	var rough := settings.f("tex_roughness")
	wall_material.albedo_color = settings.c("tex_wall_color")
	wall_material.roughness = rough
	roof_material.albedo_color = settings.c("tex_roof_color")
	roof_material.roughness = rough
	roof_material.metallic_specular = 0.1
	wall_material.metallic_specular = 0.1


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("#78b7ff"))
	parent.add_child(label)


func _set_status(text: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = "  " + text


func _on_geo_log(text: String) -> void:
	diag_lines.append(text)
	while diag_lines.size() > 6:
		diag_lines.pop_front()
	diag_label.text = "\n".join(diag_lines)


# ================================================================== settings reactions

func _on_setting_changed(key: String) -> void:
	save_timer.start()
	if _roof_batch:
		return
	if projflow._restoring:
		return
	if key == "tex_enabled":
		_update_steps()
	if key.begins_with("view_"):
		_apply_view(key.begins_with("view_grid"))
		if key.begins_with("view_wire") or key.begins_with("view_vert"):
			update_edge_overlay()
	elif key.begins_with("map_"):
		if key == "map_refresh_delay":
			map_timer.wait_time = settings.f("map_refresh_delay")
		elif key == "map_use_ortho" or key == "map_building_max_mpp" or key == "map_max_image_px":
			if key == "map_use_ortho" and not settings.b("map_use_ortho"):
				map_image = null
			map_timer.start()
		map_canvas.queue_redraw()
	elif key == "model_chimneys":
		chimneys.rebuild()
	elif key.begins_with("model_"):
		if key == "model_wall_height" and not _wall_internal and settings.b("model_walls_from_tex"):
			settings.set_value("model_walls_from_tex", false)   # a hand-set wall height wins over the texture
			return
		if key == "model_roof_type":
			var keep: Array = []
			for e in RoofGen.list_from_json(settings.s("model_roof_gen")):
				if int(e.get("part", 0)) != 0:
					keep.append(e)
			if keep.size() != RoofGen.list_from_json(settings.s("model_roof_gen")).size():
				roof_apply_settings({"model_roof_gen": RoofGen.to_json(keep)})   # the chosen type replaces a drawn roof
				return
		if key == "model_roof_height":
			if _roof_internal or _roof_batch:
				return
			if _rescale_roof(settings.f("model_roof_height")):
				return
			if settings.b("model_roof_from_tex"):
				settings.set_value("model_roof_from_tex", false)   # a hand-set height wins over the texture
				return
		if key in ["model_use_floors", "model_floor_height"] and current_floors > 0 and settings.b("model_use_floors"):
			_wall_internal = true
			settings.set_value("model_wall_height", current_floors * settings.f("model_floor_height"))
			_wall_internal = false
		else:
			_rebuild_current()
	elif key.begins_with("tex_"):
		if atlasflow.loading_tex:
			return
		if key == "tex_source":
			atlasflow._on_texture_source_changed()
		elif key == "tex_library_dir" or key == "tex_library_enabled":
			atlasflow._load_atlas(settings.s("tex_source"), true)
		elif key == "tex_enabled":
			_rebuild_current()
		elif key.begins_with("tex_slice_"):
			pass       # applied by "Przeanalizuj obraz ponownie"
		else:
			if key in ["tex_long_a", "tex_long_b", "tex_gable_a", "tex_gable_b", "tex_roof", "tex_wall_all"] and settings.s(key) != "auto" and not settings.b("tex_enabled"):
				settings.set_value("tex_enabled", true)   # picking a texture means "use it"
				return
			tex_materials.clear()
			face_materials.clear()
			_apply_plain_materials()
			_rebuild_current()
	elif key.begins_with("svc_"):
		geo.reset_cache()
	elif key == "ui_font_size":
		_apply_ui_theme()
	elif key.begins_with("src_"):
		pass


func _apply_roof_from_texture() -> void:
	if current_parts.is_empty():
		_set_status("Najpierw zbuduj model (krok 1).")
		return
	if not _use_textures():
		_set_status("Najpierw wczytaj teksturę i włącz „Teksturuj model” – kąt dachu jest mierzony na zdjęciu szczytu.")
		return
	var key := _gable_key()
	if key == "" or atlas.estimate_roof_ratio(key) <= 0.0:
		_set_status("Na zdjęciu szczytu nie widać zarysu dachu (potrzebny szczyt na jednolitym tle) – ustaw wysokość ręcznie.")
		return
	settings.set_value("model_roof_from_tex", true)
	_rebuild_current()
	_set_status("Wysokość dachu %.2f m wyliczona z nachylenia na zdjęciu „%s”." % [settings.f("model_roof_height"), key])


## Wall height that makes the long-wall picture keep its own proportions (windows are not squashed).
## The register (EGiB) often knows only a rough floor count; the photographed wall knows its real shape.
func _apply_walls_from_texture() -> void:
	if last_rt.is_empty() or not _use_textures():
		_set_status("Najpierw zbuduj model i wczytaj teksturę.")
		return
	var key := _forced_region("tex_long_a")
	if key == "":
		key = atlas.pick_key("facade_long", settings.i("tex_variant"))
	if key == "" or atlas.region(key).is_empty():
		_set_status("Brak zdjęcia długiej ściany w teksturze.")
		return
	var P: Dictionary = last_rt[0]
	var bb: Rect2 = P["bb"]
	var length := bb.size.x if bool(P["ridge_along_x"]) else bb.size.y
	var asp := atlas.aspect(key)
	if asp <= 0.2:
		return
	var h := clampf(snappedf(length / asp, 0.1), 2.0, 60.0)
	settings.set_value("model_use_floors", false)
	_wall_internal = true
	settings.set_value("model_wall_height", h)
	_wall_internal = false
	settings.set_value("model_walls_from_tex", atlas.is_template)
	_rebuild_current()
	_set_status("Wysokość ścian %.1f m = długość ściany %.1f m / proporcje zdjęcia „%s” (%.2f : 1). Sprawdź w oknie dachu, czy szczyt nadal pasuje." % [h, length, key, asp])


func _on_action(id: String) -> void:
	match id:
		"act_walls_from_tex":
			_apply_walls_from_texture()
		"act_map_refresh":
			_refresh_map()
		"act_map_save_start":
			var ll := GeoportalClient.e2180_to_lonlat(map_center.x, map_center.y)
			settings.set_value("map_start_lat", ll.y)
			settings.set_value("map_start_lon", ll.x)
			settings.set_value("map_start_mpp", map_mpp)
			_set_status("Zapisano bieżący widok mapy jako startowy.")
		"act_tex_load":
			atlasflow._on_texture_source_changed()
		"act_tex_reslice":
			atlasflow._on_texture_source_changed(true)
		"act_mgdot_save":
			projflow.save_mgdot(false)
		"act_mgdot_save_as":
			projflow.save_mgdot(true)
		"act_project_switch":
			projflow._show_project_dialog(project.is_open())
		"act_project_render":
			var rp := projflow._save_render()
			_set_status("Render zapisany: " + rp if rp != "" else "Nie zapisano renderu (brak projektu lub modelu).")
		"act_project_open_dir":
			if project.is_open():
				OS.shell_open(project.dir)
			else:
				_set_status("Najpierw wskaż folder projektu.")
		"act_gpt_prompt":
			gpt._show_gpt_prompt()
		"act_export_glb":
			exporter._export_glb()
		"act_export_gltf":
			exporter._export_gltf()
		"act_export_t3d":
			exporter._export_t3d()
		"act_open_exports":
			OS.shell_open(exporter._exports_dir())
		"act_roof_from_tex":
			_apply_roof_from_texture()
		"act_roof_editor":
			roofed.open()
		"act_roof_custom":
			roofed.open_custom()
		"act_roof_simple":
			roofed.open_simple()
		"act_chimney_editor":
			chimneys.open()
		"act_tex_clear":
			mapping.rectified = {}
			settings.set_value("tex_panels", "")
			settings.set_value("tex_source", "")
			settings.set_value("tex_enabled", false)
		"act_tex_preview":
			atlasflow._show_slice_preview()
		"act_tex_panels":
			atlasflow.open_panel_editor()
		"act_tex_import":
			atlasflow._open_import_dialog()
		"act_tex_open_dir":
			var dirs := atlasflow._library_dirs()
			if dirs.is_empty():
				_set_status("Biblioteka zdjęć jest wyłączona.")
			else:
				OS.shell_open(dirs[0])
		"act_tex_random":
			settings.set_value("tex_variant", randi() % 100)
		"act_tex_export_normal":
			atlasflow._export_normals()
		"act_tex_next":
			settings.set_value("tex_variant", (settings.i("tex_variant") + 1) % 100)
		"act_cam_reset":
			rig._reset_camera()
		"act_src_import":
			_on_load_pressed()
		"act_src_sample":
			_create_sample_building()
		"act_svc_test":
			_on_diag_pressed()
		"act_cache_clear":
			var n := geo.cache.clear()
			geo.reset_cache()
			var st := geo.cache.stats()
			_set_status("Cache Geoportalu wyczyszczony (%d plików). Pozostało: %d." % [n, int(st["files"])])
		"act_settings_save":
			if settings.save():
				_set_status("Zapisano ustawienia: " + settings.save_path_global())
			else:
				_set_status("Nie udało się zapisać ustawień.")
		"act_settings_reset_all":
			confirm_dialog.popup_centered()


## Pushes every view_* setting into the 3D scene. The grid is only rebuilt when asked to.
func _apply_view(rebuild_grid: bool) -> void:
	if subviewport == null:
		return
	var solid := settings.s("view_bg_mode") == "solid"
	env.background_mode = Environment.BG_COLOR if solid else Environment.BG_SKY
	env.background_color = settings.c("view_bg_color")
	env.ambient_light_color = settings.c("view_ambient_color")
	env.ambient_light_energy = settings.f("view_ambient_energy")
	sun.rotation_degrees = Vector3(-settings.f("view_sun_altitude"), settings.f("view_sun_azimuth"), 0.0)
	sun.light_energy = settings.f("view_sun_energy")
	sun.shadow_enabled = settings.b("view_shadows")
	match settings.i("view_msaa"):
		2: subviewport.msaa_3d = Viewport.MSAA_2X
		4: subviewport.msaa_3d = Viewport.MSAA_4X
		8: subviewport.msaa_3d = Viewport.MSAA_8X
		_: subviewport.msaa_3d = Viewport.MSAA_DISABLED
	camera.fov = settings.f("view_cam_fov")
	var gs := float(settings.i("view_ground_size"))
	(ground.mesh as PlaneMesh).size = Vector2(gs, gs)
	ground_mat.albedo_color = settings.c("view_ground_color")
	ground.visible = settings.b("view_show_ground")
	grid_mesh.visible = settings.b("view_show_grid")
	subviewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	if rebuild_grid or grid_mesh.mesh == null:
		_rebuild_grid()
	_apply_visibility()
	rig._update_camera_transform()


## Edge / vertex overlay (view tab); rebuilt from the current model meshes.
func update_edge_overlay() -> void:
	if is_instance_valid(building_root):
		EdgeOverlay.apply(building_root, settings)


func _rebuild_grid() -> void:
	var half := float(settings.i("view_grid_extent"))
	var step := maxf(settings.f("view_grid_step"), 0.1)
	var n := maxi(int(floor(half / step)), 1)
	var extent := n * step
	var base := settings.c("view_grid_color")
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-n, n + 1):
		var pos := k * step
		im.surface_set_color(base.lightened(0.5) if k == 0 else base)
		im.surface_add_vertex(Vector3(pos, -0.02, -extent))
		im.surface_add_vertex(Vector3(pos, -0.02, extent))
		im.surface_add_vertex(Vector3(-extent, -0.02, pos))
		im.surface_add_vertex(Vector3(extent, -0.02, pos))
	im.surface_end()
	grid_mesh.mesh = im


func _apply_visibility() -> void:
	if not is_instance_valid(building_root):
		return
	for child in building_root.get_children():
		var n := String(child.name)
		if n.begins_with("Walls"):
			(child as Node3D).visible = settings.b("view_show_walls")
		elif n.begins_with("Roof") or n.begins_with("Chimney"):
			(child as Node3D).visible = settings.b("view_show_roof")


# ================================================================== Geoportal map

func _world_to_screen(w: Vector2) -> Vector2:
	return Vector2((w.x - map_center.x) / map_mpp, -(w.y - map_center.y) / map_mpp) + map_canvas.size * 0.5


func _screen_to_world(s: Vector2) -> Vector2:
	var d := s - map_canvas.size * 0.5
	return Vector2(map_center.x + d.x * map_mpp, map_center.y - d.y * map_mpp)


# ================================================================== Export (glTF + meta)

func _go_to_latlon(lat: float, lon: float) -> void:
	coord_edit.text = "%.4f, %.4f" % [lat, lon]
	map_center = GeoportalClient.lonlat_to_2180(lon, lat)
	map_mpp = settings.f("map_start_mpp")
	tabs.current_tab = 0
	_refresh_map()


func _on_goto_pressed() -> void:
	var txt := coord_edit.text.replace(";", ",").replace("°", "")
	var parts := txt.split(",", false)
	if parts.size() < 2:
		parts = txt.split(" ", false)
	if parts.size() < 2:
		_set_status("Podaj współrzędne jako: szerokość, długość (z kropką dziesiętną).")
		return
	var a := parts[0].strip_edges().to_float()
	var b := parts[1].strip_edges().to_float()
	var lat := maxf(a, b)   # in Poland latitude (49-55) is always larger than longitude (14-24)
	var lon := minf(a, b)
	if lat < 48.0 or lat > 56.0 or lon < 13.0 or lon > 25.0:
		_set_status("Współrzędne poza Polską - oczekiwano np. 52.2297, 21.0122.")
		return
	map_center = GeoportalClient.lonlat_to_2180(lon, lat)
	map_mpp = settings.f("map_start_mpp")
	tabs.current_tab = 0
	_refresh_map()


func _on_diag_pressed() -> void:
	_set_status("Testuję usługi Geoportalu…")
	var report: String = await geo.diagnose()
	diag_lines.clear()
	diag_label.text = report
	_set_status("Test usług zakończony (wynik na dole panelu bocznego).")


func _refresh_map() -> void:
	if map_busy:
		map_pending = true
		return
	if map_canvas.size.x < 32.0 or map_canvas.size.y < 32.0:
		return
	map_busy = true
	map_pending = false
	var half_m := map_canvas.size * 0.5 * map_mpp
	var bbox := Rect2(map_center - half_m, half_m * 2.0)

	if settings.b("map_use_ortho"):
		_set_status("Pobieram ortofotomapę…")
		var mosaic: Dictionary = await geo.fetch_basemap_tiled(bbox, map_mpp)
		map_ortho_failed = mosaic.is_empty()
		if not mosaic.is_empty():
			var mimg: Image = mosaic["image"]
			map_image = ImageTexture.create_from_image(mimg)
			map_image_rect = mosaic["rect"]
		else:
			map_image = null
		map_canvas.queue_redraw()
	else:
		map_ortho_failed = false

	if map_mpp <= settings.f("map_building_max_mpp"):
		_set_status("Pobieram obrysy budynków (EGiB)…")
		var found: Array = await geo.fetch_buildings_cached(bbox)
		map_buildings = found
		map_selected = -1
		_update_building_label()
		var msg := "Budynków w widoku: %d. Kliknij budynek, aby go wybrać." % found.size()
		if found.is_empty():
			msg += " Brak obrysów – sprawdź połączenie lub użyj „Testuj usługi”."
		if map_ortho_failed:
			msg += " Ortofotomapa niedostępna."
		_set_status(msg)
	else:
		map_buildings = []
		map_selected = -1
		_update_building_label()
		_set_status("Przybliż mapę (kółko myszy), aby zobaczyć obrysy budynków.")

	map_canvas.queue_redraw()
	map_busy = false
	if map_pending:
		_refresh_map()


func _on_map_draw() -> void:
	var sz := map_canvas.size
	map_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color("#0b0f15"))
	if map_image != null:
		var tl := _world_to_screen(Vector2(map_image_rect.position.x, map_image_rect.end.y))
		var br := _world_to_screen(Vector2(map_image_rect.end.x, map_image_rect.position.y))
		map_canvas.draw_texture_rect(map_image, Rect2(tl, br - tl), false)
	var line_w := settings.f("map_line_width")
	var col_line := settings.c("map_color_outline")
	var col_sel := settings.c("map_color_selected")
	var col_fill := col_sel
	col_fill.a = settings.f("map_fill_alpha")
	var sel_now := _selected_indices()
	for idx in range(map_buildings.size()):
		var ring: PackedVector2Array = map_buildings[idx]["ring"]
		var screen := PackedVector2Array()
		for w in ring:
			screen.append(_world_to_screen(w))
		var selected := idx in sel_now
		if selected and not Geometry2D.triangulate_polygon(screen).is_empty():
			map_canvas.draw_colored_polygon(screen, col_fill)
		var closed := screen.duplicate()
		closed.append(screen[0])
		map_canvas.draw_polyline(closed, col_sel if selected else col_line, line_w * 2.0 if selected else line_w)
	var font := ThemeDB.fallback_font
	if map_ortho_failed and map_image == null and not map_busy:
		map_canvas.draw_string(font, Vector2(24, 40), "Brak podkładu z Geoportalu – sprawdź połączenie z internetem lub użyj „Testuj usługi” w panelu.", HORIZONTAL_ALIGNMENT_LEFT, sz.x - 48.0, 16, Color("#ffb347"))
	map_canvas.draw_string(font, Vector2(8, sz.y - 8), "Dane: GUGiK / Geoportal.gov.pl   |   %.2f m/px" % map_mpp, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))


func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				map_pressing = true
				map_moved = false
				map_press_pos = mb.position
			else:
				map_pressing = false
				if map_moved:
					_refresh_map()
				else:
					_pick_building(mb.position, mb.ctrl_pressed or mb.shift_pressed)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_mpp = maxf(map_mpp / settings.f("map_zoom_step"), settings.f("map_mpp_min"))
			map_canvas.queue_redraw()
			map_timer.start()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_mpp = minf(map_mpp * settings.f("map_zoom_step"), settings.f("map_mpp_max"))
			map_canvas.queue_redraw()
			map_timer.start()
	elif event is InputEventMouseMotion and map_pressing:
		var mm := event as InputEventMouseMotion
		if not map_moved and mm.position.distance_to(map_press_pos) > 4.0:
			map_moved = true
		if map_moved:
			map_center += Vector2(-mm.relative.x, mm.relative.y) * map_mpp
			map_canvas.queue_redraw()


func _bkey(b: Dictionary) -> String:
	var ring: PackedVector2Array = b["ring"]
	return "%.2f,%.2f,%d" % [ring[0].x, ring[0].y, ring.size()]


## Indices (into map_buildings) of everything currently selected.
func _selected_indices() -> Array:
	var out: Array = []
	for idx in range(map_buildings.size()):
		if _bkey(map_buildings[idx]) in map_sel_keys:
			out.append(idx)
	if map_selected >= 0 and map_selected < map_buildings.size() and not (map_selected in out):
		out.append(map_selected)
	return out


func _pick_building(screen_pos: Vector2, additive := false) -> void:
	var w := _screen_to_world(screen_pos)
	var best := -1
	var best_area := INF
	for idx in range(map_buildings.size()):
		var ring: PackedVector2Array = map_buildings[idx]["ring"]
		if Geometry2D.is_point_in_polygon(w, ring):
			var area: float = _ring_stats(ring)["area"]
			if area < best_area:
				best_area = area
				best = idx
	if additive:
		if best >= 0:
			var k := _bkey(map_buildings[best])
			if k in map_sel_keys:
				map_sel_keys.erase(k)
				map_selected = -1 if map_selected == best else map_selected
			else:
				map_sel_keys.append(k)
				map_selected = best
	else:
		map_sel_keys.clear()
		if best >= 0:
			map_sel_keys.append(_bkey(map_buildings[best]))
		map_selected = best
	_update_building_label()
	map_canvas.queue_redraw()


## Smallest distance between the outlines of two polygons (0 when they overlap).
func _poly_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for pair in [[a, b], [b, a]]:
		var p: PackedVector2Array = pair[0]
		var q: PackedVector2Array = pair[1]
		for v in p:
			if Geometry2D.is_point_in_polygon(v, q):
				return 0.0
			for i in range(q.size()):
				var c := Geometry2D.get_closest_point_to_segment(v, q[i], q[(i + 1) % q.size()])
				best = minf(best, v.distance_to(c))
	return best


func _on_add_neighbours() -> void:
	var sel := _selected_indices()
	if sel.is_empty():
		return
	var tol := settings.f("map_neighbor_tol")
	var added := 0
	for idx in range(map_buildings.size()):
		if idx in sel:
			continue
		var ring: PackedVector2Array = map_buildings[idx]["ring"]
		for s_idx in sel:
			if _poly_gap(map_buildings[s_idx]["ring"], ring) <= tol:
				map_sel_keys.append(_bkey(map_buildings[idx]))
				added += 1
				break
	for s_idx in sel:
		var k := _bkey(map_buildings[s_idx])
		if not (k in map_sel_keys):
			map_sel_keys.append(k)
	_update_building_label()
	map_canvas.queue_redraw()
	_set_status("Dodano %d sąsiednich części." % added if added > 0 else "Brak sąsiednich poligonów w odległości %.1f m." % tol)


func _update_building_label() -> void:
	if not projflow._project_ok():
		use_btn.disabled = true
		add_nb_btn.disabled = true
		building_label.text = "Najpierw wskaż folder projektu (przycisk „Projekt…” u góry). Zapisują się w nim dane z Geoportalu, tekstury i rendery."
		return
	var sel := _selected_indices()
	if sel.is_empty():
		use_btn.disabled = true
		add_nb_btn.disabled = true
		building_label.text = "Kliknij budynek na mapie (przeciągnij = przesuń, kółko = zoom). Ctrl/Shift + klik = dodaj kolejną część."
		return
	add_nb_btn.disabled = false
	var primary: int = map_selected if map_selected in sel else sel[0]
	var b: Dictionary = map_buildings[primary]
	var st := _ring_stats(b["ring"])
	var attrs: Dictionary = b["attrs"]
	var lines: Array[String] = []
	if sel.size() > 1:
		var total := 0.0
		for idx in sel:
			total += _ring_stats(map_buildings[idx]["ring"])["area"]
		lines.append("Zaznaczono części: %d (razem %.1f m²)" % [sel.size(), total])
		lines.append("Ostatnio kliknięta:")
	lines.append("Wybrany budynek: %.1f × %.1f m" % [st["length"], st["width"]])
	lines.append("Powierzchnia: %.1f m², obwód: %.1f m" % [st["area"], st["perimeter"]])
	var floors := _floors_from_attrs(attrs)
	if floors > 0:
		lines.append("Kondygnacje: %d → ściany ok. %.1f m" % [floors, floors * settings.f("model_floor_height")])
	var shown := 0
	for k in attrs.keys():
		var v := str(attrs[k])
		if v.length() <= 40 and shown < 6:
			lines.append("%s: %s" % [k, v])
			shown += 1
	building_label.text = "\n".join(lines)
	use_btn.disabled = not projflow._project_ok()


func _floors_from_attrs(attrs: Dictionary) -> int:
	for k in attrs.keys():
		var key := str(k)
		if key.contains("kondygn") and not key.contains("podziem"):
			var n := int(str(attrs[k]))
			if n > 0 and n < 60:
				return n
	return 0


func _on_use_building_pressed() -> void:
	if not projflow._project_ok():
		projflow._show_project_dialog(false, "Najpierw wskaż folder projektu.")
		return
	var sel := _selected_indices()
	if sel.is_empty():
		return
	var items: Array = []
	for idx in sel:
		var bld: Dictionary = map_buildings[idx]
		var ring: PackedVector2Array = bld["ring"]
		var raw: Array = []
		for p in ring:
			raw.append([p.x, p.y])
		raw.append([ring[0].x, ring[0].y])
		items.append({
			"raw": raw, "floors": _floors_from_attrs(bld["attrs"]),
			"area": _ring_stats(ring)["area"], "wall_h": -1.0, "roof": "auto", "roof_h": -1.0,
		})
	items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["area"] > y["area"])   # biggest = main body
	current_floors = items[0]["floors"]
	faces.clear()       # surface corrections belong to one outline
	_select_face("")
	current_ring = []   # so the wall-height change below does not rebuild the previous building
	current_parts = []
	if current_floors > 0 and settings.b("model_use_floors"):
		_wall_internal = true
		settings.set_value("model_wall_height", current_floors * settings.f("model_floor_height"))
		_wall_internal = false
	if _build_parts(items, true):
		current_source = "Geoportal EGiB (EPSG:2180)" + (", %d części" % items.size() if items.size() > 1 else "")
		_update_info()
		tabs.current_tab = 1
		panel.select_tab("building", true)
		var chosen: Array = []
		current_attrs = []
		for idx in sel:
			chosen.append(map_buildings[idx])
			current_attrs.append(map_buildings[idx]["attrs"])
		projflow._write_geo("Geoportal EGiB (WFS)", chosen)
		_set_status("Zbudowano model z obrysu EGiB. Dach i wysokość są przybliżone.")



# ================================================================== Project folder

## Saves the project (when one is open) and the settings, then closes the application.
func quit_app() -> void:
	projflow._on_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		projflow._on_quit()


# ================================================================== Import (GeoJSON, optional)

func _on_load_pressed() -> void:
	if not projflow._project_ok():
		projflow._show_project_dialog(false, "Najpierw wskaż folder projektu.")
		return
	var p := settings.s("src_geojson_path").strip_edges()
	if p.is_empty():
		_set_status("Podaj ścieżkę do GeoJSON.")
		return
	var candidates: Array[String] = [p]
	if not (p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path()):
		candidates.append("res://" + p.trim_prefix("/"))
		candidates.append(ProjectSettings.globalize_path("res://").path_join(p))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			_load_geojson(candidate)
			tabs.current_tab = 1
			return
	_set_status("Nie znaleziono pliku: " + p)


func _load_geojson(path: String) -> void:
	faces.clear()
	_select_face("")
	if not FileAccess.file_exists(path):
		_create_sample_building()
		return
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		_set_status("Nie można otworzyć pliku.")
		return
	var text := fh.get_as_text()
	fh.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Nieprawidłowy GeoJSON.")
		return
	var features: Array = []
	var kind: String = parsed.get("type", "")
	if kind == "FeatureCollection":
		features = parsed.get("features", [])
	elif kind == "Feature":
		features = [parsed]
	elif kind == "Polygon" or kind == "MultiPolygon":
		features = [{"geometry": parsed}]
	else:
		_set_status("Oczekiwano GeoJSON Feature lub FeatureCollection.")
		return
	var found := _find_first_polygon(features)
	var polygon: Array = found["ring"]
	if polygon.is_empty():
		_set_status("Brak obsługiwanego Polygon/MultiPolygon w pliku.")
		return
	current_floors = 0
	# Optional heights from the file's properties (metres); applied before building.
	var props: Dictionary = found["props"]
	current_ring = []   # avoid rebuilding the previous building while settings change
	if props.has("wall_height"):
		_wall_internal = true
		settings.set_value("model_wall_height", float(props["wall_height"]))
		_wall_internal = false
	if props.has("roof_height"):
		_roof_internal = true   # a value from the file is not a manual override of the texture-based pitch
		settings.set_value("model_roof_height", float(props["roof_height"]))
		_roof_internal = false
	if _build_from_polygon(polygon, true):
		current_ring = polygon
		current_source = path.get_file()
		_update_info()
		panel.select_tab("building", true)
		var ring_pts: PackedVector2Array = PackedVector2Array()
		for q in polygon:
			ring_pts.append(Vector2(float(q[0]), float(q[1])))
		projflow._write_geo("plik GeoJSON: " + path, [{"ring": ring_pts, "attrs": props}])
		_set_status("Zaimportowano obrys z GeoJSON.")


## Returns {"ring": Array, "props": Dictionary} for the first Polygon / MultiPolygon feature.
func _find_first_polygon(features: Array) -> Dictionary:
	for feature in features:
		if typeof(feature) != TYPE_DICTIONARY:
			continue
		var geom = feature.get("geometry", {})
		if typeof(geom) != TYPE_DICTIONARY:
			continue
		var typ: String = geom.get("type", "")
		var coords = geom.get("coordinates", [])
		if typeof(coords) != TYPE_ARRAY:
			continue
		var props = feature.get("properties", {})
		if typeof(props) != TYPE_DICTIONARY:
			props = {}
		if typ == "Polygon" and coords.size() > 0:
			return {"ring": coords[0], "props": props}
		if typ == "MultiPolygon" and coords.size() > 0 and coords[0].size() > 0:
			return {"ring": coords[0][0], "props": props}
	return {"ring": [], "props": {}}


func _create_sample_building() -> void:
	faces.clear()
	_select_face("")
	current_floors = 0
	if _build_from_polygon(SAMPLE_RING, true):
		current_ring = SAMPLE_RING.duplicate()
		current_source = SAMPLE_SOURCE_NAME
		_update_info()
		_set_status("Załadowano przykładowy budynek w kształcie L.")


# ================================================================== Atlas

func _rebuild_current() -> void:
	if current_ring.is_empty() or current_parts.is_empty() or subviewport == null:
		return
	if _build_parts(current_parts, false):
		_update_info()
		parts_ui._sync_parts_ui()


func _tex_material(key: String, prefix: String = "") -> StandardMaterial3D:
	var cache_key := prefix + key
	if tex_materials.has(cache_key):
		return tex_materials[cache_key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = atlas.get_texture(key)
	m.roughness = settings.f("tex_roughness")
	m.metallic_specular = 0.1     # no silvery sky sheen over dark tiles
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if settings.b("tex_relief_enabled"):
		var is_roof := prefix.begins_with("roof")
		var strength := settings.f("tex_relief_roof") if is_roof else settings.f("tex_relief_wall")
		if strength > 0.001:
			var relief := atlas.get_relief(key, strength, settings.f("tex_relief_detail"),
				settings.f("tex_relief_smooth"), settings.b("tex_relief_invert"))
			if not relief.is_empty():
				m.normal_enabled = true
				m.normal_texture = relief["normal"]
				m.normal_scale = 1.0
				if settings.b("tex_parallax"):
					m.heightmap_enabled = true
					m.heightmap_texture = relief["height"]
					m.heightmap_scale = settings.f("tex_parallax_scale") * 100.0
					m.heightmap_deep_parallax = false
	tex_materials[cache_key] = m
	return m


## Underside and rim of a textured roof: the covering's average colour, darkened (not the plain-roof blue-grey).
func _roof_edge_material(key: String) -> StandardMaterial3D:
	var ck := "roofedge:" + key
	if tex_materials.has(ck):
		return tex_materials[ck]
	var m := StandardMaterial3D.new()
	var im: Image = atlas.region(key)["img"].duplicate()
	im.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	m.albedo_color = im.get_pixel(0, 0) * 0.7
	m.albedo_color.a = 1.0
	m.roughness = 0.95
	m.metallic_specular = 0.1
	tex_materials[ck] = m
	return m


func _use_textures() -> bool:
	return settings.b("tex_enabled") and atlas.loaded


## Region chosen in the sidebar for a slot, or "" when set to automatic / not in the atlas.
func _forced_region(slot: String) -> String:
	if slot.begins_with("tex_long_") or slot.begins_with("tex_gable_"):
		var all_key := settings.s("tex_wall_all")
		if all_key != "auto" and atlas.regions.has(all_key):
			return all_key
	var k := settings.s(slot)
	return k if k != "auto" and atlas.regions.has(k) else ""


# ================================================================== Surface corrections (click a plane)

## Picture of a surface after the user's corrections: another region and/or a cut-out of it.
func _face_region(key: String, fid: String) -> String:
	if fid == "" or not _use_textures():
		return key
	var r: String = faces.get_value(fid, "region")
	if r != "" and atlas.regions.has(r):
		key = r
	if key == "":
		return key
	var c: Array = faces.get_value(fid, "crop")
	if c != FaceStore.DEFAULTS["crop"]:
		key = atlas.crop_key(key, c)
	return key


## Copy of the base material with the user's colour / gloss / relief corrections for one surface.
func _face_material(base: StandardMaterial3D, tag: String, fid: String) -> StandardMaterial3D:
	var sig := "%s#%d#%s" % [tag, base.get_instance_id(), faces.material_signature(fid)]
	if face_materials.has(sig):
		return face_materials[sig]
	var m := base.duplicate() as StandardMaterial3D
	m.albedo_color = base.albedo_color * Color.html(str(faces.get_value(fid, "tint")))
	var v: float = faces.get_value(fid, "rough")
	if v >= 0.0:
		m.roughness = v
	v = faces.get_value(fid, "metal")
	if v >= 0.0:
		m.metallic = v
	v = faces.get_value(fid, "spec")
	if v >= 0.0:
		m.metallic_specular = v
	v = faces.get_value(fid, "normal")
	if v >= 0.0 and m.normal_enabled:
		m.normal_scale = v
	if bool(faces.get_value(fid, "light")):
		m.emission_enabled = true          # preview of a lit part (the export marks it emissive_light)
		m.emission = Color(1.0, 0.92, 0.7)
		m.emission_energy_multiplier = 0.8
		if m.albedo_texture != null:
			m.emission_texture = m.albedo_texture
	face_materials[sig] = m
	return m


func _on_faces_changed(_id: String) -> void:
	save_timer.start()
	if _faces_dirty:
		return
	_faces_dirty = true
	_apply_faces.call_deferred()


func _apply_faces() -> void:
	_faces_dirty = false
	_rebuild_current()
	if selected_face != "":
		face_panel.update_info(face_info(selected_face))


## Which surface lies under a point of the 3D view ("" = none or not editable, e.g. the underside of a roof).
func _pick_face(pos: Vector2) -> String:
	if not is_instance_valid(building_root) or not is_instance_valid(camera):
		return ""
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var best := INF
	var best_id := ""
	for mi in building_root.get_children():
		if not (mi is MeshInstance3D) or not mi.has_meta("pick_tris"):
			continue
		var inv := (mi as MeshInstance3D).global_transform.affine_inverse()
		var lf: Vector3 = inv * from
		var ld: Vector3 = (inv.basis * dir).normalized()
		var tris: PackedVector3Array = mi.get_meta("pick_tris")
		var ids: PackedStringArray = mi.get_meta("pick_ids")
		for ti in range(ids.size()):
			var hit: Variant = Geometry3D.ray_intersects_triangle(lf, ld, tris[ti * 3], tris[ti * 3 + 1], tris[ti * 3 + 2])
			if hit != null:
				var dist := lf.distance_to(hit)
				if dist < best:
					best = dist
					best_id = ids[ti]
	return best_id


func _select_face(fid: String) -> void:
	selected_face = fid
	_update_highlight()
	if fid == "":
		face_panel.visible = false
	else:
		face_panel.show_face(fid, face_info(fid))
	rig._place_preset_bar()


## Translucent overlay + outline on the picked surface.
func _update_highlight() -> void:
	if not is_instance_valid(building_root):
		return
	var old := building_root.get_node_or_null("FaceHighlight")
	if old != null:
		building_root.remove_child(old)
		old.queue_free()
	if selected_face == "":
		return
	var fill_v := PackedVector3Array()
	var fill_n := PackedVector3Array()
	var edges: Dictionary = {}
	for mi in building_root.get_children():
		if not mi.has_meta("pick_tris"):
			continue
		var tris: PackedVector3Array = mi.get_meta("pick_tris")
		var ids: PackedStringArray = mi.get_meta("pick_ids")
		for ti in range(ids.size()):
			if ids[ti] != selected_face:
				continue
			var a := tris[ti * 3]
			var b := tris[ti * 3 + 1]
			var c := tris[ti * 3 + 2]
			var n := (c - a).cross(b - a).normalized()
			for q in [a, b, c]:
				fill_v.append(q + n * 0.02)
				fill_n.append(n)
			for e in [[a, b], [b, c], [c, a]]:
				var k1 := _vkey(e[0])
				var k2 := _vkey(e[1])
				var ek := k1 + "|" + k2 if k1 < k2 else k2 + "|" + k1
				edges[ek] = [e[0] + n * 0.025, e[1] + n * 0.025, int((edges.get(ek, [0, 0, 0]) as Array)[2]) + 1]
	if fill_v.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = fill_v
	arr[Mesh.ARRAY_NORMAL] = fill_n
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(0.2, 0.75, 1.0, 0.25)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, fm)
	var lines := PackedVector3Array()
	for ek in edges.keys():
		if int(edges[ek][2]) == 1:       # a border edge belongs to one triangle only
			lines.append(edges[ek][0])
			lines.append(edges[ek][1])
	if not lines.is_empty():
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = lines
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.85, 0.2)
		lm.no_depth_test = true
		mesh.surface_set_material(1, lm)
	var hi := MeshInstance3D.new()
	hi.name = "FaceHighlight"
	hi.mesh = mesh
	hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	building_root.add_child(hi)


static func _vkey(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 500.0), roundi(v.y * 500.0), roundi(v.z * 500.0)]


## What the correction panel needs to know about a surface.
func face_info(fid: String) -> Dictionary:
	var part := int(fid.get_slice(":", 0).trim_prefix("p"))
	var is_roof := ":roof" in fid
	var info := {"id": fid, "kind": "roof" if is_roof else "wall", "part": part, "textured": _use_textures(),
		"regions": [], "has_normal": settings.b("tex_relief_enabled") and _use_textures(),
		"defaults": {"rough": settings.f("tex_roughness"), "metal": 0.0, "spec": 0.5, "normal": 1.0},
		"title": "", "size": Vector2(4.0, 3.0), "wall_h": 0.0, "roof_h": 0.0, "parts": last_rt.size()}
	var regs: Array = atlas.regions.keys()
	regs.sort()
	info["regions"] = regs
	info["preview"] = _face_preview(fid)
	if face_geo.has(fid):
		info["base_key"] = _sector_of(str(face_geo[fid]["key"]))
	if part < last_rt.size():
		var P: Dictionary = last_rt[part]
		info["wall_h"] = float(P["wall_h"])
		info["roof_h"] = float(P["roof_h"])
		var part_name := "bryła główna" if part == 0 else "dobudówka %d" % part
		if is_roof:
			var bb: Rect2 = P["bb"]
			info["size"] = bb.size
			info["title"] = "Dach – połać %s (%s)" % [fid.right(1), part_name]
		else:
			var pts: PackedVector2Array = P["pts"]
			var e := int(fid.get_slice(":w", 1))
			var length := pts[e].distance_to(pts[(e + 1) % pts.size()])
			info["size"] = Vector2(length, float(P["wall_h"]))
			info["title"] = "Ściana %d · %.1f m (%s)" % [e + 1, length, part_name]
	return info


## "S3" for the key "S3" and for a crop "crop|S3|0.1,..."; "" otherwise.
func _sector_of(key: String) -> String:
	if key.begins_with("crop|"):
		return key.get_slice("|", 1)
	return key


## ---- Mapping editor (full window) + straightened photos ----------------------------------------

## ---- GPT description (materials, openings) -------------------------------------------------

## Every pop-up window can be closed with Esc and with a visible button (the title-bar X is easy to lose).
func _closable(win: Window, host: Control) -> void:
	win.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			win.queue_free())
	var b := Button.new()
	b.text = "Zamknij (Esc)"
	b.custom_minimum_size = Vector2(130, 34)
	b.pressed.connect(win.queue_free)
	if host is Container:
		host.add_child(b)
	else:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -142.0
		b.offset_right = -10.0
		b.offset_top = 10.0
		b.offset_bottom = 44.0
		host.add_child(b)


## Picture + window of a surface for the panel preview (see FacePreview).
func _face_preview(fid: String) -> Dictionary:
	if not _use_textures() or not face_geo.has(fid) or str(face_geo[fid]["key"]) in ["", "plain"]:
		return {"message": "Ta powierzchnia nie ma tekstury (kolor zastępczy)."}
	var g: Dictionary = face_geo[fid]
	var tex := atlas.get_texture(str(g["key"]))
	if tex == null:
		return {"message": "Brak obrazu dla tej powierzchni."}
	var r: Rect2 = g["uv"]
	var mp: Dictionary = faces.mapping(fid)
	var poly := PackedVector2Array()
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		poly.append(FaceStore.uv_transform(c, g["pivot"], g["pw"], g["ph"], mp["off"], mp["scale"], mp["rot"], mp["flip"]))
	var pv := {"tex": tex, "poly": poly}
	return pv


## Raises / lowers the eaves (wall height) and the ridge (roof height) of one part by the given metres.
func nudge_part(part: int, d_wall: float, d_roof: float) -> void:
	if part < 0 or part >= last_rt.size():
		return
	var P: Dictionary = last_rt[part]
	if d_wall != 0.0:
		parts_ui._on_part_wall(part, maxf(float(P["wall_h"]) + d_wall, 0.5))
	if d_roof != 0.0 and part < last_rt.size():
		parts_ui._on_part_roof_h(part, maxf(float(last_rt[part]["roof_h"]) + d_roof, 0.0))
	if selected_face != "":
		face_panel.show_face(selected_face, face_info(selected_face))


## Exact heights typed into the panel.
func set_part_heights(part: int, wall_h: float, roof_h: float) -> void:
	if part < 0 or part >= last_rt.size():
		return
	if absf(float(last_rt[part]["wall_h"]) - wall_h) > 0.001:
		parts_ui._on_part_wall(part, maxf(wall_h, 0.5))
	if part < last_rt.size() and absf(float(last_rt[part]["roof_h"]) - roof_h) > 0.001:
		parts_ui._on_part_roof_h(part, maxf(roof_h, 0.0))
	if selected_face != "":
		face_panel.show_face(selected_face, face_info(selected_face))


# ================================================================== Geometry

func _bounds(pts: PackedVector2Array) -> Rect2:
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)


## Angle of the edge direction that gives the minimum-area oriented bounding box.
func _obb_angle(pts: PackedVector2Array) -> float:
	var best_area := INF
	var best_ang := 0.0
	for i in range(pts.size()):
		var e := pts[(i + 1) % pts.size()] - pts[i]
		if e.length() < 0.01:
			continue
		var ang := e.angle()
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			var r := p.rotated(-ang)
			mn = Vector2(minf(mn.x, r.x), minf(mn.y, r.y))
			mx = Vector2(maxf(mx.x, r.x), maxf(mx.y, r.y))
		var area := (mx.x - mn.x) * (mx.y - mn.y)
		if area < best_area - 1e-6:
			best_area = area
			best_ang = ang
	return best_ang


func _ring_stats(ring: PackedVector2Array) -> Dictionary:
	var area := 0.0
	var per := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
		per += a.distance_to(b)
	var ang := _obb_angle(ring)
	var rot := PackedVector2Array()
	for p in ring:
		rot.append(p.rotated(-ang))
	var bb := _bounds(rot)
	return {
		"area": absf(area) * 0.5,
		"perimeter": per,
		"length": maxf(bb.size.x, bb.size.y),
		"width": minf(bb.size.x, bb.size.y),
	}


## Raw rings -> metric, de-duplicated, counter-clockwise footprints in ONE shared frame, so parts
## of one building keep their relative positions. With "align" on, the minimum-area bounding box
## of the FIRST (main) ring is aligned with the axes (long side along X). North maps to -Z.
## Returns one PackedVector2Array per input ring (empty when a ring is unusable).
func _prepare_parts(rings: Array) -> Array:
	var raws: Array = []
	var all := PackedVector2Array()
	for ring in rings:
		var raw := PackedVector2Array()
		for c in ring:
			if typeof(c) != TYPE_ARRAY or c.size() < 2:
				continue
			raw.append(Vector2(float(c[0]), float(c[1])))
		raws.append(raw)
		all.append_array(raw)
	if all.size() < 3:
		return []

	var rb := _bounds(all)
	var center := rb.get_center()
	var span := rb.size
	current_is_geographic = (
		absf(rb.position.x) <= 180.0 and absf(rb.end.x) <= 180.0
		and absf(rb.position.y) <= 90.0 and absf(rb.end.y) <= 90.0
		and span.x < 1.0 and span.y < 1.0
	)
	var m_per_x := 1.0
	var m_per_y := 1.0
	if current_is_geographic:
		m_per_y = 111132.0
		m_per_x = 111320.0 * cos(deg_to_rad(center.y))

	var out: Array = []
	for raw in raws:
		var pts := PackedVector2Array()
		for p in raw:
			var q := Vector2((p.x - center.x) * m_per_x, -(p.y - center.y) * m_per_y)
			if pts.is_empty() or pts[pts.size() - 1].distance_to(q) >= 0.01:
				pts.append(q)
		while pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01:
			pts.remove_at(pts.size() - 1)
		if pts.size() < 3:
			pts = PackedVector2Array()
		elif _poly_area(pts) < 0.0:
			pts.reverse()
		out.append(pts)
	if out[0].size() < 3:
		return []

	footprint_rotation_deg = 0.0
	if settings.b("model_align_obb"):
		var ang := _obb_angle(out[0])
		var rotated0 := PackedVector2Array()
		for p in out[0]:
			rotated0.append(p.rotated(-ang))
		var bb0 := _bounds(rotated0)
		if bb0.size.y > bb0.size.x:
			ang += PI * 0.5
		for i in range(out.size()):
			for k in range(out[i].size()):
				out[i][k] = out[i][k].rotated(-ang)
		footprint_rotation_deg = rad_to_deg(ang)
	footprint_src_center = center
	var union := PackedVector2Array()
	for pts in out:
		union.append_array(pts)
	var c2 := _bounds(union).get_center()
	footprint_local_center = c2
	for i in range(out.size()):
		for k in range(out[i].size()):
			out[i][k] -= c2
	return out


func _prepare_footprint(ring: Array) -> PackedVector2Array:
	var r := _prepare_parts([ring])
	return r[0] if not r.is_empty() else PackedVector2Array()


## Vectorisers leave small gaps between neighbouring polygons: pull vertices that lie within `tol`
## of another part's outline onto it, so shared walls really coincide.
func _heal_parts(parts: Array, tol: float) -> void:
	if tol <= 0.0 or parts.size() < 2:
		return
	for i in range(parts.size()):
		for k in range(parts[i].size()):
			var v: Vector2 = parts[i][k]
			var best := tol
			var target := v
			for j in range(parts.size()):
				if j == i:
					continue
				var q: PackedVector2Array = parts[j]
				for e in range(q.size()):
					var c := Geometry2D.get_closest_point_to_segment(v, q[e], q[(e + 1) % q.size()])
					var d := v.distance_to(c)
					if d < best:
						best = d
						target = c
			parts[i][k] = target


## Resolves wall height / roof type / roof height / ridge of every part from the settings and the
## per-part overrides. The main body (index 0) follows the sidebar; annexes derive from it.
func _resolve_parts(parts: Array, pts_list: Array) -> Array:
	var rt: Array = []
	var floor_h := settings.f("model_floor_height")
	for i in range(parts.size()):
		var pts: PackedVector2Array = pts_list[i]
		var bb := _bounds(pts)
		var long_is_x := bb.size.x >= bb.size.y
		var along_x := long_is_x if settings.s("model_ridge_axis") == "long" else not long_is_x
		var P := {
			"index": i, "pts": pts, "bb": bb, "part": parts[i], "covers": [],
			"ridge_along_x": along_x,
			"ridge_mid": ((bb.position.y + bb.end.y) if along_x else (bb.position.x + bb.end.x)) * 0.5,
			"ridge_half": maxf((bb.size.y if along_x else bb.size.x) * 0.5, 0.001),
			"mode": "gable", "roof_kind": "gable", "shed_axis": 0, "shed_sign": 1,
			"shed_lo": 0.0, "shed_span": 1.0, "host": -1,
		}
		var pr: Dictionary = parts[i]
		if i == 0:
			P["wall_h"] = settings.f("model_wall_height")
			var tex_wall := _tex_wall_height(float(bb.size.x if along_x else bb.size.y))
			if tex_wall > 0.0:
				P["wall_h"] = tex_wall
				if absf(settings.f("model_wall_height") - tex_wall) > 0.005:
					_wall_internal = true
					settings.set_value("model_wall_height", tex_wall)
					_wall_internal = false
		elif float(pr.get("wall_h", -1.0)) > 0.0:
			P["wall_h"] = float(pr["wall_h"])
		else:
			var main_wall: float = rt[0]["wall_h"]
			var wh := main_wall * settings.f("model_annex_ratio")
			if int(pr.get("floors", 0)) > 0:
				wh = int(pr["floors"]) * floor_h
			if main_wall > 2.6:
				wh = minf(wh, main_wall - 0.3)
			P["wall_h"] = maxf(wh, 2.0)
		rt.append(P)

	# Which earlier (bigger) part does an annex lean against? The one with the longest shared wall.
	for i in range(1, rt.size()):
		var best_len := 0.5
		var P: Dictionary = rt[i]
		var pts: PackedVector2Array = P["pts"]
		for e in range(pts.size()):
			var a := pts[e]
			var b := pts[(e + 1) % pts.size()]
			var len := a.distance_to(b)
			if len < 0.5:
				continue
			var dir := (b - a) / len
			for j in range(i):
				var q: PackedVector2Array = rt[j]["pts"]
				for f in range(q.size()):
					var iv := _shared_interval(a, dir, len, q[f], q[(f + 1) % q.size()])
					if iv.y - iv.x > best_len:
						best_len = iv.y - iv.x
						P["host"] = j
						P["host_normal"] = Vector2(dir.y, -dir.x)   # outward normal of the annex edge

	var main_roof_h := 0.0 if settings.s("model_roof_type") == "flat" else settings.f("model_roof_height")
	if main_roof_h > 0.0 and settings.b("model_roof_from_tex"):
		var from_tex := _tex_roof_height(2.0 * float(rt[0]["ridge_half"]))
		if from_tex > 0.0:
			main_roof_h = snappedf(from_tex, 0.01)
			if absf(settings.f("model_roof_height") - main_roof_h) > 0.005:
				_roof_internal = true          # show the measured value in the slider without a second rebuild
				settings.set_value("model_roof_height", main_roof_h)
				_roof_internal = false
	rt_main_half = float(rt[0]["ridge_half"])
	var main_slope: float = main_roof_h / rt[0]["ridge_half"]
	for i in range(rt.size()):
		var P: Dictionary = rt[i]
		var pr: Dictionary = parts[i]
		var kind: String = str(pr.get("roof", "auto"))
		if i == 0:
			kind = "flat" if (kind == "auto" and settings.s("model_roof_type") == "flat") else (kind if kind != "auto" else "gable")
		elif kind == "auto":
			kind = "shed" if int(P["host"]) >= 0 else ("flat" if settings.s("model_roof_type") == "flat" else "gable")
		P["roof_kind"] = kind
		var bb: Rect2 = P["bb"]
		var rh := float(pr.get("roof_h", -1.0))
		if kind == "flat":
			P["roof_h"] = 0.0
		elif kind == "shed":
			P["mode"] = "shed"
			if int(P["host"]) >= 0:
				var n: Vector2 = P["host_normal"]
				P["shed_axis"] = 0 if absf(n.x) >= absf(n.y) else 1
				var comp := n.x if int(P["shed_axis"]) == 0 else n.y
				P["shed_sign"] = -1 if comp > 0.0 else 1    # high edge on the host side
			else:
				P["shed_axis"] = 1 if bb.size.y <= bb.size.x else 0
				P["shed_sign"] = 1
			var ax: int = P["shed_axis"]
			P["shed_lo"] = bb.position.x if ax == 0 else bb.position.y
			P["shed_span"] = maxf(bb.size.x if ax == 0 else bb.size.y, 0.5)
			if rh <= 0.0:
				rh = settings.f("model_annex_roof_height")
				if int(P["host"]) >= 0:
					rh = minf(rh, maxf(float(rt[int(P["host"])]["wall_h"]) - float(P["wall_h"]) - 0.1, 0.3))
			P["roof_h"] = rh
		else:
			if i == 0:
				P["roof_h"] = rh if rh > 0.0 else main_roof_h
			else:
				P["roof_h"] = rh if rh > 0.0 else main_slope * float(P["ridge_half"])
	_apply_roof_gen(rt)
	return rt


## Parts that have a generated roof (the "Dach" window) get their planes; the rest keeps the simple roof.
func _apply_roof_gen(rt: Array) -> void:
	var typ := settings.s("model_roof_type")
	var gens: Array = RoofGen.list_from_json(settings.s("model_roof_gen"))
	if typ == "custom":
		_apply_roof_custom(rt)
		return
	if typ == "hip" and not rt.is_empty() and str(rt[0]["roof_kind"]) == "gable":
		var has0 := false
		for g0 in gens:
			if int(g0.get("part", 0)) == 0:
				has0 = true
		if not has0:
			gens.append(RoofCustom.hip_gen(2.0 * float(rt[0]["ridge_half"]), float(rt[0]["roof_h"])))   # four slopes: both ends are hipped
	for gen in gens:
		var i := int(gen.get("part", 0))
		if i < 0 or i >= rt.size():
			continue
		var P: Dictionary = rt[i]
		if str(P["roof_kind"]) != "gable":
			continue
		var bb: Rect2 = P["bb"]
		var along_x: bool = P["ridge_along_x"]
		var span := 2.0 * float(P["ridge_half"])
		var pl := RoofGen.planes(gen, span, _left_is_pos(P), float(P["ridge_mid"]), along_x, float(P["wall_h"]),
			bb.position.x if along_x else bb.position.y, bb.end.x if along_x else bb.end.y)
		if pl.is_empty():
			continue
		P["mode"] = "planes"
		P["planes"] = pl
		P["roof_h"] = RoofGen.ridge_height(RoofGen.normalize(gen, span)["prof"])
		P["gen"] = gen


## The "Własny" roof of the main part: a plane from every sloped edge of the outline (see RoofCustom).
func _apply_roof_custom(rt: Array) -> void:
	if rt.is_empty() or str(rt[0]["roof_kind"]) != "gable":
		return
	var P: Dictionary = rt[0]
	var pts: PackedVector2Array = P["pts"]
	var cfg := RoofCustom.parse(settings.s("model_roof_custom"))
	if (cfg.get("slopes", []) as Array).size() != pts.size():
		cfg = {"slopes": RoofCustom.default_slopes(pts, float(P["roof_h"])), "cap": float(cfg.get("cap", 0.0))}
	var pl := RoofCustom.planes(pts, float(P["wall_h"]), cfg)
	if pl.is_empty():
		return
	P["mode"] = "planes"
	P["planes"] = pl
	P["roof_h"] = RoofCustom.rise(pts, pl, float(P["wall_h"]))


## A hand-set roof height while a generated / custom roof exists scales that roof instead of being ignored.
func _rescale_roof(new_h: float) -> bool:
	if last_rt.is_empty() or new_h <= 0.05:
		return false
	var cur := float(last_rt[0]["roof_h"])
	if cur <= 0.05:
		return false
	var f := new_h / cur
	var typ := settings.s("model_roof_type")
	if typ == "custom":
		var cfg := RoofCustom.parse(settings.s("model_roof_custom"))
		var sl: Array = cfg.get("slopes", [])
		if sl.is_empty():
			return false
		for i in range(sl.size()):
			if float(sl[i]) >= RoofCustom.MIN_DEG:
				sl[i] = snappedf(clampf(rad_to_deg(atan(tan(deg_to_rad(float(sl[i]))) * f)), RoofCustom.MIN_DEG, RoofCustom.MAX_DEG), 0.1)
		cfg["slopes"] = sl
		if float(cfg.get("cap", 0.0)) > 0.0:
			cfg["cap"] = float(cfg["cap"]) * f
		roof_apply_settings({"model_roof_custom": JSON.stringify(cfg), "model_roof_from_tex": false})
		return true
	var list: Array = RoofGen.list_from_json(settings.s("model_roof_gen"))
	for e in list:
		if int(e.get("part", 0)) == 0:
			for v in e["prof"]:
				(v as Array)[1] = float((v as Array)[1]) * f
			roof_apply_settings({"model_roof_gen": RoofGen.to_json(list), "model_roof_from_tex": false})
			return true
	return false


## True when the left end of the gable picture is model side A (t > 0).
func _left_is_pos(P: Dictionary) -> bool:
	var pts: PackedVector2Array = P["pts"]
	var along_x_ridge: bool = P["ridge_along_x"]
	for i in range(pts.size()):
		var a2 := pts[i]
		var b2 := pts[(i + 1) % pts.size()]
		var e := b2 - a2
		if e.length() < 0.5:
			continue
		var dir := e.normalized()
		var along_x := absf(dir.x) >= absf(dir.y)
		if along_x == along_x_ridge:
			continue
		var normal := Vector3(dir.y, 0.0, -dir.x)
		var side := (1 if normal.z > 0.0 else 0) if along_x else (1 if normal.x > 0.0 else 0)
		if side != 0:
			continue
		return ((b2.y if along_x_ridge else b2.x) - float(P["ridge_mid"])) > 0.0
	return true


var _roof_internal := false
var _wall_internal := false


## Wall height (m) from the proportions of the long-wall picture of a sheet (the photo knows the real shape,
## the register only a rough floor count), or -1.0. length = length of the long wall in metres.
func _tex_wall_height(length: float) -> float:
	if not settings.b("model_walls_from_tex") or not _use_textures() or not atlas.is_template:
		return -1.0
	var key := _forced_region("tex_long_a")
	if key == "":
		key = atlas.pick_key("facade_long", settings.i("tex_variant"))
	if key == "" or atlas.region(key).is_empty():
		return -1.0
	var asp := atlas.aspect(key)
	if asp < 0.3:
		return -1.0
	return clampf(snappedf(length / asp, 0.1), 2.0, 40.0)
var _roof_batch := false          # roof editor writes several settings, then rebuilds once


## Writes several roof settings with a single rebuild (used by the roof editor).
func roof_apply_settings(d: Dictionary) -> void:
	_roof_batch = true
	for k in d.keys():
		settings.set_value(k, d[k])
	_roof_batch = false
	_rebuild_current()


## Facts the roof editor needs: the gable picture, wall height, span and which side of the picture is model side A (t > 0).
func roof_gable_info() -> Dictionary:
	var out := {"key": "", "wall_h": settings.f("model_wall_height"), "roof_h": settings.f("model_roof_height"), "span": 8.0, "left_is_pos": true}
	if last_rt.is_empty():
		return out
	var P: Dictionary = last_rt[0]
	out["wall_h"] = float(P["wall_h"])
	out["roof_h"] = float(P["roof_h"])
	out["span"] = 2.0 * float(P["ridge_half"])
	if atlas.loaded:
		out["key"] = _gable_key()        # the picture is wanted even when the model is shown without textures
	var pts: PackedVector2Array = P["pts"]
	var along_x_ridge: bool = P["ridge_along_x"]
	for i in range(pts.size()):
		var a2 := pts[i]
		var b2 := pts[(i + 1) % pts.size()]
		var e := b2 - a2
		if e.length() < 0.5:
			continue
		var dir := e.normalized()
		var along_x := absf(dir.x) >= absf(dir.y)
		if along_x == along_x_ridge:
			continue                       # an eaves wall, not a gable
		var normal := Vector3(dir.y, 0.0, -dir.x)
		var side := (1 if normal.z > 0.0 else 0) if along_x else (1 if normal.x > 0.0 else 0)
		if side != 0:
			continue
		var t_left := (b2.y if along_x_ridge else b2.x) - float(P["ridge_mid"])   # picture's left end = the edge's end point
		out["left_is_pos"] = t_left > 0.0
		break
	return out
var rt_main_half := 1.0          # half span of the main body (the ridge shift setting is in metres of THIS body)


## Gable picture used on the front gable wall (the chosen one, else the automatic pick).
func _gable_key() -> String:
	var key := _forced_region("tex_gable_a")
	if key == "":
		key = atlas.pick_key("facade_gable", settings.i("tex_variant"))
	if key == "":
		for k in ["S3", "S4"]:       # a canvas laid out from sectors: the gables are S3 / S4 whatever the role guess was
			if atlas.regions.has(k):
				return k
	return key


## Roof height (m) measured from the roof outline visible in the gable photo, or -1.0.
## span = width of the gable wall; the photo's roof rise relative to its width gives the pitch.
func _tex_roof_height(span: float) -> float:
	if not _use_textures():
		return -1.0
	var key := _gable_key()
	if key == "":
		return -1.0
	var ratio := atlas.estimate_roof_ratio(key)
	return ratio * span if ratio > 0.0 else -1.0


## Overlap (in metres along edge a->b) with another edge that runs the opposite way, same line.
func _shared_interval(a: Vector2, dir: Vector2, len: float, c: Vector2, d: Vector2) -> Vector2:
	var tol := maxf(settings.f("model_snap_tol"), 0.05) * 0.8
	var cd := d - c
	if cd.length() < 0.05:
		return Vector2.ZERO
	if dir.dot(cd.normalized()) > -0.97:
		return Vector2.ZERO
	if absf(dir.cross(c - a)) > tol or absf(dir.cross(d - a)) > tol:
		return Vector2.ZERO
	var sc := (c - a).dot(dir)
	var sd := (d - a).dot(dir)
	var lo := maxf(0.0, minf(sc, sd))
	var hi := minf(len, maxf(sc, sd))
	return Vector2(lo, hi) if hi - lo > 0.1 else Vector2.ZERO


func _use_part(P: Dictionary) -> void:
	wall_h_cur = P["wall_h"]
	roof_h_cur = P["roof_h"]
	ridge_along_x = P["ridge_along_x"]
	ridge_half = P["ridge_half"]
	ridge_shift = 0.0
	if settings.b("model_roof_asym") and P["mode"] == "gable" and rt_main_half > 0.001:
		var frac := clampf(settings.f("model_roof_ridge_shift") / rt_main_half, -0.85, 0.85)
		ridge_shift = frac * ridge_half
	ridge_mid = float(P["ridge_mid"]) + ridge_shift
	half_pos = ridge_half - ridge_shift
	half_neg = ridge_half + ridge_shift
	roof_mode = P["mode"]
	roof_planes = P.get("planes", [])
	shed_axis = P["shed_axis"]
	shed_sign = P["shed_sign"]
	shed_lo = P["shed_lo"]
	shed_span = P["shed_span"]
	part_variant = int(P["index"])
	part_is_annex = int(P["host"]) >= 0


## Wall sections that touch another part are internal: record how high that neighbour covers them.
func _compute_covers(rt: Array) -> void:
	for i in range(rt.size()):
		var P: Dictionary = rt[i]
		var pts: PackedVector2Array = P["pts"]
		var covers: Array = []
		for e in range(pts.size()):
			var a := pts[e]
			var b := pts[(e + 1) % pts.size()]
			var len := a.distance_to(b)
			var list: Array = []
			if len > 0.05:
				var dir := (b - a) / len
				for j in range(rt.size()):
					if j == i:
						continue
					var q: PackedVector2Array = rt[j]["pts"]
					for f in range(q.size()):
						var iv := _shared_interval(a, dir, len, q[f], q[(f + 1) % q.size()])
						if iv.y > iv.x:
							_use_part(rt[j])
							var mid := a + dir * ((iv.x + iv.y) * 0.5)
							list.append([iv.x / len, iv.y / len, _top_y(mid)])
			covers.append(list)
		P["covers"] = covers


func _build_from_polygon(ring: Array, reset_view := true) -> bool:
	return _build_parts([{"raw": ring, "floors": 0, "wall_h": -1.0, "roof": "auto", "roof_h": -1.0}], reset_view)


func _build_parts(parts: Array, reset_view := true) -> bool:
	var rings: Array = []
	for p in parts:
		rings.append(p["raw"])
	var pts_list := _prepare_parts(rings)
	if pts_list.is_empty():
		_set_status("Nieprawidłowy obrys (potrzeba min. 3 różnych punktów).")
		return false
	# Parts with an unusable outline are dropped (the main one was checked above).
	for i in range(pts_list.size() - 1, 0, -1):
		if pts_list[i].size() < 3:
			pts_list.remove_at(i)
			parts.remove_at(i)
	_heal_parts(pts_list, settings.f("model_snap_tol"))
	face_geo = {}
	var rt := _resolve_parts(parts, pts_list)
	tex_main_wall_h = float(rt[0]["wall_h"])
	tex_main_roof_h = float(rt[0]["roof_h"])
	_compute_covers(rt)

	_clear_building()
	building_root = Node3D.new()
	building_root.name = "Building"
	subviewport.add_child(building_root)
	var union := PackedVector2Array()
	var top := 0.0
	var roof_failed := false
	for P in rt:
		_use_part(P)
		var suffix := "" if int(P["index"]) == 0 else "_%d" % (int(P["index"]) + 1)
		var walls := _build_walls(P["pts"], P["covers"])
		walls.name = "Walls" + suffix
		building_root.add_child(walls)
		var others: Array = []
		for Q in rt:
			if int(Q["index"]) != int(P["index"]):
				others.append(Q["pts"])
		var roof := _build_roof(P["pts"], others)
		if roof != null:
			roof.name = "Roof" + suffix
			building_root.add_child(roof)
		else:
			roof_failed = true
		union.append_array(P["pts"])
		top = maxf(top, float(P["wall_h"]) + float(P["roof_h"]))
	if roof_failed:
		_set_status("Nie udało się zbudować dachu (triangulacja obrysu nie powiodła się).")
	_use_part(rt[0])
	last_rt = rt
	chimneys.rebuild()
	_apply_visibility()
	_update_highlight()

	var bb := _bounds(union)
	current_bounds = AABB(Vector3(bb.position.x, 0.0, bb.position.y), Vector3(bb.size.x, top, bb.size.y))
	current_parts = parts
	current_ring = parts[0]["raw"]
	last_rt = rt
	if reset_view:
		rig._reset_camera()
	parts_ui._refresh_parts_ui_if_needed()
	return true


## Roof surface height of a part at several points (building coordinates): the chimneys and their editor stand on it.
func roof_y_batch(part: int, pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if last_rt.is_empty():
		return out
	_use_part(last_rt[clampi(part, 0, last_rt.size() - 1)])
	for p in pts:
		out.append(_top_y(p))
	_use_part(last_rt[0])
	return out


## {has: bool (a ridge line exists), along_x: bool, mid: float (coordinate of the ridge across its direction)}.
func roof_ridge_info(part: int) -> Dictionary:
	if last_rt.is_empty():
		return {"has": false, "along_x": true, "mid": 0.0}
	_use_part(last_rt[clampi(part, 0, last_rt.size() - 1)])
	var out := {"has": _has_ridge() or roof_mode == "planes", "along_x": ridge_along_x, "mid": ridge_mid}
	_use_part(last_rt[0])
	return out


func _roof_slope() -> float:
	return roof_h_cur / (shed_span if roof_mode == "shed" else ridge_half)


## Distance from the ridge to the eave on the side p lies on (asymmetric roofs have two different ones).
func _half_at(p: Vector2) -> float:
	return maxf(half_pos if _ridge_t(p) >= 0.0 else half_neg, 0.001)


## Slope (rise / run) of the roof surface at p.
func _roof_slope_at(p: Vector2) -> float:
	if roof_mode == "shed":
		return _roof_slope()
	return roof_h_cur / _half_at(p)


## Coordinate along the roof's fall line, measured from the high edge / ridge (positive = lower).
func _roof_down(p: Vector2) -> float:
	if roof_mode == "shed":
		var c := p.x if shed_axis == 0 else p.y
		return (c - shed_lo) if shed_sign > 0 else (shed_lo + shed_span - c)
	return _half_at(p) - absf(_ridge_t(p))


## Roof surface height. Linear in the distance from the ridge / high edge, so it simply keeps going
## (below the eave line) across the overhang.
func _top_y(p: Vector2) -> float:
	if roof_mode == "planes":
		return RoofGen.height_at(roof_planes, p.x, p.y)
	if roof_mode == "shed":
		return wall_h_cur + roof_h_cur - _roof_slope() * _roof_down(p)
	return wall_h_cur + _roof_slope_at(p) * _roof_down(p)


func _has_ridge() -> bool:
	return roof_mode != "shed" and roof_mode != "planes"


## Parameters (0..1) along the edge a -> b where two roof planes cross: the wall top has a kink there.
func _plane_breaks(a: Vector2, b: Vector2) -> Array[float]:
	var res: Array[float] = []
	var n := roof_planes.size()
	var ha: Array[float] = []
	var hb: Array[float] = []
	for pl in roof_planes:
		ha.append(float(pl["a"]) * a.x + float(pl["b"]) * a.y + float(pl["c"]))
		hb.append(float(pl["a"]) * b.x + float(pl["b"]) * b.y + float(pl["c"]))
	for i in range(n):
		for j in range(i + 1, n):
			var d0 := ha[i] - ha[j]
			var d1 := hb[i] - hb[j]
			if d0 * d1 < 0.0:
				res.append(d0 / (d0 - d1))
	return res


func _ridge_t(p: Vector2) -> float:
	return (p.y if ridge_along_x else p.x) - ridge_mid


func _surf(surfs: Dictionary, key: String) -> Dictionary:
	if not surfs.has(key):
		surfs[key] = {"v": [], "n": [], "uv": [], "i": []}
	return surfs[key]


## Decides which atlas region (if any) a wall edge gets, and how many times it repeats.
## Walls running parallel to the ridge (eaves side) use "facade_long", the others "facade_gable".
func _wall_face(dir: Vector2, normal: Vector3, length: float, hmax: float, fid := "") -> Dictionary:
	if not _use_textures() or length < 0.3:
		return {"key": "plain", "tiles": 1.0, "href": hmax}
	var short_wall := length < settings.f("tex_min_edge")   # gets a cut-out of the picture, not a squeezed copy
	var along_x := absf(dir.x) >= absf(dir.y)
	var is_eave := (along_x == ridge_along_x) or part_is_annex   # annex walls are plain rectangles: no gable triangle
	var role := "facade_annex" if part_is_annex else ("facade_long" if is_eave else "facade_gable")
	var side := 0
	if along_x:
		side = 1 if normal.z > 0.0 else 0
	else:
		side = 1 if normal.x > 0.0 else 0
	var slot := ("tex_long_" if is_eave else "tex_gable_") + ("b" if side == 1 else "a")
	var key := _forced_region(slot)
	if key == "":
		key = atlas.pick_key(role, side + settings.i("tex_variant"))   # one set for the whole building
	key = _face_region(key, fid)
	if key == "":
		return {"key": "plain", "tiles": 1.0, "href": hmax}
	# The photo is scaled like on the main body (same metres per picture), so a lower annex shows the
	# bottom part of the picture instead of a squeezed copy of the whole.
	var href := hmax
	if part_is_annex:
		href = tex_main_wall_h
	elif not is_eave:
		href = maxf(hmax, 0.1)
	# Known scale of the sheet (px per metre): the picture has its real size, so a wall longer than the
	# picture repeats it and a lower wall shows only the bottom of it.
	# A wall picture covers its whole wall (what the mapping editor shows). px/m is NOT used to tile walls:
	# GPT does not keep the requested pixel sizes, so hidden repetition produced rows of extra windows.
	# Repeating happens only when "Zachowaj proporcje" is switched on, or through the face's own scale.
	if _is_sheet_region(key):
		return {"key": key, "tiles": 1.0, "href": href}
	if not settings.b("tex_keep_aspect") and not short_wall:
		return {"key": key, "tiles": 1.0, "href": href}
	# Keep the texture's proportions: its natural width at this height decides the repeat count.
	var nat_w := maxf(href * atlas.aspect(key), 0.1)
	return {"key": key, "tiles": _tile_count(length, nat_w), "href": href}


## How many times a picture of natural width nat_w repeats along a wall. A wall much shorter than the
## picture shows a part of it at true scale (fraction < 1) instead of the whole picture squeezed in.
static func _tile_count(length: float, nat_w: float) -> float:
	if length < 0.75 * nat_w:
		return maxf(length / nat_w, 0.05)
	return float(maxi(1, roundi(length / nat_w)))


func _build_walls(pts: PackedVector2Array, covers: Array = []) -> MeshInstance3D:
	var surfs: Dictionary = {}
	for i in range(pts.size()):
		var a2 := pts[i]
		var b2 := pts[(i + 1) % pts.size()]
		var edge := b2 - a2
		var length := edge.length()
		if length < 0.001:
			continue
		var dir := edge / length
		var normal := Vector3(dir.y, 0.0, -dir.x)   # outward for a counter-clockwise footprint
		var edge_covers: Array = covers[i] if i < covers.size() else []

		# Split the edge at the roof crease and wherever a neighbouring part starts or ends.
		var ts: Array[float] = [0.0, 1.0]
		var ta := _ridge_t(a2)
		var tb := _ridge_t(b2)
		var hmax := maxf(_top_y(a2), _top_y(b2))
		if _has_ridge() and ta * tb < 0.0:
			ts.append(ta / (ta - tb))
			hmax = wall_h_cur + roof_h_cur
		for c in edge_covers:
			ts.append(clampf(c[0], 0.0, 1.0))
			ts.append(clampf(c[1], 0.0, 1.0))
		if roof_mode == "planes":
			ts.append_array(_plane_breaks(a2, b2))
		ts.sort()
		if roof_mode == "planes":
			for tt in ts:
				hmax = maxf(hmax, _top_y(a2.lerp(b2, tt)))

		var fid := "p%d:w%d" % [part_variant, i]
		var face := _wall_face(dir, normal, length, hmax, fid)
		var key: String = face["key"]
		var tiles: float = face["tiles"]
		var href: float = maxf(float(face["href"]), 0.1)
		var skey := key + "@" + fid if faces.has_material(fid) else key    # own surface = own material
		var s := _surf(surfs, skey)
		s["base"] = key
		s["fid"] = fid
		var remap := faces.has_mapping(fid) and key != "plain"
		var map_p: Dictionary = faces.mapping(fid)
		var map_pivot := Vector2(tiles * 0.5, 1.0 - hmax * 0.5 / href)
		var map_pw := length / maxf(tiles, 0.001)
		face_geo[fid] = {"key": key, "uv": Rect2(0.0, 1.0 - hmax / href, tiles, hmax / href), "pivot": map_pivot, "pw": map_pw, "ph": href}
		for k in range(ts.size() - 1):
			var t0 := ts[k]
			var t1 := ts[k + 1]
			if t1 - t0 < 1e-5:
				continue
			var p0 := a2.lerp(b2, t0)
			var p1 := a2.lerp(b2, t1)
			var h0 := _top_y(p0)
			var h1 := _top_y(p1)
			# A section that leans on a neighbour is hidden up to the neighbour's height.
			var base := 0.0
			var tm := (t0 + t1) * 0.5
			for c in edge_covers:
				if tm > c[0] and tm < c[1]:
					base = maxf(base, c[2])
			if base >= maxf(h0, h1) - 0.01:
				continue
			var y0 := minf(base, h0)
			var y1 := minf(base, h1)
			var vi: int = s["v"].size()
			s["v"].append(Vector3(p0.x, y0, p0.y))
			s["v"].append(Vector3(p1.x, y1, p1.y))
			s["v"].append(Vector3(p1.x, h1, p1.y))
			s["v"].append(Vector3(p0.x, h0, p0.y))
			for j in range(4):
				s["n"].append(normal)
			if key == "plain":
				s["uv"].append(Vector2(t0 * length, y0))
				s["uv"].append(Vector2(t1 * length, y1))
				s["uv"].append(Vector2(t1 * length, h1))
				s["uv"].append(Vector2(t0 * length, h0))
			else:
				# Seen from outside, a counter-clockwise footprint runs right-to-left, so u is
				# reversed (1 - t) or the facade would be mirrored. v = 0 at the top of the region.
				var u0 := (1.0 - t0) * tiles
				var u1 := (1.0 - t1) * tiles
				var quad_uv: Array[Vector2] = [Vector2(u0, 1.0 - y0 / href), Vector2(u1, 1.0 - y1 / href), Vector2(u1, 1.0 - h1 / href), Vector2(u0, 1.0 - h0 / href)]
				for q in quad_uv:
					s["uv"].append(FaceStore.uv_transform(q, map_pivot, map_pw, href, map_p["off"], map_p["scale"], map_p["rot"], map_p["flip"]) if remap else q)
			s["i"].append_array([vi, vi + 1, vi + 2, vi, vi + 2, vi + 3])
			if not s.has("tri_faces"):
				s["tri_faces"] = []
			s["tri_faces"].append_array([fid, fid])

	var mesh := ArrayMesh.new()
	var pick_tris := PackedVector3Array()
	var pick_ids := PackedStringArray()
	var surf_lit: Array = []
	for skey in surfs.keys():
		var sd: Dictionary = surfs[skey]
		if sd["v"].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(sd["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(sd["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(sd["uv"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(sd["i"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		var base_key: String = sd["base"]
		var base_mat: StandardMaterial3D = wall_material if base_key == "plain" else _tex_material(base_key)
		mesh.surface_set_material(idx, _face_material(base_mat, "w|" + base_key, str(sd["fid"])) if faces.has_material(str(sd["fid"])) else base_mat)
		surf_lit.append(faces.has_material(str(sd["fid"])) and bool(faces.get_value(str(sd["fid"]), "light")))
		var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tf: Array = sd.get("tri_faces", [])
		for ti in range(ind.size() / 3):
			for c in range(3):
				pick_tris.append(vv[ind[ti * 3 + c]])
			pick_ids.append(str(tf[ti]) if ti < tf.size() else "")

	var walls := MeshInstance3D.new()
	walls.name = "Walls"
	walls.mesh = mesh
	walls.set_meta("pick_tris", pick_tris)
	walls.set_meta("pick_ids", pick_ids)
	walls.set_meta("surf_lit", surf_lit)
	return walls


## Roof outline = footprint pushed outwards by the overhang (eaves and gable verges), minus the
## footprints of neighbouring parts so the overhang does not run into their walls.
## Overhangs of the roof of the current part: [eave side A (t > 0), eave side B, gable ends] in metres.
func _roof_overhangs() -> Array:
	var eave_a := settings.f("model_roof_overhang")
	var eave_b := settings.f("model_roof_over_eave_b") if settings.b("model_roof_asym") else eave_a
	var gable := eave_a if settings.b("model_roof_gable_same") else settings.f("model_roof_over_gable")
	return [eave_a, eave_b, gable]


## Roof outline with the overhangs: offset by the largest one, then the extreme vertices of each side
## are pulled back to their own overhang.
func _roof_outline(pts: PackedVector2Array, others: Array = []) -> PackedVector2Array:
	var ov := _roof_overhangs()
	var base_over := maxf(maxf(float(ov[0]), float(ov[1])), float(ov[2]))
	var out := _roof_outline_offset(pts, others, base_over)
	if absf(float(ov[0]) - base_over) < 0.001 and absf(float(ov[1]) - base_over) < 0.001 and absf(float(ov[2]) - base_over) < 0.001:
		return out
	if roof_mode == "shed" or out.size() < 3:
		return out
	var bb := _bounds(pts)
	var across_lo := (bb.position.y if ridge_along_x else bb.position.x)
	var across_hi := (bb.end.y if ridge_along_x else bb.end.x)
	var along_lo := (bb.position.x if ridge_along_x else bb.position.y)
	var along_hi := (bb.end.x if ridge_along_x else bb.end.y)
	var res := PackedVector2Array()
	for p in out:
		var across := p.y if ridge_along_x else p.x
		var along := p.x if ridge_along_x else p.y
		var d_across := 0.0
		var d_along := 0.0
		if across > across_hi + 0.01:
			d_across = float(ov[0]) - base_over
		elif across < across_lo - 0.01:
			d_across = -(float(ov[1]) - base_over)
		if along > along_hi + 0.01:
			d_along = float(ov[2]) - base_over
		elif along < along_lo - 0.01:
			d_along = -(float(ov[2]) - base_over)
		if ridge_along_x:
			res.append(Vector2(p.x + d_along, p.y + d_across))
		else:
			res.append(Vector2(p.x + d_across, p.y + d_along))
	return res


func _roof_outline_offset(pts: PackedVector2Array, others: Array, over: float) -> PackedVector2Array:
	if over <= 0.001:
		return pts
	var polys: Array = []
	for poly in Geometry2D.offset_polygon(pts, over, Geometry2D.JOIN_MITER):
		polys.append(poly)
	for other in others:
		var next: Array = []
		for poly in polys:
			for piece in Geometry2D.clip_polygons(poly, other):
				if not Geometry2D.is_polygon_clockwise(piece):
					next.append(piece)
		polys = next
	if not others.is_empty():
		polys.append(pts)
		var merged: Array = []
		var cur: PackedVector2Array = polys[0]
		for k in range(1, polys.size()):
			var m: Array = Geometry2D.merge_polygons(cur, polys[k])
			var big := PackedVector2Array()
			var big_a := 0.0
			for piece in m:
				if not Geometry2D.is_polygon_clockwise(piece) and absf(_poly_area(piece)) > big_a:
					big_a = absf(_poly_area(piece))
					big = piece
			if big.size() >= 3:
				cur = big
		return cur if cur.size() >= 3 else pts
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly in polys:
		var area := absf(_poly_area(poly))
		if area > best_area:
			best_area = area
			best = poly
	return best if best.size() >= 3 else pts


func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(p.size()):
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


## UV in metres / tile size. The tile keeps the picture's own proportions (no stretching);
## "stretch once" mode maps the picture over the whole roof slope instead.
func _roof_uv(p: Vector2, tile: Vector2, origin: Vector2) -> Vector2:
	var along_is_x := ridge_along_x if roof_mode != "shed" else shed_axis == 1
	var along := (p.x if along_is_x else p.y) - origin.x
	# v = 0 at the OUTER edge of the overhang (not at the wall line), so a picture laid once over the slope
	# fills exactly 0..1 instead of wrapping over the overhang strip.
	var ovs := _roof_overhangs()
	var ov := float(ovs[0]) if (roof_mode == "shed" or _ridge_t(p) >= 0.0) else float(ovs[1])
	var slope_len := (_roof_down(p) + ov) * sqrt(1.0 + pow(_roof_slope_at(p), 2.0))
	var uv := Vector2(along / tile.x, slope_len / tile.y)
	return Vector2(uv.y, uv.x) if settings.b("tex_roof_rotate") else uv


func _add_tri(surf: Dictionary, vs: Array, uvs: Array, up: bool) -> void:
	# Godot front faces are clockwise: front normal = (v2 - v0) x (v1 - v0).
	var nrm: Vector3 = (vs[2] - vs[0]).cross(vs[1] - vs[0])
	if nrm.length_squared() < 1e-8:
		return
	if (nrm.y < 0.0) == up:
		vs = [vs[0], vs[2], vs[1]]
		uvs = [uvs[0], uvs[2], uvs[1]]
		nrm = -nrm
	_push_tri(surf, vs, uvs)


func _push_tri(surf: Dictionary, vs: Array, uvs: Array) -> void:
	var nrm: Vector3 = (vs[2] - vs[0]).cross(vs[1] - vs[0])
	if nrm.length_squared() < 1e-10:
		return
	nrm = nrm.normalized()
	for j in range(3):
		surf["v"].append(vs[j])
		surf["n"].append(nrm)
		surf["uv"].append(uvs[j])


## Polygon cut to the half plane a*x + b*z + c >= 0.
static func _clip_halfplane(poly: PackedVector2Array, a: float, b: float, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var dp := a * p.x + b * p.y + c
		var dq := a * q.x + b * q.y + c
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


## Generated roof: every plane of RoofGen is a facet; the surface is the lower envelope, cut by the outline with overhangs.
func _build_roof_planes(pts: PackedVector2Array, others: Array = []) -> MeshInstance3D:
	var outline := _roof_outline(pts, others)
	var tri_idx := Geometry2D.triangulate_polygon(outline)
	if tri_idx.is_empty():
		return null
	var thick := settings.f("model_roof_thickness")
	var roof_key := ""
	if _use_textures():
		roof_key = _forced_region("tex_roof")
		if roof_key == "":
			roof_key = atlas.pick_key("roof", settings.i("tex_variant"))
	var n := roof_planes.size()
	var facets: Array = []
	for k in range(n):
		facets.append([])
	for t in range(0, tri_idx.size(), 3):
		var tri := PackedVector2Array([outline[tri_idx[t]], outline[tri_idx[t + 1]], outline[tri_idx[t + 2]]])
		for k in range(n):
			var pk: Dictionary = roof_planes[k]
			var poly := tri
			for j in range(n):
				if j == k:
					continue
				var pj: Dictionary = roof_planes[j]
				var da := float(pj["a"]) - float(pk["a"])
				var db := float(pj["b"]) - float(pk["b"])
				var dc := float(pj["c"]) - float(pk["c"])
				if absf(da) < 1e-6 and absf(db) < 1e-6 and absf(dc) < 1e-6:
					if j < k:
						poly = PackedVector2Array()
					continue
				poly = _clip_halfplane(poly, da, db, dc)
				if poly.size() < 3:
					break
			if poly.size() >= 3:
				(facets[k] as Array).append(poly)

	var drop := Vector3(0.0, -thick, 0.0)
	var tops := {}
	var under := {"v": [], "n": [], "uv": []}
	var order: Array = []
	var frame := {}
	for k in range(n):
		if (facets[k] as Array).is_empty():
			continue
		var pk: Dictionary = roof_planes[k]
		var id := str(pk["label"])
		var fid := "p%d:roof%s" % [part_variant, id]
		var g := Vector2(float(pk["a"]), float(pk["b"]))
		var m := g.length()
		var up := g / m if m > 1e-4 else (Vector2(0.0, 1.0) if ridge_along_x else Vector2(1.0, 0.0))
		var perp := Vector2(-up.y, up.x)
		if perp.x < -1e-4 or (absf(perp.x) <= 1e-4 and perp.y < 0.0):
			perp = -perp
		var fac := sqrt(1.0 + m * m)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for poly in facets[k]:
			for q in poly:
				var uv0 := Vector2(q.dot(perp), q.dot(up) * fac)
				lo = Vector2(minf(lo.x, uv0.x), minf(lo.y, uv0.y))
				hi = Vector2(maxf(hi.x, uv0.x), maxf(hi.y, uv0.y))
		var sk := _face_region(roof_key, fid)
		var tl := Vector2.ONE * maxf(settings.f("tex_roof_tile_m"), 0.1)
		if sk != "":
			tl.y = tl.x / maxf(atlas.aspect(sk), 0.05)
		if settings.b("tex_roof_rotate"):
			tl = Vector2(tl.y, tl.x)
		var ext := hi - lo
		if not settings.b("tex_roof_repeat") or _roof_picture_is_whole(sk, ext.x, maxf(ext.y, 0.1)):
			tl = Vector2(maxf(ext.x, 0.1), maxf(ext.y, 0.1))
			if settings.b("tex_roof_rotate"):
				tl = Vector2(tl.y, tl.x)
		frame[id] = {"fid": fid, "key": sk, "tile": tl, "lo": lo, "hi": hi}
		var top := {"v": [], "n": [], "uv": []}
		for poly in facets[k]:
			for i in range(1, poly.size() - 1):
				var qs: Array[Vector2] = [poly[0], poly[i], poly[i + 1]]
				var vs: Array = []
				var uvs: Array = []
				for q in qs:
					vs.append(Vector3(q.x, float(pk["a"]) * q.x + float(pk["b"]) * q.y + float(pk["c"]), q.y))
					var u := (q.dot(perp) - lo.x) / tl.x if not settings.b("tex_roof_rotate") else (q.dot(up) * fac - lo.y) / tl.x
					var v := (q.dot(up) * fac - lo.y) / tl.y if not settings.b("tex_roof_rotate") else (q.dot(perp) - lo.x) / tl.y
					uvs.append(Vector2(u, v))
				_add_tri(top, vs, uvs, true)
				if thick > 0.001:
					_add_tri(under, [vs[0] + drop, vs[1] + drop, vs[2] + drop], uvs, false)
		tops[id] = top
		order.append(id)

	# Rim: a vertical band along the outline, split where two planes cross.
	if thick > 0.001:
		var n_pts := outline.size()
		for i in range(n_pts):
			var a := outline[i]
			var b := outline[(i + 1) % n_pts]
			var us: Array[float] = [0.0, 1.0]
			us.append_array(_plane_breaks(a, b))
			us.sort()
			for c in range(us.size() - 1):
				if us[c + 1] - us[c] < 1e-5:
					continue
				var c0 := a.lerp(b, us[c])
				var c1 := a.lerp(b, us[c + 1])
				var p0 := Vector3(c0.x, _top_y(c0), c0.y)
				var p1 := Vector3(c1.x, _top_y(c1), c1.y)
				var z := Vector2.ZERO
				var outward := Vector3(p1.z - p0.z, 0.0, -(p1.x - p0.x))
				var mid := Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.z + p1.z) * 0.5)
				if Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z) + Vector2(outward.x, outward.z).normalized() * 0.01, outline):
					outward = -outward
				var q0 := p0 + drop
				var q1 := p1 + drop
				for tri3 in [[p0, p1, q1], [p0, q1, q0]]:
					var nrm: Vector3 = (tri3[2] - tri3[0]).cross(tri3[1] - tri3[0])
					var tv: Array = tri3
					if nrm.dot(outward) < 0.0:
						tv = [tri3[0], tri3[2], tri3[1]]
					_push_tri(under, tv, [z, z, z])
	if order.is_empty():
		return null

	# Face corrections of a facet: move / scale / turn the picture around the centre of the facet.
	var corrected := false
	for id in order:
		var fr: Dictionary = frame[id]
		var sd: Dictionary = tops[id]
		var uvs_arr: Array = sd["uv"]
		var tl: Vector2 = fr["tile"]
		var lo2 := Vector2(INF, INF)
		var hi2 := Vector2(-INF, -INF)
		for q in uvs_arr:
			lo2 = Vector2(minf(lo2.x, q.x), minf(lo2.y, q.y))
			hi2 = Vector2(maxf(hi2.x, q.x), maxf(hi2.y, q.y))
		face_geo[fr["fid"]] = {"key": fr["key"], "uv": Rect2(lo2, hi2 - lo2), "pivot": (lo2 + hi2) * 0.5, "pw": tl.x, "ph": tl.y}
		if faces.has_face(str(fr["fid"])):
			corrected = true
		if not faces.has_mapping(fr["fid"]) or fr["key"] == "":
			continue
		var centre := Vector2.ZERO
		for q in uvs_arr:
			centre += q
		centre /= float(uvs_arr.size())
		var mp: Dictionary = faces.mapping(fr["fid"])
		for k in range(uvs_arr.size()):
			uvs_arr[k] = FaceStore.uv_transform(uvs_arr[k], centre, tl.x, tl.y, mp["off"], mp["scale"], mp["rot"], mp["flip"])

	var groups: Array = []
	var same_key := true
	for id in order:
		if frame[id]["key"] != frame[order[0]]["key"]:
			same_key = false
	if not corrected and same_key:
		var both := {"v": [], "n": [], "uv": [], "fids": []}
		for id in order:
			both["v"].append_array(tops[id]["v"])
			both["n"].append_array(tops[id]["n"])
			both["uv"].append_array(tops[id]["uv"])
			for i in range((tops[id]["v"] as Array).size() / 3):
				both["fids"].append(frame[id]["fid"])
		groups.append([both, str(order[0])])
	else:
		for id in order:
			var one: Dictionary = tops[id]
			one["fids"] = []
			for i in range((one["v"] as Array).size() / 3):
				one["fids"].append(frame[id]["fid"])
			groups.append([one, id])
	groups.append([under, ""])
	var mesh := ArrayMesh.new()
	var pick_tris := PackedVector3Array()
	var pick_ids := PackedStringArray()
	var surf_lit: Array = []
	for pair in groups:
		var sd: Dictionary = pair[0]
		if (sd["v"] as Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(sd["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(sd["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(sd["uv"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		var side_id: String = pair[1]
		var fid := str(frame[side_id]["fid"]) if side_id != "" else ""
		var sk: String = str(frame[side_id]["key"]) if side_id != "" else ""
		var base_mat: StandardMaterial3D = roof_material
		if sk != "":
			base_mat = _tex_material(sk, "roof:")
		elif side_id == "":
			var first_key: String = str(frame[order[0]]["key"])
			if first_key != "":
				base_mat = _roof_edge_material(first_key)
		mesh.surface_set_material(si, _face_material(base_mat, "r|" + sk, fid) if (fid != "" and faces.has_material(fid)) else base_mat)
		surf_lit.append(fid != "" and faces.has_material(fid) and bool(faces.get_value(fid, "light")))
		if side_id == "":
			for ti in range((sd["v"] as Array).size() / 3):
				pick_ids.append("")
		else:
			for f2 in (sd["fids"] as Array):
				pick_ids.append(str(f2))
		pick_tris.append_array(PackedVector3Array(sd["v"]))
	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = mesh
	mi.set_meta("pick_tris", pick_tris)
	mi.set_meta("pick_ids", pick_ids)
	mi.set_meta("surf_lit", surf_lit)
	return mi


## Roof as its own solid: top surface (textured, tiled), underside and rim, overhanging the walls.
func _build_roof(pts: PackedVector2Array, others: Array = []) -> MeshInstance3D:
	if roof_mode == "planes":
		return _build_roof_planes(pts, others)
	var outline := _roof_outline(pts, others)
	var tri_idx := Geometry2D.triangulate_polygon(outline)
	if tri_idx.is_empty():
		return null
	var thick := settings.f("model_roof_thickness")

	var roof_key := ""
	if _use_textures():
		roof_key = _forced_region("tex_roof")
		if roof_key == "":
			roof_key = atlas.pick_key("roof", settings.i("tex_variant"))
	var rb := _bounds(outline)
	var along_is_x := ridge_along_x if roof_mode != "shed" else shed_axis == 1
	var origin := Vector2(rb.position.x if along_is_x else rb.position.y, 0.0)
	var span_along := rb.size.x if along_is_x else rb.size.y
	var ovs := _roof_overhangs()
	var slope_len := 0.0
	var side_slope_len := {}
	if roof_mode == "shed":
		slope_len = (shed_span + float(ovs[0])) * sqrt(1.0 + pow(_roof_slope(), 2.0))
		side_slope_len = {"A": slope_len, "B": slope_len}
	else:
		side_slope_len = {"A": (half_pos + float(ovs[0])) * sqrt(1.0 + pow(roof_h_cur / maxf(half_pos, 0.001), 2.0)),
			"B": (half_neg + float(ovs[1])) * sqrt(1.0 + pow(roof_h_cur / maxf(half_neg, 0.001), 2.0))}
	# Each slope may wear its own picture (face corrections), so the picture and tile size are per slope.
	var slope_keys := {}
	var slope_tiles := {}
	for side_id in ["A", "B"]:
		var sk := _face_region(roof_key, "p%d:roof%s" % [part_variant, side_id])
		var tl := Vector2.ONE * maxf(settings.f("tex_roof_tile_m"), 0.1)
		if sk != "":
			tl.y = tl.x / maxf(atlas.aspect(sk), 0.05)
		if settings.b("tex_roof_rotate"):
			tl = Vector2(tl.y, tl.x)
		# Template sheet S5 is one whole slope (15.8 x 5.8 m in the prompt): lay it once over the slope.
		var sheet_roof := _roof_picture_is_whole(sk, span_along, maxf(float(side_slope_len[side_id]), 0.1))
		if not settings.b("tex_roof_repeat") or sheet_roof:
			tl = Vector2(span_along, maxf(float(side_slope_len[side_id]), 0.1))
			if settings.b("tex_roof_rotate"):
				tl = Vector2(tl.y, tl.x)
		slope_keys[side_id] = sk
		slope_tiles[side_id] = tl

	var tops := {"A": {"v": [], "n": [], "uv": []}, "B": {"v": [], "n": [], "uv": []}}
	var under := {"v": [], "n": [], "uv": []}
	var drop := Vector3(0.0, -thick, 0.0)

	for t in range(0, tri_idx.size(), 3):
		var tri := PackedVector2Array([outline[tri_idx[t]], outline[tri_idx[t + 1]], outline[tri_idx[t + 2]]])
		for keep_greater in ([true, false] if _has_ridge() else [true]):
			var top: Dictionary = tops["A" if keep_greater else "B"]
			var tile: Vector2 = slope_tiles["A" if keep_greater else "B"]
			var poly := _clip_side(tri, keep_greater) if _has_ridge() else tri
			if poly.size() < 3:
				continue
			for k in range(1, poly.size() - 1):
				var qs: Array[Vector2] = [poly[0], poly[k], poly[k + 1]]
				var vs: Array = []
				var uvs: Array = []
				for q in qs:
					vs.append(Vector3(q.x, _top_y(q), q.y))
					uvs.append(_roof_uv(q, tile, origin))
				_add_tri(top, vs, uvs, true)
				if thick > 0.001:
					_add_tri(under, [vs[0] + drop, vs[1] + drop, vs[2] + drop], uvs, false)

	# Rim: a vertical band along the outline; split where an edge crosses the ridge (the only kink).
	if thick > 0.001:
		var n_pts := outline.size()
		for i in range(n_pts):
			var a := outline[i]
			var b := outline[(i + 1) % n_pts]
			var cuts: Array[Vector2] = [a]
			var da := _ridge_t(a)
			var db := _ridge_t(b)
			if _has_ridge() and (da > 0.0) != (db > 0.0) and absf(da - db) > 1e-6:
				cuts.append(a.lerp(b, da / (da - db)))
			cuts.append(b)
			for c in range(cuts.size() - 1):
				var p0 := Vector3(cuts[c].x, _top_y(cuts[c]), cuts[c].y)
				var p1 := Vector3(cuts[c + 1].x, _top_y(cuts[c + 1]), cuts[c + 1].y)
				var z := Vector2.ZERO
				var outward := Vector3(p1.z - p0.z, 0.0, -(p1.x - p0.x))
				var mid := Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.z + p1.z) * 0.5)
				var inside := Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z) + Vector2(outward.x, outward.z).normalized() * 0.01, outline)
				if inside:
					outward = -outward
				var q0 := p0 + drop
				var q1 := p1 + drop
				for tri3 in [[p0, p1, q1], [p0, q1, q0]]:
					var nrm: Vector3 = (tri3[2] - tri3[0]).cross(tri3[1] - tri3[0])
					var tv: Array = tri3
					if nrm.dot(outward) < 0.0:
						tv = [tri3[0], tri3[2], tri3[1]]
					_push_tri(under, tv, [z, z, z])
	if (tops["A"]["v"] as Array).is_empty() and (tops["B"]["v"] as Array).is_empty():
		return null

	# Face corrections of a slope: move / scale / turn the picture around the centre of the slope.
	for side_id in ["A", "B"]:
		var fid := "p%d:roof%s" % [part_variant, side_id]
		var sd: Dictionary = tops[side_id]
		if (sd["uv"] as Array).is_empty():
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in (sd["uv"] as Array):
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		face_geo[fid] = {"key": slope_keys[side_id], "uv": Rect2(lo, hi - lo), "pivot": (lo + hi) * 0.5, "pw": (slope_tiles[side_id] as Vector2).x, "ph": (slope_tiles[side_id] as Vector2).y}
		if not faces.has_mapping(fid) or slope_keys[side_id] == "":
			continue
		var uvs_arr: Array = sd["uv"]
		var centre := Vector2.ZERO
		for q in uvs_arr:
			centre += q
		centre /= float(uvs_arr.size())
		var mp: Dictionary = faces.mapping(fid)
		var tl: Vector2 = slope_tiles[side_id]
		for k in range(uvs_arr.size()):
			uvs_arr[k] = FaceStore.uv_transform(uvs_arr[k], centre, tl.x, tl.y, mp["off"], mp["scale"], mp["rot"], mp["flip"])

	var mesh := ArrayMesh.new()
	var pick_tris := PackedVector3Array()
	var pick_ids := PackedStringArray()
	var surf_lit: Array = []
	var groups: Array = [[tops["A"], "A"], [tops["B"], "B"], [under, ""]]
	var fid_a := "p%d:roofA" % part_variant
	var fid_b := "p%d:roofB" % part_variant
	var merged := false
	if not faces.has_face(fid_a) and not faces.has_face(fid_b) and slope_keys["A"] == slope_keys["B"]:
		# Nothing corrected on either slope: one surface, like before (fewer draw calls).
		var both := {"v": (tops["A"]["v"] as Array) + (tops["B"]["v"] as Array), "n": (tops["A"]["n"] as Array) + (tops["B"]["n"] as Array),
			"uv": (tops["A"]["uv"] as Array) + (tops["B"]["uv"] as Array), "split": (tops["A"]["v"] as Array).size() / 3}
		groups = [[both, "A"], [under, ""]]
		merged = true
	for pair in groups:
		var sd: Dictionary = pair[0]
		if sd["v"].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(sd["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(sd["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(sd["uv"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		var side_id: String = pair[1]
		var fid := "p%d:roof%s" % [part_variant, side_id] if side_id != "" else ""
		var base_mat: StandardMaterial3D = roof_material
		var sk: String = slope_keys[side_id] if side_id != "" else ""
		if sk != "":
			base_mat = _tex_material(sk, "roof:")
		elif side_id == "" and slope_keys["A"] != "":
			base_mat = _roof_edge_material(slope_keys["A"])   # rim / underside in the colour of the covering
		mesh.surface_set_material(si, _face_material(base_mat, "r|" + sk, fid) if (fid != "" and faces.has_material(fid)) else base_mat)
		surf_lit.append(fid != "" and faces.has_material(fid) and bool(faces.get_value(fid, "light")))
		for ti in range((sd["v"] as Array).size() / 3):
			pick_ids.append(fid_b if (merged and sd.has("split") and ti >= int(sd["split"])) else fid)
		pick_tris.append_array(PackedVector3Array(sd["v"]))

	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = mesh
	mi.set_meta("pick_tris", pick_tris)
	mi.set_meta("pick_ids", pick_ids)
	mi.set_meta("surf_lit", surf_lit)
	return mi


## A region from a template sheet (S1..S8) is one whole picture for its wall / slope: laid ONCE, never tiled.
func _is_sheet_region(key: String) -> bool:
	if key == "":
		return false
	return (key.length() == 2 and key[0] == "S") or atlas.is_template or settings.s("tex_slice_mode") == "sheet"


## Roof picture that covers (about) the whole slope at the sheet's scale - as the roof panel of a GPT sheet does - is laid once
## over the slope. A small swatch of roof tiles (a few metres at that scale) is repeated instead.
func _roof_picture_is_whole(key: String, span_along: float, slope_len: float) -> bool:
	if _is_sheet_region(key):
		return true
	var ppm := settings.f("tex_px_per_m")
	if key == "" or ppm <= 0.0 or not atlas.regions.has(key):
		return false
	var img: Image = atlas.region(key)["img"]
	return float(img.get_width()) / ppm >= 0.5 * span_along and float(img.get_height()) / ppm >= 0.5 * slope_len


func _clip_side(poly: PackedVector2Array, keep_greater: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	var sign_f := 1.0 if keep_greater else -1.0
	for i in range(count):
		var cur := poly[i]
		var nxt := poly[(i + 1) % count]
		var dc := _ridge_t(cur) * sign_f
		var dn := _ridge_t(nxt) * sign_f
		if dc >= 0.0:
			out.append(cur)
		if (dc >= 0.0) != (dn >= 0.0):
			out.append(cur.lerp(nxt, dc / (dc - dn)))
	return out


func _clear_building() -> void:
	if is_instance_valid(building_root):
		var parent := building_root.get_parent()
		if parent:
			parent.remove_child(building_root)
		building_root.queue_free()
	building_root = null


func _update_info() -> void:
	_update_steps()
	save_timer.start()
	var sz := current_bounds.size
	var crs := "lon/lat → przybliżone metry" if current_is_geographic else "metry (układ lokalny / EPSG:2180)"
	var roof_txt := "płaski" if (roof_h_cur <= 0.001) else ("pulpitowy" if roof_mode == "shed" else "dwuspadowy") + ", %.1f m" % roof_h_cur + (" (z tekstury)" if settings.b("model_roof_from_tex") and _tex_roof_height(1.0) > 0.0 else "")
	if last_rt.size() > 1:
		roof_txt += "\nCzęści: %d (główna + %d dobudówek, patrz niżej)" % [last_rt.size(), last_rt.size() - 1]
	info_label.text = "%s (%s)\n%.1f × %.1f m, obrót %.1f°, ściany %.1f m\nDach: %s\nDach jest przybliżeniem, nie rekonstrukcją LoD2." % [
		current_source, crs, sz.x, sz.z, footprint_rotation_deg, wall_h_cur, roof_txt
	]


# ================================================================== Parts list (Start tab)

# ================================================================== 3D camera

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F11:
		rig._toggle_fullscreen()
		return
	if not (event is InputEventKey) or not event.pressed or tabs.current_tab != 1:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE and selected_face != "":
		_select_face("")
	elif k.ctrl_pressed and k.keycode == KEY_Z and not k.shift_pressed:
		faces.undo()
	elif k.ctrl_pressed and (k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)):
		faces.redo()


# ================================================================== Photo library: import / export
