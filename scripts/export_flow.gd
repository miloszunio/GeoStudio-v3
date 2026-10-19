class_name ExportFlow
extends RefCounted
## glTF export of the built model with its meta layer (see docs/MODEL_META.md).

var app          # the main scene (settings, atlas, faces, project ...)


func _init(main_scene) -> void:
	app = main_scene


func _exports_dir() -> String:
	var d = app.project.path("exports") if app.project.is_open() else ProjectSettings.globalize_path("user://exports")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Everything ModelMeta needs about the built model.
func export_info() -> Dictionary:
	var parts: Array = []
	for P in app.last_rt:
		var bb: Rect2 = P["bb"]
		var long_is_x := bb.size.x >= bb.size.y
		var pts: PackedVector2Array = P["pts"]
		var outline: Array = []
		for q in pts:
			outline.append([snappedf(q.x, 0.001), snappedf(q.y, 0.001)])
		parts.append({
			"wall_h": P["wall_h"], "roof_h": P["roof_h"], "roof_kind": P["roof_kind"],
			"ridge_along": "along" if bool(P["ridge_along_x"]) == long_is_x else "across",
			"footprint": outline,
		})
		if P["roof_kind"] == "gable" and bool(app.settings.b("model_roof_asym")) and float(P["ridge_half"]) > 0.001:
			var frac := clampf(app.settings.f("model_roof_ridge_shift") / maxf(app.rt_main_half, 0.001), -0.85, 0.85)
			var sh: float = frac * float(P["ridge_half"])
			(parts[parts.size() - 1] as Dictionary)["ridge_shift"] = snappedf(sh, 0.01)    # m from the middle, + = towards side A
			(parts[parts.size() - 1] as Dictionary)["roof_angles"] = [snappedf(rad_to_deg(atan2(float(P["roof_h"]), float(P["ridge_half"]) - sh)), 0.1), snappedf(rad_to_deg(atan2(float(P["roof_h"]), float(P["ridge_half"]) + sh)), 0.1)]
	for gen in RoofGen.list_from_json(app.settings.s("model_roof_gen")):
		var gi := int(gen.get("part", 0))
		if gi >= 0 and gi < parts.size():
			(parts[gi] as Dictionary)["roof_profile"] = gen["prof"]    # [x from left of gable pic, y above eaves] pairs
			(parts[gi] as Dictionary)["roof_hip_a"] = gen.get("ra", 0.0)
			(parts[gi] as Dictionary)["roof_hip_b"] = gen.get("rb", 0.0)
	var ids: Array = []
	for a in app.current_attrs:
		for k in (a as Dictionary).keys():
			if str(k).to_lower() in ["id_budynku", "idbudynku"]:
				ids.append(str(a[k]))
	var info := {
		"name": app.project.project_name() if app.project.is_open() else "model",
		"source": app.current_source, "egib_ids": ids, "floors": app.current_floors, "parts": parts,
	}
	if not app.current_is_geographic:
		info["placement"] = ModelMeta.placement(app.footprint_src_center, app.footprint_rotation_deg, app.footprint_local_center)
	var chim: Array = app.chimneys.export_list()
	if not chim.is_empty():
		info["chimneys"] = chim
	if app._use_textures():
		info["texture"] = {"file": app.settings.s("tex_source").get_file(), "px_per_m": app.settings.f("tex_px_per_m")}
		var longs = app.atlas.keys_for_role("facade_long")
		if not longs.is_empty():
			var im: Image = app.atlas.region(str(longs[0]))["img"].duplicate()
			im.clear_mipmaps()
			if im.is_compressed():
				im.decompress()
			im.resize(1, 1, Image.INTERPOLATE_BILINEAR)
			info["colour"] = "#" + im.get_pixel(0, 0).to_html(false)
	return info


func _safe_base() -> String:
	var base = app.project.project_name() if app.project.is_open() else "model"
	var safe := ""
	for ch in base:
		var c: int = ch.unicode_at(0)
		var plain: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch in "-_ ."
		safe += ch if plain else "_"
	return safe.strip_edges() if safe.strip_edges() != "" else "model"


func _model_ready() -> bool:
	if not is_instance_valid(app.building_root) or app.last_rt.is_empty():
		app._set_status("Najpierw zbuduj model (krok 1).")
		return false
	return true


func _export_glb() -> void:
	if not _model_ready():
		return
	var path := _exports_dir().path_join(_safe_base() + ".glb")
	var res = ModelExporter.export_glb(app.building_root, export_info(), path)
	if res["ok"]:
		app.project.log_event("Eksport GLB: " + app.project.relative(path))
		app._set_status("Zapisano %s (%d węzłów) + .meta.json." % [path, int(res["nodes"])])
	else:
		app._set_status("Eksport nie udał się: %s" % res["error"])


## glTF 2.0 as separate files: <name>.gltf + <name>.bin + the textures next to them (folder exports/gltf/<name>/).
func _export_gltf() -> void:
	if not _model_ready():
		return
	var dir := _exports_dir().path_join("gltf").path_join(_safe_base())
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(_safe_base() + ".gltf")
	var res = ModelExporter.export_glb(app.building_root, export_info(), path)
	if res["ok"]:
		app.project.log_event("Eksport glTF: " + app.project.relative(path))
		app._set_status("Zapisano %s (+ plik .bin i tekstury) oraz .meta.json." % path)
	else:
		app._set_status("Eksport nie udał się: %s" % res["error"])


## MaSzyna: models/ textures/ scenery/ nodebank.txt in exports/t3d/<name>/ (see T3dExporter and docs).
func _export_t3d() -> void:
	if not _model_ready():
		return
	var names := {}
	if app.atlas.loaded:
		for k in app.atlas.regions.keys():
			var t = app.atlas.regions[k].get("tex", null)
			if t != null:
				names[(t as Texture2D).get_instance_id()] = str(k)
	var base := _safe_base()
	var dir := _exports_dir().path_join("t3d").path_join(T3dExporter.safe_name(base))
	var res := T3dExporter.export(app.building_root, app.chimneys.export_list(), base, dir, {
		"folder": app.settings.s("export_t3d_folder"), "tex_max": app.settings.i("export_t3d_tex_max"),
		"smoke": app.settings.b("export_t3d_smoke"), "lights": app.settings.b("export_t3d_lights"), "names": names})
	if res["ok"]:
		app.project.log_event("Eksport T3D: " + app.project.relative(dir))
		app._set_status("T3D zapisany w %s (LOD0 %d wierzch., LOD1 %d, tekstur: %d)." % [dir, int(res["verts0"]), int(res["verts1"]), (res["textures"] as Array).size()])
	else:
		app._set_status("Eksport T3D nie udał się: %s" % res["error"])
