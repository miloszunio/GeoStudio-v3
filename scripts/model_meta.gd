class_name ModelMeta
extends RefCounted
## The meta layer of an exported model (see docs/MODEL_META.md for the contract).
## The mesh only says what the model looks like; everything that has a meaning (how many floors, how
## high, which part glows) is written here, into glTF `extras.meta`, and read from there - never
## guessed from node names.

const VERSION := 1


## Meta of the root node.
## info: name, source, egib_ids, floors, texture {file, px_per_m}, colour, placement {...},
##       parts: [{wall_h, roof_h, roof_kind ("gable"|"flat"|"shed"), ridge_along ("along"|"across"),
##                footprint: [[x, z], ...]}]
static func building(info: Dictionary) -> Dictionary:
	var parts: Array = info.get("parts", [])
	var m := {
		"meta_version": VERSION,
		"model_type": "building",
		"generator": "Photo-to-3D Studio",
		"name": str(info.get("name", "")),
		"source": str(info.get("source", "")),
		"parts": parts.size(),
	}
	if not (info.get("egib_ids", []) as Array).is_empty():
		m["egib_ids"] = info["egib_ids"]
	if int(info.get("floors", 0)) > 0:
		m["floors"] = int(info["floors"])
	if not parts.is_empty():
		var main: Dictionary = parts[0]
		var top := 0.0
		for p in parts:
			top = maxf(top, float(p["wall_h"]) + float(p["roof_h"]))
		m["height"] = snappedf(top, 0.01)
		m["wall_height"] = snappedf(float(main["wall_h"]), 0.01)
		m["roof_shape"] = roof_shape(str(main["roof_kind"]), float(main["roof_h"]))
		m["roof_height"] = snappedf(float(main["roof_h"]), 0.01)
		if m["roof_shape"] == "gabled" or m["roof_shape"] == "skillion":
			m["roof_orientation"] = str(main.get("ridge_along", "along"))
		var outlines: Array = []
		for p in parts:
			outlines.append(p.get("footprint", []))
		m["footprints"] = outlines
		var roofs: Array = []
		for pi in range(parts.size()):
			var rp: Dictionary = {}
			for k in ["ridge_shift", "roof_angles", "roof_profile", "roof_hip_a", "roof_hip_b"]:
				if parts[pi].has(k):
					rp[k] = parts[pi][k]
			if not rp.is_empty():
				rp["part"] = pi
				roofs.append(rp)
		if not roofs.is_empty():
			m["part_roofs"] = roofs
	if str(info.get("colour", "")) != "":
		m["colour"] = info["colour"]
	for k in ["chimneys"]:
		if not (info.get(k, []) as Array).is_empty():
			m[k] = info[k]
	if info.get("placement", null) != null:
		m["placement"] = info["placement"]
	if info.get("texture", null) != null:
		m["texture"] = info["texture"]
	return m


## OSM-style names for the roof, which is also what the world loader's inspector uses.
static func roof_shape(kind: String, roof_h: float) -> String:
	if kind == "flat" or roof_h <= 0.001:
		return "flat"
	return "skillion" if kind == "shed" else "gabled"


## Meta of one submodel (a mesh node). `lit` marks a part that glows (windows, lamps).
static func submodel(layer: String, part: int, lit: bool) -> Dictionary:
	var m := {"layer": layer, "part": part, "part_role": "main" if part == 0 else "annex"}
	if lit:
		m["emissive_light"] = true
	return m


## Where the model stands. The outline is turned and centred when the model is built; this undoes it:
##   E = origin[0] + x * local_x[0] + z * local_z[0]
##   N = origin[1] + x * local_x[1] + z * local_z[1]       (x, z = glTF node coordinates, metres)
## src_center: centre of the source outline (EPSG:2180), rotation_deg: turn applied to the outline,
## local_center: centre that was removed afterwards.
static func placement(src_center: Vector2, rotation_deg: float, local_center: Vector2) -> Dictionary:
	var th := deg_to_rad(rotation_deg)
	var d0 := local_center.rotated(th)
	return {
		"crs": "EPSG:2180",
		"origin": [snappedf(src_center.x + d0.x, 0.001), snappedf(src_center.y - d0.y, 0.001)],
		"local_x": [snappedf(cos(th), 1e-9), snappedf(-sin(th), 1e-9)],
		"local_z": [snappedf(-sin(th), 1e-9), snappedf(-cos(th), 1e-9)],
		"rotation_deg": snappedf(rotation_deg, 0.0001),
	}


## Local metres -> EPSG:2180 with the placement above.
## Returns [E, N] as doubles (a Vector2 is 32-bit and would lose ~3 cm at EPSG:2180 magnitudes).
static func to_world(pl: Dictionary, x: float, z: float) -> Array:
	var o: Array = pl["origin"]
	var lx: Array = pl["local_x"]
	var lz: Array = pl["local_z"]
	return [float(o[0]) + x * float(lx[0]) + z * float(lz[0]), float(o[1]) + x * float(lx[1]) + z * float(lz[1])]
