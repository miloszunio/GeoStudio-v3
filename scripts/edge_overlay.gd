class_name EdgeOverlay
extends RefCounted

## Diagnostic overlay in the manner of 3ds Max "Edged Faces": the shaded model with its edges drawn on top.
## Godot's own DEBUG_DRAW_WIREFRAME is 1 px thin and cannot be coloured, so the edges are real geometry:
## every edge is a screen-space quad (width in pixels, set in the shader), drawn twice – once with the depth
## test (visible edges, full strength) and once without it (hidden edges, pale). Vertices are camera-facing
## discs of constant pixel size with an outline.

const EDGE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform vec4 col : source_color = vec4(1.0, 0.82, 0.0, 1.0);
uniform float thick_px = 1.6;
uniform float toward_cam = 0.03;
void vertex() {
	vec4 va = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vb = MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	va.z += toward_cam;
	vb.z += toward_cam;
	vec4 a = PROJECTION_MATRIX * va;
	vec4 b = PROJECTION_MATRIX * vb;
	float eps = 0.02;
	if (a.w < eps && b.w < eps) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else {
		if (b.w < eps) { float t = (a.w - eps) / (a.w - b.w); b = mix(a, b, t); }
		if (a.w < eps) { float t = (b.w - eps) / (b.w - a.w); a = mix(b, a, t); }
		vec2 sa = a.xy / a.w * VIEWPORT_SIZE * 0.5;
		vec2 sb = b.xy / b.w * VIEWPORT_SIZE * 0.5;
		vec2 d = sb - sa;
		d = length(d) > 0.0001 ? normalize(d) : vec2(1.0, 0.0);
		vec2 n = vec2(-d.y, d.x);
		vec4 p = (UV.y < 0.5) ? a : b;
		p.xy += n * UV.x * thick_px * 0.5 / (VIEWPORT_SIZE * 0.5) * p.w;
		POSITION = p;
	}
}
void fragment() {
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""

const POINT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform float radius_px = 4.0;
uniform float outline_px = 1.5;
uniform vec4 outline_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float alpha = 1.0;
uniform float toward_cam = 0.05;
varying vec3 vcol;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += toward_cam;
	vec4 p = PROJECTION_MATRIX * v;
	p.xy += UV * (radius_px + outline_px) / (VIEWPORT_SIZE * 0.5) * p.w;
	POSITION = p;
	vcol = COLOR.rgb;
}
void fragment() {
	float r = length(UV) * (radius_px + outline_px);
	if (r > radius_px + outline_px) discard;
	vec3 c = r > radius_px ? outline_col.rgb : vcol;
	ALBEDO = c;
	ALPHA = alpha;
}
"""

const HOLDER := "EdgeOverlay"


static func _q(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))


## Welded vertices and edges of every model mesh under `root`.
## Returns {verts: PackedVector3Array, kinds: PackedInt32Array (0 base of a wall, 1 higher wall vertex, 2 roof / chimney),
## edges: PackedInt32Array (pairs), diag: PackedByteArray (1 = edge between two coplanar triangles of one surface)}
static func collect(root: Node3D) -> Dictionary:
	var vid := {}
	var verts := PackedVector3Array()
	var kinds := PackedInt32Array()
	var edge_info := {}      # key -> [a, b, tri_normal, surface_tag, count, show]
	for child in root.get_children():
		if not (child is MeshInstance3D) or not child.has_meta("pick_ids") or (child as MeshInstance3D).mesh == null:
			continue
		var mi := child as MeshInstance3D
		var nm := str(mi.name)
		var is_roof := nm.begins_with("Roof") or nm.begins_with("Chimney")
		for si in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(si)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ind = arrays[Mesh.ARRAY_INDEX]
			var n_idx: int = (ind as PackedInt32Array).size() if ind != null else vv.size()
			var tag := "%s/%d" % [nm, si]
			for ti in range(n_idx / 3):
				var ids := [0, 0, 0]
				var pts := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
				for c in range(3):
					var vi: int = (ind as PackedInt32Array)[ti * 3 + c] if ind != null else ti * 3 + c
					var p: Vector3 = mi.transform * vv[vi]
					pts[c] = p
					var k := _q(p)
					if not vid.has(k):
						vid[k] = verts.size()
						verts.append(p)
						kinds.append(2 if is_roof else (0 if p.y < 0.05 else 1))
					elif is_roof:
						kinds[vid[k]] = 2
					ids[c] = vid[k]
				var nrm: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
				if nrm.length_squared() < 1e-12:
					continue
				nrm = nrm.normalized()
				for c in range(3):
					var a: int = ids[c]
					var b: int = ids[(c + 1) % 3]
					if a == b:
						continue
					var key := Vector2i(mini(a, b), maxi(a, b))
					if not edge_info.has(key):
						edge_info[key] = [a, b, nrm, tag, 1, 1]
					else:
						var e: Array = edge_info[key]
						e[4] += 1
						# an edge is a "diagonal" when the two triangles lie in one plane and belong to one surface
						if (e[2] as Vector3).dot(nrm) > 0.9998 and e[3] == tag:
							e[5] = 0
						else:
							e[5] = 1
	var edges := PackedInt32Array()
	var diag := PackedByteArray()
	for key in edge_info:
		var e: Array = edge_info[key]
		edges.append(int(e[0]))
		edges.append(int(e[1]))
		diag.append(0 if int(e[5]) == 1 else 1)
	return {"verts": verts, "kinds": kinds, "edges": edges, "diag": diag}


static func _edge_mesh(data: Dictionary, with_diag: bool) -> ArrayMesh:
	var verts: PackedVector3Array = data["verts"]
	var edges: PackedInt32Array = data["edges"]
	var diag: PackedByteArray = data["diag"]
	var pos := PackedVector3Array()
	var other := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for e in range(edges.size() / 2):
		if diag[e] == 1 and not with_diag:
			continue
		var a: Vector3 = verts[edges[e * 2]]
		var b: Vector3 = verts[edges[e * 2 + 1]]
		var base := pos.size()
		# corners: (end a, side -1), (end a, +1), (end b, -1), (end b, +1); UV.y picks the end
		for c in range(4):
			var at_b := c >= 2
			pos.append(b if at_b else a)
			var o: Vector3 = a if at_b else b
			# the vertex shader reads the partner from CUSTOM0 and uses UV.y < 0.5 for "this end"
			other.append_array([o.x, o.y, o.z])
			uv.append(Vector2(-1.0 if c % 2 == 0 else 1.0, 0.0))
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var mesh := ArrayMesh.new()
	if pos.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = other
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh


static func _point_mesh(data: Dictionary, colors: Array) -> ArrayMesh:
	var verts: PackedVector3Array = data["verts"]
	var kinds: PackedInt32Array = data["kinds"]
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for i in range(verts.size()):
		var base := pos.size()
		for c in range(4):
			pos.append(verts[i])
			uv.append(corners[c])
			col.append(colors[clampi(kinds[i], 0, 2)])
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var mesh := ArrayMesh.new()
	if pos.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _mat(code: String, hidden: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code % ("depth_test_disabled" if hidden else "depth_test_default")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 0 if hidden else 1
	return m


## (Re)creates the overlay under `root` according to the view settings (`s` is the AppSettings object).
static func apply(root: Node3D, s) -> void:
	if not is_instance_valid(root):
		return
	var old := root.get_node_or_null(HOLDER)
	if old != null:
		root.remove_child(old)
		old.queue_free()
	var want_edges: bool = s.b("view_wireframe")
	var want_verts: bool = s.b("view_vertices")
	if not want_edges and not want_verts:
		return
	var data := collect(root)
	var holder := Node3D.new()
	holder.name = HOLDER
	root.add_child(holder)
	if want_edges:
		var em := _edge_mesh(data, s.b("view_wire_diag"))
		var ec: Color = s.c("view_wire_color")
		var hid: float = s.f("view_wire_hidden")
		for hidden in [true, false]:
			if hidden and hid <= 0.001:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Edges_hidden" if hidden else "Edges"
			mi.mesh = em
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16384.0
			var m := _mat(EDGE_SHADER, hidden)
			m.set_shader_parameter("col", Color(ec.r, ec.g, ec.b, s.f("view_wire_opacity") * (hid if hidden else 1.0)))
			m.set_shader_parameter("thick_px", s.f("view_wire_thick"))
			mi.material_override = m
			holder.add_child(mi)
	if want_verts:
		var pm := _point_mesh(data, [s.c("view_vert_base"), s.c("view_vert_eave"), s.c("view_vert_roof")])
		var hid2: float = s.f("view_wire_hidden")
		for hidden in [true, false]:
			if hidden and hid2 <= 0.001:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Verts_hidden" if hidden else "Verts"
			mi.mesh = pm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16384.0
			var m := _mat(POINT_SHADER, hidden)
			m.set_shader_parameter("radius_px", s.f("view_vert_size") * 0.5)
			m.set_shader_parameter("outline_px", s.f("view_vert_outline"))
			m.set_shader_parameter("outline_col", s.c("view_vert_outline_color"))
			m.set_shader_parameter("alpha", hid2 if hidden else 1.0)
			mi.material_override = m
			holder.add_child(mi)
