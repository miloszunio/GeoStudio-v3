class_name FxParticles
extends RefCounted
## The effects engine of the emitters: builds GPU particle systems (Godot's GPUParticles3D, the engine MaSzyna Reloaded runs on)
## from the data of an emitter. The same data goes to the glTF (`particle_fx`, docs/MODEL_META.md) so the simulator can reproduce it.
##
## An effect is a list of LAYERS (flame + glow + sparks + embers + smoke ...). A layer = core parameters (`ps`: rate, lifetime, speed,
## size, cone, growth, acceleration, drag - the fields of `smoke_source`) + look (`fx`: sprite sheet, blend, colour and scale over life,
## spin, turbulence, wind coupling, emission shape, soft depth). Rain (weather_rain) is built from the roof of the model.

const BASE_PS := {"rate": 10.0, "max_particles": 200, "lifetime": [2.0, 4.0], "speed": [0.5, 1.0], "size": [0.2, 0.4], "cone_angle": 0.2,
	"growth": 0.0, "acceleration": [0.0, 0.0, 0.0], "drag": 0.0, "inherit_velocity": 0.0}

const BASE_FX := {
	"texture": "smoke", "blend": "mix", "frame_speed": 0.0, "random_frame": true,
	"ramp": [[0.0, "#ffffff", 0.0], [0.15, "#ffffff", 0.6], [1.0, "#ffffff", 0.0]],
	"scale_curve": [[0.0, 1.0], [1.0, 1.0]],
	"spin": [-20.0, 20.0],
	"turbulence": {"strength": 0.0, "scale": 2.0, "speed": 0.3},
	"wind": 0.0, "hue_variation": 0.0, "soft": 0.0,
	"emission": {"shape": "point", "radius": 0.0, "height": 0.0, "inner": 0.0},
	"billboard": "particles", "aspect": 1.0,
}

## preset -> {"fx": {...}, "layers": [{"name", "along" (m along the emission axis), "ps": {...}, "fx": {...}}], "light": {...} | null}
## Starting values - tuned by eye in the editor, not verified in the simulator.
const PRESETS := {
	"smoke": {
		"fx": {"texture": "smoke", "blend": "mix",
			"ramp": [[0.0, "#303030", 0.0], [0.06, "#3d3d3d", 0.8], [0.45, "#7a7a7a", 0.6], [1.0, "#c4c4c4", 0.0]],
			"scale_curve": [[0.0, 0.3], [0.25, 0.7], [1.0, 2.6]], "spin": [-18.0, 18.0],
			"turbulence": {"strength": 0.8, "scale": 1.1, "speed": 0.22}, "wind": 1.0,
			"emission": {"shape": "sphere", "radius": 0.1, "height": 0.0, "inner": 0.0}},
		"layers": [
			{"name": "wisps", "along": 0.05,
				"ps": {"rate": 6.0, "max_particles": 100, "lifetime": [3.0, 6.0], "speed": [0.9, 1.6], "size": [0.25, 0.5], "cone_angle": 0.2,
					"acceleration": [0.0, 0.1, 0.0], "drag": 0.3},
				"fx": {"texture": "wisp", "ramp": [[0.0, "#bdbdbd", 0.0], [0.1, "#cfcfcf", 0.3], [1.0, "#e0e0e0", 0.0]],
					"scale_curve": [[0.0, 0.5], [1.0, 2.2]], "turbulence": {"strength": 1.0, "scale": 1.6, "speed": 0.35}, "wind": 1.2,
					"emission": {"shape": "sphere", "radius": 0.08, "height": 0.0, "inner": 0.0}}},
		],
		"light": null},
	"fire": {
		"fx": {"texture": "flame", "blend": "add", "frame_speed": 1.0,
			"ramp": [[0.0, "#ffffff", 0.0], [0.1, "#ffffff", 1.0], [0.6, "#ffd28a", 0.7], [1.0, "#ff5a10", 0.0]],
			"scale_curve": [[0.0, 0.55], [0.2, 1.0], [1.0, 0.3]], "spin": [0.0, 0.0],
			"turbulence": {"strength": 0.5, "scale": 3.0, "speed": 1.2}, "wind": 0.35,
			"emission": {"shape": "sphere", "radius": 0.18, "height": 0.0, "inner": 0.0}},
		"layers": [
			{"name": "glow", "along": 0.1,
				"ps": {"rate": 10.0, "max_particles": 40, "lifetime": [0.5, 0.9], "speed": [0.0, 0.1], "size": [0.9, 1.3], "cone_angle": 0.3},
				"fx": {"texture": "glow", "blend": "add", "ramp": [[0.0, "#ff7a2a", 0.0], [0.2, "#ff7a2a", 0.22], [1.0, "#ff4a10", 0.0]],
					"scale_curve": [[0.0, 1.0], [1.0, 1.0]], "spin": [0.0, 0.0], "random_frame": false}},
			{"name": "sparks", "along": 0.3,
				"ps": {"rate": 9.0, "max_particles": 90, "lifetime": [0.8, 2.0], "speed": [1.0, 2.6], "size": [0.012, 0.028], "cone_angle": 0.6,
					"acceleration": [0.0, 0.6, 0.0], "drag": 0.3},
				"fx": {"texture": "spark", "blend": "add", "ramp": [[0.0, "#fff0b0", 0.0], [0.05, "#ffe090", 1.0], [0.6, "#ff9030", 0.8], [1.0, "#ff4000", 0.0]],
					"scale_curve": [[0.0, 1.0], [1.0, 0.3]], "spin": [0.0, 0.0], "random_frame": false,
					"turbulence": {"strength": 1.2, "scale": 4.0, "speed": 1.5}, "wind": 0.8,
					"emission": {"shape": "sphere", "radius": 0.1, "height": 0.0, "inner": 0.0}}},
			{"name": "embers", "along": 0.3,
				"ps": {"rate": 2.5, "max_particles": 30, "lifetime": [2.0, 4.0], "speed": [0.2, 0.5], "size": [0.02, 0.04], "cone_angle": 0.8,
					"acceleration": [0.0, 0.25, 0.0]},
				"fx": {"texture": "glow", "blend": "add", "ramp": [[0.0, "#ff8a30", 0.0], [0.1, "#ff7a20", 0.9], [0.7, "#e04a10", 0.5], [1.0, "#400800", 0.0]],
					"scale_curve": [[0.0, 1.0], [1.0, 0.4]], "spin": [0.0, 0.0], "random_frame": false,
					"turbulence": {"strength": 0.8, "scale": 2.0, "speed": 0.5}, "wind": 1.0,
					"emission": {"shape": "sphere", "radius": 0.15, "height": 0.0, "inner": 0.0}}},
			{"name": "smoke", "along": 0.5,
				"ps": {"rate": 5.0, "max_particles": 80, "lifetime": [2.5, 4.5], "speed": [0.5, 0.9], "size": [0.3, 0.5], "cone_angle": 0.3,
					"acceleration": [0.0, 0.1, 0.0], "drag": 0.3},
				"fx": {"texture": "smoke", "blend": "mix", "ramp": [[0.0, "#2a2a2a", 0.0], [0.15, "#303030", 0.35], [0.6, "#6a6a6a", 0.22], [1.0, "#9a9a9a", 0.0]],
					"scale_curve": [[0.0, 0.5], [1.0, 2.5]], "turbulence": {"strength": 0.9, "scale": 1.2, "speed": 0.3}, "wind": 1.2,
					"emission": {"shape": "sphere", "radius": 0.12, "height": 0.0, "inner": 0.0}}},
		],
		"light": {"colour": "#ff9a40", "energy": 2.6, "range": 7.0, "flicker": 0.45}},
	"steam": {
		"fx": {"texture": "smoke", "blend": "mix",
			"ramp": [[0.0, "#ffffff", 0.0], [0.15, "#ffffff", 0.28], [1.0, "#ffffff", 0.0]],
			"scale_curve": [[0.0, 0.4], [1.0, 2.4]], "spin": [-25.0, 25.0],
			"turbulence": {"strength": 0.8, "scale": 1.6, "speed": 0.5}, "wind": 1.2,
			"emission": {"shape": "sphere", "radius": 0.08, "height": 0.0, "inner": 0.0}},
		"layers": [
			{"name": "wisps", "along": 0.1,
				"ps": {"rate": 8.0, "max_particles": 80, "lifetime": [1.2, 2.4], "speed": [1.0, 1.8], "size": [0.2, 0.4], "cone_angle": 0.3, "drag": 0.6},
				"fx": {"texture": "wisp", "ramp": [[0.0, "#ffffff", 0.0], [0.12, "#ffffff", 0.22], [1.0, "#ffffff", 0.0]],
					"scale_curve": [[0.0, 0.5], [1.0, 1.8]], "turbulence": {"strength": 1.2, "scale": 2.0, "speed": 0.7}, "wind": 1.3,
					"emission": {"shape": "sphere", "radius": 0.06, "height": 0.0, "inner": 0.0}}},
		],
		"light": null},
	"water": {
		"fx": {"texture": "drop", "blend": "mix", "random_frame": false, "billboard": "fixed_y", "aspect": 2.2,
			"ramp": [[0.0, "#dff0ff", 0.0], [0.05, "#dff0ff", 0.9], [0.8, "#cfe6ff", 0.7], [1.0, "#cfe6ff", 0.0]],
			"scale_curve": [[0.0, 1.0], [1.0, 1.0]], "spin": [0.0, 0.0],
			"turbulence": {"strength": 0.15, "scale": 3.0, "speed": 0.5}, "wind": 0.4,
			"emission": {"shape": "sphere", "radius": 0.03, "height": 0.0, "inner": 0.0}},
		"layers": [
			{"name": "mist", "along": 0.0,
				"ps": {"rate": 14.0, "max_particles": 90, "lifetime": [1.2, 2.2], "speed": [0.2, 0.5], "size": [0.3, 0.6], "cone_angle": 0.6,
					"acceleration": [0.0, 0.1, 0.0]},
				"fx": {"texture": "smoke", "ramp": [[0.0, "#e8f4ff", 0.0], [0.2, "#e8f4ff", 0.12], [1.0, "#e8f4ff", 0.0]],
					"scale_curve": [[0.0, 0.5], [1.0, 2.0]], "turbulence": {"strength": 0.6, "scale": 1.5, "speed": 0.4}, "wind": 1.0}},
			{"name": "spray", "along": 0.0,
				"ps": {"rate": 60.0, "max_particles": 260, "lifetime": [0.8, 1.4], "speed": [3.0, 8.0], "size": [0.02, 0.04], "cone_angle": 0.45,
					"acceleration": [0.0, -9.81, 0.0], "drag": 0.05},
				"fx": {"texture": "spark", "blend": "add", "random_frame": false,
					"ramp": [[0.0, "#d8ecff", 0.0], [0.05, "#d8ecff", 0.8], [1.0, "#d8ecff", 0.0]], "spin": [0.0, 0.0],
					"wind": 0.5}},
		],
		"light": null},
}

const RAIN := {"intensity": 0.6, "shell": 9.0, "margin": 9.0, "speed": 9.5, "streak": 0.55, "colour": "#b8cfe6",
	"runoff": true, "drips": true, "splash": true, "ripples": true}

const UP := Vector3.UP


# ---------------------------------------------------------------------------------------------- data helpers

## Recursively fills `base` with the values of `given` (same keys and types only).
static func merge(base: Variant, given: Variant) -> Variant:
	if typeof(base) == TYPE_DICTIONARY:
		var out: Dictionary = (base as Dictionary).duplicate(true)
		if typeof(given) == TYPE_DICTIONARY:
			for k in out.keys():
				if (given as Dictionary).has(k):
					out[k] = merge(out[k], (given as Dictionary)[k])
		return out
	if typeof(base) == TYPE_ARRAY:
		if typeof(given) == TYPE_ARRAY and (given as Array).size() > 0:
			var arr: Array = []
			var proto: Array = base
			for i in range((given as Array).size()):
				var p: Variant = proto[mini(i, proto.size() - 1)] if proto.size() > 0 else (given as Array)[i]
				arr.append(merge(p, (given as Array)[i]))
			if proto.size() > 0 and typeof(proto[0]) != TYPE_ARRAY and (given as Array).size() != proto.size():
				return base
			return arr
		return (base as Array).duplicate(true)
	if typeof(base) == TYPE_STRING:
		return str(given) if given != null and typeof(given) == TYPE_STRING else base
	if typeof(base) == TYPE_BOOL:
		return bool(given) if typeof(given) == TYPE_BOOL else base
	if typeof(base) == TYPE_INT:
		return int(given) if (typeof(given) == TYPE_FLOAT or typeof(given) == TYPE_INT) else base
	if typeof(base) == TYPE_FLOAT:
		return float(given) if (typeof(given) == TYPE_FLOAT or typeof(given) == TYPE_INT) else base
	return base


## Clean `fx` of a layer (BASE_FX + the preset's changes + what the user set).
static func norm_fx(given: Variant) -> Dictionary:
	var out: Dictionary = merge(BASE_FX, given)
	if typeof(given) == TYPE_DICTIONARY:
		# the ramp and curve are free-length lists: take them as given when they look right
		var g: Dictionary = given
		if typeof(g.get("ramp")) == TYPE_ARRAY and (g["ramp"] as Array).size() >= 2:
			out["ramp"] = _clean_ramp(g["ramp"])
		if typeof(g.get("scale_curve")) == TYPE_ARRAY and (g["scale_curve"] as Array).size() >= 2:
			out["scale_curve"] = _clean_curve(g["scale_curve"])
	if not FxTex.SHEETS.has(str(out["texture"])):
		out["texture"] = "glow"
	if not (str(out["blend"]) in ["mix", "add"]):
		out["blend"] = "mix"
	if not (str(out["billboard"]) in ["particles", "fixed_y"]):
		out["billboard"] = "particles"
	return out


static func _clean_ramp(a: Array) -> Array:
	var out: Array = []
	for s in a:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 3:
			out.append([clampf(float(s[0]), 0.0, 1.0), str(s[1]), clampf(float(s[2]), 0.0, 1.0)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	return out if out.size() >= 2 else BASE_FX["ramp"].duplicate(true)


static func _clean_curve(a: Array) -> Array:
	var out: Array = []
	for s in a:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2:
			out.append([clampf(float(s[0]), 0.0, 1.0), clampf(float(s[1]), 0.0, 20.0)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	return out if out.size() >= 2 else BASE_FX["scale_curve"].duplicate(true)


static func norm_ps(given: Variant, base: Dictionary = BASE_PS) -> Dictionary:
	return merge(base, given)


## The default extra layers of a preset, ready to store in the emitter: [{"name", "along", "ps", "fx"}] with every field filled in.
static func default_layers(preset: String) -> Array:
	var out: Array = []
	for l in (PRESETS[preset]["layers"] as Array):
		out.append(norm_layer(l))
	return out


static func default_fx(preset: String) -> Dictionary:
	return norm_fx((PRESETS[preset] as Dictionary)["fx"])


static func default_light(preset: String) -> Variant:
	var l: Variant = (PRESETS[preset] as Dictionary).get("light", null)
	return (l as Dictionary).duplicate(true) if l != null else null


static func norm_layer(l: Variant) -> Dictionary:
	var g: Dictionary = l if typeof(l) == TYPE_DICTIONARY else {}
	return {"name": str(g.get("name", "layer")), "along": clampf(float(g.get("along", 0.0)), -20.0, 20.0),
		"ps": norm_ps(g.get("ps", {})), "fx": norm_fx(g.get("fx", {}))}


static func norm_light(l: Variant) -> Variant:
	if typeof(l) != TYPE_DICTIONARY:
		return null
	var g: Dictionary = l
	return {"colour": str(g.get("colour", "#ff9a40")), "energy": clampf(float(g.get("energy", 2.0)), 0.0, 100.0),
		"range": clampf(float(g.get("range", 6.0)), 0.5, 100.0), "flicker": clampf(float(g.get("flicker", 0.3)), 0.0, 1.0)}


static func norm_rain(g: Variant) -> Dictionary:
	return merge(RAIN, g)


## Wind of the scene as a vector (m/s): the model's own x / z plane.
static func wind_vec(speed: float, dir_deg: float) -> Vector3:
	return Vector3(cos(deg_to_rad(dir_deg)), 0.0, sin(deg_to_rad(dir_deg))) * speed


# ---------------------------------------------------------------------------------------------- building blocks

static func _gradient_tex(ramp: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in ramp:
		offs.append(float(s[0]))
		var c := Color(str(s[1]))
		cols.append(Color(c.r, c.g, c.b, float(s[2])))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


static func _curve_tex(pts: Array, mul: Callable = Callable()) -> CurveTexture:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 20.0
	for s in pts:
		var y := float(s[1])
		if mul.is_valid():
			y *= float(mul.call(float(s[0])))
		c.add_point(Vector2(float(s[0]), clampf(y, 0.0, 20.0)))
	var t := CurveTexture.new()
	t.curve = c
	t.width = 128
	return t


static func _draw_material(fx: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FxTex.texture(str(fx["texture"]))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if str(fx["blend"]) == "add" else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if str(fx["billboard"]) == "fixed_y" else BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	var grid := FxTex.grid_of(str(fx["texture"]))
	if grid > 1 and str(fx["billboard"]) != "fixed_y":
		m.particles_anim_h_frames = grid
		m.particles_anim_v_frames = grid
		m.particles_anim_loop = float(fx["frame_speed"]) > 0.0
	if float(fx["soft"]) > 0.0:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = float(fx["soft"])
	return m


static func _gpu(amount: int, life_max: float, life_min: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = clampi(amount, 1, 60000)
	p.lifetime = maxf(life_max, 0.05)
	pm.lifetime_randomness = clampf(1.0 - life_min / maxf(life_max, 0.001), 0.0, 1.0)
	p.preprocess = p.lifetime
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 80, 120))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.emitting = true
	return p


static func _quad(fx: Dictionary, size := 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * float(fx["aspect"]))
	q.material = _draw_material(fx)
	return q


## One layer: GPUParticles3D whose -Y axis is the emission direction (the holder is rotated so that it points along the emission axis).
## wind: scene wind (m/s). Returns a node you add under the holder.
static func build_layer(ps: Dictionary, fx: Dictionary, wind: Vector3) -> GPUParticles3D:
	var life: Array = ps["lifetime"]
	var spd: Array = ps["speed"]
	var siz: Array = ps["size"]
	var lmax := maxf(float(life[1]), 0.05)
	var lmin := clampf(float(life[0]), 0.05, lmax)
	var smean := maxf((float(siz[0]) + float(siz[1])) * 0.5, 0.001)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = rad_to_deg(float(ps["cone_angle"]))
	pm.initial_velocity_min = float(spd[0])
	pm.initial_velocity_max = maxf(float(spd[1]), float(spd[0]))
	var acc: Array = ps["acceleration"]
	pm.gravity = Vector3(float(acc[0]), float(acc[1]), float(acc[2])) + wind * float(fx["wind"])
	pm.damping_min = float(ps["drag"])
	pm.damping_max = float(ps["drag"])
	pm.scale_min = float(siz[0])
	pm.scale_max = maxf(float(siz[1]), float(siz[0]))
	# the quad is 1 m: scale = size in metres; the curve multiplies it (growth: extra linear size growth over the life)
	var growth := float(ps["growth"])
	var lmean := (lmin + lmax) * 0.5
	var mul := Callable()
	if absf(growth) > 0.0001:
		mul = func(t: float) -> float: return maxf(1.0 + growth * lmean * t / smean, 0.05)
	pm.scale_curve = _curve_tex(fx["scale_curve"], mul)
	pm.color_ramp = _gradient_tex(fx["ramp"])
	var spin: Array = fx["spin"]
	pm.angle_min = 0.0
	pm.angle_max = 360.0 if float(spin[0]) != 0.0 or float(spin[1]) != 0.0 else 0.0
	pm.angular_velocity_min = float(spin[0])
	pm.angular_velocity_max = float(spin[1])
	pm.hue_variation_min = -float(fx["hue_variation"])
	pm.hue_variation_max = float(fx["hue_variation"])
	var grid := FxTex.grid_of(str(fx["texture"]))
	if grid > 1 and str(fx["billboard"]) != "fixed_y":
		pm.anim_speed_min = float(fx["frame_speed"])
		pm.anim_speed_max = float(fx["frame_speed"])
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0 if bool(fx["random_frame"]) else 0.0
	var tb: Dictionary = fx["turbulence"]
	if float(tb["strength"]) > 0.001:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(tb["strength"])
		pm.turbulence_noise_scale = float(tb["scale"])
		pm.turbulence_noise_speed = Vector3(0, 1, 0) * float(tb["speed"])
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.25
	var em: Dictionary = fx["emission"]
	match str(em["shape"]):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = maxf(float(em["radius"]), 0.001)
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(float(em["radius"]), maxf(float(em["height"]), 0.001), float(em["radius"]))
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3(0, 1, 0)
			pm.emission_ring_radius = maxf(float(em["radius"]), 0.001)
			pm.emission_ring_inner_radius = float(em["inner"])
			pm.emission_ring_height = maxf(float(em["height"]), 0.001)
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	var amount := int(ceil(float(ps["rate"]) * lmax))
	amount = mini(amount, maxi(int(ps["max_particles"]), 1))
	var p := _gpu(amount, lmax, lmin, pm, _quad(fx))
	p.name = "Layer"
	return p


## The whole effect of a particle emitter (all layers + light), to add under a holder whose -Y axis is the emission direction.
static func build(e: Dictionary, wind: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Fx"
	var main := build_layer(e["ps"], e["fx"], wind)
	main.name = "main"
	root.add_child(main)
	for l in (e.get("layers", []) as Array):
		var layer: Dictionary = l
		var n := build_layer(layer["ps"], layer["fx"], wind)
		n.name = str(layer["name"])
		n.position = Vector3(0, -float(layer["along"]), 0)
		root.add_child(n)
	var li: Variant = e.get("light", null)
	if li != null:
		var lt := FxFlicker.new()
		lt.name = "Light"
		var c := Color(str((li as Dictionary)["colour"]))
		lt.light_color = c
		lt.base_energy = float((li as Dictionary)["energy"])
		lt.light_energy = lt.base_energy
		lt.omni_range = float((li as Dictionary)["range"])
		lt.amount = float((li as Dictionary)["flicker"])
		lt.position = Vector3(0, -0.5, 0)
		root.add_child(lt)
	return root


# ---------------------------------------------------------------------------------------------- export description

static func _layer_export(name: String, along: float, ps: Dictionary, fx: Dictionary) -> Dictionary:
	var tex := str(fx["texture"])
	var grid := FxTex.grid_of(tex)
	return {"name": name, "along": snappedf(along, 0.001),
		"rate": float(ps["rate"]), "max_particles": int(ps["max_particles"]), "lifetime": ps["lifetime"], "speed": ps["speed"],
		"size": ps["size"], "cone_angle": float(ps["cone_angle"]), "growth": float(ps["growth"]), "acceleration": ps["acceleration"],
		"drag": float(ps["drag"]),
		"texture": {"file": "fx/%s.png" % tex, "grid": [grid, grid], "frame_speed": float(fx["frame_speed"]), "random_frame": bool(fx["random_frame"])},
		"blend": str(fx["blend"]), "billboard": str(fx["billboard"]), "aspect": float(fx["aspect"]),
		"colour_over_life": fx["ramp"], "scale_over_life": fx["scale_curve"], "spin": fx["spin"], "turbulence": fx["turbulence"],
		"wind": float(fx["wind"]), "hue_variation": float(fx["hue_variation"]), "soft_depth": float(fx["soft"]), "emission": fx["emission"]}


## `particle_fx` of a particle emitter node (glTF node extras). Textures used: see used_textures().
static func export_dict(e: Dictionary) -> Dictionary:
	var layers: Array = [_layer_export("main", 0.0, e["ps"], e["fx"])]
	for l in (e.get("layers", []) as Array):
		layers.append(_layer_export(str(l["name"]), float(l["along"]), l["ps"], l["fx"]))
	var d := {"fx_version": 1, "layers": layers}
	if e.get("light", null) != null:
		d["light"] = e["light"]
	return d


static func used_textures(e: Dictionary) -> Array:
	var out: Array = []
	if typeof(e.get("fx")) == TYPE_DICTIONARY:
		out.append(str(e["fx"]["texture"]))
	for l in (e.get("layers", []) as Array):
		out.append(str(l["fx"]["texture"]))
	if str(e.get("kind", "")) == "weather_rain":
		out.append_array(["streak", "drop", "ring", "spark"])
	return out
