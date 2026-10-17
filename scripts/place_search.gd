class_name PlaceSearch
extends RefCounted
## Place search box of the first tab: Nominatim results and the history of the last searches.
## The widgets are created by the main scene (sidebar card "Szukaj miejsca") and handed over here.

var app                          # the main scene
var edit: LineEdit
var list: ItemList
var caption: Label               # "Wyniki (n)" / "Ostatnie wyszukiwania (n)" above the list
var entries: Array = []          # what the list shows: [{name, lat, lon}]


func _init(main_scene) -> void:
	app = main_scene


func fill_list(found: Array, caption_text: String) -> void:
	entries = found
	list.clear()
	for e in found:
		var full := str(e["name"])
		var cut := full.find(",")
		list.add_item(full if cut < 0 else full.substr(0, cut).strip_edges() + " — " + full.substr(cut + 1).strip_edges())
		list.set_item_tooltip(list.item_count - 1, full)
	caption.text = caption_text
	list.visible = not found.is_empty()


func show_history() -> void:
	var h: Array = PlaceHistory.list(app.settings.s("ui_place_history"))
	fill_list(h, ("Ostatnie wyszukiwania (%d). Kliknij, aby tam wrócić." % h.size()) if not h.is_empty() else "Wpisz nazwę i naciśnij Enter. Historia ostatnich 30 wyszukiwań pojawi się tutaj.")


func search() -> void:
	var q := edit.text.strip_edges()
	if q == "":
		show_history()
		return
	app._set_status("Szukam: %s…" % q)
	var found: Array = await app.geo.search_places(q)
	if found.is_empty():
		fill_list([], "Nic nie znaleziono (albo wyszukiwarka nie odpowiada – sprawdź Opcje → Połączenie).")
		app._set_status("Brak wyników dla „%s”." % q)
		return
	fill_list(found, "Wyniki (%d). Kliknij, aby przejść na mapie." % found.size())
	app._set_status("Znaleziono %d miejsc dla „%s”." % [found.size(), q])


func choose(i: int) -> void:
	if i < 0 or i >= entries.size():
		return
	var e: Dictionary = entries[i]
	app.settings.set_value("ui_place_history", PlaceHistory.push(app.settings.s("ui_place_history"), e))
	if app.project_required:
		app.settings.save()
	app._go_to_latlon(float(e["lat"]), float(e["lon"]))
	app._set_status("Przeszedłem do: %s" % e["name"])
