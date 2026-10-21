class_name SceneryTrees
extends RefCounted
## Procedural trees for the preview surroundings: oak (round crown), birch (slender, white bark), spruce (tiers of needle sprigs), bushes.
## Trunks and branches are tapered tubes merged per species; crowns are thousands of leaf cards (alpha-scissored sprites tinted per leaf,
## darker towards the inside of the crown) in one MultiMesh per species, swaying in the scene wind (shader). Never exported.

const STRIDE := 20      # 12 transform + 4 colour + 4 custom floats per MultiMesh instance

static var _tex_cache: Dictionary = {}


class Batch:
	extends RefCounted
	var buf := PackedFloat32Array()
	var n := 0

	func add(b: Basis, o: Vector3, col: Color, cust: Color) -> void:
		buf.append_array(PackedFloat32Array([
			b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
			col.r, col.g, col.b, col.a, cust.r, cust.g, cust.b, cust.a]))
		n += 1


class Mesher:
	extends RefCounted
	var st := SurfaceTool.new()
	var vc := 0

	func _init(custom := true) -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if custom:
			st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)


# ------------------------------------------------------------------ textures (luminance sprites, tinted per instance)

static func leaf_tex(kind: String) -> ImageTexture:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + kind.hash() % 1000
	match kind:
		"needle":
			for stem in range(3):
				var ang := (-0.45 + 0.45 * stem) + rng.randf_range(-0.06, 0.06)
				var base := Vector2(64.0 + (stem - 1) * 6.0, 124.0)
				var dir := Vector2(sin(ang), -cos(ang))
				var length := 108.0 - absf(stem - 1) * 10.0
				var t := 4.0
				while t < length:
					var p := base + dir * t
					var side_len := 26.0 * (1.0 - t / length * 0.75) + rng.randf_range(-2.0, 2.0)
					for sgn in [-1.0, 1.0]:
						var a2: float = ang + sgn * rng.randf_range(0.85, 1.15)
						var d2 := Vector2(sin(a2), -cos(a2))
						_seg(img, p, p + d2 * side_len, 1.5, rng.randf_range(0.6, 1.0))
					t += 5.0
				_seg(img, base, base + dir * length, 2.2, 0.55)
		"birch":
			for i in range(30):
				var c := Vector2(rng.randf_range(16, 112), rng.randf_range(16, 112))
				_ellipse(img, c, rng.randf() * TAU, rng.randf_range(12, 17), rng.randf_range(8, 11), rng.randf_range(0.7, 1.0))
		"flower":
			for i in range(6):
				var a := TAU * i / 6.0
				_ellipse(img, Vector2(64, 64) + Vector2(cos(a), sin(a)) * 26.0, a, 28.0, 14.0, 1.0)
			_ellipse(img, Vector2(64, 64), 0.0, 13.0, 13.0, 0.4)
		_:
			for i in range(15):
				var c := Vector2(rng.randf_range(20, 108), rng.randf_range(20, 108))
				_ellipse(img, c, rng.randf() * TAU, rng.randf_range(24, 32), rng.randf_range(11, 15), rng.randf_range(0.7, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[kind] = tex
	return tex


static func _ellipse(img: Image, c: Vector2, ang: float, a: float, b: float, lum: float) -> void:
	var r := int(ceil(maxf(a, b)))
	var ca := cos(ang)
	var sa := sin(ang)
	for y in range(maxi(int(c.y) - r, 0), mini(int(c.y) + r + 1, img.get_height())):
		for x in range(maxi(int(c.x) - r, 0), mini(int(c.x) + r + 1, img.get_width())):
			var dx := float(x) - c.x
			var dy := float(y) - c.y
			var u := (dx * ca + dy * sa) / a
			var v := (-dx * sa + dy * ca) / b
			# leaf outline: pointed at both ends
			var d := u * u + v * v * (1.0 + 0.9 * absf(u))
			if d < 1.0:
				var l := lum * (0.78 + 0.22 * (1.0 - d))
				if absf(v) < 0.06 and u > -0.9:
					l *= 1.25
				img.set_pixel(x, y, Color(minf(l, 1.0), minf(l * 1.02, 1.0), minf(l * 0.96, 1.0), 1.0))


static func _seg(img: Image, a: Vector2, b: Vector2, w: float, lum: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(w + 1.0, w + 1.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(w + 1.0, w + 1.0)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.001)
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, img.get_height())):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, img.get_width())):
			var p := Vector2(x, y)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			if p.distance_to(a + ab * t) < w:
				img.set_pixel(x, y, Color(lum, lum, lum * 0.95, 1.0))


# ------------------------------------------------------------------ colours

static func _palette(kind: String, season: String) -> Array:
	match kind:
		"spruce":
			return [Color(0.12, 0.30, 0.17), Color(0.15, 0.35, 0.19), Color(0.10, 0.26, 0.16)]
		"birch":
			match season:
				"autumn": return [Color(1.0, 0.82, 0.18), Color(0.95, 0.66, 0.12)]
				"spring": return [Color(0.66, 0.85, 0.30), Color(0.75, 0.90, 0.42)]
				_: return [Color(0.46, 0.68, 0.20), Color(0.55, 0.74, 0.24)]
		_:
			match season:
				"autumn": return [Color(0.95, 0.52, 0.08), Color(0.85, 0.26, 0.07), Color(0.88, 0.70, 0.14), Color(0.55, 0.56, 0.13)]
				"spring": return [Color(0.55, 0.78, 0.22), Color(0.66, 0.85, 0.30)]
				_: return [Color(0.32, 0.55, 0.13), Color(0.40, 0.62, 0.16), Color(0.26, 0.46, 0.11)]


static func _leaf_col(pal: Array, tree_pick: int, rng: RandomNumberGenerator, ao: float) -> Color:
	var base: Color = pal[tree_pick % pal.size()]
	if rng.randf() < 0.22:
		base = pal[rng.randi() % pal.size()]
	var j := rng.randf_range(0.82, 1.15)
	return Color(clampf(base.r * j, 0, 1), clampf(base.g * j, 0, 1), clampf(base.b * j, 0, 1), ao)


# ------------------------------------------------------------------ geometry helpers

static func _card(b: Batch, tf: Transform3D, pos: Vector3, n: Vector3, up_hint: Vector3, size: float, col: Color, cust: Color, rng: RandomNumberGenerator, roll_free: bool) -> void:
	n = n.normalized()
	var up := up_hint.normalized()
	if absf(n.dot(up)) > 0.97:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(-n, up)
	if roll_free:
		basis = basis * Basis(Vector3.BACK, rng.randf() * TAU)
	basis = basis.scaled_local(Vector3(size, size, size))
	b.add(tf.basis * basis, tf * pos, col, cust)


static func _tube(m: Mesher, tf: Transform3D, pts: Array, radii: Array, sides: int, cust: Color) -> void:
	var count := pts.size()
	var along := 0.0
	for i in range(count):
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, count - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)
		t = t.normalized()
		var u := t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
		var v := t.cross(u)
		if i > 0:
			along += (p - (pts[i - 1] as Vector3)).length()
		for k in range(sides + 1):
			var a := TAU * k / float(sides)
			var dir := u * cos(a) + v * sin(a)
			m.st.set_uv(Vector2(float(k) / sides, along * 0.35))
			m.st.set_normal((tf.basis * dir).normalized())
			m.st.set_custom(0, cust)
			m.st.add_vertex(tf * (p + dir * float(radii[i])))
	for i in range(count - 1):
		for k in range(sides):
			var a := m.vc + i * (sides + 1) + k
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			m.st.add_index(a)
			m.st.add_index(c)
			m.st.add_index(b)
			m.st.add_index(b)
			m.st.add_index(c)
			m.st.add_index(d)
	m.vc += count * (sides + 1)


static func _trunk_path(h: float, lean: Vector2, wob: float, segs: int, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	var ph := rng.randf() * TAU
	for i in range(segs + 1):
		var t := float(i) / segs
		pts.append(Vector3(lean.x * t * t + sin(t * 5.0 + ph) * wob * t, t * h, lean.y * t * t + cos(t * 4.0 + ph) * wob * t))
	return pts


static func _flare(t: float, r0: float, taper: float) -> float:
	return r0 * (1.0 - taper * t) * (1.0 + 0.9 * clampf(1.0 - t * 9.0, 0.0, 1.0))


static func _branch(m: Mesher, tf: Transform3D, from: Vector3, to: Vector3, r_from: float, cust: Color, rng: RandomNumberGenerator) -> void:
	var mid := from.lerp(to, 0.5) + Vector3(rng.randf_range(-0.25, 0.25), 0.25, rng.randf_range(-0.25, 0.25))
	var pts: Array = [from, from.lerp(mid, 0.6), mid.lerp(to, 0.4), to]
	_tube(m, tf, pts, [r_from, r_from * 0.7, r_from * 0.42, r_from * 0.12], 6, cust)


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


## One lobe of leaves: cards over the surface (and a bit inside) of an ellipsoid.
static func _lobe(b: Batch, tf: Transform3D, centre: Vector3, rad: Vector3, size: float, count: int, pal: Array, pick: int, cust: Color, rng: RandomNumberGenerator, up_bias: float) -> void:
	for i in range(count):
		var d := _rand_dir(rng)
		var depth := pow(rng.randf(), 0.32)
		var local := Vector3(d.x * rad.x, d.y * rad.y, d.z * rad.z) * depth
		var n := (d + Vector3.UP * up_bias).normalized()
		_card(b, tf, centre + local, n, Vector3.UP, size * rng.randf_range(0.8, 1.2), _leaf_col(pal, pick, rng, 0.25 + 0.75 * depth), cust, rng, true)


static func _core(m: SurfaceTool, tf: Transform3D, centre: Vector3, rad: Vector3) -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 9
	s.rings = 5
	var local := Transform3D(Basis.from_scale(rad), centre)
	m.append_from(s, 0, tf * local)


# ------------------------------------------------------------------ species

static func _oak(c: Dictionary, tf: Transform3D, h: float, far: bool, pal: Array, pick: int, rng: RandomNumberGenerator, wpos: Vector3) -> void:
	var th := h * rng.randf_range(0.30, 0.40)
	var cr := (h - th) * 0.5
	var cust := Color(h, wpos.x, wpos.z, 0.0)
	var bark_c := Color(wpos.x, wpos.z, h, 0.0)
	var lean := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
	var path := _trunk_path(th + cr * 0.5, lean, 0.18, 9, rng)
	var radii: Array = []
	var r0 := h * 0.026
	for i in range(path.size()):
		radii.append(_flare(float(i) / (path.size() - 1), r0, 0.62))
	_tube(c["bark_oak"], tf, path, radii, 10, bark_c)
	var size := 2.9 if far else 1.55
	var lobes := 5 + rng.randi() % 3
	var top := Vector3(lean.x, th + cr * 0.55, lean.y)
	var centre := top + Vector3(0, cr * 0.45, 0)
	for k in range(lobes):
		var d := _rand_dir(rng)
		var lc := centre + Vector3(d.x * cr * 0.62, d.y * cr * 0.42, d.z * cr * 0.62)
		var lr := cr * rng.randf_range(0.55, 0.78)
		var rad := Vector3(lr, lr * 0.85, lr)
		var area := 4.0 * PI * lr * lr
		var count := clampi(int(area / (size * size * 0.36)), 24, 420)
		_lobe(c["leaf_oak"], tf, lc, rad, size, count, pal, pick, cust, rng, 0.35)
		_core(c["core_oak"], tf, lc, rad * 0.72)
		if not far:
			_branch(c["bark_oak"], tf, top - Vector3(0, cr * 0.15, 0), lc - Vector3(0, lr * 0.3, 0), radii[radii.size() - 1] * 1.4 + 0.04, bark_c, rng)


static func _birch(c: Dictionary, tf: Transform3D, h: float, far: bool, pal: Array, pick: int, rng: RandomNumberGenerator, wpos: Vector3) -> void:
	var cust := Color(h, wpos.x, wpos.z, 0.0)
	var bark_c := Color(wpos.x, wpos.z, h, 0.0)
	var lean := Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
	var path := _trunk_path(h * 0.92, lean, 0.25, 10, rng)
	var radii: Array = []
	var r0 := h * 0.015
	for i in range(path.size()):
		radii.append(_flare(float(i) / (path.size() - 1), r0, 0.82))
	_tube(c["bark_birch"], tf, path, radii, 8, bark_c)
	var size := 1.9 if far else 1.0
	var lobes := 5 + rng.randi() % 3
	for k in range(lobes):
		var t := 0.5 + 0.48 * float(k) / lobes
		var yy := h * t
		var a := rng.randf() * TAU
		var off := rng.randf_range(0.5, 1.5) * (1.0 - t * 0.5)
		var base := (path[clampi(int(t * 10.0), 0, 10)] as Vector3)
		var lc := Vector3(base.x + cos(a) * off, yy, base.z + sin(a) * off)
		var lr := h * rng.randf_range(0.10, 0.15)
		var rad := Vector3(lr, lr * 1.2, lr)
		var count := clampi(int(4.0 * PI * lr * lr / (size * size * 0.34)), 20, 220)
		_lobe(c["leaf_birch"], tf, lc, rad, size, count, pal, pick, cust, rng, 0.1)
		_core(c["core_birch"], tf, lc, rad * 0.7)
		if not far:
			_branch(c["bark_birch"], tf, Vector3(base.x, yy - 0.4, base.z), lc - Vector3(0, lr * 0.4, 0), 0.035, bark_c, rng)


static func _spruce(c: Dictionary, tf: Transform3D, h: float, far: bool, pal: Array, pick: int, rng: RandomNumberGenerator, wpos: Vector3) -> void:
	var cust := Color(h, wpos.x, wpos.z, 0.0)
	var bark_c := Color(wpos.x, wpos.z, h, 0.0)
	var path := _trunk_path(h * 0.97, Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)), 0.05, 8, rng)
	var radii: Array = []
	var r0 := h * 0.022
	for i in range(path.size()):
		radii.append(_flare(float(i) / (path.size() - 1), r0, 0.9))
	_tube(c["bark_spruce"], tf, path, radii, 8, bark_c)
	var size := 3.0 if far else 1.7
	var rmax := h * 0.21
	var tiers := int(h * (0.7 if far else 1.25))
	for i in range(tiers):
		var t := float(i) / maxf(tiers - 1, 1)
		var y := h * (0.13 + 0.85 * t)
		var rr := rmax * pow(1.0 - t, 0.85) + 0.18
		var k := clampi(int(rr * (2.5 if far else 5.0)) + 3, 4, 40)
		for j in range(k):
			var a := rng.randf() * TAU
			var rad_d := Vector3(cos(a), 0, sin(a))
			var r := rr * sqrt(rng.randf_range(0.12, 1.0))
			var pos := Vector3(rad_d.x * r, y - 0.28 * r + rng.randf_range(-0.15, 0.15), rad_d.z * r)
			var n := (rad_d * 0.5 + Vector3.UP * 0.85).normalized()
			_card(c["leaf_spruce"], tf, pos, n, rad_d - Vector3.UP * 0.25, size * rng.randf_range(0.85, 1.2), _leaf_col(pal, pick, rng, 0.3 + 0.7 * (r / maxf(rr, 0.1))), cust, rng, false)
		if i % 3 == 0 and t < 0.95:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = rr * 0.8
			cone.height = h * 0.2
			cone.radial_segments = 9
			cone.rings = 1
			(c["core_spruce"] as SurfaceTool).append_from(cone, 0, tf * Transform3D(Basis.IDENTITY, Vector3(0, y + h * 0.04, 0)))
	_card(c["leaf_spruce"], tf, Vector3(0, h * 0.99, 0), Vector3.FORWARD, Vector3.UP, size * 0.9, _leaf_col(pal, pick, rng, 1.0), cust, rng, false)


static func _bush(c: Dictionary, tf: Transform3D, h: float, pal: Array, pick: int, rng: RandomNumberGenerator, wpos: Vector3) -> void:
	var cust := Color(h * 1.4, wpos.x, wpos.z, 0.0)
	var lobes := 3 + rng.randi() % 3
	for k in range(lobes):
		var a := rng.randf() * TAU
		var off := rng.randf_range(0.0, h * 0.5)
		var lc := Vector3(cos(a) * off, h * 0.45, sin(a) * off)
		var lr := h * rng.randf_range(0.42, 0.62)
		var rad := Vector3(lr, lr * 0.8, lr)
		_lobe(c["leaf_oak"], tf, lc, rad, 0.8, clampi(int(4.0 * PI * lr * lr / 0.3), 16, 140), pal, pick, cust, rng, 0.3)
		_core(c["core_oak"], tf, lc, rad * 0.7)


# ------------------------------------------------------------------ build

## sites: [{kind: oak|birch|spruce|bush, pos: Vector3, h: float, far: bool, yaw: float}]
static func build(parent: Node3D, sites: Array, season: String, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c := {}
	for k in ["oak", "birch", "spruce"]:
		c["leaf_" + k] = Batch.new()
		c["bark_" + k] = Mesher.new(true)
		var cs := SurfaceTool.new()
		cs.begin(Mesh.PRIMITIVE_TRIANGLES)
		c["core_" + k] = cs
	for s in sites:
		var pos: Vector3 = s["pos"]
		var tf := Transform3D(Basis(Vector3.UP, float(s.get("yaw", 0.0))), pos)
		var h: float = s["h"]
		var far: bool = s.get("far", false)
		var kind: String = s["kind"]
		var pal := _palette("oak" if kind == "bush" else kind, season)
		var pick := rng.randi()
		match kind:
			"oak": _oak(c, tf, h, far, pal, pick, rng, pos)
			"birch": _birch(c, tf, h, far, pal, pick, rng, pos)
			"spruce": _spruce(c, tf, h, far, pal, pick, rng, pos)
			_: _bush(c, tf, h, pal, pick, rng, pos)
	var core_cols := {"oak": Color(0.10, 0.20, 0.06), "birch": Color(0.18, 0.28, 0.08), "spruce": Color(0.05, 0.14, 0.08)}
	if season == "autumn":
		core_cols["oak"] = Color(0.30, 0.16, 0.05)
		core_cols["birch"] = Color(0.40, 0.30, 0.06)
	for k in ["oak", "birch", "spruce"]:
		# bark
		var bm: Mesher = c["bark_" + k]
		if bm.vc > 0:
			var bmesh := bm.st.commit()
			var bi := MeshInstance3D.new()
			bi.name = "Bark_" + k
			bi.mesh = bmesh
			var mat := ShaderMaterial.new()
			mat.shader = _shader(SceneryShaders.BARK)
			match k:
				"birch":
					mat.set_shader_parameter("base_col", Color(0.86, 0.85, 0.80))
					mat.set_shader_parameter("marks", 1.0)
					mat.set_shader_parameter("stripes", 2.0)
				"spruce":
					mat.set_shader_parameter("base_col", Color(0.30, 0.20, 0.13))
				_:
					mat.set_shader_parameter("base_col", Color(0.24, 0.18, 0.12))
			bi.material_override = mat
			bi.extra_cull_margin = 6.0
			parent.add_child(bi)
		# cores (dark filler inside crowns)
		var cs: SurfaceTool = c["core_" + k]
		var cmesh := cs.commit()
		if cmesh != null and cmesh.get_surface_count() > 0:
			var ci := MeshInstance3D.new()
			ci.name = "Core_" + k
			ci.mesh = cmesh
			var cm := StandardMaterial3D.new()
			cm.albedo_color = core_cols[k]
			cm.roughness = 1.0
			ci.material_override = cm
			parent.add_child(ci)
		# leaves
		var lb: Batch = c["leaf_" + k]
		if lb.n > 0:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			mm.mesh = q
			mm.instance_count = lb.n
			mm.buffer = lb.buf
			var mi := MultiMeshInstance3D.new()
			mi.name = "Leaves_" + k
			mi.multimesh = mm
			var lm := ShaderMaterial.new()
			lm.shader = _shader(SceneryShaders.LEAVES)
			lm.set_shader_parameter("tex", leaf_tex({"oak": "broad", "birch": "birch", "spruce": "needle"}[k]))
			mi.material_override = lm
			mi.extra_cull_margin = 8.0
			parent.add_child(mi)


static var _shader_cache: Dictionary = {}


static func _shader(code: String) -> Shader:
	if not _shader_cache.has(code):
		var sh := Shader.new()
		sh.code = code
		_shader_cache[code] = sh
	return _shader_cache[code]
