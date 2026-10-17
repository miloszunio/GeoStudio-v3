class_name AtlasSlicer
extends RefCounted
## Cuts a texture sheet (many panels on a plain background: facades, roof, doors, windows ...) into
## separate regions, and guesses what each region is. A single photo is kept whole.
## Works on a shrunken copy, so a 4000 px sheet takes well under a second.

const ANALYSIS_SIDE := 800     # the sheet is shrunk to this before analysis
const CELL := 2                # coarse grid cell (analysis px) used for the flood fill

## Fixed template: the sheet is 2 columns x 4 rows of equal sectors, one element each.
## S1/S2 long walls, S3/S4 gables, S5 roof, S6..S8 walls of annexes (or empty).
const TEMPLATE_COLS := 2
const TEMPLATE_ROWS := 4
const TEMPLATE_ROLES := ["facade_long", "facade_long", "facade_gable", "facade_gable", "roof", "facade_annex", "facade_annex", "facade_annex"]


## opts: sensitivity (colour distance from the background that counts as "content", 0..1),
##       min_area (percent of the sheet below which blobs are ignored), gap (px at analysis size
##       (640 px) that still joins neighbouring blobs; 2 = only touching panels join), mode ("auto" | "sheet" | "single")
## mode "template" (or "auto" on a square sheet whose panels sit neatly inside the 2 x 4 sectors) names
## the regions S1..S8 and gives them roles by position.
## Returns {"mode": "sheet"|"single", "template": bool, "regions": {key: {"role", "rect": [x,y,w,h]}}, "background": Color}
static func slice(src: Image, opts: Dictionary) -> Dictionary:
	var mode := str(opts.get("mode", "auto"))
	var full_w := src.get_width()
	var full_h := src.get_height()
	if mode == "single":
		return _single(src)

	var img: Image = src.duplicate()
	img.clear_mipmaps()
	if img.is_compressed():
		img.decompress()
	var k := minf(1.0, float(ANALYSIS_SIDE) / float(maxi(full_w, full_h)))
	var w := maxi(8, int(full_w * k))
	var h := maxi(8, int(full_h * k))
	if k < 1.0:
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var px := img.get_data()

	var bg := _background(px, w, h)
	var sens := clampf(float(opts.get("sensitivity", 0.06)), 0.01, 0.8) * 255.0
	var mask := PackedByteArray()
	mask.resize(w * h)
	var fg_count := 0
	for i in range(w * h):
		var o := i * 3
		var d := maxf(maxf(absf(px[o] - bg.x), absf(px[o + 1] - bg.y)), absf(px[o + 2] - bg.z))
		if d > sens:
			mask[i] = 1
			fg_count += 1
	var fg_frac := float(fg_count) / float(w * h)
	if mode == "auto" and fg_frac > 0.92:
		return _single(src)      # no background to speak of: a plain photo

	# Coarse grid: a cell is "content" when at least half of its pixels are (stray noise pixels in
	# the gaps between panels therefore do not bridge them).
	var gw := ceili(float(w) / CELL)
	var gh := ceili(float(h) / CELL)
	var grid := PackedByteArray()
	grid.resize(gw * gh)
	for gy in range(gh):
		for gx in range(gw):
			var n := 0
			for yy in range(gy * CELL, mini(gy * CELL + CELL, h)):
				for xx in range(gx * CELL, mini(gx * CELL + CELL, w)):
					n += mask[yy * w + xx]
			if n >= CELL * CELL / 2:
				grid[gy * gw + gx] = 1
	var gap_cells := maxi(0, int(float(opts.get("gap", 2)) / CELL / 2.0))
	var joined := _dilate(grid, gw, gh, gap_cells)

	# Connected components of the joined grid.
	var label := PackedInt32Array()
	label.resize(gw * gh)
	var comps: Array = []
	for start in range(gw * gh):
		if joined[start] == 0 or label[start] != 0:
			continue
		var id := comps.size() + 1
		var stack: Array[int] = [start]
		label[start] = id
		var cells: Array[int] = []
		while not stack.is_empty():
			var c: int = stack.pop_back()
			cells.append(c)
			var cx := c % gw
			var cy := c / gw
			for nb in [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]:
				if nb[0] < 0 or nb[1] < 0 or nb[0] >= gw or nb[1] >= gh:
					continue
				var ni: int = nb[1] * gw + nb[0]
				if joined[ni] == 1 and label[ni] == 0:
					label[ni] = id
					stack.append(ni)
		comps.append(cells)

	# Tight boxes from the real mask, plus colour statistics for the role guess.
	var min_area := float(opts.get("min_area", 0.15)) * 0.01 * w * h
	var boxes: Array = []
	for cells in comps:
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		var sum_s := 0.0
		var sum_v := 0.0
		var sum_h := 0.0
		var samples := 0
		var filled := 0
		for c in cells:
			var gx: int = c % gw
			var gy: int = c / gw
			for yy in range(gy * CELL, mini(gy * CELL + CELL, h)):
				for xx in range(gx * CELL, mini(gx * CELL + CELL, w)):
					var i := yy * w + xx
					if mask[i] == 0:
						continue
					filled += 1
					x0 = mini(x0, xx)
					y0 = mini(y0, yy)
					x1 = maxi(x1, xx)
					y1 = maxi(y1, yy)
					if (xx + yy) % 3 == 0:
						var col := Color8(px[i * 3], px[i * 3 + 1], px[i * 3 + 2])
						sum_s += col.s
						sum_v += col.v
						sum_h += col.h
						samples += 1
		if x1 < 0:
			continue
		var bw := x1 - x0 + 1
		var bh := y1 - y0 + 1
		if float(bw * bh) < min_area or bw < 6 or bh < 6:
			continue
		boxes.append({
			"r": Rect2i(x0, y0, bw, bh), "fill": float(filled) / float(bw * bh),
			"s": sum_s / maxf(samples, 1.0), "v": sum_v / maxf(samples, 1.0), "h": sum_h / maxf(samples, 1.0),
		})

	# Panels that only touch (a roof tip against the wall above it, a plinth against the next picture)
	# were flood-filled into one blob: cut them apart along empty rows / columns.
	boxes = _split_boxes(boxes, mask, px, w, h)

	# Drop specks that sit inside a much bigger box (a caption next to a panel).
	var keep: Array = []
	for i in range(boxes.size()):
		var inside := false
		for j in range(boxes.size()):
			if i != j and boxes[j]["r"].encloses(boxes[i]["r"]) and float(boxes[i]["r"].get_area()) < 0.03 * float(boxes[j]["r"].get_area()):
				inside = true
				break
		if not inside:
			keep.append(boxes[i])
	if keep.is_empty():
		return _single(src)
	if mode == "auto" and keep.size() == 1 and float(keep[0]["r"].get_area()) > 0.6 * w * h:
		return _single(src)      # one big blob: a photo, not a sheet

	# Template: first the layout computed for this building (frames of true proportions), then the fixed 2 x 4 grid.
	var square := absf(float(full_w) / float(full_h) - 1.0) < 0.03
	if mode == "template" or (mode == "auto" and square):
		var candidates: Array = []
		var lay_defs := _layout_defs(opts.get("layout", {}))
		if not lay_defs.is_empty():
			candidates.append(lay_defs)
		candidates.append(_fixed_defs())
		var chosen: Array = []
		for defs in candidates:
			if fits_template(keep, w, h, defs):
				chosen = defs
				break
		if chosen.is_empty() and mode == "template":
			chosen = candidates[0]      # forced: use the first one even if the panels do not sit neatly in it
		if not chosen.is_empty():
			var tr := _template_regions(keep, w, h, full_w, full_h, 1.0 / k, chosen)
			if not tr.is_empty():
				return {"mode": "sheet", "template": true, "regions": tr, "background": Color8(int(bg.x), int(bg.y), int(bg.z))}

	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(a["r"].position.y / (0.1 * h))
		var rb := int(b["r"].position.y / (0.1 * h))
		return ra < rb if ra != rb else a["r"].position.x < b["r"].position.x)

	var roles: Array = []
	for b in keep:
		roles.append(_guess_role(b["r"], b["s"], b["v"], b["h"], b["fill"], w, h))
	_split_long_and_gable(keep, roles)

	var regions: Dictionary = {}
	var counters: Dictionary = {}
	for bi in range(keep.size()):
		var b: Dictionary = keep[bi]
		var r: Rect2i = b["r"]
		var role: String = roles[bi]
		counters[role] = int(counters.get(role, 0)) + 1
		var key := "%s_%d" % [role, counters[role]]
		var scale := 1.0 / k
		var pad := 1
		var fx := maxi(0, int(floor(r.position.x * scale)) - pad)
		var fy := maxi(0, int(floor(r.position.y * scale)) - pad)
		var fe := mini(full_w, int(ceil(r.end.x * scale)) + pad)
		var fb := mini(full_h, int(ceil(r.end.y * scale)) + pad)
		regions[key] = {"role": role, "rect": [fx, fy, fe - fx, fb - fy]}
	return {"mode": "sheet", "regions": regions, "background": Color8(int(bg.x), int(bg.y), int(bg.z))}


## Sector definitions: [{code, role, rect (normalised 0..1)}]. The fixed 2 x 4 grid ...
static func _fixed_defs() -> Array:
	var defs: Array = []
	for s in range(TEMPLATE_COLS * TEMPLATE_ROWS):
		defs.append({"code": "S%d" % (s + 1), "role": TEMPLATE_ROLES[s],
			"rect": Rect2(float(s % TEMPLATE_COLS) / TEMPLATE_COLS, float(s / TEMPLATE_COLS) / TEMPLATE_ROWS, 1.0 / TEMPLATE_COLS, 1.0 / TEMPLATE_ROWS)})
	return defs


## ... or the frames of a SheetLayout (stored as JSON-compatible data).
static func _layout_defs(layout) -> Array:
	var defs: Array = []
	if typeof(layout) != TYPE_DICTIONARY or not layout.has("frames"):
		return defs
	var c := float(layout.get("canvas", 0))
	if c <= 0.0:
		return defs
	for code in layout["frames"].keys():
		var f: Array = layout["frames"][code]
		defs.append({"code": str(code), "role": SheetLayout.role_of(str(code)), "rect": Rect2(float(f[0]) / c, float(f[1]) / c, float(f[2]) / c, float(f[3]) / c)})
	return defs


## Index of the definition that holds the point (analysis pixels); the nearest one when none does.
static func _def_of(p: Vector2, defs: Array, w: int, h: int) -> int:
	var n := Vector2(p.x / float(w), p.y / float(h))
	var best := -1
	var best_d := 1e9
	for i in range(defs.size()):
		var r: Rect2 = defs[i]["rect"]
		if r.has_point(n):
			return i
		var d := n.distance_to(r.get_center())
		if d < best_d:
			best_d = d
			best = i
	return best


## XY-cut: a box is cut wherever a run of (nearly) empty rows - or columns - separates two stretches of content,
## both at least `MIN_PART` of the box. Boxes are re-measured from the mask afterwards.
const CUT_EMPTY := 0.015      # a row / column with less content than this share counts as empty
const MIN_PART := 0.12


static func _split_boxes(boxes: Array, mask: PackedByteArray, px: PackedByteArray, w: int, h: int) -> Array:
	var out: Array = []
	for b in boxes:
		for r in _cut_rect(b["r"], mask, w, h, 0):
			out.append(_measure_box(r, mask, px, w, h) if r != b["r"] else b)
	return out


static func _cut_rect(r: Rect2i, mask: PackedByteArray, w: int, h: int, depth: int) -> Array:
	if depth > 4 or r.size.x < 20 or r.size.y < 20:
		return [r]
	for axis in [1, 0]:     # rows first (stacked panels), then columns
		var n: int = r.size.y if axis == 1 else r.size.x
		var span: int = r.size.x if axis == 1 else r.size.y
		var prof := PackedInt32Array()
		prof.resize(n)
		for i in range(n):
			var c := 0
			if axis == 1:
				var y := r.position.y + i
				for x in range(r.position.x, r.position.x + r.size.x):
					c += mask[y * w + x]
			else:
				var xx := r.position.x + i
				for y in range(r.position.y, r.position.y + r.size.y):
					c += mask[y * w + xx]
			prof[i] = c
		var thr := maxi(1, int(CUT_EMPTY * span))
		var min_part := maxi(6, int(MIN_PART * n))
		# runs of content
		var runs: Array = []
		var start := -1
		for i in range(n + 1):
			var full := i < n and prof[i] > thr
			if full and start < 0:
				start = i
			elif not full and start >= 0:
				runs.append([start, i])
				start = -1
		var big: Array = []
		for run in runs:
			if run[1] - run[0] >= min_part:
				big.append(run)
		if big.size() >= 2:
			var parts: Array = []
			for k in range(big.size()):
				var lo: int = int(big[k][0]) if k > 0 else 0
				var hi: int = int(big[k][1]) if k < big.size() - 1 else n
				var sub := Rect2i(r.position.x, r.position.y + lo, r.size.x, hi - lo) if axis == 1 else Rect2i(r.position.x + lo, r.position.y, hi - lo, r.size.y)
				parts.append_array(_cut_rect(sub, mask, w, h, depth + 1))
			return parts
	return [r]


## Tight box and colour statistics of the mask inside r (same record as the flood-fill boxes).
static func _measure_box(r: Rect2i, mask: PackedByteArray, px: PackedByteArray, w: int, h: int) -> Dictionary:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	var filled := 0
	var sum_s := 0.0
	var sum_v := 0.0
	var sum_h := 0.0
	var samples := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var i := y * w + x
			if mask[i] == 0:
				continue
			filled += 1
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			if (x + y) % 3 == 0:
				var col := Color8(px[i * 3], px[i * 3 + 1], px[i * 3 + 2])
				sum_s += col.s
				sum_v += col.v
				sum_h += col.h
				samples += 1
	if x1 < 0:
		return {"r": Rect2i(r.position, Vector2i(1, 1)), "fill": 0.0, "s": 0.0, "v": 0.0, "h": 0.0}
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	return {"r": Rect2i(x0, y0, bw, bh), "fill": float(filled) / float(bw * bh), "s": sum_s / maxf(samples, 1.0), "v": sum_v / maxf(samples, 1.0), "h": sum_h / maxf(samples, 1.0)}


## True when every panel lies inside one sector (small tolerance) and at least two sectors are used.
static func fits_template(boxes: Array, w: int, h: int, defs: Array = []) -> bool:
	if defs.is_empty():
		defs = _fixed_defs()
	var used := {}
	var tol := 0.02
	for b in boxes:
		var r: Rect2i = b["r"]
		var s := _def_of(Vector2(r.get_center()), defs, w, h)
		var sec: Rect2 = (defs[s]["rect"] as Rect2).grow(tol)
		var nr := Rect2(float(r.position.x) / w, float(r.position.y) / h, float(r.size.x) / w, float(r.size.y) / h)
		if not sec.encloses(nr):
			return false
		used[s] = true
	return used.size() >= 2


## One region per used sector: the union of the panels inside it, shrunk a hair so no background shows.
static func _template_regions(boxes: Array, w: int, h: int, full_w: int, full_h: int, scale: float, defs: Array = []) -> Dictionary:
	if defs.is_empty():
		defs = _fixed_defs()
	var union := {}
	for b in boxes:
		var r: Rect2i = b["r"]
		var s := _def_of(Vector2(r.get_center()), defs, w, h)
		union[s] = (union[s] as Rect2i).merge(r) if union.has(s) else r
	var regions := {}
	var inset := int(ceil(scale))
	for s in union.keys():
		var r: Rect2i = union[s]
		var fx := int(floor(r.position.x * scale)) + inset
		var fy := int(floor(r.position.y * scale)) + inset
		var fe := mini(full_w, int(ceil(r.end.x * scale))) - inset
		var fb := mini(full_h, int(ceil(r.end.y * scale))) - inset
		if fe - fx < 8 or fb - fy < 8:
			continue
		var code := str(defs[int(s)]["code"])
		regions[code] = {"role": str(defs[int(s)]["role"]), "rect": [fx, fy, fe - fx, fb - fy], "sector": int(code.substr(1))}
	return regions


static func _single(src: Image) -> Dictionary:
	return {
		"mode": "single",
		"regions": {"foto": {"role": "facade", "rect": [0, 0, src.get_width(), src.get_height()]}},
		"background": Color.BLACK,
	}


## Most common colour along the border of the sheet.
static func _background(px: PackedByteArray, w: int, h: int) -> Vector3:
	var bins: Dictionary = {}
	var add := func(x: int, y: int) -> void:
		var o := (y * w + x) * 3
		var key := (px[o] >> 4) << 8 | (px[o + 1] >> 4) << 4 | (px[o + 2] >> 4)
		var e: Array = bins.get(key, [0, 0.0, 0.0, 0.0])
		e[0] += 1
		e[1] += px[o]
		e[2] += px[o + 1]
		e[3] += px[o + 2]
		bins[key] = e
	for x in range(w):
		add.call(x, 0)
		add.call(x, h - 1)
	for y in range(h):
		add.call(0, y)
		add.call(w - 1, y)
	var best: Array = [0, 0.0, 0.0, 0.0]
	for key in bins.keys():
		if bins[key][0] > best[0]:
			best = bins[key]
	var n := maxf(best[0], 1.0)
	return Vector3(best[1] / n, best[2] / n, best[3] / n)


static func _dilate(grid: PackedByteArray, gw: int, gh: int, r: int) -> PackedByteArray:
	if r <= 0:
		return grid
	var tmp := PackedByteArray()
	tmp.resize(gw * gh)
	for y in range(gh):
		for x in range(gw):
			if grid[y * gw + x] == 1:
				for xx in range(maxi(0, x - r), mini(gw, x + r + 1)):
					tmp[y * gw + xx] = 1
	var out := PackedByteArray()
	out.resize(gw * gh)
	for y in range(gh):
		for x in range(gw):
			if tmp[y * gw + x] == 1:
				for yy in range(maxi(0, y - r), mini(gh, y + r + 1)):
					out[yy * gw + x] = 1
	return out


## Geometry + colour guess. Deliberately simple: users can correct roles in the generated JSON.
static func _guess_role(r: Rect2i, sat: float, val: float, hue: float, fill: float, w: int, h: int) -> String:
	var area := float(r.get_area()) / float(w * h)
	var aspect := float(r.size.x) / float(r.size.y)
	var hfrac := float(r.size.y) / float(h)
	if aspect > 3.5 or aspect < 0.22:
		return "drainpipe" if sat > 0.25 else "roof_trim"
	if fill < 0.3:
		return "drainpipe" if sat > 0.25 else "misc"      # thin L-shaped things (pipes, rails)
	if area >= 0.06:
		if sat < 0.2 and val < 0.45:
			return "roof"                       # big, dark, grey: slate / felt
		if fill < 0.6:
			return "misc"                       # a cluster of small parts, not one elevation
		return "facade_long" if aspect >= 1.3 else "facade_gable"
	if aspect >= 0.28 and aspect <= 0.85 and hfrac >= 0.12:
		return "door" if hfrac >= 0.185 else "window"
	if area >= 0.025:
		return "roof" if (sat < 0.2 and val < 0.45) else "eave"
	if sat > 0.45 and (hue < 0.07 or hue > 0.95) and aspect < 1.3:
		return "chimney"
	return "misc"


## Long walls and gables cannot be told apart by aspect alone (a block's long wall can be square).
## Among the big elevation panels the wide ones are long walls and the narrow ones gables: the split
## goes where the widths drop the most (at least 1.25x).
static func _split_long_and_gable(boxes: Array, roles: Array) -> void:
	var idx: Array = []
	for i in range(roles.size()):
		if roles[i] == "facade_long" or roles[i] == "facade_gable":
			idx.append(i)
	if idx.size() < 2:
		return
	idx.sort_custom(func(a: int, b: int) -> bool: return boxes[a]["r"].size.x > boxes[b]["r"].size.x)
	var best_ratio := 1.0
	var best_at := -1
	for k in range(idx.size() - 1):
		var ratio := float(boxes[idx[k]]["r"].size.x) / float(boxes[idx[k + 1]]["r"].size.x)
		if ratio > best_ratio:
			best_ratio = ratio
			best_at = k
	if best_ratio < 1.25:
		return
	for k in range(idx.size()):
		roles[idx[k]] = "facade_long" if k <= best_at else "facade_gable"
