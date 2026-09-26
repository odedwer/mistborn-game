extends SceneTree
## Screenshot of the full game at a route location (needs a display; see
## docs/PERFORMANCE.md for the lavapipe/xvfb command line):
##   godot --rendering-driver vulkan -s res://tools/shot.gd -- <location> <out.png> [frames] [look_at] [steel]
## <location>/<look_at>: spawn, an objective id (cp_2, keep_courtyard, ...)
## or "x,y,z". Chunks around the location are streamed in synchronously.


func _initialize() -> void:
	_run.call_deferred()


func _pos(world: Node, id: String) -> Vector3:
	if id == "spawn":
		return world.call("spawn_position")
	if id.count(",") == 2:
		var c := id.split(",")
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	for e: Dictionary in world.call("get_marker_data", &"objective_point"):
		if str((e["meta"] as Dictionary).get("objective_id", "")) == id:
			return e["position"]
	return Vector3.ZERO


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	# Shots are of the vertical slice (the story itself opens indoors, Act I).
	var mission := OS.get_environment("SHOT_MISSION")
	(load("res://tests/story_jump.gd") as GDScript).call("jump_to",
			StringName(mission if mission != "" else "mistwalk_to_keep_venture"))
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var world: Node = game.get_node(^"World")
	var player: Node3D = get_first_node_in_group(&"player")
	var pos := _pos(world, args[0])
	world.get("streamer").call("load_now", pos, 220.0)
	player.global_position = pos + Vector3.UP * 0.3
	var frames := int(args[2]) if args.size() > 2 else 30
	if args.size() > 3 and args[3] != "":
		var t := _pos(world, args[3])
		var d := t - pos
		player.get("camera_rig").set("yaw", atan2(-d.x, -d.z))
	if args.size() > 4 and args[4] == "steel":
		var al: Node = player.get("allomancer")
		al.call("set_reserve", 0, 100.0)
		al.call("set_burning", 0, true)
	player.get("camera_rig").call("snap")
	for i in frames:
		await process_frame
	# Report floating/sunk enemies: feet vs the ground right under them.
	var space := player.get_world_3d().direct_space_state
	for e: Node3D in get_nodes_in_group(&"enemy"):
		if e.global_position.distance_to(pos) > 60.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP * 1.0, e.global_position + Vector3.DOWN * 5.0, 1)
		var hit := space.intersect_ray(q)
		var gap: float = e.global_position.y - (hit["position"] as Vector3).y if not hit.is_empty() else INF
		print("enemy %s at %s, feet-ground gap %.2f m" % [e.name, e.global_position, gap])
	for g in OS.get_environment("SHOT_HIDE").split(",", false):
		for n in get_nodes_in_group(StringName(g)):
			if n is Node3D:
				(n as Node3D).visible = false
	if OS.get_environment("SHOT_BILINEAR") != "":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		for i in 5:
			await process_frame
	if OS.get_environment("SHOT_NO_TENDRIL_VOLUME") != "":
		world.get("mist").get("_tendrils").set("use_volume", false)
		for i in 3:
			await process_frame
	if OS.get_environment("SHOT_NOGLOW") != "":
		var we := get_first_node_in_group(&"world_environment") as WorldEnvironment
		if we != null:
			we.environment.glow_enabled = false
	if OS.get_environment("SHOT_NOFOGLIGHT") != "":
		for l: Node in root.find_children("*", "Light3D", true, false):
			if not (l is DirectionalLight3D):
				(l as Light3D).light_volumetric_fog_energy = 0.0
	for path in OS.get_environment("SHOT_HIDE_PATH").split(",", false):
		var hn := root.get_node_or_null(NodePath(path))
		if hn is Node3D:
			(hn as Node3D).visible = false
	await process_frame
	await process_frame
	if OS.get_environment("SHOT_BONES") != "":
		for sk: Node in root.find_children("*", "Skeleton3D", true, false):
			var skel := sk as Skeleton3D
			var bad: Array = []
			for b in skel.get_bone_count():
				var t := skel.get_bone_global_pose(b)
				if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()) \
						or absf(t.basis.determinant()) < 1e-6:
					bad.append("%s det %.3g" % [skel.get_bone_name(b), t.basis.determinant()])
			if not bad.is_empty():
				print("bad bones in %s: %s" % [skel.get_path(), bad])
	if OS.get_environment("SHOT_NODES") != "":
		for n: Node in root.find_children("*", "VisualInstance3D", true, false):
			var g := n as VisualInstance3D
			if g.is_visible_in_tree() and g.global_position.distance_to(pos) < 40.0 and not str(g.get_path()).contains("/Units/"):
				print("geom %s (%s) at %s" % [g.get_path(), g.get_class(), g.global_position])
		for n: Node in root.find_children("*", "VisualInstance3D", true, false):
			var g := n as VisualInstance3D
			if g.is_visible_in_tree() and g.global_position.distance_to(pos) < 40.0 and str(g.get_path()).contains("/Units/") \
					and not (g is MeshInstance3D and g.get_parent() is RigidBody3D) \
					and not (g.get_parent() is Node3D and g.get_parent().get_parent() == world.get("units_root")) \
					and not str(g.get_path()).contains("Skeleton3D"):
				print("unit geom %s (%s) at %s" % [g.get_path(), g.get_class(), g.global_position])
	if OS.get_environment("SHOT_LIGHTS") != "":
		var cam := root.get_viewport().get_camera_3d()
		for l: Node in root.find_children("*", "Light3D", true, false):
			var ln := l as Light3D
			if ln is DirectionalLight3D:
				continue
			if not cam.is_position_behind(ln.global_position):
				print("  screen %s visible %s" % [cam.unproject_position(ln.global_position), ln.is_visible_in_tree()])
			if ln.global_position.distance_to(pos) < 25.0:
				print("light %s at %s energy %.2f fog %.2f" % [ln.get_path(), ln.global_position, ln.light_energy, ln.light_volumetric_fog_energy])
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(args[1])
	print("saved ", args[1], " at ", player.global_position)
	quit()
