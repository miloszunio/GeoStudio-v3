extends SceneTree
## A GPT-like canvas: textured pictures in thin red frames at free places.  OUT=dir godot --headless --script res://tools/gen_canvas.gd
func _frame(img: Image, r: Rect2i, t: int) -> void:
	var red := Color8(255, 0, 0)
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, t), red)
	img.fill_rect(Rect2i(r.position.x, r.end.y - t, r.size.x, t), red)
	img.fill_rect(Rect2i(r.position.x, r.position.y, t, r.size.y), red)
	img.fill_rect(Rect2i(r.end.x - t, r.position.y, t, r.size.y), red)

func _wall(img: Image, r: Rect2i, col: Color, cols: int, rows: int, gable_h := 0) -> void:
	img.fill_rect(r, col)
	for y in range(r.position.y, r.end.y, 14):                      # brick courses
		img.fill_rect(Rect2i(r.position.x, y, r.size.x, 2), col.darkened(0.25))
	var body_h := r.size.y - gable_h
	var ww := int(r.size.x / float(cols * 2 + 1))
	var wh := int(body_h / float(rows * 2 + 1) * 1.1)
	for ry in range(rows):
		for cx in range(cols):
			var x := r.position.x + ww + cx * ww * 2
			var y := r.position.y + gable_h + int(body_h * (0.12 + 0.4 * ry))
			img.fill_rect(Rect2i(x, y, ww, wh), Color8(60, 80, 110))
			img.fill_rect(Rect2i(x + 3, y + 3, ww - 6, wh - 6), Color8(150, 190, 220))
	if gable_h > 0:
		var grey := Color8(128, 128, 128)
		for y in range(r.position.y, r.position.y + gable_h):
			var half := int(float(r.size.x) * 0.5 * float(y - r.position.y) / float(gable_h))
			img.fill_rect(Rect2i(r.position.x, y, r.size.x / 2 - half, 1), grey)
			img.fill_rect(Rect2i(r.position.x + r.size.x / 2 + half, y, r.size.x / 2 - half, 1), grey)

func _init() -> void:
	var img := Image.create(4096, 4096, false, Image.FORMAT_RGB8)
	img.fill(Color8(255, 255, 255))
	# the sample building is 10 x 6 m: 1 m = 150 px here, but placed freely
	var s1 := Rect2i(120, 140, 1500, 560)
	var s2 := Rect2i(1900, 260, 1500, 560)
	var s3 := Rect2i(160, 1000, 900, 1150)
	var s4 := Rect2i(1300, 1000, 900, 1150)
	var s5 := Rect2i(2500, 1100, 1500, 700)
	_wall(img, s1, Color8(176, 96, 66), 5, 2)
	_wall(img, s2, Color8(170, 100, 70), 4, 2)
	_wall(img, s3, Color8(180, 100, 70), 2, 2, 380)
	_wall(img, s4, Color8(172, 98, 68), 2, 2, 380)
	img.fill_rect(s5, Color8(90, 60, 60))
	for y in range(s5.position.y, s5.end.y, 16):
		img.fill_rect(Rect2i(s5.position.x, y, s5.size.x, 3), Color8(60, 40, 40))
	for r in [s1, s2, s3, s4, s5]:
		_frame(img, r, 2)
	img.save_png(OS.get_environment("OUT").path_join("canvas.png"))
	quit()
