extends SceneTree
## Fast open-world preview shots (opengl3, needs a display; use xvfb-run):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --resolution 1280x720 -s res://tools/preview.gd -- \
##     --shot=x,y,z,yaw,pitch,out.png[;x,y,z,yaw,pitch,out2.png...] \
##     [--time=<hour>] [--radius=140] [--far=500] [--frames=6]
##
## Streams only the chunks within `--radius` of each pose (synchronously), no
## far-LOD skyline, no marker index, no navmesh bakes, no crowd/enemies, low
## mist, and a short camera far plane, so a district shot takes seconds, not
## minutes (see docs/PERFORMANCE.md). Yaw/pitch in degrees (yaw 0 looks -Z,
## -90 looks +X; pitch -90 looks straight down). `--time` is read by the
## TimeOfDay autoload (22 = night, 11 = day). Landmarks (keeps, Kredik Shaw)
## within the radius stream in like chunks.

var radius := 140.0
var far := 500.0
var frames := 6
var shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--radius="):
			radius = float(a.substr(9))
		elif a.begins_with("--far="):
			far = float(a.substr(6))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--shot="):
			for s in a.substr(7).split(";"):
				var p := s.split(",")
				if p.size() >= 6:
					shots.append([Vector3(float(p[0]), float(p[1]), float(p[2])), float(p[3]), float(p[4]), p[5]])
	if shots.is_empty():
		push_error("preview: pass --shot=x,y,z,yaw,pitch,out.png")
		quit(1)
		return
	# Never hang a batch job on a script error.
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("preview: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	# Untyped on purpose: this script compiles before the autoloads exist, so
	# it must not reference world classes (they use autoload globals) directly.
	var world: Node3D = (load("res://src/world/luthadel.tscn") as PackedScene).instantiate()
	world.build_far_lod = false
	world.build_marker_index = false
	world.initial_radius = -1.0   # nothing around the (unused) spawn
	world.load_radius = radius
	world.unload_radius = radius + 80.0
	world.mist_quality = 0
	root.add_child(world)
	world.streamer.max_bakes = 0
	var cam := Camera3D.new()
	cam.far = far
	root.add_child(cam)
	cam.make_current()
	print("preview: world ready in %d ms" % (Time.get_ticks_msec() - t0))
	for s: Array in shots:
		var t1 := Time.get_ticks_msec()
		cam.global_position = s[0]
		cam.rotation = Vector3(deg_to_rad(s[2]), deg_to_rad(s[1]), 0.0)
		world.streamer.call("load_now", s[0], radius)
		# Static set dressing that the game scene would spawn (sentry guards).
		(load("res://src/world/sentry_posts.gd") as GDScript).call("populate", get_nodes_in_group(&"sentry_post"))
		for i in frames:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(s[3])
		print("preview: %s in %d ms (%d units, %d prims)" % [s[3], Time.get_ticks_msec() - t1,
				world.streamer.call("unit_count"),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	print("preview: total %d ms" % (Time.get_ticks_msec() - t0))
	quit()
