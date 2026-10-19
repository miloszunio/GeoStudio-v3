class_name MgDot
extends RefCounted
## ".mgdot" – the project file of the program: an ordinary ZIP archive under its own extension.
##
##   manifest.json    format, format version, program version, name, times, summary, list of files
##   thumbnail.png    last render of the model (for file managers / the recent list)
##   prompt.txt       the prompt that was generated for ChatGPT for this building
##   project.json     the whole state: outlines, wall heights, roof (profile, hips), chimneys, panels S1–S8 with
##                    their codes, UV edits and manual assignments, all settings
##   geo.txt/geo.json Geoportal (EGiB) data, geo/ortho.png the orthophoto crop
##   texture/         the GPT canvas, the laid-out sheet (<name>_arkusz.jpg), the cut (.atlas.json), rectified photos
##   project.log      event log
##
## The manifest carries `format_version`; a file from a newer format is refused with a clear message.

const EXT := "mgdot"
const FORMAT := "mgdot"
const FORMAT_VERSION := 1
const MANIFEST := "manifest.json"
## Folders of a project that are not part of the file (they can be regenerated).
## Written into the unpacked folder: which save of the file it came from.
const MARKER := ".mgdot_from"
const SKIP_DIRS := ["exports", "renders"]


static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "3.0.0"))


static func _collect(dir: String, rel := "") -> Array:
	var out: Array = []
	var here := dir if rel == "" else dir.path_join(rel)
	for d in DirAccess.get_directories_at(here):
		if rel == "" and d in SKIP_DIRS:
			continue
		out.append_array(_collect(dir, d if rel == "" else rel.path_join(d)))
	for f in DirAccess.get_files_at(here):
		out.append(f if rel == "" else rel.path_join(f))
	return out


## Packs the project folder into `out_path` (written to a temporary file first, so an old file is never lost).
## `extra` may hold: thumbnail (Image), prompt (String), summary (Dictionary). Returns "" or an error text.
static func pack(project_dir: String, out_path: String, extra: Dictionary = {}) -> String:
	if not DirAccess.dir_exists_absolute(project_dir):
		return "Brak folderu projektu."
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var tmp := out_path + ".tmp"
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK:
		return "Nie można zapisać pliku: " + out_path
	var files := _collect(project_dir)
	var listing: Array = []
	var thumb_png := PackedByteArray()
	var thumb: Image = extra.get("thumbnail", null)
	if thumb != null and not thumb.is_empty():
		thumb_png = thumb.save_png_to_buffer()
	else:
		var rdir := project_dir.path_join("renders")
		var best := ""
		for f in DirAccess.get_files_at(rdir):
			if f.ends_with(".png") and f > best:
				best = f
		if best != "":
			thumb_png = FileAccess.get_file_as_bytes(rdir.path_join(best))
	for rel in files:
		if rel == MANIFEST or rel == "thumbnail.png" or rel == "prompt.txt" or rel == MARKER:
			continue
		var bytes := FileAccess.get_file_as_bytes(project_dir.path_join(rel))
		zip.start_file(rel)
		zip.write_file(bytes)
		zip.close_file()
		listing.append({"path": rel, "bytes": bytes.size()})
	if not thumb_png.is_empty():
		zip.start_file("thumbnail.png")
		zip.write_file(thumb_png)
		zip.close_file()
	var prompt := str(extra.get("prompt", ""))
	if prompt != "":
		zip.start_file("prompt.txt")
		zip.write_file(prompt.to_utf8_buffer())
		zip.close_file()
	var pj := _read_json(project_dir.path_join("project.json"))
	var manifest := {
		"format": FORMAT, "format_version": FORMAT_VERSION, "app": "Photo-to-3D Studio (GeoStudio)",
		"app_version": app_version(), "name": str(pj.get("name", project_dir.get_file())),
		"saved": str(pj.get("updated", ProjectStore.timestamp())), "created": str(pj.get("created", "")),
		"summary": extra.get("summary", {}), "has_thumbnail": not thumb_png.is_empty(),
		"has_prompt": prompt != "", "files": listing,
	}
	zip.start_file(MANIFEST)
	zip.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	zip.close_file()
	zip.close()
	# swap: the finished temporary file replaces the old one
	var bak := out_path + ".bak"
	if FileAccess.file_exists(out_path):
		DirAccess.rename_absolute(out_path, bak)
	if DirAccess.rename_absolute(tmp, out_path) != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, out_path)
		return "Nie udało się zapisać pliku: " + out_path
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return ""


static func _read_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Manifest of an archive, or {} when the file is not a valid .mgdot. `error` (optional out) is not needed:
## use `check()` for a message.
static func read_manifest(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var out := {}
	if zip.file_exists(MANIFEST):
		var d = JSON.parse_string(zip.read_file(MANIFEST).get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY and d.get("format", "") == FORMAT:
			out = d
	zip.close()
	return out


## "" when the file can be opened, otherwise the reason.
static func check(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Plik nie istnieje: " + path
	var m := read_manifest(path)
	if m.is_empty():
		return "To nie jest poprawny plik .mgdot (brak manifestu)."
	if int(m.get("format_version", 0)) > FORMAT_VERSION:
		return "Plik pochodzi z nowszej wersji programu (format %d, ten program zna %d)." % [int(m["format_version"]), FORMAT_VERSION]
	return ""


static func thumbnail(path: String) -> Image:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return null
	var img: Image = null
	if zip.file_exists("thumbnail.png"):
		img = Image.new()
		if img.load_png_from_buffer(zip.read_file("thumbnail.png")) != OK:
			img = null
	zip.close()
	return img


static func _safe(rel: String) -> bool:
	return rel != "" and not rel.begins_with("/") and not rel.contains("..") and not rel.contains(":") and not rel.contains("\\")


## Unpacks the archive into `dest_dir` (created). Returns "" or an error text.
static func unpack(path: String, dest_dir: String) -> String:
	var msg := check(path)
	if msg != "":
		return msg
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return "Nie można otworzyć pliku: " + path
	DirAccess.make_dir_recursive_absolute(dest_dir)
	for rel in zip.get_files():
		if rel.ends_with("/"):
			continue
		if not _safe(rel):
			zip.close()
			return "Plik zawiera niedozwoloną ścieżkę: " + rel
		var target := dest_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "Nie można zapisać: " + target
		f.store_buffer(zip.read_file(rel))
		f.close()
	zip.close()
	var mf := FileAccess.open(dest_dir.path_join(MARKER), FileAccess.WRITE)
	if mf != null:
		mf.store_string(str(read_manifest(path).get("saved", "?")))
		mf.close()
	return ""


## Folder to unpack `path` into: <dir of file>/<name>_projekt; reused when it was unpacked from this very save.
static func work_folder(path: String) -> Dictionary:
	var m := read_manifest(path)
	var base := path.get_basename() + "_projekt"
	var n := 1
	var cand := base
	while DirAccess.dir_exists_absolute(cand):
		if FileAccess.file_exists(cand.path_join(MARKER)) and FileAccess.get_file_as_string(cand.path_join(MARKER)).strip_edges() == str(m.get("saved", "?")):
			return {"dir": cand, "reuse": true}
		n += 1
		cand = "%s_%d" % [base, n]
	return {"dir": cand, "reuse": false}
