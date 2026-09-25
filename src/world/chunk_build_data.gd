class_name ChunkBuildData
extends RefCounted
## Everything needed to instantiate one streamed unit (a grid chunk or a
## landmark), produced off the main thread as plain data.
##
## Generators fill this; `ChunkInstancer` turns it into nodes on the main
## thread. Coordinates are world space (chunk roots sit at the origin).

## Unique streaming key, e.g. "c:-1,2" or "lm:keep_venture".
var key := ""
var coord := Vector2i.ZERO
## Material id (WorldMaterials.Mat) -> WorldMeshBuilder for the main mesh.
var builders: Dictionary = {}
## Material id -> WorldMeshBuilder for small details (visibility-ranged, no shadows).
var detail_builders: Dictionary = {}
## Collision shapes: {"xf": Transform3D, "box": Vector3} or {"xf": Transform3D, "convex": PackedVector3Array}.
var shapes: Array[Dictionary] = []
## Occluder geometry (triangles).
var occ_verts := PackedVector3Array()
var occ_idx := PackedInt32Array()
## Anchored metals on the chunk's static body: {"pos": Vector3, "mass": float}.
var static_metals: Array[Dictionary] = []
## Lamp posts (own StaticBody + Metallic): {"pos", "dir": Vector2, "lit": bool, "shadow": bool}.
var lamp_posts: Array[Dictionary] = []
## PropMeshes kind -> Array of Transform3D (drawn with MultiMeshInstance3D).
var instances: Dictionary = {}
## Omni lights: {"pos", "color", "range", "energy", "shadow"}.
var lights: Array[Dictionary] = []
## Loose rigid props: {"kind": StringName, "xf": Transform3D}.
var rigid: Array[Dictionary] = []
## Static props with their own shapes are merged into builders/shapes above.
## Markers: {"group": StringName, "pos": Vector3, "meta": Dictionary}.
var markers: Array[Dictionary] = []
## Navigation source triangles (world space, 3 vertices per face).
var nav_faces := PackedVector3Array()
## Projected nav obstructions: {"verts": PackedVector3Array, "elevation": float, "height": float}.
var nav_obstructions: Array[Dictionary] = []
## XZ area this unit bakes navigation for (empty = no navigation).
var nav_rect := Rect2()
## Local mist volumes: {"pos": Vector3, "size": Vector3, "density": float}.
var fog_volumes: Array[Dictionary] = []
## Stats for reports/tests.
var metal_count := 0


## Main-mesh builder for material `mat`.
func mb(mat: int) -> WorldMeshBuilder:
	var b: WorldMeshBuilder = builders.get(mat)
	if b == null:
		b = WorldMeshBuilder.new()
		builders[mat] = b
	return b


## Detail-mesh builder for material `mat`.
func db(mat: int) -> WorldMeshBuilder:
	var b: WorldMeshBuilder = detail_builders.get(mat)
	if b == null:
		b = WorldMeshBuilder.new()
		detail_builders[mat] = b
	return b


func add_box_shape(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), center)
	shapes.append({"xf": xf, "box": size})


func add_box_shape_lohi(lo: Vector3, hi: Vector3) -> void:
	add_box_shape((lo + hi) * 0.5, hi - lo)


func add_convex_shape(points: PackedVector3Array) -> void:
	shapes.append({"xf": Transform3D.IDENTITY, "convex": points})


func add_metal(pos: Vector3, mass: float) -> void:
	static_metals.append({"pos": pos, "mass": mass})
	metal_count += 1


func add_instance(kind: StringName, xf: Transform3D) -> void:
	var arr: Array = instances.get(kind, [])
	if arr.is_empty():
		instances[kind] = arr
	arr.append(xf)


func add_light(pos: Vector3, color: Color, light_range: float, energy: float, shadow := false) -> void:
	lights.append({"pos": pos, "color": color, "range": light_range, "energy": energy, "shadow": shadow})


func add_rigid(kind: StringName, xf: Transform3D) -> void:
	rigid.append({"kind": kind, "xf": xf})
	metal_count += 1


func add_marker(group: StringName, pos: Vector3, meta: Dictionary) -> void:
	markers.append({"group": group, "pos": pos, "meta": meta})


## Adds an axis-aligned box to the occluder.
func add_occluder_box(lo: Vector3, hi: Vector3) -> void:
	var b := occ_verts.size()
	for i in 8:
		occ_verts.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	var q := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in q:
		occ_idx.append_array([b + f[0], b + f[1], b + f[2], b + f[0], b + f[2], b + f[3]])


## Adds a horizontal walkable quad (XZ rect at height y) to the nav source.
func add_nav_rect(r: Rect2, y: float) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	# Clockwise seen from above (Godot front face = up).
	nav_faces.append_array([a, b, c, a, c, d])


## Adds a solid box (top + sides) to the nav source as an obstacle/walkable top.
func add_nav_box(lo: Vector3, hi: Vector3, with_top := true) -> void:
	if with_top:
		add_nav_rect(Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z), hi.y)
	var c := [Vector3(lo.x, 0, lo.z), Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z)]
	for i in 4:
		var p: Vector3 = c[i]
		var q: Vector3 = c[(i + 1) % 4]
		var p0 := Vector3(p.x, lo.y, p.z)
		var q0 := Vector3(q.x, lo.y, q.z)
		var p1 := Vector3(p.x, hi.y, p.z)
		var q1 := Vector3(q.x, hi.y, q.z)
		nav_faces.append_array([p0, p1, q1, p0, q1, q0])


## Marks an XZ rectangle as non-walkable between `elevation` and `elevation + height`
## (building interiors), so no nav islands form inside closed buildings.
func add_nav_obstruction(r: Rect2, elevation: float, height: float) -> void:
	var v := PackedVector3Array([Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y),
			Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)])
	nav_obstructions.append({"verts": v, "elevation": elevation, "height": height})


## Adds arbitrary triangles to the nav source.
func add_nav_tris(tris: PackedVector3Array) -> void:
	nav_faces.append_array(tris)


## World-space bounds of the main geometry.
func compute_aabb() -> AABB:
	var ab := AABB()
	var first := true
	for k in builders:
		var b: WorldMeshBuilder = builders[k]
		if b.is_empty():
			continue
		var bb := b.get_aabb()
		ab = bb if first else ab.merge(bb)
		first = false
	return ab
