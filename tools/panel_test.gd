extends SceneTree
## GPT-like sheet: pictures with thin red frames in random places -> PanelFrames / PanelSheet.
func _frame(img: Image, r: Rect2i, t: int) -> void:
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, t), Color8(255, 0, 0))
	img.fill_rect(Rect2i(r.position.x, r.end.y - t, r.size.x, t), Color8(255, 0, 0))
	img.fill_rect(Rect2i(r.position.x, r.position.y, t, r.size.y), Color8(255, 0, 0))
	img.fill_rect(Rect2i(r.end.x - t, r.position.y, t, r.size.y), Color8(255, 0, 0))

func _init() -> void:
	var info := {"main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "roof": "gable", "annexes": []}
	var img := Image.create(4096, 4096, false, Image.FORMAT_RGB8)
	img.fill(Color8(235, 235, 235))
	var boxes := [Rect2i(100, 120, 1500, 520), Rect2i(1800, 150, 1400, 480), Rect2i(150, 900, 700, 800), Rect2i(1100, 950, 650, 760), Rect2i(300, 2100, 1600, 700)]
	var fills := [Color8(180, 90, 60), Color8(60, 120, 90), Color8(90, 90, 160), Color8(150, 150, 60), Color8(110, 70, 60)]
	for i in range(boxes.size()):
		var b: Rect2i = boxes[i]
		img.fill_rect(b, fills[i])
		# red-ish brick noise that must NOT be mistaken for a frame
		for k in range(300):
			img.set_pixel(b.position.x + 20 + (k * 37) % (b.size.x - 40), b.position.y + 20 + (k * 53) % (b.size.y - 40), Color8(200, 40, 40))
		if i == 2 or i == 3:
			var tri := b.size.y / 3
			for y in range(b.position.y + 2, b.position.y + tri):
				var half := int(float(b.size.x) * 0.5 * float(y - b.position.y) / float(tri))
				img.fill_rect(Rect2i(b.position.x + 2, y, b.size.x / 2 - half, 1), Color8(128, 128, 128))
				img.fill_rect(Rect2i(b.position.x + b.size.x / 2 + half, y, b.size.x / 2 - half - 2, 1), Color8(128, 128, 128))
		_frame(img, b, 2 + (i % 2))
	var t := Time.get_ticks_msec()
	var found := PanelFrames.detect(img)
	print("frames ", found.size(), " in ", Time.get_ticks_msec() - t, " ms")
	for f in found:
		print("  ", f["outer"])
	var asg := PanelSheet.detect_and_assign(img, info)
	var s := []
	for a in asg:
		s.append(a["code"])
	print("codes ", s)
	var res := PanelSheet.build(img, asg, info)
	print("found ", res["found"], " missing ", res["missing"], " ppm ", res["layout"].get("ppm"), " fill ", res["layout"].get("fill"))
	(res["image"] as Image).save_png("/tmp/claude-0/panel_out.png")
	img.save_png("/tmp/claude-0/panel_in.png")
	quit()
