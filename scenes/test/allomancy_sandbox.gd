extends Node3D
## Self-contained allomancy test level: a night courtyard with towers,
## lamp posts (anchored), loose metal crates, target dummies and a field of
## hidden rivets for steel-sight stress tests. Everything is built in code.
##
## Command-line options (after `--`):
##   --screenshot=<path>  burn steel, wait `--frames` frames, save a PNG, quit
##   --frames=<n>         frames to wait before the screenshot (default 90)
##   --demo               burn steel and fly around automatically (feel check)

const PLAYER_SCENE := preload("res://src/player/player.tscn")

## Number of hidden anchored rivets (steel-sight stress test).
@export var stress_metals := 600
@export var lamp_post_metal_mass := 60.0
@export var crate_metal_mass := 40.0

var player: Player
var _hud: Label
var _screenshot_path := ""
var _screenshot_frames := 90
var _frame := 0
var _demo := false
var _dummies: Array[Health] = []
var _concrete: StandardMaterial3D
var _stone: StandardMaterial3D
var _iron: StandardMaterial3D
var _wood: StandardMaterial3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--frames="):
			_screenshot_frames = int(arg.get_slice("=", 1))
		elif arg == "--demo":
			_demo = true
	_make_materials()
	_build_environment()
	_build_level()
	_spawn_player()
	_build_hud()
	if _screenshot_path != "" or _demo:
		player.allomancer.set_burning(Metal.Type.STEEL, true)
		player.allomancer.set_burning(Metal.Type.IRON, true)


func _make_materials() -> void:
	_concrete = _mat(Color(0.32, 0.31, 0.30), 0.95)
	_stone = _mat(Color(0.24, 0.23, 0.24), 0.9)
	_iron = _mat(Color(0.2, 0.2, 0.22), 0.45, 0.8)
	_wood = _mat(Color(0.35, 0.24, 0.15), 0.85)


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.05, 0.08)
	sky_mat.sky_horizon_color = Color(0.16, 0.16, 0.18)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.13)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.03)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.44, 0.48)
	env.fog_density = 0.008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.7, 0.75, 0.9)
	moon.light_energy = 0.6
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-50, 30, 0)
	add_child(moon)


func _build_level() -> void:
	# Ground and boundary walls.
	_box(Vector3(0, -0.5, 0), Vector3(240, 1, 240), _stone)
	for s in [-1.0, 1.0]:
		_box(Vector3(120 * s, 15, 0), Vector3(2, 30, 240), _concrete)
		_box(Vector3(0, 15, 120 * s), Vector3(240, 30, 2), _concrete)
	# Towers of increasing height with a lamp post on each roof.
	var towers := [
		[Vector3(-20, 0, -30), Vector3(10, 8, 10)],
		[Vector3(5, 0, -45), Vector3(12, 15, 12)],
		[Vector3(30, 0, -30), Vector3(10, 24, 10)],
		[Vector3(45, 0, 5), Vector3(14, 36, 14)],
		[Vector3(-40, 0, 10), Vector3(12, 18, 20)],
		[Vector3(-10, 0, 60), Vector3(30, 12, 10)],
		[Vector3(60, 0, 60), Vector3(8, 55, 8)],
	]
	for t in towers:
		var pos: Vector3 = t[0]
		var size: Vector3 = t[1]
		_box(pos + Vector3(0, size.y * 0.5, 0), size, _concrete)
		_lamp_post(pos + Vector3(size.x * 0.3, size.y, size.z * 0.3), false)
		# Rivets on the facade (anchored metal, visible only as lines).
		for i in 6:
			_rivet(pos + Vector3(-size.x * 0.5 - 0.02, size.y * (0.2 + 0.13 * i), randf_range(-size.z, size.z) * 0.4), 3.0)
	# A street of lamp posts.
	for i in 8:
		var z := -60.0 + i * 16.0
		_lamp_post(Vector3(-8, 0, z), i % 2 == 0)
		_lamp_post(Vector3(8, 0, z + 8), false)
	# Loose metal crates and a stack.
	for i in 6:
		_crate(Vector3(-15 + i * 2.2, 0.6, 8), 30.0)
	for i in 3:
		_crate(Vector3(15, 0.6 + i * 1.21, 20), 30.0)
	# Target dummies: fixed posts with armour, and a free-standing armoured dummy.
	for i in 4:
		_dummy(Vector3(-6 + i * 4, 0, -12), true)
	_dummy(Vector3(12, 0, -8), false)
	# Coins on the ground.
	var pool := CoinPool.get_for(self)
	for i in 30:
		var p := Vector3(randf_range(-20, 20), 0.2, randf_range(-20, 20))
		pool.spawn(Transform3D(Basis.IDENTITY, p), Vector3.ZERO, null)
	# Stress field: hidden rivets in the far walls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in stress_metals:
		var side := rng.randi_range(0, 3)
		var along := rng.randf_range(-110, 110)
		var h := rng.randf_range(1, 28)
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(-118.9, h, along)
			1: p = Vector3(118.9, h, along)
			2: p = Vector3(along, h, -118.9)
			_: p = Vector3(along, h, 118.9)
		_rivet(p, 2.0)
	# A dense field of floor rivets in the east yard: stand there for 500+ lines at once.
	for i in stress_metals:
		_rivet(Vector3(rng.randf_range(55, 110), rng.randf_range(0.05, 0.1), rng.randf_range(-100, -40)), 0.5)


func _box(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	sb.global_position = center
	return sb


func _lamp_post(base: Vector3, lit: bool) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = 5.0
	cs.shape = shape
	cs.position = Vector3(0, 2.5, 0)
	sb.add_child(cs)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.12
	pm.height = 5.0
	pole.mesh = pm
	pole.material_override = _iron
	pole.position = Vector3(0, 2.5, 0)
	sb.add_child(pole)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.45, 0.55, 0.45)
	head.mesh = hm
	var glow := _mat(Color(1.0, 0.7, 0.35), 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.3)
	glow.emission_energy_multiplier = 3.0
	head.material_override = glow
	head.position = Vector3(0, 5.2, 0)
	sb.add_child(head)
	if lit:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.65, 0.35)
		light.light_energy = 2.0
		light.omni_range = 12.0
		light.position = Vector3(0, 5.0, 0)
		sb.add_child(light)
	add_child(sb)
	sb.global_position = base
	var m := Metallic.new()
	m.metal_mass = lamp_post_metal_mass
	m.position = Vector3(0, 3.5, 0)
	sb.add_child(m)


func _rivet(pos: Vector3, mass: float) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	var m := Metallic.new()
	m.metal_mass = mass
	m.anchored = true
	n.add_child(m)


func _crate(pos: Vector3, kg: float) -> void:
	var rb := RigidBody3D.new()
	rb.mass = kg
	rb.collision_layer = 1 << 3
	rb.collision_mask = 1 | 2 | 4 | 8 | 16
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	cs.shape = shape
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 1.2, 1.2)
	mi.mesh = mesh
	mi.material_override = _iron
	rb.add_child(mi)
	add_child(rb)
	rb.global_position = pos
	var m := Metallic.new()
	m.metal_mass = crate_metal_mass
	rb.add_child(m)


func _dummy(pos: Vector3, fixed: bool) -> void:
	var body: PhysicsBody3D
	if fixed:
		body = StaticBody3D.new()
	else:
		var rb := RigidBody3D.new()
		rb.mass = 80.0
		rb.axis_lock_angular_x = true
		rb.axis_lock_angular_z = true
		body = rb
	body.collision_layer = 1 << 2
	body.collision_mask = 1 | 2 | 4 | 8 | 16
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	mi.mesh = mesh
	mi.material_override = _wood
	mi.position = Vector3(0, 0.9, 0)
	body.add_child(mi)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.6, 0.5, 0.1)
	plate.mesh = pm
	plate.material_override = _iron
	plate.position = Vector3(0, 1.25, 0.33)
	body.add_child(plate)
	var h := Health.new()
	h.name = "Health"
	h.max_health = 100.0
	h.regen_per_second = 20.0
	h.regen_delay = 2.0
	body.add_child(h)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.2, 0)
	label.font_size = 48
	label.pixel_size = 0.005
	body.add_child(label)
	add_child(body)
	body.global_position = pos
	var m := Metallic.new()
	m.metal_mass = 8.0
	m.position = Vector3(0, 1.25, 0.35)
	body.add_child(m)
	_dummies.append(h)
	h.died.connect(func(_k: Node) -> void:
		get_tree().create_timer(3.0).timeout.connect(h.revive))
	h.damaged.connect(func(a: float, _s: Node, kind: StringName) -> void:
		label.text = "-%d %s" % [roundi(a), kind])


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = Vector3(0, 0.05, 10)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch_angle = -0.05
	player.camera_rig.snap()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 16)
	_hud.add_theme_color_override(&"font_color", Color(0.85, 0.9, 1.0))
	_hud.add_theme_font_size_override(&"font_size", 18)
	layer.add_child(_hud)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override(&"font_size", 28)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position -= Vector2(8, 20)
	layer.add_child(cross)


func _process(_delta: float) -> void:
	_frame += 1
	if player == null:
		return
	var a := player.allomancer
	var burning := PackedStringArray()
	for i in Metal.COUNT:
		if a.is_burning(i):
			burning.append("%s %d" % [Metal.name_of(i), roundi(a.get_reserve(i))])
	var t := player.targeting.target
	_hud.text = "Speed %5.1f m/s  |  HP %d  |  Coins %d  Vials %d  |  Lines %d (drawn %d)  |  %d FPS\nBurning: %s%s\nTarget: %s%s\n[1-9] metals  [B] basics  LMB push  RMB pull  Alt flare  Q throw  G drop  F dagger  R vial  V camera" % [
		player.velocity.length(), roundi(player.health.current), player.coins, player.vials,
		a.lines_in_range().size(), player.steel_lines.drawn_count(), Engine.get_frames_per_second(),
		", ".join(burning) if not burning.is_empty() else "-",
		"  (FLARING)" if a.flaring else "",
		(t.get_parent().name + " (%.0f)" % t.metal_mass) if t != null else "-",
		"  [assist]" if player.targeting.from_assist else ""]
	if _screenshot_path != "" and _frame == _screenshot_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("Saved screenshot to ", _screenshot_path)
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if not _demo or player == null:
		return
	# Demo: steel-push off the nearest anchor below/behind every half second.
	var lines := player.allomancer.lines_in_range()
	var desired := (Vector3.FORWARD + Vector3.UP).normalized()
	var anchor := player.targeting.pick_traversal_anchor(lines, player.allomancer.line_origin(), desired,
		player.allomancer.current_range(), player.mass_kg)
	if anchor != null and (_frame / 30) % 2 == 0:
		player.allomancer.push(anchor, 1.0, delta)
