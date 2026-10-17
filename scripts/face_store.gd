class_name FaceStore
extends RefCounted
## Per-surface corrections made in the 3D view (the "click a plane and fix it" tool).
##
## A surface ("face") has a stable id:  p<part>:w<edge>   a wall (edge of the footprint polygon)
##                                      p<part>:roofA/B   a roof slope (flat and shed roofs only have A)
## For every face only the fields that differ from the default are stored, so the project file stays
## small and a face that was never touched costs nothing:
##   off [x, y]      metres the picture is shifted on the surface (right / up)
##   scale [x, y]    magnification of the picture (1 = as is; 2 = twice as big)
##   rot             degrees, counter-clockwise
##   flip [fx, fy]   mirror
##   region          picture used instead of the automatic one (atlas region key, "" = automatic)
##   crop [x, y, w, h]  part of the region (0..1) that is used and repeated over the surface
##   tint            colour multiplied with the picture (HTML string)
##   rough, metal, spec, normal   material overrides (roughness, metallic, specular, normal-map strength)
##   light           the surface is a lit part (exported as its own node with emissive_light = true)
## Every change can be undone (undo / redo of the whole set); fast slider moves on one field are
## merged into one undo step.

signal changed(face_id: String)

const DEFAULTS := {
	"off": [0.0, 0.0], "scale": [1.0, 1.0], "rot": 0.0, "flip": [false, false],
	"region": "", "crop": [0.0, 0.0, 1.0, 1.0],
	"tint": "#ffffff", "rough": -1.0, "metal": -1.0, "spec": -1.0, "normal": -1.0, "light": false,
}
const MAPPING_FIELDS := ["off", "scale", "rot", "flip"]
const MATERIAL_FIELDS := ["tint", "rough", "metal", "spec", "normal", "light"]
const MAX_UNDO := 60
const MERGE_MSEC := 700

var faces: Dictionary = {}
var _undo: Array = []
var _redo: Array = []
var _last_field := ""
var _last_msec := 0


func clear() -> void:
	faces.clear()
	_undo.clear()
	_redo.clear()
	_last_field = ""


func get_value(id: String, field: String) -> Variant:
	var f: Dictionary = faces.get(id, {})
	if f.has(field):
		return f[field]
	return DEFAULTS[field]


func has_face(id: String) -> bool:
	return faces.has(id) and not (faces[id] as Dictionary).is_empty()


func has_mapping(id: String) -> bool:
	for k in MAPPING_FIELDS:
		if (faces.get(id, {}) as Dictionary).has(k):
			return true
	return false


func has_material(id: String) -> bool:
	for k in MATERIAL_FIELDS:
		if (faces.get(id, {}) as Dictionary).has(k):
			return true
	return false


## Text that changes whenever the material of a face changes (cache key).
func material_signature(id: String) -> String:
	var parts: Array = []
	for k in MATERIAL_FIELDS:
		if (faces.get(id, {}) as Dictionary).has(k):
			parts.append("%s=%s" % [k, str(faces[id][k])])
	return ";".join(PackedStringArray(parts))


func set_field(id: String, field: String, value: Variant) -> void:
	if not DEFAULTS.has(field):
		return
	var f: Dictionary = faces.get(id, {})
	if f.has(field) and f[field] == value:
		return
	if not f.has(field) and DEFAULTS[field] == value:
		return
	var now := Time.get_ticks_msec()
	var key := id + "/" + field
	if key != _last_field or now - _last_msec > MERGE_MSEC:
		_push_undo()
	_last_field = key
	_last_msec = now
	if DEFAULTS[field] == value:
		f.erase(field)
	else:
		f[field] = value
	if f.is_empty():
		faces.erase(id)
	else:
		faces[id] = f
	changed.emit(id)


func reset_face(id: String, only: Array = []) -> void:
	if not faces.has(id):
		return
	_push_undo()
	_last_field = ""
	if only.is_empty():
		faces.erase(id)
	else:
		for k in only:
			(faces[id] as Dictionary).erase(k)
		if (faces[id] as Dictionary).is_empty():
			faces.erase(id)
	changed.emit(id)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(faces.duplicate(true))
	faces = _undo.pop_back()
	_last_field = ""
	changed.emit("")


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(faces.duplicate(true))
	faces = _redo.pop_back()
	_last_field = ""
	changed.emit("")


func _push_undo() -> void:
	_undo.append(faces.duplicate(true))
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func to_dict() -> Dictionary:
	return faces.duplicate(true)


func from_dict(d: Dictionary) -> void:
	clear()
	for id in d.keys():
		if typeof(d[id]) != TYPE_DICTIONARY:
			continue
		var f := {}
		for k in (d[id] as Dictionary).keys():
			if DEFAULTS.has(k):
				f[k] = _fix(k, d[id][k])
		if not f.is_empty():
			faces[str(id)] = f


## JSON turns every number into float and every pair into a plain Array: put the types back.
static func _fix(field: String, v: Variant) -> Variant:
	match field:
		"flip":
			return [bool(v[0]), bool(v[1])] if typeof(v) == TYPE_ARRAY and v.size() == 2 else [false, false]
		"off", "scale":
			return [float(v[0]), float(v[1])] if typeof(v) == TYPE_ARRAY and v.size() == 2 else DEFAULTS[field]
		"crop":
			return [float(v[0]), float(v[1]), float(v[2]), float(v[3])] if typeof(v) == TYPE_ARRAY and v.size() == 4 else DEFAULTS[field]
		"rot", "rough", "metal", "spec", "normal":
			return float(v)
		"light":
			return bool(v)
	return str(v)


# ------------------------------------------------------------------ geometry of the mapping

## The picture moves on the surface, so a texture coordinate is sampled from where the picture was.
## Everything happens in metres around the centre of the face (pivot), so rotation does not shear.
##   uv      coordinate produced by the normal mapping (1 = one picture)
##   pivot   uv of the face centre
##   pw, ph  size of one picture on the surface in metres (width, height)
## Axes in metres: X right, Y up (v grows downwards, hence the minus).
static func uv_transform(uv: Vector2, pivot: Vector2, pw: float, ph: float, off: Vector2, scale: Vector2, rot_deg: float, flip: Vector2 = Vector2.ONE) -> Vector2:
	var p := Vector2((uv.x - pivot.x) * pw, -(uv.y - pivot.y) * ph)
	p -= off
	p = p.rotated(deg_to_rad(-rot_deg))
	p = Vector2(p.x / (scale.x * flip.x), p.y / (scale.y * flip.y))
	return Vector2(pivot.x + p.x / pw, pivot.y - p.y / ph)


## Convenience: the whole mapping of a face as the parameters of uv_transform().
func mapping(id: String) -> Dictionary:
	var o: Array = get_value(id, "off")
	var s: Array = get_value(id, "scale")
	var fl: Array = get_value(id, "flip")
	return {
		"off": Vector2(float(o[0]), float(o[1])),
		"scale": Vector2(maxf(absf(float(s[0])), 0.01), maxf(absf(float(s[1])), 0.01)),
		"rot": float(get_value(id, "rot")),
		"flip": Vector2(-1.0 if bool(fl[0]) else 1.0, -1.0 if bool(fl[1]) else 1.0),
	}
