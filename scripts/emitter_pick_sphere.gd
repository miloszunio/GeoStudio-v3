class_name EmitterPickSphere
extends MeshInstance3D
## The faint ball around an emitter: it is what you click in the 3D view to select the emitter. Selected: brighter and gold.
## It keeps a minimum size on screen, so far-away emitters can still be hit.

const MIN_RADIUS := 0.3
var emitter_id := ""
var _mat: StandardMaterial3D


func setup(id: String, col: Color, selected: bool) -> void:
	emitter_id = id
	name = "Pick_" + id
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c := Color("#ffd24a") if selected else col
	_mat.albedo_color = Color(c.r, c.g, c.b, 0.26 if selected else 0.10)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_selected(selected: bool, col: Color) -> void:
	if _mat == null:
		return
	var c := Color("#ffd24a") if selected else col
	_mat.albedo_color = Color(c.r, c.g, c.b, 0.26 if selected else 0.10)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		scale = Vector3.ONE * radius_for(cam, global_position)


static func radius_for(cam: Camera3D, pos: Vector3) -> float:
	return maxf(MIN_RADIUS, EmitterGizmo.unit(cam, pos) * 0.45)
