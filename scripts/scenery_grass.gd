class_name SceneryGrass
extends RefCounted
## Grass (tens of thousands of tapered blades in clumps, each swaying in the wind) and meadow flowers for the preview surroundings.
## One MultiMesh for the blades; stems and flower heads for the flowers. Dense near the building, taller and sparser far away.

const GRASS_TINTS := {
	"summer": [Color(0.09, 0.20, 0.04), Color(0.46, 0.64, 0.18)],
	"spring": [Color(0.12, 0.26, 0.06), Color(0.58, 0.78, 0.26)],
	"autumn": [Color(0.20, 0.17, 0.05), Color(0.72, 0.60, 0.22)],
}

const FLOWER_COLOURS := [Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.15), Color(0.72, 0.45, 0.95), Color(0.95, 0.25, 0.25), Color(1.0, 0.65, 0.8)]


static func blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ts: Array[float] = [0.0, 0.35, 0.7]
	for t: float in ts:
		var hw := 0.5 * (1.0 - 0.75 * pow(t, 1.4))
		var z := 0.2 * t * t
		st.set_uv(Vector2(0, t))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-hw, t, z))
		st.set_uv(Vector2(1, t))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(hw, t, z))
	st.set_uv(Vector2(0.5, 1.0))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0, 1.0, 0.22))
	for i in range(2):
		var a := i * 2
		for idx in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			st.add_index(idx)
	for idx in [4, 5, 6]:
		st.add_index(idx)
	return st.commit()


## Distance from p to a rectangle (0 inside).
static func rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


static func in_road(road: Dictionary, p: Vector2, margin: float) -> bool:
	if not bool(road.get("on", false)):
		return false
	var d := absf(p.dot(road["n"]) - float(road["off"]))
	return d < float(road["w"]) * 0.5 + margin


static func build(parent: Node3D, footprint: Rect2, road: Dictionary, density: float, season: String, seed_v: int, mats: Array) -> void:
	if density <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var span := 46.0
	var area := footprint.grow(span)
	var tints: Array = GRASS_TINTS.get(season, GRASS_TINTS["summer"])
	var batch := SceneryTrees.Batch.new()
	var candidates := int(area.get_area() * 2.1 * density)
	for i in range(candidates):
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var d := rect_dist(footprint, p)
		if d < 0.9 or in_road(road, p, 2.6):
			continue
		if rng.randf() > clampf(1.15 - d / 46.0, 0.05, 1.0) * clampf(0.35 + d / 9.0, 0.0, 1.0):
			continue
		if d > span:
			continue
		var far_k := 1.0 + minf(d, 40.0) / 26.0
		var blades := 9 if d < 18.0 else 6
		for b in range(blades):
			var o := Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)) * far_k
			var h := rng.randf_range(0.26, 0.52) * far_k
			var w := rng.randf_range(0.045, 0.075) * far_k
			var tilt := rng.randf_range(-0.05, 0.42)
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3(w, h, w))
			var j := rng.randf_range(0.8, 1.18)
			batch.add(basis, Vector3(p.x + o.x, -0.03, p.y + o.y), Color(j, j * rng.randf_range(0.94, 1.06), j * 0.92, 1.0), Color(0, 0, 0, 0))
	if batch.n > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = blade_mesh()
		mm.instance_count = batch.n
		mm.buffer = batch.buf
		var mi := MultiMeshInstance3D.new()
		mi.name = "Grass"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		var sm := ShaderMaterial.new()
		sm.shader = SceneryTrees._shader(SceneryShaders.GRASS)
		sm.set_shader_parameter("tint_a", tints[0])
		sm.set_shader_parameter("tint_b", tints[1])
		mi.material_override = sm
		mats.append(sm)
		parent.add_child(mi)
	if season != "autumn":
		_flowers(parent, footprint, road, density, season, rng, mats)


static func _flowers(parent: Node3D, footprint: Rect2, road: Dictionary, density: float, season: String, rng: RandomNumberGenerator, mats: Array) -> void:
	var area := footprint.grow(34.0)
	var patch := FastNoiseLite.new()
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch.frequency = 0.07
	patch.seed = rng.randi()
	var kind := FastNoiseLite.new()
	kind.noise_type = FastNoiseLite.TYPE_CELLULAR
	kind.frequency = 0.05
	kind.seed = rng.randi()
	var stems := SceneryTrees.Batch.new()
	var heads := SceneryTrees.Batch.new()
	var want := int(area.get_area() * 0.6 * density * (1.3 if season == "spring" else 1.0))
	for i in range(want):
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var d := rect_dist(footprint, p)
		if d < 1.2 or in_road(road, p, 2.8):
			continue
		var pn := patch.get_noise_2d(p.x, p.y)
		if pn < 0.12 or rng.randf() > (pn - 0.05) * 2.2:
			continue
		var ci := int(absf(kind.get_noise_2d(p.x, p.y)) * 5.0 * 3.0) % FLOWER_COLOURS.size()
		var col: Color = FLOWER_COLOURS[ci]
		var h := rng.randf_range(0.32, 0.6)
		var lean := Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, 0.05) * Basis.from_scale(Vector3(0.012, h, 0.012))
		stems.add(basis, Vector3(p.x, -0.03, p.y), Color(0.7, 0.85, 0.6, 1.0), Color(0, 0, 0, 0))
		var hc := Vector3(p.x + lean.x, h - 0.03, p.y + lean.y)
		var n := Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35)).normalized()
		var hb := Basis.looking_at(-n, Vector3.UP).scaled_local(Vector3.ONE * rng.randf_range(0.08, 0.13))
		heads.add(hb, hc, Color(col.r, col.g, col.b, 1.0), Color(h, p.x, p.y, 0.0))
	if stems.n > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = blade_mesh()
		mm.instance_count = stems.n
		mm.buffer = stems.buf
		var mi := MultiMeshInstance3D.new()
		mi.name = "FlowerStems"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = SceneryTrees._shader(SceneryShaders.GRASS)
		sm.set_shader_parameter("tint_a", Color(0.15, 0.3, 0.08))
		sm.set_shader_parameter("tint_b", Color(0.3, 0.5, 0.15))
		mi.material_override = sm
		mats.append(sm)
		parent.add_child(mi)
	if heads.n > 0:
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mm2.mesh = q
		mm2.instance_count = heads.n
		mm2.buffer = heads.buf
		var mi2 := MultiMeshInstance3D.new()
		mi2.name = "FlowerHeads"
		mi2.multimesh = mm2
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lm := ShaderMaterial.new()
		lm.shader = SceneryTrees._shader(SceneryShaders.LEAVES)
		lm.set_shader_parameter("tex", SceneryTrees.leaf_tex("flower"))
		lm.set_shader_parameter("ao_min", 1.0)
		lm.set_shader_parameter("sway_k", 1.6)
		lm.set_shader_parameter("flutter_k", 0.15)
		mi2.material_override = lm
		mats.append(lm)
		parent.add_child(mi2)
