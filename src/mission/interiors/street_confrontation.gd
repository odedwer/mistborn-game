extends Node3D
## "Soothing the Masses" interior (Act II): a walled-off skaa street square,
## standing in for a slice of the open city so the crowd set piece stays
## self-contained. Breeze teaches brass (Soothe) and zinc (Riot) here; a
## `CrowdMoodMeter` tracks the square's temper, driven by a handful of
## `CrowdMember`s. A recruiter NPC sets the "soldiers recruited" flag once
## talked to, standing in for turning calmed/emboldened skaa toward the
## rebellion.
##
## Markers: `"interior_spawn"` and `"objective_point"`/`"street_recruit"`
## (talk to the would-be soldier). The `crowd_mood` objective itself needs no
## marker — `MissionDirector` polls the scene's `CrowdMoodMeter` directly.

const SQUARE_SIZE := Vector3(20.0, 6.0, 20.0)


func _ready() -> void:
	_build_square()
	_build_lighting()
	_build_crowd()
	_build_people()
	_build_markers()
	_build_exit_door()


func _build_square() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.28, 0.26)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(SQUARE_SIZE.x, 0.4, SQUARE_SIZE.z)
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
	wall_mat.albedo_color = Color(0.22, 0.2, 0.19)
	var half_x := SQUARE_SIZE.x * 0.5
	var half_z := SQUARE_SIZE.z * 0.5
	var door_half_w := 1.6
	var walls := [
		{"size": Vector3(SQUARE_SIZE.x, SQUARE_SIZE.y, 0.4), "pos": Vector3(0, SQUARE_SIZE.y * 0.5, -half_z)},
		{"size": Vector3(0.4, SQUARE_SIZE.y, SQUARE_SIZE.z), "pos": Vector3(-half_x, SQUARE_SIZE.y * 0.5, 0)},
		{"size": Vector3(0.4, SQUARE_SIZE.y, SQUARE_SIZE.z), "pos": Vector3(half_x, SQUARE_SIZE.y * 0.5, 0)},
		# South wall has the alley gap back out to the district.
		{"size": Vector3(half_x - door_half_w, SQUARE_SIZE.y, 0.4), "pos": Vector3(-(half_x + door_half_w) * 0.5, SQUARE_SIZE.y * 0.5, half_z)},
		{"size": Vector3(half_x - door_half_w, SQUARE_SIZE.y, 0.4), "pos": Vector3((half_x + door_half_w) * 0.5, SQUARE_SIZE.y * 0.5, half_z)},
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
	# No ceiling: this is an open-air street square under the ash sky.


## Open-air square in the skaa slums under the real night sky/skyline (see
## `MissionBackdrop`), plus a warm lantern so the crowd stays readable.
func _build_lighting() -> void:
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(-240.0, 290.0)
	bd.clear_radius = 40.0
	add_child(bd)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.62, 0.3)
	lamp.light_energy = 1.4
	lamp.omni_range = 16.0
	lamp.position = Vector3(0, 4.5, 0)
	add_child(lamp)


func _build_crowd() -> void:
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	var count := 6
	for i in count:
		var member := CrowdMember.new()
		var ang := TAU * float(i) / float(count)
		member.position = Vector3(cos(ang) * 5.0, 0.0, sin(ang) * 5.0)
		member.wander_radius = 2.5
		add_child(member)


func _build_people() -> void:
	var breeze := NPCTalker.new()
	breeze.display_name = "Breeze"
	breeze.dialogue_id = "breeze_lesson"
	breeze.body_color = Color(0.55, 0.42, 0.3)
	breeze.wander_radius = 0.0
	breeze.position = Vector3(0.0, 0.0, SQUARE_SIZE.z * 0.5 - 4.0)
	add_child(breeze)

	var recruit := NPCTalker.new()
	recruit.display_name = "A Wary Skaa"
	recruit.dialogue_id = "street_recruit"
	recruit.body_color = Color(0.4, 0.4, 0.42)
	recruit.wander_radius = 1.0
	recruit.position = Vector3(-6.0, 0.0, -2.0)
	add_child(recruit)


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, SQUARE_SIZE.z * 0.5 - 1.5)
	add_child(spawn)

	var recruit_marker := Marker3D.new()
	recruit_marker.add_to_group(&"objective_point")
	recruit_marker.set_meta("objective_id", "street_recruit")
	recruit_marker.position = Vector3(-6.0, 0.05, -2.0)
	add_child(recruit_marker)


func _build_exit_door() -> void:
	var door := StaticBody3D.new()
	door.set_script(load("res://src/world/interior_door.gd"))
	door.set("is_exit", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 3.0, 0.4)
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.25)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, SQUARE_SIZE.z * 0.5 - 0.3)
	add_child(door)
