class_name AppSettings
extends RefCounted
## Single source of truth for every adjustable parameter.
## The sidebar (settings_panel.gd) is generated from `sections`, values are saved to
## user://photo_to_3d_settings.json, and the rest of the app only reads through s()/f()/i()/b()/c().
## To add a new option: add one _add(...) line below - the sidebar, saving and reset follow.

signal changed(key: String)
signal options_changed(key: String)

const SAVE_PATH := "user://photo_to_3d_settings.json"
const FORMAT_VERSION := 1

var tabs: Array = []          # [{id, title, heading, tip, step}] - tab strip of the sidebar, in work-flow order
var sections: Array = []      # [{id, title, tab, tip, collapsed, items: [def]}]
var defs: Dictionary = {}     # key -> def
var values: Dictionary = {}   # key -> current value (buttons have no value)

var _cur: Dictionary = {}


func _init() -> void:
	_define()
	for key in defs.keys():
		if defs[key]["type"] != "button":
			values[key] = defs[key]["default"]
	load_from_disk()


# ------------------------------------------------------------------ access

func v(key: String) -> Variant:
	if values.has(key):
		return values[key]
	push_warning("AppSettings: unknown key '%s'" % key)
	return null


func s(key: String) -> String:
	return str(v(key))


func f(key: String) -> float:
	return float(v(key))


func i(key: String) -> int:
	return int(v(key))


func b(key: String) -> bool:
	return bool(v(key))


func c(key: String) -> Color:
	return Color.html(s(key))


func set_value(key: String, value: Variant) -> void:
	if not defs.has(key) or defs[key]["type"] == "button":
		return
	var nv: Variant = _coerce(defs[key], value)
	if values.get(key) == nv:
		return
	values[key] = nv
	changed.emit(key)


func reset_key(key: String) -> void:
	if defs.has(key) and defs[key]["type"] != "button":
		set_value(key, defs[key]["default"])


func reset_section(section_id: String) -> void:
	for sec in sections:
		if sec["id"] == section_id:
			for d in sec["items"]:
				reset_key(d["key"])


func reset_all() -> void:
	for key in defs.keys():
		reset_key(key)


## Replace the list of choices of a "choice" setting at runtime (e.g. regions of a loaded atlas).
## options: Array of [value: String, label: String]
func set_options(key: String, options: Array) -> void:
	if defs.has(key):
		defs[key]["options"] = options
		options_changed.emit(key)


# ------------------------------------------------------------------ persistence

func save() -> bool:
	var fh := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if fh == null:
		return false
	fh.store_string(JSON.stringify({"version": FORMAT_VERSION, "values": values}, "\t"))
	fh.close()
	return true


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("values")) != TYPE_DICTIONARY:
		return
	for key in data["values"].keys():
		if defs.has(key) and defs[key]["type"] != "button":
			values[key] = _coerce(defs[key], data["values"][key])


func save_path_global() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)


func _coerce(d: Dictionary, value: Variant) -> Variant:
	match str(d["type"]):
		"float":
			return clampf(float(value), float(d.get("min", -INF)), float(d.get("max", INF)))
		"int":
			return clampi(int(value), int(d.get("min", -2147483648)), int(d.get("max", 2147483647)))
		"bool":
			return bool(value)
		"color":
			if value is Color:
				return (value as Color).to_html(false)
			return str(value)
		_:
			return str(value)


# ------------------------------------------------------------------ schema

## step: position in the work flow (1..n), 0 = a tab outside the flow. heading/tip are shown on top of the page.
func _tab(id: String, title: String, heading: String, tip: String, step: int) -> void:
	tabs.append({"id": id, "title": title, "heading": heading, "tip": tip, "step": step})


## A group of settings inside a sidebar tab. Several sections in one tab behave like an accordion.
## pinned: always open, shown as a plain heading (for the essentials of a tab); the other sections
## are collapsible and work like an accordion.
## Sections that live in the "Zaawansowane" window of their tab (rarely changed, safe to hide).
const ADVANCED_SECTIONS := ["map_loc", "map_start", "map_nav", "map_look", "src", "bld_adv", "tex_relief_adv", "tex_slice", "view_scene", "svc", "svc_cache"]


func _section(id: String, title: String, tab_id: String, collapsed := false, tip := "", pinned := false) -> void:
	_cur = {"id": id, "title": title, "tab": tab_id, "tip": tip, "collapsed": collapsed, "pinned": pinned, "items": [], "advanced": id in ADVANCED_SECTIONS}
	sections.append(_cur)


## type: float | int | bool | string | path | choice | color | button
## opts: min, max, step, suffix, slider (bool), tip, options ([[value, label], ...]), filters, stack (choice: label above the drop-down),
##       hidden (kept and saved, but not shown in the sidebar)
func _add(key: String, type: String, label: String, def_value: Variant, opts: Dictionary = {}) -> void:
	var d := {"key": key, "type": type, "label": label, "default": def_value}
	d.merge(opts)
	defs[key] = d
	_cur["items"].append(d)


func _button(key: String, label: String, tip := "") -> void:
	_add(key, "button", label, null, {"tip": tip})


func _define() -> void:
	# Tabs follow the order of work: 1 find the building -> 2 shape it -> 3 texture it -> 4 look at it.
	# step 0 = not part of the flow (settings). `heading` and `tip` are shown at the top of the page.
	_tab("place", "Miejsce", "Krok 1 z 4: wskaż budynek", "Znajdź miejsce na mapie, kliknij budynek (Ctrl/Shift + klik dodaje kolejne części) i zbuduj model.", 1)
	_tab("building", "Budynek", "Krok 2 z 5: bryła", "Sprawdź wymiary i wysokość ścian. Zmiany widać od razu w widoku 3D.", 2)
	_tab("tex", "Tekstury", "Krok 3 z 5: tekstury", "Prompt dla GPT, płótno od GPT (wskaż plik), dobór zdjęć na ściany, relief. Bez tekstury model jest gładki.", 3)
	_tab("roof", "Dach", "Krok 4 z 5: dach", "Wybierz typ dachu (dwuspadowy, kopertowy, własny, płaski) i ustaw go: profil na zdjęciu szczytu albo spadki krawędzi w rzucie z góry. Zmiany widać od razu. Kominy są niżej.", 4)
	_tab("view", "Widok", "Krok 5 z 5: oglądanie", "Warstwy, światło i kamera. Niskie słońce najlepiej pokazuje relief.", 5)
	_tab("emit", "Emitery", "Emitery: światło, efekty, dźwięk", "Opcjonalnie. Dodaj miejsca, które mogą świecić, grać, dymić, palić się albo padać deszczem, i połącz je kanałami sterowania. To opis w metadanych, nic nie jest wycinane z modelu.", 0)
	_tab("app", "Projekt", "Projekt: zapis, otwieranie i program", "Zapis i otwieranie projektu, rendery, ustawienia programu i adresy usług Geoportalu.", 0)


	# ---------------------------------------------------------------- 1. place
	_section("map_loc", "Podkład mapy", "place", true)
	_add("map_use_ortho", "bool", "Podkład: ortofotomapa", true, {"tip": "Wyłącz, jeśli chcesz tylko obrysy na ciemnym tle (szybciej)."})
	_add("map_building_max_mpp", "float", "Obrysy budynków od przybliżenia", 2.0, {"min": 0.2, "max": 10.0, "step": 0.1, "suffix": " m/px", "tip": "Obrysy są pobierane tylko, gdy mapa jest przybliżona co najmniej tak bardzo."})
	_button("act_map_refresh", "Odśwież mapę")
	_section("map_start", "Widok startowy", "place", true, "Gdzie mapa otwiera się po starcie programu.")
	_add("map_start_lat", "float", "Szerokość geogr. startu", 52.2297, {"min": 48.0, "max": 56.0, "step": 0.0001, "suffix": " °N", "slider": false, "tip": "Gdzie mapa otwiera się po starcie programu."})
	_add("map_start_lon", "float", "Długość geogr. startu", 21.0122, {"min": 13.0, "max": 25.0, "step": 0.0001, "suffix": " °E", "slider": false})
	_add("map_start_mpp", "float", "Początkowe przybliżenie", 0.4, {"min": 0.05, "max": 20.0, "step": 0.05, "suffix": " m/px", "tip": "Mniejsza wartość = mapa bliżej."})
	_button("act_map_save_start", "Zapisz bieżący widok jako start", "Zapamiętuje aktualne położenie i przybliżenie mapy jako widok startowy.")
	_section("map_nav", "Nawigacja i pobieranie", "place", true)
	_add("map_zoom_step", "float", "Krok zoomu kółkiem", 1.25, {"min": 1.05, "max": 2.5, "step": 0.05, "suffix": " ×"})
	_add("map_neighbor_tol", "float", "Sąsiednie części: maks. odstęp", 0.8, {"min": 0.0, "max": 5.0, "step": 0.1, "suffix": " m", "tip": "Przycisk „+ Sąsiednie części” dodaje poligony oddalone od zaznaczonych nie bardziej niż tyle."})
	_add("map_mpp_min", "float", "Maksymalne przybliżenie", 0.1, {"min": 0.02, "max": 2.0, "step": 0.02, "suffix": " m/px"})
	_add("map_mpp_max", "float", "Maksymalne oddalenie", 8.0, {"min": 2.0, "max": 50.0, "step": 1.0, "suffix": " m/px"})
	_add("map_refresh_delay", "float", "Opóźnienie odświeżenia po ruchu", 0.4, {"min": 0.1, "max": 3.0, "step": 0.1, "suffix": " s", "tip": "Ile mapa czeka po zoomie, zanim pobierze nowe dane."})
	_add("map_max_image_px", "int", "Maks. bok pobieranego obrazu", 1600, {"min": 256, "max": 4096, "step": 64, "suffix": " px"})
	_section("map_look", "Wygląd obrysów", "place", true)
	_add("map_color_outline", "color", "Kolor obrysów", "#4cc9f0")
	_add("map_color_selected", "color", "Kolor wybranego budynku", "#ffb347")
	_add("map_line_width", "float", "Grubość linii obrysu", 1.5, {"min": 0.5, "max": 6.0, "step": 0.5, "suffix": " px"})
	_add("map_fill_alpha", "float", "Przezroczystość wypełnienia wyboru", 0.35, {"min": 0.0, "max": 1.0, "step": 0.05})
	_section("src", "Obrys z pliku GeoJSON (zamiast mapy)", "place", true, "Alternatywa dla wyboru z mapy: wczytaj własny obrys. Współrzędne lon/lat są wykrywane i przeliczane na metry.")
	_add("src_geojson_path", "path", "Plik GeoJSON", "res://samples/sample_building.geojson", {"filters": ["*.geojson,*.json ; GeoJSON"], "tip": "Współrzędne lon/lat są wykrywane i przeliczane na metry."})
	_button("act_src_import", "Importuj GeoJSON")
	_button("act_src_sample", "Załaduj przykładowy budynek (L)")

	# ---------------------------------------------------------------- 2. building
	_section("bld_height", "Ściany", "building", false, "", true)
	_add("model_wall_height", "float", "Wysokość ścian", 8.0, {"min": 2.0, "max": 60.0, "step": 0.5, "suffix": " m"})
	_button("act_walls_from_tex", "Dopasuj wysokość ścian do proporcji tekstury", "Liczy wysokość ścian z proporcji zdjęcia długiej ściany (okna przestają być spłaszczone lub rozciągnięte). Ewidencja zna tylko przybliżoną liczbę kondygnacji.")
	_add("model_use_floors", "bool", "Wysokość z liczby kondygnacji (EGiB)", true, {"tip": "Po wybraniu budynku z mapy ustaw wysokość ścian = kondygnacje × wysokość kondygnacji, jeśli EGiB podaje kondygnacje."})
	_add("model_floor_height", "float", "Wysokość jednej kondygnacji", 3.0, {"min": 2.0, "max": 6.0, "step": 0.1, "suffix": " m"})
	_section("bld_roof", "Dach", "roof", false, "", true)
	_add("model_roof_type", "choice", "Typ dachu", "gable", {"options": [["gable", "Dwuspadowy"], ["hip", "Kopertowy (4 połacie)"], ["custom", "Własny – kierunki spadków"], ["flat", "Płaski"]], "tip": "Dwuspadowy rysujesz na zdjęciu szczytu. Kopertowy ma cztery połacie schodzące do okapu. Własny: w oknie z rzutem z góry ustawiasz spadek każdej krawędzi albo robisz z niej ścianę szczytową."})
	_add("model_roof_height", "float", "Wysokość dachu ponad okap", 3.0, {"min": 0.0, "max": 40.0, "step": 0.1, "suffix": " m"})
	_add("model_roof_overhang", "float", "Wysunięcie dachu poza ściany (okap)", 0.5, {"min": 0.0, "max": 3.0, "step": 0.05, "suffix": " m", "tip": "O tyle dach wystaje poza obrys budynku - przy okapie i przy szczytach. Spadek dachu zostaje ten sam."})
	_add("model_roof_gable_same", "bool", "Wysunięcie szczytów jak okap", true, {"hidden": true})
	_add("model_roof_over_gable", "float", "Wysunięcie dachu przy szczytach", 0.5, {"min": 0.0, "max": 3.0, "step": 0.05, "suffix": " m", "hidden": true})
	_add("model_roof_asym", "bool", "Dach asymetryczny", false, {"hidden": true})
	_add("model_roof_ridge_shift", "float", "Przesunięcie kalenicy", 0.0, {"min": -10.0, "max": 10.0, "step": 0.05, "suffix": " m", "hidden": true})
	_add("model_roof_over_eave_b", "float", "Okap strony B (dach asymetryczny)", 0.5, {"min": 0.0, "max": 3.0, "step": 0.05, "suffix": " m", "hidden": true})
	_add("model_chimneys", "string", "Kominy (JSON)", "[]", {"hidden": true})
	_add("tex_sheet_key", "string", "Klucz ułożonego arkusza", "", {"hidden": true})
	_add("model_roof_gen", "string", "Wygenerowany dach (JSON)", "[]", {"hidden": true})
	_add("model_roof_custom", "string", "Dach własny (JSON)", "{}", {"hidden": true})
	_add("model_emitters", "string", "Emitery (JSON)", "[]", {"hidden": true})
	_add("model_channels", "string", "Kanały sterowania (JSON)", "[]", {"hidden": true})
	_button("act_chimney_editor", "Kominy – generator…", "Okno z rzutem z góry i dwoma rzutami bocznymi: dodajesz komin (szerokość, długość, wysokość z palca), ustawiasz go na dachu, przesuwasz po połaci i zmieniasz wysokość. Korpus dostaje powielany fragment ściany z arkusza.")
	_button("act_roof_editor", "Dach dwuspadowy – profil na zdjęciu szczytu…", "Okno ze zdjęciem szczytu i rzutem z góry: rysujesz profil dachu (wierzchołki, załamania, wysunięcie), kalenicę i walmy. Zmiany od razu widać na modelu.")
	_button("act_roof_custom", "Dach własny – rzut z góry, kierunki spadków…", "Okno z rzutem budynku z góry: kliknij krawędź i ustaw jej spadek (strzałka pokazuje kierunek) albo zrób z niej ścianę szczytową. Działa dla typu dachu „Własny”.")
	_add("model_roof_thickness", "float", "Grubość dachu", 0.15, {"min": 0.0, "max": 1.0, "step": 0.01, "suffix": " m", "tip": "Dach jest osobną bryłą (z spodem i krawędzią), nie samą powierzchnią."})
	_add("model_ridge_axis", "choice", "Kalenica biegnie wzdłuż", "long", {"options": [["long", "dłuższego boku"], ["short", "krótszego boku"]], "tip": "Wzdłuż dłuższego boku to typowy dach dwuspadowy."})
	_section("bld_adv", "Zaawansowane: części i obrys", "building", true)
	_add("model_annex_ratio", "float", "Dobudówki: wysokość względem głównej bryły", 0.7, {"min": 0.3, "max": 1.0, "step": 0.05, "tip": "Gdy EGiB nie podaje kondygnacji dobudówki, jej ściany mają tyle głównej wysokości."})
	_add("model_annex_roof_height", "float", "Dobudówki: wzniesienie dachu pulpitowego", 1.0, {"min": 0.2, "max": 6.0, "step": 0.1, "suffix": " m", "tip": "Dach dobudówki opada od ściany głównej bryły. Wartość jest ograniczana tak, by dach nie sięgał okapu budynku głównego."})
	_add("model_snap_tol", "float", "Doklejanie części (tolerancja szczelin)", 0.35, {"min": 0.0, "max": 1.5, "step": 0.05, "suffix": " m", "tip": "Wektoryzacja zostawia szczeliny między częściami jednego budynku. Wierzchołki bliższe niż tyle są przyciągane do sąsiedniej części, a wspólne ściany wycinane."})
	_add("model_align_obb", "bool", "Wyrównaj obrys do osi", true, {"tip": "Obraca obrys tak, by najmniejszy opisany prostokąt był równoległy do osi. Dzięki temu kalenica i tekstury ułożą się zgodnie z budynkiem."})

	# ---------------------------------------------------------------- 3. textures
	_section("tex_prepare", "1. Prompt dla GPT", "tex", false, "Gotowy opis zadania dla ChatGPT: z Twoich zdjęć zrobi fototekstury każdego widocznego boku (wyprostowane, wyczyszczone, w jednej skali) w 8 sektorach arkusza 4096 × 4096 px (S1–S8, rzędami od lewej). Wklej go razem ze zdjęciami budynku.")
	_button("act_gpt_prompt", "Generuj prompt dla GPT…", "Otwiera okno z gotowym tekstem i przyciskiem „Kopiuj”. Tekst trafia też do pliku texture/prompt_gpt.txt w folderze projektu.")
	_section("tex_source", "2. Płótno od GPT", "tex", false, "Zapisz obraz od GPT na dysku i wskaż go tu. Program wytnie obrazy z sektorów (albo z ramek, jeśli są), nada im kody według sektora (S1 ściana długa … S5 dach, S6–S8 dobudówki), ułoży je w jednej skali według rzeczywistych wymiarów ścian i pokaże na modelu. Złe kody poprawisz w „Przyporządkuj panele…”. Zwykłe zdjęcie też działa.")
	_add("tex_source", "path", "Plik płótna od GPT (lub atlas JSON)", "", {"picker": true, "filters": ["*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga,*.json ; Obraz lub atlas JSON"], "tip": "Puste = bez tekstury."})
	_button("act_tex_panels", "Przyporządkuj panele…", "Pokazuje płótno z wykrytymi ramkami: możesz poprawić rozmiar ramki i kod (S1 długa A, S2 długa B, S3/S4 szczyty, S5 dach, S6+ dobudówki) albo narysować ramkę ręcznie.")
	_add("tex_panels", "string", "Panele płótna (JSON)", "", {"hidden": true})
	_add("tex_enabled", "bool", "Teksturuj model", false, {"tip": "Włącza się samo po wczytaniu tekstury."})
	_add("tex_sheet_layout", "string", "Układ arkusza (JSON)", "", {"hidden": true})
	_add("tex_px_per_m", "float", "Skala arkusza", 0.0, {"min": 0.0, "max": 1000.0, "step": 1.0, "suffix": " px/m", "tip": "Ile pikseli arkusza odpowiada 1 m ściany. 0 = rozciągnij zdjęcie na całą ścianę. Używana w prompcie dla GPT i w metadanych eksportu oraz do kafelkowania dachu; ściany zawsze dostają cały obraz na całą ścianę."})
	_button("act_tex_preview", "Podgląd cięcia na regiony…", "Pokazuje obraz z ramkami i nazwami wykrytych regionów.")
	_button("act_tex_clear", "Usuń teksturę (model bez tekstur)")
	_section("tex_roofsec", "Dach ze zdjęcia szczytu", "roof", false, "Gdy tekstura ma zdjęcie szczytu z widocznym dachem, nachylenie dachu można zmierzyć na zdjęciu zamiast ustawiać ręcznie.")
	_add("model_roof_from_tex", "bool", "Kąt dachu z tekstury (gdy jest szczyt ze zdjęcia)", true, {"tip": "Gdy model jest teksturowany zdjęciem szczytu z widocznym dachem, wysokość dachu jest liczona z jego nachylenia na zdjęciu. Wyłącz, aby użyć wysokości z suwaka."})
	_add("model_walls_from_tex", "bool", "Wysokość ścian z proporcji zdjęcia (arkusz GPT)", true, {"tip": "Gdy model ma arkusz z szablonu, wysokość ścian = długość ściany / proporcje jej zdjęcia. Ewidencja zna tylko przybliżoną liczbę kondygnacji. Ręczna zmiana wysokości ścian wyłącza tę opcję."})
	_button("act_roof_from_tex", "Dopasuj wysokość dachu do tekstury", "Mierzy nachylenie dachu na zdjęciu szczytu i ustawia wysokość dachu. Działa też po fakcie, gdy zmienisz teksturę.")
	_section("tex_assign", "3. Dobór na ściany i dach", "tex", true, "Zostaw „Automatycznie” albo wskaż konkretne zdjęcie dla każdej ściany.")
	_add("tex_wall_all", "choice", "Jedna tekstura na wszystkie ściany", "auto", {"options": [["auto", "Nie (dobierz według ściany)"]], "tip": "Wybrane zdjęcie zostanie położone na każdej ścianie, niezależnie od ustawień poniżej.", "stack": true})
	_add("tex_long_a", "choice", "Długa ściana – strona A", "auto", {"options": [["auto", "Automatycznie"]]})
	_add("tex_long_b", "choice", "Długa ściana – strona B", "auto", {"options": [["auto", "Automatycznie"]]})
	_add("tex_gable_a", "choice", "Ściana szczytowa – strona A", "auto", {"options": [["auto", "Automatycznie"]]})
	_add("tex_gable_b", "choice", "Ściana szczytowa – strona B", "auto", {"options": [["auto", "Automatycznie"]]})
	_add("tex_roof", "choice", "Dach", "auto", {"options": [["auto", "Automatycznie"]]})
	_button("act_tex_next", "Następny wariant elewacji")
	_button("act_tex_random", "Losuj tekstury", "Losowo przetasowuje wybór zdjęć dla ścian i dachu (przy ustawieniach „Automatycznie”).")
	_section("tex_relief", "4. Relief (normal map z fotografii)", "tex", true, "Fotografie nie mają głębi, więc relief powstaje z jasności zdjęcia: ciemne spoiny i szczeliny są „w dole”, jasne powierzchnie „w górze”. Najlepiej widać go przy niskim słońcu (zakładka Widok).")
	_add("tex_relief_enabled", "bool", "Generuj relief", true)
	_add("tex_relief_wall", "float", "Siła reliefu – ściany", 1.0, {"min": 0.0, "max": 4.0, "step": 0.1, "tip": "0 = płasko. Cegła i tynk zwykle dobrze wyglądają przy 0.5–1.5."})
	_add("tex_relief_roof", "float", "Siła reliefu – dach", 0.7, {"min": 0.0, "max": 4.0, "step": 0.1, "tip": "Dachówka i papa lubią mocniejszy relief niż elewacja."})
	_button("act_tex_export_normal", "Eksportuj mapy normalnych (PNG)", "Zapisuje albedo i wygenerowaną normal mapę użytych tekstur do folderu biblioteki/_export, by użyć ich w innym programie.")
	_section("tex_relief_adv", "Relief: szczegóły", "tex", true)
	_add("tex_relief_detail", "float", "Wielkość szczegółu", 24.0, {"min": 4.0, "max": 128.0, "step": 2.0, "suffix": " px", "tip": "Największy element, który jeszcze liczy się jako relief (przy tekstury 512 px). Mały = tylko rysy i spoiny; duży = także wypukłe pasy, gzymsy, ramy okien."})
	_add("tex_relief_smooth", "float", "Wygładzenie szumu", 1.0, {"min": 0.0, "max": 6.0, "step": 0.5, "tip": "Usuwa ziarno i artefakty JPEG, które inaczej dawałyby chropowatą „skórkę”."})
	_add("tex_relief_invert", "bool", "Odwróć relief", false, {"tip": "Włącz, jeśli spoiny wyglądają na wypukłe, a cegły na wklęsłe."})
	_add("tex_parallax", "bool", "Paralaksa (głębia, wolniejsze)", false, {"tip": "Dodatkowo przesuwa teksturę zależnie od kąta patrzenia, co daje wrażenie prawdziwej głębi. Kosztuje wydajność."})
	_add("tex_parallax_scale", "float", "Głębokość paralaksy", 0.03, {"min": 0.005, "max": 0.15, "step": 0.005})
	_section("tex_mat", "Skala i materiał", "tex", true)
	_add("tex_keep_aspect", "bool", "Zachowaj proporcje (powtarzaj teksturę)", false, {"tip": "Wyłączone: tekstura jest rozciągana raz na całą ścianę."})
	_add("tex_roof_repeat", "bool", "Powtarzaj teksturę dachu", true, {"tip": "Włączone: tekstura układa się kaflami w proporcjach oryginału. Wyłączone: jedna tekstura rozciągnięta na całą połać."})
	_add("tex_roof_rotate", "bool", "Obróć teksturę dachu o 90°", false, {"tip": "Użyj, jeśli rzędy dachówek biegną w złą stronę względem spadku."})
	_add("tex_roof_tile_m", "float", "Szerokość kafla dachu", 3.0, {"min": 0.5, "max": 20.0, "step": 0.5, "suffix": " m"})
	_add("tex_min_edge", "float", "Ściana „krótka” (wycinek zdjęcia)", 2.0, {"min": 0.5, "max": 10.0, "step": 0.5, "suffix": " m", "tip": "Krótsze ściany dostają wycinek zdjęcia w prawdziwej skali, nie ściśnięte całe zdjęcie. Ściany poniżej 0,3 m dostają kolor zastępczy."})
	_add("tex_roughness", "float", "Chropowatość materiału", 0.95, {"min": 0.0, "max": 1.0, "step": 0.05})
	_add("tex_wall_color", "color", "Kolor ścian bez tekstury", "#b96e4a")
	_add("tex_roof_color", "color", "Kolor dachu bez tekstury", "#414b5b")
	_section("tex_atlas", "Biblioteka zdjęć", "tex", true)
	_add("tex_library_enabled", "bool", "Używaj biblioteki zdjęć", true, {"tip": "Każde zdjęcie (PNG/JPG/WebP) z folderu biblioteki staje się osobną teksturą do wyboru. Rodzaj (dach / elewacja / szczyt / drzwi / okno) jest zgadywany z nazwy pliku lub podfolderu, np. dach_papa.jpg, roof/slate.png, szczyt_cegla.jpg. Reszta to elewacje."})
	_add("tex_library_dir", "path", "Folder biblioteki zdjęć", "user://texture_library", {"dir": true, "tip": "Wrzuć tu zdjęcia fasad i dachów albo użyj przycisku poniżej. Dodatkowo czytany jest folder res://textures/library w projekcie."})
	_button("act_tex_import", "Dodaj zdjęcia do biblioteki…", "Kopiuje wybrane pliki do folderu biblioteki i od razu je wczytuje.")
	_button("act_tex_open_dir", "Otwórz folder biblioteki")
	_section("tex_slice", "Cięcie arkusza (zaawansowane)", "tex", true, "Parametry automatycznego podziału obrazu. Po zmianie użyj „Przeanalizuj obraz ponownie”.")
	_add("tex_slice_mode", "choice", "Tryb", "auto", {"options": [["auto", "Automatycznie"], ["template", "Szablon 4096 (8 sektorów S1–S8)"], ["sheet", "Zawsze tnij na panele"], ["single", "Jedna tekstura (nie tnij)"]], "tip": "Automatycznie: arkusz z ciemnym/jednolitym tłem jest cięty, zwykłe zdjęcie zostaje w całości."})
	_add("tex_slice_sensitivity", "float", "Czułość odróżniania od tła", 0.06, {"min": 0.01, "max": 0.5, "step": 0.01, "tip": "Mniejsza = nawet ciemne fragmenty liczą się jako treść. Większa = tło i szum są pomijane."})
	_add("tex_slice_min_area", "float", "Min. wielkość regionu", 0.15, {"min": 0.01, "max": 5.0, "step": 0.01, "suffix": " %", "tip": "Mniejsze plamki (procent powierzchni arkusza) są ignorowane."})
	_add("tex_slice_gap", "float", "Łączenie stykających się paneli", 2.0, {"min": 0.0, "max": 20.0, "step": 1.0, "suffix": " px", "tip": "Panele oddalone o mniej niż tyle (przy analizie 640 px) zostaną sklejone w jeden."})
	_button("act_tex_reslice", "Przeanalizuj obraz ponownie")
	_button("act_tex_load", "Wczytaj ponownie")
	_add("tex_variant", "int", "Wariant (przy wyborze automatycznym)", 0, {"min": 0, "max": 99, "step": 1, "tip": "Przesuwa wybór elewacji, gdy atlas ma kilka tego samego rodzaju.", "hidden": true})

	# ---------------------------------------------------------------- 4. view
	_section("view_export", "Eksport modelu", "view", false, "Plik .glb (Y w górę, metry) otwiera się w Blenderze i w programie świata bez konwersji. Opis modelu (piętra, wysokość, dach, położenie w EPSG:2180, części świecące) jest zapisany w metadanych węzłów (extras.meta), nie w nazwach.", true)
	_add("export_zip", "bool", "Eksport jako paczka ZIP", false, {"tip": "Po każdym eksporcie (GLB, glTF, T3D) obok plików powstaje też archiwum .zip gotowe do wysłania. GLB: <nazwa>.zip; glTF i T3D: zip całego folderu."})
	_button("act_export_glb", "Eksportuj model do GLB", "Zapisuje <projekt>/exports/<nazwa>.glb oraz <nazwa>.meta.json (te same metadane do wglądu).")
	_button("act_export_gltf", "Eksportuj model do glTF (.gltf + .bin + tekstury)", "Zapisuje <projekt>/exports/gltf/<nazwa>/. To samo co GLB, ale w osobnych plikach – wygodne do ręcznej edycji.")
	_button("act_export_t3d", "Eksportuj model do T3D (MaSzyna)", "Zapisuje <projekt>/exports/t3d/<nazwa>/: models/, textures/ (.tga + .mat), scenery/ (.inc) i gotowy wpis do nodebank.txt. LOD0 0–200 m, LOD1 200–2000 m (bez kominów), dym z kominów.")
	_button("act_open_exports", "Otwórz folder eksportów")
	_add("export_t3d_folder", "string", "T3D: podfolder w modelach i teksturach", "geostudio", {"tip": "Np. mieszkalne – jak w paczkach przykładowych: models/<podfolder>/nazwa.t3d."})
	_add("export_t3d_tex_max", "choice", "T3D: największy bok tekstury", "2048", {"options": [["512", "512 px"], ["1024", "1024 px"], ["2048", "2048 px"], ["4096", "4096 px"]], "tip": "Większe obrazy są pomniejszane przy zapisie do .tga (symulator nie lubi dużych tekstur)."})
	_add("export_t3d_smoke", "bool", "T3D: źródła dymu na kominach", true)
	_add("export_t3d_lights", "bool", "T3D: submodel świateł nocnych (light_on00)", true, {"tip": "Powierzchnie oznaczone w panelu ściany jako świecące trafiają do osobnego submodelu z SelfIllum."})
	_section("view_fx", "Efekty (dym, ogień, deszcz)", "view", true, "Wiatr działa na podgląd cząstek w widoku 3D i jest zapisywany w metadanych emiterów jako współczynnik wiatru (wiatr sceny ustawia symulator).")
	_add("fx_wind_speed", "float", "Wiatr: prędkość", 1.5, {"min": 0.0, "max": 25.0, "step": 0.1, "suffix": " m/s", "tip": "Znosi dym, iskry i deszcz w podglądzie."})
	_add("fx_wind_dir", "float", "Wiatr: kierunek", 90.0, {"min": 0.0, "max": 360.0, "step": 5.0, "suffix": " °", "tip": "W płaszczyźnie modelu: 0° = w stronę +X, 90° = w stronę +Z."})
	_section("view_layers", "Co pokazać", "view", false, "", true)
	_add("view_show_walls", "bool", "Pokaż elewacje", true)
	_add("view_show_roof", "bool", "Pokaż dach", true)
	_add("view_show_ground", "bool", "Pokaż podłoże", true)
	_add("view_show_grid", "bool", "Pokaż siatkę pomocniczą", true)
	_add("view_wireframe", "bool", "Krawędzie siatki (jak „Edged Faces” w 3ds Max)", false, {"tip": "Model cieniowany z narysowanymi krawędziami. Grubość w pikselach, kolor i przezroczystość ustawiasz niżej; krawędzie zasłonięte są bledsze."})
	_add("view_vertices", "bool", "Pokaż wierzchołki", false, {"tip": "Punkty o stałej wielkości na ekranie, z obwódką. Kolor zależy od rodzaju: narożniki obrysu przy gruncie, górne narożniki ścian, wierzchołki dachu i kominów."})
	_section("view_wire", "Krawędzie i wierzchołki", "view", true, "Działa po włączeniu „Krawędzie siatki” lub „Pokaż wierzchołki” wyżej.")
	_add("view_wire_thick", "float", "Grubość krawędzi", 1.6, {"min": 0.5, "max": 8.0, "step": 0.1, "suffix": " px"})
	_add("view_wire_color", "color", "Kolor krawędzi", "#ffd200")
	_add("view_wire_opacity", "float", "Nieprzezroczystość krawędzi", 1.0, {"min": 0.05, "max": 1.0, "step": 0.05})
	_add("view_wire_hidden", "float", "Widoczność krawędzi zasłoniętych", 0.3, {"min": 0.0, "max": 1.0, "step": 0.05, "tip": "0 = ukryte; wartość większa pokazuje krawędzie i wierzchołki zza ścian bledszym kolorem."})
	_add("view_wire_diag", "bool", "Pokaż przekątne trójkątów", false, {"tip": "Domyślnie ukryte: widać krawędzie ścian i połaci, nie podział na trójkąty."})
	_add("view_vert_size", "float", "Wielkość wierzchołków", 9.0, {"min": 3.0, "max": 30.0, "step": 1.0, "suffix": " px"})
	_add("view_vert_outline", "float", "Grubość obwódki wierzchołków", 1.5, {"min": 0.0, "max": 5.0, "step": 0.5, "suffix": " px"})
	_add("view_vert_outline_color", "color", "Kolor obwódki", "#000000")
	_add("view_vert_base", "color", "Wierzchołki: obrys przy gruncie", "#39d353")
	_add("view_vert_eave", "color", "Wierzchołki: górne narożniki ścian", "#ff9f1c")
	_add("view_vert_roof", "color", "Wierzchołki: dach i kominy", "#ff3b6b")
	_section("view_light", "Światło i tło", "view", true)
	_add("view_sun_altitude", "float", "Wysokość słońca nad horyzontem", 48.0, {"min": 5.0, "max": 90.0, "step": 1.0, "suffix": " °"})
	_add("view_sun_azimuth", "float", "Kierunek słońca", -32.0, {"min": -180.0, "max": 180.0, "step": 1.0, "suffix": " °"})
	_add("view_sun_energy", "float", "Jasność słońca", 1.0, {"min": 0.0, "max": 4.0, "step": 0.1})
	_add("view_shadows", "bool", "Cienie", true)
	_add("view_ambient_energy", "float", "Światło otoczenia", 0.5, {"min": 0.0, "max": 2.0, "step": 0.05})
	_add("view_ambient_color", "color", "Kolor światła otoczenia", "#b8c5d8")
	_add("view_bg_mode", "choice", "Tło", "sky", {"options": [["sky", "Niebo"], ["solid", "Jednolity kolor"]]})
	_add("view_bg_color", "color", "Kolor tła (jednolitego)", "#1b2230")
	_add("view_msaa", "choice", "Wygładzanie krawędzi (MSAA)", "4", {"options": [["0", "Wyłączone"], ["2", "2×"], ["4", "4×"], ["8", "8×"]]})
	_section("view_cam", "Kamera", "view", true)
	_button("act_cam_reset", "Resetuj kamerę")
	_add("view_cam_fov", "float", "Kąt widzenia kamery", 70.0, {"min": 20.0, "max": 110.0, "step": 1.0, "suffix": " °"})
	_add("view_cam_yaw", "float", "Startowy obrót kamery", 37.0, {"min": -180.0, "max": 180.0, "step": 1.0, "suffix": " °"})
	_add("view_cam_pitch", "float", "Startowe pochylenie kamery", -20.0, {"min": -77.0, "max": 8.0, "step": 1.0, "suffix": " °"})
	_add("view_cam_fit", "float", "Startowa odległość kamery", 1.8, {"min": 0.5, "max": 6.0, "step": 0.1, "suffix": " × rozmiar", "tip": "Krotność większego wymiaru budynku."})
	_add("view_cam_min_dist", "float", "Min. odległość kamery", 2.0, {"min": 0.5, "max": 50.0, "step": 0.5, "suffix": " m"})
	_add("view_cam_max_dist", "float", "Maks. odległość kamery", 1000.0, {"min": 50.0, "max": 5000.0, "step": 50.0, "suffix": " m"})
	_add("view_cam_rot_speed", "float", "Czułość obrotu myszą", 0.008, {"min": 0.001, "max": 0.03, "step": 0.001})
	_add("view_cam_zoom_step", "float", "Krok zoomu kółkiem", 0.12, {"min": 0.02, "max": 0.5, "step": 0.01})
	_section("view_scene", "Podłoże i siatka", "view", true)
	_add("view_ground_size", "int", "Rozmiar podłoża", 400, {"min": 50, "max": 2000, "step": 50, "suffix": " m"})
	_add("view_ground_color", "color", "Kolor podłoża", "#1b222d")
	_add("view_grid_extent", "int", "Zasięg siatki", 50, {"min": 10, "max": 200, "step": 10, "suffix": " m"})
	_add("view_grid_step", "float", "Oczko siatki", 1.0, {"min": 0.5, "max": 10.0, "step": 0.5, "suffix": " m"})
	_add("view_grid_color", "color", "Kolor siatki", "#34404f")

	# ---------------------------------------------------------------- settings
	_section("proj", "Zapis i pliki projektu", "app", false, "Wszystko o modelu (dane z Geoportalu, tekstura i jej podział, rendery, eksporty) leży w jednym folderze projektu.", true)
	_button("act_mgdot_save", "Zapisz projekt (.mgdot)", "Cały projekt w jednym pliku: dane z Geoportalu, zdjęcia i płótno od GPT, panele S1–S8, dach, kominy, poprawki UV, ustawienia, miniatura i użyty prompt.")
	_button("act_mgdot_save_as", "Zapisz projekt jako…")
	_button("act_project_switch", "Otwórz projekt / zmień folder…", "Okno z ostatnimi plikami .mgdot, folderami i przyciskiem „Otwórz plik projektu”.")
	_button("act_project_render", "Zapisz render teraz")
	_button("act_project_open_dir", "Otwórz folder projektu")
	_add("proj_keep_renders", "int", "Ile ostatnich renderów zachować", 3, {"min": 1, "max": 50, "step": 1, "tip": "Render widoku 3D jest zapisywany do folderu projektu przy zamykaniu programu (renders/lastView_<czas>.png); starsze ponad ten limit są usuwane."})
	_add("meta_author", "string", "Autor modelu", "", {"tip": "Trafia do metadanych eksportu (asset.copyright i geostudio.credits). Np. Imię „nick” Nazwisko."})
	_add("meta_licence", "choice", "Licencja modelu", "", {"options": [["", "brak (wszelkie prawa zastrzeżone)"], ["CC-BY-4.0", "CC BY 4.0"], ["CC-BY-SA-4.0", "CC BY-SA 4.0"], ["CC0-1.0", "CC0 (domena publiczna)"], ["MIT", "MIT"], ["GPL-3.0-only", "GPL 3.0"]], "tip": "Licencja eksportowanego MODELU (identyfikator SPDX). Nie zmienia licencji danych źródłowych (zdjęcia, ortofotomapa)."})
	_add("export_legacy_meta", "bool", "Eksport: dodaj stary układ metadanych (v1)", false, {"tip": "Dopisuje do głównego węzła `extras.meta` w układzie z wersji 1 (dla narzędzi, które jeszcze go czytają). Domyślnie wyłączone: eksport zapisuje profil MaSzyna Reloaded (docs/MODEL_META.md)."})
	_add("ui_last_project", "string", "Ostatni projekt", "", {"hidden": true})
	_add("ui_recent_projects", "string", "Ostatnie projekty", "", {"hidden": true})
	_add("ui_recent_mgdot", "string", "Ostatnie pliki .mgdot", "", {"hidden": true})
	_section("ui", "Program", "app", false, "", true)
	_add("app_fullscreen", "bool", "Start na pełnym ekranie", true, {"tip": "F11 przełącza pełny ekran / okno zmaksymalizowane w trakcie pracy."})
	_add("ui_font_size", "int", "Rozmiar czcionki interfejsu", 14, {"min": 10, "max": 28, "step": 1, "suffix": " pt"})
	_button("act_settings_save", "Zapisz ustawienia teraz", "Ustawienia zapisują się też automatycznie po każdej zmianie.")
	_button("act_settings_reset_all", "Przywróć wszystkie domyślne")
	_add("ui_last_tab", "string", "Ostatnia karta", "place", {"hidden": true})
	_section("svc", "Połączenie z Geoportalem", "app", true, "Adresy i nazwy warstw. Zmieniaj, jeśli usługa zwraca błąd lub pustą mapę.")
	_button("act_svc_test", "Testuj usługi", "Pobiera GetCapabilities i wypisuje dostępne warstwy / typy obiektów.")
	_add("svc_wms_url", "string", "Adres WMS ortofotomapy", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/StandardResolution")
	_add("svc_wms_layer", "string", "Warstwa ortofotomapy", "Raster", {"tip": "Użyj „Testuj usługi”, aby zobaczyć nazwy warstw."})
	_add("svc_wfs_url", "string", "Adres WFS budynków (EGiB)", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/EGIB/WFS/UslugaZbiorcza")
	_add("svc_wfs_typenames", "string", "Typy obiektów budynków (po przecinku)", "ewns:budynki, budynki", {"tip": "Kolejne nazwy są próbowane po kolei."})
	_add("svc_max_features", "int", "Maks. liczba budynków w zapytaniu", 500, {"min": 10, "max": 5000, "step": 10})
	_add("svc_geocode_url", "string", "Wyszukiwarka miejsc (geokodowanie)", "https://nominatim.openstreetmap.org/search", {"tip": "Usługa zgodna z Nominatim (OpenStreetMap): zwraca listę JSON z polami lat, lon, display_name. Limit publicznego serwera: 1 zapytanie na sekundę."})
	_add("ui_place_history", "string", "Ostatnie wyszukiwania", "", {"hidden": true})
	_add("svc_timeout", "float", "Limit czasu zapytania", 25.0, {"min": 5.0, "max": 120.0, "step": 5.0, "suffix": " s"})
	_section("svc_cache", "Geoportal: cache i limity zapytań", "app", true, "Odpowiedzi serwera (kafelki ortofotomapy, obrysy budynków) są zapisywane na dysku, więc przewijanie mapy i powrót w znane miejsce nie obciążają serwera.")
	_add("svc_cache_days", "float", "Ważność cache", 30.0, {"min": 1.0, "max": 365.0, "step": 1.0, "suffix": " dni", "tip": "Starsze wpisy są odświeżane; gdy serwer nie odpowiada, służą jako kopia zapasowa."})
	_add("svc_cache_mb", "int", "Maks. rozmiar cache", 500, {"min": 50, "max": 5000, "step": 50, "suffix": " MB"})
	_add("svc_max_parallel", "int", "Zapytań naraz", 2, {"min": 1, "max": 6, "step": 1, "tip": "Mniej = grzeczniej wobec serwera."})
	_add("svc_min_gap_ms", "int", "Odstęp między zapytaniami", 150, {"min": 0, "max": 2000, "step": 50, "suffix": " ms"})
	_button("act_cache_clear", "Wyczyść cache Geoportalu")
