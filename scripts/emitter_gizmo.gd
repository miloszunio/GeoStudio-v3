class_name EmitterGizmo
extends Node3D
## The move handles of the selected emitter: one arrow per axis, drawn on top of everything and kept the same size on screen.
## axes: [{"dir": Vector3, "colour": Color}]

var axes: Array = []
var active := -1 : set = _set_active
var _arrows: Array = []


func setup(axes_in: Array) -> void:
	axes = axes_in
	name = "SelGizmo"
	for a in axes:
		var holder := Node3D.new()
		var dir: Vector3 = a["dir"]
		holder.basis = Basis(Quaternion(Vector3.UP, dir)) if not dir.is_equal_approx(Vector3.UP) else Basis.IDENTITY
		var col: Color = a["colour"]
		var mat := _mat(col)
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = 0.7
		shaft.mesh = cm
		shaft.position = Vector3(0, 0.35, 0)
		shaft.material_override = mat
		holder.add_child(shaft)
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.0
		tm.bottom_radius = 0.065
		tm.height = 0.26
		tip.mesh = tm
		tip.position = Vector3(0, 0.83, 0)
		tip.material_override = mat
		holder.add_child(tip)
		add_child(holder)
		_arrows.append(mat)


static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 100
	return m


func _set_active(i: int) -> void:
	active = i
	for k in range(_arrows.size()):
		var base: Color = (axes[k] as Dictionary)["colour"]
		(_arrows[k] as StandardMaterial3D).albedo_color = base.lightened(0.55) if k == i else base


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		scale = Vector3.ONE * unit(cam, global_position)


## Length of one gizmo unit (m) at a position, so that it covers about the same number of pixels everywhere.
static func unit(cam: Camera3D, pos: Vector3) -> float:
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return cam.size * 0.10
	return cam.global_position.distance_to(pos) * tan(deg_to_rad(cam.fov * 0.5)) * 0.28
