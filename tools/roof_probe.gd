extends SceneTree
func _initialize() -> void:
	var a := TextureAtlas.new()
	a.load_source("/tmp/claude-0/atlas_real.png", {}, true)
	print(a.sheet_mode)
	for k in a.regions.keys():
		var r: Dictionary = a.regions[k]
		var im: Image = r["img"]
		print(k, " ", r["role"], " rect ", r["rect"], " img ", im.get_size(), " ratio ", r["roof_ratio"])
		if r["role"].begins_with("facade"):
			im.save_png("/tmp/claude-0/shots/%s.png" % k)
	quit()
