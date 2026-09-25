class_name ActivityBeacon
extends Node3D
## Subtle world marker for a side-activity start point: a thin light pillar,
## visible from a distance, cheap enough to have several in a district
## (unshadowed omni + an additive cylinder, same spirit as `WorldPickup`).

@export var beacon_color := Color(0.85, 0.7, 0.3)
@export var beacon_height := 14.0

var _t := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = beacon_color
	mat.emission_enabled = true
	mat.emission = beacon_color
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = beacon_height
	_mesh.mesh = cyl
	_mesh.material_override = mat
	_mesh.position.y = beacon_height * 0.5
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = beacon_color
	light.omni_range = 10.0
	light.light_energy = 1.1
	light.position.y = 1.5
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 20.0
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	if _mesh != null:
		_mesh.scale.y = 1.0 + sin(_t * 1.5) * 0.03
