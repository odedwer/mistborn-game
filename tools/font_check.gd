extends SceneTree
## Renders the HUD's dialogue/hint line in the UI theme at a few sizes and
## saves a PNG, to check small-size glyph rendering (e.g. "el" merging into
## "d" at 720p). Needs a display (xvfb-run) and a renderer:
##   godot --rendering-driver opengl3 --resolution 1280x720 -s res://tools/font_check.gd -- out.png


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://font_check.png"
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = load("res://src/ui/theme.tres")
	root.add_child(bg)
	root.add_child(ui)
	var y := 20.0
	for size in [14, 16, 18, 20, 24]:
		var l := Label.new()
		l.text = "%d: Kelsier: \"Feel that? That's steel in your blood. Burn it.\" hell, well, eel" % size
		l.add_theme_font_size_override("font_size", size)
		l.position = Vector2(20, y)
		ui.add_child(l)
		y += size * 2.2
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
