class_name GeoCache
extends RefCounted
## Disk cache for Geoportal answers (orthophoto tiles, building outlines per grid cell).
## Shared by all projects: the same place is downloaded once. Entries are plain files:
##   user://geo_cache/<kind>/<service hash>/<name>
## An entry younger than `ttl_days` is "fresh"; an older one is still used when the server is unreachable
## (offline work). The folder is trimmed to `max_bytes` by deleting the least recently written files.

var root := "user://geo_cache"
var ttl_days := 30.0
var max_bytes := 500 * 1024 * 1024
var _writes_since_trim := 0


func path_for(kind: String, service_key: String, name: String) -> String:
	return "%s/%s/%s/%s" % [root, kind, service_key, name]


static func service_key(url: String, layer: String) -> String:
	return ("%s|%s" % [url, layer]).md5_text().left(10)


func is_fresh(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var age_days := (Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path))) / 86400.0
	return age_days <= ttl_days


## Bytes of the entry, or an empty array. `stale_ok`: also return entries older than the TTL.
func read(path: String, stale_ok := false) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	if not stale_ok and not is_fresh(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	_writes_since_trim += 1
	if _writes_since_trim >= 40:
		trim()


func stats() -> Dictionary:
	var files := _list(root)
	var total := 0
	for e in files:
		total += int(e["size"])
	return {"files": files.size(), "bytes": total}


## Deletes the oldest files until the folder fits in max_bytes.
func trim() -> int:
	_writes_since_trim = 0
	var files := _list(root)
	var total := 0
	for e in files:
		total += int(e["size"])
	if total <= max_bytes:
		return 0
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["mtime"] < b["mtime"])
	var removed := 0
	for e in files:
		if total <= max_bytes:
			break
		DirAccess.remove_absolute(str(e["path"]))
		total -= int(e["size"])
		removed += 1
	return removed


## Removes everything. Returns the number of deleted files.
func clear() -> int:
	var files := _list(root)
	for e in files:
		DirAccess.remove_absolute(str(e["path"]))
	return files.size()


func _list(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var p := dir.path_join(f)
		var fh := FileAccess.open(p, FileAccess.READ)
		var size := fh.get_length() if fh != null else 0
		out.append({"path": p, "size": size, "mtime": FileAccess.get_modified_time(p)})
	for sub in d.get_directories():
		out.append_array(_list(dir.path_join(sub)))
	return out
