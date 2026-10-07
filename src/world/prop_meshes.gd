class_name PropMeshes
extends RefCounted
## Shared procedural meshes and collision shapes for repeated props
## (lamp posts, lanterns, window bars, rooftop ironwork, loose props).
## Built once on the main thread and reused by every chunk.

const M := WorldMaterials.Mat

## Loose rigid prop definitions: kind -> [mass kg, metal_mass, shape kind, shape size, metal offset].
const RIGID := {
	&"crate": [25.0, 5.0, "box", Vector3(0.8, 0.8, 0.8), Vector3(0, 0.3, 0)],
	&"barrel": [40.0, 6.0, "cyl", Vector3(0.36, 0.95, 0.36), Vector3(0, 0.3, 0)],
	&"bucket": [4.0, 2.0, "cyl", Vector3(0.19, 0.32, 0.19), Vector3.ZERO],
	&"horseshoe": [0.4, 0.4, "box", Vector3(0.14, 0.03, 0.14), Vector3.ZERO],
	&"scrap": [3.0, 3.0, "box", Vector3(0.55, 0.1, 0.3), Vector3.ZERO],
	&"cart": [120.0, 25.0, "box", Vector3(2.2, 0.8, 1.3), Vector3(0, -0.2, 0.62)],
}

## Modillions dither out between these distances (m) from the camera.
const MODILLION_FADE := Vector2(32.0, 48.0)

static var _meshes: Dictionary = {}
static var _shapes: Dictionary = {}


static func mesh(kind: StringName) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m := _build(kind)
	if kind == &"modillion":
		# Brackets dither out instead of popping when their cell culls (see
		# ChunkInstancer.INSTANCE_MARGIN). Past 48 m one covers 2-3 px.
		(m as ArrayMesh).surface_set_material(0, WorldMaterials.faded(M.ASHLAR, MODILLION_FADE.x, MODILLION_FADE.y))
	_meshes[kind] = m
	return m


## Shared collision shape for a rigid prop kind.
static func shape(kind: StringName) -> Shape3D:
	if _shapes.has(kind):
		return _shapes[kind]
	var def: Array = RIGID[kind]
	var s: Shape3D
	var size: Vector3 = def[3]
	if def[2] == "cyl":
		var c := CylinderShape3D.new()
		c.radius = size.x
		c.height = size.y
		s = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		s = b
	_shapes[kind] = s
	return s


static func clear() -> void:
	_meshes.clear()
	_shapes.clear()


static func _commit(parts: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	for mat: int in parts:
		var b: WorldMeshBuilder = parts[mat]
		if b.is_empty():
			continue
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.to_arrays())
		am.surface_set_material(am.get_surface_count() - 1, WorldMaterials.get_mat(mat))
	return am


## Octagonal prism helper (around Y).
static func _prism(b: WorldMeshBuilder, center: Vector3, radius: float, height: float, sides: int,
		col: Color, cap := true) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := center + Vector3(sin(a0), 0, cos(a0)) * radius
		var p1 := center + Vector3(sin(a1), 0, cos(a1)) * radius
		var n := Vector3(sin((a0 + a1) * 0.5), 0, cos((a0 + a1) * 0.5))
		b.add_quad(p0, p1, p1 + Vector3.UP * height, p0 + Vector3.UP * height, n, col, col)
		if cap:
			var top := center + Vector3.UP * height
			b.add_tri(p0 + Vector3.UP * height, p1 + Vector3.UP * height, top, col)


## A tapered four-sided limb from `a` to `b` (radius `r0` -> `r1`): used for
## tree branches, which need arbitrary directions (boxes are axis-aligned).
static func _limb(b: WorldMeshBuilder, a: Vector3, e: Vector3, r0: float, r1: float, col: Color) -> void:
	var d := (e - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := u.cross(d)
	for k in 4:
		var a0 := TAU * float(k) / 4.0 + 0.785
		var a1 := TAU * float(k + 1) / 4.0 + 0.785
		var o0 := u * sin(a0) + v * cos(a0)
		var o1 := u * sin(a1) + v * cos(a1)
		var nm := (o0 + o1).normalized()
		b.add_quad(a + o0 * r0, a + o1 * r0, e + o1 * r1, e + o0 * r1, nm, col, col * 0.85)


## Tapered `sides`-gon tube from `a` to `e` (radii r0 -> r1) with smooth
## normals; `cap` closes the `e` end (a hand, a finial).
static func _limb_n(b: WorldMeshBuilder, a: Vector3, e: Vector3, r0: float, r1: float, col: Color,
		sides: int, cap := false) -> void:
	var d := (e - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := u.cross(d)
	var slope := (r0 - r1) / maxf(a.distance_to(e), 0.001)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var o0 := u * sin(a0) + v * cos(a0)
		var o1 := u * sin(a1) + v * cos(a1)
		var n0 := (o0 + d * slope).normalized()
		var n1 := (o1 + d * slope).normalized()
		b.add_quad_smooth(a + o0 * r0, a + o1 * r0, e + o1 * r1, e + o0 * r1, n0, n1, n1, n0, col * 0.9, col)
		if cap:
			b.add_tri(e + o0 * r1, e + o1 * r1, e + d * r1 * 0.6, col)


## A lathed solid around Y with smooth normals. Each ring is
## [y, rx, rz, z offset, shade]: elliptical cross-sections (wider across the
## shoulders than front to back) whose centres can lean (a cloak). The top
## ring is capped unless `cap` is false.
static func _lathe(b: WorldMeshBuilder, rings: Array, sides: int, col: Color, cap := true) -> void:
	var n := rings.size()
	for k in n - 1:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		var rp: Array = rings[maxi(k - 1, 0)]
		var rn: Array = rings[mini(k + 2, n - 1)]
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			b.add_quad_smooth(_ring_pt(r0, a0), _ring_pt(r0, a1), _ring_pt(r1, a1), _ring_pt(r1, a0),
					_ring_n(rp, r0, r1, a0), _ring_n(rp, r0, r1, a1), _ring_n(r0, r1, rn, a1), _ring_n(r0, r1, rn, a0),
					col * float(r0[4]), col * float(r1[4]))
	if cap:
		var top: Array = rings[n - 1]
		var c := Vector3(0, float(top[0]), float(top[3]))
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			b.add_tri(_ring_pt(top, a0), _ring_pt(top, a1), c, col * float(top[4]))


## Head rows for `_statue_head`: [y, rx, rz, z offset, shade]. The first sits
## inside the neck (the 12-sided neck and the 20-column head can't share
## vertices, so they overlap instead of leaving a crack).
const HEAD_ROWS := [[1.7, 0.077, 0.08, 0.02, 0.85], [1.745, 0.085, 0.108, 0.045, 0.8],
		[1.77, 0.106, 0.127, 0.042, 0.9], [1.79, 0.12, 0.137, 0.038, 0.95], [1.81, 0.129, 0.144, 0.035, 0.97],
		[1.84, 0.137, 0.149, 0.03, 1.0], [1.865, 0.139, 0.151, 0.027, 1.0], [1.88, 0.139, 0.151, 0.025, 1.0],
		[1.898, 0.139, 0.15, 0.022, 1.0], [1.925, 0.134, 0.146, 0.018, 1.0], [1.97, 0.108, 0.122, 0.01, 1.0]]
## Head columns (degrees from the front, +Z, towards +X): close over the face
## so the sockets, the nose and the mouth have vertices, sparse behind it.
const HEAD_COLS := [0.0, 6.0, 14.0, 24.0, 36.0, 50.0, 68.0, 90.0, 115.0, 145.0, 180.0,
		215.0, 245.0, 270.0, 292.0, 310.0, 324.0, 336.0, 346.0, 354.0]
## Nose profile: [y, forward offset at the ridge].
const NOSE := [[1.79, 0.0], [1.81, 0.012], [1.84, 0.042], [1.865, 0.022], [1.88, 0.012], [1.898, 0.004], [1.93, 0.0]]
const HEAD_APEX := Vector3(0, 2.008, 0.002)


## The statue's head (faces +Z): an elliptical lathe whose rows are pushed in
## and out over the face: eye sockets under a brow ridge, a nose, a mouth
## line, a chin and cheekbones, plus two ears. Recesses are darkened in the
## vertex colour, which the bronze shader also reads as where the patina
## gathers. About 470 triangles.
static func _statue_head(b: WorldMeshBuilder, col: Color) -> void:
	var nr := HEAD_ROWS.size()
	var nc := HEAD_COLS.size()
	var pts: Array[Vector3] = []
	var shades := PackedFloat32Array()
	for r: Array in HEAD_ROWS:
		var y := float(r[0])
		for deg: float in HEAD_COLS:
			var a := deg_to_rad(deg)
			var rx := float(r[1])
			var rz := float(r[2])
			var x := sin(a) * rx
			var h := Vector3(sin(a) / rx, 0.0, cos(a) / rz).normalized()
			var d := _face_relief(x, y)
			var w := smoothstep(0.35, 0.75, cos(a))
			pts.append(Vector3(x, y, float(r[3]) + cos(a) * rz) + h * d.x * w)
			shades.append(float(r[4]) * lerpf(1.0, d.y, w))
	var nrm: Array[Vector3] = []
	for ri in nr:
		for ci in nc:
			var tc := pts[ri * nc + (ci + 1) % nc] - pts[ri * nc + (ci + nc - 1) % nc]
			var up := HEAD_APEX if ri == nr - 1 else pts[(ri + 1) * nc + ci]
			var dn := pts[maxi(ri - 1, 0) * nc + ci]
			nrm.append(tc.cross(up - dn).normalized())
	for ri in nr - 1:
		for ci in nc:
			var c1 := (ci + 1) % nc
			var ids := [ri * nc + ci, ri * nc + c1, (ri + 1) * nc + c1, (ri + 1) * nc + ci]
			b.add_quad_smooth4(ids.map(func(i: int) -> Vector3: return pts[i]),
					ids.map(func(i: int) -> Vector3: return nrm[i]),
					ids.map(func(i: int) -> Color: return col * shades[i]))
	var top := (nr - 1) * nc
	for ci in nc:
		var i0 := top + ci
		var i1 := top + (ci + 1) % nc
		b.add_tri_smooth([pts[i0], pts[i1], HEAD_APEX], [nrm[i0], nrm[i1], Vector3.UP],
				[col * shades[i0], col * shades[i1], col])
	# Ears: flattened ellipsoids against the sides of the head, tilted back.
	for s: float in [-1.0, 1.0]:
		var basis := Basis(Vector3(0.011 * s, 0, 0), Vector3(0, 0.034, -0.008), Vector3(0, 0, 0.02 * s))
		_ellipsoid(b, Vector3(0.149 * s, 1.858, 0.002), basis, 6, col * 0.92)


## Forward offset (x) and shade (y) of the face at lateral `x` and height `y`.
static func _face_relief(x: float, y: float) -> Vector2:
	var ax := absf(x)
	var eye := -0.024 * exp(-pow((ax - 0.047) / 0.024, 2.0) - pow((y - 1.873) / 0.014, 2.0))
	var brow := 0.012 * exp(-pow((y - 1.897) / 0.011, 2.0)) * smoothstep(0.1, 0.06, ax)
	var ridge := 0.0
	for k in NOSE.size() - 1:
		var n0: Array = NOSE[k]
		var n1: Array = NOSE[k + 1]
		if y >= float(n0[0]) and y <= float(n1[0]):
			ridge = lerpf(float(n0[1]), float(n1[1]), inverse_lerp(float(n0[0]), float(n1[0]), y))
	var nose := ridge * exp(-pow(x / 0.015, 2.0))
	var mouth := -0.01 * exp(-pow((y - 1.79) / 0.006, 2.0)) * smoothstep(0.045, 0.025, ax)
	var chin := 0.012 * exp(-pow((y - 1.765) / 0.014, 2.0) - pow(x / 0.035, 2.0))
	var cheek := 0.006 * exp(-pow((ax - 0.08) / 0.025, 2.0) - pow((y - 1.848) / 0.015, 2.0))
	# Shade: the sockets, the mouth line and the shadow under the nose.
	var under_nose := exp(-pow(x / 0.02, 2.0) - pow((y - 1.81) / 0.006, 2.0))
	var shade := (1.0 + eye * 18.0) * (1.0 + mouth * 35.0) * (1.0 - 0.15 * under_nose)
	return Vector2(eye + brow + nose + mouth + chin + cheek, shade)


## A smooth ellipsoid: the unit sphere mapped by `basis` (its columns are the
## half-axes, right-handed), `sides` around and three bands from pole to pole.
static func _ellipsoid(b: WorldMeshBuilder, c: Vector3, basis: Basis, sides: int, col: Color) -> void:
	var nb := basis.inverse().transposed()
	var lats := [-PI * 0.5, -PI / 6.0, PI / 6.0, PI * 0.5]
	for k in lats.size() - 1:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var us := [_sph(a0, lats[k]), _sph(a1, lats[k]), _sph(a1, lats[k + 1]), _sph(a0, lats[k + 1])]
			b.add_quad_smooth4(us.map(func(u: Vector3) -> Vector3: return c + basis * u),
					us.map(func(u: Vector3) -> Vector3: return (nb * u).normalized()), [col, col, col, col])


static func _sph(a: float, lat: float) -> Vector3:
	return Vector3(sin(a) * cos(lat), sin(lat), cos(a) * cos(lat))


static func _ring_pt(r: Array, a: float) -> Vector3:
	return Vector3(sin(a) * float(r[1]), float(r[0]), float(r[3]) + cos(a) * float(r[2]))


## Smooth normal at angle `a` of ring `cur`, from the profile slope between
## its neighbours `prev` and `next`.
static func _ring_n(prev: Array, cur: Array, next: Array, a: float) -> Vector3:
	var h := Vector3(sin(a) / float(cur[1]), 0.0, cos(a) / float(cur[2])).normalized()
	var dr := (_ring_pt(next, a) - _ring_pt(prev, a))
	var dy := dr.y
	var out := Vector3(dr.x, 0.0, dr.z).dot(h)
	var nm := h * dy - Vector3.UP * out
	return nm.normalized() if nm.length() > 0.0001 else h


## An upright disc (a wheel) facing +-X: `sides`-gon of `radius`, `width` thick.
static func _prism_x(b: WorldMeshBuilder, center: Vector3, radius: float, width: float, sides: int, col: Color) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(0, sin(a0), cos(a0)) * radius
		var p1 := Vector3(0, sin(a1), cos(a1)) * radius
		var h := Vector3(width * 0.5, 0, 0)
		var n := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		b.add_quad(center + p1 - h, center + p0 - h, center + p0 + h, center + p1 + h, n, col, col)
		b.add_tri(center + h, center + p0 + h, center + p1 + h, col)
		b.add_tri(center - h, center + p1 - h, center + p0 - h, col)


## One rectangular face centred on `c`, spanning +-`r` (right) and +-`u`
## (up) as seen from the front; the outward normal is r x u.
static func _face(b: WorldMeshBuilder, c: Vector3, r: Vector3, u: Vector3, col: Color) -> void:
	b.add_quad(c - r - u, c + r - u, c + r + u, c - r + u, r.cross(u).normalized(), col, col)


static func _box_c(b: WorldMeshBuilder, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	b.add_box(center - h, center + h, col, col, col, true)


static func _build(kind: StringName) -> Mesh:
	var white := Color(1, 1, 1)
	var iron := WorldMeshBuilder.new()
	var glass := WorldMeshBuilder.new()
	var wood := WorldMeshBuilder.new()
	var stone := WorldMeshBuilder.new()
	var ashlar := WorldMeshBuilder.new()
	var paint := WorldMeshBuilder.new()
	var bronze := WorldMeshBuilder.new()
	var dressed := WorldMeshBuilder.new()
	match kind:
		&"lamp_post":
			_prism(stone, Vector3.ZERO, 0.28, 0.45, 8, Color(0.5, 0.5, 0.5))
			_prism(iron, Vector3(0, 0.45, 0), 0.07, 3.6, 8, white, false)
			_prism(iron, Vector3(0, 0.45, 0), 0.12, 0.35, 8, white)
			# Arm toward -Z, lantern hanging from it.
			_box_c(iron, Vector3(0, 4.0, -0.4), Vector3(0.06, 0.06, 0.8), white)
			_box_c(iron, Vector3(0, 3.7, -0.2), Vector3(0.04, 0.5, 0.04), white)
			_box_c(iron, Vector3(0, 4.12, -0.75), Vector3(0.36, 0.08, 0.36), white)
			_box_c(iron, Vector3(0, 3.5, -0.75), Vector3(0.3, 0.06, 0.3), white)
			_box_c(glass, Vector3(0, 3.8, -0.75), Vector3(0.26, 0.56, 0.26), white)
			iron.add_pyramid(Vector3(0, 4.16, -0.75), 0.2, 0.25, white)
			for sx: float in [-0.14, 0.14]:
				for sz: float in [-0.14, 0.14]:
					_box_c(iron, Vector3(sx, 3.8, -0.75 + sz), Vector3(0.03, 0.6, 0.03), white)
		&"wall_lantern":
			_box_c(iron, Vector3(0, 0.3, -0.22), Vector3(0.05, 0.05, 0.44), white)
			_box_c(iron, Vector3(0, 0.0, -0.4), Vector3(0.12, 0.5, 0.05), white)
			_box_c(iron, Vector3(0, 0.3, 0), Vector3(0.28, 0.06, 0.28), white)
			_box_c(iron, Vector3(0, -0.28, 0), Vector3(0.24, 0.05, 0.24), white)
			_box_c(glass, Vector3(0, 0.0, 0), Vector3(0.2, 0.5, 0.2), white)
			iron.add_pyramid(Vector3(0, 0.33, 0), 0.16, 0.18, white)
		&"window_bars":
			# Unit square in the XY plane, bars slightly proud of the wall.
			for i in 5:
				var x := -0.4 + 0.2 * float(i)
				_box_c(iron, Vector3(x, 0, 0), Vector3(0.035, 1.0, 0.035), white)
			for y: float in [-0.45, 0.0, 0.45]:
				_box_c(iron, Vector3(0, y, 0), Vector3(1.0, 0.035, 0.035), white)
		&"chimney_cap":
			for sx: float in [-0.22, 0.22]:
				for sz: float in [-0.22, 0.22]:
					_box_c(iron, Vector3(sx, 0.15, sz), Vector3(0.04, 0.3, 0.04), white)
			_box_c(iron, Vector3(0, 0.32, 0), Vector3(0.62, 0.05, 0.62), white)
			iron.add_pyramid(Vector3(0, 0.34, 0), 0.31, 0.22, white)
		&"weathervane":
			_prism(iron, Vector3.ZERO, 0.04, 2.0, 6, white)
			_box_c(iron, Vector3(0, 1.45, 0), Vector3(0.9, 0.03, 0.03), white)
			_box_c(iron, Vector3(0, 1.45, 0), Vector3(0.03, 0.03, 0.9), white)
			_box_c(iron, Vector3(0, 1.8, 0), Vector3(1.1, 0.04, 0.04), white)
			_box_c(iron, Vector3(0.45, 1.8, 0), Vector3(0.25, 0.2, 0.02), white)
			_box_c(iron, Vector3(-0.1, 1.95, 0), Vector3(0.35, 0.28, 0.02), white)
		&"lightning_rod":
			_box_c(iron, Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.3), white)
			_prism(iron, Vector3.ZERO, 0.03, 3.2, 6, white)
			iron.add_pyramid(Vector3(0, 3.2, 0), 0.05, 0.25, white)
		&"bollard":
			_prism(iron, Vector3.ZERO, 0.18, 0.7, 8, white)
			_prism(iron, Vector3(0, 0.7, 0), 0.24, 0.12, 8, white)
		&"crate":
			_box_c(wood, Vector3.ZERO, Vector3(0.8, 0.8, 0.8), Color(0.8, 0.75, 0.7))
			for y: float in [-0.3, 0.3]:
				_box_c(iron, Vector3(0, y, 0), Vector3(0.82, 0.07, 0.82), white)
		&"barrel":
			_prism(wood, Vector3(0, -0.475, 0), 0.36, 0.95, 10, Color(0.75, 0.7, 0.65))
			for y: float in [-0.35, 0.0, 0.3]:
				_prism(iron, Vector3(0, y, 0), 0.375, 0.07, 10, white, false)
		&"bucket":
			_prism(iron, Vector3(0, -0.16, 0), 0.19, 0.32, 8, white, false)
			_prism(iron, Vector3(0, -0.16, 0), 0.17, 0.02, 8, Color(0.3, 0.3, 0.3))
			_box_c(iron, Vector3(0, 0.22, 0), Vector3(0.38, 0.02, 0.02), white)
		&"horseshoe":
			_box_c(iron, Vector3(0, 0, 0.055), Vector3(0.14, 0.03, 0.03), white)
			_box_c(iron, Vector3(-0.055, 0, -0.01), Vector3(0.03, 0.03, 0.12), white)
			_box_c(iron, Vector3(0.055, 0, -0.01), Vector3(0.03, 0.03, 0.12), white)
		&"scrap":
			_box_c(iron, Vector3(0, 0, 0), Vector3(0.55, 0.06, 0.3), white)
			_box_c(iron, Vector3(0.1, 0.04, 0.05), Vector3(0.3, 0.05, 0.12), Color(0.7, 0.6, 0.55))
		&"cart":
			_box_c(wood, Vector3(0, 0.05, 0), Vector3(2.0, 0.12, 1.2), Color(0.7, 0.65, 0.6))
			_box_c(wood, Vector3(0, 0.3, 0.58), Vector3(2.0, 0.45, 0.06), Color(0.7, 0.65, 0.6))
			_box_c(wood, Vector3(0, 0.3, -0.58), Vector3(2.0, 0.45, 0.06), Color(0.7, 0.65, 0.6))
			_box_c(wood, Vector3(1.4, 0.05, 0.4), Vector3(1.0, 0.06, 0.06), Color(0.7, 0.65, 0.6))
			_box_c(wood, Vector3(1.4, 0.05, -0.4), Vector3(1.0, 0.06, 0.06), Color(0.7, 0.65, 0.6))
			for sz: float in [-0.66, 0.66]:
				var wb := WorldMeshBuilder.new()
				_prism(wb, Vector3.ZERO, 0.42, 0.08, 10, white)
				# Rotate the disc to stand upright (axis along Z).
				var rot := Basis(Vector3.RIGHT, PI * 0.5)
				for vi in wb.verts.size():
					wb.verts[vi] = rot * wb.verts[vi] + Vector3(0, -0.03, sz - 0.04)
					wb.normals[vi] = rot * wb.normals[vi]
				iron.append_builder(wb)
		&"stall":
			_box_c(wood, Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 1.1), Color(0.7, 0.65, 0.6))
			for sx: float in [-1.15, 1.15]:
				_box_c(wood, Vector3(sx, 1.25, 0.5), Vector3(0.08, 2.5, 0.08), Color(0.6, 0.55, 0.5))
			_box_c(wood, Vector3(0, 2.5, 0.2), Vector3(2.6, 0.06, 1.6), Color(0.45, 0.3, 0.25))
		&"well":
			_prism(stone, Vector3.ZERO, 1.1, 0.9, 10, Color(0.6, 0.6, 0.6))
			for sx: float in [-0.9, 0.9]:
				_box_c(wood, Vector3(sx, 1.4, 0), Vector3(0.12, 2.0, 0.12), white)
			_box_c(iron, Vector3(0, 2.2, 0), Vector3(1.9, 0.1, 0.1), white)
			_box_c(iron, Vector3(0, 1.6, 0), Vector3(0.1, 1.1, 0.1), white)
		&"balcony":
			# A shallow stone ledge with an iron railing (also a Push/Pull anchor).
			# Dark, heavy wrought iron so the rail reads against pale stone at
			# street distance: thick corner posts and top rail, close balusters.
			var ironc := Color(0.3, 0.28, 0.27)
			_box_c(stone, Vector3(0, -0.08, 0.35), Vector3(1.8, 0.14, 0.95), Color(0.55, 0.53, 0.5))
			for sx: float in [-0.86, 0.86]:
				_box_c(iron, Vector3(sx, 0.47, 0.76), Vector3(0.09, 0.94, 0.09), ironc)
				_box_c(iron, Vector3(sx, 0.47, 0.35), Vector3(0.06, 0.94, 0.06), ironc)
				_box_c(iron, Vector3(sx, 0.92, 0.35), Vector3(0.06, 0.07, 0.82), ironc)
			_box_c(iron, Vector3(0, 0.92, 0.76), Vector3(1.8, 0.09, 0.09), ironc)
			_box_c(iron, Vector3(0, 0.12, 0.76), Vector3(1.8, 0.06, 0.06), ironc)
			for k in 11:
				var sx := -0.72 + 0.144 * float(k)
				_box_c(iron, Vector3(sx, 0.5, 0.76), Vector3(0.035, 0.78, 0.035), ironc)
			for sx: float in [-0.8, 0.8]:
				_box_c(stone, Vector3(sx, -0.16, -0.02), Vector3(0.16, 0.32, 0.72), Color(0.5, 0.48, 0.45))
		&"hedge":
			# A trimmed, half-dead garden hedge segment (Ashmount soot, not lush).
			_box_c(stone, Vector3.ZERO, Vector3(1.8, 0.7, 0.5), Color(0.28, 0.3, 0.2))
			_box_c(stone, Vector3(0, 0.42, 0), Vector3(1.7, 0.14, 0.42), Color(0.32, 0.34, 0.22))
		&"carriage":
			# A closed noble coach, long axis along z: body, roof, four
			# iron-rimmed wheels, driver's bench and shafts.
			var body := Color(0.16, 0.12, 0.1)
			_box_c(wood, Vector3(0, 1.45, 0), Vector3(1.6, 1.5, 2.4), body)
			_box_c(wood, Vector3(0, 2.26, 0), Vector3(1.75, 0.12, 2.6), body * 0.8)
			_box_c(wood, Vector3(0, 1.0, 1.55), Vector3(1.4, 0.2, 0.7), body)
			_box_c(iron, Vector3(0, 0.75, 0), Vector3(0.12, 0.12, 3.2), white)
			for wz: float in [-1.0, 1.1]:
				for wx: float in [-0.88, 0.88]:
					_prism_x(iron, Vector3(wx, 0.62, wz), 0.62, 0.08, 12, white)
			for sx: float in [-0.5, 0.5]:
				_box_c(wood, Vector3(sx, 0.7, 2.6), Vector3(0.07, 0.07, 1.8), body * 1.4)
			_box_c(glass, Vector3(0.81, 1.6, 0), Vector3(0.02, 0.5, 0.7), white)
			_box_c(glass, Vector3(-0.81, 1.6, 0), Vector3(0.02, 0.5, 0.7), white)
		&"topiary":
			# A clipped, soot-dulled box topiary: a squat stack in a stone collar.
			_prism(stone, Vector3.ZERO, 0.32, 0.18, 8, Color(0.45, 0.43, 0.4))
			_prism(stone, Vector3(0, 0.18, 0), 0.42, 0.55, 8, Color(0.25, 0.28, 0.18))
			_prism(stone, Vector3(0, 0.73, 0), 0.3, 0.4, 8, Color(0.28, 0.31, 0.2))
		&"statue", &"statue_bronze":
			# A robed figure raising a standard, faces +Z. Lathed with smooth
			# normals (robe flaring to a bevelled hem, belted waist, sloping
			# shoulders, neck and a rounded head) and tapered eight-sided arms
			# bent at the elbow, so the silhouette reads as cast, not boxed.
			# `statue` is cast iron (Keep Venture's fountain, a Push/Pull
			# anchor); `statue_bronze` weathered verdigris bronze (the avenue
			# statues), dark enough not to glow against sooty streets.
			var fig := iron if kind == &"statue" else bronze
			var ic := Color(0.85, 0.85, 0.85) if kind == &"statue" else Color(1, 1, 1)
			# Cast base plate with a chamfered edge.
			_prism(fig, Vector3.ZERO, 0.54, 0.13, 8, ic * 0.7, false)
			_lathe(fig, [[0.13, 0.54, 0.54, 0.0, 0.75], [0.19, 0.49, 0.49, 0.0, 0.8]], 8, ic)
			# Body: [y, rx, rz, z offset, shade].
			_lathe(fig, [[0.19, 0.46, 0.4, 0.0, 0.62], [0.28, 0.45, 0.38, 0.0, 0.7], [0.6, 0.41, 0.34, 0.0, 0.8],
					[0.95, 0.36, 0.29, 0.0, 0.88], [1.12, 0.31, 0.24, 0.0, 0.85], [1.18, 0.32, 0.25, 0.0, 0.92],
					[1.36, 0.35, 0.25, 0.0, 1.0], [1.48, 0.41, 0.24, 0.0, 1.0], [1.55, 0.38, 0.21, 0.0, 0.98],
					[1.61, 0.2, 0.15, 0.0, 0.92], [1.64, 0.085, 0.09, 0.01, 0.85], [1.72, 0.08, 0.085, 0.02, 0.88]],
					12, ic, false)
			# Head: a displaced grid (see `_statue_head`) with eye sockets, a
			# nose, a mouth line, a chin and cheekbones, and ears.
			_statue_head(fig, ic)
			# Hair massed at the back of the skull and the nape.
			_lathe(fig, [[1.76, 0.1, 0.07, -0.05, 0.8], [1.84, 0.142, 0.115, -0.035, 0.9],
					[1.94, 0.14, 0.12, -0.01, 0.95], [2.0, 0.08, 0.075, 0.0, 1.0]], 10, ic * 0.95)
			# A laurel wreath round the temples.
			_lathe(fig, [[1.9, 0.142, 0.153, 0.018, 0.85], [1.925, 0.156, 0.167, 0.018, 1.0],
					[1.95, 0.142, 0.153, 0.014, 0.9]], 12, ic * 1.05, false)
			for i in 10:
				var a := TAU * (float(i) + 0.5) / 10.0
				if cos(a) > 0.8:
					continue  # the wreath parts over the brow
				# Leaves lie along the band, pointing back, in two rows.
				var radial := Vector3(sin(a), 0.0, cos(a))
				var back := Vector3(cos(a), 0.0, -sin(a)) * (1.0 if a < PI else -1.0)
				for row: float in [-1.0, 1.0]:
					var on := Vector3(sin(a) * 0.155, 1.925 + row * 0.012, 0.018 + cos(a) * 0.166)
					var dir := (back + radial * 0.3 + Vector3.UP * row * 0.35).normalized()
					_limb_n(fig, on, on + dir * 0.06, 0.018, 0.004, ic * 1.05, 3)
			# A cloak falling from the shoulders and spreading behind the hem.
			_lathe(fig, [[0.19, 0.47, 0.14, -0.3, 0.6], [0.7, 0.47, 0.15, -0.27, 0.75], [1.2, 0.42, 0.15, -0.2, 0.88],
					[1.52, 0.37, 0.13, -0.1, 0.95]], 10, ic, false)
			# Raised arm holding the standard, and the other at the side.
			_limb_n(fig, Vector3(0.37, 1.47, 0), Vector3(0.5, 1.8, 0.1), 0.095, 0.075, ic, 8)
			_limb_n(fig, Vector3(0.5, 1.8, 0.1), Vector3(0.53, 2.12, 0.14), 0.075, 0.055, ic, 8)
			_limb_n(fig, Vector3(0.53, 2.08, 0.14), Vector3(0.53, 2.24, 0.14), 0.065, 0.045, ic, 8, true)
			_limb_n(fig, Vector3(-0.37, 1.47, 0), Vector3(-0.44, 1.16, 0.05), 0.095, 0.075, ic, 8)
			_limb_n(fig, Vector3(-0.44, 1.16, 0.05), Vector3(-0.43, 0.9, 0.12), 0.075, 0.055, ic * 0.95, 8)
			_limb_n(fig, Vector3(-0.43, 0.94, 0.12), Vector3(-0.42, 0.8, 0.14), 0.06, 0.04, ic * 0.95, 8, true)
			# The standard: a tapered pole, a spear finial, a crossbar and a
			# swallow-tailed banner.
			_limb_n(fig, Vector3(0.53, 1.0, 0.14), Vector3(0.53, 3.05, 0.14), 0.035, 0.028, ic, 6)
			_limb_n(fig, Vector3(0.53, 3.05, 0.14), Vector3(0.53, 3.24, 0.14), 0.05, 0.004, ic, 6)
			_box_c(fig, Vector3(0.53, 2.99, 0.3), Vector3(0.03, 0.03, 0.36), ic)
			_box_c(fig, Vector3(0.53, 2.75, 0.3), Vector3(0.025, 0.46, 0.3), ic * 0.92)
			for bz: float in [0.2, 0.4]:
				_box_c(fig, Vector3(0.53, 2.46, bz), Vector3(0.025, 0.12, 0.1), ic * 0.88)
		&"ash_planter":
			# A stone urn holding bare, ash-dead twigs — no living greenery this
			# close to the Ashmounts.
			_prism(stone, Vector3.ZERO, 0.42, 0.55, 8, Color(0.5, 0.48, 0.45))
			_prism(stone, Vector3(0, 0.55, 0), 0.5, 0.08, 8, Color(0.45, 0.43, 0.4))
			for i in 5:
				var a := TAU * float(i) / 5.0
				var lean := Vector3(sin(a) * 0.18, 0.7 + float(i % 3) * 0.15, cos(a) * 0.18)
				_box_c(wood, lean * 0.5 + Vector3(0, 0.6, 0), Vector3(0.04, lean.y, 0.04), Color(0.28, 0.24, 0.2))
		&"street_tree":
			# A bare, ash-dead street tree: a stout trunk that forks into a
			# vase of limbs, each splitting into twigs, so the crown reads as a
			# mass (not a few sticks) from across the avenue.
			var bark := Color(0.2, 0.18, 0.16)
			_limb(wood, Vector3(0, 0.0, 0), Vector3(0, 2.6, 0), 0.24, 0.16, bark)
			for i in 8:
				var a := TAU * float(i) / 8.0 + 0.3
				var base := Vector3(0, 2.1 + float(i % 3) * 0.25, 0)
				var len := 1.9 + float(i % 3) * 0.4
				var dir := Vector3(sin(a), 0.75 + float(i % 2) * 0.35, cos(a)).normalized()
				var tip := base + dir * len
				_limb(wood, base, tip, 0.13, 0.06, bark)
				for j in 4:
					var b2 := a + (float(j) - 1.5) * 0.6
					var mid := base.lerp(tip, 0.45 + 0.15 * float(j))
					var tw := Vector3(sin(b2), 0.9, cos(b2)).normalized() * (0.9 + 0.2 * float(j % 2))
					_limb(wood, mid, mid + tw, 0.055, 0.02, bark)
		&"modillion":
			# A cornice bracket under the corona soffit (local: x along the
			# facade, +z out of the wall, y = 0 at the soffit): a deep top
			# block and a shorter drop, pale dressed stone. Only the eight
			# faces that can be seen (16 triangles, was 24): the top sits on
			# the soffit, the backs against the bed moulding and the frieze,
			# and the top block's sides start where the bed moulding (0.38 m
			# out) stops hiding them.
			var pc := Color(0.9, 0.87, 0.8)
			var pd := pc * 0.9
			# Top block: x +-0.11, y -0.16..0, z 0.38..1.0.
			_face(ashlar, Vector3(0, -0.08, 1.0), Vector3.RIGHT * 0.11, Vector3.UP * 0.08, pc)
			_face(ashlar, Vector3(0, -0.16, 0.74), Vector3.RIGHT * 0.11, Vector3.BACK * 0.26, pc * 0.8)
			_face(ashlar, Vector3(0.11, -0.08, 0.69), Vector3.FORWARD * 0.31, Vector3.UP * 0.08, pc)
			_face(ashlar, Vector3(-0.11, -0.08, 0.69), Vector3.BACK * 0.31, Vector3.UP * 0.08, pc)
			# Drop: x +-0.09, y -0.33..-0.15, z 0.12..0.48.
			_face(ashlar, Vector3(0, -0.24, 0.48), Vector3.RIGHT * 0.09, Vector3.UP * 0.09, pd)
			_face(ashlar, Vector3(0, -0.33, 0.3), Vector3.RIGHT * 0.09, Vector3.BACK * 0.18, pd * 0.8)
			_face(ashlar, Vector3(0.09, -0.24, 0.3), Vector3.FORWARD * 0.18, Vector3.UP * 0.09, pd)
			_face(ashlar, Vector3(-0.09, -0.24, 0.3), Vector3.BACK * 0.18, Vector3.UP * 0.09, pd)
		&"plinth":
			# Dressed-stone pedestal for a district statue (big 0.6 m courses,
			# not the facade's brick-sized ones): a chamfered base, a step
			# with a sloped wash, the die, a coved bed moulding and a cap slab
			# (top at 1.7 m, where the figure stands).
			var sc := Color(0.82, 0.79, 0.73)
			_box_c(dressed, Vector3(0, 0.13, 0), Vector3(1.7, 0.26, 1.7), sc * 0.78)
			dressed.add_frustum(Vector3(0, 0.26, 0), 0.85, 0.75, 0.08, sc * 0.78, sc * 0.82)
			_box_c(dressed, Vector3(0, 0.39, 0), Vector3(1.5, 0.1, 1.5), sc * 0.85)
			dressed.add_frustum(Vector3(0, 0.44, 0), 0.75, 0.6, 0.06, sc * 0.85, sc * 0.9)
			_box_c(dressed, Vector3(0, 1.0, 0), Vector3(1.2, 1.0, 1.2), sc)
			dressed.add_frustum(Vector3(0, 1.5, 0), 0.6, 0.7, 0.06, sc * 0.8, sc * 0.9)
			_box_c(dressed, Vector3(0, 1.6, 0), Vector3(1.4, 0.08, 1.4), sc * 0.95)
			dressed.add_frustum(Vector3(0, 1.64, 0), 0.7, 0.78, 0.03, sc * 0.9, sc * 0.92)
			_box_c(dressed, Vector3(0, 1.685, 0), Vector3(1.56, 0.03, 1.56), sc * 0.92)
			# A bronze dedication plaque on the street face.
			_box_c(bronze, Vector3(0, 1.0, 0.613), Vector3(0.6, 0.4, 0.026), Color(0.9, 0.85, 0.75))
		&"shop_sign_board", &"shop_sign_medallion", &"shop_sign_coin":
			# A hanging trade sign on a wrought-iron bracket (local: x along
			# the facade, +z out of the wall, y = 0 at the bracket arm), the
			# board edge-on to the facade so it reads down the street.
			var ironc := Color(0.32, 0.3, 0.28)
			_box_c(iron, Vector3(0, -0.12, 0.03), Vector3(0.12, 0.42, 0.05), ironc)
			_box_c(iron, Vector3(0, 0.0, 0.56), Vector3(0.05, 0.05, 1.08), ironc)
			_limb(iron, Vector3(0, -0.3, 0.05), Vector3(0, -0.02, 0.62), 0.022, 0.018, ironc)
			_box_c(iron, Vector3(0, 0.04, 1.08), Vector3(0.07, 0.07, 0.07), ironc)
			for z: float in [0.36, 0.92]:
				_box_c(iron, Vector3(0, -0.07, z), Vector3(0.02, 0.14, 0.02), ironc)
			var gilt := Color(0.86, 0.66, 0.26)
			match kind:
				&"shop_sign_board":
					# Oxblood board in a dark frame with a gilded panel.
					_box_c(wood, Vector3(0, -0.45, 0.64), Vector3(0.06, 0.62, 0.78), Color(0.3, 0.24, 0.2))
					_box_c(paint, Vector3(0, -0.45, 0.64), Vector3(0.075, 0.5, 0.66), Color(0.42, 0.1, 0.08))
					_box_c(paint, Vector3(0, -0.45, 0.64), Vector3(0.085, 0.22, 0.4), gilt)
				&"shop_sign_medallion":
					# Bottle-green roundel with a gilt boss.
					_prism_x(wood, Vector3(0, -0.45, 0.64), 0.34, 0.06, 12, Color(0.3, 0.24, 0.2))
					_prism_x(paint, Vector3(0, -0.45, 0.64), 0.29, 0.075, 12, Color(0.1, 0.24, 0.16))
					_prism_x(paint, Vector3(0, -0.45, 0.64), 0.13, 0.085, 10, gilt)
				_:
					# A moneychanger's gilt coin, the house mark on a dark ring.
					_prism_x(paint, Vector3(0, -0.47, 0.64), 0.33, 0.07, 16, gilt)
					_prism_x(paint, Vector3(0, -0.47, 0.64), 0.2, 0.08, 12, Color(0.2, 0.16, 0.12))
					_prism_x(paint, Vector3(0, -0.47, 0.64), 0.09, 0.09, 8, gilt * 1.1)
	return _commit({M.IRON: iron, M.LANTERN_GLASS: glass, M.WOOD: wood, M.STONE: stone,
			M.ASHLAR: ashlar, M.BANNER: paint, M.BRONZE: bronze, M.DRESSED_STONE: dressed})
