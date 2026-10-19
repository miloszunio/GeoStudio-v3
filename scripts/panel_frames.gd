class_name PanelFrames
extends RefCounted
## Finds the thin red rectangles (about 2 px, #FF0000) that ChatGPT draws around every texture picture of the sheet.
## The image is scanned on a grid with step 2 (a 2 px line is always hit); horizontal and vertical line segments are
## collected, and a rectangle is a top and a bottom segment of the same extent that are joined by red sides.
## Everything is returned in pixels of the scanned image: {"outer": Rect2i (the frame), "inner": Rect2i (inside it)}.

const STEP := 2
const MIN_SIDE := 120            # px: smaller rectangles are noise
const GAP := 1                   # samples: a line may be interrupted by this much (anti-aliasing)
const TOL := 4                   # samples: how far two edges of one rectangle may be apart
const COVER := 0.6               # share of a side that has to be red


static func is_red(r: int, g: int, b: int) -> bool:
	return r >= 170 and g <= 95 and b <= 95 and r - maxi(g, b) >= 105


static func detect(img: Image) -> Array:
	var work := img
	if work.is_compressed():
		work = img.duplicate()
		work.decompress()
	if work.get_format() != Image.FORMAT_RGB8:
		work = work.duplicate()
		work.convert(Image.FORMAT_RGB8)
	var W := work.get_width()
	var H := work.get_height()
	var w := W / STEP
	var h := H / STEP
	if w < 20 or h < 20:
		return []
	var data := work.get_data()
	var m := PackedByteArray()
	m.resize(w * h)
	var any := 0
	for y in range(h):
		var row := y * STEP * W * 3
		var o := y * w
		for x in range(w):
			var i := row + x * STEP * 3
			# a thin (resampled) line can fall between the grid samples: look at the pixel to the right and below too
			for k in range(3):
				var j := i
				if k == 1 and x * STEP + 1 < W:
					j = i + 3
				elif k == 2 and (y * STEP + 1) < H:
					j = i + W * 3
				elif k > 0:
					continue
				if data[j] >= 170 and data[j + 1] <= 95 and data[j + 2] <= 95 and int(data[j]) - maxi(data[j + 1], data[j + 2]) >= 105:
					m[o + x] = 1
					any += 1
					break
	if any < 40:
		return []
	var hs := _h_segments(m, w, h)
	var rects: Array = _pair(hs, m, w, h)
	# frames that share their edges (a grid of cells): cells between the long red lines
	for g in _grid_cells(m, w, h, hs):
		var gr: Rect2i = g
		var dup := false
		for f in rects:
			var fr: Rect2i = f
			if fr.intersects(gr):
				var ov := fr.intersection(gr)
				if float(ov.get_area()) / float(fr.get_area() + gr.get_area() - ov.get_area()) > 0.6:
					dup = true
					break
		if not dup:
			rects.append(gr)
	var keep: Array = []
	for a in rects:
		var inside := 0
		for b in rects:
			if (a as Rect2i) != (b as Rect2i) and (a as Rect2i).grow(2).encloses(b):
				inside += 1
		if inside < 2:
			keep.append(a)
	rects = keep
	var out: Array = []
	for r in rects:
		var rr: Rect2i = r
		var outer := Rect2i(rr.position.x * STEP, rr.position.y * STEP, rr.size.x * STEP, rr.size.y * STEP)
		var t := _thickness(work, outer)
		out.append({"outer": outer, "inner": outer.grow_individual(-(t[0] + 2), -(t[1] + 2), -(t[2] + 2), -(t[3] + 2))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2i = a["outer"]
		var rb: Rect2i = b["outer"]
		var rowa := int(ra.position.y / 300)
		var rowb := int(rb.position.y / 300)
		return ra.position.x < rb.position.x if rowa == rowb else rowa < rowb)
	return out


## Horizontal runs of red samples (length >= MIN_SIDE) as Vector3i(y, x0, x1); neighbouring rows are merged.
static func _h_segments(m: PackedByteArray, w: int, h: int) -> Array:
	var min_len := MIN_SIDE / STEP
	var segs: Array = []
	for y in range(h):
		var o := y * w
		var x := 0
		while x < w:
			if m[o + x] == 0:
				x += 1
				continue
			var x0 := x
			var last := x
			while x < w and (m[o + x] == 1 or (x - last) <= GAP):
				if m[o + x] == 1:
					last = x
				x += 1
			if last - x0 + 1 >= min_len:
				segs.append(Vector3i(y, x0, last))
	# merge segments of consecutive rows with the same extent (a thick line)
	var merged: Array = []
	for s in segs:
		var sv: Vector3i = s
		var done := false
		for k in range(merged.size() - 1, maxi(merged.size() - 40, -1), -1):
			var mv: Vector3i = merged[k]
			if absi(sv.y - mv.y) <= TOL and absi(sv.z - mv.z) <= TOL and sv.x - mv.x <= 3 and sv.x >= mv.x:
				done = true
				break
		if not done:
			merged.append(sv)
	return merged


## Rectangles bounded by long horizontal and vertical red lines, also when neighbours share a line.
## Only minimal ones (no other accepted rectangle inside).
static func _grid_cells(m: PackedByteArray, w: int, h: int, hs: Array) -> Array:
	var mt := PackedByteArray()
	mt.resize(w * h)
	for y in range(h):
		for x in range(w):
			mt[x * h + y] = m[y * w + x]
	var vs := _h_segments(mt, h, w)     # Vector3i(x, y0, y1)
	var ys := _cluster(hs.map(func(v: Vector3i) -> int: return v.x))
	var xs := _cluster(vs.map(func(v: Vector3i) -> int: return v.x))
	if xs.size() < 2 or ys.size() < 2 or xs.size() > 24 or ys.size() > 24:
		return []
	var min_side := MIN_SIDE / STEP
	var cand: Array = []
	for a in range(xs.size()):
		for b in range(a + 1, xs.size()):
			for c in range(ys.size()):
				for d in range(c + 1, ys.size()):
					var r := Rect2i(xs[a], ys[c], xs[b] - xs[a], ys[d] - ys[c])
					if r.size.x < min_side or r.size.y < min_side:
						continue
					if _cover_h(m, w, h, r.position.y, r.position.x, r.end.x) < 0.85 or _cover_h(m, w, h, r.end.y, r.position.x, r.end.x) < 0.85:
						continue
					if _cover_v(m, w, h, r.position.x, r.position.y, r.end.y) < 0.85 or _cover_v(m, w, h, r.end.x, r.position.y, r.end.y) < 0.85:
						continue
					cand.append(r)
	cand.sort_custom(func(p: Rect2i, q: Rect2i) -> bool: return p.get_area() < q.get_area())
	var out: Array = []
	for c in cand:
		var cr: Rect2i = c
		var contains := false
		for o in out:
			if cr.grow(2).encloses(o):
				contains = true
				break
		if not contains:
			out.append(cr)
	return out


static func _cluster(vals: Array) -> Array:
	var v := vals.duplicate()
	v.sort()
	var out: Array = []
	for x in v:
		if out.is_empty() or int(x) - int(out[out.size() - 1]) > TOL:
			out.append(int(x))
	return out


static func _cover_h(m: PackedByteArray, w: int, h: int, y: int, x0: int, x1: int) -> float:
	var n := 0
	for x in range(x0, x1 + 1):
		var hit := false
		for dy in range(-1, 2):
			var yy := y + dy
			if yy >= 0 and yy < h and m[yy * w + x] == 1:
				hit = true
				break
		if hit:
			n += 1
	return float(n) / float(maxi(x1 - x0 + 1, 1))


static func _cover_v(m: PackedByteArray, w: int, h: int, x: int, y0: int, y1: int) -> float:
	var n := 0
	for y in range(y0, y1 + 1):
		var hit := false
		for dx in range(-1, 2):
			var xx := x + dx
			if xx >= 0 and xx < w and m[y * w + xx] == 1:
				hit = true
				break
		if hit:
			n += 1
	return float(n) / float(maxi(y1 - y0 + 1, 1))


## Top/bottom pairs of the horizontal segments that are closed by red sides. Returns Rect2i in grid samples.
static func _pair(hs: Array, m: PackedByteArray, w: int, h: int) -> Array:
	var min_side := MIN_SIDE / STEP
	var found: Array = []
	for i in range(hs.size()):
		var top: Vector3i = hs[i]
		for j in range(hs.size()):
			var bot: Vector3i = hs[j]
			if bot.x < top.x + min_side:
				continue
			if absi(bot.y - top.y) > TOL or absi(bot.z - top.z) > TOL:
				continue
			var x0 := (top.y + bot.y) / 2
			var x1 := (top.z + bot.z) / 2
			var y0 := top.x
			var y1 := bot.x
			if _cover_v(m, w, h, x0, y0, y1) < COVER or _cover_v(m, w, h, x1, y0, y1) < COVER:
				continue
			if _cover_h(m, w, h, y0, x0, x1) < COVER or _cover_h(m, w, h, y1, x0, x1) < COVER:
				continue
			var r := Rect2i(x0, y0, x1 - x0, y1 - y0)
			var dup := false
			for k in range(found.size()):
				var f: Rect2i = found[k]
				if f.intersects(r):
					var ov := f.intersection(r)
					var iou := float(ov.get_area()) / float(f.get_area() + r.get_area() - ov.get_area())
					if iou > 0.7:
						dup = true
						# keep the smaller one (the inner edge of a thick frame)
						if r.get_area() < f.get_area():
							found[k] = r
						break
			if not dup:
				found.append(r)
	return found


## Thickness of the frame line on each side (left, top, right, bottom) in px, measured inwards from the outer edge.
static func _thickness(img: Image, outer: Rect2i) -> Array:
	var res := [3, 3, 3, 3]
	var W := img.get_width()
	var H := img.get_height()
	var cx := clampi(outer.position.x + outer.size.x / 2, 0, W - 1)
	var cy := clampi(outer.position.y + outer.size.y / 2, 0, H - 1)
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var starts := [Vector2i(outer.position.x, cy), Vector2i(cx, outer.position.y), Vector2i(outer.end.x - 1, cy), Vector2i(cx, outer.end.y - 1)]
	for s in range(4):
		var p: Vector2i = starts[s]
		var d: Vector2i = dirs[s]
		var best := 0
		# the line may sit a few px off the grid position: look for the first red pixel, then count the run
		var t := 0
		var started := false
		for k in range(-8, 14):
			var q := p + d * k
			if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H:
				continue
			var c := img.get_pixel(q.x, q.y)
			if is_red(int(c.r8), int(c.g8), int(c.b8)):
				started = true
				t += 1
			elif started:
				break
		best = maxi(t, 1)
		res[s] = best + maxi(0, 3 - best)
	return res
