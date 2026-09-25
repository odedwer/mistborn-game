class_name ThiefRunner
extends Node3D
## Scripted "fleeing thief" for the rooftop pursuit activity. Follows a
## precomputed rooftop path (authored as offsets from the activity's start
## marker) at a fixed speed; no navmesh/physics involved, matching the other
## rooftop-scale scripted actors in the vertical slice (e.g. patrol points).
## `ActivityManager` reads `global_position` each frame to check catch range.

@export var speed := 6.0
var path: PackedVector3Array = PackedVector3Array()

var _seg := 0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(&"activity_thief")
	_mesh = MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.35
	m.height = 1.7
	_mesh.mesh = m
	_mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.1, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.15, 0.1)
	mat.emission_energy_multiplier = 0.4
	_mesh.material_override = mat
	add_child(_mesh)
	if not path.is_empty():
		global_position = path[0]


func _process(delta: float) -> void:
	if path.size() < 2 or _seg >= path.size() - 1:
		return
	var a: Vector3 = path[_seg]
	var b: Vector3 = path[_seg + 1]
	var to_b := b - global_position
	var step := speed * delta
	if to_b.length() <= step:
		global_position = b
		_seg += 1
	else:
		global_position += to_b.normalized() * step
	if to_b.length_squared() > 0.001:
		look_at(global_position + Vector3(to_b.x, 0.0, to_b.z), Vector3.UP)


## True once the thief has reached the end of its path (escaped).
func reached_end() -> bool:
	return _seg >= path.size() - 1
