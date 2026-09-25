class_name WorldMeshBuilder
extends RefCounted
## Fast geometry accumulator for merged world meshes.
##
## Writes straight into packed arrays (no SurfaceTool overhead) so worker
## threads can build a whole chunk's geometry cheaply. Uses Godot's clockwise
## front-face winding. Call `to_arrays()` and hand the result to
## `ArrayMesh.add_surface_from_arrays` on the main thread.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var tangents := PackedFloat32Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


func is_empty() -> bool:
	return indices.is_empty()


func vertex_count() -> int:
	return verts.size()


## Adds a quad. Corners are bottom-left, bottom-right, top-right, top-left as
## seen from the front. `cb` colours the bottom edge and `ct` the top edge.
func add_quad(bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, n: Vector3,
		cb: Color, ct: Color, uv_max := Vector2.ONE) -> void:
	var i := verts.size()
	verts.append(bl)
	verts.append(br)
	verts.append(tr)
	verts.append(tl)
	for _k in 4:
		normals.append(n)
	var t := (br - bl).normalized()
	for _k in 4:
		tangents.append(t.x)
		tangents.append(t.y)
		tangents.append(t.z)
		tangents.append(1.0)
	colors.append(cb)
	colors.append(cb)
	colors.append(ct)
	colors.append(ct)
	uvs.append(Vector2(0.0, uv_max.y))
	uvs.append(Vector2(uv_max.x, uv_max.y))
	uvs.append(Vector2(uv_max.x, 0.0))
	uvs.append(Vector2(0.0, 0.0))
	indices.append(i)
	indices.append(i + 3)
	indices.append(i + 2)
	indices.append(i)
	indices.append(i + 2)
	indices.append(i + 1)


## Adds a single triangle (a, b, c counter-clockwise seen from the front).
func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var i := verts.size()
	var n := (b - a).cross(c - a).normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	var t := (b - a).normalized()
	for _k in 3:
		normals.append(n)
		colors.append(col)
		tangents.append(t.x)
		tangents.append(t.y)
		tangents.append(t.z)
		tangents.append(1.0)
	uvs.append(Vector2(0, 1))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0.5, 0))
	indices.append(i)
	indices.append(i + 2)
	indices.append(i + 1)


## Axis-aligned box from `lo` to `hi`. Side faces fade from `cb` (bottom) to
## `ct` (top); the top face uses `ctop`. The bottom face is omitted unless
## `bottom` is true (most world boxes sit on the ground).
func add_box(lo: Vector3, hi: Vector3, cb: Color, ct: Color, ctop: Color, bottom := false) -> void:
	# +Z face (south)
	add_quad(Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z),
			Vector3(lo.x, hi.y, hi.z), Vector3.BACK, cb, ct)
	# -Z face (north)
	add_quad(Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(hi.x, hi.y, lo.z), Vector3.FORWARD, cb, ct)
	# +X face (east)
	add_quad(Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(hi.x, hi.y, hi.z), Vector3.RIGHT, cb, ct)
	# -X face (west)
	add_quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z),
			Vector3(lo.x, hi.y, lo.z), Vector3.LEFT, cb, ct)
	# top
	add_quad(Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(lo.x, hi.y, lo.z), Vector3.UP, ctop, ctop)
	if bottom:
		add_quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z),
				Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, cb, cb)


## Box whose four walls are split at `band_y` so vertex colours can express
## a sooty base, a cleaner middle and a grimy top: `c0` at the ground, `c1`
## at `band_y`, `c2` at the top. `skip` is a bitmask of side faces to omit
## (1 = +Z, 2 = -Z, 4 = +X, 8 = -X), used for shared party walls.
func add_banded_box(lo: Vector3, hi: Vector3, band_y: float, c0: Color, c1: Color, c2: Color,
		ctop: Color, skip := 0, top := true) -> void:
	var ys := [lo.y, clampf(band_y, lo.y, hi.y), hi.y]
	var cs := [c0, c1, c2]
	for b in 2:
		var y0: float = ys[b]
		var y1: float = ys[b + 1]
		if y1 - y0 < 0.01:
			continue
		var ca: Color = cs[b]
		var cc: Color = cs[b + 1]
		if skip & 1 == 0:
			add_quad(Vector3(lo.x, y0, hi.z), Vector3(hi.x, y0, hi.z), Vector3(hi.x, y1, hi.z),
					Vector3(lo.x, y1, hi.z), Vector3.BACK, ca, cc)
		if skip & 2 == 0:
			add_quad(Vector3(hi.x, y0, lo.z), Vector3(lo.x, y0, lo.z), Vector3(lo.x, y1, lo.z),
					Vector3(hi.x, y1, lo.z), Vector3.FORWARD, ca, cc)
		if skip & 4 == 0:
			add_quad(Vector3(hi.x, y0, hi.z), Vector3(hi.x, y0, lo.z), Vector3(hi.x, y1, lo.z),
					Vector3(hi.x, y1, hi.z), Vector3.RIGHT, ca, cc)
		if skip & 8 == 0:
			add_quad(Vector3(lo.x, y0, lo.z), Vector3(lo.x, y0, hi.z), Vector3(lo.x, y1, hi.z),
					Vector3(lo.x, y1, lo.z), Vector3.LEFT, ca, cc)
	if top:
		add_quad(Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z),
				Vector3(lo.x, hi.y, lo.z), Vector3.UP, ctop, ctop)


## Oriented box: centre, half extents and a Y rotation (radians).
func add_obox(center: Vector3, half: Vector3, yaw: float, cb: Color, ct: Color) -> void:
	var bx := Basis(Vector3.UP, yaw)
	var ax := bx.x * half.x
	var az := bx.z * half.z
	var y0 := center.y - half.y
	var y1 := center.y + half.y
	var c := Vector3(center.x, 0.0, center.z)
	var p := [c - ax + az, c + ax + az, c + ax - az, c - ax - az]  # sw, se, ne, nw (local)
	var nrm := [bx.z, bx.x, -bx.z, -bx.x]
	for i in 4:
		var a: Vector3 = p[i]
		var b: Vector3 = p[(i + 1) % 4]
		var n: Vector3 = nrm[i]
		add_quad(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z),
				Vector3(a.x, y1, a.z), n, cb, ct)
	var t0: Vector3 = p[0]
	var t1: Vector3 = p[1]
	var t2: Vector3 = p[2]
	var t3: Vector3 = p[3]
	add_quad(Vector3(t0.x, y1, t0.z), Vector3(t1.x, y1, t1.z), Vector3(t2.x, y1, t2.z),
			Vector3(t3.x, y1, t3.z), Vector3.UP, ct, ct)


## Gable (pitched) roof over rect lo..hi (XZ) starting at `y`, with ridge
## height `rise`. Ridge runs along X if `along_x`. `ov` is the eave overhang.
## Slopes go into this builder; gable-end triangles go into `gable_builder`.
func add_gable_roof(lo: Vector2, hi: Vector2, y: float, rise: float, along_x: bool, ov: float,
		col: Color, gable_builder: WorldMeshBuilder, gable_col: Color) -> void:
	var ry := y + rise
	if along_x:
		var zm := (lo.y + hi.y) * 0.5
		var x0 := lo.x - ov * 0.5
		var x1 := hi.x + ov * 0.5
		var z0 := lo.y - ov
		var z1 := hi.y + ov
		var drop := rise * ov / maxf((hi.y - lo.y) * 0.5, 0.1)
		# south slope (+Z facing)
		var ns := Vector3(0.0, (hi.y - zm), rise).normalized()
		add_quad(Vector3(x0, y - drop, z1), Vector3(x1, y - drop, z1), Vector3(x1, ry, zm),
				Vector3(x0, ry, zm), ns, col, col.lightened(0.05))
		var nn := Vector3(0.0, (zm - lo.y), -rise).normalized()
		add_quad(Vector3(x1, y - drop, z0), Vector3(x0, y - drop, z0), Vector3(x0, ry, zm),
				Vector3(x1, ry, zm), nn, col, col.lightened(0.05))
		if gable_builder != null:
			gable_builder.add_tri(Vector3(lo.x, y, lo.y), Vector3(lo.x, y, hi.y), Vector3(lo.x, ry, zm), gable_col)
			gable_builder.add_tri(Vector3(hi.x, y, hi.y), Vector3(hi.x, y, lo.y), Vector3(hi.x, ry, zm), gable_col)
	else:
		var xm := (lo.x + hi.x) * 0.5
		var x0 := lo.x - ov
		var x1 := hi.x + ov
		var z0 := lo.y - ov * 0.5
		var z1 := hi.y + ov * 0.5
		var drop := rise * ov / maxf((hi.x - lo.x) * 0.5, 0.1)
		var ne := Vector3(rise, (hi.x - xm), 0.0).normalized()
		add_quad(Vector3(x1, y - drop, z1), Vector3(x1, y - drop, z0), Vector3(xm, ry, z0),
				Vector3(xm, ry, z1), ne, col, col.lightened(0.05))
		var nw := Vector3(-rise, (xm - lo.x), 0.0).normalized()
		add_quad(Vector3(x0, y - drop, z0), Vector3(x0, y - drop, z1), Vector3(xm, ry, z1),
				Vector3(xm, ry, z0), nw, col, col.lightened(0.05))
		if gable_builder != null:
			gable_builder.add_tri(Vector3(lo.x, y, hi.y), Vector3(hi.x, y, hi.y), Vector3(xm, ry, hi.y), gable_col)
			gable_builder.add_tri(Vector3(hi.x, y, lo.y), Vector3(lo.x, y, lo.y), Vector3(xm, ry, lo.y), gable_col)


## Four-sided pyramid (spire / tower cap) over a square base.
func add_pyramid(center: Vector3, half: float, rise: float, col: Color) -> void:
	var apex := center + Vector3(0.0, rise, 0.0)
	var a := center + Vector3(-half, 0.0, half)
	var b := center + Vector3(half, 0.0, half)
	var c := center + Vector3(half, 0.0, -half)
	var d := center + Vector3(-half, 0.0, -half)
	add_tri(a, b, apex, col)
	add_tri(b, c, apex, col)
	add_tri(c, d, apex, col)
	add_tri(d, a, apex, col)


## Tapered square prism (frustum) from `half0` at y0 to `half1` at y1.
func add_frustum(center: Vector3, half0: float, half1: float, height: float, cb: Color, ct: Color) -> void:
	var y0 := center.y
	var y1 := center.y + height
	var cx := center.x
	var cz := center.z
	var lo := [Vector3(cx - half0, y0, cz + half0), Vector3(cx + half0, y0, cz + half0),
			Vector3(cx + half0, y0, cz - half0), Vector3(cx - half0, y0, cz - half0)]
	var up := [Vector3(cx - half1, y1, cz + half1), Vector3(cx + half1, y1, cz + half1),
			Vector3(cx + half1, y1, cz - half1), Vector3(cx - half1, y1, cz - half1)]
	for i in 4:
		var j := (i + 1) % 4
		var a: Vector3 = lo[i]
		var b: Vector3 = lo[j]
		var c: Vector3 = up[j]
		var d: Vector3 = up[i]
		var n := (b - a).cross(d - a).normalized()
		add_quad(a, b, c, d, n, cb, ct)


## Appends another builder's geometry, offset by `offset`.
func append_builder(o: WorldMeshBuilder, offset := Vector3.ZERO) -> void:
	var base := verts.size()
	if offset == Vector3.ZERO:
		verts.append_array(o.verts)
	else:
		for v in o.verts:
			verts.append(v + offset)
	normals.append_array(o.normals)
	tangents.append_array(o.tangents)
	colors.append_array(o.colors)
	uvs.append_array(o.uvs)
	for i in o.indices:
		indices.append(i + base)


## Returns the Mesh.ARRAY_MAX array for `ArrayMesh.add_surface_from_arrays`.
func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


## Axis-aligned bounds of everything added so far.
func get_aabb() -> AABB:
	if verts.is_empty():
		return AABB()
	var ab := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		ab = ab.expand(v)
	return ab
