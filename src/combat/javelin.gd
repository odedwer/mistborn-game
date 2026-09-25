class_name Javelin
extends RigidBody3D
## Thrown wooden javelin (hazekiller). Builds its own collision shape/mesh at
## runtime so it needs no separate .tscn.

@export var damage: float = 25.0
@export var lifetime: float = 6.0

var thrower: Node
var _age: float = 0.0


func _ready() -> void:
	if get_node_or_null(^"Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(0.06, 0.06, 1.8)
		shape.shape = box
		add_child(shape)
		var mesh_inst := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.03
		cyl.height = 1.8
		mesh_inst.mesh = cyl
		mesh_inst.rotation.x = deg_to_rad(90.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.3, 0.15)
		mesh_inst.material_override = mat
		add_child(mesh_inst)
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 1 << 4  # coins/projectiles layer
	collision_mask = 1 | (1 << 1) | (1 << 2)  # world, player, enemies
	body_entered.connect(_on_body_entered)


## Launches from `from` toward `to` at `speed` m/s.
func launch(from: Vector3, to: Vector3, speed: float, source: Node) -> void:
	thrower = source
	global_position = from
	if (to - from).length() > 0.01:
		look_at(to, Vector3.UP)
	linear_velocity = (to - from).normalized() * speed


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == thrower:
		return
	var health := Health.find_on(body)
	if health:
		health.take_damage(damage, thrower, &"blade")
	queue_free()
