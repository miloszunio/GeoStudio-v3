extends SceneTree
## Writes every FxTex sheet (over a dark grey background) to $SHOT_DIR/fx_<name>.png and prints the generation time.
func _initialize() -> void:
	var out := OS.get_environment("SHOT_DIR")
	for n in FxTex.names():
		var t0 := Time.get_ticks_msec()
		var img := FxTex.image(str(n)).duplicate() as Image
		print("RESULT ", n, " ", img.get_size(), " ", Time.get_ticks_msec() - t0, " ms")
		var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(Color(0.16, 0.18, 0.22, 1.0))
		img.clear_mipmaps()
		bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		bg.save_png(out.path_join("fx_%s.png" % n))
	quit()
