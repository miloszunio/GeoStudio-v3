class_name ModelExporter
extends RefCounted
## Writes the model as binary glTF (.glb): meshes + materials + textures, and the meta layer in
## `extras.meta` of the nodes (see ModelMeta). Y up, metres - the glTF standard, so Blender and the
## world loader read it without conversion. A <name>.meta.json with the same meta is written beside it.
##
## Layout of the file:
##   Building                      root node, extras.meta = model description
##     walls_p0, roof_p0 ...       one node per part and layer, extras.meta = {layer, part, part_role}
##     walls_p0_lit ...            surfaces marked as lit become their own node with emissive_light = true


## glTF has no field for custom data on a node, so the node's `gltf_extras` meta is copied into `extras`.
class ExtrasExtension:
	extends GLTFDocumentExtension

	func _export_node(_state: GLTFState, _gltf_node: GLTFNode, json: Dictionary, node: Node) -> Error:
		if node.has_meta("gltf_extras"):
			json["extras"] = node.get_meta("gltf_extras")
		return OK


## building_root: the Walls*/Roof* mesh nodes of the scene. Returns {ok, path, error, nodes, sidecar}.
static func export_glb(building_root: Node3D, info: Dictionary, path: String) -> Dictionary:
	var out := {"ok": false, "path": path, "error": "", "nodes": 0, "sidecar": ""}
	if not is_instance_valid(building_root):
		out["error"] = "Brak modelu do wyeksportowania."
		return out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var root := Node3D.new()
	root.name = "Building"
	var root_meta := ModelMeta.building(info)
	root.set_meta("gltf_extras", {"meta": root_meta})
	var side_nodes := {}
	for child in building_root.get_children():
		if not (child is MeshInstance3D) or not child.has_meta("pick_ids"):
			continue    # highlight and other helpers do not belong to the model
		var mi := child as MeshInstance3D
		var is_roof := str(mi.name).begins_with("Roof")
		var is_chimney := str(mi.name).begins_with("Chimney")
		var layer := "roof" if is_roof else ("chimney" if is_chimney else "walls")
		var bits := str(mi.name).split("_")
		var part := int(bits[1]) - 1 if bits.size() > 1 and bits[1].is_valid_int() else 0
		if is_chimney:
			part = int(mi.get_meta("chimney_part", 0))
		var lit_flags: Array = mi.get_meta("surf_lit", [])
		for want_lit in [false, true]:
			var mesh := ArrayMesh.new()
			for si in range(mi.mesh.get_surface_count()):
				var lit: bool = si < lit_flags.size() and bool(lit_flags[si])
				if lit != want_lit:
					continue
				var arrays := mi.mesh.surface_get_arrays(si)
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var mat := mi.mesh.surface_get_material(si)
				if mat != null:
					var named := mat.duplicate() as Material
					named.resource_name = "%s_p%d_%d" % [layer, part, si]
					mesh.surface_set_material(mesh.get_surface_count() - 1, named)
			if mesh.get_surface_count() == 0:
				continue
			var node := MeshInstance3D.new()
			node.name = ("chimney_%s" % bits[1]) if is_chimney else ("%s_p%d%s" % [layer, part, "_lit" if want_lit else ""])
			node.mesh = mesh
			var nm := ModelMeta.submodel(layer, part, want_lit)
			if is_chimney and bits.size() > 1 and bits[1].is_valid_int():
				nm["chimney_id"] = int(bits[1])
			node.set_meta("gltf_extras", {"meta": nm})
			root.add_child(node)
			node.owner = root
			side_nodes[str(node.name)] = nm
	out["nodes"] = side_nodes.size()
	if side_nodes.is_empty():
		root.free()
		out["error"] = "Model nie ma żadnej siatki."
		return out

	var ext := ExtrasExtension.new()
	GLTFDocument.register_gltf_document_extension(ext)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	GLTFDocument.unregister_gltf_document_extension(ext)
	root.free()
	if err != OK:
		out["error"] = "Zapis glTF nie powiódł się (kod %d)." % err
		return out
	var sidecar := path.get_basename() + ".meta.json"
	var f := FileAccess.open(sidecar, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"meta_version": ModelMeta.VERSION, "file": path.get_file(), "building": root_meta, "nodes": side_nodes}, "\t"))
		f.close()
		out["sidecar"] = sidecar
	out["ok"] = true
	return out


## The JSON part of a .glb (for checks and tools).
static func read_glb_json(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 20 or b.decode_u32(0) != 0x46546C67:
		return {}
	var d = JSON.parse_string(b.slice(20, 20 + b.decode_u32(12)).get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else {}
