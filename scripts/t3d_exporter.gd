class_name T3dExporter
extends RefCounted
## Export to the MaSzyna train simulator (wiki.eu07.pl): an indexed text .t3d model, textures as .tga with a .mat
## file, an include file for the scenery and a ready nodebank.txt line – the layout of the example packs:
##
##   <out>/models/<folder>/<name>.t3d
##   <out>/textures/<folder>/<name>_<tex>_diffuse.tga (+ _normalmap.tga, _specgloss.tga) and <name>_<tex>.mat
##   <out>/scenery/<folder>/<name>.inc
##   <out>/nodebank.txt, <out>/info.txt
##
## Coordinates: Godot is Y-up, T3D (3ds Max) is Z-up:  (x, y, z) -> (x, -z, y). That is a pure rotation, so the
## triangle order must be reversed (Godot: clockwise front faces, T3D: counter-clockwise). V is flipped (TGA is
## stored bottom-up, V grows upwards). Submodels (all roots, like the example packs):
##   LOD0 (0–200 m) one submodel per texture; the first one has "Map: -1" (texture comes from the node line),
##   LOD1 (200–2000 m) the same without chimneys, light_on00 for faces marked as lit (SelfIllum),
##   smokesource_light at the top of every chimney.

const NL := "\r\n"
const SEP := "//---------------------------------------------------------------------------------"
const LOD0_MAX := 200.0
const LOD1_MAX := 2000.0


static func _n(v: float) -> String:
	var s := "%.5f" % v
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


## Godot (Y up) -> T3D (Z up).
static func to_t3d(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


static func safe_name(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		var c: int = ch.unicode_at(0)
		out += ch if ((c >= 48 and c <= 57) or (c >= 97 and c <= 122) or ch in "-_") else "_"
	out = out.strip_edges()
	while out.contains("__"):
		out = out.replace("__", "_")
	return out if out != "" else "model"


# ------------------------------------------------------------------------------------------------ TGA

## Uncompressed true-colour TGA (bottom-left origin, like the example textures). 24 bit, or 32 bit with alpha.
static func tga_bytes(img: Image, with_alpha: bool) -> PackedByteArray:
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width()
	var h := im.get_height()
	var bpp := 4 if with_alpha else 3
	var out := PackedByteArray()
	out.resize(18 + w * h * bpp)
	out[2] = 2
	out.encode_u16(12, w)
	out.encode_u16(14, h)
	out[16] = bpp * 8
	out[17] = 8 if with_alpha else 0
	var src := im.get_data()
	var o := 18
	for y in range(h - 1, -1, -1):
		var row := y * w * 4
		for x in range(w):
			var p := row + x * 4
			out[o] = src[p + 2]
			out[o + 1] = src[p + 1]
			out[o + 2] = src[p]
			if with_alpha:
				out[o + 3] = src[p + 3]
				o += 4
			else:
				o += 3
	return out


static func write_tga(path: String, img: Image, with_alpha := false) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(tga_bytes(img, with_alpha))
	f.close()
	return true


static func _flat_image(c: Color) -> Image:
	var im := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	im.fill(c)
	return im


# ------------------------------------------------------------------------------------------------ geometry

## Tangents (xyz + handedness) from positions, normals and UVs (V already flipped).
static func tangents(pos: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> PackedFloat32Array:
	var tan1 := PackedVector3Array()
	var tan2 := PackedVector3Array()
	tan1.resize(pos.size())
	tan2.resize(pos.size())
	for t in range(idx.size() / 3):
		var i0 := idx[t * 3]
		var i1 := idx[t * 3 + 1]
		var i2 := idx[t * 3 + 2]
		var e1 := pos[i1] - pos[i0]
		var e2 := pos[i2] - pos[i0]
		var d1 := uv[i1] - uv[i0]
		var d2 := uv[i2] - uv[i0]
		var det := d1.x * d2.y - d2.x * d1.y
		if absf(det) < 1e-12:
			continue
		var r := 1.0 / det
		var sd := (e1 * d2.y - e2 * d1.y) * r
		var td := (e2 * d1.x - e1 * d2.x) * r
		for i in [i0, i1, i2]:
			tan1[i] += sd
			tan2[i] += td
	var out := PackedFloat32Array()
	out.resize(pos.size() * 4)
	for i in range(pos.size()):
		var n := nrm[i]
		var t := tan1[i] - n * n.dot(tan1[i])
		if t.length_squared() < 1e-12:
			t = n.cross(Vector3.UP) if absf(n.y) < 0.99 else Vector3.RIGHT
		t = t.normalized()
		var w := -1.0 if n.cross(t).dot(tan2[i]) < 0.0 else 1.0
		out[i * 4] = t.x
		out[i * 4 + 1] = t.y
		out[i * 4 + 2] = t.z
		out[i * 4 + 3] = w
	return out


## A submodel text block. `mesh` = {pos, nrm, uv, idx} already in T3D space (or empty for a dummy submodel).
static func submodel_text(name: String, parent: String, map: String, max_d: float, min_d: float, mesh: Dictionary, illum := false, translate := Vector3.ZERO) -> String:
	var s := SEP + NL
	s += "Parent: %s " % parent + NL + "Type: Mesh " + NL + "Name: %s " % name + NL + "Anim: false " + NL
	s += "Ambient: 255 255 255 " + NL + "Diffuse: 255 255 255 " + NL + "Specular: 50 50 50" + NL
	s += "SelfIllum: %s " % ("true" if illum else "false") + NL + "Wire: false " + NL + "WireSize: 1 " + NL + "Opacity: 1 " + NL
	s += "Map: %s" % map + NL
	s += "MaxDistance: %s " % _n(max_d) + NL + "MinDistance: %s " % _n(min_d) + NL
	s += "Transform: " + NL + "\t 1 0 0 0 " + NL + "\t 0 1 0 0 " + NL + "\t 0 0 1 0 " + NL
	s += "\t %s %s %s 1 " % [_n(translate.x), _n(translate.y), _n(translate.z)] + NL + NL
	if mesh.is_empty():
		return s + "NumVerts: 0 " + NL
	var idx: PackedInt32Array = mesh["idx"]
	var pos: PackedVector3Array = mesh["pos"]
	var nrm: PackedVector3Array = mesh["nrm"]
	var uv: PackedVector2Array = mesh["uv"]
	var tg: PackedFloat32Array = mesh["tan"]
	s += "NumIndices: %d " % idx.size() + NL
	var lines := PackedStringArray()
	for t in range(idx.size() / 3):
		lines.append("%d %d %d " % [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
	s += NL.join(lines) + NL
	s += "NumVerts: %d " % pos.size() + NL
	lines = PackedStringArray()
	for i in range(pos.size()):
		lines.append("%s %s %s %s %s %s %s %s %s %s %s %s " % [
			_n(pos[i].x), _n(pos[i].y), _n(pos[i].z), _n(nrm[i].x), _n(nrm[i].y), _n(nrm[i].z),
			_n(uv[i].x), _n(uv[i].y), _n(tg[i * 4]), _n(tg[i * 4 + 1]), _n(tg[i * 4 + 2]), _n(tg[i * 4 + 3])])
	return s + NL.join(lines) + NL


## Centre of the building floor (x, z in model space): the middle of the bounding box of every wall vertex that stands on the ground.
## The exported model is shifted so that this point becomes the origin (the pivot of the root submodels), with the floor at z = 0.
static func floor_centre(root: Node3D) -> Vector3:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for child in root.get_children():
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null or not str(child.name).begins_with("Walls"):
			continue
		var mi := child as MeshInstance3D
		for si in range(mi.mesh.get_surface_count()):
			var vv: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vv:
				var w := mi.transform * v
				if w.y <= 0.03:
					lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
					hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	if lo.x == INF:
		return Vector3.ZERO
	return Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)


## Collects the model into groups by texture. Returns {groups: {key: {tex: Texture2D|null, color: Color, lod0: mesh, lod1: mesh, lit: mesh}},
## order: keys by area (largest first), smoke: [Vector3 in T3D space]}.
## `names` maps a texture instance id to a readable name.
static func collect(root: Node3D, chimneys: Array, names: Dictionary) -> Dictionary:
	var groups := {}
	var area := {}
	var pivot := floor_centre(root)
	var shift := Transform3D(Basis.IDENTITY, -pivot)
	for child in root.get_children():
		if not (child is MeshInstance3D) or not child.has_meta("pick_ids") or (child as MeshInstance3D).mesh == null:
			continue
		var mi := child as MeshInstance3D
		var is_chimney := str(mi.name).begins_with("Chimney")
		var lit_flags: Array = mi.get_meta("surf_lit", [])
		for si in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(si)
			var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vv.is_empty():
				continue
			var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uu: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var ii: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ii.is_empty():
				ii.resize(vv.size())
				for k in range(vv.size()):
					ii[k] = k
			var mat := mi.mesh.surface_get_material(si) as StandardMaterial3D
			var tex: Texture2D = mat.albedo_texture if mat != null else null
			var col: Color = mat.albedo_color if mat != null else Color(0.7, 0.7, 0.7)
			var key := ("tex%d" % tex.get_instance_id()) if tex != null else ("col" + col.to_html(false))
			if not groups.has(key):
				groups[key] = {"tex": tex, "color": col, "name": str(names.get(tex.get_instance_id(), "")) if tex != null else "kolor_" + col.to_html(false),
					"lod0": _new_mesh(), "lod1": _new_mesh(), "lit": _new_mesh()}
				area[key] = 0.0
			var lit: bool = si < lit_flags.size() and bool(lit_flags[si])
			var targets: Array = ["lod0"] if is_chimney else ["lod0", "lod1"]
			if lit:
				targets.append("lit")
			var tr := shift * mi.transform
			for tgt in targets:
				_append(groups[key][tgt], vv, nn, uu, ii, tr)
			for t in range(ii.size() / 3):
				area[key] += ((tr * vv[ii[t * 3 + 1]]) - (tr * vv[ii[t * 3]])).cross((tr * vv[ii[t * 3 + 2]]) - (tr * vv[ii[t * 3]])).length() * 0.5
	var order: Array = groups.keys()
	order.sort_custom(func(a, b): return area[a] > area[b])
	var smoke: Array = []
	for c in chimneys:
		var p: Array = c["centre"]
		smoke.append(to_t3d(Vector3(float(p[0]), float(c["top_y"]), float(p[1])) - pivot))
	return {"groups": groups, "order": order, "smoke": smoke, "pivot": pivot}


static func _new_mesh() -> Dictionary:
	return {"pos": PackedVector3Array(), "nrm": PackedVector3Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}


static func _append(m: Dictionary, vv: PackedVector3Array, nn: PackedVector3Array, uu: PackedVector2Array, ii: PackedInt32Array, tr: Transform3D) -> void:
	var pos: PackedVector3Array = m["pos"]      # packed arrays are values: modify the copies, then store them back
	var nrm: PackedVector3Array = m["nrm"]
	var uv: PackedVector2Array = m["uv"]
	var idx: PackedInt32Array = m["idx"]
	var base := pos.size()
	for k in range(vv.size()):
		pos.append(to_t3d(tr * vv[k]))
		var n := tr.basis * nn[k] if k < nn.size() else Vector3.UP
		nrm.append(to_t3d(n.normalized()))
		var u := uu[k] if k < uu.size() else Vector2.ZERO
		uv.append(Vector2(u.x, 1.0 - u.y))
	for t in range(ii.size() / 3):      # reversed winding (see the class comment)
		idx.append(base + ii[t * 3])
		idx.append(base + ii[t * 3 + 2])
		idx.append(base + ii[t * 3 + 1])
	m["pos"] = pos
	m["nrm"] = nrm
	m["uv"] = uv
	m["idx"] = idx


static func _finish(m: Dictionary) -> Dictionary:
	if (m["idx"] as PackedInt32Array).is_empty():
		return {}
	m["tan"] = tangents(m["pos"], m["nrm"], m["uv"], m["idx"])
	return m


## Writes the whole pack. opts: folder, tex_max, smoke (bool), lights (bool), names (Dictionary).
## Returns {ok, error, dir, t3d, textures, verts0, verts1, notes}.
static func export(root: Node3D, chimneys: Array, name: String, out_dir: String, opts: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "error": "", "dir": out_dir, "t3d": "", "textures": [], "verts0": 0, "verts1": 0, "notes": []}
	if not is_instance_valid(root):
		res["error"] = "Brak modelu do wyeksportowania."
		return res
	var folder := safe_name(str(opts.get("folder", "geostudio")))
	var nm := safe_name(name)
	var tex_max := int(opts.get("tex_max", 2048))
	var data := collect(root, chimneys, opts.get("names", {}))
	var order: Array = data["order"]
	if order.is_empty():
		res["error"] = "Model nie ma żadnej siatki."
		return res
	var mdir := out_dir.path_join("models").path_join(folder)
	var tdir := out_dir.path_join("textures").path_join(folder)
	var sdir := out_dir.path_join("scenery").path_join(folder)
	for d in [mdir, tdir, sdir]:
		DirAccess.make_dir_recursive_absolute(d)

	# neutral normal / spec-gloss maps shared by every material
	var flat_n := "%s_plaska_normalmap" % nm
	var flat_s := "%s_matowa_specgloss" % nm
	write_tga(tdir.path_join(flat_n + ".tga"), _flat_image(Color8(128, 128, 255, 255)), true)
	write_tga(tdir.path_join(flat_s + ".tga"), _flat_image(Color8(40, 40, 40)), false)

	var tex_rel := {}      # group key -> texture base name (without extension)
	var used := {}
	var counter := 0
	for key in order:
		var g: Dictionary = data["groups"][key]
		counter += 1
		var base := safe_name(str(g["name"])) if str(g["name"]) != "" else "tekstura%d" % counter
		var tn := "%s_%s" % [nm, base]
		var k := 2
		while used.has(tn):
			tn = "%s_%s_%d" % [nm, base, k]
			k += 1
		used[tn] = true
		tex_rel[key] = tn
		var img: Image
		if g["tex"] != null:
			img = (g["tex"] as Texture2D).get_image()
			img = img.duplicate() as Image
			img.clear_mipmaps()
			if img.is_compressed():
				img.decompress()
			var m := maxi(img.get_width(), img.get_height())
			if m > tex_max:
				var f := float(tex_max) / float(m)
				img.resize(maxi(int(img.get_width() * f), 1), maxi(int(img.get_height() * f), 1), Image.INTERPOLATE_LANCZOS)
		else:
			img = _flat_image(g["color"])
		var has_alpha := false
		if img.detect_alpha() == Image.ALPHA_BLEND:
			has_alpha = true
		if not write_tga(tdir.path_join(tn + "_diffuse.tga"), img, has_alpha):
			res["error"] = "Nie można zapisać tekstury: " + tn
			return res
		var mat := "shader: normalmap_specgloss" + NL
		mat += "texture_diffuse: textures/%s/%s_diffuse" % [folder, tn] + NL
		mat += "texture_normalmap: textures/%s/%s" % [folder, flat_n] + NL
		mat += "texture_specgloss: textures/%s/%s" % [folder, flat_s]
		var mf := FileAccess.open(tdir.path_join(tn + ".mat"), FileAccess.WRITE)
		if mf == null:
			res["error"] = "Nie można zapisać materiału: " + tn
			return res
		mf.store_string(mat)
		mf.close()
		(res["textures"] as Array).append(tn)

	var txt := ""
	for lod in [0, 1]:
		var li := 0
		for key in order:
			var m := _finish((data["groups"][key] as Dictionary)["lod%d" % lod])
			if m.is_empty():
				continue
			var map := "-1" if key == order[0] else "textures/%s/%s" % [folder, tex_rel[key]]
			var sub := ("LOD%d" % lod) if li == 0 else ("LOD%d_%d" % [lod, li + 1])
			txt += submodel_text(sub, "none", map, LOD0_MAX if lod == 0 else LOD1_MAX, 0.0 if lod == 0 else LOD0_MAX, m)
			res["verts%d" % lod] = int(res["verts%d" % lod]) + (m["pos"] as PackedVector3Array).size()
			li += 1
	if bool(opts.get("lights", true)):
		var li2 := 0
		for key in order:
			var m := _finish((data["groups"][key] as Dictionary)["lit"])
			if m.is_empty():
				continue
			var map2 := "textures/%s/%s" % [folder, tex_rel[key]]
			txt += submodel_text("light_on00" if li2 == 0 else "light_on00_%d" % (li2 + 1), "none", map2, -1.0, 0.0, m, true)
			li2 += 1
	if bool(opts.get("smoke", true)):
		var si := 0
		for p in data["smoke"]:
			txt += submodel_text("smokesource_light" if si == 0 else "smokesource_light_%d" % (si + 1), "none", "-1", -1.0, 0.0, {}, false, p)
			si += 1
	var t3d_path := mdir.path_join(nm + ".t3d")
	var f := FileAccess.open(t3d_path, FileAccess.WRITE)
	if f == null:
		res["error"] = "Nie można zapisać modelu: " + t3d_path
		return res
	f.store_buffer(txt.to_utf8_buffer())
	f.close()
	res["t3d"] = t3d_path

	# scenery include + nodebank line (same shape as in the example packs)
	var main_tex: String = tex_rel[order[0]]
	var inc := "origin (p1) (p2) (p3)" + NL + "rotate 0 (p4) 0" + NL
	inc += "node 2000 0 none model 0 0 0 0 %s/%s.t3d %s/%s lights 4 endmodel" % [folder, nm, folder, main_tex] + NL
	inc += "rotate 0 0 0" + NL + "endorigin"
	var inf := FileAccess.open(sdir.path_join(nm + ".inc"), FileAccess.WRITE)
	if inf != null:
		inf.store_string(inc)
		inf.close()
	var bank := "node 2000 0 none model 0.0 0.0 0.0 0.0 %s\\%s.t3d textures\\%s\\%s lights 4 endmodel" % [folder, nm, folder, main_tex] + NL
	var bf := FileAccess.open(out_dir.path_join("nodebank.txt"), FileAccess.WRITE)
	if bf != null:
		bf.store_string(bank)
		bf.close()
	var info := "%s – model z Photo-to-3D Studio (GeoStudio)" % name + NL + NL
	info += "Zawiera:" + NL + "- models/%s/%s.t3d (LOD0 0-200 m: %d wierzchołków, LOD1 200-2000 m: %d)" % [folder, nm, int(res["verts0"]), int(res["verts1"])] + NL
	info += "- textures/%s/ (%d tekstur .tga + .mat; mapy normalnych i połysku są neutralne)" % [folder, order.size()] + NL
	info += "- scenery/%s/%s.inc" % [folder, nm] + NL + NL
	var pv: Vector3 = data["pivot"]
	info += "Początek układu modelu (pivot głównych submodeli): środek podłogi budynku, podłoga na z = 0." + NL
	info += "(przesunięcie względem widoku w aplikacji: x %s m, z %s m)" % [_n(pv.x), _n(pv.z)] + NL + NL
	info += "Wpis do nodebank.txt:" + NL + bank + NL
	info += "Wpis na tor doswiadczalny:" + NL + "include %s/%s.inc 0 0 0 0 end" % [folder, nm] + NL
	var nf := FileAccess.open(out_dir.path_join("info.txt"), FileAccess.WRITE)
	if nf != null:
		nf.store_string(info)
		nf.close()
	res["ok"] = true
	res["pivot"] = data["pivot"]
	return res
