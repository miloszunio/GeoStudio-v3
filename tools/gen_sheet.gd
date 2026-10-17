extends SceneTree
## Synthetic sheet drawn in the computed frames:  OUT=dir godot --headless --script res://tools/gen_sheet.gd
func _init() -> void:
	var info := {"main": {"len": 10.0, "wid": 6.0, "wall_h": 3.0, "roof_h": 2.0}, "roof": "gable", "annexes": []}
	var lay := GptPrompt.layout(info)
	var img := Image.create(4096, 4096, false, Image.FORMAT_RGB8)
	img.fill(Color8(128, 128, 128))
	for code in lay["pictures"].keys():
		var p: Array = lay["pictures"][code]
		var base := Color8(170, 110, 80) if code != "S5" else Color8(110, 70, 60)
		for y in range(int(p[1]), int(p[1]) + int(p[3])):
			for x in range(int(p[0]), int(p[0]) + int(p[2])):
				var wob := 12 * (((x / 40) + (y / 24)) % 2)
				if str(lay["kinds"][code]) == "gable":
					var tri_h: int = int(p[3]) - int(lay["eave_px"][code])
					var row := y - int(p[1])
					if row < tri_h and absf(float(x - int(p[0])) - float(p[2]) * 0.5) > float(p[2]) * 0.5 * float(row) / float(tri_h):
						continue
				img.set_pixel(x, y, Color8(base.r8 + wob, base.g8 + wob, base.b8 + wob))
	var out := OS.get_environment("OUT")
	img.save_png(out.path_join("sheet.png"))
	var f := FileAccess.open(out.path_join("layout.json"), FileAccess.WRITE)
	f.store_string(SheetLayout.to_json(lay))
	f.close()
	quit()
