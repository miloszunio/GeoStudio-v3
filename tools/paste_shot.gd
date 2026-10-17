extends SceneTree
## Paste window on a GPT-like sheet that auto-slicing does not take for a template. SHOT_DIR=/tmp/x
func _initialize() -> void:
	_run()

func _run() -> void:
	root.size = Vector2i(1500, 900)
	var main: Control = (load("res://main.tscn") as PackedScene).instantiate()
	main.project_required = false
	root.add_child(main)
	for _i in 15: await process_frame
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://textures/samples/kamienica_ceglana.png"))
	var sheet := Image.create(4096, 4096, false, Image.FORMAT_RGB8)
	sheet.fill(Color8(128, 128, 128))
	var spots := [Vector2i(30, 40), Vector2i(2090, 10), Vector2i(60, 1100), Vector2i(2100, 1060), Vector2i(20, 2120)]
	for sp in spots:
		var p := src.duplicate()
		p.resize(1900, 940)
		sheet.blit_rect(p, Rect2i(0, 0, 1900, 940), sp)
	var path := "/tmp/claude-0/gptlike.png"
	sheet.save_png(path)
	main._create_sample_building()
	main.settings.set_value("tex_slice_mode", "sheet")
	main.settings.set_value("tex_source", path)
	for _i in 30: await process_frame
	print("template after load: ", main.atlas.is_template)
	main.gpt._show_gpt_paste()
	for _i in 10: await process_frame
	print("template after paste window: ", main.atlas.is_template, "  status: ", main.status_label.text)
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("paste.png"))
	main.atlasflow._show_slice_preview()
	for _i in 10: await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("preview.png"))
	quit()
