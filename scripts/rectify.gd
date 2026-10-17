class_name Rectify
extends RefCounted
## Perspective correction: a quadrilateral cut out of a photo (any four corners) becomes a flat
## rectangle. Used to straighten a wall photographed at an angle, so that windows keep their
## real shape and the picture can be laid on the model without a skew.

## Square-to-quad projective map (Heckbert). quad = [p0, p1, p2, p3] for the unit-square corners
## (0,0), (1,0), (1,1), (0,1), i.e. top left, top right, bottom right, bottom left of the picture.
## Returns [a, b, c, d, e, f, g, h]:  x = (a u + b v + c) / (g u + h v + 1),  y = (d u + e v + f) / (g u + h v + 1)
static func square_to_quad(q: Array) -> Array:
	var x0: float = q[0].x
	var y0: float = q[0].y
	var x1: float = q[1].x
	var y1: float = q[1].y
	var x2: float = q[2].x
	var y2: float = q[2].y
	var x3: float = q[3].x
	var y3: float = q[3].y
	var dx1 := x1 - x2
	var dx2 := x3 - x2
	var dx3 := x0 - x1 + x2 - x3
	var dy1 := y1 - y2
	var dy2 := y3 - y2
	var dy3 := y0 - y1 + y2 - y3
	if absf(dx3) < 1e-9 and absf(dy3) < 1e-9:
		return [x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0.0, 0.0]
	var den := dx1 * dy2 - dx2 * dy1
	if absf(den) < 1e-12:
		return []
	var g := (dx3 * dy2 - dx2 * dy3) / den
	var h := (dx1 * dy3 - dx3 * dy1) / den
	return [x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h]


## Source point for the unit-square coordinate (u, v).
static func map_point(m: Array, u: float, v: float) -> Vector2:
	var w := float(m[6]) * u + float(m[7]) * v + 1.0
	return Vector2((float(m[0]) * u + float(m[1]) * v + float(m[2])) / w, (float(m[3]) * u + float(m[4]) * v + float(m[5])) / w)


## Straightened picture of `quad` (pixel coordinates in `src`: top left, top right, bottom right, bottom left).
static func warp(src: Image, quad: Array, out_w: int, out_h: int) -> Image:
	out_w = clampi(out_w, 8, 4096)
	out_h = clampi(out_h, 8, 4096)
	var m := square_to_quad(quad)
	if m.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var sw := img.get_width()
	var sh := img.get_height()
	var data := img.get_data()
	var out := PackedByteArray()
	out.resize(out_w * out_h * 4)
	var a: float = m[0]
	var b: float = m[1]
	var c: float = m[2]
	var d: float = m[3]
	var e: float = m[4]
	var f: float = m[5]
	var g: float = m[6]
	var hh: float = m[7]
	var o := 0
	for j in range(out_h):
		var v := (float(j) + 0.5) / float(out_h)
		for i in range(out_w):
			var u := (float(i) + 0.5) / float(out_w)
			var w := g * u + hh * v + 1.0
			var sx := (a * u + b * v + c) / w - 0.5
			var sy := (d * u + e * v + f) / w - 0.5
			var x0 := clampi(int(floor(sx)), 0, sw - 1)
			var y0 := clampi(int(floor(sy)), 0, sh - 1)
			var x1 := mini(x0 + 1, sw - 1)
			var y1 := mini(y0 + 1, sh - 1)
			var fx := clampf(sx - float(x0), 0.0, 1.0)
			var fy := clampf(sy - float(y0), 0.0, 1.0)
			var p00 := (y0 * sw + x0) * 4
			var p10 := (y0 * sw + x1) * 4
			var p01 := (y1 * sw + x0) * 4
			var p11 := (y1 * sw + x1) * 4
			var w00 := (1.0 - fx) * (1.0 - fy)
			var w10 := fx * (1.0 - fy)
			var w01 := (1.0 - fx) * fy
			var w11 := fx * fy
			for ch in range(3):
				out[o + ch] = int(data[p00 + ch] * w00 + data[p10 + ch] * w10 + data[p01 + ch] * w01 + data[p11 + ch] * w11 + 0.5)
			out[o + 3] = 255
			o += 4
	return Image.create_from_data(out_w, out_h, false, Image.FORMAT_RGBA8, out)
