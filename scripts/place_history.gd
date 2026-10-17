class_name PlaceHistory
extends RefCounted
## Last searched places, newest first, stored as one JSON string in the settings (ui_place_history).
## An entry is {"name": String, "lat": float, "lon": float}. The same place is never listed twice.

const MAX_ITEMS := 30


static func list(stored: String) -> Array:
	var d = JSON.parse_string(stored) if stored.strip_edges() != "" else null
	var out: Array = []
	if typeof(d) == TYPE_ARRAY:
		for e in d:
			if typeof(e) == TYPE_DICTIONARY and e.has("name") and e.has("lat") and e.has("lon"):
				out.append({"name": str(e["name"]), "lat": float(e["lat"]), "lon": float(e["lon"])})
	return out


static func push(stored: String, entry: Dictionary, max_items := MAX_ITEMS) -> String:
	var items := list(stored)
	var fresh: Array = [entry]
	for e in items:
		var same_name := str(e["name"]).to_lower() == str(entry["name"]).to_lower()
		var same_spot := absf(float(e["lat"]) - float(entry["lat"])) < 1e-4 and absf(float(e["lon"]) - float(entry["lon"])) < 1e-4
		if not (same_name or same_spot) and fresh.size() < max_items:
			fresh.append(e)
	return JSON.stringify(fresh)


## Answer of Nominatim (format=jsonv2) -> [{name, lat, lon}].
static func parse_nominatim(text: String) -> Array:
	var d = JSON.parse_string(text)
	var out: Array = []
	if typeof(d) != TYPE_ARRAY:
		return out
	for e in d:
		if typeof(e) != TYPE_DICTIONARY or not e.has("lat") or not e.has("lon"):
			continue
		out.append({"name": str(e.get("display_name", e.get("name", "?"))), "lat": float(e["lat"]), "lon": float(e["lon"])})
	return out
