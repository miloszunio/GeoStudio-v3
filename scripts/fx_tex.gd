class_name FxTex
extends RefCounted
## Procedural sprite sheets for the particle effects (smoke puffs, flame frames, steam wisps, rain streaks, drops, sparks, glow, ripple).
## Generated once from noise, cached, and written next to the exported model (fx/<name>.png) so the simulator can use the very same pictures.
## Every sheet is RGBA, `grid` x `grid` square cells; colour carries the shading / heat, alpha carries the shape.

## name -> [cell size px, grid (cells per side)]
const SHEETS := {
	"smoke": [128, 4], "flame": [128, 4], "wisp": [128, 4], "mist": [128, 2],
	"streak": [64, 1], "drop": [64, 1], "spark": [64, 1], "glow": [64, 1], "ring": [128, 1],
}

static var _cache: Dictionary = {}


static func names() -> Array:
	return SHEETS.keys()


static func grid_of(tex: String) -> int:
	return int((SHEETS.get(tex, [64, 1]) as Array)[1])


## The sheet as an Image (cached).
static func image(tex: String) -> Image:
	if not SHEETS.has(tex):
		tex = "glow"
	if _cache.has(tex):
		return _cache[tex]
	var cell: int = int((SHEETS[tex] as Array)[0])
	var grid: int = int((SHEETS[tex] as Array)[1])
	var size := cell * grid
	var data := PackedByteArray()
	data.resize(size * size * 4)
	for gy in range(grid):
		for gx in range(grid):
			var frame := gy * grid + gx
			var cd := _cell(tex, cell, frame)
			for y in range(cell):
				var dst := ((gy * cell + y) * size + gx * cell) * 4
				for x in range(cell):
					var src := (y * cell + x) * 4
					data[dst] = cd[src]
					data[dst + 1] = cd[src + 1]
					data[dst + 2] = cd[src + 2]
					data[dst + 3] = cd[src + 3]
					dst += 4
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	_cache[tex] = img
	return img


static func texture(tex: String) -> ImageTexture:
	return ImageTexture.create_from_image(image(tex))


static func save_png(tex: String, path: String) -> int:
	var img := image(tex).duplicate() as Image
	if img.has_mipmaps():
		img.clear_mipmaps()
	return img.save_png(path)


static func _noise(seed_v: int, freq: float, octaves := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = 0.55
	n.frequency = freq
	n.seed = seed_v
	return n


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## One cell (cell x cell x RGBA bytes).
static func _cell(tex: String, cell: int, frame: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cell * cell * 4)
	var nz1 := _noise(1000 + frame * 17, 0.035)
	var nz2 := _noise(7000 + frame * 31, 0.09, 3)
	var inv := 2.0 / float(cell)
	for y in range(cell):
		for x in range(cell):
			var u := (float(x) + 0.5) * inv - 1.0      # -1 .. 1
			var v := 1.0 - (float(y) + 0.5) * inv      # -1 .. 1, up
			var rgba := _pixel(tex, u, v, nz1.get_noise_2d(x, y), nz2.get_noise_2d(x, y), frame, nz1)
			var i := (y * cell + x) * 4
			out[i] = int(clampf(rgba[0], 0.0, 1.0) * 255.0)
			out[i + 1] = int(clampf(rgba[1], 0.0, 1.0) * 255.0)
			out[i + 2] = int(clampf(rgba[2], 0.0, 1.0) * 255.0)
			out[i + 3] = int(clampf(rgba[3], 0.0, 1.0) * 255.0)
	return out


static func _pixel(tex: String, u: float, v: float, n1: float, n2: float, frame: int, nz: FastNoiseLite) -> Array:
	var r2 := u * u + v * v
	match tex:
		"smoke", "wisp", "mist":
			var soft := 1.0 if tex == "smoke" else 0.65
			# a puffy blob: radial falloff eaten by fbm noise, shaded from the upper left
			var body := clampf(1.0 - r2 * 1.15, 0.0, 1.0)
			var d := body * (0.55 + 0.95 * (n1 * 0.5 + 0.5)) + 0.18 * n2 * body - (0.12 if tex == "smoke" else 0.0)
			var a := _ss(0.12, 0.72 if tex == "smoke" else 0.95, d) * soft
			if tex == "wisp":
				# stretched curl: squash horizontally, drift with the noise
				var wv := absf(u + n1 * 0.55) * 1.6
				a = _ss(1.0, 0.0, wv + absf(v) * 0.55) * (0.5 + 0.5 * (n2 * 0.5 + 0.5)) * 0.7
			var lit := clampf(0.78 + 0.22 * (-u * 0.5 + v * 0.7) + 0.16 * n2, 0.0, 1.0)
			return [lit, lit, lit, a]
		"flame":
			# a teardrop licking upwards, distorted by the noise; hot white core -> orange rim
			var y := (v + 1.0) * 0.5                  # 0 bottom .. 1 top
			var sway := n1 * 0.42 * y + n2 * 0.12
			var xs := u - sway
			var w := 0.64 * pow(maxf(1.0 - y, 0.0), 0.6) * _ss(0.0, 0.16, y) + 0.015
			var dens := _ss(w, w * 0.15, absf(xs))
			dens *= 1.0 - _ss(0.82, 1.0, y)
			dens *= 0.75 + 0.45 * (n2 * 0.5 + 0.5)
			var core := _ss(0.0, 1.0, dens) * (1.0 - y) * (1.0 - absf(xs) / maxf(w, 0.02))
			var rgb := Color(1.0, 0.38 + 0.5 * clampf(core, 0.0, 1.0), 0.04 + 0.55 * pow(clampf(core, 0.0, 1.0), 1.7))
			return [rgb.r, rgb.g, rgb.b, clampf(dens, 0.0, 1.0)]
		"streak":
			# a falling rain streak: thin, brighter at the lower end
			var a := _ss(0.12, 0.0, absf(u)) * _ss(-1.0, -0.2, v) * (1.0 - _ss(0.85, 1.0, v)) * (0.35 + 0.65 * _ss(1.0, -1.0, v))
			return [0.86, 0.93, 1.0, a]
		"drop":
			# teardrop (round at the bottom, pointed at the top)
			var hw := 0.34 * (1.0 - _ss(-0.6, 1.0, v) * 0.85)
			var a := _ss(hw, hw * 0.5, absf(u)) * (1.0 - _ss(0.9, 1.0, v)) * _ss(-1.0, -0.55, v)
			return [0.9, 0.96, 1.0, a * 0.95]
		"spark":
			var core := exp(-r2 * 38.0)
			var cross := exp(-absf(u) * 22.0) * exp(-absf(v) * 2.4) + exp(-absf(v) * 22.0) * exp(-absf(u) * 2.4)
			var a := clampf(core + cross * 0.35, 0.0, 1.0)
			return [1.0, 0.82 + 0.18 * core, 0.45 + 0.55 * core, a]
		"ring":
			var r := sqrt(r2)
			var wobble := 1.0 + 0.06 * n1
			var a := exp(-pow((r - 0.78 * wobble) / 0.07, 2.0)) * _ss(1.0, 0.82, r)
			return [0.93, 0.97, 1.0, a * 0.9]
		_:      # glow
			var a := exp(-r2 * 5.5)
			return [1.0, 1.0, 1.0, a]
