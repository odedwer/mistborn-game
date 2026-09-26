extends Node3D
## "Lady Valette" ball interior: Keep Venture's grand hall — stained glass,
## chandeliers, tables, a dance floor — plus the social-stealth systems
## (`SuspicionMeter`, `SuspicionBar`) and three wandering, talkable noble
## `NPCTalker`s.
##
## Markers: `"interior_spawn"` and `"objective_point"`/`"ball_eavesdrop"` (a
## quiet alcove where a hushed conversation can be made out — but only while
## burning tin; see `MissionData`'s `require_metal`). Chandeliers carry a
## `Metallic` component like any other metal prop: nothing stops a flared
## Push from swinging one, which is exactly why the mission's suspicion meter
## exists instead of a hard lock.

const HALL_SIZE := Vector3(26.0, 8.0, 17.0)

const NOBLES := [
	{"id": "1", "name": "Lord Fedren", "color": Color("#7a5c8f"), "pos": Vector2(-7.0, -2.0), "model": &"noble_man_1"},
	{"id": "2", "name": "Lady Hesting", "color": Color("#a26b7a"), "pos": Vector2(6.0, 1.0), "model": &"noble_woman_2"},
	{"id": "3", "name": "Lord Elariel", "color": Color("#6b8f7c"), "pos": Vector2(0.0, 5.0), "model": &"noble_man_3"},
]
## Unnamed guests milling about (no dialogue): base models with a re-rolled variant each.
const GUESTS := [
	{"model": &"noble_woman", "pos": Vector2(-3.0, -4.5)}, {"model": &"noble_man", "pos": Vector2(-2.0, -5.2)},
	{"model": &"noble_woman", "pos": Vector2(3.5, -3.0)}, {"model": &"noble_man", "pos": Vector2(8.5, -1.5)},
	{"model": &"noble_woman", "pos": Vector2(-8.0, 3.0)}, {"model": &"noble_man", "pos": Vector2(-6.5, 3.8)},
	{"model": &"noble_woman", "pos": Vector2(2.0, 1.5)}, {"model": &"noble_man", "pos": Vector2(-1.5, 1.0)},
]


func _ready() -> void:
	add_child(DisguiseZone.new())  # Lady Valette wears Vin's ball gown in here
	_build_hall()
	_build_stained_glass()
	_build_chandeliers()
	_build_tables_and_floor()
	_build_lighting()
	_build_nobles()
	_build_markers()
	_build_exit_door()
	add_child(SuspicionMeter.new())
	var bar_scene := "res://src/ui/suspicion_bar.tscn"
	if ResourceLoader.exists(bar_scene):
		add_child((load(bar_scene) as PackedScene).instantiate())


func _build_hall() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.5, 0.45)
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
	wall_mat.albedo_color = Color(0.42, 0.4, 0.4)
	var half_x := HALL_SIZE.x * 0.5
	var half_z := HALL_SIZE.z * 0.5
	var door_half_w := 1.4
	var walls := [
		{"size": Vector3(HALL_SIZE.x, HALL_SIZE.y, 0.4), "pos": Vector3(0, HALL_SIZE.y * 0.5, -half_z)},
		{"size": Vector3(0.4, HALL_SIZE.y, HALL_SIZE.z), "pos": Vector3(-half_x, HALL_SIZE.y * 0.5, 0)},
		{"size": Vector3(0.4, HALL_SIZE.y, HALL_SIZE.z), "pos": Vector3(half_x, HALL_SIZE.y * 0.5, 0)},
		# South wall has a doorway gap onto the terrace (the mistwalk exit).
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

	# A row of stone pillars down each side.
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.5, 0.48, 0.45)
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var pillar := MeshInstance3D.new()
			pillar.mesh = CylinderMesh.new()
			(pillar.mesh as CylinderMesh).top_radius = 0.35
			(pillar.mesh as CylinderMesh).bottom_radius = 0.4
			(pillar.mesh as CylinderMesh).height = HALL_SIZE.y - 0.2
			pillar.material_override = pillar_mat
			pillar.position = Vector3(side * (half_x - 1.2), (HALL_SIZE.y - 0.2) * 0.5, -half_z + 2.0 + float(i) * 4.2)
			add_child(pillar)


## Tall emissive panels on the north wall (opposite the entrance), standing
## in for stained glass.
func _build_stained_glass() -> void:
	var colors := [Color(0.7, 0.2, 0.25), Color(0.2, 0.4, 0.7), Color(0.8, 0.65, 0.2), Color(0.25, 0.55, 0.35)]
	var half_x := HALL_SIZE.x * 0.5
	for i in colors.size():
		var panel := MeshInstance3D.new()
		panel.mesh = PlaneMesh.new()
		(panel.mesh as PlaneMesh).size = Vector2(3.0, 5.0)
		(panel.mesh as PlaneMesh).orientation = PlaneMesh.FACE_Z
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		panel.material_override = mat
		panel.position = Vector3(-half_x + 4.0 + float(i) * 6.0, 4.5, -HALL_SIZE.z * 0.5 + 0.35)
		add_child(panel)


## Metal chandeliers Vin must not Push/Pull while disguised (suspicion, not a
## hard lock — see `SuspicionMeter`).
func _build_chandeliers() -> void:
	var metallic_script := load("res://src/allomancy/metallic.gd")
	for x: float in [-6.0, 0.0, 6.0]:
		var chandelier := Node3D.new()
		chandelier.position = Vector3(x, HALL_SIZE.y - 1.2, 0)
		var mesh := MeshInstance3D.new()
		mesh.mesh = TorusMesh.new()
		(mesh.mesh as TorusMesh).inner_radius = 0.5
		(mesh.mesh as TorusMesh).outer_radius = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.75, 0.4)
		mat.metallic = 0.9
		mat.roughness = 0.3
		mesh.material_override = mat
		chandelier.add_child(mesh)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)
		light.light_energy = 1.3
		light.omni_range = 8.0
		chandelier.add_child(light)
		if metallic_script != null:
			var metallic := Node3D.new()
			metallic.set_script(metallic_script)
			metallic.set("metal_mass", 45.0)
			chandelier.add_child(metallic)
		add_child(chandelier)


func _build_tables_and_floor() -> void:
	var dance_floor := MeshInstance3D.new()
	dance_floor.mesh = PlaneMesh.new()
	(dance_floor.mesh as PlaneMesh).size = Vector2(8.0, 8.0)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.75, 0.7, 0.65)
	dmat.metallic = 0.2
	dmat.roughness = 0.15
	dance_floor.material_override = dmat
	dance_floor.position = Vector3(0, 0.01, 0)
	add_child(dance_floor)

	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.9, 0.9, 0.88)
	for pos: Vector3 in [Vector3(-9, 0.5, -6), Vector3(9, 0.5, -6), Vector3(-9, 0.5, 6), Vector3(9, 0.5, 6)]:
		var table := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.0
		cyl.height = 1.0
		shape.shape = cyl
		table.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = CylinderMesh.new()
		(mesh.mesh as CylinderMesh).top_radius = 1.0
		(mesh.mesh as CylinderMesh).bottom_radius = 1.0
		(mesh.mesh as CylinderMesh).height = 1.0
		mesh.material_override = table_mat
		table.add_child(mesh)
		table.position = pos
		add_child(table)


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.04, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.22, 0.2)
	e.ambient_light_energy = 1.4
	env.environment = e
	add_child(env)


func _build_nobles() -> void:
	for n: Dictionary in NOBLES:
		var npc := NPCTalker.new()
		npc.display_name = n["name"]
		npc.dialogue_id = "ball_noble_%s" % n["id"]
		npc.body_color = n["color"]
		npc.model_id = n["model"]
		npc.wander_radius = 3.0
		npc.wander_speed = 0.8
		npc.idle_chatter = true
		var p: Vector2 = n["pos"]
		npc.position = Vector3(p.x, 0.0, p.y)
		add_child(npc)
	for i in GUESTS.size():
		var g: Dictionary = GUESTS[i]
		var guest := NPCTalker.new()
		guest.model_id = g["model"]
		guest.variant_seed = 101 + i * 37
		guest.idle_chatter = true
		guest.wander_radius = 1.5 if i % 3 == 0 else 0.0
		guest.wander_speed = 0.6
		var gp: Vector2 = g["pos"]
		guest.position = Vector3(gp.x, 0.0, gp.y)
		# guests stand in pairs, facing each other
		var other: Vector2 = GUESTS[i ^ 1]["pos"]
		guest.facing_deg = rad_to_deg(atan2(other.x - gp.x, other.y - gp.y))
		add_child(guest)



func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, HALL_SIZE.z * 0.5 - 1.5)
	add_child(spawn)

	var eavesdrop := Marker3D.new()
	eavesdrop.add_to_group(&"objective_point")
	eavesdrop.set_meta("objective_id", "ball_eavesdrop")
	eavesdrop.position = Vector3(-HALL_SIZE.x * 0.5 + 2.5, 0.05, -HALL_SIZE.z * 0.5 + 2.5)
	add_child(eavesdrop)


func _build_exit_door() -> void:
	var door := StaticBody3D.new()
	door.set_script(load("res://src/world/interior_door.gd"))
	door.set("is_exit", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 3.0, 0.4)
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, HALL_SIZE.z * 0.5 - 0.3)
	add_child(door)
