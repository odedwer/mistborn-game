extends Node3D
## "The Crew" hub interior: the back room of Clubs' shop where Kelsier's crew
## gathers. Eight talkable `NPCTalker`s (Kelsier, Dockson, Breeze, Ham, Clubs,
## Spook, Sazed, Marsh); a door back outside via `SceneTransition`.

const ROOM_SIZE := Vector3(16.0, 3.6, 11.0)

## id -> {name, color, pos (local XZ offset from centre)}. Colors match each
## dialogue file's speaker `color`.
const CREW := [
	{"id": "kelsier", "name": "Kelsier", "color": Color("#c9a227"), "pos": Vector2(0.0, -3.0)},
	{"id": "dockson", "name": "Dockson", "color": Color("#6b7280"), "pos": Vector2(-4.5, -1.0)},
	{"id": "breeze", "name": "Breeze", "color": Color("#90743a"), "pos": Vector2(4.5, -1.0)},
	{"id": "ham", "name": "Ham", "color": Color("#8a4b3d"), "pos": Vector2(-5.5, 2.0)},
	{"id": "clubs", "name": "Clubs", "color": Color("#4a4a4a"), "pos": Vector2(5.5, 2.0)},
	{"id": "spook", "name": "Spook", "color": Color("#5c7a99"), "pos": Vector2(-2.0, 3.5)},
	{"id": "sazed", "name": "Sazed", "color": Color("#c2a878"), "pos": Vector2(2.0, 3.5)},
	{"id": "marsh", "name": "Marsh", "color": Color("#3f5a4a"), "pos": Vector2(0.0, 4.5)},
]


func _ready() -> void:
	_build_room()
	_build_lighting()
	_build_crew()
	_build_markers()
	_build_exit_door()


func _build_room() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.24, 0.16)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(ROOM_SIZE.x, 0.4, ROOM_SIZE.z)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = floor_box.size
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(0, -0.2, 0)
	add_child(floor_body)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.26, 0.22, 0.18)
	var half_x := ROOM_SIZE.x * 0.5
	var half_z := ROOM_SIZE.z * 0.5
	var walls := [
		{"size": Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.3), "pos": Vector3(0, ROOM_SIZE.y * 0.5, -half_z)},
		{"size": Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), "pos": Vector3(-half_x, ROOM_SIZE.y * 0.5, 0)},
		{"size": Vector3(0.3, ROOM_SIZE.y, ROOM_SIZE.z), "pos": Vector3(half_x, ROOM_SIZE.y * 0.5, 0)},
		{"size": Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.3), "pos": Vector3(0, ROOM_SIZE.y * 0.5, half_z)},
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

	# A long worktable, standing in for Clubs' smithy front.
	var table := StaticBody3D.new()
	var t_shape := CollisionShape3D.new()
	var t_box := BoxShape3D.new()
	t_box.size = Vector3(3.0, 0.8, 1.2)
	t_shape.shape = t_box
	table.add_child(t_shape)
	var t_mesh := MeshInstance3D.new()
	t_mesh.mesh = BoxMesh.new()
	(t_mesh.mesh as BoxMesh).size = t_box.size
	var t_mat := StandardMaterial3D.new()
	t_mat.albedo_color = Color(0.4, 0.3, 0.2)
	t_mesh.material_override = t_mat
	table.add_child(t_mesh)
	table.position = Vector3(0, 0.4, -4.5)
	add_child(table)


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.14, 0.12, 0.1)
	env.environment = e
	add_child(env)

	for pos: Vector3 in [Vector3(-4, 3.0, 0), Vector3(4, 3.0, 0), Vector3(0, 3.0, 3)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.68, 0.4)
		lamp.light_energy = 1.1
		lamp.omni_range = 9.0
		lamp.position = pos
		add_child(lamp)


func _build_crew() -> void:
	for member: Dictionary in CREW:
		var npc := NPCTalker.new()
		npc.display_name = member["name"]
		npc.dialogue_id = "meet_%s" % member["id"]
		npc.body_color = member["color"]
		var p: Vector2 = member["pos"]
		npc.position = Vector3(p.x, 0.0, p.y)
		add_child(npc)


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, ROOM_SIZE.z * 0.5 - 1.0)
	add_child(spawn)


func _build_exit_door() -> void:
	var door := StaticBody3D.new()
	door.set_script(load("res://src/world/interior_door.gd"))
	door.set("is_exit", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 0.4)
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.2, ROOM_SIZE.z * 0.5 - 0.3)
	add_child(door)
