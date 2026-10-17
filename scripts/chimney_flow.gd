class_name ChimneyFlow
extends RefCounted
## Chimneys: boxes standing on the roof. Width, length and height are typed in by hand, the position is set in the
## plan view and moved / raised in the side views (ChimneyEditor). They are stored in the hidden setting
## `model_chimneys` (JSON, so they travel with the project) and built as mesh nodes "Chimney_<n>" under the building.
## The shaft wears a REPEATED cut-out of a wall picture (region + fragment), the cap is plain concrete.
##
## One chimney: {part, x, z (centre, building coordinates in m), w (along X), l (along Z),
##               h (height above the roof surface at the UP-SLOPE side of the footprint),
##               cap (concrete cap), tex ("auto" = long wall of the sheet, or a region key),
##               frag [x, y, w, h] (share of the region picture), tscale (picture size factor)}

const KEY := "model_chimneys"
const CAP_T := 0.08          # thickness of the cap, m
const CAP_OVER := 0.05       # how far the cap sticks out, m
const SINK := 0.3            # the shaft goes this far below the lowest roof point under it, m
const DEFAULT_PPM := 150.0

var app
var window: Window


func _init(main_scene) -> void:
	app = main_scene


# ---------------------------------------------------------------------------------------------- data

static func normalize(e: Dictionary) -> Dictionary:
	var f: Array = e.get("frag", [])
	if f.size() != 4:
		f = [0.4, 0.55, 0.2, 0.25]
	var fx := clampf(float(f[0]), 0.0, 0.98)
	var fy := clampf(float(f[1]), 0.0, 0.98)
	return {
		"part": maxi(int(e.get("part", 0)), 0), "x": float(e.get("x", 0.0)), "z": float(e.get("z", 0.0)),
		"w": clampf(float(e.get("w", 0.5)), 0.1, 6.0), "l": clampf(float(e.get("l", 0.5)), 0.1, 6.0),
		"h": clampf(float(e.get("h", 1.0)), 0.0, 12.0),
		"cap": bool(e.get("cap", true)), "tex": str(e.get("tex", "auto")),
		"frag": [fx, fy, clampf(float(f[2]), 0.02, 1.0 - fx), clampf(float(f[3]), 0.02, 1.0 - fy)],
		"tscale": clampf(float(e.get("tscale", 1.0)), 0.1, 10.0),
	}


static func parse(text: String) -> Array:
	var out: Array = []
	if text.strip_edges() == "":
		return out
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_ARRAY:
		return out
	for e in d:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(normalize(e))
	return out


func list() -> Array:
	return parse(app.settings.s(KEY))


func save(arr: Array) -> void:
	app.settings.set_value(KEY, JSON.stringify(arr))


## A new chimney near the ridge of the main body.
func default_chimney() -> Dictionary:
	var c := normalize({})
	if app.last_rt.is_empty():
		return c
	var P: Dictionary = app.last_rt[0]
	var bb: Rect2 = P["bb"]
	var info: Dictionary = app.roof_ridge_info(0)
	if bool(info["along_x"]):
		c["x"] = bb.get_center().x + bb.size.x * 0.25
		c["z"] = float(info["mid"]) if bool(info["has"]) else bb.get_center().y
	else:
		c["z"] = bb.get_center().y + bb.size.y * 0.25
		c["x"] = float(info["mid"]) if bool(info["has"]) else bb.get_center().x
	return c


# ---------------------------------------------------------------------------------------------- geometry

## 5 x 5 sample points over the footprint of the chimney.
static func footprint_samples(c: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(5):
		for j in range(5):
			pts.append(Vector2(float(c["x"]) + (float(i) / 4.0 - 0.5) * float(c["w"]), float(c["z"]) + (float(j) / 4.0 - 0.5) * float(c["l"])))
	return pts


## (lowest, highest) roof surface height under the chimney.
func roof_range(c: Dictionary) -> Vector2:
	var ys: PackedFloat32Array = app.roof_y_batch(int(c["part"]), footprint_samples(c))
	if ys.is_empty():
		return Vector2.ZERO
	var lo := 1e9
	var hi := -1e9
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


func top_y(c: Dictionary) -> float:
	return roof_range(c).y + float(c["h"])


func base_y(c: Dictionary) -> float:
	return roof_range(c).x - SINK


## Where the chimney sits, for the export metadata.
func export_list() -> Array:
	var out: Array = []
	var arr := list()
	for i in range(arr.size()):
		var c: Dictionary = arr[i]
		var rr := roof_range(c)
		out.append({"id": i + 1, "part": int(c["part"]), "centre": [snappedf(float(c["x"]), 0.001), snappedf(float(c["z"]), 0.001)],
			"size": [snappedf(float(c["w"]), 0.001), snappedf(float(c["l"]), 0.001)], "height_above_roof": snappedf(float(c["h"]), 0.001),
			"base_y": snappedf(rr.x - SINK, 0.001), "top_y": snappedf(rr.y + float(c["h"]), 0.001), "cap": bool(c["cap"])})
	return out


# ---------------------------------------------------------------------------------------------- mesh

func _region_key(c: Dictionary) -> String:
	if not app.atlas.loaded:
		return ""
	var k := str(c["tex"])
	if k != "auto" and app.atlas.regions.has(k):
		return k
	var longs: Array = app.atlas.keys_for_role("facade_long")
	if not longs.is_empty():
		return str(longs[0])
	var all: Array = app.atlas.regions.keys()
	all.sort()
	return str(all[0]) if not all.is_empty() else ""


## Pixel rectangle of the fragment inside the region picture.
func _frag_rect(c: Dictionary, img: Image) -> Rect2i:
	var f: Array = c["frag"]
	var w := img.get_width()
	var h := img.get_height()
	var r := Rect2i(int(float(f[0]) * w), int(float(f[1]) * h), maxi(int(float(f[2]) * w), 2), maxi(int(float(f[3]) * h), 2))
	return r.intersection(Rect2i(0, 0, w, h))


## Size in metres of one repeat of the fragment.
func frag_size_m(c: Dictionary) -> Vector2:
	var key := _region_key(c)
	if key == "":
		return Vector2.ONE
	var img: Image = app.atlas.region(key)["img"]
	var r := _frag_rect(c, img)
	var ppm: float = app.settings.f("tex_px_per_m")
	if ppm <= 0.0:
		ppm = DEFAULT_PPM
	return Vector2(float(r.size.x), float(r.size.y)) / ppm * float(c["tscale"])


func _shaft_material(c: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.92
	m.metallic = 0.0
	var key := _region_key(c)
	if key != "":
		var img: Image = app.atlas.region(key)["img"]
		var r := _frag_rect(c, img)
		if r.size.x >= 2 and r.size.y >= 2:
			var crop := img.get_region(r)
			crop.generate_mipmaps()
			m.albedo_texture = ImageTexture.create_from_image(crop)
			m.texture_repeat = true
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			return m
	m.albedo_color = Color8(150, 84, 62)
	return m


static func _cap_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color8(122, 122, 118)
	m.roughness = 0.95
	return m


## Two triangles of a quad with the normal pointing to `outward` (Godot front faces are clockwise).
static func _quad(s: Dictionary, vs: Array, uvs: Array, outward: Vector3) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = vs[tri[0]]
		var b: Vector3 = vs[tri[1]]
		var c: Vector3 = vs[tri[2]]
		var n := (c - a).cross(b - a)
		var order: Array = tri
		if n.dot(outward) < 0.0:
			order = [tri[0], tri[2], tri[1]]
			n = -n
		n = n.normalized()
		for k in order:
			(s["v"] as Array).append(vs[k])
			(s["n"] as Array).append(n)
			(s["uv"] as Array).append(uvs[k])


## Four side walls of a box (no bottom). v = 0 at the top of the picture, so the picture stands upright.
static func _box_sides(s: Dictionary, cx: float, cz: float, hw: float, hl: float, y0: float, y1: float, rep: Vector2) -> void:
	var corners := [Vector2(cx - hw, cz - hl), Vector2(cx + hw, cz - hl), Vector2(cx + hw, cz + hl), Vector2(cx - hw, cz + hl)]
	var run := 0.0
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var d := b - a
		var out := Vector3(d.y, 0.0, -d.x)
		var mid := Vector2((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
		if (Vector2(mid.x, mid.y) + Vector2(out.x, out.z).normalized() * 0.01).distance_to(Vector2(cx, cz)) < mid.distance_to(Vector2(cx, cz)):
			out = -out
		var u0 := run / rep.x
		var u1 := (run + len) / rep.x
		var v0 := 0.0
		var v1 := (y1 - y0) / rep.y
		_quad(s, [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)],
			[Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)], out)
		run += len


static func _box_top(s: Dictionary, cx: float, cz: float, hw: float, hl: float, y: float) -> void:
	_quad(s, [Vector3(cx - hw, y, cz - hl), Vector3(cx + hw, y, cz - hl), Vector3(cx + hw, y, cz + hl), Vector3(cx - hw, y, cz + hl)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)


func build_one(c: Dictionary, idx: int) -> MeshInstance3D:
	var rr := roof_range(c)
	var top := rr.y + float(c["h"])
	var base := rr.x - SINK
	if top - base < 0.05:
		return null
	var cx := float(c["x"])
	var cz := float(c["z"])
	var hw := float(c["w"]) * 0.5
	var hl := float(c["l"]) * 0.5
	var cap := bool(c["cap"]) and (top - base) > CAP_T * 2.0
	var shaft_top := top - CAP_T if cap else top
	var rep := frag_size_m(c)
	var shaft := {"v": [], "n": [], "uv": []}
	_box_sides(shaft, cx, cz, hw, hl, base, shaft_top, rep)
	var cap_s := {"v": [], "n": [], "uv": []}
	if cap:
		_box_sides(cap_s, cx, cz, hw + CAP_OVER, hl + CAP_OVER, shaft_top, top, Vector2.ONE)
		_box_top(cap_s, cx, cz, hw + CAP_OVER, hl + CAP_OVER, top)
	else:
		_box_top(cap_s, cx, cz, hw, hl, top)
	var mesh := ArrayMesh.new()
	var mats: Array = [_shaft_material(c), _cap_material()]
	var si := 0
	for sd in [shaft, cap_s]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(sd["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(sd["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(sd["uv"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[si])
		si += 1
	var mi := MeshInstance3D.new()
	mi.name = "Chimney_%d" % (idx + 1)
	mi.mesh = mesh
	mi.set_meta("pick_ids", PackedStringArray())       # the exporter takes meshes that carry this
	mi.set_meta("chimney_part", int(c["part"]))
	return mi


## Removes and builds all chimneys again (the model itself is left alone).
func rebuild() -> void:
	var root: Node3D = app.building_root
	if not is_instance_valid(root):
		return
	for ch in root.get_children():
		if String(ch.name).begins_with("Chimney"):
			root.remove_child(ch)
			ch.queue_free()
	var arr := list()
	for i in range(arr.size()):
		var mi := build_one(arr[i], i)
		if mi != null:
			root.add_child(mi)
	app._apply_visibility()


# ---------------------------------------------------------------------------------------------- window

func open() -> void:
	if app.last_rt.is_empty():
		app._set_status("Najpierw zbuduj model, potem dodasz kominy.")
		return
	if is_instance_valid(window):
		window.queue_free()
	var win := Window.new()
	win.title = "Kominy"
	var scr := Vector2(app.get_viewport().get_visible_rect().size)
	win.size = Vector2i(int(clampf(scr.x * 0.92, 1000.0, 1700.0)), int(clampf(scr.y * 0.92, 620.0, 980.0)))
	win.transient = true
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var m := MarginContainer.new()
	for sname in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(sname, 12)
	bg.add_child(m)
	var ed := ChimneyEditor.new()
	m.add_child(ed)
	ed.setup(app, self)
	ed.finished.connect(func(saved: bool) -> void:
		win.queue_free()
		if saved and app.project.is_open():
			app.projflow._save_project())
	win.close_requested.connect(func() -> void: ed.cancel_edit())
	win.window_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			ed.cancel_edit())
	app.add_child(win)
	win.popup_centered()
	window = win
