class_name GeoportalClient
extends Node
## Thin client for Geoportal.gov.pl services.
## Everything here works in EPSG:2180 (PUWG 1992): metres, x = easting, y = northing.
##
## NOTE: layer / feature-type names and the WFS axis-order behaviour could not be tested from
## the authoring sandbox (no network). Use "Testuj usługi" in the sidebar to list what the
## servers really expose and fix the values in the "Usługi Geoportalu" section.

signal log_message(text: String)

const CRS_URN := "urn:ogc:def:crs:EPSG::2180"

## All service addresses, layer names, limits and timeouts come from the settings sidebar.
var settings: AppSettings

var _wfs_variant := -1   # index of the request variant that worked last time

## Disk cache shared by all projects, plus a few decoded tiles kept in memory.
var cache := GeoCache.new()
var last_stats := {"tiles": 0, "from_cache": 0, "downloaded": 0, "offline": 0}
var _mem: Dictionary = {}          # cache path -> Image
var _active := 0                   # requests in flight
var _last_msec := 0                # start of the latest request
var _any_http_ok := false          # did the latest fetch_buildings() get a valid HTTP answer?

const TILE_PX := 512
const LEVELS_DM := [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]   # tile resolution in decimetres per pixel
const BUILDING_CELL_M := 400.0
const MAX_TILES := 48


# ------------------------------------------------------------------ projection

## WGS84 lon/lat (degrees) -> EPSG:2180 (x = easting, y = northing), Kruger series on GRS80.
static func lonlat_to_2180(lon_deg: float, lat_deg: float) -> Vector2:
	var a := 6378137.0
	var f := 1.0 / 298.257222101
	var n := f / (2.0 - f)
	var big_a := a / (1.0 + n) * (1.0 + n * n / 4.0 + pow(n, 4.0) / 64.0)
	var al: Array[float] = [
		n / 2.0 - 2.0 * n * n / 3.0 + 5.0 * pow(n, 3.0) / 16.0,
		13.0 * n * n / 48.0 - 3.0 * pow(n, 3.0) / 5.0,
		61.0 * pow(n, 3.0) / 240.0,
	]
	var phi := deg_to_rad(lat_deg)
	var dl := deg_to_rad(lon_deg - 19.0)
	var c := 2.0 * sqrt(n) / (1.0 + n)
	var t := sinh(atanh(sin(phi)) - c * atanh(c * sin(phi)))
	var xi := atan2(t, cos(dl))
	var eta := atanh(sin(dl) / sqrt(1.0 + t * t))
	var xs := xi
	var es := eta
	for j in range(3):
		var k := float(j + 1)
		xs += al[j] * sin(2.0 * k * xi) * cosh(2.0 * k * eta)
		es += al[j] * cos(2.0 * k * xi) * sinh(2.0 * k * eta)
	return Vector2(500000.0 + 0.9993 * big_a * es, -5300000.0 + 0.9993 * big_a * xs)


## EPSG:2180 (x = easting, y = northing) -> WGS84, returns Vector2(lon, lat) in degrees.
static func e2180_to_lonlat(easting: float, northing: float) -> Vector2:
	var a := 6378137.0
	var f := 1.0 / 298.257222101
	var n := f / (2.0 - f)
	var big_a := a / (1.0 + n) * (1.0 + n * n / 4.0 + pow(n, 4.0) / 64.0)
	var beta: Array[float] = [
		n / 2.0 - 2.0 * n * n / 3.0 + 37.0 * pow(n, 3.0) / 96.0,
		n * n / 48.0 + pow(n, 3.0) / 15.0,
		17.0 * pow(n, 3.0) / 480.0,
	]
	var delta: Array[float] = [
		2.0 * n - 2.0 * n * n / 3.0 - 2.0 * pow(n, 3.0),
		7.0 * n * n / 3.0 - 8.0 * pow(n, 3.0) / 5.0,
		56.0 * pow(n, 3.0) / 15.0,
	]
	var xi0 := (northing + 5300000.0) / (0.9993 * big_a)
	var eta0 := (easting - 500000.0) / (0.9993 * big_a)
	var xi := xi0
	var eta := eta0
	for j in range(3):
		var k := float(j + 1)
		xi -= beta[j] * sin(2.0 * k * xi0) * cosh(2.0 * k * eta0)
		eta -= beta[j] * cos(2.0 * k * xi0) * sinh(2.0 * k * eta0)
	var chi := asin(sin(xi) / cosh(eta))
	var phi := chi
	for j in range(3):
		phi += delta[j] * sin(2.0 * float(j + 1) * chi)
	var lam := deg_to_rad(19.0) + atan2(sinh(eta), cos(xi))
	return Vector2(rad_to_deg(lam), rad_to_deg(phi))


# ------------------------------------------------------------------ HTTP

## One GET. Requests are queued (at most svc_max_parallel at a time, svc_min_gap_ms apart) so that
## panning the map does not hammer the server; 429/503 are retried with a growing pause.
func http_get(url: String) -> Dictionary:
	var parallel := maxi(settings.i("svc_max_parallel"), 1)
	var gap := settings.i("svc_min_gap_ms")
	while _active >= parallel:
		await get_tree().process_frame
	_active += 1
	var result_dict := {"ok": false, "code": 0, "body": PackedByteArray(), "error": ""}
	for attempt in range(3):
		var wait := _last_msec + gap - Time.get_ticks_msec()
		if wait > 0:
			await get_tree().create_timer(float(wait) / 1000.0).timeout
		_last_msec = Time.get_ticks_msec()
		result_dict = await _request_once(url)
		var code: int = result_dict["code"]
		if result_dict["ok"] or not (code == 429 or code == 503 or code == 502 or code == 504):
			break
		var pause := float(result_dict.get("retry_after", 0.0))
		if pause <= 0.0:
			pause = 2.0 * float(attempt + 1)
		log_message.emit("HTTP %d – serwer prosi o spokój, ponawiam za %.0f s" % [code, pause])
		await get_tree().create_timer(pause).timeout
	_active -= 1
	return result_dict


func _request_once(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = settings.f("svc_timeout")
	add_child(req)
	var err := req.request(url, ["User-Agent: PhotoTo3DStudio/0.3", "Accept: */*"])
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray(), "error": "request() error %d" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var retry_after := 0.0
	for h in res[2]:
		if str(h).to_lower().begins_with("retry-after:"):
			retry_after = clampf(str(h).get_slice(":", 1).strip_edges().to_float(), 0.0, 30.0)
	return {"ok": ok, "code": code, "body": body, "error": "result=%d" % result, "retry_after": retry_after}


func _sync_cache_settings() -> void:
	cache.ttl_days = settings.f("svc_cache_days")
	cache.max_bytes = settings.i("svc_cache_mb") * 1024 * 1024


## Place search (Nominatim-compatible). Returns [{name, lat, lon}], empty on error.
func search_places(query: String) -> Array:
	var q := query.strip_edges()
	if q == "":
		return []
	var base := settings.s("svc_geocode_url")
	var url := "%s%sformat=jsonv2&limit=8&countrycodes=pl&accept-language=pl&q=%s" % [base, "&" if "?" in base else "?", q.uri_encode()]
	var r: Dictionary = await http_get(url)
	if not r["ok"]:
		log_message.emit("Wyszukiwarka miejsc: HTTP %s (%s)" % [r["code"], r["error"]])
		return []
	return PlaceHistory.parse_nominatim((r["body"] as PackedByteArray).get_string_from_utf8())


# ------------------------------------------------------------------ WMS basemap

## bbox: Rect2 in EPSG:2180 (position = min easting/northing, size = width/height in metres).
func fetch_basemap(bbox: Rect2, size_px: Vector2i) -> Image:
	# WMS 1.1.1 on purpose: BBOX is always minx,miny,maxx,maxy (easting first), no axis-order trap.
	var url := "%s?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=%s&STYLES=&SRS=EPSG:2180&BBOX=%.2f,%.2f,%.2f,%.2f&WIDTH=%d&HEIGHT=%d&FORMAT=image/jpeg" % [
		settings.s("svc_wms_url"), settings.s("svc_wms_layer"), bbox.position.x, bbox.position.y, bbox.end.x, bbox.end.y, size_px.x, size_px.y
	]
	var r: Dictionary = await http_get(url)
	if not r["ok"]:
		log_message.emit("ORTO: HTTP %s (%s)" % [r["code"], r["error"]])
		return null
	var body: PackedByteArray = r["body"]
	var img := Image.new()
	var err: int = ERR_FILE_UNRECOGNIZED
	if body.size() > 4 and body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body.size() > 4 and body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	if err != OK:
		log_message.emit("ORTO: odpowiedź nie jest obrazem: " + body.get_string_from_utf8().left(200))
		return null
	return img


## Orthophoto for a view, assembled from cached 512 px tiles on a fixed grid, so panning and zooming back
## re-use what was downloaded. Returns {"image": Image, "rect": Rect2 (EPSG:2180, covers bbox)} or {}.
func fetch_basemap_tiled(bbox: Rect2, mpp: float) -> Dictionary:
	_sync_cache_settings()
	var level := 0
	for i in range(LEVELS_DM.size()):
		if float(LEVELS_DM[i]) / 10.0 <= mpp * 1.05:
			level = i
	# too many tiles at this resolution: step to a coarser level
	var tile_m := 0.0
	var ix0 := 0
	var iy0 := 0
	var nx := 0
	var ny := 0
	while true:
		tile_m = float(TILE_PX) * float(LEVELS_DM[level]) / 10.0
		ix0 = int(floor(bbox.position.x / tile_m))
		iy0 = int(floor(bbox.position.y / tile_m))
		nx = int(ceil(bbox.end.x / tile_m)) - ix0
		ny = int(ceil(bbox.end.y / tile_m)) - iy0
		if nx * ny <= MAX_TILES or level >= LEVELS_DM.size() - 1:
			break
		level += 1
	var key := GeoCache.service_key(settings.s("svc_wms_url"), settings.s("svc_wms_layer"))
	last_stats = {"tiles": nx * ny, "from_cache": 0, "downloaded": 0, "offline": 0}
	var mosaic := Image.create(nx * TILE_PX, ny * TILE_PX, false, Image.FORMAT_RGB8)
	mosaic.fill(Color(0.08, 0.1, 0.13))
	var got := 0
	for jy in range(ny):
		for jx in range(nx):
			var ix := ix0 + jx
			var iy := iy0 + jy
			var img: Image = await _tile(key, level, ix, iy, tile_m)
			if img == null:
				continue
			got += 1
			# image y runs downwards, northing upwards: the top row of the mosaic is the highest iy
			mosaic.blit_rect(img, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(jx * TILE_PX, (ny - 1 - jy) * TILE_PX))
	log_message.emit("ORTO: %d kafelków (cache %d, pobrano %d, offline %d)" % [
		nx * ny, last_stats["from_cache"], last_stats["downloaded"], last_stats["offline"]])
	if got == 0:
		return {}
	var rect := Rect2(Vector2(ix0 * tile_m, iy0 * tile_m), Vector2(nx * tile_m, ny * tile_m))
	return {"image": mosaic, "rect": rect}


func _tile(service: String, level: int, ix: int, iy: int, tile_m: float) -> Image:
	var path := cache.path_for("wms", service, "L%d_%d_%d.jpg" % [LEVELS_DM[level], ix, iy])
	if _mem.has(path) and cache.is_fresh(path):
		last_stats["from_cache"] += 1
		return _mem[path]
	var bytes := cache.read(path)
	var from_cache := not bytes.is_empty()
	if bytes.is_empty():
		var x0 := float(ix) * tile_m
		var y0 := float(iy) * tile_m
		var url := "%s?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=%s&STYLES=&SRS=EPSG:2180&BBOX=%.1f,%.1f,%.1f,%.1f&WIDTH=%d&HEIGHT=%d&FORMAT=image/jpeg" % [
			settings.s("svc_wms_url"), settings.s("svc_wms_layer"), x0, y0, x0 + tile_m, y0 + tile_m, TILE_PX, TILE_PX]
		var r: Dictionary = await http_get(url)
		if r["ok"] and _decode(r["body"]) != null:
			bytes = r["body"]
			cache.write(path, bytes)
			last_stats["downloaded"] += 1
		else:
			log_message.emit("ORTO: kafelek %d/%d – HTTP %s (%s)" % [ix, iy, r["code"], r["error"]])
			bytes = cache.read(path, true)      # old copy is better than a hole in the map
			if bytes.is_empty():
				return null
			last_stats["offline"] += 1
	else:
		last_stats["from_cache"] += 1
	var img := _decode(bytes)
	if img != null and img.get_width() == TILE_PX:
		if _mem.size() > 80:
			_mem.erase(_mem.keys()[0])
		_mem[path] = img
	return img if (img != null and img.get_width() == TILE_PX and img.get_height() == TILE_PX) else null


static func _decode(body: PackedByteArray) -> Image:
	var img := Image.new()
	var err: int = ERR_FILE_UNRECOGNIZED
	if body.size() > 4 and body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body.size() > 4 and body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	if err != OK:
		return null
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


# ------------------------------------------------------------------ WFS buildings

## Forget which request variant worked (call after the service settings change).
func reset_cache() -> void:
	_wfs_variant = -1
	_mem.clear()


func _typenames() -> PackedStringArray:
	var out := PackedStringArray()
	for t in settings.s("svc_wfs_typenames").split(",", false):
		var tn := t.strip_edges()
		if tn != "":
			out.append(tn)
	return out


func _wfs_urls(bbox: Rect2) -> Array[String]:
	var urls: Array[String] = []
	var minx := bbox.position.x
	var miny := bbox.position.y
	var maxx := bbox.end.x
	var maxy := bbox.end.y
	for tn in _typenames():
		var base := "%s?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=%s&COUNT=%d" % [settings.s("svc_wfs_url"), tn, settings.i("svc_max_features")]
		# Variant A: URN CRS -> official axis order for EPSG:2180 is northing, easting.
		urls.append(base + "&SRSNAME=%s&BBOX=%.2f,%.2f,%.2f,%.2f,%s" % [CRS_URN, miny, minx, maxy, maxx, CRS_URN])
		# Variant B: short EPSG code -> many servers use easting, northing.
		urls.append(base + "&SRSNAME=EPSG:2180&BBOX=%.2f,%.2f,%.2f,%.2f,EPSG:2180" % [minx, miny, maxx, maxy])
	return urls


## Building outlines for a view. The area is split into 400 m grid cells; every cell is downloaded once
## and kept on disk, so moving the map costs requests only for cells not seen before.
## Returns Array of {"ring": PackedVector2Array (x = easting, y = northing), "attrs": Dictionary}.
func fetch_buildings_cached(bbox: Rect2) -> Array:
	_sync_cache_settings()
	var key := GeoCache.service_key(settings.s("svc_wfs_url"), settings.s("svc_wfs_typenames"))
	var ix0 := int(floor(bbox.position.x / BUILDING_CELL_M))
	var iy0 := int(floor(bbox.position.y / BUILDING_CELL_M))
	var ix1 := int(floor(bbox.end.x / BUILDING_CELL_M))
	var iy1 := int(floor(bbox.end.y / BUILDING_CELL_M))
	var seen: Dictionary = {}
	var out: Array = []
	var from_cache := 0
	var downloaded := 0
	for iy in range(iy0, iy1 + 1):
		for ix in range(ix0, ix1 + 1):
			var path := cache.path_for("wfs", key, "c_%d_%d.json" % [ix, iy])
			var cell: Array = []
			var raw := cache.read(path)
			if not raw.is_empty():
				cell = _cell_from_json(raw.get_string_from_utf8())
				from_cache += 1
			else:
				var rect := Rect2(Vector2(ix, iy) * BUILDING_CELL_M, Vector2(BUILDING_CELL_M, BUILDING_CELL_M))
				cell = await fetch_buildings(rect)
				if _any_http_ok:
					cache.write(path, _cell_to_json(cell).to_utf8_buffer())
					downloaded += 1
				else:
					var old := cache.read(path, true)
					if not old.is_empty():
						cell = _cell_from_json(old.get_string_from_utf8())
			for b in cell:
				var ring: PackedVector2Array = b["ring"]
				var k := "%.2f,%.2f,%d" % [ring[0].x, ring[0].y, ring.size()]
				if seen.has(k):
					continue
				seen[k] = true
				out.append(b)
	log_message.emit("EGiB: %d komórek (cache %d, pobrano %d), budynków: %d" % [
		(ix1 - ix0 + 1) * (iy1 - iy0 + 1), from_cache, downloaded, out.size()])
	# only what touches the view
	var visible: Array = []
	for b in out:
		var ring: PackedVector2Array = b["ring"]
		var lo := ring[0]
		var hi := ring[0]
		for q in ring:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		if bbox.intersects(Rect2(lo, hi - lo)):
			visible.append(b)
	return visible


static func _cell_to_json(cell: Array) -> String:
	var arr: Array = []
	for b in cell:
		var ring: Array = []
		for q in (b["ring"] as PackedVector2Array):
			ring.append([q.x, q.y])
		arr.append({"ring": ring, "attrs": b["attrs"]})
	return JSON.stringify({"saved": Time.get_unix_time_from_system(), "buildings": arr})


static func _cell_from_json(text: String) -> Array:
	var d = JSON.parse_string(text)
	var out: Array = []
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for b in d.get("buildings", []):
		var ring := PackedVector2Array()
		for q in b["ring"]:
			ring.append(Vector2(float(q[0]), float(q[1])))
		if ring.size() >= 3:
			out.append({"ring": ring, "attrs": b.get("attrs", {})})
	return out


## Returns Array of {"ring": PackedVector2Array (x = easting, y = northing), "attrs": Dictionary}.
func fetch_buildings(bbox: Rect2) -> Array:
	_any_http_ok = false
	var urls := _wfs_urls(bbox)
	var order: Array[int] = []
	if _wfs_variant >= 0:
		order.append(_wfs_variant)
	for i in range(urls.size()):
		if i != _wfs_variant:
			order.append(i)
	var hint := bbox.get_center()
	for i in order:
		var r: Dictionary = await http_get(urls[i])
		if not r["ok"]:
			log_message.emit("WFS wariant %d: HTTP %s (%s)" % [i, r["code"], r["error"]])
			continue
		_any_http_ok = true
		var body: PackedByteArray = r["body"]
		var found := parse_gml_buildings(body, hint)
		log_message.emit("WFS wariant %d: %d budynków" % [i, found.size()])
		if found.size() > 0:
			_wfs_variant = i
			return found
		var head := body.get_string_from_utf8().left(300)
		if head.contains("Exception"):
			log_message.emit("WFS wyjątek: " + head)
	return []


## Minimal GML 3.x reader: one feature per wfs:member / gml:featureMember, takes the largest
## exterior ring found in it, and keeps simple text properties as attributes (lower-case keys).
func parse_gml_buildings(xml: PackedByteArray, hint: Vector2) -> Array:
	var out: Array = []
	var p := XMLParser.new()
	if p.open_buffer(xml) != OK:
		return out
	var stack := PackedStringArray()
	var member_depth := -1
	var attrs: Dictionary = {}
	var rings: Array = []
	var want := ""
	var dim := 2
	var interior := false
	while p.read() == OK:
		var t := p.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var local := _local(p.get_node_name())
			var empty := p.is_empty()
			if not empty:
				stack.append(local)
			if member_depth == -1:
				if (local == "member" or local == "featureMember") and not empty:
					member_depth = stack.size()
					attrs = {}
					rings = []
					want = ""
			else:
				if local == "posList":
					dim = 2
					var d := p.get_named_attribute_value_safe("srsDimension")
					if d != "":
						dim = int(d)
					interior = stack.has("interior")
					want = "posList"
				elif not empty:
					want = local
		elif t == XMLParser.NODE_TEXT:
			if member_depth != -1 and want != "":
				var txt := p.get_node_data().strip_edges()
				if txt != "":
					if want == "posList":
						if not interior:
							rings.append(_ring_from_text(txt, dim, hint))
					else:
						attrs[want.to_lower()] = txt
		elif t == XMLParser.NODE_ELEMENT_END:
			var lname := _local(p.get_node_name())
			if member_depth != -1 and stack.size() == member_depth and (lname == "member" or lname == "featureMember"):
				var best := _largest_ring(rings)
				if best.size() >= 3:
					out.append({"ring": best, "attrs": attrs})
				member_depth = -1
			if stack.size() > 0:
				stack.remove_at(stack.size() - 1)
			want = ""
	return out


func _local(node_name: String) -> String:
	var i := node_name.rfind(":")
	return node_name.substr(i + 1) if i >= 0 else node_name


## Parses a gml:posList and decides the axis order by proximity to the requested area.
func _ring_from_text(text: String, dim: int, hint: Vector2) -> PackedVector2Array:
	var cleaned := text.replace("\n", " ").replace("\t", " ").replace("\r", " ")
	var nums := cleaned.split_floats(" ", false)
	var step := maxi(dim, 2)
	var a := PackedVector2Array()
	var i := 0
	while i + 1 < nums.size():
		a.append(Vector2(nums[i], nums[i + 1]))
		i += step
	if a.size() >= 2 and a[0].distance_to(a[a.size() - 1]) < 0.001:
		a.remove_at(a.size() - 1)
	if a.size() < 3:
		return PackedVector2Array()
	var swapped := PackedVector2Array()
	for v in a:
		swapped.append(Vector2(v.y, v.x))
	if a[0].distance_to(hint) <= swapped[0].distance_to(hint):
		return a
	return swapped


func _largest_ring(rings: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for r in rings:
		var ring: PackedVector2Array = r
		if ring.size() < 3:
			continue
		var area := 0.0
		for i in range(ring.size()):
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			area += a.x * b.y - b.x * a.y
		area = absf(area) * 0.5
		if area > best_area:
			best_area = area
			best = ring
	return best


# ------------------------------------------------------------------ diagnostics

## Lists feature types / layers the servers advertise, so constants above can be corrected.
func diagnose() -> String:
	var lines := PackedStringArray()
	var wfs: Dictionary = await http_get("%s?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetCapabilities" % settings.s("svc_wfs_url"))
	lines.append("WFS EGiB: HTTP %s" % wfs["code"])
	if wfs["ok"]:
		lines.append("  typy: " + ", ".join(_names_in(wfs["body"], 12)))
	var wms: Dictionary = await http_get("%s?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetCapabilities" % settings.s("svc_wms_url"))
	lines.append("WMS ORTO: HTTP %s" % wms["code"])
	if wms["ok"]:
		lines.append("  warstwy: " + ", ".join(_names_in(wms["body"], 12)))
	return "\n".join(lines)


func _names_in(body: PackedByteArray, max_count: int) -> PackedStringArray:
	var names := PackedStringArray()
	var re := RegEx.create_from_string("<(?:\\w+:)?Name>([^<]+)</(?:\\w+:)?Name>")
	var text := body.get_string_from_utf8()
	for m in re.search_all(text):
		names.append(m.get_string(1).strip_edges())
		if names.size() >= max_count:
			break
	return names
