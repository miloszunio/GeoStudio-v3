class_name Scenery
extends Node3D
## The surroundings of the model in the 3D preview, so the effects (smoke, rain, wind) can be judged against something other than an empty plane:
## a meadow with a ground shader (earth, grass, a piece of road with kerb and pavement), tens of thousands of swaying grass blades and flowers,
## oaks / birches / spruces / bushes with leaf cards, a hazy forest line, drifting clouds, a tuned sky and distance haze, seasons.
## It lives next to the model in the preview viewport only. It is never part of an export (exports read the Building node alone).

var app                                  # the main scene (settings, bounds, environment, old ground)
var active := false
var ground_node: MeshInstance3D
var _mats: Array = []
var _cloud_mat: ShaderMaterial
var _timer: Timer
var _road := {"on": false, "n": Vector2(0, 1), "off": 20.0, "w": 6.0}


func _init(main_scene) -> void:
	app = main_scene
	name = "Scenery"
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.35
	_timer.timeout.connect(apply)
	add_child(_timer)


const GUARD := "user://scenery_guard"        # holds the id of the part that was being put on screen
const BAD_FILE := "user://scenery_bad.txt"   # parts that took the program down on this computer; they are skipped
const LOG_FILE := "user://scenery.log"
const STAGE_WAIT := 0.7                      # seconds each part is shown before the next one is added (first build per run only)
var _gen := 0
var _proven := false                         # the staged build of this run finished without dying
var _bad: Array = []


func _log(msg: String) -> void:
	var f := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_FILE) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), msg])
		f.close()


func _load_bad() -> void:
	_bad.clear()
	if FileAccess.file_exists(BAD_FILE):
		for line in FileAccess.get_file_as_string(BAD_FILE).split("\n", false):
			_bad.append(line.strip_edges())


func _save_bad() -> void:
	var f := FileAccess.open(BAD_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_bad)))
		f.close()


func reset_bad() -> void:
	_bad.clear()
	_save_bad()
	_log("skipped parts list cleared")
	schedule()


## First build at program start. The surroundings are put on screen part by part; the id of the part being shown is kept in a guard file.
## If the previous run died (a graphics driver problem), the part named in the guard is remembered as bad and skipped from now on,
## so the rest of the scene still comes up and the culprit is found without anyone reading a log.
func startup() -> void:
	_load_bad()
	if FileAccess.file_exists(GUARD):
		var id := FileAccess.get_file_as_string(GUARD).strip_edges()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD))
		if id != "" and not _bad.has(id):
			_bad.append(id)
			_save_bad()
		_log("previous run died while showing '%s'; it will be skipped" % id)
		app._set_status("Poprzednie uruchomienie wysypało się na części otoczenia „%s”. Pomijam ją, reszta wchodzi. Lista pominiętych: Widok → Otoczenie." % id)
	schedule()


func _exit_tree() -> void:
	# a normal exit clears the guard; only a crash leaves it behind
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD))


func _mark(id: String) -> void:
	var f := FileAccess.open(GUARD, FileAccess.WRITE)
	if f != null:
		f.store_string(id)
		f.close()


## Rebuild after a short pause (sliders send many changes).
func schedule() -> void:
	_timer.start()


func _clear() -> void:
	for c in get_children():
		if c != _timer:
			remove_child(c)
			c.queue_free()
	_mats.clear()
	ground_node = null
	_cloud_mat = null


func wind_vec2() -> Vector2:
	var w := FxParticles.wind_vec(app.settings.f("fx_wind_speed"), app.settings.f("fx_wind_dir"))
	return Vector2(w.x, w.z)


func set_wind() -> void:
	var w := wind_vec2()
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("wind", w)
	if _cloud_mat != null:
		_cloud_mat.set_shader_parameter("drift", w * 1.5 + Vector2(1.2, 0.4))


func update_visibility() -> void:
	if is_instance_valid(ground_node):
		ground_node.visible = app.settings.b("view_show_ground")


## instant = everything at once (tests, rebuilds after the first successful pass); otherwise part by part, see startup().
func apply(instant := false) -> void:
	_gen += 1
	var gen := _gen
	_clear()
	var s = app.settings
	var want: bool = s.b("view_env_on")
	var env: Environment = app.env
	active = false
	if not want:
		_restore_environment(env)
		app._apply_view(false)
		return
	var season: String = s.s("view_env_season")
	var seed_v: int = s.i("view_env_seed")
	var b: AABB = app.current_bounds
	var fp := Rect2(b.position.x, b.position.z, maxf(b.size.x, 1.0), maxf(b.size.z, 1.0))
	_road_setup(fp, s)
	var holder := Node3D.new()                      # parts are built here first and put into the scene one by one
	_ground(holder, fp, season)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_clouds(holder, s.f("view_env_clouds"), rng)
	SceneryGrass.build(holder, fp, _road, s.f("view_env_grass"), season, seed_v, _mats)
	var sites := _tree_sites(fp, s.i("view_env_trees"), rng, deg_to_rad(s.f("view_cam_yaw")))
	SceneryTrees.build(holder, sites, season, seed_v + 1)
	var parts: Array = [{"id": "env"}]
	for c in holder.get_children():
		parts.append({"id": String(c.name), "node": c})
	for p in parts:
		if p["id"] == "MeadowGround":
			parts.erase(p)
			parts.insert(0, p)
			break
	if instant or _proven:
		for p in parts:
			if _bad.has(p["id"]):
				continue
			_put(p, env, season, s.f("view_env_haze"))
		_finish(holder)
		return
	_log("staged build start (%d parts, skipped: %s)" % [parts.size(), ",".join(PackedStringArray(_bad))])
	for p in parts:
		if gen != _gen:
			holder.queue_free()
			return
		var id: String = p["id"]
		if _bad.has(id):
			_log("skip " + id)
			continue
		_mark(id)
		_log("show " + id)
		_put(p, env, season, s.f("view_env_haze"))
		if id == "MeadowGround":
			app._apply_view(false)
		await get_tree().create_timer(STAGE_WAIT).timeout
	if gen != _gen:
		holder.queue_free()
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD))
	_proven = true
	_log("staged build finished")
	_finish(holder)


func _put(p: Dictionary, env: Environment, season: String, haze: float) -> void:
	if p["id"] == "env":
		_environment(env, season, haze)
		return
	var n: Node = p["node"]
	n.get_parent().remove_child(n)
	add_child(n)
	if p["id"] == "MeadowGround":
		active = true


func _finish(holder: Node3D) -> void:
	holder.queue_free()
	set_wind()
	app._apply_view(false)


func _restore_environment(env: Environment) -> void:
	env.fog_enabled = false
	env.ssao_enabled = false
	env.glow_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.sky.sky_material = ProceduralSkyMaterial.new()


func _environment(env: Environment, season: String, haze: float) -> void:
	var sky := ProceduralSkyMaterial.new()
	var top := Color(0.17, 0.37, 0.74)
	var hor := Color(0.64, 0.78, 0.92)
	match season:
		"autumn":
			top = Color(0.26, 0.42, 0.70)
			hor = Color(0.80, 0.82, 0.88)
		"spring":
			top = Color(0.20, 0.42, 0.80)
			hor = Color(0.70, 0.84, 0.95)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor.lerp(Color(0.55, 0.6, 0.55), 0.35)
	sky.ground_bottom_color = Color(0.30, 0.36, 0.30)
	sky.sky_curve = 0.14
	sky.ground_curve = 0.04
	sky.sun_angle_max = 28.0
	sky.sun_curve = 0.12
	env.sky.sky_material = sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = haze > 0.0
	env.fog_light_color = hor.lerp(Color(0.8, 0.86, 0.92), 0.4)
	env.fog_density = 0.0004 + 0.0026 * haze
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = app.settings.f("view_ambient_energy") * 1.3


func _road_setup(fp: Rect2, s) -> void:
	var on: bool = s.b("view_env_road")
	var ang := deg_to_rad(s.f("view_env_road_side"))
	var n := Vector2(-sin(ang), cos(ang))
	var w := 6.0
	var support := -INF
	for c in [fp.position, Vector2(fp.end.x, fp.position.y), fp.end, Vector2(fp.position.x, fp.end.y)]:
		support = maxf(support, (c as Vector2).dot(n))
	_road = {"on": on, "n": n, "off": support + s.f("view_env_road_dist") + w * 0.5, "w": w}


func _ground(parent: Node3D, fp: Rect2, season: String) -> void:
	var size := maxf(float(app.settings.i("view_ground_size")), 900.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	ground_node = MeshInstance3D.new()
	ground_node.name = "MeadowGround"
	ground_node.mesh = pm
	ground_node.position.y = -0.04
	var m := ShaderMaterial.new()
	m.shader = SceneryTrees._shader(SceneryShaders.GROUND)
	match season:
		"autumn":
			m.set_shader_parameter("grass_a", Color(0.24, 0.21, 0.07))
			m.set_shader_parameter("grass_b", Color(0.46, 0.40, 0.14))
			m.set_shader_parameter("dry", Color(0.55, 0.42, 0.18))
		"spring":
			m.set_shader_parameter("grass_a", Color(0.15, 0.30, 0.07))
			m.set_shader_parameter("grass_b", Color(0.36, 0.52, 0.14))
	m.set_shader_parameter("road_on", 1.0 if bool(_road["on"]) else 0.0)
	m.set_shader_parameter("road_n", _road["n"])
	m.set_shader_parameter("road_off", float(_road["off"]))
	m.set_shader_parameter("road_w", float(_road["w"]))
	m.set_shader_parameter("pad_min", fp.position - Vector2(0.4, 0.4))
	m.set_shader_parameter("pad_max", fp.end + Vector2(0.4, 0.4))
	ground_node.material_override = m
	parent.add_child(ground_node)


func _tree_sites(fp: Rect2, near_n: int, rng: RandomNumberGenerator, cam_yaw: float) -> Array:
	var sites: Array = []
	var centre := fp.get_center()
	var half_diag := fp.size.length() * 0.5
	var cam_dir := Vector2(sin(cam_yaw), cos(cam_yaw))
	var taken: Array = []
	var kinds := ["oak", "oak", "oak", "birch", "birch", "spruce", "spruce"]
	# near trees
	var tries := 0
	while taken.size() < near_n and tries < near_n * 40:
		tries += 1
		var a := rng.randf() * TAU
		var dist := half_diag + rng.randf_range(5.0, 42.0)
		var p := centre + Vector2(cos(a), sin(a)) * dist
		if SceneryGrass.rect_dist(fp, p) < 6.0 or SceneryGrass.in_road(_road, p, 4.5):
			continue
		var from_c := (p - centre)
		if from_c.length() < 26.0 + half_diag and absf(from_c.normalized().angle_to(cam_dir)) < deg_to_rad(34.0):
			continue          # keep the default viewing direction open
		if _too_close(taken, p, 5.0):
			continue
		taken.append(p)
		sites.append(_site(kinds[rng.randi() % kinds.size()], p, rng, false))
	# forest line on the horizon
	var far_n := int(near_n * 2.4)
	tries = 0
	var far_taken := 0
	while far_taken < far_n and tries < far_n * 20:
		tries += 1
		var a := rng.randf() * TAU
		var dist := half_diag + rng.randf_range(70.0, 190.0)
		var p := centre + Vector2(cos(a), sin(a)) * dist
		if SceneryGrass.in_road(_road, p, 5.0):
			continue
		far_taken += 1
		sites.append(_site(kinds[rng.randi() % kinds.size()], p, rng, true))
	# bushes: around the building and along the road
	var bush_n := int(near_n * 1.6)
	for i in range(bush_n):
		var p := Vector2.ZERO
		if rng.randf() < 0.45 or not bool(_road["on"]):
			var a := rng.randf() * TAU
			p = centre + Vector2(cos(a), sin(a)) * (half_diag + rng.randf_range(1.0, 9.0))
			if SceneryGrass.rect_dist(fp, p) < 1.4 or SceneryGrass.in_road(_road, p, 3.5):
				continue
		else:
			var n: Vector2 = _road["n"]
			var al := Vector2(n.y, -n.x)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			p = n * (float(_road["off"]) + side * (float(_road["w"]) * 0.5 + rng.randf_range(3.8, 5.5))) + al * rng.randf_range(-45.0, 45.0)
			if SceneryGrass.rect_dist(fp, p) < 3.0:
				continue
		sites.append({"kind": "bush", "pos": Vector3(p.x, 0, p.y), "h": rng.randf_range(0.8, 1.6), "far": false, "yaw": rng.randf() * TAU})
	return sites


static func _too_close(list: Array, p: Vector2, d: float) -> bool:
	for q in list:
		if (q as Vector2).distance_to(p) < d:
			return true
	return false


static func _site(kind: String, p: Vector2, rng: RandomNumberGenerator, far: bool) -> Dictionary:
	var h := 10.0
	match kind:
		"oak": h = rng.randf_range(9.0, 14.0)
		"birch": h = rng.randf_range(8.0, 12.0)
		_: h = rng.randf_range(9.0, 15.0)
	if far:
		h *= rng.randf_range(1.0, 1.3)
	return {"kind": kind, "pos": Vector3(p.x, 0, p.y), "h": h, "far": far, "yaw": rng.randf() * TAU}


func _clouds(parent: Node3D, cover: float, rng: RandomNumberGenerator) -> void:
	if cover <= 0.0:
		return
	var range_m := 1600.0
	var n_clouds := int(10.0 + 26.0 * cover)
	var batch := SceneryTrees.Batch.new()
	for i in range(n_clouds):
		var cx := rng.randf_range(-range_m * 0.95, range_m * 0.95)
		var cz := rng.randf_range(-range_m * 0.95, range_m * 0.95)
		var cy := rng.randf_range(170.0, 340.0)
		var rx := rng.randf_range(90.0, 220.0)
		var ry := rng.randf_range(24.0, 48.0)
		var rz := rng.randf_range(70.0, 150.0)
		for k in range(rng.randi_range(10, 18)):
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if d.length() > 1.0:
				d = d.normalized() * rng.randf()
			var up := clampf(d.y * 0.5 + 0.5, 0.0, 1.0)
			var size := rng.randf_range(110.0, 240.0) * (1.0 - 0.25 * absf(d.x))
			batch.add(Basis.IDENTITY, Vector3(cx + d.x * rx, cy + d.y * ry - 0.3 * ry, cz + d.z * rz),
				Color(1, 1, 1, 1), Color(float(rng.randi() % 16), size, 0.25 + 0.75 * up, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = batch.n
	mm.buffer = batch.buf
	mm.custom_aabb = AABB(Vector3(-2600, 0, -2600), Vector3(5200, 700, 5200))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Clouds"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = SceneryTrees._shader(SceneryShaders.CLOUD)
	_cloud_mat.set_shader_parameter("tex", FxTex.texture("smoke"))
	_cloud_mat.set_shader_parameter("range", range_m)
	_cloud_mat.set_shader_parameter("cover", clampf(0.55 + cover * 0.6, 0.0, 1.0))
	mi.material_override = _cloud_mat
	parent.add_child(mi)
