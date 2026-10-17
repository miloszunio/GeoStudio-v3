class_name GptDescribe
extends RefCounted
## The second half of the GPT answer: a JSON description of the sheet it has just drawn.
## GPT names *classes* (material, condition, opening type) and rough positions; the program owns the
## numbers: class -> roughness/metallic/specular comes from the table below, and opening rectangles
## are snapped to real edges in the picture (refine_rect), so a sloppy answer cannot spoil the model.

const SCHEMA := "geo3d_describe_v1"

## class -> [roughness, metallic, specular]
const MATERIALS := {
	"plaster": [0.90, 0.0, 0.35], "brick": [0.85, 0.0, 0.40], "stone": [0.80, 0.0, 0.50],
	"concrete": [0.92, 0.0, 0.30], "wood": [0.75, 0.0, 0.40], "metal_sheet": [0.45, 0.80, 0.70],
	"roof_tile": [0.70, 0.0, 0.45], "roofing_felt": [0.95, 0.0, 0.25], "thatch": [1.00, 0.0, 0.15],
	"glass": [0.10, 0.0, 0.90], "other": [0.85, 0.0, 0.40],
}
## condition -> added roughness
const CONDITIONS := {"new": -0.10, "good": 0.0, "worn": 0.08, "dirty": 0.12}
const OPENING_TYPES := ["window", "door", "gate", "shopfront", "vent"]
const ROOF_SHAPES := ["gabled", "flat", "skillion", "hipped"]
const MAX_ELEMENTS := 40


## Text appended to the GPT prompt. `sectors` = codes that hold a wall or roof, e.g. ["S1","S2","S5"].
static func prompt_section(sectors: Array) -> String:
	var l: Array[String] = []
	l.append("")
	l.append("CZĘŚĆ 2 ODPOWIEDZI – OPIS JSON TEGO ARKUSZA")
	l.append("Gdy arkusz jest gotowy, przeanalizuj DOKŁADNIE ten obraz, który wygenerowałeś, i w tej samej odpowiedzi podaj jeden blok JSON (w bloku kodu ```json, bez komentarzy) według schematu:")
	l.append("{")
	l.append('  "schema": "%s",' % SCHEMA)
	l.append('  "building": {"roof_shape": "gabled|flat|skillion|hipped", "floors": liczba, "colour": "#rrggbb", "notes": "czego nie udało się zachować / co wywnioskowano"},')
	l.append('  "sectors": {')
	l.append('    "S1": {"source": "photo|inferred", "photo_counts": {"windows": liczba, "doors": liczba},')
	l.append('           "material": "<klasa>", "condition": "new|good|worn|dirty", "colour": "#rrggbb",')
	l.append('           "elements": [{"id": "okno_1", "type": "window|door|gate|shopfront|vent", "rect": [x0, y0, x1, y1], "lit": false}]},')
	l.append('    "S2": {…}')
	l.append("  }")
	l.append("}")
	l.append("Sektory do opisania: %s (pozostałe pomiń)." % ", ".join(PackedStringArray(sectors)))
	l.append("REGUŁY JSON:")
	l.append("- „source”: photo = sektor powstał z poprawionego zdjęcia tej ściany; inferred = ściany nie było na zdjęciach i została wywnioskowana. „photo_counts” = ile okien i drzwi liczysz na ZDJĘCIU ŹRÓDŁOWYM tej ściany (przed rysowaniem; pomiń dla inferred). Liczba elementów w „elements” ma się zgadzać z liczbą okien/drzwi, które narysowałeś – jeśli się różni, wyjaśnij w „notes”.")
	l.append("- „notes” w „building”: krótko, po polsku, każde odstępstwo od zdjęcia (np. „S2: brak zdjęcia, wariant S1”, „S1: nie zachowałem rozstawu okien”). Pusty tekst, jeśli wszystko wiernie.")
	l.append("- „material” to JEDNA z klas: %s. Dla dachu (S5) użyj klasy pokrycia (roof_tile, metal_sheet, roofing_felt, thatch)." % ", ".join(PackedStringArray(MATERIALS.keys())))
	l.append("- „condition” opisuje stan powierzchni; „colour” to dominujący kolor powierzchni bez okien i drzwi.")
	l.append("- „elements” to okna, drzwi, bramy, witryny i kratki wentylacyjne WIDOCZNE na ścianie w tym sektorze (nie dotyczy dachu S5). Każdy element ma unikalne „id” w całym pliku (okno_1, okno_2, drzwi_1, …).")
	l.append("- „rect” = [x0, y0, x1, y1]: lewy-górny i prawy-dolny róg prostokąta elementu jako UŁAMKI od 0 do 1 mierzone względem samego obrazu ściany w sektorze (x0,y0 = 0,0 to lewy górny róg ściany, 1,1 to prawy dolny; NIE względem całego arkusza i nie względem tła). Obejmij całą ramę okna/drzwi. Podaj 3 miejsca po przecinku.")
	l.append('- „lit”: true tylko dla okien/lamp, które na zdjęciu świecą; w przeciwnym razie false.')
	l.append("- Nie zgaduj: jeśli nie widzisz elementu wyraźnie, pomiń go. Nie wymyślaj elementów, których nie ma na obrazie.")
	l.append("- Poza blokiem JSON nie dodawaj żadnych komentarzy do tej części.")
	return "\n".join(l)


## Text from ChatGPT -> {"ok", "error", "warnings", "data"}. Accepts the JSON inside ``` fences or after chatter.
static func parse(text: String) -> Dictionary:
	var out := {"ok": false, "error": "", "warnings": [], "data": {}}
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		out["error"] = "Nie znaleziono bloku JSON w tekście."
		return out
	var parsed = JSON.parse_string(text.substr(a, b - a + 1))
	if typeof(parsed) != TYPE_DICTIONARY:
		out["error"] = "JSON jest niepoprawny (sprawdź przecinki i cudzysłowy)."
		return out
	return validate(parsed, out)


static func validate(src: Dictionary, out := {"ok": false, "error": "", "warnings": [], "data": {}}) -> Dictionary:
	var warn: Array = out["warnings"]
	var sectors_in = src.get("sectors", null)
	if typeof(sectors_in) != TYPE_DICTIONARY or (sectors_in as Dictionary).is_empty():
		out["error"] = "Brak sekcji „sectors”."
		return out
	var data := {"schema": SCHEMA, "building": {}, "sectors": {}}
	var bi = src.get("building", {})
	if typeof(bi) == TYPE_DICTIONARY:
		var rs := str(bi.get("roof_shape", ""))
		if rs != "":
			if rs in ROOF_SHAPES:
				data["building"]["roof_shape"] = rs
			else:
				warn.append("Nieznany kształt dachu „%s” – pominięto." % rs)
		if bi.has("floors") and (typeof(bi["floors"]) == TYPE_INT or typeof(bi["floors"]) == TYPE_FLOAT) and int(bi["floors"]) > 0:
			data["building"]["floors"] = int(bi["floors"])
		if _hex_ok(str(bi.get("colour", ""))):
			data["building"]["colour"] = str(bi["colour"]).to_lower()
		if str(bi.get("notes", "")).strip_edges() != "":
			data["building"]["notes"] = str(bi["notes"]).strip_edges().left(600)
	var used_ids := {}
	for code in (sectors_in as Dictionary).keys():
		var c := str(code).to_upper()
		var s = sectors_in[code]
		if not (c.length() == 2 and c[0] == "S" and c[1].is_valid_int() and int(c[1]) >= 1 and int(c[1]) <= 8) or typeof(s) != TYPE_DICTIONARY:
			warn.append("Pominięto sektor „%s”." % str(code))
			continue
		var sec := {}
		var mat := str(s.get("material", "other")).to_lower()
		if not MATERIALS.has(mat):
			warn.append("%s: nieznana klasa materiału „%s” – użyto „other”." % [c, mat])
			mat = "other"
		sec["material"] = mat
		var cond := str(s.get("condition", "good")).to_lower()
		if not CONDITIONS.has(cond):
			warn.append("%s: nieznany stan „%s” – użyto „good”." % [c, cond])
			cond = "good"
		sec["condition"] = cond
		var src_kind := str(s.get("source", "photo")).to_lower()
		sec["source"] = src_kind if src_kind in ["photo", "inferred"] else "photo"
		var pc = s.get("photo_counts", null)
		if typeof(pc) == TYPE_DICTIONARY:
			var cnt := {}
			for k in ["windows", "doors"]:
				if pc.has(k) and (typeof(pc[k]) == TYPE_INT or typeof(pc[k]) == TYPE_FLOAT) and int(pc[k]) >= 0:
					cnt[k] = int(pc[k])
			if not cnt.is_empty():
				sec["photo_counts"] = cnt
		if _hex_ok(str(s.get("colour", ""))):
			sec["colour"] = str(s["colour"]).to_lower()
		var els: Array = []
		var raw = s.get("elements", [])
		if typeof(raw) == TYPE_ARRAY:
			for e in raw:
				if els.size() >= MAX_ELEMENTS:
					warn.append("%s: za dużo elementów, reszta pominięta." % c)
					break
				var el := _element(e, c, used_ids, warn)
				if not el.is_empty():
					els.append(el)
		sec["elements"] = els
		warn.append_array(count_warnings(c, sec))
		data["sectors"][c] = sec
	if (data["sectors"] as Dictionary).is_empty():
		out["error"] = "Żaden sektor nie nadaje się do użycia."
		return out
	out["data"] = data
	out["ok"] = true
	return out


## Compares what GPT counted on the source photo with the openings it listed on the sheet.
static func count_warnings(code: String, sec: Dictionary) -> Array:
	var out: Array = []
	if str(sec.get("source", "photo")) != "photo" or not sec.has("photo_counts"):
		return out
	var win := 0
	var doors := 0
	for e in sec["elements"]:
		if e["type"] in ["window", "shopfront"]:
			win += 1
		elif e["type"] in ["door", "gate"]:
			doors += 1
	var pc: Dictionary = sec["photo_counts"]
	if pc.has("windows") and int(pc["windows"]) != win:
		out.append("%s: na zdjęciu %d okien, na arkuszu opisano %d – arkusz mógł zmienić ich liczbę." % [code, int(pc["windows"]), win])
	if pc.has("doors") and int(pc["doors"]) != doors:
		out.append("%s: na zdjęciu %d drzwi, na arkuszu opisano %d." % [code, int(pc["doors"]), doors])
	return out


static func _element(e: Variant, sector: String, used: Dictionary, warn: Array) -> Dictionary:
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var t := str(e.get("type", "window")).to_lower()
	if not t in OPENING_TYPES:
		warn.append("%s: nieznany typ elementu „%s” – pominięto." % [sector, t])
		return {}
	var r = e.get("rect", null)
	if typeof(r) != TYPE_ARRAY or (r as Array).size() != 4:
		warn.append("%s: element bez poprawnego „rect” – pominięto." % sector)
		return {}
	var v: Array = []
	for x in r:
		if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
			warn.append("%s: współrzędna nie jest liczbą – element pominięto." % sector)
			return {}
		v.append(clampf(float(x), 0.0, 1.0))
	var x0 := minf(v[0], v[2])
	var x1 := maxf(v[0], v[2])
	var y0 := minf(v[1], v[3])
	var y1 := maxf(v[1], v[3])
	if x1 - x0 < 0.01 or y1 - y0 < 0.01:
		warn.append("%s: prostokąt zbyt mały – pominięto." % sector)
		return {}
	var id := str(e.get("id", t)).strip_edges()
	if id == "" or used.has(id):
		var n := 1
		while used.has("%s_%d" % [t, n]):
			n += 1
		id = "%s_%d" % [t, n]
	used[id] = true
	return {"id": id, "type": t, "rect": [snappedf(x0, 0.0001), snappedf(y0, 0.0001), snappedf(x1, 0.0001), snappedf(y1, 0.0001)], "lit": bool(e.get("lit", false))}


static func _hex_ok(s: String) -> bool:
	if s.length() != 7 or s[0] != "#":
		return false
	return s.substr(1).is_valid_hex_number()


## [roughness, metallic, specular] of a class + condition.
static func material_values(cls: String, cond: String) -> Dictionary:
	var m: Array = MATERIALS.get(cls, MATERIALS["other"])
	return {"rough": clampf(float(m[0]) + float(CONDITIONS.get(cond, 0.0)), 0.0, 1.0), "metal": float(m[1]), "spec": float(m[2])}


## Rectangle corners A (top left), B (top right), C (bottom right), D (bottom left), each [x, y].
static func quad(rect: Array) -> Array:
	return [[rect[0], rect[1]], [rect[2], rect[1]], [rect[2], rect[3]], [rect[0], rect[3]]]


## Pulls a rough rectangle (fractions of the image) onto the strongest nearby edges.
## Each side moves at most `reach` (fraction of the image's size). The side is judged on the middle
## 80 % of its length, so a neighbouring window does not drag it away.
static func refine_rect(img: Image, rect: Array, reach := 0.04) -> Array:
	if img.get_width() < 16 or img.get_height() < 16:
		return rect
	if img.get_width() > 1024:
		img = img.duplicate()
		img.clear_mipmaps()
		if img.is_compressed():
			img.decompress()
		img.resize(1024, maxi(int(1024.0 * img.get_height() / img.get_width()), 16), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in range(h):
		for x in range(w):
			lum[y * w + x] = img.get_pixel(x, y).get_luminance()
	var x0 := float(rect[0]) * w
	var y0 := float(rect[1]) * h
	var x1 := float(rect[2]) * w
	var y1 := float(rect[3]) * h
	var rx := maxi(int(reach * w), 2)
	var ry := maxi(int(reach * h), 2)
	var nx0 := _best_vertical(lum, w, h, int(x0), int(y0 + (y1 - y0) * 0.1), int(y0 + (y1 - y0) * 0.9), rx)
	var nx1 := _best_vertical(lum, w, h, int(x1), int(y0 + (y1 - y0) * 0.1), int(y0 + (y1 - y0) * 0.9), rx)
	var ny0 := _best_horizontal(lum, w, h, int(y0), int(x0 + (x1 - x0) * 0.1), int(x0 + (x1 - x0) * 0.9), ry)
	var ny1 := _best_horizontal(lum, w, h, int(y1), int(x0 + (x1 - x0) * 0.1), int(x0 + (x1 - x0) * 0.9), ry)
	if nx1 - nx0 < 3 or ny1 - ny0 < 3:
		return rect
	return [snappedf(nx0 / float(w), 0.0001), snappedf(ny0 / float(h), 0.0001), snappedf(nx1 / float(w), 0.0001), snappedf(ny1 / float(h), 0.0001)]


## x of the vertical edge (between columns x-1 and x) with the biggest mean luminance step near x0.
static func _best_vertical(lum: PackedFloat32Array, w: int, h: int, x0: int, ya: int, yb: int, reach: int) -> int:
	var best := x0
	var best_v := -1.0
	ya = clampi(ya, 0, h - 1)
	yb = clampi(yb, ya + 1, h)
	for x in range(maxi(x0 - reach, 1), mini(x0 + reach, w - 1) + 1):
		var sum := 0.0
		for y in range(ya, yb):
			sum += absf(lum[y * w + x] - lum[y * w + x - 1])
		var v := sum / float(yb - ya) - 0.0005 * absf(float(x - x0))    # prefers the closer one when equal
		if v > best_v:
			best_v = v
			best = x
	return best


static func _best_horizontal(lum: PackedFloat32Array, w: int, h: int, y0: int, xa: int, xb: int, reach: int) -> int:
	var best := y0
	var best_v := -1.0
	xa = clampi(xa, 0, w - 1)
	xb = clampi(xb, xa + 1, w)
	for y in range(maxi(y0 - reach, 1), mini(y0 + reach, h - 1) + 1):
		var sum := 0.0
		for x in range(xa, xb):
			sum += absf(lum[y * w + x] - lum[(y - 1) * w + x])
		var v := sum / float(xb - xa) - 0.0005 * absf(float(y - y0))
		if v > best_v:
			best_v = v
			best = y
	return best
