class_name SheetLayout
extends RefCounted
## Layout of the texture sheet computed from the real size of the walls, instead of a fixed grid.
##
## Every picture gets a frame with the true proportions of its wall (width x height in metres times ONE
## common scale, px per metre). The frames are packed tightly on the square canvas and the scale is the
## largest whole number of px/m at which everything still fits - so no canvas is wasted and nothing has
## to be stretched. The same data cuts the sheet back into panels (AtlasSlicer) and draws the guide image
## that is given to ChatGPT together with the prompt.
##
## Element: [code "S1", width m, height m, kind "wall"|"gable"|"roof", eave height m (gables only)]

const CANVAS := 4096
const PAD := 16          # px of plain background kept around each picture inside its frame
const MAX_PPM := 300

const BG := Color8(128, 128, 128)


## Returns {"canvas", "ppm", "frames": {code: [x,y,w,h]}, "pictures": {code: [x,y,w,h]}, "kinds": {code: kind},
##          "eave_px": {code: px}, "fill": 0..1}. `frames` include the padding, `pictures` are the areas to draw in.
static func compute(elems: Array, canvas := CANVAS) -> Dictionary:
	var out := {"canvas": canvas, "ppm": 0, "frames": {}, "pictures": {}, "kinds": {}, "eave_px": {}, "fill": 0.0}
	if elems.is_empty():
		return out
	# the area of the pictures bounds the scale from above: start the search there
	var area1 := 0.0
	for e in elems:
		area1 += float(e[1]) * float(e[2])
	var upper := mini(MAX_PPM, int(floor(float(canvas) / sqrt(maxf(area1, 0.01)))))
	for ppm in range(upper, 7, -1):
		var items: Array = []
		for i in range(elems.size()):
			var e: Array = elems[i]
			items.append({"i": i, "w": int(ceil(float(e[1]) * ppm)) + 2 * PAD, "h": int(ceil(float(e[2]) * ppm)) + 2 * PAD})
		var pos := _pack(items, canvas)
		if pos.is_empty():
			continue
		var used := 0.0
		for i in range(elems.size()):
			var e: Array = elems[i]
			var it: Dictionary = items[i]
			var p: Vector2i = pos[i]
			var code := str(e[0])
			out["frames"][code] = [p.x, p.y, int(it["w"]), int(it["h"])]
			out["pictures"][code] = [p.x + PAD, p.y + PAD, int(it["w"]) - 2 * PAD, int(it["h"]) - 2 * PAD]
			out["kinds"][code] = str(e[3]) if e.size() > 3 else "wall"
			if e.size() > 4:
				out["eave_px"][code] = int(round(float(e[4]) * ppm))
			used += float(int(it["w"]) * int(it["h"]))
		out["ppm"] = ppm
		out["fill"] = used / float(canvas * canvas)
		return out
	return out


## MaxRects packing: several item orders and fit rules are tried (a few hundred cheap runs for <= 8 items).
## Returns the top-left corner of every item in the order of `items`, or [] when they do not fit.
static func _pack(items: Array, canvas: int) -> Array:
	for it in items:
		if int(it["w"]) > canvas or int(it["h"]) > canvas:
			return []
	var orders: Array = []
	var keys := [
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["h"]) > int(b["h"]),
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["w"]) > int(b["w"]),
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["w"]) * int(a["h"]) > int(b["w"]) * int(b["h"]),
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["w"]) + int(a["h"]) > int(b["w"]) + int(b["h"]),
	]
	for k in keys:
		var list := items.duplicate()
		list.sort_custom(k)
		orders.append(list)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for _n in range(60):
		var list := items.duplicate()
		for i in range(list.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = list[i]
			list[i] = list[j]
			list[j] = t
		orders.append(list)
	for list in orders:
		for rule in range(3):
			var pos := _maxrects(list, items.size(), canvas, rule)
			if not pos.is_empty():
				return pos
	return []


## rule 0: best short side fit, 1: best area fit, 2: bottom-left.
static func _maxrects(list: Array, count: int, canvas: int, rule: int) -> Array:
	var free: Array = [Rect2i(0, 0, canvas, canvas)]
	var pos: Array = []
	pos.resize(count)
	for it in list:
		var w: int = it["w"]
		var h: int = it["h"]
		var best := -1
		var best_a := 1 << 60
		var best_b := 1 << 60
		for fi in range(free.size()):
			var f: Rect2i = free[fi]
			if w > f.size.x or h > f.size.y:
				continue
			var a := 0
			var b := 0
			match rule:
				0:
					a = mini(f.size.x - w, f.size.y - h)
					b = maxi(f.size.x - w, f.size.y - h)
				1:
					a = f.size.x * f.size.y - w * h
					b = mini(f.size.x - w, f.size.y - h)
				_:
					a = f.position.y + h
					b = f.position.x
			if a < best_a or (a == best_a and b < best_b):
				best = fi
				best_a = a
				best_b = b
		if best < 0:
			return []
		var fr: Rect2i = free[best]
		var placed := Rect2i(fr.position, Vector2i(w, h))
		pos[int(it["i"])] = fr.position
		var next: Array = []
		for f in free:
			if not f.intersects(placed):
				next.append(f)
				continue
			if placed.position.x > f.position.x:
				next.append(Rect2i(f.position, Vector2i(placed.position.x - f.position.x, f.size.y)))
			if placed.end.x < f.end.x:
				next.append(Rect2i(Vector2i(placed.end.x, f.position.y), Vector2i(f.end.x - placed.end.x, f.size.y)))
			if placed.position.y > f.position.y:
				next.append(Rect2i(f.position, Vector2i(f.size.x, placed.position.y - f.position.y)))
			if placed.end.y < f.end.y:
				next.append(Rect2i(Vector2i(f.position.x, placed.end.y), Vector2i(f.size.x, f.end.y - placed.end.y)))
		# drop free rectangles that lie inside another one
		var pruned: Array = []
		for i in range(next.size()):
			var inside := false
			for j in range(next.size()):
				if i != j and (next[j] as Rect2i).encloses(next[i]) and (next[i] != next[j] or j < i):
					inside = true
					break
			if not inside:
				pruned.append(next[i])
		free = pruned
	return pos


## Role of a sector code: S1/S2 long walls, S3/S4 gables, S5 roof, S6.. annex walls.
static func role_of(code: String) -> String:
	var n := int(code.substr(1))
	if n >= 1 and n <= AtlasSlicer.TEMPLATE_ROLES.size():
		return AtlasSlicer.TEMPLATE_ROLES[n - 1]
	return "facade_annex"


static func to_json(layout: Dictionary) -> String:
	return JSON.stringify({"canvas": layout["canvas"], "ppm": layout["ppm"], "frames": layout["frames"], "pictures": layout["pictures"],
		"kinds": layout["kinds"], "eave_px": layout["eave_px"]})


## Parses a stored layout; returns {} when it is not usable.
static func from_json(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or not d.has("frames") or typeof(d["frames"]) != TYPE_DICTIONARY or (d["frames"] as Dictionary).is_empty():
		return {}
	if float(d.get("canvas", 0)) <= 0.0:
		return {}
	return d


# ---------------------------------------------------------------------------------------------------------------
# Guide image: the frames drawn on the canvas, to be attached to the ChatGPT message.

const GLYPHS := {
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
}


static func render_guide(layout: Dictionary) -> Image:
	var size := int(layout["canvas"])
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(BG)
	var frame_col := Color8(214, 60, 52)
	var fill_col := Color8(205, 205, 205)
	var out_col := Color8(96, 96, 96)
	var shape_col := Color8(40, 90, 200)
	for code in layout["frames"].keys():
		var f: Array = layout["frames"][code]
		var p: Array = layout["pictures"][code]
		img.fill_rect(Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3])), frame_col)
		var pic := Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
		img.fill_rect(pic, fill_col)
		if str(layout["kinds"].get(code, "wall")) == "gable":
			_gable_shape(img, pic, int(layout["eave_px"].get(code, pic.size.y / 2)), out_col, shape_col)
		var scale := maxi(3, mini(pic.size.x, pic.size.y) / 22)
		_text(img, str(code), pic.position + Vector2i(scale * 2, scale * 2 + (pic.size.y / 2 - scale * 4 if str(layout["kinds"].get(code, "wall")) == "gable" else 0)), scale, Color8(30, 30, 30))
	return img


## Grey outside the house outline (the two corners beside the roof triangle) and a blue outline.
static func _gable_shape(img: Image, pic: Rect2i, eave_px: int, out_col: Color, line_col: Color) -> void:
	var eave := clampi(eave_px, 1, pic.size.y - 2)
	var tri_h := pic.size.y - eave
	var half := pic.size.x * 0.5
	for row in range(tri_h):
		var inside := half * float(row) / float(maxi(tri_h, 1))          # half-width of the roof triangle in this row
		var left := int(floor(half - inside))
		var right := int(ceil(half + inside))
		if left > 0:
			img.fill_rect(Rect2i(pic.position.x, pic.position.y + row, left, 1), out_col)
		if pic.size.x - right > 0:
			img.fill_rect(Rect2i(pic.position.x + right, pic.position.y + row, pic.size.x - right, 1), out_col)
	var t := maxi(2, pic.size.x / 400)
	var apex := Vector2(pic.position.x + half, pic.position.y)
	var le := Vector2(pic.position.x, pic.position.y + tri_h)
	var re := Vector2(pic.end.x, pic.position.y + tri_h)
	_line(img, le, apex, t, line_col)
	_line(img, apex, re, t, line_col)
	_line(img, le, Vector2(le.x, pic.end.y), t, line_col)
	_line(img, re, Vector2(re.x - t, pic.end.y), t, line_col)


static func _line(img: Image, a: Vector2, b: Vector2, t: int, col: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	var sz := img.get_size()
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		var r := Rect2i(int(p.x) - t / 2, int(p.y) - t / 2, t, t).intersection(Rect2i(Vector2i.ZERO, sz))
		if r.size.x > 0 and r.size.y > 0:
			img.fill_rect(r, col)


static func _text(img: Image, txt: String, at: Vector2i, scale: int, col: Color) -> void:
	var x := at.x
	for ch in txt:
		var g: Array = GLYPHS.get(ch, [])
		if g.is_empty():
			x += 6 * scale
			continue
		for gy in range(7):
			var row: String = g[gy]
			for gx in range(5):
				if row[gx] == "#":
					img.fill_rect(Rect2i(x + gx * scale, at.y + gy * scale, scale, scale), col)
		x += 6 * scale
