class_name WorldPickup
extends Area3D
## Collectible spawned at `pickup_spawn` markers (vial, coins, atium,
## duralumin, health). Calls `add_pickup(kind, amount)` on the player body.

## Emitted when the player picks this up (before it frees itself).
signal collected(pickup: WorldPickup)

const AMOUNTS := {&"coins": 10.0, &"vial": 1.0, &"atium": 25.0, &"duralumin": 100.0, &"health": 40.0}
const COLORS := {
	&"coins": Color(0.8, 0.8, 0.85), &"vial": Color(0.55, 0.7, 1.0), &"atium": Color(1.0, 0.95, 0.75),
	&"duralumin": Color(0.8, 0.85, 1.0), &"health": Color(1.0, 0.35, 0.3),
}

@export var pickup_kind: StringName = &"vial":
	set(v):
		pickup_kind = v
		_refresh()
@export var amount := -1.0

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 2
	monitorable = false
	add_to_group(&"pickup")
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	cs.shape = sph
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)
	_mesh = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.07
	m.bottom_radius = 0.09
	m.height = 0.26
	_mesh.mesh = m
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.omni_range = 2.5
	_light.light_energy = 0.45
	_light.position = Vector3(0, 0.7, 0)
	add_child(_light)
	_refresh()
	body_entered.connect(_on_body_entered)


func _refresh() -> void:
	if _mesh == null:
		return
	var c: Color = COLORS.get(pickup_kind, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.9
	mat.metallic = 0.6
	mat.roughness = 0.3
	_mesh.material_override = mat
	_light.light_color = c


func _process(delta: float) -> void:
	_t += delta
	if _mesh != null:
		_mesh.rotation.y = _t * 1.5
		_mesh.position.y = 0.5 + sin(_t * 2.0) * 0.08


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or not body.has_method(&"add_pickup"):
		return
	var amt := amount if amount > 0.0 else float(AMOUNTS.get(pickup_kind, 1.0))
	body.call(&"add_pickup", pickup_kind, amt)
	collected.emit(self)
	queue_free()
