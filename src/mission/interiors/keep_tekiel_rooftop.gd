extends Node3D
## "House War" interior (Act II): a covert rooftop strike on Keep Tekiel to
## stoke the Venture/Tekiel feud. Staggered rooftop platforms carry a
## `Coinshot` and two `Hazekiller`s; the set piece at the end is a heavy iron
## gate suspended over the courtyard below — Pushed or Pulled hard enough
## (any metal, any direction; see `MissionDirector`'s `push_target` objective)
## it drops and the resulting chaos closes the mission.
##
## Markers: `"interior_spawn"`, `"objective_point"`/`"tekiel_gate"` (where the
## gate's `Metallic` lives — the trigger the objective actually watches is the
## Push/Pull itself, not proximity) and `"objective_point"`/`"tekiel_exit"`.

const ARENA_SIZE := Vector3(24.0, 10.0, 20.0)

## See `canton_resource.gd`'s `_nav` doc: the `Coinshot`/`Hazekiller`s here
## carry a `NavigationAgent3D` and need a baked navmesh to path across the
## staggered platforms at all.
var _nav: NavigationRegion3D


func _ready() -> void:
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_rooftops()
	_nav.navigation_mesh = NavigationMesh.new()
	_nav.bake_navigation_mesh(false)
	_build_lighting()
	_build_gate()
	_build_enemies()
	_build_markers()
	_build_exit_door()


func _build_rooftops() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.28, 0.27)
	var platforms := [
		{"size": Vector3(ARENA_SIZE.x, 0.6, ARENA_SIZE.z), "pos": Vector3(0, -0.3, 0)},
		{"size": Vector3(6.0, 0.6, 5.0), "pos": Vector3(-6.0, 2.2, -3.0)},
		{"size": Vector3(6.0, 0.6, 5.0), "pos": Vector3(6.0, 3.6, 3.0)},
	]
	for p: Dictionary in platforms:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = p["size"]
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		(mesh.mesh as BoxMesh).size = box.size
		mesh.material_override = mat
		body.add_child(mesh)
		body.position = p["pos"]
		_nav.add_child(body)

	# A low parapet ring, with a wide gap on the south side (the way in/out —
	# this is a rooftop, not a walled room, so "leaving" just means walking
	# off the open edge back toward the exit marker).
	var half_x := ARENA_SIZE.x * 0.5
	var half_z := ARENA_SIZE.z * 0.5
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.24, 0.22, 0.22)
	var parapets := [
		{"size": Vector3(ARENA_SIZE.x, 1.0, 0.3), "pos": Vector3(0, 0.5, -half_z)},
		{"size": Vector3(0.3, 1.0, ARENA_SIZE.z), "pos": Vector3(-half_x, 0.5, 0)},
		{"size": Vector3(0.3, 1.0, ARENA_SIZE.z), "pos": Vector3(half_x, 0.5, 0)},
	]
	for w: Dictionary in parapets:
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


## Night sky + the real skyline around Keep Tekiel's roofs (see
## `MissionBackdrop`), with the keep itself masked out — this scene *is* its
## rooftop.
func _build_lighting() -> void:
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(520.0, -640.0)
	bd.ground_y = -18.0
	bd.clear_radius = 80.0
	bd.hide_landmarks = [&"keep_tekiel"]
	add_child(bd)


## The suspended iron gate: a heavy `Metallic` prop tagged with the objective
## id the `push_target` objective watches for.
func _build_gate() -> void:
	var gate := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.5, 0.3)
	shape.shape = box
	gate.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	mat.metallic = 0.8
	mat.roughness = 0.4
	mesh.material_override = mat
	gate.add_child(mesh)
	gate.position = Vector3(0.0, 5.0, -half_z_inner())
	var metallic_script := load("res://src/allomancy/metallic.gd")
	if metallic_script != null:
		var metallic := Node3D.new()
		metallic.set_script(metallic_script)
		metallic.set("metal_mass", 220.0)
		metallic.set_meta("objective_id", "tekiel_gate")
		gate.add_child(metallic)
	add_child(gate)


func half_z_inner() -> float:
	return ARENA_SIZE.z * 0.5 - 2.0


func _build_enemies() -> void:
	var coinshot_scene: PackedScene = load("res://src/enemies/coinshot.tscn")
	var hazekiller_scene: PackedScene = load("res://src/enemies/hazekiller.tscn")

	var cs := coinshot_scene.instantiate()
	add_child(cs)
	cs.global_position = Vector3(-6.0, 2.5, -3.0)

	for pos: Vector3 in [Vector3(4.0, 0.0, 5.0), Vector3(-3.0, 0.0, 6.0)]:
		var hz := hazekiller_scene.instantiate()
		add_child(hz)
		hz.global_position = pos


func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.add_to_group(&"interior_spawn")
	spawn.position = Vector3(0.0, 0.05, ARENA_SIZE.z * 0.5 - 1.5)
	add_child(spawn)

	var gate_marker := Marker3D.new()
	gate_marker.add_to_group(&"objective_point")
	gate_marker.set_meta("objective_id", "tekiel_gate")
	gate_marker.position = Vector3(0.0, 2.0, -half_z_inner())
	add_child(gate_marker)

	var exit_marker := Marker3D.new()
	exit_marker.add_to_group(&"objective_point")
	exit_marker.set_meta("objective_id", "tekiel_exit")
	exit_marker.position = Vector3(0.0, 0.05, ARENA_SIZE.z * 0.5 - 1.5)
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
	mat.albedo_color = Color(0.4, 0.35, 0.3)
	mesh.material_override = mat
	door.add_child(mesh)
	door.position = Vector3(0.0, 1.5, ARENA_SIZE.z * 0.5 - 0.3)
	add_child(door)
