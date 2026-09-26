extends Node3D
## Character lineup / preview scene.
##
## Run: godot res://scenes/test/character_lineup.tscn -- [options]
##   --only=<id>            show a single character (any id in GROUPS, e.g. vin, kelsier, noble_woman_2)
##   --group=<name>         enemies (default), crew, gentry, folk (crowd variants), all
##   --variants=<n>         with --only: n randomize_variant() copies of a base model (crowd check)
##   --anim=<name>          play this animation on everyone (AnimationPlayer, tree disabled)
##   --t=<seconds>          freeze the animation at this time (with --anim)
##   --action=<name>        call play_action(name) through the CharacterModel API after 0.5 s
##   --moving               characters run around a circle via set_locomotion (cloak dynamics)
##   --cam=front|back|side|34|top
##   --zoom=head            close-up of the head (with --only)
##   --light=night|studio
##   --shot=<png path>      save a screenshot after --frames frames and quit
##   --frames=<n>           frames to wait before the screenshot (default 20)
##   --quit=<seconds>       quit after this many seconds (headless smoke test)

const IDS: Array[StringName] = [&"vin", &"guard", &"hazekiller", &"thug", &"coinshot", &"inquisitor"]
const GROUPS := {
	"enemies": [&"vin", &"guard", &"hazekiller", &"thug", &"coinshot", &"inquisitor"],
	"crew": [&"kelsier", &"dockson", &"breeze", &"ham", &"clubs", &"spook", &"sazed", &"marsh"],
	"gentry": [&"vin_gown", &"noble_man_1", &"noble_woman_1", &"noble_man_2", &"noble_woman_2",
		&"noble_man_3", &"noble_woman_3"],
	"folk": [&"obligator", &"obligator_2", &"skaa_man", &"skaa_woman", &"skaa_man", &"skaa_woman",
		&"skaa_man", &"skaa_woman"],
}

var opts := {}
var models: Array[CharacterModel] = []
var _time := 0.0
var _frames := 0
var _camera: Camera3D
var _moving := false
var _fired := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_moving = opts.has("moving")
	_build_environment(opts.get("light", "night"))
	var ids: Array[StringName] = IDS
	var group: String = opts.get("group", "enemies")
	if group == "all":
		ids = []
		for g: String in ["enemies", "crew", "gentry"]:
			for id: StringName in GROUPS[g]:
				ids.append(id)
	elif GROUPS.has(group):
		ids.assign(GROUPS[group])
	if opts.has("only"):
		ids = [StringName(opts["only"])]
		for i in int(opts.get("variants", "1")) - 1:
			ids.append(StringName(opts["only"]))
	var spacing := 1.25
	for i in ids.size():
		var ps: PackedScene = load("res://assets/models/characters/%s.tscn" % ids[i])
		var m: CharacterModel = ps.instantiate()
		if group == "folk" and i >= 4 or opts.has("variants") and i > 0:
			m.randomize_variant(i * 7919)
		add_child(m)
		m.position = Vector3((i - (ids.size() - 1) * 0.5) * spacing, 0, 0)
		models.append(m)
	await get_tree().process_frame
	if opts.has("anim"):
		for m in models:
			m.animation_tree.active = false
			m.animation_player.play(StringName(opts["anim"]))
			if opts.has("t"):
				m.animation_player.seek(float(opts["t"]), true)
				m.animation_player.pause()
	_setup_camera(ids.size())


func _build_environment(mode: String) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sun := DirectionalLight3D.new()
	add_child(sun)
	if mode == "studio":
		env.background_color = Color(0.32, 0.34, 0.38)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.56, 0.6)
		env.ambient_light_energy = 0.7
		sun.rotation_degrees = Vector3(-35, -20, 0)
		sun.light_energy = 1.6
	else:
		env.background_color = Color(0.05, 0.055, 0.07)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.25, 0.28, 0.36)
		env.ambient_light_energy = 0.55
		env.fog_enabled = true
		env.fog_light_color = Color(0.5, 0.52, 0.56)
		env.fog_density = 0.05
		sun.rotation_degrees = Vector3(-40, -35, 0)
		sun.light_color = Color(0.62, 0.7, 0.9)
		sun.light_energy = 0.55
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.65, 0.35)
		lamp.light_energy = 2.5
		lamp.omni_range = 9.0
		lamp.position = Vector3(3.0, 2.8, 2.5)
		add_child(lamp)
	sun.shadow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.16, 0.17)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)


func _setup_camera(count: int) -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.fov = 40.0
	var dist := 2.6 if count == 1 else 8.8 * maxf(1.0, count / 6.0)
	var h := 1.05 if count == 1 else 1.1
	var cam: String = opts.get("cam", "34")
	var dir := Vector3(0, 0, 1)  # models face +Z, camera looks from the front
	match cam:
		"front":
			dir = Vector3(0, 0, 1)
		"back":
			dir = Vector3(0, 0, -1)
		"side":
			dir = Vector3(1, 0, 0)
		"34":
			dir = Vector3(0.55, 0, 0.85).normalized()
		"top":
			dir = Vector3(0, 0.8, 0.6).normalized()
	var target := Vector3(0, h * (0.9 if count == 1 else 1.0), 0)
	if count == 1 and models.size() == 1:
		target.y = models[0].get_model_height() * 0.55
		dist = models[0].get_model_height() * 1.75
	if opts.has("dist"):
		dist = float(opts["dist"])
	if opts.has("zoom") and models.size() == 1:
		# frame the head: --zoom=head
		target.y = models[0].get_model_height() - 0.14
		dist = 0.75
	_camera.position = target + dir * dist + Vector3(0, 0.15 if not opts.has("zoom") else 0.0, 0)
	_camera.look_at(target, Vector3.UP)


func _process(delta: float) -> void:
	_time += delta
	_frames += 1
	if _moving:
		for i in models.size():
			var m := models[i]
			var r := 2.0
			var w := 1.6
			var a := _time * w + i * TAU / models.size()
			var prev := m.position
			m.position = Vector3(cos(a) * r, 0, sin(a) * r)
			var vel := (m.position - prev) / maxf(delta, 1e-4)
			if vel.length() > 0.01:
				m.rotation.y = atan2(vel.x, vel.z)  # CharacterModel roots face +Z
			m.set_locomotion(r * w, true, 0.0)
	elif not opts.has("anim"):
		for m in models:
			m.set_locomotion(float(opts.get("speed", "0")), true, 0.0)
	if opts.has("action") and not _fired and _time > 0.5:
		_fired = true
		for m in models:
			m.play_action(StringName(opts["action"]))
	if opts.has("aim"):
		for m in models:
			m.set_aim(Vector3(1, 0.4, -1))
	if opts.has("shot") and _frames == int(opts.get("frames", "20")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(opts["shot"])
		print("saved ", opts["shot"])
		get_tree().quit()
	if opts.has("quit") and _time > float(opts["quit"]):
		print("lineup ran %.1fs, %d frames" % [_time, _frames])
		get_tree().quit()
