extends SceneTree
## Tagged sheet in random places and sizes -> TagSheet.assemble.  godot --headless --script res://tools/tag_test.gd
func _init() -> void:
	var info := {"main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "roof": "gable", "annexes": []}
	print("start")
	var lay := GptPrompt.layout(info)
	print("layout ok ", lay["ppm"])
	var img := Image.create(2048, 2048, false, Image.FORMAT_RGB8)
	img.fill(Color8(200, 200, 200))
	var boxes := {"S1": Rect2i(60, 40, 900, 300), "S2": Rect2i(1000, 100, 800, 260), "S3": Rect2i(100, 500, 420, 520), "S4": Rect2i(700, 600, 400, 500), "S5": Rect2i(200, 1300, 1000, 400)}
	var fills := {"S1": Color8(180, 90, 60), "S2": Color8(60, 120, 90), "S3": Color8(90, 90, 160), "S4": Color8(150, 150, 60), "S5": Color8(110, 70, 60)}
	for code in boxes.keys():
		var b: Rect2i = boxes[code]
		img.fill_rect(b, TagSheet.TAGS[code])
		img.fill_rect(b.grow(-14), fills[code])
	var t := Time.get_ticks_msec()
	var fr := TagSheet.find_frames(img)
	print("frames ", fr.keys(), " in ", Time.get_ticks_msec() - t, " ms")
	for c in fr.keys():
		print(c, " inner ", fr[c]["inner"], " expected ~", (boxes[c] as Rect2i).grow(-14))
	var a := TagSheet.assemble(img, lay)
	print("found ", a["found"], " missing ", a["missing"], " notes ", a["notes"])
	(a["image"] as Image).save_png("/tmp/claude-0/tag_out.png")
	quit()
