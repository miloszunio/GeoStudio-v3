class_name TagSheet
extends RefCounted
## Import of a sheet drawn by ChatGPT where every picture sits in a flat colour frame (the "tag").
## The colour tells WHICH picture it is (S1 red, S2 green ...), the frame tells WHERE it is and how big. ChatGPT may
## put the pictures anywhere on the canvas, in any order and size: the program cuts each one out along its frame,
## brings it to the real width of the wall and lays it into the computed layout (SheetLayout). The result is an
## ordinary sheet that the slicer cuts as before.

const TAGS := {
	"S1": Color8(255, 0, 0), "S2": Color8(0, 255, 0), "S3": Color8(0, 0, 255), "S4": Color8(255, 255, 0),
	"S5": Color8(255, 0, 255), "S6": Color8(0, 255, 255), "S7": Color8(255, 128, 0), "S8": Color8(128, 0, 255),
}
const TAG_NAMES := {
	"S1": "czerwona #FF0000", "S2": "zielona #00FF00", "S3": "niebieska #0000FF", "S4": "żółta #FFFF00",
	"S5": "magenta #FF00FF", "S6": "cyjan #00FFFF", "S7": "pomarańczowa #FF8000", "S8": "fioletowa #8000FF",
}
const DETECT_SIZE := 1024
const MIN_FRAME_PX := 24        # smallest frame side at detection scale


## Level of one channel: 0 low, 1 middle, 2 high, 3 in between (not a tag colour).
static func _lvl(v: int) -> int:
	if v < 80:
		return 0
	if v > 175:
		return 2
	if v >= 100 and v <= 156:
		return 1
	return 3


static func _key(r: int, g: int, b: int) -> int:
	return _lvl(r) * 16 + _lvl(g) * 4 + _lvl(b)


static func _key_of_color(c: Color) -> int:
	return _key(int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0)))


## Frames found in the image: {code: {"outer": Rect2i, "inner": Rect2i}} in pixels of `img`.
static func find_frames(img: Image) -> Dictionary:
	var out := {}
	var work := img.duplicate() as Image
	if work.is_compressed():
		work.decompress()
	work.convert(Image.FORMAT_RGB8)
	var f := 1.0
	var big := maxi(work.get_width(), work.get_height())
	if big > DETECT_SIZE:
		f = float(big) / float(DETECT_SIZE)
		work.resize(int(round(work.get_width() / f)), int(round(work.get_height() / f)), Image.INTERPOLATE_BILINEAR)
	var w := work.get_width()
	var h := work.get_height()
	var data := work.get_data()
	var codes: Array = TAGS.keys()
	var n := codes.size()
	var cols := PackedInt32Array()
	cols.resize(n * w)
	var rows := PackedInt32Array()
	rows.resize(n * h)
	var idx_of := {}
	for ci in range(n):
		idx_of[_key_of_color(TAGS[codes[ci]])] = ci
	var i := 0
	for y in range(h):
		for x in range(w):
			var r := data[i]
			var g := data[i + 1]
			var b := data[i + 2]
			i += 3
			# quick reject: grey and dull pixels carry no tag
			if maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 120:
				continue
			var ci: int = idx_of.get(_key(r, g, b), -1)
			if ci >= 0:
				cols[ci * w + x] += 1
				rows[ci * h + y] += 1
	for ci in range(n):
		var code: String = codes[ci]
		var cc: PackedInt32Array = cols.slice(ci * w, (ci + 1) * w)
		var rr: PackedInt32Array = rows.slice(ci * h, (ci + 1) * h)
		var cmax := 0
		for v in cc:
			cmax = maxi(cmax, v)
		var rmax := 0
		for v in rr:
			rmax = maxi(rmax, v)
		if cmax < MIN_FRAME_PX or rmax < MIN_FRAME_PX:
			continue
		var cthr := maxi(int(cmax * 0.4), MIN_FRAME_PX / 2)
		var rthr := maxi(int(rmax * 0.4), MIN_FRAME_PX / 2)
		var x0 := -1
		var x1 := -1
		for x in range(w):
			if cc[x] >= cthr:
				if x0 < 0:
					x0 = x
				x1 = x
		var y0 := -1
		var y1 := -1
		for y in range(h):
			if rr[y] >= rthr:
				if y0 < 0:
					y0 = y
				y1 = y
		if x0 < 0 or y0 < 0 or x1 - x0 < MIN_FRAME_PX or y1 - y0 < MIN_FRAME_PX:
			continue
		# thickness of the frame on each side (consecutive busy columns / rows)
		var tl := 0
		while x0 + tl <= x1 and cc[x0 + tl] >= cthr:
			tl += 1
		var tr := 0
		while x1 - tr >= x0 and cc[x1 - tr] >= cthr:
			tr += 1
		var tt := 0
		while y0 + tt <= y1 and rr[y0 + tt] >= rthr:
			tt += 1
		var tb := 0
		while y1 - tb >= y0 and rr[y1 - tb] >= rthr:
			tb += 1
		# a frame is a thin line: when the "line" is as thick as half the box it was a filled area, not a frame
		if tl * 2 >= x1 - x0 or tt * 2 >= y1 - y0:
			continue
		var margin := 2    # anti-aliased edge of the line, in full-size pixels
		var ox0 := int(floor(x0 * f))
		var oy0 := int(floor(y0 * f))
		var ox1 := int(ceil((x1 + 1) * f))
		var oy1 := int(ceil((y1 + 1) * f))
		var ix0 := int(ceil((x0 + tl) * f)) + margin
		var iy0 := int(ceil((y0 + tt) * f)) + margin
		var ix1 := int(floor((x1 + 1 - tr) * f)) - margin
		var iy1 := int(floor((y1 + 1 - tb) * f)) - margin
		ix1 = mini(ix1, img.get_width())
		iy1 = mini(iy1, img.get_height())
		if ix1 - ix0 < 8 or iy1 - iy0 < 8:
			continue
		out[code] = {"outer": Rect2i(ox0, oy0, ox1 - ox0, oy1 - oy0), "inner": Rect2i(ix0, iy0, ix1 - ix0, iy1 - iy0)}
	return out


## Lays the framed pictures into the layout. Returns {"image": Image, "found": [codes], "missing": [codes], "notes": [text]}
## or {} when the image carries no tags at all.
static func assemble(img: Image, layout: Dictionary) -> Dictionary:
	if layout.is_empty():
		return {}
	var frames := find_frames(img)
	if frames.is_empty():
		return {}
	var size := int(layout["canvas"])
	var sheet := Image.create(size, size, false, Image.FORMAT_RGB8)
	sheet.fill(SheetLayout.BG)
	var src := img.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGB8)
	var found: Array = []
	var missing: Array = []
	var notes: Array = []
	var codes: Array = (layout["pictures"] as Dictionary).keys()
	codes.sort()
	for code in codes:
		if not frames.has(code):
			missing.append(code)
			continue
		var pic: Array = layout["pictures"][code]
		var pw := int(pic[2])
		var ph := int(pic[3])
		var crop := src.get_region(frames[code]["inner"])
		var kind := str(layout["kinds"].get(code, "wall"))
		var tw := pw
		var th := ph
		if kind == "wall":
			th = clampi(int(round(float(pw) * float(crop.get_height()) / float(maxi(crop.get_width(), 1)))), 8, ph)
			var natural := float(pw) * float(crop.get_height()) / float(maxi(crop.get_width(), 1))
			if natural > ph * 1.08:
				notes.append("%s: obraz wyższy niż przewiduje ewidencja, ściśnięty o %d%%" % [code, int(round((1.0 - float(ph) / natural) * 100.0))])
		crop.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(crop, Rect2i(0, 0, tw, th), Vector2i(int(pic[0]), int(pic[1])))
		found.append(code)
	return {"image": sheet, "found": found, "missing": missing, "notes": notes}


## Loads `path`; when it carries tag frames, writes the assembled sheet next to it and returns its path.
## Returns {"path": String (assembled sheet) or "", "found": [...], "missing": [...], "notes": [...]}.
static func normalize(path: String, layout: Dictionary) -> Dictionary:
	var res := {"path": "", "found": [], "missing": [], "notes": []}
	if layout.is_empty() or not FileAccess.file_exists(path):
		return res
	var ext := path.get_extension().to_lower()
	if not ext in ["png", "jpg", "jpeg", "webp"]:
		return res
	var out_path := path.get_basename() + "_arkusz.png"
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return res
	var a := assemble(img, layout)
	if a.is_empty():
		return res
	if (a["image"] as Image).save_png(out_path) != OK:
		return res
	res["path"] = out_path
	res["found"] = a["found"]
	res["missing"] = a["missing"]
	res["notes"] = a["notes"]
	return res
