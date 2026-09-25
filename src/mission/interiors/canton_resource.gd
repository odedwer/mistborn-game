extends Node3D
## "The Canton of Resource" heist interior (Act II): a night break-in to steal
## the Canton's ledgers. Two connected rooms — an outer records hall with a
## patrolling `Guard` and a bronze-burning `Seeker` (see `src/enemies/seeker.gd`;
## it senses the player's own allomantic pulses, so burning copper — not just
## staying in shadow — is the real counter), and an inner archive with the
## ledger objective and a second `Guard`. Guards can be quietly fought
## (an optional, non-lethal-flavoured takedown) — the heist's fail_conditions
## only trip once several are hostile at once (see `MissionDirector`'s
## `combat_count`), not the instant a single one notices.
##
## Markers: `"interior_spawn"`, `"objective_point"`/`"canton_ledger"` (the
## strongbox of ledgers), `"objective_point"`/`"canton_exit"` (the way back
## out with the goods).

const OUTER_SIZE := Vector3(18.0, 5.0, 12.0)
const INNER_SIZE := Vector3(10.0, 5.0, 8.0)
const INNER_OFFSET := Vector3(0.0, 0.0, -(12.0 * 0.5 + 8.0 * 0.5))

## Floor/wall geometry is parented under this instead of `self` so it can be
## baked into a real navmesh (`Guard`/`Seeker` carry a `NavigationAgent3D`,
## which needs one to path at all — the open world bakes one per chunk; a
## bespoke interior has to bake its own).
var _nav: NavigationRegion3D


func _ready() -> void:
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	# Outer hall: an entrance/exit gap south (the courtyard door) and a
	# connector gap north (into the archive). Inner archive: a connector gap
	# south, lining up with the outer hall's north gap at the shared wall
	# (both at z=-6, both centred on x=0 with the same door_half_w), and a
	# solid back wall north — the archive is a dead end, not a second exit.
	_build_room(Vector3.ZERO, OUTER_SIZE, true, true)
	_build_room(INNER_OFFSET, INNER_SIZE, true, false)
	_nav.navigation_mesh = NavigationMesh.new()
	_nav.bake_navigation_mesh(false)
	_build_lighting()
	_build_ledger()
	_build_enemies()
	_build_markers()
	_build_exit_door()


## Builds a boxy room. `south_gap` leaves a doorway gap in the south (+z)
## wall; `north_gap` leaves one in the north (-z) wall. A room with a gap
## disabled on a side gets a solid wall there instead, so every room still
## reads as fully enclosed except where a doorway is meant to be.
func _build_room(center: Vector3, size: Vector3, south_gap: bool, north_gap: bool) -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.2, 0.24)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(size.x, 0.4, size.z)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = floor_box.size
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)
	floor_body.position = center + Vector3(0, -0.2, 0)
	_nav.add_child(floor_body)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.28, 0.26, 0.3)
	var half_x := size.x * 0.5
	var half_z := size.z * 0.5
	var door_half_w := 1.4
	var walls := [
		{"size": Vector3(0.4, size.y, size.z), "pos": center + Vector3(-half_x, size.y * 0.5, 0)},
		{"size": Vector3(0.4, size.y, size.z), "pos": center + Vector3(half_x, size.y * 0.5, 0)},
	]
	if north_gap:
		walls.append({"size": Vector3(half_x - door_half_w, size.y, 0.4), "pos": center + Vector3(-(half_x + door_half_w) * 0.5, size.y * 0.5, -half_z)})
		walls.append({"size": Vector3(half_x - door_half_w, size.y, 0.4), "pos": center + Vector3((half_x + door_half_w) * 0.5, size.y * 0.5, -half_z)})
	else:
		walls.append({"size": Vector3(size.x, size.y, 0.4), "pos": center + Vector3(0, size.y * 0.5, -half_z)})
	if south_gap:
		walls.append({"size": Vector3(half_x - door_half_w, size.y, 0.4), "pos": center + Vector3(-(half_x + door_half_w) * 0.5, size.y * 0.5, half_z)})
		walls.append({"size": Vector3(half_x - door_half_w, size.y, 0.4), "pos": center + Vector3((half_x + door_half_w) * 0.5, size.y * 0.5, half_z)})
	else:
		walls.append({"size": Vector3(size.x, size.y, 0.4), "pos": center + Vector3(0, size.y * 0.5, half_z)})
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
	(ceiling.mesh as BoxMesh).size = Vector3(size.x, 0.2, size.z)
	ceiling.material_override = wall_mat
	ceiling.position = center + Vector3(0, size.y, 0)
	add_child(ceiling)


## The gap in each room's shared wall already lines up (both use the same
## `door_half_w`), so no extra geometry is needed; this just documents the
## connector's opening so it's easy to find on a screenshot check.
func _build_connector() -> void:
	pass


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.015, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.06, 0.06, 0.08)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)
	for pos: Vector3 in [Vector3(-5, 3.5, -3), Vector3(5, 3.5, 3), INNER_OFFSET]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.9, 0.7, 0.4)
		lamp.light_energy = 0.9
		lamp.omni_range = 7.0
		lamp.position = pos
		add_child(lamp)


func _build_ledger() -> void:
	var box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.4, 1.1, 0.9)
	shape.shape = b
	box.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = b.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.2)
	mesh.material_override = mat
	box.add_child(mesh)
	box.position = INNER_OFFSET + Vector3(0.0, 0.55, -2.5)
	var metallic_script := load("res://src/allomancy/metallic.gd")
	if metallic_script != null:
		var metallic := Node3D.new()
		metallic.set_script(metallic_script)
		metallic.set("metal_mass", 25.0)
		box.add_child(metallic)
	add_child(box)


func _build_enemies() -> void:
	var guard_scene: PackedScene = load("res://src/enemies/guard.tscn")
	var seeker_scene: PackedScene = load("res://src/enemies/seeker.tscn")

	var g1 := guard_scene.instantiate()
	add_child(g1)
	g1.global_position = Vector3(4.0, 0.0, 3.0)
	g1.call("set_patrol_points", PackedVector3Array([Vector3(4.0, 0.0, 3.0), Vector3(-4.0, 0.0, 3.0), Vector3(-4.0, 0.0, -3.0), Vector3(4.0, 0.0, -3.0)]))

	var seeker := seeker_scene.instantiate()
	add_child(seeker)
	seeker.global_position = Vector3(0.0, 0.0, -1.0)
	seeker.call("set_patrol_points", PackedVector3Array([Vector3(0.0, 0.0, -1.0), Vector3(6.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-6.0, 0.0, 0.0)]))

	var g2 := guard_scene.instantiate()
	add_child(g2)
	g2.global_position = INNER_OFFSET + Vector3(2.5, 0.0, 1.0)
	g2.call("set_patrol_points", PackedVector3Array([INNER_OFFSET + Vector3(2.5, 0.0, 1.0), INNER_OFFSET + Vector3(-2.5, 0.0, 1.0)]))


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, OUTER_SIZE.z * 0.5 - 1.5)
	add_child(spawn)

	var ledger := Marker3D.new()
	ledger.add_to_group(&"objective_point")
	ledger.set_meta("objective_id", "canton_ledger")
	ledger.position = INNER_OFFSET + Vector3(0.0, 0.05, -2.0)
	add_child(ledger)

	var exit_marker := Marker3D.new()
	exit_marker.add_to_group(&"objective_point")
	exit_marker.set_meta("objective_id", "canton_exit")
	exit_marker.position = Vector3(0.0, 0.05, OUTER_SIZE.z * 0.5 - 1.5)
	add_child(exit_marker)


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
	mat.albedo_color = Color(0.3, 0.28, 0.3)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, OUTER_SIZE.z * 0.5 - 0.3)
	add_child(door)
