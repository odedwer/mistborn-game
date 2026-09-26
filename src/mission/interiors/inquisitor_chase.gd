extends Node3D
## "The Inquisitor's Shadow" (Act II finale): a long rooftop corridor
## standing in for a chase across the city. Spook bolts ahead through three
## checkpoints with a Steel Inquisitor closing in behind; the last stretch
## opens into a small arena where the Inquisitor catches up for a first,
## survivable clash (see `MissionDirector`'s `survive` objective type) before
## the escape door.
##
## Markers: `"interior_spawn"`, `"objective_point"`/`"chase_checkpoint_1..3"`,
## `"objective_point"`/`"chase_arena"` and `"objective_point"`/`"chase_exit"`.

const CORRIDOR_LENGTH := 60.0
const SEGMENT_COUNT := 4

## See `canton_resource.gd`'s `_nav` doc: the Inquisitor's `NavigationAgent3D`
## needs a baked navmesh to close the chase distance at all.
var _nav: NavigationRegion3D


func _ready() -> void:
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_corridor()
	_nav.navigation_mesh = NavigationMesh.new()
	# Bake from the rooms' collision shapes: parsing visual meshes reads them
	# back from the GPU (a stall, and a warning on every bake).
	_nav.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_nav.bake_navigation_mesh(false)
	_build_lighting()
	_build_spook()
	_build_inquisitor()
	_build_markers()
	_build_exit_door()


func _build_corridor() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.26, 0.24)
	var seg_len := CORRIDOR_LENGTH / float(SEGMENT_COUNT)
	for i in SEGMENT_COUNT:
		var z := float(i) * seg_len
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 0.6, seg_len + 1.0)
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		(mesh.mesh as BoxMesh).size = box.size
		mesh.material_override = mat
		body.add_child(mesh)
		body.position = Vector3(0, -0.3, z)
		_nav.add_child(body)
	# The arena at the far end, wider than the corridor.
	var arena := StaticBody3D.new()
	var a_shape := CollisionShape3D.new()
	var a_box := BoxShape3D.new()
	a_box.size = Vector3(18.0, 0.6, 14.0)
	a_shape.shape = a_box
	arena.add_child(a_shape)
	var a_mesh := MeshInstance3D.new()
	a_mesh.mesh = BoxMesh.new()
	(a_mesh.mesh as BoxMesh).size = a_box.size
	a_mesh.material_override = mat
	arena.add_child(a_mesh)
	arena.position = Vector3(0, -0.3, CORRIDOR_LENGTH + 6.0)
	_nav.add_child(arena)


## The Inquisitor starts behind the player, out of its own vision range, so
## the opening beats read as a chase (Spook's checkpoints) before it catches
## up in the arena for the first, survivable clash.
func _build_inquisitor() -> void:
	var scene: PackedScene = load("res://src/enemies/inquisitor.tscn")
	var inquisitor := scene.instantiate()
	add_child(inquisitor)
	inquisitor.global_position = Vector3(0.0, 0.0, -6.0)
	inquisitor.call("set_patrol_points", PackedVector3Array([Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, CORRIDOR_LENGTH + 6.0)]))


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.2, 0.24)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.55
	moon.light_color = Color(0.8, 0.83, 0.95)
	moon.rotation_degrees = Vector3(-58, 40, 0)
	add_child(moon)


func _build_spook() -> void:
	var spook := NPCTalker.new()
	spook.display_name = "Spook"
	spook.dialogue_id = "spook_flees"
	spook.body_color = Color(0.35, 0.35, 0.38)
	spook.wander_radius = 0.0
	spook.position = Vector3(0.0, 0.0, 2.0)
	add_child(spook)


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, -1.5)
	add_child(spawn)

	var seg_len := CORRIDOR_LENGTH / float(SEGMENT_COUNT)
	for i in range(1, SEGMENT_COUNT + 1):
		var m := Marker3D.new()
		m.add_to_group(&"objective_point")
		m.set_meta("objective_id", "chase_checkpoint_%d" % i)
		m.position = Vector3(0.0, 0.05, float(i) * seg_len)
		add_child(m)

	var arena_marker := Marker3D.new()
	arena_marker.add_to_group(&"objective_point")
	arena_marker.set_meta("objective_id", "chase_arena")
	arena_marker.position = Vector3(0.0, 0.05, CORRIDOR_LENGTH + 6.0)
	add_child(arena_marker)

	var exit_marker := Marker3D.new()
	exit_marker.add_to_group(&"objective_point")
	exit_marker.set_meta("objective_id", "chase_exit")
	exit_marker.position = Vector3(0.0, 0.05, CORRIDOR_LENGTH + 12.0)
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
	mat.albedo_color = Color(0.4, 0.38, 0.4)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, CORRIDOR_LENGTH + 12.0)
	add_child(door)
