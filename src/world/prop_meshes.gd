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

static var _meshes: Dictionary = {}
static var _shapes: Dictionary = {}


static func mesh(kind: StringName) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m := _build(kind)
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
		&"statue", &"statue_marble":
			# A figure on a plinth cap: a robe flaring to the ground, a
			# narrower torso under broad shoulders, a head, one arm raising a
			# tall standard and one hanging, so it reads as a person (not a
			# post). Faces +Z. `statue` is cast iron (the courtyard fountain),
			# `statue_marble` smooth pale stone (untextured: the ashlar courses read
			# as brickwork on a figure), which stands out against sooty facades.
			var fig := iron if kind == &"statue" else paint
			var ic := Color(0.85, 0.85, 0.85) if kind == &"statue" else Color(0.74, 0.72, 0.68)
			_prism(stone, Vector3.ZERO, 0.6, 0.2, 8, Color(0.5, 0.48, 0.45))
			_limb(fig, Vector3(0, 0.2, 0), Vector3(0, 0.95, 0), 0.5, 0.36, ic)
			_limb(fig, Vector3(0, 0.95, 0), Vector3(0, 1.55, 0), 0.36, 0.3, ic)
			_box_c(fig, Vector3(0, 1.56, -0.02), Vector3(0.78, 0.18, 0.36), ic)
			_prism(fig, Vector3(0, 1.65, 0), 0.08, 0.1, 6, ic)
			_prism(fig, Vector3(0, 1.74, 0.02), 0.15, 0.28, 8, ic)
			# A cloak falling down the back.
			_limb(fig, Vector3(0, 1.5, -0.2), Vector3(0, 0.25, -0.38), 0.24, 0.4, ic * 0.9)
			# Raised arm holding a standard; the other at the side.
			_limb(fig, Vector3(0.36, 1.52, 0), Vector3(0.5, 2.2, 0.12), 0.09, 0.07, ic)
			_limb(fig, Vector3(0.52, 1.1, 0.14), Vector3(0.52, 3.1, 0.14), 0.035, 0.03, ic)
			_box_c(fig, Vector3(0.52, 2.85, 0.28), Vector3(0.03, 0.42, 0.28), ic)
			_limb(fig, Vector3(-0.36, 1.52, 0), Vector3(-0.44, 0.85, 0.08), 0.09, 0.07, ic)
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
			# block and a shorter scrolled drop, pale dressed stone.
			var pc := Color(0.9, 0.87, 0.8)
			_box_c(ashlar, Vector3(0, -0.08, 0.56), Vector3(0.22, 0.16, 0.88), pc)
			_box_c(ashlar, Vector3(0, -0.24, 0.3), Vector3(0.18, 0.18, 0.36), pc * 0.9)
		&"plinth":
			# Ashlar pedestal for a district statue: base, die and moulded cap
			# (top at 1.7 m, where the `statue` instance stands).
			var sc := Color(0.82, 0.79, 0.73)
			_box_c(ashlar, Vector3(0, 0.15, 0), Vector3(1.7, 0.3, 1.7), sc * 0.8)
			_box_c(ashlar, Vector3(0, 0.36, 0), Vector3(1.5, 0.12, 1.5), sc * 0.9)
			_box_c(ashlar, Vector3(0, 0.96, 0), Vector3(1.2, 1.08, 1.2), sc)
			_box_c(ashlar, Vector3(0, 1.56, 0), Vector3(1.4, 0.1, 1.4), sc * 0.95)
			_box_c(ashlar, Vector3(0, 1.66, 0), Vector3(1.6, 0.08, 1.6), sc * 0.9)
			# A dark bronze dedication plaque on the street face.
			_box_c(iron, Vector3(0, 0.98, 0.615), Vector3(0.6, 0.4, 0.03), Color(0.45, 0.4, 0.32))
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
			M.ASHLAR: ashlar, M.BANNER: paint})
