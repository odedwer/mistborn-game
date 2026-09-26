extends SceneTree
## Loads an interior scene, drops a camera at its interior_spawn marker
## looking down the +z axis (matching the player's forward on entry), and
## saves a screenshot. Usage:
##   godot --rendering-driver vulkan -s res://tools/screenshot_interior.gd -- <scene> <out.png> [frames]

func _find_in_group(root: Node, group: StringName) -> Node3D:
	if root.is_in_group(group) and root is Node3D:
		return root
	for c in root.get_children():
		var found := _find_in_group(c, group)
		if found != null:
			return found
	return null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0])
	var inst := scene.instantiate()
	root.add_child(inst)
	var spawn := _find_in_group(inst, &"interior_spawn")
	var cam := Camera3D.new()
	var center: Vector3 = spawn.global_position if spawn != null else Vector3.ZERO
	var pos: Vector3 = center + Vector3(0, 2.4, 4.5)
	cam.look_at_from_position(pos, center + Vector3(0, -2.0, -8.0), Vector3.UP)
	root.add_child(cam)
	cam.current = true
	# A debug headlamp so a dim night interior is still checkable by eye;
	# this is the screenshot tool only, it never ships in the real scene.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 8.0
	lamp.omni_range = 60.0
	cam.add_child(lamp)
	# Build any MissionBackdrop skyline up front instead of waiting on its
	# background tasks for hundreds of (slow, software-rendered) frames.
	for bd in get_nodes_in_group(&"mission_backdrop"):
		bd.call("finish_now")
	var frames := int(args[2]) if args.size() > 2 else 60
	for i in frames:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(args[1])
	print("saved ", args[1])
	quit()
