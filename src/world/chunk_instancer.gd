class_name ChunkInstancer
extends RefCounted
## Turns a ChunkBuildData into scene nodes on the main thread, a little at a
## time: call `step(budget_usec)` each frame until it returns true. The root
## node is added to the tree first and children are attached progressively,
## so no single frame pays for the whole chunk.

const M := WorldMaterials.Mat
const WORLD_LAYER := 1
const PROP_LAYER := 1 << 3
const TRIGGER_LAYER := 1 << 5
const PROP_MASK := 1 | 2 | 4 | 8 | 16
const PLAYER_MASK := 2

## Visibility range (m) per MultiMesh kind (0 = unlimited).
const INSTANCE_RANGE := {
	&"lamp_post": 0.0, &"wall_lantern": 170.0, &"window_bars": 90.0, &"chimney_cap": 170.0,
	&"weathervane": 220.0, &"lightning_rod": 260.0, &"bollard": 130.0, &"stall": 160.0, &"well": 200.0,
}
const DETAIL_RANGE := 150.0
const WINDOW_RANGE := 420.0
const RIGID_RANGE := 110.0
const NO_SHADOW_MATS := [M.WATER, M.WINDOW, M.LANTERN_GLASS]

static var _lamp_shape: BoxShape3D
static var _checkpoint_shape: BoxShape3D

var data: ChunkBuildData
var root: Node3D
var static_body: StaticBody3D
var nav_region: NavigationRegion3D
## The navmesh being baked (kept so shutdown can wait for the bake).
var nav_mesh: NavigationMesh
var fog_material: Material
var _parent: Node3D
var _stage := 0
var _cursor := 0
var _done := false
## Emitted through the streamer when the navmesh finishes baking.
var nav_ready := false
var draw_meshes := 0


func _init(build: ChunkBuildData, parent: Node3D, canal_fog: Material) -> void:
	data = build
	_parent = parent
	fog_material = canal_fog


func is_done() -> bool:
	return _done


## Performs work until `budget_usec` is spent. Returns true when finished.
func step(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _done:
		_step_once()
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	return _done


func _step_once() -> void:
	match _stage:
		0:
			root = Node3D.new()
			root.name = data.key.replace(":", "_").replace(",", "_").replace("-", "m")
			root.set_meta(&"stream_key", data.key)
			_parent.add_child(root)
			static_body = StaticBody3D.new()
			static_body.name = "Static"
			static_body.collision_layer = WORLD_LAYER
			static_body.collision_mask = 0
			root.add_child(static_body)
			_stage += 1
		1:
			_build_meshes()
			_stage += 1
		2:
			if _batch(data.shapes.size(), 96, _add_shape):
				_stage += 1
		3:
			_build_occluder()
			_build_multimeshes()
			_stage += 1
		4:
			if _batch(data.static_metals.size(), 64, _add_static_metal):
				_stage += 1
		5:
			if _batch(data.lamp_posts.size(), 24, _add_lamp):
				_stage += 1
		6:
			if _batch(data.lights.size(), 48, _add_light):
				_stage += 1
		7:
			if _batch(data.rigid.size(), 16, _add_rigid):
				_stage += 1
		8:
			for m in data.markers:
				_add_marker(m)
			for f in data.fog_volumes:
				_add_fog(f)
			_stage += 1
		_:
			_done = true


## Calls `fn(i)` for the next `per_step` items; returns true when all are done.
func _batch(total: int, per_step: int, fn: Callable) -> bool:
	var end := mini(total, _cursor + per_step)
	for i in range(_cursor, end):
		fn.call(i)
	_cursor = end
	if _cursor >= total:
		_cursor = 0
		return true
	return false


func _make_mesh(builders: Dictionary, filter: Callable) -> ArrayMesh:
	var am := ArrayMesh.new()
	for mat: int in builders:
		if not filter.call(mat):
			continue
		var b: WorldMeshBuilder = builders[mat]
		if b.is_empty():
			continue
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.to_arrays())
		am.surface_set_material(am.get_surface_count() - 1, WorldMaterials.get_mat(mat))
	return am if am.get_surface_count() > 0 else null


func _mesh_instance(mesh: ArrayMesh, mi_name: String, shadows: bool, range_end: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = mi_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)
	draw_meshes += mesh.get_surface_count()


func _build_meshes() -> void:
	_mesh_instance(_make_mesh(data.builders, func(m: int) -> bool: return not m in NO_SHADOW_MATS), "Mesh", true, 0.0)
	_mesh_instance(_make_mesh(data.builders, func(m: int) -> bool: return m in NO_SHADOW_MATS), "Water", false, 0.0)
	_mesh_instance(_make_mesh(data.detail_builders, func(m: int) -> bool: return m == M.WINDOW), "Windows", false, WINDOW_RANGE)
	_mesh_instance(_make_mesh(data.detail_builders, func(m: int) -> bool: return m != M.WINDOW), "Detail", false, DETAIL_RANGE)


func _add_shape(i: int) -> void:
	var s: Dictionary = data.shapes[i]
	var cs := CollisionShape3D.new()
	if s.has("box"):
		var b := BoxShape3D.new()
		b.size = s["box"]
		cs.shape = b
	else:
		var c := ConvexPolygonShape3D.new()
		c.points = s["convex"]
		cs.shape = c
	cs.transform = s["xf"]
	static_body.add_child(cs)


func _build_occluder() -> void:
	if data.occ_idx.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(data.occ_verts, data.occ_idx)
	var oi := OccluderInstance3D.new()
	oi.name = "Occluder"
	oi.occluder = occ
	root.add_child(oi)


func _build_multimeshes() -> void:
	for kind: StringName in data.instances:
		var xfs: Array = data.instances[kind]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropMeshes.mesh(kind)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % kind
		mmi.multimesh = mm
		var r: float = INSTANCE_RANGE.get(kind, 150.0)
		if r > 0.0:
			mmi.visibility_range_end = r
			mmi.visibility_range_end_margin = 10.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in [&"lamp_post", &"lightning_rod", &"weathervane"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		draw_meshes += mm.mesh.get_surface_count()
	# Lamp post visuals.
	if not data.lamp_posts.is_empty():
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = PropMeshes.mesh(&"lamp_post")
		mm2.instance_count = data.lamp_posts.size()
		for i in data.lamp_posts.size():
			var lp: Dictionary = data.lamp_posts[i]
			var d: Vector2 = lp["dir"]
			var bx := Basis.looking_at(Vector3(d.x, 0, d.y)) if d.length() > 0.01 else Basis()
			mm2.set_instance_transform(i, Transform3D(bx, lp["pos"]))
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.name = "MM_lamp_posts"
		mmi2.multimesh = mm2
		root.add_child(mmi2)
		draw_meshes += mm2.mesh.get_surface_count()


func _add_static_metal(i: int) -> void:
	var m: Dictionary = data.static_metals[i]
	var met := Metallic.new()
	met.metal_mass = m["mass"]
	met.anchored = true
	met.position = m["pos"]
	static_body.add_child(met)


func _add_lamp(i: int) -> void:
	if _lamp_shape == null:
		_lamp_shape = BoxShape3D.new()
		_lamp_shape.size = Vector3(0.24, 4.2, 0.24)
	var lp: Dictionary = data.lamp_posts[i]
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = lp["pos"]
	body.add_to_group(&"lamp_post")
	var cs := CollisionShape3D.new()
	cs.shape = _lamp_shape
	cs.position = Vector3(0, 2.1, 0)
	body.add_child(cs)
	var met := Metallic.new()
	met.metal_mass = 60.0
	met.anchored = true
	met.position = Vector3(0, 3.0, 0)
	body.add_child(met)
	root.add_child(body)


func _add_light(i: int) -> void:
	var l: Dictionary = data.lights[i]
	var o := OmniLight3D.new()
	o.position = l["pos"]
	o.light_color = l["color"]
	o.light_energy = l["energy"]
	o.omni_range = l["range"]
	o.omni_attenuation = 1.2
	o.light_specular = 0.4
	o.light_volumetric_fog_energy = 2.5
	o.shadow_enabled = l["shadow"]
	o.distance_fade_enabled = true
	o.distance_fade_begin = 70.0 if l["shadow"] else 55.0
	o.distance_fade_length = 20.0
	o.distance_fade_shadow = 30.0
	if l["shadow"]:
		o.add_to_group(&"world_shadow_light")
	root.add_child(o)


func _add_rigid(i: int) -> void:
	var r: Dictionary = data.rigid[i]
	var kind: StringName = r["kind"]
	var def: Array = PropMeshes.RIGID[kind]
	var rb := RigidBody3D.new()
	rb.collision_layer = PROP_LAYER
	rb.collision_mask = PROP_MASK
	rb.mass = def[0]
	rb.transform = r["xf"]
	rb.can_sleep = true
	rb.sleeping = true
	rb.add_to_group(&"metal_prop")
	if kind in [&"horseshoe", &"scrap", &"bucket"]:
		rb.continuous_cd = true
	var cs := CollisionShape3D.new()
	cs.shape = PropMeshes.shape(kind)
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = PropMeshes.mesh(kind)
	mi.visibility_range_end = RIGID_RANGE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	var met := Metallic.new()
	met.metal_mass = def[1]
	met.position = def[4]
	rb.add_child(met)
	root.add_child(rb)


func _add_marker(m: Dictionary) -> void:
	var group: StringName = m["group"]
	var meta: Dictionary = m["meta"]
	var mk := Marker3D.new()
	mk.position = m["pos"]
	mk.add_to_group(group)
	for k: String in meta:
		mk.set_meta(StringName(k), meta[k])
	if meta.has("objective_id"):
		mk.name = String(meta["objective_id"])
	elif meta.has("enemy_type"):
		mk.name = "enemy_%s" % meta["enemy_type"]
	elif meta.has("pickup_kind"):
		mk.name = "pickup_%s" % meta["pickup_kind"]
	else:
		mk.name = String(group)
	root.add_child(mk, true)
	if meta.has("checkpoint_id"):
		if _checkpoint_shape == null:
			_checkpoint_shape = BoxShape3D.new()
			_checkpoint_shape.size = Vector3(8, 5, 8)
		var area := Area3D.new()
		area.name = "Checkpoint_%s" % meta["checkpoint_id"]
		area.collision_layer = TRIGGER_LAYER
		area.collision_mask = PLAYER_MASK
		area.monitorable = false
		area.position = m["pos"] + Vector3(0, 2.0, 0)
		area.set_meta(&"checkpoint_id", meta["checkpoint_id"])
		area.add_to_group(&"checkpoint")
		var cs := CollisionShape3D.new()
		cs.shape = _checkpoint_shape
		area.add_child(cs)
		root.add_child(area)


func _add_fog(f: Dictionary) -> void:
	if fog_material == null:
		return
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.size = f["size"]
	fv.position = f["pos"]
	fv.material = fog_material
	fv.add_to_group(&"mist_volume")
	root.add_child(fv)


## Starts the asynchronous navmesh bake for this unit. `on_done` is called
## (deferred, on the main thread) when finished.
func bake_navigation(on_done: Callable) -> void:
	if data.nav_rect.size == Vector2.ZERO or data.nav_faces.is_empty():
		nav_ready = true
		on_done.call_deferred()
		return
	var nm := NavigationMesh.new()
	nav_mesh = nm
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 45.0
	nm.border_size = ChunkGenerator.NAV_BORDER
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var r := data.nav_rect.grow(ChunkGenerator.NAV_BORDER)
	nm.filter_baking_aabb = AABB(Vector3(r.position.x, -8.0, r.position.y), Vector3(r.size.x, 120.0, r.size.y))
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(data.nav_faces, Transform3D.IDENTITY)
	for ob in data.nav_obstructions:
		src.add_projected_obstruction(ob["verts"], ob["elevation"], ob["height"], false)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	root.add_child(nav_region)
	var region_ref: WeakRef = weakref(nav_region)
	var self_ref: WeakRef = weakref(self)
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
		_finish_nav.call_deferred(region_ref, nm, self_ref, on_done))


static func _finish_nav(region_ref: WeakRef, nm: NavigationMesh, self_ref: WeakRef, on_done: Callable) -> void:
	var region := region_ref.get_ref() as NavigationRegion3D
	if region != null and region.is_inside_tree():
		region.navigation_mesh = nm
	var inst := self_ref.get_ref() as ChunkInstancer
	if inst != null:
		inst.nav_ready = true
	if on_done.is_valid():
		on_done.call()


## Blocks until an in-flight navmesh bake finishes (used on shutdown).
func wait_for_bake(max_msec := 10000) -> void:
	var t0 := Time.get_ticks_msec()
	while nav_mesh != null and NavigationServer3D.is_baking_navigation_mesh(nav_mesh):
		if Time.get_ticks_msec() - t0 > max_msec:
			break
		OS.delay_msec(2)


## Frees the unit's nodes (Metallics unregister themselves on exit).
func free_nodes() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
