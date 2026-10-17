class_name FacePreview
extends Control
## "What is on this wall": the picture the surface is sampled from, repeated around, with the window
## the surface shows (yellow). Moving, scaling or turning the picture moves the window in the
## opposite sense, so the user sees which part of the photo ends up where.

var texture: Texture2D
var window := PackedVector2Array()      # corners of the surface in picture space (1 = one picture)
var message := ""
var openings: Array = []     # [{rect: [x0,y0,x1,y1] in picture fractions, lit, type}]


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	clip_contents = true


func set_data(tex: Texture2D, poly: PackedVector2Array, msg := "", ops: Array = []) -> void:
	openings = ops
	texture = tex
	window = poly
	message = msg
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09))
	if texture == null or window.size() < 3:
		var f := get_theme_default_font()
		draw_string(f, Vector2(8, size.y * 0.5), message if message != "" else "Brak tekstury na tej powierzchni", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13, Color("#aab6c7"))
		return
	var lo := window[0]
	var hi := window[0]
	for q in window:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var span := (hi - lo).max(Vector2(0.05, 0.05))
	var margin := 0.12
	var k := minf(size.x / (span.x * (1.0 + 2.0 * margin)), size.y / (span.y * (1.0 + 2.0 * margin)))
	k = clampf(k, 4.0, 4000.0)                       # px per picture
	var centre := (lo + hi) * 0.5
	var to_px := func(p: Vector2) -> Vector2: return size * 0.5 + (p - centre) * k
	var first := Vector2(floor(centre.x - size.x * 0.5 / k), floor(centre.y - size.y * 0.5 / k))
	var last := Vector2(ceil(centre.x + size.x * 0.5 / k), ceil(centre.y + size.y * 0.5 / k))
	var cells := 0
	for ty in range(int(first.y), int(last.y)):
		for tx in range(int(first.x), int(last.x)):
			cells += 1
			if cells > 64:
				break
			var a: Vector2 = to_px.call(Vector2(tx, ty))
			draw_texture_rect(texture, Rect2(a, Vector2(k, k)), false, Color(1, 1, 1, 0.55))
			draw_rect(Rect2(a, Vector2(k, k)), Color(1, 1, 1, 0.25), false, 1.0)
			for o in openings:
				var r: Array = o["rect"]
				var col := Color(1.0, 0.6, 0.15) if bool(o["lit"]) else Color(0.35, 0.8, 1.0)
				draw_rect(Rect2(a + Vector2(float(r[0]), float(r[1])) * k, Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])) * k), col, false, 1.5)
	var poly_px := PackedVector2Array()
	for q in window:
		poly_px.append(to_px.call(q))
	draw_colored_polygon(poly_px, Color(1.0, 0.85, 0.2, 0.18))
	var closed := poly_px.duplicate()
	closed.append(poly_px[0])
	draw_polyline(closed, Color(1.0, 0.85, 0.2), 2.0)
