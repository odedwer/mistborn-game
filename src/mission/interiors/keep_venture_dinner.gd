extends Node3D
## "Dinner at Keep Venture" interior (Act II): a smaller, intimate dining hall
## — Vin's second visit to the Ventures, this time for a quiet dinner rather
## than a full ball. Elend Venture sits reading at the head of the table
## (a talkable `NPCTalker` with a choice-driven dialogue that sets a
## relationship flag). Two other nobles gossip near the hearth — burn tin at
## the alcove to make out house politics — and a steward's coin-purse sits
## within Pull range of a side table for a subtle pickpocket.
##
## Markers: `"interior_spawn"`, `"objective_point"`/`"dinner_eavesdrop"`
## (tin), `"objective_point"`/`"dinner_pickpocket"` (iron). Elend's dialogue
## sets one of three boolean relationship flags (`elend_curious`,
## `elend_guarded`, `elend_warm`) depending on the player's answer. Reuses
## `SuspicionMeter` — pickpocketing or Pulling too close to a noble still
## risks being noticed, same as the ball.

const HALL_SIZE := Vector3(16.0, 6.0, 12.0)


func _ready() -> void:
	_build_room()
	_build_table()
	_build_hearth()
	_build_lighting()
	_build_people()
	_build_markers()
	_build_exit_door()
	add_child(SuspicionMeter.new())
	var bar_scene := "res://src/ui/suspicion_bar.tscn"
	if ResourceLoader.exists(bar_scene):
		add_child((load(bar_scene) as PackedScene).instantiate())


func _build_room() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.5, 0.42, 0.35)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(HALL_SIZE.x, 0.4, HALL_SIZE.z)
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
	wall_mat.albedo_color = Color(0.38, 0.34, 0.3)
	var half_x := HALL_SIZE.x * 0.5
	var half_z := HALL_SIZE.z * 0.5
	var door_half_w := 1.3
	var walls := [
		{"size": Vector3(HALL_SIZE.x, HALL_SIZE.y, 0.4), "pos": Vector3(0, HALL_SIZE.y * 0.5, -half_z)},
		{"size": Vector3(0.4, HALL_SIZE.y, HALL_SIZE.z), "pos": Vector3(-half_x, HALL_SIZE.y * 0.5, 0)},
		{"size": Vector3(0.4, HALL_SIZE.y, HALL_SIZE.z), "pos": Vector3(half_x, HALL_SIZE.y * 0.5, 0)},
		# South wall has a doorway gap back to the courtyard (the exit).
		{"size": Vector3(half_x - door_half_w, HALL_SIZE.y, 0.4), "pos": Vector3(-(half_x + door_half_w) * 0.5, HALL_SIZE.y * 0.5, half_z)},
		{"size": Vector3(half_x - door_half_w, HALL_SIZE.y, 0.4), "pos": Vector3((half_x + door_half_w) * 0.5, HALL_SIZE.y * 0.5, half_z)},
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
	(ceiling.mesh as BoxMesh).size = Vector3(HALL_SIZE.x, 0.2, HALL_SIZE.z)
	ceiling.material_override = wall_mat
	ceiling.position = Vector3(0, HALL_SIZE.y, 0)
	add_child(ceiling)


func _build_table() -> void:
	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.35, 0.24, 0.15)
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.5, 0.8, 2.0)
	shape.shape = box
	table.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	mesh.material_override = table_mat
	table.add_child(mesh)
	table.position = Vector3(0, 0.4, -1.5)
	add_child(table)

	# The steward's coin-purse: a small, light `Metallic` prop on a side
	# table, subtle enough for a Pull that doesn't ring the suspicion meter
	# the way a chandelier Push would.
	var side := StaticBody3D.new()
	var s_shape := CollisionShape3D.new()
	var s_box := BoxShape3D.new()
	s_box.size = Vector3(0.9, 0.7, 0.6)
	s_shape.shape = s_box
	side.add_child(s_shape)
	var s_mesh := MeshInstance3D.new()
	s_mesh.mesh = BoxMesh.new()
	(s_mesh.mesh as BoxMesh).size = s_box.size
	var s_mat := StandardMaterial3D.new()
	s_mat.albedo_color = Color(0.3, 0.28, 0.26)
	s_mesh.material_override = s_mat
	side.add_child(s_mesh)
	side.position = Vector3(-half_x_offset(), 0.35, 3.0)
	var metallic_script := load("res://src/allomancy/metallic.gd")
	if metallic_script != null:
		var metallic := Node3D.new()
		metallic.set_script(metallic_script)
		metallic.set("metal_mass", 2.0)
		side.add_child(metallic)
	add_child(side)


func half_x_offset() -> float:
	return HALL_SIZE.x * 0.5 - 3.0


func _build_hearth() -> void:
	var hearth := MeshInstance3D.new()
	hearth.mesh = BoxMesh.new()
	(hearth.mesh as BoxMesh).size = Vector3(3.0, 2.2, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.28, 0.27)
	hearth.material_override = mat
	hearth.position = Vector3(HALL_SIZE.x * 0.5 - 0.5, 1.1, -HALL_SIZE.z * 0.5 + 3.0)
	add_child(hearth)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 1.6
	fire.omni_range = 7.0
	fire.position = hearth.position + Vector3(-0.5, -0.6, 0.4)
	add_child(fire)


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.19, 0.17)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)


func _build_people() -> void:
	var elend := NPCTalker.new()
	elend.display_name = "Elend Venture"
	elend.dialogue_id = "elend_venture_intro"
	elend.body_color = Color(0.55, 0.5, 0.75)
	elend.wander_radius = 0.0
	elend.position = Vector3(2.2, 0.0, -1.5)
	add_child(elend)

	var gossipers := [
		{"name": "Lady Kliss", "color": Color("#7a8f5c"), "pos": Vector2(-4.0, 2.5)},
		{"name": "Lord Ashweather", "color": Color("#8f5c6b"), "pos": Vector2(-5.5, -1.0)},
	]
	for g: Dictionary in gossipers:
		var npc := NPCTalker.new()
		npc.display_name = g["name"]
		npc.body_color = g["color"]
		npc.wander_radius = 2.0
		npc.wander_speed = 0.7
		var p: Vector2 = g["pos"]
		npc.position = Vector3(p.x, 0.0, p.y)
		add_child(npc)


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, HALL_SIZE.z * 0.5 - 1.5)
	add_child(spawn)

	var eavesdrop := Marker3D.new()
	eavesdrop.add_to_group(&"objective_point")
	eavesdrop.set_meta("objective_id", "dinner_eavesdrop")
	eavesdrop.position = Vector3(-4.5, 0.05, 1.0)
	add_child(eavesdrop)

	var pickpocket := Marker3D.new()
	pickpocket.add_to_group(&"objective_point")
	pickpocket.set_meta("objective_id", "dinner_pickpocket")
	pickpocket.position = Vector3(-half_x_offset(), 0.05, 3.0)
	add_child(pickpocket)


func _build_exit_door() -> void:
	var door := StaticBody3D.new()
	door.set_script(load("res://src/world/interior_door.gd"))
	door.set("is_exit", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 3.0, 0.4)
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.28)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, HALL_SIZE.z * 0.5 - 0.3)
	add_child(door)
