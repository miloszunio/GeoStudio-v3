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
	if not app.gpt.describe.is_empty():
		info["surfaces"] = app.gpt.describe_surfaces()
		info["openings"] = app.gpt.describe_openings()
		info["gpt_building"] = app.gpt.describe.get("building", {})
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


func _export_glb() -> void:
	if not is_instance_valid(app.building_root) or app.last_rt.is_empty():
		app._set_status("Najpierw zbuduj model (krok 1).")
		return
	var base = app.project.project_name() if app.project.is_open() else "model"
	var safe := ""
	for ch in base:
		var c: int = ch.unicode_at(0)
		var plain: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch in "-_ ."
		safe += ch if plain else "_"
	var path := _exports_dir().path_join((safe.strip_edges() if safe.strip_edges() != "" else "model") + ".glb")
	var res = ModelExporter.export_glb(app.building_root, export_info(), path)
	if res["ok"]:
		app.project.log_event("Eksport GLB: " + app.project.relative(path))
		app._set_status("Zapisano %s (%d węzłów) + .meta.json." % [path, int(res["nodes"])])
	else:
		app._set_status("Eksport nie udał się: %s" % res["error"])
