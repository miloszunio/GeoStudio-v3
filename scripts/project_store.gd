class_name ProjectStore
extends RefCounted
## One folder per model (or group of buildings). Everything that belongs to it lives there:
##
##   <project>/
##     project.json        state: parts (outlines), settings snapshot, texture, map position, camera
##     geo.txt             human-readable Geoportal data (ids, attributes, outlines, services, time)
##     geo.json            the same, machine-readable (also holds the ortho crop bounds)
##     geo/ortho.png       crop of the orthophoto around the building (reference for texturing)
##     texture/            copy of the chosen texture + its <name>.atlas.json (the cut into regions)
##     renders/            lastView_<timestamp>.png, written when the app closes
##     exports/            glb / t3d ... (written by the export module)
##     project.log         timestamped events (build, texture, render, ...)
##
## Paths inside project.json are relative to the project folder, so the folder can be moved or zipped.

const VERSION := 1
const FILE := "project.json"
const SUBDIRS := ["geo", "texture", "renders", "exports"]

var dir := ""
var data: Dictionary = {}


func is_open() -> bool:
	return dir != ""


func project_name() -> String:
	return str(data.get("name", dir.get_file()))


func path(rel: String) -> String:
	return dir.path_join(rel)


static func norm(p: String) -> String:
	var out := p.strip_edges().replace("\\", "/")
	if out.begins_with("res://") or out.begins_with("user://"):
		out = ProjectSettings.globalize_path(out)
	while out.length() > 1 and out.ends_with("/") and not out.ends_with(":/"):
		out = out.left(out.length() - 1)
	return out


## Opens the folder as a project; a folder without project.json becomes a new project.
## Returns "" or an error message.
func open(folder: String, name := "") -> String:
	var d := norm(folder)
	if d == "":
		return "Nie wskazano folderu."
	var err := DirAccess.make_dir_recursive_absolute(d)
	if err != OK and not DirAccess.dir_exists_absolute(d):
		return "Nie można utworzyć folderu: " + d
	dir = d
	for s in SUBDIRS:
		DirAccess.make_dir_recursive_absolute(path(s))
	data = read_json(FILE)
	var fresh := data.is_empty()
	if fresh:
		data = {
			"version": VERSION, "name": name if name != "" else d.get_file(),
			"created": timestamp(), "app": "Photo-to-3D Studio",
		}
	elif int(data.get("version", 0)) > VERSION:
		var newer := int(data["version"])
		dir = ""
		data = {}
		return "Projekt pochodzi z nowszej wersji programu (format %d)." % newer
	if not save():
		dir = ""
		return "Folder jest tylko do odczytu: " + d
	log_event("Projekt " + ("utworzony" if fresh else "otwarty"))
	return ""


func close() -> void:
	dir = ""
	data = {}


func save() -> bool:
	if dir == "":
		return false
	data["updated"] = timestamp()
	data["version"] = VERSION
	return write_json(FILE, data)


# ------------------------------------------------------------------ files

func write_text(rel: String, text: String) -> bool:
	if dir == "":
		return false
	DirAccess.make_dir_recursive_absolute(path(rel).get_base_dir())
	var f := FileAccess.open(path(rel), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func write_json(rel: String, value: Variant) -> bool:
	return write_text(rel, JSON.stringify(value, "\t"))


func read_json(rel: String) -> Dictionary:
	var p := path(rel)
	if dir == "" or not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func inside(p: String) -> bool:
	return dir != "" and norm(p).begins_with(dir + "/")


func relative(p: String) -> String:
	var n := norm(p)
	return n.trim_prefix(dir + "/") if inside(n) else n


## Absolute path for something stored in project.json (relative or already absolute).
func resolve(p: String) -> String:
	if p == "":
		return ""
	if p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://"):
		return norm(p)
	return path(p)


## Copies a file into <project>/<subdir> and returns the new absolute path.
## A file that already lives in the project is left where it is. A second file with the same name
## but different content gets a numeric suffix. A hand-edited <name>.atlas.json next to the source
## is copied too, so the cut travels with the texture.
func import_file(src: String, subdir: String) -> String:
	if dir == "" or src.strip_edges() == "":
		return src
	var s := src.strip_edges().replace("\\", "/")
	if inside(s) or not FileAccess.file_exists(s):
		return norm(s)
	var bytes := FileAccess.get_file_as_bytes(s)
	var base := s.get_file().get_basename()
	var ext := s.get_extension()
	var target := path(subdir).path_join(s.get_file())
	var n := 2
	while FileAccess.file_exists(target) and FileAccess.get_file_as_bytes(target).size() != bytes.size():
		target = path(subdir).path_join("%s_%d.%s" % [base, n, ext])
		n += 1
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if not FileAccess.file_exists(target):
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			return norm(s)
		f.store_buffer(bytes)
		f.close()
	var side := s.get_base_dir().path_join(base + ".atlas.json")
	var side_target := target.get_basename() + ".atlas.json"
	if FileAccess.file_exists(side) and not FileAccess.file_exists(side_target):
		var sb := FileAccess.get_file_as_bytes(side)
		var sf := FileAccess.open(side_target, FileAccess.WRITE)
		if sf != null:
			sf.store_buffer(sb)
			sf.close()
	log_event("Tekstura skopiowana do projektu: " + relative(target))
	return target


## Writes renders/lastView_<timestamp>.png and keeps only the newest `keep` of them.
func save_render(img: Image, keep := 3) -> String:
	if dir == "" or img == null:
		return ""
	var stamp := timestamp().replace("-", "").replace(":", "").replace(" ", "_")
	var rel := "renders/lastView_%s.png" % stamp
	if img.save_png(path(rel)) != OK:
		return ""
	var old: Array = []
	for f in DirAccess.get_files_at(path("renders")):
		if f.begins_with("lastView_") and f.ends_with(".png"):
			old.append(f)
	old.sort()
	while old.size() > maxi(keep, 1):
		DirAccess.remove_absolute(path("renders").path_join(str(old.pop_front())))
	log_event("Render zapisany: " + rel)
	return path(rel)


func log_event(msg: String) -> void:
	if dir == "":
		return
	var p := path("project.log")
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s  %s" % [timestamp(), msg])
	f.close()


static func timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]


# ------------------------------------------------------------------ recent projects

## `recent` is stored in the settings as one string, folders separated by "|".
static func recent_list(stored: String) -> Array:
	var out: Array = []
	for p in stored.split("|", false):
		if DirAccess.dir_exists_absolute(p):
			out.append(p)
	return out


static func push_recent(stored: String, folder: String, max_items := 8) -> String:
	var list: Array = [norm(folder)]
	for p in stored.split("|", false):
		if p != norm(folder) and list.size() < max_items:
			list.append(p)
	return "|".join(PackedStringArray(list))


## Same for single files (.mgdot): only those that still exist are listed.
static func recent_files(stored: String) -> Array:
	var out: Array = []
	for p in stored.split("|", false):
		if FileAccess.file_exists(p):
			out.append(p)
	return out
