extends SceneTree
## Character portrait shots: each scene side by side, full body and a head
## close-up, under a moonlit night key + warm lantern fill (or --day).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --resolution 1600x900 -s res://tools/char_portrait.gd -- \
##     --scenes=res://a.tscn,res://b.tscn --out=/tmp/p.png [--close] [--day] [--anim=idle] [--t=0.5]

var scenes: PackedStringArray = []
var out := "user://portrait.png"
var close := false
var day := false
var anim := "idle"
var t := 0.5
var yaw := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenes="):
			scenes = a.substr(9).split(",")
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--close":
			close = true
		elif a == "--day":
			day = true
		elif a.begins_with("--anim="):
			anim = a.substr(7)
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--t="):
			t = float(a.substr(4))
	_run.call_deferred()


func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.065) if not day else Color(0.55, 0.52, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.4) if not day else Color(0.6, 0.58, 0.55)
	env.ambient_light_energy = 0.5 if not day else 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.2
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.4 if not day else 2.2
	key.light_color = Color(0.75, 0.82, 1.0) if not day else Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	w.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.2, 2.0, 2.4)
	fill.omni_range = 6.0
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 0.9 if not day else 0.4
	w.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.18, 0.17, 0.16)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	w.add_child(floor_mi)
	var n := scenes.size()
	var spacing := 1.1
	var models: Array[Node3D] = []
	for i in n:
		var c := (load(scenes[i]) as PackedScene).instantiate() as Node3D
		c.position = Vector3((i - (n - 1) * 0.5) * spacing, 0, 0)
		c.rotation_degrees.y = yaw
		w.add_child(c)
		models.append(c)
		for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
			mi.visible = true
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 30.0 if not close else 22.0
	if close:
		var cx := (n - 1) * 0.5 * spacing
		cam.position = Vector3(cx + 0.35, 1.78, 0.85)
		cam.look_at(Vector3(cx, 1.72, 0))
	else:
		cam.position = Vector3(0, 1.15, 3.6 + 1.2 * (n - 1))
		cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	for f in 3:
		await process_frame
	for c in models:
		for ap: AnimationPlayer in c.find_children("*", "AnimationPlayer", true, false):
			var nm := anim if ap.has_animation(anim) else anim + "-loop"
			if ap.has_animation(nm):
				ap.play(nm)
				ap.seek(t, true)
				ap.pause()
		for at: AnimationTree in c.find_children("*", "AnimationTree", true, false):
			at.active = false
	for f in 12:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()
