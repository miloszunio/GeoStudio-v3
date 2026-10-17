class_name TextureAtlas
extends RefCounted
## Loads an atlas (PNG + JSON with named regions) and slices it into separate textures,
## so each region can repeat (tile) on its own - impossible with a single atlas texture.

var loaded := false
var regions: Dictionary = {}   # key -> {"role": String, "rect": Rect2i, "tex": ImageTexture, "aspect": float}
var by_role: Dictionary = {}   # role -> Array of keys (sorted)
var relief_cache: Dictionary = {}   # "key|params" -> {"normal": ImageTexture, "height": ImageTexture}

const RELIEF_MAX_SIDE := 512


## Image shown in the "slicing preview" and what produced the regions.
var sheet_tex: Texture2D
var sheet_path := ""
var sheet_mode := ""          # "sheet" (cut into panels), "single" (one photo) or "json" (hand-made)
var is_template := false      # regions are the fixed sectors S1..S8 (see AtlasSlicer.TEMPLATE_ROLES)
var sidecar_path := ""
var source_width := 1.0       # width of the source image in px (regions are in these pixels)

const CACHE_DIR := "user://atlas_cache"


func clear() -> void:
	loaded = false
	regions.clear()
	by_role.clear()
	relief_cache.clear()
	_crops.clear()
	sheet_tex = null
	sheet_path = ""
	sheet_mode = ""
	is_template = false
	sidecar_path = ""
	source_width = 1.0


## Returns an error message, or "" on success.
func load_from(json_path: String) -> String:
	clear()
	if not FileAccess.file_exists(json_path):
		return "Nie znaleziono pliku atlasu: " + json_path
	var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("regions") or not data.has("image"):
		return "Nieprawidłowy JSON atlasu (wymagane pola: image, regions)."
	sidecar_path = json_path
	return _load_data(data, json_path.get_base_dir())


## Loads either an atlas JSON, or a plain image: a sheet is cut into panels automatically (and the
## cut is saved as <image>.atlas.json so it can be corrected by hand), a single photo stays whole.
## `force` ignores a saved cut and analyses the image again.
func load_source(path: String, opts: Dictionary = {}, force := false) -> String:
	if path.strip_edges() == "":
		clear()
		return ""
	if path.get_extension().to_lower() == "json":
		return load_from(path)
	var img := _load_image(path)
	if img == null:
		clear()
		return "Nie można wczytać obrazu: " + path
	var iw := img.get_width()
	var ih := img.get_height()
	var side := sidecar_candidates(path)
	if not force:
		for c in side:
			if not FileAccess.file_exists(c):
				continue
			var d = JSON.parse_string(FileAccess.get_file_as_string(c))
			if typeof(d) == TYPE_DICTIONARY and d.has("regions") and d.get("image_size", []) == [iw, ih]:
				clear()
				sidecar_path = c
				var e := _load_data(d, c.get_base_dir(), img)
				if e == "":
					sheet_mode = str(d.get("mode", "sheet"))
				return e
	var res := AtlasSlicer.slice(img, opts)
	var regs: Dictionary = res["regions"]
	if str(res["mode"]) == "single":
		var base := path.get_file().get_basename()
		regs = {base: {"role": guess_role(path.get_file()), "rect": [0, 0, iw, ih]}}
	var data := {
		"image": path if (path.begins_with("res://") or path.begins_with("user://")) else path,
		"image_size": [iw, ih], "mode": res["mode"], "auto": true, "regions": regs, "template": bool(res.get("template", false)),
	}
	clear()
	for c in side:
		var fh := FileAccess.open(c, FileAccess.WRITE)
		if fh == null:
			DirAccess.make_dir_recursive_absolute(c.get_base_dir())
			fh = FileAccess.open(c, FileAccess.WRITE)
		if fh != null:
			fh.store_string(JSON.stringify(data, "\t"))
			fh.close()
			sidecar_path = c
			break
	var err := _load_data(data, path.get_base_dir(), img)
	if err == "":
		sheet_mode = str(res["mode"])
	return err


## Where the cut of an image is stored: next to it, or (when that folder is read-only) in a cache.
static func sidecar_candidates(image_path: String) -> Array[String]:
	var name := image_path.get_file().get_basename() + ".atlas.json"
	var beside := image_path.get_basename() + ".atlas.json"
	var list: Array[String] = [beside]
	list.append(CACHE_DIR.path_join(str(image_path.hash()) + "_" + name))
	return list


func _load_data(data: Dictionary, base_dir: String, preloaded: Image = null) -> String:
	var img_path := str(data["image"])
	if not (img_path.begins_with("res://") or img_path.begins_with("user://") or img_path.is_absolute_path()):
		img_path = base_dir.path_join(img_path)
	var img := preloaded if preloaded != null else _load_image(img_path)
	if img == null:
		return "Nie można wczytać obrazu atlasu: " + img_path
	sheet_path = img_path
	sheet_mode = "json"
	is_template = bool(data.get("template", false))
	var prev: Image = img.duplicate()
	prev.clear_mipmaps()
	if prev.is_compressed():
		prev.decompress()
	var pk := minf(1.0, 1400.0 / float(maxi(prev.get_width(), prev.get_height())))
	if pk < 1.0:
		prev.resize(int(prev.get_width() * pk), int(prev.get_height() * pk), Image.INTERPOLATE_BILINEAR)
	sheet_tex = ImageTexture.create_from_image(prev)
	source_width = float(img.get_width())
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var skipped := 0
	for key in data["regions"].keys():
		var d: Dictionary = data["regions"][key]
		var r: Array = d.get("rect", [])
		if r.size() != 4:
			skipped += 1
			continue
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		if rect.size.x < 2 or rect.size.y < 2 or not bounds.encloses(rect):
			skipped += 1
			continue
		var sub := img.get_region(rect)
		var role := str(d.get("role", "misc"))
		# Sheet panels: drop the outermost pixels. They are blended with the grey background (and with the
		# neighbouring panel) by GPT's resampling, which shows up as grey seams where a picture repeats or meets.
		if bool(data.get("template", false)) or str(data.get("mode", "")) == "sheet":
			var inset := maxi(4, roundi(float(img.get_width()) / 600.0))   # 4 px at ~1250 px, 7 px at 4096
			if sub.get_width() > 8 * inset and sub.get_height() > 8 * inset:
				sub = sub.get_region(Rect2i(inset, inset, sub.get_width() - 2 * inset, sub.get_height() - 2 * inset))
		if str(data.get("mode", "")) == "sheet" and role.begins_with("facade"):
			var span := _content_columns(sub)
			if span.y - span.x < sub.get_width() - 2:
				sub = sub.get_region(Rect2i(span.x, 0, span.y - span.x, sub.get_height()))
		var ratio := _roof_ratio(sub) if role == "facade_gable" else -1.0   # after the trim: the picture spans the wall
		sub.generate_mipmaps()
		regions[str(key)] = {
			"roof_ratio": ratio,
			"role": role,
			"rect": rect,
			"tex": ImageTexture.create_from_image(sub),
			"img": sub,
			"thumb": _make_thumb(sub),
			"source": "atlas",
			"aspect": float(sub.get_width()) / float(sub.get_height()),
		}
		if not by_role.has(role):
			by_role[role] = []
		by_role[role].append(str(key))
	for role in by_role.keys():
		by_role[role].sort()
	loaded = not regions.is_empty()
	if not loaded:
		return "Atlas nie zawiera poprawnych regionów (pominięto %d)." % skipped
	return ""


func _load_image(path: String) -> Image:
	# Project files (res://) go through the import system so this also works in exported builds;
	# files anywhere else on disk are read directly.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			var from_tex := tex.get_image()
			if from_tex != null and not from_tex.is_empty():
				return from_tex
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)   # not imported yet (e.g. just copied in)
	var img := Image.load_from_file(path)
	if img != null and not img.is_empty():
		return img
	return null


func has_role(role: String) -> bool:
	return by_role.has(role) and not by_role[role].is_empty()


## Picks one region of a role; `variant` wraps around, so callers can just increment it.
## Library photos without a clear role are "facade" and fit both long walls and gables.
func pick_key(role: String, variant: int) -> String:
	var keys: Array = keys_for_role(role)
	if keys.is_empty():
		return ""
	return str(keys[posmod(variant, keys.size())])


## Roof pitch seen in a gable photo: rise of the roof line divided by the width of the picture,
## or -1.0 when the picture is no gable (no background above the walls, e.g. a plain facade photo).
## The picture is a tight box around a gable on a plain background, so the top corners are background;
## the highest non-background pixel per column gives the roof outline: apex minus eaves = rise.
func estimate_roof_ratio(key: String) -> float:
	if not regions.has(key):
		return -1.0
	var cached: Variant = regions[key].get("roof_ratio")
	if cached != null:
		return float(cached)
	var r := _roof_ratio(regions[key]["img"])
	regions[key]["roof_ratio"] = r
	return r


## First and last column (x = first, y = one past the last) that hold real content in the lower
## 70% of a facade picture. A cut-out elevation sits on a plain background, and the bare margins left
## and right of the wall would otherwise be stretched over the model as black/white strips.
## Pictures whose top corners disagree (a plain photo, no background) are returned unchanged.
static func _content_columns(src: Image) -> Vector2i:
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var full := Vector2i(0, w)
	if w < 16 or h < 16:
		return full
	var c1 := Vector3.ZERO
	var c2 := Vector3.ZERO
	for yy in range(4):
		for xx in range(4):
			var a := img.get_pixel(xx, yy)
			var b := img.get_pixel(w - 1 - xx, yy)
			c1 += Vector3(a.r, a.g, a.b)
			c2 += Vector3(b.r, b.g, b.b)
	c1 /= 16.0
	c2 /= 16.0
	if c1.distance_to(c2) > 0.12:
		return full
	var bg := (c1 + c2) * 0.5
	var y0 := int(h * 0.3)
	var step := maxi(h / 120, 1)
	var first := -1
	var last := -1
	var samples := 0
	var yy0 := y0
	while yy0 < h:
		samples += 1
		yy0 += step
	for x in range(w):
		var hits := 0
		var y := y0
		while y < h:
			var px := img.get_pixel(x, y)
			if Vector3(px.r, px.g, px.b).distance_to(bg) > 0.16:
				hits += 1
			y += step
		if hits >= maxi(3, int(samples * 0.3)):   # a real column (wall, pipe), not a speck of the edge
			if first < 0:
				first = x
			last = x
	if first < 0:
		return full
	return Vector2i(first, last + 1)


static func _roof_ratio(src: Image) -> float:
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	var k := minf(1.0, 240.0 / float(maxi(img.get_width(), img.get_height())))
	if k < 1.0:
		img.resize(maxi(int(img.get_width() * k), 8), maxi(int(img.get_height() * k), 8), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	# background = mean of the two top corners (4x4 patches); both must agree
	var c1 := Vector3.ZERO
	var c2 := Vector3.ZERO
	for yy in range(4):
		for xx in range(4):
			var a := img.get_pixel(xx, yy)
			var b := img.get_pixel(w - 1 - xx, yy)
			c1 += Vector3(a.r, a.g, a.b)
			c2 += Vector3(b.r, b.g, b.b)
	c1 /= 16.0
	c2 /= 16.0
	if c1.distance_to(c2) > 0.12:
		return -1.0
	var bg := (c1 + c2) * 0.5
	var top := PackedInt32Array()
	top.resize(w)
	for x in range(w):
		top[x] = h
		var run := 0
		for y in range(h):
			var px := img.get_pixel(x, y)
			if Vector3(px.r, px.g, px.b).distance_to(bg) > 0.16:
				run += 1
				if run >= 3:
					top[x] = y - 2
					break
			else:
				run = 0
	# smooth the outline (median of 5) so drainpipes and specks do not count
	var sm := PackedInt32Array()
	sm.resize(w)
	for x in range(w):
		var v: Array = []
		for dx in range(-2, 3):
			v.append(top[clampi(x + dx, 0, w - 1)])
		v.sort()
		sm[x] = v[2]
	var apex := h
	for x in range(w):
		apex = mini(apex, sm[x])
	var edge := PackedInt32Array()
	var margin := maxi(int(w * 0.06), 2)
	for x in range(margin):
		edge.append(sm[x])
		edge.append(sm[w - 1 - x])
	edge.sort()
	var eave: int = edge[edge.size() / 2]
	var rise := float(eave - apex)
	if rise < 0.04 * w or eave >= h - 1:
		return -1.0
	return rise / float(w)


func get_texture(key: String) -> Texture2D:
	var r := region(key)
	return null if r.is_empty() else r["tex"]


func aspect(key: String) -> float:
	var r := region(key)
	return 1.0 if r.is_empty() else float(r["aspect"])


## A region of the atlas, or of a crop (see crop_key). {} for an unknown key.
func region(key: String) -> Dictionary:
	if regions.has(key):
		return regions[key]
	if key.begins_with("crop|"):
		return _crop_region(key)
	return {}


var _crops: Dictionary = {}


## Key of a piece cut out of a region: rect = [x, y, w, h] as fractions (0..1) of the region.
## The piece is its own small texture, so it can repeat over a whole surface (impossible with a
## sub-rectangle of one big atlas texture, which would also bleed into its neighbours).
func crop_key(region_key: String, rect: Array) -> String:
	return "crop|%s|%.4f,%.4f,%.4f,%.4f" % [region_key, rect[0], rect[1], rect[2], rect[3]]


func _crop_region(key: String) -> Dictionary:
	if _crops.has(key):
		return _crops[key]
	var bits := key.split("|")
	if bits.size() != 3 or not regions.has(bits[1]):
		return {}
	var f := bits[2].split(",")
	if f.size() != 4:
		return {}
	var src: Image = regions[bits[1]]["img"]
	var w := src.get_width()
	var h := src.get_height()
	var x0 := clampi(int(round(f[0].to_float() * w)), 0, w - 2)
	var y0 := clampi(int(round(f[1].to_float() * h)), 0, h - 2)
	var cw := clampi(int(round(f[2].to_float() * w)), 2, w - x0)
	var ch := clampi(int(round(f[3].to_float() * h)), 2, h - y0)
	var sub := src.get_region(Rect2i(x0, y0, cw, ch))
	sub.generate_mipmaps()
	var d := {"role": "crop", "tex": ImageTexture.create_from_image(sub), "img": sub, "aspect": float(cw) / float(ch), "source": "crop", "rect": Rect2i(x0, y0, cw, ch)}
	_crops[key] = d
	return d


## Photos carry no depth, so relief is faked from brightness: dark joints, cracks and gaps read as
## "low", bright faces as "high". The low-frequency part (soft shading / light gradient in the
## photo) is removed first, otherwise the whole wall would tilt instead of showing mortar and tiles.
##   detail   - size (in px at 512 px) of the largest feature that still counts as relief
##   smooth   - blur before the normals are taken (kills JPEG noise and film grain)
##   contrast - how much the brightness differences are pushed (before the strength is applied)
## Returns {"normal": ImageTexture, "height": ImageTexture} or {} for an unknown key.
func get_relief(key: String, strength: float, detail: float, smooth: float, invert: bool) -> Dictionary:
	var reg := region(key)
	if reg.is_empty():
		return {}
	var ck := "%s|%.3f|%.1f|%.1f|%s" % [key, strength, detail, smooth, invert]
	if relief_cache.has(ck):
		return relief_cache[ck]
	var res := _make_relief(reg["img"], strength, detail, smooth, invert)
	relief_cache[ck] = res
	return res


static func _make_relief(src: Image, strength: float, detail: float, smooth: float, invert: bool) -> Dictionary:
	var img: Image = src.duplicate()
	img.clear_mipmaps()
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(1.0, float(RELIEF_MAX_SIDE) / float(maxi(w, h)))
	if k < 1.0:
		w = maxi(2, int(w * k))
		h = maxi(2, int(h * k))
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_L8)
	var lum := img.get_data()

	# Low-pass copy = the soft shading to subtract.
	var low := Image.create_from_data(w, h, false, Image.FORMAT_L8, lum)
	var lw := maxi(2, int(w / maxf(detail, 2.0)))
	var lh := maxi(2, int(h / maxf(detail, 2.0)))
	low.resize(lw, lh, Image.INTERPOLATE_BILINEAR)
	low.resize(w, h, Image.INTERPOLATE_CUBIC)
	var lowd := low.get_data()

	var hd := PackedByteArray()
	hd.resize(w * h)
	var inv := -1.0 if invert else 1.0
	# Normalise by the spread so a dull and a contrasty photo give comparable relief.
	var sum2 := 0.0
	for i in range(w * h):
		var d := float(lum[i]) - float(lowd[i])
		sum2 += d * d
	var sigma := maxf(sqrt(sum2 / float(w * h)), 4.0)
	var gain := 48.0 / sigma
	for i in range(w * h):
		var d := (float(lum[i]) - float(lowd[i])) * gain * inv
		hd[i] = int(clampf(128.0 + d, 0.0, 255.0))
	var height := Image.create_from_data(w, h, false, Image.FORMAT_L8, hd)

	if smooth > 0.0:
		var sw := maxi(2, int(w / (1.0 + smooth)))
		var sh := maxi(2, int(h / (1.0 + smooth)))
		height.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
		height.resize(w, h, Image.INTERPOLATE_CUBIC)

	var bump := height.duplicate()
	bump.convert(Image.FORMAT_RGBA8)
	bump.bump_map_to_normal_map(maxf(strength, 0.0) * 6.0)
	bump.generate_mipmaps()
	height.generate_mipmaps()
	return {
		"normal": ImageTexture.create_from_image(bump),
		"height": ImageTexture.create_from_image(height),
	}


func keys_for_role(role: String) -> Array:
	if role == "facade_annex" and by_role.get("facade_annex", []).is_empty():
		return keys_for_role("facade_long")     # a sheet without annex sectors: annexes wear the long-wall pictures
	var keys: Array = (by_role.get(role, []) as Array).duplicate()
	if role == "facade_long" or role == "facade_gable":
		keys.append_array(by_role.get("facade", []))
	keys.sort()
	return keys


static func _make_thumb(img: Image) -> ImageTexture:
	var t: Image = img.duplicate()
	t.clear_mipmaps()
	if t.is_compressed():
		t.decompress()
	var k := minf(72.0 / float(t.get_width()), 48.0 / float(t.get_height()))
	t.resize(maxi(8, int(t.get_width() * k)), maxi(8, int(t.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(t)


const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const ROLE_WORDS := [
	["roof", ["roof", "dach", "dachow", "dachówk", "blacha", "papa"]],
	["facade_gable", ["gable", "szczyt"]],
	["facade_long", ["long", "front", "dlug", "długa"]],
	["door", ["door", "drzwi"]],
	["window", ["window", "okno", "okien"]],
	["chimney", ["chimney", "komin"]],
]


## Guesses what a photo is from its path ("roof/slate_03.jpg", "dach_papa.png", "szczyt_cegla.jpg").
## Anything unrecognised is a general "facade" photo.
static func guess_role(rel_path: String) -> String:
	var p := rel_path.to_lower()
	for entry in ROLE_WORDS:
		for w in entry[1]:
			if p.contains(str(w)):
				return str(entry[0])
	return "facade"


## Adds every photo found in `dir` (and one level of sub-folders) as a texture region named after
## the file. Returns how many were added. Photos are shrunk to `max_side` to keep memory sane.
func add_folder(dir: String, max_side := 2048) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var added := 0
	var files: Array = []
	_collect_images(dir, "", 0, files)
	files.sort()
	for rel in files:
		var path := dir.path_join(str(rel))
		var img := _load_image(path)
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var longest := maxi(img.get_width(), img.get_height())
		if longest > max_side:
			var k := float(max_side) / float(longest)
			img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
		if img.get_width() < 8 or img.get_height() < 8:
			continue
		var key := "foto/" + str(rel).get_basename().replace("\\", "/")
		if regions.has(key):
			continue
		var role := guess_role(str(rel))
		var sub: Image = img.duplicate()
		sub.generate_mipmaps()
		regions[key] = {
			"role": role,
			"rect": Rect2i(Vector2i.ZERO, img.get_size()),
			"tex": ImageTexture.create_from_image(sub),
			"img": img,
			"thumb": _make_thumb(img),
			"aspect": float(img.get_width()) / float(img.get_height()),
			"source": "library",
		}
		if not by_role.has(role):
			by_role[role] = []
		by_role[role].append(key)
		added += 1
	for role in by_role.keys():
		by_role[role].sort()
	loaded = not regions.is_empty()
	return added


## A picture made inside the program (e.g. a straightened photo): joins the regions under `key`.
## Role "extra" keeps it out of the automatic wall / roof assignment; faces can pick it by name.
func add_image_region(key: String, img: Image, source := "rectified") -> void:
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	im.clear_mipmaps()
	var sub: Image = im.duplicate()
	sub.generate_mipmaps()
	regions[key] = {
		"role": "extra",
		"rect": Rect2i(Vector2i.ZERO, im.get_size()),
		"tex": ImageTexture.create_from_image(sub),
		"img": im,
		"thumb": _make_thumb(im),
		"aspect": float(im.get_width()) / float(im.get_height()),
		"source": source,
	}
	if not by_role.has("extra"):
		by_role["extra"] = []
	if not (key in by_role["extra"]):
		by_role["extra"].append(key)
	loaded = true


func _collect_images(root: String, rel: String, depth: int, out: Array) -> void:
	var here := root.path_join(rel) if rel != "" else root
	var da := DirAccess.open(here)
	if da == null:
		return
	for f in da.get_files():
		if f.get_extension().to_lower() in IMAGE_EXTS:
			out.append(rel.path_join(f) if rel != "" else f)
	if depth < 2:
		for d in da.get_directories():
			if not d.begins_with(".") and not d.begins_with("_"):
				_collect_images(root, rel.path_join(d) if rel != "" else d, depth + 1, out)
