class_name SteelLines
extends Node3D
## Draws every steel/iron line of one Allomancer with a single
## MultiMeshInstance3D: camera-facing additive blue ribbons from the chest to
## each metal. Brightness scales with metal mass and fades with distance; the
## current target is highlighted, and brighter while it is being Pushed/Pulled.
##
## The per-instance data is written straight into a preallocated float buffer
## (one RenderingServer upload per frame), so it stays cheap with 500+ lines.

const LINE_SHADER := preload("res://src/allomancy/steel_lines.gdshader")
## Floats per instance: 12 (3x4 transform) + 4 (custom data).
const STRIDE := 16

## The allomancer whose lines are drawn.
var allomancer: Allomancer
## Line to highlight (the crosshair/locked target).
var highlight: Metallic
## Optional node whose global position is the line origin (e.g. a chest
## marker on an interpolated visual). Falls back to allomancer.line_origin().
var origin_node: Node3D

## Maximum number of lines drawn.
@export var capacity := 1024
## Ribbon width (m) for a coin-sized metal.
@export var base_width := 0.012
## Lines start this far (m) from the chest so they don't clump in the view.
@export var start_offset := 0.25

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _buf := PackedFloat32Array()
var _material: ShaderMaterial


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _build_ribbon_mesh()
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3.ONE * -50000.0, Vector3.ONE * 100000.0)
	_buf.resize(capacity * STRIDE)
	_material = ShaderMaterial.new()
	_material.shader = LINE_SHADER
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Lines"
	_mmi.multimesh = _mm
	_mmi.material_override = _material
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mmi)


func _process(_delta: float) -> void:
	if allomancer == null or not is_instance_valid(allomancer):
		_mm.visible_instance_count = 0
		return
	var lines := allomancer.lines_in_range()
	var n := mini(lines.size(), capacity)
	if n == 0:
		_mm.visible_instance_count = 0
		return
	var origin := origin_node.global_position if origin_node != null else allomancer.line_origin()
	var rng := maxf(allomancer.current_range(), 1.0)
	var active := allomancer.is_using_line(Metal.Type.STEEL) or allomancer.is_using_line(Metal.Type.IRON)
	var written := 0
	for i in n:
		var m := lines[i]
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var end := m.global_position
		var to := end - origin
		var d := to.length()
		if d < 0.05:
			continue
		var start := origin + to * (minf(start_offset, d * 0.5) / d)
		var axis := end - start
		var mass_f := log(1.0 + m.metal_mass) / log(10.0)  # 1 coin ~0.3, lamp ~1.8
		var bright := clampf(0.35 + 0.35 * mass_f, 0.25, 1.4) * pow(clampf(1.0 - d / rng, 0.0, 1.0), 0.6)
		var width := base_width * (0.8 + 0.8 * mass_f)
		var hl := 0.0
		if m == highlight:
			hl = 2.0 if active else 1.0
			bright = maxf(bright, 0.8)
			width *= 1.6
		var o := written * STRIDE
		# Row-major 3x4: basis columns X=(1,0,0), Y=axis, Z=(0,0,1), origin=start.
		_buf[o] = 1.0
		_buf[o + 1] = axis.x
		_buf[o + 2] = 0.0
		_buf[o + 3] = start.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = axis.y
		_buf[o + 6] = 0.0
		_buf[o + 7] = start.y
		_buf[o + 8] = 0.0
		_buf[o + 9] = axis.z
		_buf[o + 10] = 1.0
		_buf[o + 11] = start.z
		_buf[o + 12] = width
		_buf[o + 13] = bright
		_buf[o + 14] = hl
		_buf[o + 15] = 0.0
		written += 1
	RenderingServer.multimesh_set_buffer(_mm.get_rid(), _buf)
	_mm.visible_instance_count = written


## Number of lines drawn last frame.
func drawn_count() -> int:
	return _mm.visible_instance_count if _mm != null else 0


static func _build_ribbon_mesh() -> ArrayMesh:
	# Unit ribbon: x in [-0.5, 0.5] (across), y in [0, 1] (along). The shader
	# turns it to face the camera and scales it to the instance's axis.
	var verts := PackedVector3Array([
		Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 1, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
