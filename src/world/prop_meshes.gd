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


static func _box_c(b: WorldMeshBuilder, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	b.add_box(center - h, center + h, col, col, col, true)


static func _build(kind: StringName) -> Mesh:
	var white := Color(1, 1, 1)
	var iron := WorldMeshBuilder.new()
	var glass := WorldMeshBuilder.new()
	var wood := WorldMeshBuilder.new()
	var stone := WorldMeshBuilder.new()
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
	return _commit({M.IRON: iron, M.LANTERN_GLASS: glass, M.WOOD: wood, M.STONE: stone})
