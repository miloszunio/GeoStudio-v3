class_name ModelExporter
extends RefCounted
## Writes the model as binary glTF (.glb) or glTF + .bin (.gltf): meshes + materials + textures, and the metadata in the
## profile of docs/MODEL_META.md (GeoStudio on top of the MaSzyna Reloaded model format): asset.extras (model_format_version,
## osm, geo, geostudio), node.extras (semantic_id, light layers, particle / audio sources) and KHR_lights_punctual.
## Y up, metres - the glTF standard, so Blender and the world loader read it without conversion.
## A <name>.meta.json with the same metadata is written beside it.
##
## Layout of the file:
##   Building                       root node
##     walls_p0, roof_p0 ...        one node per part and layer
##     walls_p0_lit ...             surfaces marked as lit become their own node: a light layer (light_id, light_state)
##     chimney_<n>                  chimneys
##     light_<id> / particles_<id> / audio_<id>   emitters (docs/MODEL_META.md, section 4)


## glTF has no field for custom data on a node, so the node's `gltf_extras` meta is copied into `extras`; at the end of the
## export the asset block, the materials of the particle presets and the light parameters are patched into the JSON.
class ProfileExtension:
	extends GLTFDocumentExtension
	var asset_patch := {}
	var extra_materials: Array = []
	var light_fix := {}

	func _export_node(_state: GLTFState, _gltf_node: GLTFNode, json: Dictionary, node: Node) -> Error:
		if node.has_meta("gltf_extras"):
			json["extras"] = node.get_meta("gltf_extras")
		return OK

	func _export_post(state: GLTFState) -> Error:
		var j := state.json
		var a: Dictionary = j.get("asset", {})
		for k in asset_patch.keys():
			a[k] = asset_patch[k]
		j["asset"] = a
		if not extra_materials.is_empty():
			var mats: Array = j.get("materials", [])
			mats.append_array(extra_materials)
			j["materials"] = mats
		var lights: Array = ((j.get("extensions", {}) as Dictionary).get("KHR_lights_punctual", {}) as Dictionary).get("lights", [])
		for nd in j.get("nodes", []):
			var node: Dictionary = nd
			var ref: Dictionary = (node.get("extensions", {}) as Dictionary).get("KHR_lights_punctual", {})
			if ref.is_empty():
				continue
			var sid := str((node.get("extras", {}) as Dictionary).get("semantic_id", ""))
			var li := int(ref.get("light", -1))
			if li < 0 or li >= lights.size() or not light_fix.has(sid):
				continue
			var fix: Dictionary = light_fix[sid]
			var light: Dictionary = lights[li]
			light["intensity"] = float(fix["intensity"])
			if light.has("spot") and fix.has("outer"):
				light["spot"] = {"innerConeAngle": float(fix["inner"]), "outerConeAngle": float(fix["outer"])}
		state.json = j
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
	var v1 := ModelMeta.building(info)
	var emitters: EmitterFlow = info.get("emitter_flow", null)
	var any_lit := false
	for child in building_root.get_children():
		if child is MeshInstance3D and child.has_meta("pick_ids") and not (child.get_meta("surf_lit", []) as Array).is_empty() and (child.get_meta("surf_lit", []) as Array).has(true):
			any_lit = true
	var ids: Dictionary = emitters.light_ids(any_lit) if emitters != null else ({"building.lights": 0} if any_lit else {})
	var root_extras := {"semantic_id": "building"}
	if bool(info.get("legacy_meta", false)):
		root_extras["meta"] = v1          # the version 1 layout, for consumers that still read it
	root.set_meta("gltf_extras", root_extras)
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
			var chim_id := int(bits[1]) if is_chimney and bits.size() > 1 and bits[1].is_valid_int() else 0
			var ne := ProfileExport.node_extras(layer, part, want_lit, chim_id, int(ids.get("building.lights", 0)))
			node.set_meta("gltf_extras", ne)
			root.add_child(node)
			node.owner = root
			side_nodes[str(node.name)] = ne
	out["nodes"] = side_nodes.size()
	if side_nodes.is_empty():
		root.free()
		out["error"] = "Model nie ma żadnej siatki."
		return out

	var built := {"nodes": [], "materials": [], "light_fix": {}}
	if emitters != null:
		built = emitters.build_export_nodes(ids)
	for n in built["nodes"]:
		root.add_child(n)
		(n as Node).owner = root
		for sub in (n as Node).get_children():
			sub.owner = root
		side_nodes[str((n as Node).name)] = (n as Node).get_meta("gltf_extras")
	var channels: Array = emitters.channel_export_list(ids) if emitters != null else []
	var patch := ProfileExport.asset_patch(info, v1, info.get("surfaces", []), channels)

	var ext := ProfileExtension.new()
	ext.asset_patch = patch
	ext.extra_materials = built["materials"]
	ext.light_fix = built["light_fix"]
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
	if emitters != null:
		var tex_names: Array = emitters.used_textures()
		if not tex_names.is_empty():
			var fx_dir := path.get_base_dir().path_join("fx")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fx_dir) if fx_dir.begins_with("user://") or fx_dir.begins_with("res://") else fx_dir)
			for tn in tex_names:
				FxTex.save_png(str(tn), fx_dir.path_join("%s.png" % str(tn)))
	var sidecar := path.get_basename() + ".meta.json"
	var f := FileAccess.open(sidecar, FileAccess.WRITE)
	if f != null:
		var side := {"model_format_version": ProfileExport.MODEL_FORMAT_VERSION, "file": path.get_file(), "asset": patch, "nodes": side_nodes}
		if bool(info.get("legacy_meta", false)):
			side["meta_version"] = ModelMeta.VERSION
			side["building"] = v1
		f.store_string(JSON.stringify(side, "\t"))
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
