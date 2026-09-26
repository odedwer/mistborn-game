class_name InteriorKit
extends RefCounted
## Small static helpers shared by the Act III mission spaces (rebel caves,
## battlefield, Fountain Square, Keep Venture's library, Kredik Shaw, the
## palace pits, the throne room), so each scene script reads as a layout
## rather than a wall of node boilerplate. Everything the earlier interiors
## hand-roll (collision box + mesh, markers, the exit door, talkable NPCs,
## anchored metal) lives here once.


static func mat(color: Color, metallic := 0.0, roughness := 0.9, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


## A static box (collision + mesh) of `size` centred at `pos`. `yaw` in
## radians. Returns the body so callers can tag it or add a `Metallic`.
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, yaw := 0.0, collide := true) -> Node3D:
	var root: Node3D
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		root = body
	else:
		root = Node3D.new()
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	root.add_child(mesh)
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	return root


## A tapering spire/pillar (frustum): collision is a cylinder of the base
## radius. `top` is the top radius (0 for a point).
static func spire(parent: Node, base: Vector3, radius: float, top: float, height: float, material: Material, collide := true, sides := 6) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = top
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	mesh.mesh = cm
	mesh.material_override = material
	mesh.position.y = height * 0.5
	root.add_child(mesh)
	if collide:
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = maxf(radius, top) * 0.85
		cs.height = height
		shape.shape = cs
		shape.position.y = height * 0.5
		root.add_child(shape)
	root.position = base
	parent.add_child(root)
	return root


static func marker(parent: Node, group: StringName, id: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.add_to_group(group)
	if id != "":
		m.set_meta("objective_id", id)
	m.position = pos
	parent.add_child(m)
	return m


static func spawn_point(parent: Node, pos: Vector3, yaw := 0.0) -> Marker3D:
	var m := Marker3D.new()
	m.add_to_group(&"interior_spawn")
	m.position = pos
	m.rotation.y = yaw
	parent.add_child(m)
	return m


## A door back out to the open world (`interior_door.gd`, `is_exit`).
static func exit_door(parent: Node, pos: Vector3, yaw := 0.0, color := Color(0.4, 0.34, 0.28)) -> StaticBody3D:
	var door := StaticBody3D.new()
	door.name = "ExitDoor"
	door.set_script(load("res://src/world/interior_door.gd"))
	door.set("is_exit", true)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 3.0, 0.4)
	shape.shape = bs
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mesh.mesh = bm
	mesh.material_override = mat(color)
	door.add_child(mesh)
	door.position = pos + Vector3(0, 1.5, 0)
	door.rotation.y = yaw
	parent.add_child(door)
	return door


## A talkable crew/NPC placeholder (the same `NPCTalker` hookup the
## character pass is replacing with real models).
static func npc(parent: Node, display_name: String, dialogue_id: String, color: Color, pos: Vector3, yaw := 0.0, wander := 0.0) -> NPCTalker:
	var n := NPCTalker.new()
	n.name = display_name.replace(" ", "")
	n.display_name = display_name
	n.dialogue_id = dialogue_id
	n.body_color = color
	n.wander_radius = wander
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n


static func light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = pos
	parent.add_child(l)
	return l


## A brazier/campfire: a squat stand, an emissive coal bed and a warm light.
static func brazier(parent: Node, pos: Vector3, energy := 2.2, rng := 10.0) -> void:
	box(parent, Vector3(0.9, 0.8, 0.9), pos + Vector3(0, 0.4, 0), mat(Color(0.18, 0.16, 0.15), 0.6, 0.5))
	box(parent, Vector3(0.7, 0.12, 0.7), pos + Vector3(0, 0.86, 0), mat(Color(1.0, 0.45, 0.15), 0.0, 1.0, Color(1.0, 0.4, 0.1), 3.0), 0.0, false)
	var l := light(parent, pos + Vector3(0, 1.6, 0), Color(1.0, 0.55, 0.25), energy, rng)
	# Under a MissionBackdrop's volumetric fog a full-strength fire light
	# blooms into a white orb; keep its fog contribution subtle.
	l.light_volumetric_fog_energy = 0.15
	l.add_to_group(&"lantern")


## Adds an anchored/free `Metallic` to `body` at local `offset`.
static func add_metal(body: Node3D, mass: float, offset := Vector3.ZERO, anchored := true, objective_id := "") -> Metallic:
	var m := Metallic.new()
	m.metal_mass = mass
	m.anchored = anchored
	m.position = offset
	if objective_id != "":
		body.set_meta("objective_id", objective_id)
	body.add_child(m)
	return m


## A simple flat-colour environment for enclosed spaces (caves, halls,
## cells) that have no sky to show.
static func enclosed_environment(parent: Node, ambient: Color, energy: float, fog_color := Color(0.05, 0.05, 0.06), fog_density := 0.01) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = energy
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.2
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.fog_enabled = true
	e.fog_light_color = fog_color
	e.fog_density = fog_density
	we.environment = e
	we.add_to_group(&"world_environment")
	parent.add_child(we)
	return we


## Bakes a navmesh from `region`'s static-body collision shapes (not the
## render meshes — see the runtime-bake warning in the Act II interiors).
static func bake_nav(region: NavigationRegion3D, cell := 0.25) -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = cell
	nm.agent_radius = 0.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
