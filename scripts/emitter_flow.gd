class_name EmitterFlow
extends RefCounted
## Emitters: everything the model can give off optically or acoustically - light, particles (smoke, fire, water, steam)
## and audio (wind is left out on purpose). Contract: docs/MODEL_META.md.
## They are DATA in the project (hidden settings `model_emitters` / `model_channels`, so they travel with the .mgdot);
## nothing is cut out of the mesh. In the 3D view they show as small markers (node "EmitterGizmos", a sibling of the building,
## so the exporters never see it). The glTF export turns them into nodes (see build_export_nodes).
##
## One emitter: {id, kind, channel, part, wall (0-based footprint edge), rect [u, v, w, h] (m; light_surface only),
##               pos [x, y, z] (m, building coordinates), yaw, pitch, cone (deg), range (m), colour "#rrggbb", strength,
##               chimney (0 = free position, 1.. = on top of that chimney; particles), ps {particle parameters}}
## One channel: {id, type "switch"|"level", default (0..1), ramp_up, ramp_down (s)}

const KEY := "model_emitters"
const KEY_CH := "model_channels"
const QUAD_OFFSET := 0.04     # the light quad stands this far in front of the wall, m

## [kind id, button label, group] - group: light | particle | audio
const KINDS := [
	["light_surface", "Światło – powierzchnia (okno, szyld)", "light"],
	["light_point", "Światło – punktowe (żarówka)", "light"],
	["light_spot", "Światło – reflektor (latarnia)", "light"],
	["particle_smoke", "Cząstki – dym", "particle"],
	["particle_fire", "Cząstki – ogień", "particle"],
	["particle_water", "Cząstki – woda (fontanna, strumień)", "particle"],
	["particle_steam", "Cząstki – para", "particle"],
	["audio_omni", "Dźwięk – dookólny", "audio"],
	["audio_dir", "Dźwięk – kierunkowy", "audio"],
]

## Starting values of the particle presets (docs/MODEL_META.md, 4.3). Not verified in the simulator.
const PRESETS := {
	"smoke": {"rate": 8.0, "max_particles": 60, "lifetime": [3.0, 6.0], "speed": [0.4, 0.9], "size": [0.2, 0.5], "cone_angle": 0.25,
		"growth": 0.15, "acceleration": [0.0, 0.15, 0.0], "drag": 0.3, "inherit_velocity": 0.0},
	"fire": {"rate": 40.0, "max_particles": 120, "lifetime": [0.4, 0.9], "speed": [0.8, 1.6], "size": [0.15, 0.35], "cone_angle": 0.2,
		"growth": -0.2, "acceleration": [0.0, 1.5, 0.0], "drag": 0.5, "inherit_velocity": 0.0},
	"water": {"rate": 120.0, "max_particles": 400, "lifetime": [1.2, 1.8], "speed": [5.0, 7.0], "size": [0.04, 0.08], "cone_angle": 0.12,
		"growth": 0.0, "acceleration": [0.0, -9.81, 0.0], "drag": 0.05, "inherit_velocity": 0.0},
	"steam": {"rate": 15.0, "max_particles": 80, "lifetime": [1.5, 3.0], "speed": [0.8, 1.4], "size": [0.15, 0.35], "cone_angle": 0.35,
		"growth": 0.25, "acceleration": [0.0, 0.4, 0.0], "drag": 0.8, "inherit_velocity": 0.0},
}

## The material every particle preset points to (`material` is required by the format): [base colour rgba, emissive rgb or null]
const PARTICLE_MATERIALS := {
	"smoke": [[0.55, 0.55, 0.55, 0.5], null],
	"fire": [[1.0, 0.55, 0.15, 0.8], [1.0, 0.45, 0.1]],
	"water": [[0.7, 0.85, 1.0, 0.6], null],
	"steam": [[0.95, 0.95, 0.95, 0.35], null],
}

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


## "particle_fire" -> "fire"; "" for other kinds.
static func preset_of(kind: String) -> String:
	return kind.trim_prefix("particle_") if kind.begins_with("particle_") else ""


static func _merge_ps(preset: String, given: Variant) -> Dictionary:
	var out: Dictionary = (PRESETS[preset] as Dictionary).duplicate(true)
	if typeof(given) == TYPE_DICTIONARY:
		for k in out.keys():
			if (given as Dictionary).has(k):
				var v = (given as Dictionary)[k]
				if typeof(out[k]) == TYPE_ARRAY and typeof(v) == TYPE_ARRAY and (v as Array).size() == (out[k] as Array).size():
					var arr: Array = []
					for x in v:
						arr.append(float(x))
					out[k] = arr
				elif typeof(out[k]) != TYPE_ARRAY and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
					out[k] = float(v) if k != "max_particles" else int(v)
	return out


static func normalize(e: Dictionary) -> Dictionary:
	var kind := str(e.get("kind", "light_point"))
	if kind == "smoke":     # 3.0.2 name
		kind = "particle_smoke"
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
	var is_particle := kind.begins_with("particle_")
	var out := {
		"id": str(e.get("id", "E1")), "kind": kind, "channel": str(e.get("channel", "")),
		"part": maxi(int(e.get("part", 0)), 0), "wall": maxi(int(e.get("wall", 0)), 0),
		"rect": [float(r[0]), maxf(float(r[1]), 0.0), clampf(float(r[2]), 0.05, 50.0), clampf(float(r[3]), 0.05, 50.0)],
		"pos": [float(p[0]), float(p[1]), float(p[2])],
		"yaw": float(e.get("yaw", 0.0)), "pitch": clampf(float(e.get("pitch", (90.0 if is_particle else (-90.0 if kind == "light_spot" else 0.0)))), -90.0, 90.0),
		"cone": clampf(float(e.get("cone", 60.0)), 1.0, 360.0), "range": clampf(float(e.get("range", 10.0)), 0.1, 1000.0),
		"colour": str(e.get("colour", "#ffd9a0")), "strength": clampf(float(e.get("strength", 1.0)), 0.0, 100.0),
		"chimney": maxi(int(e.get("chimney", 1 if kind == "particle_smoke" else 0)), 0),
	}
	if is_particle:
		out["ps"] = _merge_ps(preset_of(kind), e.get("ps", null))
	return out


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
		"particle_smoke": base = "dym"
		"particle_fire": base = "ogien"
		"particle_water": base = "woda"
		"particle_steam": base = "para"
		"audio_omni", "audio_dir": base = "dzwiek"
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
			e["channel"] = "building.lights"
			e["rect"] = [0.6, minf(1.0, maxf(wall_h - 1.4, 0.2)), 1.0, 1.2]
		"light_point":
			e["channel"] = "building.lights"
			e["range"] = 8.0
		"light_spot":
			e["channel"] = "building.lamp"
			e["pos"] = [spot.x, wall_h + 0.5, spot.y]
			e["range"] = 15.0
			e["cone"] = 70.0
			e["pitch"] = -90.0
		"particle_smoke":
			e["channel"] = "building.smoke"
			e["chimney"] = 1 if not app.chimneys.list().is_empty() else 0
		"particle_fire":
			e["channel"] = "building.fire"
		"particle_water":
			e["channel"] = "building.water"
			e["pitch"] = 75.0
		"particle_steam":
			e["channel"] = "building.steam"
		"audio_omni":
			e["range"] = 30.0
		"audio_dir":
			e["range"] = 40.0
			e["cone"] = 90.0
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


## Unit direction for an azimuth (0 = +Z, clockwise seen from above) and pitch (0 = horizontal, +90 = up).
static func dir_of(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)).normalized()


## Where the emitter stands: its own position, or (particles with a chimney) the top of that chimney.
func position_of(e: Dictionary) -> Vector3:
	if str(e["kind"]).begins_with("particle_") and int(e["chimney"]) > 0:
		var arr: Array = app.chimneys.list()
		var idx := int(e["chimney"]) - 1
		if idx < arr.size():
			var ch: Dictionary = arr[idx]
			return Vector3(float(ch["x"]), app.chimneys.top_y(ch) + 0.05, float(ch["z"]))
	return Vector3(float(e["pos"][0]), float(e["pos"][1]), float(e["pos"][2]))


# ---------------------------------------------------------------------------------------------- glTF export

## Light-layer id of every channel that drives a surface light ("building.lights" when none is named) - one id per
## channel, sorted, so the ids are stable. `legacy_lit`: the old "Świeci" surfaces count as the default channel.
func light_ids(legacy_lit := false) -> Dictionary:
	var names := {}
	for e in list():
		if str(e["kind"]) == "light_surface":
			names[_chan(e)] = true
	if legacy_lit:
		names["building.lights"] = true
	var keys: Array = names.keys()
	keys.sort()
	var out := {}
	for i in range(keys.size()):
		out[str(keys[i])] = i
	return out


static func _chan(e: Dictionary) -> String:
	var c := str(e.get("channel", "")).strip_edges()
	return c if c != "" else "building.lights"


func channel_default(name: String) -> float:
	for c in channels():
		if str(c["id"]) == name:
			return float(c["default"])
	return 0.0


static func _lin(c: Color) -> Array:
	var l := c.srgb_to_linear()
	return [snappedf(l.r, 0.0001), snappedf(l.g, 0.0001), snappedf(l.b, 0.0001)]


static func _basis_y_to(dir: Vector3) -> Basis:
	if dir.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	return Basis(Quaternion(Vector3.UP, dir))


static func _basis_look(dir: Vector3) -> Basis:
	var up_ref := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir, up_ref)


## Builds the glTF nodes of all emitters. Returns {nodes: [Node3D], materials: [dict], light_fix: {semantic_id: {...}},
## used_particle_materials: [names]}. The nodes are NOT in the scene tree; the exporter adopts them.
## ids: light layer ids (light_ids()).
func build_export_nodes(ids: Dictionary) -> Dictionary:
	var nodes: Array = []
	var materials: Array = []
	var light_fix := {}
	var used_ps := {}
	for e in list():
		var kind := str(e["kind"])
		var sid := "emitter." + str(e["id"])
		match kind:
			"light_surface":
				var n := _surface_light_node(e, sid, ids)
				if n != null:
					nodes.append(n)
			"light_point", "light_spot":
				var ln := _punctual_node(e, sid, light_fix)
				nodes.append(ln)
			"audio_omni", "audio_dir":
				nodes.append(_audio_node(e, sid))
			_:
				if kind.begins_with("particle_"):
					var pn := _particle_node(e, sid)
					nodes.append(pn)
					used_ps[preset_of(kind)] = true
	for pname in used_ps.keys():
		var spec: Array = PARTICLE_MATERIALS[pname]
		var bc: Array = spec[0]
		var m := {"name": "smoke_source_" + str(pname),
			"pbrMetallicRoughness": {"baseColorFactor": bc, "metallicFactor": 0.0, "roughnessFactor": 1.0},
			"alphaMode": "BLEND", "doubleSided": true, "extras": {"semantic_id": "material." + str(pname)}}
		if spec[1] != null:
			m["emissiveFactor"] = spec[1]
		materials.append(m)
	return {"nodes": nodes, "materials": materials, "light_fix": light_fix}


func _surface_light_node(e: Dictionary, sid: String, ids: Dictionary) -> Node3D:
	var fr := wall_frame(int(e["part"]), int(e["wall"]))
	if fr.is_empty():
		return null
	var r: Array = e["rect"]
	var a: Vector2 = fr["a"]
	var d: Vector2 = fr["d"]
	var nn: Vector2 = fr["n"]
	var p0 := a + d * float(r[0]) + nn * QUAD_OFFSET
	var p1 := p0 + d * float(r[2])
	var y0 := float(r[1])
	var y1 := y0 + float(r[3])
	var n3 := Vector3(nn.x, 0.0, nn.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n3)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	var col := Color(str(e["colour"]))
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = float(e["strength"])
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.resource_name = "light_" + str(e["id"])
	mesh.surface_set_material(0, mat)
	var node := MeshInstance3D.new()
	node.name = "light_" + str(e["id"])
	node.mesh = mesh
	var chan := _chan(e)
	node.set_meta("gltf_extras", {
		"semantic_id": sid,
		"light_id": int(ids.get(chan, 0)),
		"light_color": _lin(col),
		"light_state": "on",
		"geostudio": {"kind": "light_surface", "channel": chan,
			"surface": "building.part_%d.wall_%d" % [int(e["part"]), int(e["wall"])], "rect": r.duplicate()},
	})
	return node


func _punctual_node(e: Dictionary, sid: String, light_fix: Dictionary) -> Node3D:
	var kind := str(e["kind"])
	var col := Color(str(e["colour"]))
	var intensity := float(e["strength"]) * 100.0      # candela; starting value, to be tuned in the simulator
	var node: Light3D
	if kind == "light_spot":
		var sp := SpotLight3D.new()
		var outer := deg_to_rad(float(e["cone"]) * 0.5)
		sp.spot_angle = float(e["cone"]) * 0.5
		sp.spot_range = float(e["range"])
		node = sp
		light_fix[sid] = {"intensity": intensity, "inner": outer * 0.8, "outer": outer}
		node.basis = _basis_look(dir_of(float(e["yaw"]), float(e["pitch"])))
	else:
		var om := OmniLight3D.new()
		om.omni_range = float(e["range"])
		node = om
		light_fix[sid] = {"intensity": intensity}
	node.name = "light_" + str(e["id"])
	node.light_color = col
	node.light_energy = intensity
	node.position = position_of(e)
	var extras := {"semantic_id": sid, "geostudio": {"kind": kind}}
	var chan := str(e["channel"]).strip_edges()
	if chan != "":
		extras["light_control"] = {"source": chan, "default": channel_default(chan)}
	node.set_meta("gltf_extras", extras)
	return node


func _particle_node(e: Dictionary, sid: String) -> Node3D:
	var ps: Dictionary = e["ps"]
	var preset := preset_of(str(e["kind"]))
	var src := {
		"rate": float(ps["rate"]), "max_particles": int(ps["max_particles"]),
		"lifetime": ps["lifetime"], "speed": ps["speed"], "size": ps["size"],
		"material": "material." + preset,
		"cone_angle": float(ps["cone_angle"]), "growth": float(ps["growth"]),
		"acceleration": ps["acceleration"], "drag": float(ps["drag"]), "inherit_velocity": float(ps["inherit_velocity"]),
	}
	var chan := str(e["channel"]).strip_edges()
	if chan != "":
		src["source"] = chan
		src["default"] = maxf(channel_default(chan), 0.0)
	var node := Node3D.new()
	node.name = "particles_" + str(e["id"])
	node.position = position_of(e)
	node.basis = _basis_y_to(dir_of(float(e["yaw"]), float(e["pitch"])))    # the stream leaves along the node's +Y
	node.set_meta("gltf_extras", {"semantic_id": sid, "smoke_source": src,
		"geostudio": {"kind": str(e["kind"]), "preset": preset, "emission_axis": "+Y"}})
	return node


func _audio_node(e: Dictionary, sid: String) -> Node3D:
	var kind := str(e["kind"])
	var src := {"pattern": "omni" if kind == "audio_omni" else "directional", "range": float(e["range"]),
		"trigger": sid + ".trigger", "clip": sid + ".clip"}
	var node := Node3D.new()
	node.name = "audio_" + str(e["id"])
	node.position = position_of(e)
	if kind == "audio_dir":
		var outer := deg_to_rad(float(e["cone"]) * 0.5)
		src["cone"] = {"inner": snappedf(outer * 0.8, 0.0001), "outer": snappedf(outer, 0.0001)}
		node.basis = _basis_look(dir_of(float(e["yaw"]), float(e["pitch"])))    # the sound leaves along -Z, like a spot light
	var chan := str(e["channel"]).strip_edges()
	if chan != "":
		src["source"] = chan
		src["default"] = 1.0
	node.set_meta("gltf_extras", {"semantic_id": sid, "audio_source": src, "geostudio": {"kind": kind}})
	return node


## Channels with the light-layer id they drive (for geostudio.channels in the export).
func channel_export_list(ids: Dictionary) -> Array:
	var out: Array = []
	var have := {}
	for c in channels():
		var o := {"id": c["id"], "type": c["type"], "default": snappedf(float(c["default"]), 0.001),
			"ramp_up": snappedf(float(c["ramp_up"]), 0.001), "ramp_down": snappedf(float(c["ramp_down"]), 0.001)}
		if ids.has(str(c["id"])):
			o["light_id"] = int(ids[str(c["id"])])
		have[str(c["id"])] = true
		out.append(o)
	for k in ids.keys():     # a light-layer channel nobody declared (e.g. the default one)
		if not have.has(k):
			out.append({"id": k, "type": "switch", "default": 0.0, "ramp_up": 0.0, "ramp_down": 0.0, "light_id": int(ids[k])})
	return out


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
	var col := Color(str(e["colour"]))
	if group == "audio":
		col = Color("#52a9ff")
	elif group == "particle":
		match preset_of(kind):
			"smoke": col = Color("#b9c2cc")
			"fire": col = Color("#ff7a30")
			"water": col = Color("#4aa8ff")
			"steam": col = Color("#e8eef5")
	var holder := Node3D.new()
	holder.name = "Emitter_" + str(e["id"])
	var mi := MeshInstance3D.new()
	holder.add_child(mi)
	var pos := position_of(e)
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
		_:
			# spot / directional audio / particles: a cone whose tip sits at the emitter and whose open end points along the beam
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.25
			cm.height = 0.7
			mi.mesh = cm
			mi.position = Vector3(0, -0.35, 0)
			holder.position = pos
			var dir := dir_of(float(e["yaw"]), float(e["pitch"]))
			var up_ref := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
			var zax := dir.cross(up_ref).normalized()
			var xax := dir.cross(zax).normalized()
			holder.basis = Basis(xax, -dir, -zax)
	mi.material_override = _mat(col)
	if group == "particle":
		holder.add_child(_preview_particles(e, preset_of(kind)))
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.25     # the cone only marks the nozzle
	return holder


## Live preview of a particle emitter (CPUParticles3D in the same Godot the simulator runs on): the same numbers as `smoke_source`.
## The holder's -Y axis is the emission direction, so the particles fly along local -Y.
func _preview_particles(e: Dictionary, preset: String) -> CPUParticles3D:
	var ps: Dictionary = e["ps"]
	var life: Array = ps["lifetime"]
	var spd: Array = ps["speed"]
	var siz: Array = ps["size"]
	var lmean := (float(life[0]) + float(life[1])) * 0.5
	var smean := maxf((float(siz[0]) + float(siz[1])) * 0.5, 0.001)
	var p := CPUParticles3D.new()
	p.name = "Preview"
	p.amount = clampi(int(ceil(float(ps["rate"]) * float(life[1]))), 1, maxi(int(ps["max_particles"]), 1))
	p.lifetime = maxf(float(life[1]), 0.05)
	p.lifetime_randomness = clampf(1.0 - float(life[0]) / maxf(float(life[1]), 0.001), 0.0, 1.0)
	p.preprocess = p.lifetime
	p.direction = Vector3(0, -1, 0)
	p.spread = rad_to_deg(float(ps["cone_angle"]))
	p.initial_velocity_min = float(spd[0])
	p.initial_velocity_max = float(spd[1])
	var acc: Array = ps["acceleration"]
	p.gravity = Vector3(float(acc[0]), float(acc[1]), float(acc[2]))
	p.local_coords = false
	p.damping_min = float(ps["drag"])
	p.damping_max = float(ps["drag"])
	p.scale_amount_min = float(siz[0]) / smean
	p.scale_amount_max = float(siz[1]) / smean
	var end_scale := clampf(1.0 + float(ps["growth"]) * lmean / smean, 0.05, 20.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, end_scale))
	p.scale_amount_curve = curve
	var spec: Array = PARTICLE_MATERIALS[preset]
	var bc: Array = spec[0]
	var ramp := Gradient.new()
	var base := Color(bc[0], bc[1], bc[2], 1.0)
	match preset:
		"fire":
			ramp.colors = PackedColorArray([Color(1, 0.95, 0.5, 0.9), Color(1, 0.45, 0.1, 0.8), Color(0.3, 0.05, 0.0, 0.0)])
			ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		_:
			ramp.colors = PackedColorArray([Color(base, 0.0), Color(base, float(bc[3])), Color(base, 0.0)])
			ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(smean * 1.0, smean * 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if preset == "fire" else BaseMaterial3D.BLEND_MODE_MIX
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	gt.gradient = g
	m.albedo_texture = gt
	q.material = m
	p.mesh = q
	p.emitting = true
	return p
