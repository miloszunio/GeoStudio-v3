class_name ProfileExport
extends RefCounted
## The metadata the glTF export carries by default: GeoStudio's profile on top of the MaSzyna Reloaded model format
## (docs/MODEL_META.md). Pure helpers - they take the export info and return dictionaries.
##
##   asset.generator / asset.copyright                glTF
##   asset.extras.model_format_version / osm / geo    the Reloaded profile
##   asset.extras.geostudio                           our own data (footprints, roofs, chimneys, surfaces, channels, credits)
##   node.extras.semantic_id                          stable dot-separated ids

const MODEL_FORMAT_VERSION := "0.4.0"
const PROFILE_VERSION := "3"


# ---------------------------------------------------------------------------------------------- orientation

## Compass side ("N", "E", "S", "W") a direction in the model's (x, z) plane looks at; "" when the model is not placed in the world.
static func compass(placement: Dictionary, vx: float, vz: float) -> String:
	if placement.is_empty() or (absf(vx) < 1e-6 and absf(vz) < 1e-6):
		return ""
	var lx: Array = placement["local_x"]
	var lz: Array = placement["local_z"]
	var east := vx * float(lx[0]) + vz * float(lz[0])
	var north := vx * float(lx[1]) + vz * float(lz[1])
	var bearing := fposmod(rad_to_deg(atan2(east, north)), 360.0)
	if bearing >= 315.0 or bearing < 45.0:
		return "N"
	if bearing < 135.0:
		return "E"
	if bearing < 225.0:
		return "S"
	return "W"


## Direction of the model's local +Z, clockwise from geographic north, degrees [0, 360).
static func heading(placement: Dictionary) -> float:
	var lz: Array = placement["local_z"]
	return fposmod(rad_to_deg(atan2(float(lz[0]), float(lz[1]))), 360.0)


## `geo` of the Reloaded profile: WGS84 lat/lng of the model origin and the heading of local +Z. {} without a placement.
static func geo(placement: Dictionary) -> Dictionary:
	if placement.is_empty() or str(placement.get("crs", "")) != "EPSG:2180":
		return {}
	var o: Array = placement["origin"]
	var ll: Vector2 = GeoportalClient.e2180_to_lonlat(float(o[0]), float(o[1]))
	return {"lat": snappedf(ll.y, 0.0000001), "lng": snappedf(ll.x, 0.0000001), "heading": snappedf(heading(placement), 0.01)}


# ---------------------------------------------------------------------------------------------- OSM tags

## Tags of the `osm` map (all values are strings, as in OSM) from the v1 meta of the building.
static func osm_tags(m: Dictionary) -> Dictionary:
	var t := {"building": "yes"}
	if int(m.get("floors", 0)) > 0:
		t["building:levels"] = str(int(m["floors"]))
	if float(m.get("height", 0.0)) > 0.0:
		t["height"] = "%.1f" % float(m["height"])
	if str(m.get("roof_shape", "")) != "":
		t["roof:shape"] = str(m["roof_shape"])
	if float(m.get("roof_height", 0.0)) > 0.0:
		t["roof:height"] = "%.1f" % float(m["roof_height"])
	if str(m.get("colour", "")) != "":
		t["building:colour"] = str(m["colour"])
	if not (m.get("egib_ids", []) as Array).is_empty():
		t["ref:egib"] = ";".join(PackedStringArray(m["egib_ids"]))
	return t


# ---------------------------------------------------------------------------------------------- credits

static func iso_utc_now() -> String:
	var t := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]


## "2026-10-21 19:08:00" (local time, as the project stores it) -> "2026-10-21T17:08:00Z". "" stays "".
static func local_to_iso_utc(local_ts: String) -> String:
	if local_ts.strip_edges() == "":
		return ""
	var unix := Time.get_unix_time_from_datetime_string(local_ts.replace(" ", "T"))
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix - bias * 60)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]


static func credits(info: Dictionary) -> Dictionary:
	var c := {"modified": iso_utc_now()}
	var created := str(info.get("created", ""))
	c["created"] = created if created != "" else c["modified"]
	if str(info.get("author", "")) != "":
		c["author"] = str(info["author"])
	if str(info.get("licence", "")) != "":
		c["licence"] = str(info["licence"])
		c["licence_url"] = "https://spdx.org/licenses/%s.html" % str(info["licence"])
	var src: Array = []
	if str(info.get("source", "")).to_lower().contains("egib") or str(info.get("source", "")).to_lower().contains("geoportal"):
		src.append({"name": "Geoportal.gov.pl (EGiB, ortofotomapa)", "url": "https://www.geoportal.gov.pl", "licence": "warunki usługi GUGiK", "note": "sprawdź warunki przed publikacją"})
	if info.get("texture", null) != null:
		src.append({"name": "Tekstura: " + str((info["texture"] as Dictionary).get("file", "")), "licence": "", "note": "licencja zdjęć do uzupełnienia"})
	if not src.is_empty():
		c["sources"] = src
	return c


static func copyright_line(info: Dictionary) -> String:
	if str(info.get("author", "")) == "":
		return ""
	var year: int = int(Time.get_datetime_dict_from_system(true)["year"])
	var s := "© %d %s" % [year, str(info["author"])]
	if str(info.get("licence", "")) != "":
		s += ", " + str(info["licence"])
	return s


# ---------------------------------------------------------------------------------------------- asset block

## What is written into the glTF `asset` object. v1: the v1 meta dictionary (ModelMeta.building).
## surfaces / channels: lists computed by the exporter.
static func asset_patch(info: Dictionary, v1: Dictionary, surfaces: Array, channels: Array) -> Dictionary:
	var gs: Dictionary = v1.duplicate(true)
	for k in ["generator", "meta_version"]:
		gs.erase(k)
	gs["profile_version"] = PROFILE_VERSION
	if not surfaces.is_empty():
		gs["surfaces"] = surfaces
	if not channels.is_empty():
		gs["channels"] = channels
	gs["credits"] = credits(info)
	var extras := {"model_format_version": MODEL_FORMAT_VERSION, "osm": osm_tags(v1), "geostudio": gs}
	var g := geo(info.get("placement", {}) if info.get("placement", null) != null else {})
	if not g.is_empty():
		extras["geo"] = g
	var patch := {"generator": "GeoStudio " + str(info.get("app_version", "")), "extras": extras}
	var cr := copyright_line(info)
	if cr != "":
		patch["copyright"] = cr
	return patch


# ---------------------------------------------------------------------------------------------- node extras

## semantic_id of a part node: building.part_<n>.walls | walls_lit | roof | chimney_<k> (k counts from 0).
static func node_semantic_id(layer: String, part: int, lit: bool, chimney_id: int) -> String:
	var base := "building.part_%d." % part
	if layer == "chimney":
		return base + "chimney_%d" % maxi(chimney_id - 1, 0)
	return base + layer + ("_lit" if lit else "")


## `extras` of a mesh node of the building. A node made of lit surfaces is a light layer of the Reloaded profile.
static func node_extras(layer: String, part: int, lit: bool, chimney_id: int, light_id: int) -> Dictionary:
	var gs := ModelMeta.submodel(layer, part, lit)
	if chimney_id > 0:
		gs["chimney_id"] = chimney_id
	var e := {"semantic_id": node_semantic_id(layer, part, lit, chimney_id), "geostudio": gs}
	if lit:
		e["light_id"] = light_id
		e["light_state"] = "on"
	return e
