class_name RoofGen
extends RefCounted
## Roof generated from a drawn profile (the "Dach" window).
##
## A roof description is {"part": int, "prof": [[x, y], ...], "ra": m, "rb": m}:
##   prof  profile across the building as seen on the gable picture: x = metres from the LEFT edge of the picture
##         (0 .. span), y = metres above the eaves. The first and the last vertex sit on the walls (y = 0); the ones
##         in between are the corners of the roof (ridge, the break of a mansard ...).
##   ra/rb how far (m) the ridge stops short of the start / end gable: 0 = a gable wall, > 0 = a hipped end.
##         Hips are made only for a roof with one ridge.
## The roof surface is the lower envelope of planes y = a*x + b*z + c (a convex roof). Every plane is one
## facet of the roof; the walls under the roof follow the same envelope.

const MAX_VERTS := 7
const MIN_H := 0.05


static func default_profile(span: float, roof_h: float, apex_x := -1.0) -> Array:
	var ax := span * 0.5 if apex_x < 0.0 else clampf(apex_x, 0.1, span - 0.1)
	return [[0.0, 0.0], [ax, maxf(roof_h, MIN_H)], [span, 0.0]]


## Clean description: sorted, ends on the walls, heights positive, limited number of vertices.
static func normalize(gen: Dictionary, span: float) -> Dictionary:
	var prof: Array = []
	for v in gen.get("prof", []):
		if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
			prof.append([clampf(float(v[0]), 0.0, span), maxf(float(v[1]), 0.0)])
	if prof.size() < 3:
		prof = default_profile(span, 3.0)
	prof.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	prof[0] = [0.0, 0.0]
	prof[prof.size() - 1] = [span, 0.0]
	var out: Array = [prof[0]]
	for i in range(1, prof.size() - 1):
		var v: Array = prof[i]
		if float(v[0]) - float((out[out.size() - 1] as Array)[0]) < 0.05 or span - float(v[0]) < 0.05:
			continue      # two vertices on top of each other
		out.append([float(v[0]), maxf(float(v[1]), MIN_H)])
		if out.size() >= MAX_VERTS - 1:
			break
	out.append(prof[prof.size() - 1])
	if out.size() < 3:
		out = default_profile(span, 3.0)
	return {"part": int(gen.get("part", 0)), "prof": out, "ra": maxf(float(gen.get("ra", 0.0)), 0.0), "rb": maxf(float(gen.get("rb", 0.0)), 0.0)}


## True when the profile has a single ridge (hips are possible).
static func single_ridge(prof: Array) -> bool:
	return prof.size() == 3


static func ridge_height(prof: Array) -> float:
	var h := 0.0
	for v in prof:
		h = maxf(h, float((v as Array)[1]))
	return h


## Planes of the roof: [{"a","b","c","label","end": bool}] with y = a*x + b*z + c in the part's plan coordinates.
## along_x: the ridge runs along X; s_lo/s_hi: extent of the building along the ridge; ridge_mid: ridge coordinate across.
static func planes(gen: Dictionary, span: float, left_is_pos: bool, ridge_mid: float, along_x: bool, wall_h: float, s_lo: float, s_hi: float) -> Array:
	var g := normalize(gen, span)
	var prof: Array = g["prof"]
	var half := span * 0.5
	var sgn := -1.0 if left_is_pos else 1.0
	var out: Array = []
	var a_side := ["A", "C", "E", "G"]
	var b_side := ["B", "D", "F", "H"]
	var na := 0
	var nb := 0
	# eave -> ridge order inside each side: segments on the left of the picture go up, on the right come down
	var order: Array = []
	for k in range(prof.size() - 1):
		order.append(k)
	for k in order:
		var p0: Array = prof[k]
		var p1: Array = prof[k + 1]
		var dx := float(p1[0]) - float(p0[0])
		if dx < 1e-4:
			continue
		var m := (float(p1[1]) - float(p0[1])) / dx
		var kt := m * sgn
		var c0 := wall_h + float(p0[1]) + m * (half - float(p0[0])) - kt * ridge_mid
		var mid_x := (float(p0[0]) + float(p1[0])) * 0.5
		var on_left := mid_x < half
		var on_a := on_left == left_is_pos      # picture's left is model side A when left_is_pos
		var label := ""
		if on_a:
			label = a_side[mini(na, 3)]
			na += 1
		else:
			label = b_side[mini(nb, 3)]
			nb += 1
		out.append({"a": 0.0 if along_x else kt, "b": kt if along_x else 0.0, "c": c0, "label": label, "end": false})
	if single_ridge(prof):
		var hr := ridge_height(prof)
		var ra := float(g["ra"])
		var rb := float(g["rb"])
		var max_in := maxf((s_hi - s_lo) * 0.5 - 0.05, 0.0)
		ra = minf(ra, max_in)
		rb = minf(rb, max_in)
		if ra > 0.02 and hr > 0.01:
			var k1 := hr / ra
			out.append({"a": k1 if along_x else 0.0, "b": 0.0 if along_x else k1, "c": wall_h - k1 * s_lo, "label": "G", "end": true})
		if rb > 0.02 and hr > 0.01:
			var k2 := hr / rb
			out.append({"a": -k2 if along_x else 0.0, "b": 0.0 if along_x else -k2, "c": wall_h + k2 * s_hi, "label": "H", "end": true})
	return out


static func height_at(planes: Array, x: float, z: float) -> float:
	var y := INF
	for p in planes:
		y = minf(y, float(p["a"]) * x + float(p["b"]) * z + float(p["c"]))
	return y


## Effective profile (what the lower envelope really gives) sampled across the span, for drawing: [[x, y above eaves], ...].
## Uses the planes of the segments only (ends ignored).
static func effective_profile(gen: Dictionary, span: float, steps := 48) -> Array:
	var g := normalize(gen, span)
	var prof: Array = g["prof"]
	var out: Array = []
	for i in range(steps + 1):
		var x := span * float(i) / float(steps)
		var y := INF
		for k in range(prof.size() - 1):
			var p0: Array = prof[k]
			var p1: Array = prof[k + 1]
			var dx := float(p1[0]) - float(p0[0])
			if dx < 1e-4:
				continue
			y = minf(y, float(p0[1]) + (float(p1[1]) - float(p0[1])) / dx * (x - float(p0[0])))
		out.append([x, maxf(y, 0.0) if y < INF else 0.0])
	return out


static func to_json(list: Array) -> String:
	return JSON.stringify(list)


static func list_from_json(text: String) -> Array:
	if text.strip_edges() == "":
		return []
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_ARRAY:
		return []
	var out: Array = []
	for e in d:
		if typeof(e) == TYPE_DICTIONARY and typeof(e.get("prof")) == TYPE_ARRAY:
			out.append(e)
	return out


## Eaves line and apex measured on a gable PICTURE (wall + triangle on a flat background):
## {"eave": row of the eaves, "apex": row of the ridge} in pixels from the top, or {} for a picture without background corners.
static func picture_profile(img: Image) -> Dictionary:
	if img == null or img.get_width() < 40 or img.get_height() < 40:
		return {}
	var w := img.get_width()
	var h := img.get_height()
	var a := img.get_pixel(3, 3)
	var b := img.get_pixel(w - 4, 3)
	var bg := (a + b) * 0.5
	if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.15:
		return {}
	var first: Array = []
	first.resize(w)
	for x in range(w):
		first[x] = -1
	for x in range(2, w - 2, 2):
		var run := 0
		for y in range(0, h):
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.3:
				run += 1
				if run >= 3:
					first[x] = y - 2
					break
			else:
				run = 0
	var apex := h
	for x in range(2, w - 2, 2):
		if int(first[x]) >= 0:
			apex = mini(apex, int(first[x]))
	var left: Array = []
	var right: Array = []
	for x in range(2, 12, 2):
		if int(first[x]) >= 0:
			left.append(int(first[x]))
	for x in range(w - 12 - (w % 2), w - 2, 2):
		if x >= 0 and int(first[x]) >= 0:
			right.append(int(first[x]))
	if left.is_empty() or right.is_empty() or apex >= h:
		return {}
	left.sort()
	right.sort()
	var eave := (int(left[left.size() / 2]) + int(right[right.size() / 2])) / 2
	if eave <= apex + 2 or eave >= h - 4:
		return {}
	return {"eave": eave, "apex": apex}
