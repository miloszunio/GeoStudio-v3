class_name FxRain
extends RefCounted
## Rain built from the geometry of the model (not a flat curtain): streaks fall onto the ground AND onto the roof, splash where they hit
## the roof facets, run down the facets in rivulets (a shader on a thin skin over the roof), leave the building along the eaves as drips
## and gutter streams, and land on the ground as ripples and spray. Everything is derived from the roof meshes (node names roof*),
## so it follows any roof the editors can make. The same plan is written to the glTF (weather_source / particle_fx).

const G := 9.81
const DRIP_RATE := 30.0        # drips per metre of eave per second at intensity 1
const GUTTER_RATE := 90.0      # gutter-stream particles per metre per second per unit of intensity above GUTTER_MIN
const GUTTER_MIN := 0.15

const RUNOFF_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
uniform float wet : hint_range(0.0, 1.5) = 0.6;
uniform float flow_speed = 1.1;
varying vec3 w_pos;
varying vec3 w_nrm;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 g = vec3(0.0, -1.0, 0.0);
	vec3 dn = g - n * dot(n, g);
	float slope = length(dn);
	vec3 d = slope > 0.02 ? dn / slope : vec3(1.0, 0.0, 0.0);
	vec3 sd = normalize(cross(n, d));
	float s = dot(w_pos, d);
	float t = dot(w_pos, sd);
	float steep = smoothstep(0.02, 0.35, slope);
	float spd = flow_speed * (0.6 + slope * 2.2);
	// narrow rivulets: sharp across the flow, long and stretched along it, three layers moving at different speeds
	float r1 = vnoise(vec2(t * 16.0, s * 0.35 - TIME * spd));
	float r2 = vnoise(vec2(t * 27.0 + 7.3, s * 0.6 - TIME * spd * 1.35));
	float r3 = vnoise(vec2(t * 9.0 + 2.1, s * 0.22 - TIME * spd * 0.7));
	float m = r1 * 0.45 + r2 * 0.3 + r3 * 0.35;
	float rill = smoothstep(0.66 - 0.10 * wet, 0.80, m) * steep;
	float core = smoothstep(0.78, 0.9, m) * steep;
	float film = 0.34 * clamp(wet, 0.0, 1.0);
	float a = clamp(film + rill * 0.42 * clamp(wet, 0.0, 1.2) + core * 0.25, 0.0, 0.85);
	ALBEDO = mix(vec3(0.03, 0.04, 0.05), vec3(0.30, 0.38, 0.46), rill + core);
	ROUGHNESS = mix(0.30, 0.03, clamp(film * 2.0 + rill, 0.0, 1.0));
	SPECULAR = 1.0;
	METALLIC = 0.0;
	ALPHA = a;
}
"""


# ---------------------------------------------------------------------------------------------- geometry

static func _q(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 400.0), roundi(v.y * 400.0), roundi(v.z * 400.0))


static func _ekey(a: Vector3i, b: Vector3i) -> String:
	var sa := "%d,%d,%d" % [a.x, a.y, a.z]
	var sb := "%d,%d,%d" % [b.x, b.y, b.z]
	return sa + "|" + sb if sa < sb else sb + "|" + sa


## The upward-facing triangles of the roof meshes and the lower boundary (eave) edges.
## {tris: PackedVector3Array (3 per triangle), nrm: PackedVector3Array (per triangle), area: PackedFloat32Array,
##  eaves: [{a, b, out, part}], parts: [int], total: float}
static func roof_geometry(root: Node3D) -> Dictionary:
	var tris := PackedVector3Array()
	var nrm := PackedVector3Array()
	var area := PackedFloat32Array()
	var eaves: Array = []
	var parts: Array = []
	if root == null or not is_instance_valid(root):
		return {"tris": tris, "nrm": nrm, "area": area, "eaves": eaves, "parts": parts, "total": 0.0}
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for node in root.get_children():
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not str(mi.name).to_lower().begins_with("roof"):
			continue
		var digits := str(mi.name).to_lower().trim_prefix("roof").trim_prefix("_")      # Roof, Roof_2, Roof_3 ... = parts 0, 1, 2
		var part := maxi(digits.to_int() - 1, 0) if digits.is_valid_int() else 0
		if not parts.has(part):
			parts.append(part)
		var xf := inv * mi.global_transform if mi.is_inside_tree() and root.is_inside_tree() else mi.transform
		var edges := {}
		for sidx in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(sidx)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var ids := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
				ids = arr[Mesh.ARRAY_INDEX]
			else:
				ids.resize(vs.size())
				for i in range(vs.size()):
					ids[i] = i
			for t in range(0, ids.size() - 2, 3):
				var ia := ids[t]
				var ib := ids[t + 1]
				var ic := ids[t + 2]
				var a: Vector3 = xf * vs[ia]
				var b: Vector3 = xf * vs[ib]
				var c: Vector3 = xf * vs[ic]
				var n := Vector3.ZERO
				if ns.size() == vs.size():
					n = (xf.basis * (ns[ia] + ns[ib] + ns[ic])).normalized()
				else:
					n = (b - a).cross(c - a).normalized()
					if n.y < 0.0:
						n = -n
				var ar := (b - a).cross(c - a).length() * 0.5
				if n.y < 0.03 or ar < 1e-5:
					continue
				tris.append(a)
				tris.append(b)
				tris.append(c)
				nrm.append(n)
				area.append(ar)
				for pair in [[a, b], [b, c], [c, a]]:
					var key := _ekey(_q(pair[0]), _q(pair[1]))
					if edges.has(key):
						(edges[key] as Dictionary)["n"] = int((edges[key] as Dictionary)["n"]) + 1
					else:
						edges[key] = {"a": pair[0], "b": pair[1], "n": 1, "cen": (a + b + c) / 3.0, "nrm": n}
		# eaves of this roof: boundary edges that lie low (the rake edges of a gable climb, they are skipped)
		var ymin := INF
		for k in edges.keys():
			var ed: Dictionary = edges[k]
			if int(ed["n"]) == 1:
				ymin = minf(ymin, minf((ed["a"] as Vector3).y, (ed["b"] as Vector3).y))
		for k in edges.keys():
			var ed: Dictionary = edges[k]
			if int(ed["n"]) != 1:
				continue
			var ea: Vector3 = ed["a"]
			var eb: Vector3 = ed["b"]
			var len := ea.distance_to(eb)
			if len < 0.05 or maxf(ea.y, eb.y) > ymin + 0.35 or absf(ea.y - eb.y) > 0.25 * len:
				continue
			var mid := (ea + eb) * 0.5
			var cen: Vector3 = ed["cen"]
			var tn: Vector3 = ed["nrm"]
			var out := Vector3(tn.x, 0.0, tn.z)          # downhill: the horizontal part of the facet's normal
			if out.length() < 0.05:                       # flat roof: away from the middle of the triangle
				out = Vector3(mid.x - cen.x, 0.0, mid.z - cen.z)
			if out.length() < 0.001:
				continue
			eaves.append({"a": ea, "b": eb, "out": out.normalized(), "part": part})
	var total := 0.0
	for ar2 in area:
		total += ar2
	return {"tris": tris, "nrm": nrm, "area": area, "eaves": eaves, "parts": parts, "total": total}


static func _sample_roof(geo: Dictionary, n: int, rng: RandomNumberGenerator) -> Array:
	var area: PackedFloat32Array = geo["area"]
	var tris: PackedVector3Array = geo["tris"]
	var nrm: PackedVector3Array = geo["nrm"]
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	if area.is_empty():
		return [pos, nor]
	var cum := PackedFloat32Array()
	var acc := 0.0
	for a in area:
		acc += a
		cum.append(acc)
	for _i in range(n):
		var r := rng.randf() * acc
		var lo := 0
		var hi := cum.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if cum[mid] < r:
				lo = mid + 1
			else:
				hi = mid
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var a := tris[lo * 3]
		var b := tris[lo * 3 + 1]
		var c := tris[lo * 3 + 2]
		pos.append(a + (b - a) * u + (c - a) * v + nrm[lo] * 0.012)
		nor.append(nrm[lo])
	return [pos, nor]


static func _sample_eaves(geo: Dictionary, n: int, rng: RandomNumberGenerator) -> Array:
	var eaves: Array = geo["eaves"]
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var cum := PackedFloat32Array()
	var acc := 0.0
	for ed in eaves:
		acc += (ed["a"] as Vector3).distance_to(ed["b"])
		cum.append(acc)
	if eaves.is_empty():
		return [pos, nor, 0.0]
	for _i in range(n):
		var r := rng.randf() * acc
		var k := 0
		while k < cum.size() - 1 and cum[k] < r:
			k += 1
		var ed: Dictionary = eaves[k]
		var p: Vector3 = (ed["a"] as Vector3).lerp(ed["b"], rng.randf())
		pos.append(p + (ed["out"] as Vector3) * 0.04 - Vector3(0, 0.02, 0))
		nor.append(ed["out"])
	return [pos, nor, acc]


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _bounds(polys: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for poly in polys:
		for p in (poly as PackedVector2Array):
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r if not first else Rect2(-3, -3, 6, 6)


static func _ground_points(polys: Array, margin: float, n: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var bb := _bounds(polys).grow(margin)
	var fat: Array = []
	for poly in polys:
		var o := Geometry2D.offset_polygon(poly, 0.8)
		if o.size() > 0:
			fat.append(o[0])
	var out := PackedVector3Array()
	var tries := 0
	while out.size() < n and tries < n * 6:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		var inside := false
		for f in fat:
			if Geometry2D.is_point_in_polygon(p, f):
				inside = true
				break
		if not inside:
			out.append(Vector3(p.x, 0.0, p.y))
	return out


static func _points_tex(pts: PackedVector3Array) -> ImageTexture:
	var w := 128
	var h := maxi(int(ceil(float(pts.size()) / float(w))), 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBF)
	for i in range(pts.size()):
		var p := pts[i]
		img.set_pixel(i % w, i / w, Color(p.x, p.y, p.z))
	return ImageTexture.create_from_image(img)


## Everything the build and the export need, derived once from the roof and the footprint.
static func plan(e: Dictionary, root: Node3D, polys: Array) -> Dictionary:
	var rain: Dictionary = e["rain"]
	var geo := roof_geometry(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var inten := clampf(float(rain["intensity"]), 0.0, 2.0)
	var bb := _bounds(polys).grow(float(rain["margin"]))
	var fp_area := 0.0
	for poly in polys:
		fp_area += absf(_poly_area(poly))
	var ground_area := maxf(bb.get_area() - fp_area, 1.0)
	var pl := {"I": inten, "rain": rain, "geo": geo, "bb": bb, "rng": rng, "polys": polys, "ground_area": ground_area}
	var eaves: Array = geo["eaves"]
	var eave_h := 0.0
	var eave_len := 0.0
	for ed in eaves:
		var l := (ed["a"] as Vector3).distance_to(ed["b"])
		eave_len += l
		eave_h += ((ed["a"] as Vector3).y + (ed["b"] as Vector3).y) * 0.5 * l
	pl["eave_len"] = eave_len
	pl["eave_h"] = maxf(eave_h / eave_len, 0.4) if eave_len > 0.0 else 0.0
	return pl


# ---------------------------------------------------------------------------------------------- building blocks

static func _flat_material(tex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FxTex.texture(tex)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mat_from_fx(tex: String, billboard: String) -> StandardMaterial3D:
	return FxParticles._draw_material({"texture": tex, "blend": "mix", "frame_speed": 0.0, "billboard": billboard, "soft": 0.0})


static func _pm_base(col: Color, a: float, fade_in := 0.1, fade_out := 0.12) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	var ramp := [[0.0, col.to_html(false), 0.0], [fade_in, col.to_html(false), a], [1.0 - fade_out, col.to_html(false), a], [1.0, col.to_html(false), 0.0]]
	pm.color_ramp = FxParticles._gradient_tex(ramp)
	return pm


static func _points(pm: ParticleProcessMaterial, pos: PackedVector3Array, nor: PackedVector3Array = PackedVector3Array()) -> void:
	pm.emission_point_texture = _points_tex(pos)
	pm.emission_point_count = pos.size()
	if nor.size() == pos.size() and nor.size() > 0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
		pm.emission_normal_texture = _points_tex(nor)
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS


static func _node(name: String, amount: int, life: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := FxParticles._gpu(amount, life, life, pm, mesh)
	p.name = name
	return p


static func _quad(w: float, h: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.material = mat
	return q


## The whole rain of an emitter (a Node3D at the model origin; add it to the scene next to the building).
static func build(e: Dictionary, root: Node3D, polys: Array, wind: Vector3) -> Node3D:
	var pl := plan(e, root, polys)
	var rain: Dictionary = pl["rain"]
	var geo: Dictionary = pl["geo"]
	var rng: RandomNumberGenerator = pl["rng"]
	var inten: float = pl["I"]
	var holder := Node3D.new()
	holder.name = "RainFx"
	if inten <= 0.001:
		return holder
	var col := Color(str(rain["colour"]))
	var shell := float(rain["shell"])
	var speed := float(rain["speed"])
	var life := shell / speed
	var a_roof := float(geo["total"])
	var polys_arr: Array = polys

	# 1. streaks: fall onto the ground (outside the footprint) and onto the roof facets
	var n_g := clampi(int(float(pl["ground_area"]) * 3.0), 400, 9000)
	var g_pts := _ground_points(polys_arr, float(rain["margin"]), n_g, rng)
	var roof_s := _sample_roof(geo, clampi(int(a_roof * 6.0), 0, 5000), rng)
	var start := PackedVector3Array()
	for p in g_pts:
		start.append(Vector3(p.x, shell, p.z))
	for p in (roof_s[0] as PackedVector3Array):
		start.append(p + Vector3(0, shell, 0))
	if start.size() > 0:
		var pm := _pm_base(col, 0.75 * minf(0.6 + inten * 0.5, 1.0), 0.12, 0.1)
		_points(pm, start)
		pm.direction = Vector3(wind.x * 0.03, -1.0, wind.z * 0.03).normalized()
		pm.spread = 1.0
		pm.initial_velocity_min = speed * 0.93
		pm.initial_velocity_max = speed * 1.07
		pm.gravity = Vector3.ZERO
		var surf := float(pl["ground_area"]) + a_roof
		var amount := mini(int(22.0 * inten * (surf + 1.0) * life), 45000)
		holder.add_child(_node("streaks", amount, life, pm, _quad(0.05, float(rain["streak"]), _mat_from_fx("streak", "fixed_y"))))

	# 2. splashes on the roof facets
	if bool(rain["splash"]) and (roof_s[0] as PackedVector3Array).size() > 0:
		var sp := _sample_roof(geo, clampi(int(a_roof * 8.0), 200, 4000), rng)
		var pm2 := _pm_base(Color(0.9, 0.96, 1.0), 0.85, 0.05, 0.4)
		_points(pm2, sp[0], sp[1])
		pm2.spread = 38.0
		pm2.initial_velocity_min = 0.6
		pm2.initial_velocity_max = 1.8
		pm2.gravity = Vector3(0, -G, 0)
		var life2 := 0.42
		var amount2 := mini(int(a_roof * 10.0 * inten * life2), 14000)
		var fxs := {"texture": "drop", "blend": "mix", "frame_speed": 0.0, "billboard": "fixed_y", "soft": 0.0}
		holder.add_child(_node("roof_splash", amount2, life2, pm2, _quad(0.035, 0.06, FxParticles._draw_material(fxs))))

	# 3. rivulets running down the roof facets (a thin skin with a shader)
	if bool(rain["runoff"]) and (geo["tris"] as PackedVector3Array).size() > 0:
		var skin := _runoff_skin(geo, inten)
		if skin != null:
			holder.add_child(skin)

	# 4. drips and gutter streams along the eaves, 5. what they do on the ground
	var eaves: Array = geo["eaves"]
	if bool(rain["drips"]) and not eaves.is_empty():
		var l_tot: float = pl["eave_len"]
		var h: float = pl["eave_h"]
		var tfall := sqrt(2.0 * h / G)
		var ep := _sample_eaves(geo, clampi(int(l_tot * 14.0), 60, 3000), rng)
		var pm3 := _pm_base(Color(0.85, 0.93, 1.0), 0.9, 0.04, 0.08)
		_points(pm3, ep[0], ep[1])
		pm3.spread = 8.0
		pm3.initial_velocity_min = 0.1
		pm3.initial_velocity_max = 0.45
		pm3.gravity = Vector3(0, -G, 0) + wind * 0.25
		var dfx := {"texture": "drop", "blend": "mix", "frame_speed": 0.0, "billboard": "fixed_y", "soft": 0.0}
		var drip_rate := l_tot * DRIP_RATE * inten
		holder.add_child(_node("eave_drips", mini(int(drip_rate * tfall) + 1, 6000), tfall, pm3, _quad(0.03, 0.1, FxParticles._draw_material(dfx))))
		if inten > GUTTER_MIN + 0.05:
			var pm4 := _pm_base(Color(0.8, 0.9, 1.0), 0.5, 0.04, 0.1)
			_points(pm4, ep[0], ep[1])
			pm4.spread = 3.0
			pm4.initial_velocity_min = 0.05
			pm4.initial_velocity_max = 0.2
			pm4.gravity = Vector3(0, -G, 0) + wind * 0.2
			var gutter_rate := l_tot * (inten - GUTTER_MIN) * GUTTER_RATE
			holder.add_child(_node("gutter_stream", mini(int(gutter_rate * tfall) + 1, 9000), tfall, pm4, _quad(0.05, 0.38, _mat_from_fx("streak", "fixed_y"))))
		# landing: where the drips hit the ground
		if bool(rain["ripples"]):
			var land := PackedVector3Array()
			var lnor := PackedVector3Array()
			for i in range((ep[0] as PackedVector3Array).size()):
				var pp: Vector3 = ep[0][i]
				var oo: Vector3 = ep[1][i]
				land.append(Vector3(pp.x, 0.03, pp.z) + oo * (0.28 * tfall))
				lnor.append(Vector3.UP)
			var pm5 := _pm_base(Color(0.9, 0.96, 1.0), 0.9, 0.12, 0.6)
			_points(pm5, land)
			pm5.scale_min = 0.4
			pm5.scale_max = 0.6
			pm5.scale_curve = FxParticles._curve_tex([[0.0, 0.25], [1.0, 1.0]])
			var rng_rate := (drip_rate + (l_tot * (inten - GUTTER_MIN) * GUTTER_RATE if inten > GUTTER_MIN + 0.05 else 0.0)) * 0.45
			var flat := _flat_material("ring")
			var fq := QuadMesh.new()
			fq.size = Vector2(1, 1)
			fq.orientation = PlaneMesh.FACE_Y
			fq.material = flat
			holder.add_child(_node("ground_ripples_eave", mini(int(rng_rate * 0.55) + 1, 5000), 0.55, pm5, fq))
			var pm6 := _pm_base(Color(0.9, 0.96, 1.0), 0.8, 0.05, 0.5)
			_points(pm6, land, lnor)
			pm6.spread = 40.0
			pm6.initial_velocity_min = 0.6
			pm6.initial_velocity_max = 1.7
			pm6.gravity = Vector3(0, -G, 0)
			var sfx := {"texture": "drop", "blend": "mix", "frame_speed": 0.0, "billboard": "fixed_y", "soft": 0.0}
			holder.add_child(_node("ground_spray", mini(int(rng_rate * 1.5 * 0.4) + 1, 6000), 0.4, pm6, _quad(0.025, 0.045, FxParticles._draw_material(sfx))))

	# 6. ripples on the open ground
	if bool(rain["ripples"]) and g_pts.size() > 0:
		var gp := PackedVector3Array()
		for p in g_pts:
			gp.append(Vector3(p.x, 0.03, p.z))
		var pm7 := _pm_base(Color(0.9, 0.96, 1.0), 0.8, 0.12, 0.6)
		_points(pm7, gp)
		pm7.scale_min = 0.25
		pm7.scale_max = 0.45
		pm7.scale_curve = FxParticles._curve_tex([[0.0, 0.3], [1.0, 1.0]])
		var fq2 := QuadMesh.new()
		fq2.size = Vector2(1, 1)
		fq2.orientation = PlaneMesh.FACE_Y
		fq2.material = _flat_material("ring")
		var rate7 := minf(float(pl["ground_area"]) * 0.22 * inten, 3500.0)
		holder.add_child(_node("ground_ripples", int(rate7 * 0.7) + 1, 0.7, pm7, fq2))
	return holder


static func _runoff_skin(geo: Dictionary, inten: float) -> MeshInstance3D:
	var tris: PackedVector3Array = geo["tris"]
	var nrm: PackedVector3Array = geo["nrm"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for t in range(nrm.size()):
		for k in range(3):
			verts.append(tris[t * 3 + k] + nrm[t] * 0.015)
			norms.append(nrm[t])
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sh := Shader.new()
	sh.code = RUNOFF_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("wet", clampf(inten * 1.1, 0.0, 1.5))
	mesh.surface_set_material(0, sm)
	var mi := MeshInstance3D.new()
	mi.name = "roof_runoff"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------------------------------------- export description

## `particle_fx` of a rain emitter node. Positions in model coordinates (m, Y up).
static func export_dict(e: Dictionary, root: Node3D, polys: Array) -> Dictionary:
	var pl := plan(e, root, polys)
	var rain: Dictionary = pl["rain"]
	var geo: Dictionary = pl["geo"]
	var inten: float = pl["I"]
	var surfaces: Array = []
	for part in (geo["parts"] as Array):
		surfaces.append("building.part_%d.roof" % int(part))
	var eaves: Array = []
	for ed in (geo["eaves"] as Array):
		var a: Vector3 = ed["a"]
		var b: Vector3 = ed["b"]
		var o: Vector3 = ed["out"]
		eaves.append({"a": [snappedf(a.x, 0.001), snappedf(a.y, 0.001), snappedf(a.z, 0.001)],
			"b": [snappedf(b.x, 0.001), snappedf(b.y, 0.001), snappedf(b.z, 0.001)],
			"outward": [snappedf(o.x, 0.001), 0.0, snappedf(o.z, 0.001)], "surface": "building.part_%d.roof" % int(ed["part"])})
	var bb: Rect2 = pl["bb"]
	var l_tot: float = pl["eave_len"]
	var tfall := sqrt(2.0 * float(pl["eave_h"]) / G) if l_tot > 0.0 else 0.0
	return {
		"fx_version": 1, "type": "rain",
		"area": {"min": [snappedf(bb.position.x, 0.01), snappedf(bb.position.y, 0.01)], "max": [snappedf(bb.end.x, 0.01), snappedf(bb.end.y, 0.01)],
			"ground_y": 0.0, "shell_height": float(rain["shell"])},
		"streaks": {"density_per_m2_s": snappedf(22.0 * inten, 0.01), "speed": float(rain["speed"]), "length": float(rain["streak"]), "width": 0.05,
			"colour": str(rain["colour"]), "texture": {"file": "fx/streak.png", "grid": [1, 1]}, "billboard": "fixed_y",
			"stop_on": "surface"},
		"roof": {"surfaces": surfaces, "area_m2": snappedf(float(geo["total"]), 0.01),
			"splash": {"enabled": bool(rain["splash"]), "per_m2_s": snappedf(10.0 * inten, 0.01), "lifetime": 0.42, "speed": [0.6, 1.8], "size": [0.035, 0.06],
				"texture": {"file": "fx/drop.png", "grid": [1, 1]}},
			"runoff": {"enabled": bool(rain["runoff"]), "model": "flow_film", "follows": "steepest_descent", "flow_speed": 1.1,
				"wetness": snappedf(clampf(inten * 1.1, 0.0, 1.5), 0.01), "note": "rivulets run down each facet along the line of steepest descent and leave it at the eaves"}},
		"eaves": {"edges": eaves, "length_m": snappedf(l_tot, 0.01), "height_m": snappedf(float(pl["eave_h"]), 0.01), "fall_time_s": snappedf(tfall, 0.01),
			"drips": {"enabled": bool(rain["drips"]), "per_m_s": snappedf(DRIP_RATE * inten, 0.01), "size": [0.03, 0.1], "texture": {"file": "fx/drop.png", "grid": [1, 1]}},
			"gutter_stream": {"enabled": inten > GUTTER_MIN + 0.05, "per_m_s": snappedf(maxf(inten - GUTTER_MIN, 0.0) * GUTTER_RATE, 0.01), "size": [0.05, 0.38], "texture": {"file": "fx/streak.png", "grid": [1, 1]}}},
		"ground": {"ripples": {"enabled": bool(rain["ripples"]), "per_m2_s": snappedf(0.22 * inten, 0.001), "lifetime": 0.7, "scale": [0.25, 0.45],
				"texture": {"file": "fx/ring.png", "grid": [1, 1]}, "orientation": "flat"},
			"drip_landing": {"ripples": true, "spray": true, "offset_m": snappedf(0.28 * tfall, 0.01)}},
	}
