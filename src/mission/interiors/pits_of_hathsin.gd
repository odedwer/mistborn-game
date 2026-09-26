extends Node3D
## "The Pits of Hathsin" (Act II): a separate mission space — a deep, dark
## crevasse system riddled with embedded iron spikes (the descent anchors) and
## a scatter of rare atium geodes. Built as a stepped shaft of ledges dropping
## in height, each with a heavy anchored `Metallic` spike within Pull range,
## so the whole descent plays as a traversal chain rather than a scripted
## cutscene. A short stealth stretch of patrolling `Guard`s guards the lowest
## ledge before the escape shaft back up.
##
## Kelsier's history here is told only through original hint text at three
## `cutscene_hint`-style waypoints and the environment itself (chains, an old
## collapsed dig, a geode vein) — no book text is reproduced.
##
## Markers: `"interior_spawn"`, `"objective_point"`/`"pits_ledge_1..3"` (the
## descent), `"objective_point"`/`"pits_geode"` (an atium geode sample) and
## `"objective_point"`/`"pits_escape"` (the way back up).

const SHAFT_WIDTH := 10.0
const LEDGE_COUNT := 4
const LEDGE_DROP := 6.0
const LEDGE_DEPTH := 8.0

## See `canton_resource.gd`'s `_nav` doc: the lowest ledge's `Guard`s need a
## baked navmesh to patrol at all.
var _nav: NavigationRegion3D


func _ready() -> void:
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_shaft()
	_nav.navigation_mesh = NavigationMesh.new()
	# Bake from the rooms' collision shapes: parsing visual meshes reads them
	# back from the GPU (a stall, and a warning on every bake).
	_nav.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_nav.bake_navigation_mesh(false)
	_build_lighting()
	_build_geode()
	_build_guards()
	_build_markers()
	_build_exit_door()


func _build_shaft() -> void:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.16, 0.13, 0.14)
	var half_w := SHAFT_WIDTH * 0.5
	for i in LEDGE_COUNT:
		var y := -float(i) * LEDGE_DROP
		var z := float(i) * LEDGE_DEPTH
		# Ledge floor.
		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(SHAFT_WIDTH, 0.6, LEDGE_DEPTH)
		floor_shape.shape = floor_box
		floor_body.add_child(floor_shape)
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.mesh = BoxMesh.new()
		(floor_mesh.mesh as BoxMesh).size = floor_box.size
		floor_mesh.material_override = rock_mat
		floor_body.add_child(floor_mesh)
		floor_body.position = Vector3(0, y - 0.3, z)
		_nav.add_child(floor_body)
		# Side walls, so the shaft reads as a crevasse, not a flat cave.
		for side: float in [-1.0, 1.0]:
			var wall := StaticBody3D.new()
			var w_shape := CollisionShape3D.new()
			var w_box := BoxShape3D.new()
			w_box.size = Vector3(0.6, LEDGE_DROP + 4.0, LEDGE_DEPTH)
			w_shape.shape = w_box
			wall.add_child(w_shape)
			var w_mesh := MeshInstance3D.new()
			w_mesh.mesh = BoxMesh.new()
			(w_mesh.mesh as BoxMesh).size = w_box.size
			w_mesh.material_override = rock_mat
			wall.add_child(w_mesh)
			wall.position = Vector3(side * (half_w + 0.3), y + LEDGE_DROP * 0.5 - 2.0, z)
			add_child(wall)
		if i < LEDGE_COUNT - 1:
			_add_descent_spike(Vector3(0, y - 1.5, z + LEDGE_DEPTH * 0.5))


## A heavy, anchored iron spike embedded in the rock — a real Pull anchor for
## the next ledge down, not just set dressing.
func _add_descent_spike(pos: Vector3) -> void:
	var spike := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.15
	cyl.height = 1.2
	shape.shape = cyl
	spike.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	(mesh.mesh as CylinderMesh).top_radius = 0.1
	(mesh.mesh as CylinderMesh).bottom_radius = 0.2
	(mesh.mesh as CylinderMesh).height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.3)
	mat.metallic = 0.85
	mesh.material_override = mat
	spike.add_child(mesh)
	spike.position = pos
	var metallic_script := load("res://src/allomancy/metallic.gd")
	if metallic_script != null:
		var metallic := Node3D.new()
		metallic.set_script(metallic_script)
		metallic.set("metal_mass", 500.0)
		metallic.set("anchored", true)
		spike.add_child(metallic)
	add_child(spike)


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.015)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.04, 0.05)
	e.ambient_light_energy = 0.4
	env.environment = e
	add_child(env)
	for i in LEDGE_COUNT:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.85, 0.4, 0.25)
		lamp.light_energy = 0.7
		lamp.omni_range = 8.0
		lamp.position = Vector3(0, -float(i) * LEDGE_DROP + 1.5, float(i) * LEDGE_DEPTH)
		add_child(lamp)


## A vein of rare atium geodes on the lowest ledge — the sample objective.
func _build_geode() -> void:
	var y := -float(LEDGE_COUNT - 1) * LEDGE_DROP
	var z := float(LEDGE_COUNT - 1) * LEDGE_DEPTH
	var geode := MeshInstance3D.new()
	geode.mesh = SphereMesh.new()
	(geode.mesh as SphereMesh).radius = 0.3
	(geode.mesh as SphereMesh).height = 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.9, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.9, 0.7)
	mat.emission_energy_multiplier = 1.4
	geode.material_override = mat
	geode.position = Vector3(2.5, y + 0.4, z - 2.0)
	add_child(geode)


func _build_guards() -> void:
	var guard_scene: PackedScene = load("res://src/enemies/guard.tscn")
	var y := -float(LEDGE_COUNT - 1) * LEDGE_DROP
	var z := float(LEDGE_COUNT - 1) * LEDGE_DEPTH
	for x: float in [-3.0, 3.0]:
		var g := guard_scene.instantiate()
		add_child(g)
		g.global_position = Vector3(x, y, z - 1.0)
		g.call("set_patrol_points", PackedVector3Array([Vector3(x, y, z - 3.0), Vector3(x, y, z + 3.0)]))


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.4, -LEDGE_DEPTH * 0.5 + 1.5)
	add_child(spawn)

	for i in range(1, LEDGE_COUNT):
		var m := Marker3D.new()
		m.add_to_group(&"objective_point")
		m.set_meta("objective_id", "pits_ledge_%d" % i)
		m.position = Vector3(0.0, -float(i) * LEDGE_DROP + 0.4, float(i) * LEDGE_DEPTH)
		add_child(m)

	var geode_marker := Marker3D.new()
	geode_marker.add_to_group(&"objective_point")
	geode_marker.set_meta("objective_id", "pits_geode")
	var gy := -float(LEDGE_COUNT - 1) * LEDGE_DROP
	var gz := float(LEDGE_COUNT - 1) * LEDGE_DEPTH
	geode_marker.position = Vector3(2.5, gy + 0.4, gz - 2.0)
	add_child(geode_marker)

	var escape_marker := Marker3D.new()
	escape_marker.add_to_group(&"objective_point")
	escape_marker.set_meta("objective_id", "pits_escape")
	escape_marker.position = Vector3(0.0, gy + 0.4, gz + LEDGE_DEPTH * 0.5 - 1.0)
	add_child(escape_marker)


func _build_exit_door() -> void:
	var y := -float(LEDGE_COUNT - 1) * LEDGE_DROP
	var z := float(LEDGE_COUNT - 1) * LEDGE_DEPTH
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
	mat.albedo_color = Color(0.5, 0.45, 0.4)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, y + 1.5, z + LEDGE_DEPTH * 0.5 - 0.3)
	add_child(door)
