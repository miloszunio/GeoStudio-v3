class_name EmitterPick
extends RefCounted
## Selecting and moving emitters in the 3D view: a click on the faint ball of an emitter selects it (and shows the Emitery tab);
## the selected one has move arrows (drag an arrow to move along that axis). Called by the camera rig before it treats the mouse
## as a camera or a surface click.

var app
var dragging := false
var _axis := -1
var _e: Dictionary = {}
var _axis_dir := Vector3.ZERO
var _start_pos := Vector3.ZERO
var _anchor := 0.0


func _init(main_scene) -> void:
	app = main_scene


func _ray(pos: Vector2) -> Array:
	return [app.camera.project_ray_origin(pos), app.camera.project_ray_normal(pos)]


## Distance along the ray to a sphere, or -1.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t


## Parameter (m) of the point on the axis line through `origin` along `dir` that is closest to the mouse ray.
static func axis_param(o: Vector3, d: Vector3, origin: Vector3, dir: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(o, o + d * 2000.0, origin - dir * 500.0, origin + dir * 500.0)
	return (pts[1] as Vector3 - origin).dot(dir)


## The arrow under the mouse (index) or -1.
func _arrow_at(pos: Vector2) -> int:
	var flow: EmitterFlow = app.emitters
	if flow.selected == "" or not is_instance_valid(app.camera):
		return -1
	var e := flow.find_emitter(flow.selected)
	if e.is_empty():
		return -1
	var axes := flow.axes_of(e)
	var origin := flow.pick_position(e)
	var ray := _ray(pos)
	var unit := EmitterGizmo.unit(app.camera, origin)
	var best := -1
	var best_d := INF
	for i in range(axes.size()):
		var dir: Vector3 = axes[i]["dir"]
		var pts := Geometry3D.get_closest_points_between_segments(ray[0], ray[0] + ray[1] * 2000.0, origin + dir * unit * 0.1, origin + dir * unit * 1.0)
		var dist: float = (pts[0] as Vector3).distance_to(pts[1])
		if dist < unit * 0.09 and dist < best_d:
			best = i
			best_d = dist
	return best


## Mouse pressed: starts dragging an arrow. True = consumed (the camera must not start orbiting).
func press(pos: Vector2) -> bool:
	var flow: EmitterFlow = app.emitters
	var i := _arrow_at(pos)
	if i < 0:
		return false
	_e = flow.find_emitter(flow.selected)
	var axes := flow.axes_of(_e)
	_axis = i
	_axis_dir = axes[i]["dir"]
	if str(_e["kind"]).begins_with("particle_") and int(_e.get("chimney", 0)) > 0:
		var p := flow.position_of(_e)         # a free emitter from now on
		_e["chimney"] = 0
		_e["pos"] = [p.x, p.y, p.z]
	_start_pos = flow.pick_position(_e)
	var ray := _ray(pos)
	_anchor = axis_param(ray[0], ray[1], _start_pos, _axis_dir)
	dragging = true
	var g := _gizmo()
	if g != null:
		g.active = i
	return true


func _gizmo() -> EmitterGizmo:
	var root: Node = app.emitters._gizmo_root()
	return root.get_node_or_null("SelGizmo") as EmitterGizmo if root != null else null


func motion(pos: Vector2) -> void:
	if not dragging:
		return
	var flow: EmitterFlow = app.emitters
	var ray := _ray(pos)
	var t := axis_param(ray[0], ray[1], _start_pos, _axis_dir) - _anchor
	var np := _start_pos + _axis_dir * t
	if str(_e["kind"]) == "light_surface":
		var fr := flow.wall_frame(int(_e["part"]), int(_e["wall"]))
		var r: Array = _e["rect"]
		if not fr.is_empty():
			var d: Vector2 = fr["d"]
			var a: Vector2 = fr["a"]
			var u := (Vector2(np.x, np.z) - a - Vector2(0.0, 0.0)).dot(d) - float(r[2]) * 0.5
			r[0] = clampf(u, 0.0, maxf(float(fr["len"]) - float(r[2]), 0.0))
		r[1] = maxf(np.y - float(r[3]) * 0.5, 0.0)
	else:
		_e["pos"] = [snappedf(np.x, 0.01), snappedf(np.y, 0.01), snappedf(np.z, 0.01)]
	flow.apply_live(_e)


func release() -> void:
	if not dragging:
		return
	dragging = false
	var g := _gizmo()
	if g != null:
		g.active = -1
	app.emitters.commit_emitter(_e)


## A click (not a drag) on the 3D view. True = it hit an emitter (the surface under it must not be selected).
func click(pos: Vector2) -> bool:
	var flow: EmitterFlow = app.emitters
	if not is_instance_valid(app.camera):
		return false
	var ray := _ray(pos)
	var best_id := ""
	var best_t := INF
	for e in flow.list():
		var c := flow.pick_position(e)
		var r := EmitterPickSphere.radius_for(app.camera, c)
		if ray_sphere(ray[0], ray[1], c, r) < 0.0:
			continue
		# of the balls under the mouse take the one whose centre is closest to the ray (balls may overlap)
		var perp: float = ((c - (ray[0] as Vector3)).cross(ray[1] as Vector3)).length() / r
		if perp < best_t:
			best_t = perp
			best_id = str(e["id"])
	if best_id != "":
		flow.select(best_id)
		app.panel.select_tab("emit", true)
		return true
	if flow.selected != "" and app._pick_face(pos) == "":
		flow.select("")                  # a click on the empty background lets go of the selection
	return false
