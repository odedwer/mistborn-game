extends SceneTree
## Renders a scene for N frames and saves a screenshot. Needs a display
## (use xvfb-run on headless machines):
##   godot --rendering-driver opengl3 -s res://tools/screenshot.gd -- <scene> <out.png> [frames]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0])
	root.add_child(scene.instantiate())
	var frames := int(args[2]) if args.size() > 2 else 120
	for i in frames:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(args[1])
	print("saved ", args[1])
	quit()
