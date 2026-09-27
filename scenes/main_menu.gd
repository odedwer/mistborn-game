extends Node
## Main menu: animated mist/spire background plus Continue / New Game / Load /
## Settings / Credits / Quit. This is the project's main scene.

const GAME_SCENE := "res://scenes/game.tscn"
const LOADING_SCENE := "res://src/ui/loading_screen.tscn"

var _settings_instance: CanvasLayer
var _slot_popup: PopupPanel
var _credits_popup: PopupPanel
var _first_button: Button


func _ready() -> void:
	_build_background()
	_build_ui()


# --- Background --------------------------------------------------------------

func _build_background() -> void:
	var world := Node3D.new()
	world.name = "Background"
	add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.06, 0.06, 0.08)
	e.ambient_light_energy = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.12, 0.14)
	e.fog_density = 0.035
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.0
	env.environment = e
	env.add_to_group("world_environment")
	world.add_child(env)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_color = Color(0.7, 0.75, 0.9)
	moon.light_energy = 0.6
	world.add_child(moon)

	_build_skyline(world)

	# Drifting mist: a slow GPUParticles3D field of soft, depth-faded puffs
	# (the soft_particle sprite + a shader that fades a puff out rather than
	# cutting a hard quad edge into the skyline/ground).
	var mist := GPUParticles3D.new()
	mist.amount = 90
	mist.lifetime = 14.0
	mist.position = Vector3(0, -2, -20)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 7, 24)
	pm.scale_min = 5.0
	pm.scale_max = 11.0
	pm.color = Color(1.0, 1.0, 1.0, 1.0)
	mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mist.draw_pass_1 = quad
	var mist_mat := ShaderMaterial.new()
	var soft_shader := "res://assets/shaders/soft_mist_particle.gdshader"
	var soft_tex := "res://assets/textures/soft_particle.png"
	if ResourceLoader.exists(soft_shader):
		mist_mat.shader = load(soft_shader)
		if ResourceLoader.exists(soft_tex):
			mist_mat.set_shader_parameter("albedo_tex", load(soft_tex))
		else:
			mist_mat.set_shader_parameter("albedo_tex", _soft_circle_texture())
		mist_mat.set_shader_parameter("tint", Vector3(0.5, 0.51, 0.57))
	quad.material = mist_mat
	world.add_child(mist)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 14)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 55
	world.add_child(cam)
	_animate_camera(cam)


## Luthadel silhouette: a jagged skyline of dark building blocks with Kredik
## Shaw's cluster of black obsidian spires rising above them, slowly
## revealed by the drifting mist.
func _build_skyline(world: Node3D) -> void:
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.012, 0.011, 0.014)
	dark_mat.roughness = 1.0

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925
	for i in 16:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := rng.randf_range(2.0, 5.0)
		var h := rng.randf_range(4.0, 16.0)
		bm.size = Vector3(w, h, w)
		b.mesh = bm
		b.material_override = dark_mat
		var x := rng.randf_range(-40.0, 40.0)
		var z := rng.randf_range(-55.0, -25.0)
		b.position = Vector3(x, h * 0.5 - 3.0, z)
		world.add_child(b)

	# Kredik Shaw: one tall central spire plus a ring of shorter needle
	# spires, echoing the real landmark's "forest of black spires" shape.
	var spire_center := Vector3(-4.0, -3.0, -48.0)
	_spire(world, dark_mat, spire_center, 2.2, 34.0)
	var n := 7
	for i in n:
		var a := TAU * float(i) / float(n)
		var rad := rng.randf_range(6.0, 12.0)
		var hgt := rng.randf_range(0.35, 0.7) * 34.0
		var pos := spire_center + Vector3(sin(a) * rad, 0.0, cos(a) * rad * 0.6)
		_spire(world, dark_mat, pos, rng.randf_range(0.9, 1.6), hgt)


func _spire(world: Node3D, mat: Material, base: Vector3, radius: float, height: float) -> void:
	var spire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.08
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	spire.mesh = mesh
	spire.material_override = mat
	spire.position = base + Vector3(0, height * 0.5, 0)
	world.add_child(spire)


func _soft_circle_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.35))
	grad.add_point(0.6, Color(1, 1, 1, 0.12))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	tex.gradient = grad
	return tex


## A slow cinematic drift over the skyline: a wide side-to-side pan plus a
## gentle push in/out and a matching yaw, so Kredik Shaw's spires slide past
## rather than the camera just sliding on a rail.
func _animate_camera(cam: Camera3D) -> void:
	var start_pos := cam.position
	var tw := create_tween().set_loops()
	tw.tween_property(cam, "position:x", start_pos.x + 5.0, 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "position:x", start_pos.x - 5.0, 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw2 := create_tween().set_loops()
	tw2.tween_property(cam, "position:z", start_pos.z - 2.0, 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(cam, "position:z", start_pos.z + 2.0, 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw3 := create_tween().set_loops()
	tw3.tween_property(cam, "rotation:y", deg_to_rad(4.0), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw3.tween_property(cam, "rotation:y", deg_to_rad(-4.0), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	layer.add_child(root)

	var vign := ColorRect.new()
	vign.color = Color(0, 0, 0, 0.25)
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vign)

	var title := UIHelpers.title_label("Ashes of Luthadel")
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 70)
	root.add_child(title)

	var subtitle := UIHelpers.dim_label("A non-commercial Mistborn fan game")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.position = Vector2(0, 130)
	root.add_child(subtitle)

	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 6)
	menu_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	menu_box.position = Vector2(90, -140)
	root.add_child(menu_box)

	var continue_btn := UIHelpers.button("Continue")
	continue_btn.disabled = GameState.latest_slot() == -1
	continue_btn.pressed.connect(_on_continue)
	menu_box.add_child(continue_btn)
	_first_button = continue_btn

	var new_game_btn := UIHelpers.button("New Game")
	new_game_btn.pressed.connect(_on_new_game)
	menu_box.add_child(new_game_btn)

	var load_btn := UIHelpers.button("Load")
	load_btn.pressed.connect(_on_load)
	menu_box.add_child(load_btn)

	var settings_btn := UIHelpers.button("Settings")
	settings_btn.pressed.connect(_on_settings)
	menu_box.add_child(settings_btn)

	var credits_btn := UIHelpers.button("Credits")
	credits_btn.pressed.connect(_on_credits)
	menu_box.add_child(credits_btn)

	var quit_btn := UIHelpers.button("Quit")
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu_box.add_child(quit_btn)

	_slot_popup = PopupPanel.new()
	root.add_child(_slot_popup)
	_credits_popup = PopupPanel.new()
	root.add_child(_credits_popup)

	if continue_btn.disabled:
		new_game_btn.grab_focus()
	else:
		continue_btn.grab_focus()


func _on_continue() -> void:
	GameState.continue_from_latest()
	_go_to_game()


func _on_new_game() -> void:
	GameState.reset_run()
	_go_to_game()


func _go_to_game() -> void:
	if not ResourceLoader.exists(LOADING_SCENE):
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	LoadingScreen.pending_target = GAME_SCENE
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_load() -> void:
	for c in _slot_popup.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_slot_popup.add_child(box)
	box.add_child(UIHelpers.heading_label("Load"))
	for slot in range(1, 4):
		var has := GameState.has_save(slot)
		var b := UIHelpers.button("Slot %d %s" % [slot, "(occupied)" if has else "(empty)"])
		b.disabled = not has
		b.pressed.connect(func():
			GameState.load_game(slot)
			_slot_popup.hide()
			_go_to_game()
		)
		box.add_child(b)
	_slot_popup.popup_centered(Vector2i(300, 220))


func _on_settings() -> void:
	if _settings_instance != null:
		return
	var scene: PackedScene = load("res://src/ui/settings_menu.tscn")
	_settings_instance = scene.instantiate()
	add_child(_settings_instance)
	if _settings_instance.has_signal("closed"):
		_settings_instance.closed.connect(func():
			_settings_instance.queue_free()
			_settings_instance = null
		)


func _on_credits() -> void:
	# The same scrolling credits the finale rolls (disclaimer, tools, CC0/OFL
	# assets), so there is one source of truth for them.
	if get_tree().get_first_node_in_group(&"credits_screen") != null:
		return
	var credits := CreditsScreen.new()
	add_child(credits)
	credits.finished.connect(func() -> void:
		if _first_button != null and is_instance_valid(_first_button):
			_first_button.grab_focus()
	)
	credits.play()
