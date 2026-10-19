class_name PanelSheet
extends RefCounted
## The sheet ChatGPT returns: every texture picture sits in a thin red frame (PanelFrames), anywhere and at any size.
## Each frame gets a code - S1/S2 long walls, S3/S4 gables, S5 roof, S6..S8 annex walls - from ChatGPT's own JSON
## (the rough position of the frame), otherwise from the shape of the picture; the user can fix it in the panel editor.
## The program then lays the pictures out itself (SheetLayout) at the REAL width of each wall, so the sheet that goes on
## to the slicer has one scale and the true proportions, whatever ChatGPT did with sizes.

const CODES := ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8"]
const LABELS := {
	"": "— pomiń —", "S1": "S1 ściana długa A", "S2": "S2 ściana długa B", "S3": "S3 szczyt A", "S4": "S4 szczyt B",
	"S5": "S5 dach", "S6": "S6 dobudówka 1", "S7": "S7 dobudówka 2", "S8": "S8 dobudówka 3",
}


## What each code stands for in this building: {code: {"w": width m, "kind": "wall"|"gable"|"roof", "h_guess": m}}.
static func expected(info: Dictionary) -> Dictionary:
	var main: Dictionary = info.get("main", {})
	var len_m := float(main.get("len", 10.0))
	var wid_m := float(main.get("wid", 6.0))
	var wall_h := float(main.get("wall_h", 3.0))
	var roof_h := float(main.get("roof_h", 0.0))
	var gable := str(info.get("roof", "gable")) == "gable"
	var slope := sqrt(pow(wid_m * 0.5, 2.0) + roof_h * roof_h) if gable else wid_m
	var out := {
		"S1": {"w": len_m, "kind": "wall", "h_guess": wall_h}, "S2": {"w": len_m, "kind": "wall", "h_guess": wall_h},
		"S3": {"w": wid_m, "kind": "gable" if gable else "wall", "h_guess": wall_h + (roof_h if gable else 0.0)},
		"S4": {"w": wid_m, "kind": "gable" if gable else "wall", "h_guess": wall_h + (roof_h if gable else 0.0)},
		"S5": {"w": len_m, "kind": "roof", "h_guess": slope},
	}
	var idx := 6
	for a in info.get("annexes", []):
		if idx > 8:
			break
		out["S%d" % idx] = {"w": float(a.get("len", 4.0)), "kind": "wall", "h_guess": float(a.get("wall_h", 3.0))}
		idx += 1
	return out


# ---------------------------------------------------------------------------------------------------------------
# Assignment of codes

## True when the top corners of the picture are flat and alike (a gable picture: the triangle leaves two grey corners).
static func _has_grey_corners(img: Image, r: Rect2i) -> bool:
	if r.size.x < 60 or r.size.y < 60:
		return false
	var s := 8
	var a := _patch(img, Rect2i(r.position.x + 4, r.position.y + 4, s, s))
	var b := _patch(img, Rect2i(r.end.x - 4 - s, r.position.y + 4, s, s))
	var mid := _patch(img, Rect2i(r.position.x + 4, r.position.y + r.size.y / 2, s, s))
	if a[1] > 0.02 or b[1] > 0.02:
		return false
	var ca: Color = a[0]
	var cb: Color = b[0]
	var cm: Color = mid[0]
	var da := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	var grey := absf(ca.r - 0.5) < 0.1 and absf(ca.g - 0.5) < 0.1 and absf(ca.b - 0.5) < 0.1
	var unlike_wall := (absf(ca.r - cm.r) + absf(ca.g - cm.g) + absf(ca.b - cm.b)) > 0.08
	return da < 0.12 and (grey or unlike_wall)


## [mean colour, standard deviation of luminance] of a small block.
static func _patch(img: Image, r: Rect2i) -> Array:
	var sum := Color(0, 0, 0)
	var n := 0
	var lum: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			sum += c
			n += 1
			lum.append(c.get_luminance())
	if n == 0:
		return [Color(0, 0, 0), 1.0]
	var mean := sum / float(n)
	var ml := mean.get_luminance()
	var v := 0.0
	for l in lum:
		v += (float(l) - ml) * (float(l) - ml)
	return [mean, sqrt(v / float(n))]


## codes[i] for panels[i] (the Rect2i "inner" of each). hints: {code: [x0,y0,x1,y1] fractions of the sheet} from ChatGPT's JSON.
static func auto_assign(panels: Array, img: Image, info: Dictionary, hints: Dictionary = {}) -> Array:
	var codes: Array = []
	codes.resize(panels.size())
	codes.fill("")
	var exp := expected(info)
	var used := {}
	var hinted := {}
	var W := float(img.get_width())
	var H := float(img.get_height())
	# 1. ChatGPT's own idea of where each frame is
	var pairs: Array = []
	for i in range(panels.size()):
		var c: Vector2 = Rect2((panels[i] as Rect2i)).get_center() / Vector2(W, H)
		for code in hints.keys():
			var f: Array = hints[code]
			if f.size() < 4 or not exp.has(code):
				continue
			var hc := Vector2((float(f[0]) + float(f[2])) * 0.5, (float(f[1]) + float(f[3])) * 0.5)
			pairs.append([c.distance_to(hc), i, str(code)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for p in pairs:
		if float(p[0]) > 0.22:
			break
		var i := int(p[1])
		if str(codes[i]) != "" or used.has(str(p[2])):
			continue
		codes[i] = str(p[2])
		hinted[i] = true
		used[str(p[2])] = true
	# 2. the rest by the shape of the picture
	var left: Array = []
	for i in range(panels.size()):
		if str(codes[i]) == "":
			left.append(i)
	var gables: Array = []
	var others: Array = []
	for i in left:
		if exp.get("S3", {}).get("kind", "") == "gable" and _has_grey_corners(img, panels[i]):
			gables.append(i)
		else:
			others.append(i)
	for i in gables:
		for code in ["S3", "S4"]:
			if not used.has(code):
				codes[i] = code
				used[code] = true
				break
	# roof: a dark, colourless, uniform surface (tiles, felt) - no walls look like that
	if not used.has("S5"):
		var best := -1
		var best_score := 0.0
		for i in others:
			var pr: Rect2i = panels[i]
			var cell := _patch(img, Rect2i(pr.position.x + pr.size.x / 4, pr.position.y + pr.size.y / 4, pr.size.x / 2, pr.size.y / 2))
			var mc: Color = cell[0]
			var chroma := maxf(mc.r, maxf(mc.g, mc.b)) - minf(mc.r, minf(mc.g, mc.b))
			if mc.get_luminance() < 0.3 and chroma < 0.14:
				var score := 0.3 - mc.get_luminance()
				if best < 0 or score > best_score:
					best = i
					best_score = score
		if best >= 0:
			codes[best] = "S5"
			used["S5"] = true
			others.erase(best)
	# long walls: closest aspect to len / wall height, then the roof, then annexes
	var main_len := float(exp["S1"]["w"])
	var asp_long := main_len / maxf(float(exp["S1"]["h_guess"]), 0.5)
	var asp_roof := main_len / maxf(float(exp["S5"]["h_guess"]), 0.5)
	others.sort_custom(func(a: int, b: int) -> bool:
		var ra: Rect2i = panels[a]
		var rb: Rect2i = panels[b]
		return absf(log(float(ra.size.x) / float(ra.size.y) / asp_long)) < absf(log(float(rb.size.x) / float(rb.size.y) / asp_long)))
	for i in others:
		var r: Rect2i = panels[i]
		var a := float(r.size.x) / float(r.size.y)
		var want := ""
		if not used.has("S1"):
			want = "S1"
		elif not used.has("S2"):
			want = "S2"
		elif not used.has("S5") and absf(log(a / asp_roof)) < 0.6:
			want = "S5"
		else:
			for code in ["S6", "S7", "S8"]:
				if exp.has(code) and not used.has(code):
					want = code
					break
		if want != "":
			codes[i] = want
			used[want] = true
	# long walls left to right
	var l1 := codes.find("S1")
	var l2 := codes.find("S2")
	if l1 >= 0 and l2 >= 0 and not (hinted.has(l1) or hinted.has(l2)) and (panels[l1] as Rect2i).position.x > (panels[l2] as Rect2i).position.x:
		codes[l1] = "S2"
		codes[l2] = "S1"
	return codes


# ---------------------------------------------------------------------------------------------------------------
# Laying the sheet out

## panels: [{"code": "S1", "inner": Rect2i}] in pixels of `img`. Returns {"image", "layout", "found", "missing", "notes"}.
static func build(img: Image, panels: Array, info: Dictionary) -> Dictionary:
	var exp := expected(info)
	var src := img
	if src.is_compressed():
		src = img.duplicate()
		src.decompress()
	if src.get_format() != Image.FORMAT_RGB8:
		src = src.duplicate()
		src.convert(Image.FORMAT_RGB8)
	var crops := {}
	for p in panels:
		var code := str(p["code"])
		if code == "" or not exp.has(code) or crops.has(code):
			continue
		var r: Rect2i = (p["inner"] as Rect2i).intersection(Rect2i(0, 0, src.get_width(), src.get_height()))
		if r.size.x < 8 or r.size.y < 8:
			continue
		crops[code] = src.get_region(r)
	var out := {"image": null, "layout": {}, "found": [], "missing": [], "notes": []}
	if crops.is_empty():
		return out
	var wall_m := -1.0
	var elems: Array = []
	var order: Array = crops.keys()
	order.sort()
	for code in order:
		var c: Image = crops[code]
		var w_m := float(exp[code]["w"])
		var h_m := w_m * float(c.get_height()) / float(c.get_width())
		if code == "S1" or (code == "S2" and wall_m < 0.0):
			wall_m = h_m
	for code in order:
		var c: Image = crops[code]
		var e: Dictionary = exp[code]
		var w_m := float(e["w"])
		var h_m := w_m * float(c.get_height()) / float(c.get_width())
		var kind := str(e["kind"])
		if kind == "gable":
			var eave := wall_m if wall_m > 0.0 else float(info.get("main", {}).get("wall_h", 3.0))
			elems.append([code, w_m, h_m, "gable", minf(eave, h_m * 0.95)])
		else:
			elems.append([code, w_m, h_m, kind])
	var lay := SheetLayout.compute(elems)
	if int(lay["ppm"]) <= 0:
		out["notes"].append("Panele nie mieszczą się na płótnie 4096 px.")
		return out
	var sheet := Image.create(int(lay["canvas"]), int(lay["canvas"]), false, Image.FORMAT_RGB8)
	sheet.fill(SheetLayout.BG)
	for code in order:
		var pic: Array = lay["pictures"][code]
		var c2: Image = crops[code]
		c2.resize(int(pic[2]), int(pic[3]), Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(c2, Rect2i(0, 0, c2.get_width(), c2.get_height()), Vector2i(int(pic[0]), int(pic[1])))
		out["found"].append(code)
	for code in exp.keys():
		if not crops.has(code) and code in ["S1", "S2", "S3", "S4", "S5"]:
			out["missing"].append(code)
	out["image"] = sheet
	out["layout"] = lay
	return out


# ---------------------------------------------------------------------------------------------------------------
# Stored assignment (the hidden setting tex_panels)

static func panels_to_json(src_sig: String, panels: Array, auto := true) -> String:
	var list: Array = []
	for p in panels:
		var r: Rect2i = p["inner"]
		list.append({"code": str(p["code"]), "r": [r.position.x, r.position.y, r.size.x, r.size.y]})
	return JSON.stringify({"src": src_sig, "auto": auto, "list": list})


static func panels_from_json(text: String, src_sig: String) -> Array:
	if text.strip_edges() == "":
		return []
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or str(d.get("src", "")) != src_sig or typeof(d.get("list")) != TYPE_ARRAY:
		return []
	var out: Array = []
	for e in d["list"]:
		if typeof(e) == TYPE_DICTIONARY and typeof(e.get("r")) == TYPE_ARRAY and (e["r"] as Array).size() == 4:
			var r: Array = e["r"]
			out.append({"code": str(e.get("code", "")), "inner": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))})
	return out


## Identifies the file: name + size + modification time (the stored panels belong to this exact image).
static func signature(path: String) -> String:
	return "%s|%d|%d" % [path.get_file(), FileAccess.get_size(path) if FileAccess.file_exists(path) else 0, FileAccess.get_modified_time(path)]


## Detects the frames of `img` and assigns codes. Returns [{"code", "inner"}] (empty when the image has no red frames).
static func detect_and_assign(img: Image, info: Dictionary, hints: Dictionary = {}) -> Array:
	if light_framed(img):
		return grid_panels(img)          # cheap test first: no need to hunt for red frames
	var frames := PanelFrames.detect(img)
	if is_sector_sheet(img, frames):
		return grid_panels(img)
	if frames.is_empty():
		return []
	var inner: Array = []
	for f in frames:
		inner.append(trim_background(img, f["inner"]))
	var codes := auto_assign(inner, img, info, hints)
	var out: Array = []
	for i in range(inner.size()):
		out.append({"code": str(codes[i]), "inner": inner[i]})
	return out


## When a picture sits in a frame with a margin of flat background (ChatGPT often draws a frame around its whole
## sector), shrinks the rectangle to what is really drawn. Corners that are not flat = no margin = unchanged.
static func trim_background(img: Image, r: Rect2i, bg_hint := Color(-1, -1, -1)) -> Rect2i:
	if r.size.x < 80 or r.size.y < 80:
		return r
	var s := 6
	var corners := [
		_patch(img, Rect2i(r.position.x + 1, r.position.y + 1, s, s)),
		_patch(img, Rect2i(r.end.x - 1 - s, r.position.y + 1, s, s)),
		_patch(img, Rect2i(r.position.x + 1, r.end.y - 1 - s, s, s)),
		_patch(img, Rect2i(r.end.x - 1 - s, r.end.y - 1 - s, s, s)),
	]
	# background = the colour that at least two flat corners share
	var bg := Color(-1, -1, -1)
	for i in range(4):
		var ci: Array = corners[i]
		if ci[1] > 0.02:
			continue
		var n := 0
		for j in range(4):
			var cj: Array = corners[j]
			if cj[1] <= 0.02 and _dist(ci[0], cj[0]) < 0.06:
				n += 1
		if n >= 2:
			bg = ci[0]
			break
	if bg_hint.r >= 0.0:
		bg = bg_hint
	if bg.r < 0.0:
		return r
	var x0 := r.end.x
	var x1 := r.position.x
	var y0 := r.end.y
	var y1 := r.position.y
	var col_n := PackedInt32Array()
	col_n.resize(r.size.x)
	var row_n := PackedInt32Array()
	row_n.resize(r.size.y)
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			if _dist(img.get_pixel(x, y), bg) > 0.11:
				col_n[x - r.position.x] += 1
				row_n[y - r.position.y] += 1
	var need_c := maxi(2, r.size.y / 2 / 100)
	var need_r := maxi(2, r.size.x / 2 / 100)
	for i in range(r.size.x):
		if col_n[i] >= need_c:
			x0 = mini(x0, r.position.x + i)
			x1 = maxi(x1, r.position.x + i)
	for i in range(r.size.y):
		if row_n[i] >= need_r:
			y0 = mini(y0, r.position.y + i)
			y1 = maxi(y1, r.position.y + i)
	if x1 - x0 < 40 or y1 - y0 < 40:
		return r
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _dist(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


# ---------------------------------------------------------------------------------------------------------------
# Sector sheet: 2 columns x 4 rows of equal sectors, one picture per sector, S1..S8 in reading order.
# This is the layout ChatGPT keeps to best when told to; frames (if any) go round the sectors, not the pictures.

const GRID_COLS := 2
const GRID_ROWS := 4


## A square canvas whose sectors carry thin light frames (what ChatGPT draws round its sectors).
static func light_framed(img: Image) -> bool:
	var asp := float(img.get_width()) / float(maxi(img.get_height(), 1))
	if asp < 0.85 or asp > 1.18 or img.get_width() < 600:
		return false
	var bg := sheet_background(img)
	var framed := 0
	for i in range(GRID_COLS * GRID_ROWS):
		var sec := Rect2i((i % GRID_COLS) * img.get_width() / GRID_COLS, (i / GRID_COLS) * img.get_height() / GRID_ROWS, img.get_width() / GRID_COLS, img.get_height() / GRID_ROWS)
		if _frame_inset(img, sec, 0, bg, -1) > 0 and _frame_inset(img, sec, 1, bg, -1) > 0:
			framed += 1
	return framed >= 2


## True for a (nearly) square canvas that has no frames or only sector-sized ones.
static func is_sector_sheet(img: Image, frames: Array) -> bool:
	var asp := float(img.get_width()) / float(maxi(img.get_height(), 1))
	if asp < 0.85 or asp > 1.18 or img.get_width() < 600:
		return false
	if frames.is_empty():
		return light_framed(img)
	var big := 0
	var sw := float(img.get_width()) / float(GRID_COLS)
	var sh := float(img.get_height()) / float(GRID_ROWS)
	for f in frames:
		var o: Rect2i = f["outer"]
		if float(o.size.x) >= sw * 0.8 and float(o.size.y) >= sh * 0.8:
			big += 1
	return big >= maxi(2, frames.size() * 2 / 3)


## The commonest flat grey of the canvas (the background outside the pictures).
static func sheet_background(img: Image) -> Color:
	var W := img.get_width()
	var H := img.get_height()
	var step := maxi(W / 256, 2)
	var counts := {}
	for y in range(0, H, step):
		for x in range(0, W, step):
			var c := img.get_pixel(x, y)
			var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if chroma > 0.06 or c.get_luminance() < 0.2 or c.get_luminance() > 0.85:
				continue
			var k := int(c.r * 31.0) * 32 + int(c.b * 31.0)
			counts[k] = int(counts.get(k, 0)) + 1
	var best := -1
	var best_n := 0
	for k in counts.keys():
		if int(counts[k]) > best_n:
			best_n = int(counts[k])
			best = int(k)
	if best < 0:
		return Color(0.5, 0.5, 0.5)
	return Color(float(best / 32) / 31.0 + 0.016, float(best / 32) / 31.0 + 0.016, float(best % 32) / 31.0 + 0.016)


## Distance in px from the sector edge to the inside of a thin bright frame line, scanning inwards along `n` lines.
## Returns the median over the lines that found one, or `fallback`.
static func _frame_inset(img: Image, sec: Rect2i, side: int, bg: Color, fallback: int) -> int:
	var found: Array = []
	var maxd := mini(96, (sec.size.x if side % 2 == 0 else sec.size.y) / 8)
	for k in range(1, 8):
		var d0 := 0
		var seen := false
		var run := 0
		var end := -1
		for d in range(0, maxd):
			var pt := Vector2i()
			match side:
				0: pt = Vector2i(sec.position.x + d, sec.position.y + sec.size.y * k / 8)
				1: pt = Vector2i(sec.position.x + sec.size.x * k / 8, sec.position.y + d)
				2: pt = Vector2i(sec.end.x - 1 - d, sec.position.y + sec.size.y * k / 8)
				_: pt = Vector2i(sec.position.x + sec.size.x * k / 8, sec.end.y - 1 - d)
			var c := img.get_pixel(pt.x, pt.y)
			var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var bright := c.get_luminance() > 0.7 and c.get_luminance() > bg.get_luminance() + 0.3 and chroma < 0.08
			if bright:
				if not seen:
					seen = true
					d0 = d
				run += 1
			elif seen:
				end = d
				break
		if seen and end > 0 and run <= 8:
			found.append(end)
	if found.size() < 3:
		return fallback
	found.sort()
	return int(found[found.size() / 2]) + 5


## Panels of a sector sheet: [{"code": "S1".., "inner": Rect2i}] for the sectors that really hold a picture.
static func grid_panels(img: Image) -> Array:
	var W := img.get_width()
	var H := img.get_height()
	var bg := sheet_background(img)
	var out: Array = []
	for i in range(GRID_COLS * GRID_ROWS):
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		var sec := Rect2i(col * W / GRID_COLS, row * H / GRID_ROWS, W / GRID_COLS, H / GRID_ROWS)
		var fb := maxi(3, W / 1024)
		var il := _frame_inset(img, sec, 0, bg, fb)
		var it := _frame_inset(img, sec, 1, bg, fb)
		var ir := _frame_inset(img, sec, 2, bg, fb)
		var ib := _frame_inset(img, sec, 3, bg, fb)
		var inner := sec.grow_individual(-il, -it, -ir, -ib)
		# is there anything but the background?
		var diff := 0
		var total := 0
		var step := maxi(inner.size.x / 160, 2)
		for y in range(inner.position.y, inner.end.y, step):
			for x in range(inner.position.x, inner.end.x, step):
				total += 1
				if _dist(img.get_pixel(x, y), bg) > 0.09:
					diff += 1
		if total == 0 or float(diff) / float(total) < 0.01:
			continue
		var tight := trim_background(img, inner, bg)
		if tight.size.x < 60 or tight.size.y < 60:
			continue
		out.append({"code": "S%d" % (i + 1), "inner": tight})
	return out
