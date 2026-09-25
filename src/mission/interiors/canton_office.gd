extends Node3D
## "The Survivor's Offer" opening interior: a dim canton office cellar Vin is
## working when Kelsier and Dockson break her out. Built in code (same spirit
## as `scenes/game.gd`'s fallback world) rather than hand-placed in the
## editor, so it needs no imported assets.
##
## Markers: `"interior_spawn"` (where the player appears on entry) and
## `"objective_point"`/`"office_exit"` (the low window/door Kelsier leads her
## through, back into the open world).

const ROOM_SIZE := Vector3(9.0, 3.2, 7.0)


func _ready() -> void:
	_build_room()
	_build_furniture()
	_build_lighting()
	_build_markers()


func _build_room() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.14, 0.12)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(ROOM_SIZE.x, 0.4, ROOM_SIZE.z)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = floor_box.size
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(0, -0.2, 0)
	add_child(floor_body)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.22, 0.19, 0.16)
	var half_x := ROOM_SIZE.x * 0.5
	var half_z := ROOM_SIZE.z * 0.5
	var walls := [
		{"size": Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.3), "pos": Vector3(0, ROOM_SIZE.y * 0.5, -half_z)},
		{"size": Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), "pos": Vector3(-half_x, ROOM_SIZE.y * 0.5, 0)},
		{"size": Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), "pos": Vector3(half_x, ROOM_SIZE.y * 0.5, 0)},
		# North wall has a gap (the office door/window Kelsier breaks through).
		{"size": Vector3(3.0, ROOM_SIZE.y, 0.3), "pos": Vector3(-3.0, ROOM_SIZE.y * 0.5, half_z)},
		{"size": Vector3(3.0, ROOM_SIZE.y, 0.3), "pos": Vector3(3.0, ROOM_SIZE.y * 0.5, half_z)},
	]
	for w: Dictionary in walls:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w["size"]
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		(mesh.mesh as BoxMesh).size = w["size"]
		mesh.material_override = wall_mat
		body.add_child(mesh)
		body.position = w["pos"]
		add_child(body)

	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	(ceiling.mesh as BoxMesh).size = Vector3(ROOM_SIZE.x, 0.2, ROOM_SIZE.z)
	ceiling.material_override = wall_mat
	ceiling.position = Vector3(0, ROOM_SIZE.y, 0)
	add_child(ceiling)


func _build_furniture() -> void:
	# A locked strongbox and desk, a hint of Camon's obligator-office fence
	# work. Metal props with a Metallic component so pewter/steel already read.
	var desk := _box(Vector3(1.6, 0.8, 0.7), Color(0.35, 0.25, 0.15))
	desk.position = Vector3(-2.0, 0.4, -2.5)
	add_child(desk)
	var strongbox := _box(Vector3(0.7, 0.6, 0.6), Color(0.3, 0.3, 0.32))
	strongbox.position = Vector3(2.5, 0.3, -2.6)
	var metallic_script := load("res://src/allomancy/metallic.gd")
	if metallic_script != null:
		var metallic := Node3D.new()
		metallic.set_script(metallic_script)
		metallic.set("metal_mass", 20.0)
		strongbox.add_child(metallic)
	add_child(strongbox)


func _box(size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	return body


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.08, 0.07, 0.06)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.6, 0.3)
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	lamp.position = Vector3(-1.0, 2.4, -1.0)
	lamp.shadow_enabled = true
	add_child(lamp)


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, -1.5)
	add_child(spawn)

	var exit_marker := Marker3D.new()
	exit_marker.add_to_group(&"objective_point")
	exit_marker.set_meta("objective_id", "office_exit")
	exit_marker.position = Vector3(0.0, 0.05, ROOM_SIZE.z * 0.5 - 0.5)
	add_child(exit_marker)
