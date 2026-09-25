class_name FallbackCoin
extends RigidBody3D
## Minimal thrown-coin projectile used by enemy allomancers (coinshot) only
## when `res://src/combat/coin.tscn` doesn't exist yet. Carries its own small
## [Metallic] so it can still be Pushed/Pulled. Builds its own shape/mesh at
## runtime so it needs no separate .tscn.

@export var damage: float = 10.0
@export var lifetime: float = 5.0

var thrower: Node
var _age: float = 0.0


func _ready() -> void:
	add_to_group(&"coin")
	if get_node_or_null(^"Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.05
		shape.shape = sphere
		add_child(shape)
		var mesh_inst := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		mesh_inst.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.75, 0.4)
		mesh_inst.material_override = mat
		add_child(mesh_inst)
		var metallic := Metallic.new()
		metallic.name = "Metallic"
		metallic.metal_mass = 1.0
		add_child(metallic)
	contact_monitor = true
	max_contacts_reported = 2
	collision_layer = 1 << 4  # coins
	collision_mask = 1 | (1 << 1) | (1 << 2)
	body_entered.connect(_on_body_entered)


## Launches from `from` with a world-space velocity.
func launch(from: Vector3, velocity_vec: Vector3, source: Node) -> void:
	thrower = source
	global_position = from
	linear_velocity = velocity_vec


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == thrower:
		return
	var health := Health.find_on(body)
	if health:
		health.take_damage(damage, thrower, &"coin")
		queue_free()
