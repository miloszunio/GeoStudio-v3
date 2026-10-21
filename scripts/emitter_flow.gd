class_name EmitterFlow
extends RefCounted
## Emitters: places on the model that give off light, sound or smoke (draft contract: docs/MODEL_META.md, "v2").
## They are DATA only - nothing is cut out of the mesh. Stored as JSON in the hidden settings `model_emitters` and
## `model_channels` (so they travel with the project). In the 3D view they show as small markers (node "EmitterGizmos",
## a sibling of the building, so the exporters never see it).
##
## One emitter: {id, kind, channel, part, wall (0-based footprint edge), rect [u, v, w, h] (m; light_surface only),
##               pos [x, y, z] (m, building coordinates), yaw, pitch, cone (deg), range (m), colour "#rrggbb", strength,
##               chimney (1-based, smoke only)}
## One channel: {id, type "switch"|"level", default (0..1), ramp_up, ramp_down (s)}

const KEY := "model_emitters"
const KEY_CH := "model_channels"

## [kind id, button label, group] - group: light | audio | smoke (also the `kind` of the exported emitter)
const KINDS := [
	["light_surface", "Światło – powierzchnia (okno, szyld)", "light"],
	["light_point", "Światło – punktowe (żarówka)", "light"],
	["light_spot", "Światło – reflektor (latarnia)", "light"],
	["audio_omni", "Dźwięk – dookólny", "audio"],
	["audio_dir", "Dźwięk – kierunkowy", "audio"],
	["smoke", "Dym – komin", "smoke"],
]

var app


func _init(main_scene) -> void:
	app = main_scene


# ---------------------------------------------------------------------------------------------- data

static func kind_label(kind: String) -> String:
	for k in KINDS:
		if k[0] == kind:
			return str(k[1])
	return kind


static func kind_group(kind: String) -> String:
	for k in KINDS:
		if k[0] == kind:
			return str(k[2])
	return "light"


static func normalize(e: Dictionary) -> Dictionary:
	var kind := str(e.get("kind", "light_point"))
	var known := false
	for k in KINDS:
		if k[0] == kind:
			known = true
	if not known:
		kind = "light_point"
	var r: Array = e.get("rect", [])
	if r.size() != 4:
		r = [0.5, 1.0, 1.0, 1.2]
	var p: Array = e.get("pos", [])
	if p.size() != 3:
		p = [0.0, 3.0, 0.0]
	return {
		"id": str(e.get("id", "E1")), "kind": kind, "channel": str(e.get("channel", "")),
		"part": maxi(int(e.get("part", 0)), 0), "wall": maxi(int(e.get("wall", 0)), 0),
		"rect": [float(r[0]), maxf(float(r[1]), 0.0), clampf(float(r[2]), 0.05, 50.0), clampf(float(r[3]), 0.05, 50.0)],
		"pos": [float(p[0]), float(p[1]), float(p[2])],
		"yaw": float(e.get("yaw", 0.0)), "pitch": clampf(float(e.get("pitch", -90.0 if kind == "light_spot" else 0.0)), -90.0, 90.0),
		"cone": clampf(float(e.get("cone", 60.0)), 1.0, 360.0), "range": clampf(float(e.get("range", 10.0)), 0.1, 1000.0),
		"colour": str(e.get("colour", "#ffd9a0")), "strength": clampf(float(e.get("strength", 1.0)), 0.0, 100.0),
		"chimney": maxi(int(e.get("chimney", 1)), 1),
	}


static func normalize_channel(c: Dictionary) -> Dictionary:
	var t := str(c.get("type", "switch"))
	return {
		"id": str(c.get("id", "")), "type": t if t in ["switch", "level"] else "switch",
		"default": clampf(float(c.get("default", 0.0)), 0.0, 1.0),
		"ramp_up": clampf(float(c.get("ramp_up", 0.0)), 0.0, 3600.0), "ramp_down": clampf(float(c.get("ramp_down", 0.0)), 0.0, 3600.0),
	}


static func _parse_array(text: String) -> Array:
	if text.strip_edges() == "":
		return []
	var d = JSON.parse_string(text)
	return d if typeof(d) == TYPE_ARRAY else []


static func parse(text: String) -> Array:
	var out: Array = []
	for e in _parse_array(text):
		if typeof(e) == TYPE_DICTIONARY:
			out.append(normalize(e))
	return out


static func parse_channels(text: String) -> Array:
	var out: Array = []
	for c in _parse_array(text):
		if typeof(c) == TYPE_DICTIONARY and str(c.get("id", "")) != "":
			out.append(normalize_channel(c))
	return out


func list() -> Array:
	return parse(app.settings.s(KEY))


func channels() -> Array:
	return parse_channels(app.settings.s(KEY_CH))


## Saves the emitters and makes sure that every channel they name exists (new ones start as plain switches).
func save(arr: Array) -> void:
	var chs := channels()
	var have := {}
	for c in chs:
		have[str(c["id"])] = true
	var added := false
	for e in arr:
		var ch := str(e.get("channel", "")).strip_edges()
		if ch != "" and not have.has(ch):
			chs.append(normalize_channel({"id": ch}))
			have[ch] = true
			added = true
	if added:
		app.settings.set_value(KEY_CH, JSON.stringify(chs))
	app.settings.set_value(KEY, JSON.stringify(arr))


func save_channels(arr: Array) -> void:
	app.settings.set_value(KEY_CH, JSON.stringify(arr))


## A free id for a new emitter of this kind: "okno1", "lampa2", ...
func next_id(kind: String, arr: Array) -> String:
	var base := "emiter"
	match kind:
		"light_surface": base = "okno"
		"light_point": base = "swiatlo"
		"light_spot": base = "lampa"
		"audio_omni", "audio_dir": base = "dzwiek"
		"smoke": base = "dym"
	var n := 1
	while true:
		var cand := "%s%d" % [base, n]
		var used := false
		for e in arr:
			if str(e.get("id", "")) == cand:
				used = true
		if not used:
			return cand
		n += 1
	return base


## A new emitter of the given kind, placed sensibly on the current model (or at the origin when there is none).
func default_emitter(kind: String) -> Dictionary:
	var e := normalize({"kind": kind})
	var arr := list()
	e["id"] = next_id(kind, arr)
	var centre := Vector2.ZERO
	var wall_h := 3.0
	if not app.last_rt.is_empty():
		var P: Dictionary = app.last_rt[0]
		var bb: Rect2 = P["bb"]
		centre = bb.get_center()
		wall_h = float(P["wall_h"])
	# visible default: just outside the middle of the first wall (inside the building the marker would be hidden)
	var fr := wall_frame(0, 0)
	var spot := centre
	if not fr.is_empty():
		var a: Vector2 = fr["a"]
		var d: Vector2 = fr["d"]
		var nn: Vector2 = fr["n"]
		var along := fmod(float(fr["len"]) * 0.5 + 0.6 * float(arr.size()), maxf(float(fr["len"]) * 0.8, 0.5))   # next ones do not sit on top of each other
		spot = a + d * along + nn * 0.8
	e["pos"] = [spot.x, minf(2.2, maxf(wall_h - 0.4, 0.5)), spot.y]
	match kind:
		"light_surface":
			e["channel"] = "swiatla"
			e["rect"] = [0.6, minf(1.0, maxf(wall_h - 1.4, 0.2)), 1.0, 1.2]
		"light_point":
			e["channel"] = "swiatla"
			e["range"] = 8.0
		"light_spot":
			e["channel"] = "latarnia"
			e["pos"] = [spot.x, wall_h + 0.5, spot.y]
			e["range"] = 15.0
			e["cone"] = 70.0
			e["pitch"] = -90.0
		"audio_omni":
			e["range"] = 30.0
		"audio_dir":
			e["range"] = 40.0
			e["cone"] = 90.0
		"smoke":
			e["channel"] = "dym"
			e["strength"] = 1.0
	return e


# ---------------------------------------------------------------------------------------------- geometry helpers

## Footprint of a part (Vector2 x, z) or an empty array.
func footprint(part: int) -> PackedVector2Array:
	if part < 0 or part >= app.last_rt.size():
		return PackedVector2Array()
	return app.last_rt[part]["pts"]


func wall_count(part: int) -> int:
	return footprint(part).size()


## Unit direction along the wall (A -> B) and the outward normal. Both in the (x, z) plane.
func wall_frame(part: int, wall: int) -> Dictionary:
	var pts := footprint(part)
	if pts.size() < 3:
		return {}
	var w := wall % pts.size()
	var a := pts[w]
	var b := pts[(w + 1) % pts.size()]
	var d := (b - a)
	var len := d.length()
	if len < 0.001:
		return {}
	d = d / len
	var n := Vector2(d.y, -d.x)
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	if n.dot((a + b) * 0.5 - c) < 0.0:
		n = -n
	return {"a": a, "d": d, "n": n, "len": len}


# ---------------------------------------------------------------------------------------------- export (draft v2 meta)

static func _r(v: float) -> float:
	return snappedf(v, 0.001)


## Emitters for the metadata (docs/MODEL_META.md, draft v2). `surface` is the provisional face id "p<part>:w<wall>".
func export_list() -> Array:
	var out: Array = []
	for e in list():
		var kind := str(e["kind"])
		var o := {"id": str(e["id"])}
		match kind:
			"light_surface":
				var fr := wall_frame(int(e["part"]), int(e["wall"]))
				o["kind"] = "light"
				o["shape"] = "surface"
				o["surface"] = "p%d:w%d" % [int(e["part"]), int(e["wall"])]
				o["rect"] = [_r(e["rect"][0]), _r(e["rect"][1]), _r(e["rect"][2]), _r(e["rect"][3])]
				if not fr.is_empty():
					o["surface_size"] = [_r(float(fr["len"])), 0.0]
			"light_point", "light_spot":
				o["kind"] = "light"
				o["shape"] = "point" if kind == "light_point" else "spot"
				o["position"] = [_r(e["pos"][0]), _r(e["pos"][1]), _r(e["pos"][2])]
				o["range_m"] = _r(float(e["range"]))
				if kind == "light_spot":
					o["direction"] = _dir_vec(float(e["yaw"]), float(e["pitch"]))
					o["cone_deg"] = _r(float(e["cone"]))
			"audio_omni", "audio_dir":
				o["kind"] = "audio"
				o["pattern"] = "omni" if kind == "audio_omni" else "directional"
				o["position"] = [_r(e["pos"][0]), _r(e["pos"][1]), _r(e["pos"][2])]
				o["range_m"] = _r(float(e["range"]))
				if kind == "audio_dir":
					o["direction"] = _dir_vec(float(e["yaw"]), float(e["pitch"]))
					o["cone_deg"] = _r(float(e["cone"]))
			"smoke":
				o["kind"] = "smoke"
				o["chimney_id"] = int(e["chimney"])
		if kind_group(kind) == "light":
			o["colour"] = str(e["colour"])
		if kind_group(kind) != "audio":
			o["strength"] = _r(float(e["strength"]))
		if str(e["channel"]) != "":
			o["channel"] = str(e["channel"])
		out.append(o)
	return out


func channel_export_list() -> Array:
	var out: Array = []
	for c in channels():
		out.append({"id": c["id"], "type": c["type"], "default": _r(float(c["default"])),
			"ramp_up": _r(float(c["ramp_up"])), "ramp_down": _r(float(c["ramp_down"]))})
	return out


## Unit vector (x, y, z) for an azimuth (0 = +Z, clockwise seen from above) and pitch (0 = horizontal, -90 = down).
static func _dir_vec(yaw_deg: float, pitch_deg: float) -> Array:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return [_r(sin(y) * cos(p)), _r(sin(p)), _r(cos(y) * cos(p))]


# ---------------------------------------------------------------------------------------------- markers in the 3D view

func rebuild_gizmos() -> void:
	if not is_instance_valid(app.building_root):
		return
	var parent: Node = app.building_root.get_parent()
	if parent == null:
		return
	var old := parent.get_node_or_null("EmitterGizmos")
	if old != null:
		parent.remove_child(old)
		old.queue_free()
	var arr := list()
	if arr.is_empty():
		return
	var root := Node3D.new()
	root.name = "EmitterGizmos"
	parent.add_child(root)
	for e in arr:
		var n := _gizmo(e)
		if n != null:
			root.add_child(n)


static func _mat(col: Color, alpha := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _gizmo(e: Dictionary) -> Node3D:
	var kind := str(e["kind"])
	var group := kind_group(kind)
	var col := Color(str(e["colour"])) if group == "light" else (Color("#52a9ff") if group == "audio" else Color("#b9c2cc"))
	var holder := Node3D.new()
	holder.name = "Emitter_" + str(e["id"])
	var mi := MeshInstance3D.new()
	holder.add_child(mi)
	var pos := Vector3(float(e["pos"][0]), float(e["pos"][1]), float(e["pos"][2]))
	match kind:
		"light_surface":
			var fr := wall_frame(int(e["part"]), int(e["wall"]))
			if fr.is_empty():
				return null
			var r: Array = e["rect"]
			var bm := BoxMesh.new()
			bm.size = Vector3(float(r[2]), float(r[3]), 0.05)
			mi.mesh = bm
			var d: Vector2 = fr["d"]
			var nn: Vector2 = fr["n"]
			var a: Vector2 = fr["a"]
			var c2 := a + d * (float(r[0]) + float(r[2]) * 0.5) + nn * 0.04
			holder.position = Vector3(c2.x, float(r[1]) + float(r[3]) * 0.5, c2.y)
			var xa := Vector3(d.x, 0.0, d.y)
			var za := Vector3(nn.x, 0.0, nn.y)
			holder.basis = Basis(xa, za.cross(xa), za)
		"light_point", "audio_omni":
			var sm := SphereMesh.new()
			sm.radius = 0.2
			sm.height = 0.4
			mi.mesh = sm
			holder.position = pos
		"light_spot", "audio_dir":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.25
			cm.height = 0.7
			mi.mesh = cm
			mi.position = Vector3(0, -0.35, 0)    # the tip (+Y of the mesh) sits at the emitter, the open end (-Y) points along the beam
			holder.position = pos
			var dv := _dir_vec(float(e["yaw"]), float(e["pitch"]))
			var dir := Vector3(dv[0], dv[1], dv[2]).normalized()
			# the cone's axis is +Y with the tip at +Y; turn -Y (the open end) into the beam direction
			var up_ref := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
			var zax := dir.cross(up_ref).normalized()
			var xax := dir.cross(zax).normalized()
			holder.basis = Basis(xax, -dir, -zax)
		"smoke":
			var idx := int(e["chimney"]) - 1
			var arr: Array = app.chimneys.list()
			if idx < 0 or idx >= arr.size():
				return null
			var ch: Dictionary = arr[idx]
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.35
			cyl.bottom_radius = 0.12
			cyl.height = 1.2
			mi.mesh = cyl
			holder.position = Vector3(float(ch["x"]), app.chimneys.top_y(ch) + 0.7, float(ch["z"]))
	mi.material_override = _mat(col)
	return holder
