class_name BattleSurvivor
extends Area3D
## A wounded skaa soldier lying on the battlefield ("The Army in the Caves").
## When the player reaches them they set story flag `flag` (counted by the
## mission's `flag_count` objective), get up and limp for `retreat_point`,
## then vanish once safe. Cheap: one capsule, one trigger, no AI.

signal rescued(survivor: BattleSurvivor)

@export var flag := ""
@export var retreat_point := Vector3.ZERO
@export var limp_speed := 2.6

var is_rescued := false
var _body: MeshInstance3D
var _glow: OmniLight3D


func _ready() -> void:
	add_to_group(&"battle_survivor")
	collision_layer = 0
	collision_mask = 1 << 1  # player
	monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.2
	cs.shape = sph
	cs.position.y = 0.5
	add_child(cs)
	_body = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.7
	_body.mesh = cap
	_body.material_override = InteriorKit.mat(Color(0.5, 0.4, 0.3))
	_body.rotation.x = PI * 0.5  # lying down
	_body.position.y = 0.3
	add_child(_body)
	# A faint warm marker so the wounded read in the dark and the ash.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.75, 0.45)
	_glow.light_energy = 0.45
	_glow.omni_range = 3.0
	_glow.light_volumetric_fog_energy = 0.0
	_glow.position.y = 0.8
	add_child(_glow)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		rescue()


## Marks the survivor rescued (sets `flag`) and sends them off the field.
func rescue() -> void:
	if is_rescued:
		return
	is_rescued = true
	if flag != "":
		GameState.set_dialogue_flag(StringName(flag), true)
	Events.hint_requested.emit("On your feet. Go — toward the ridge!", 2.0)
	_body.rotation.x = 0.0
	_body.position.y = 0.85
	_glow.visible = false
	rescued.emit(self)


func _physics_process(delta: float) -> void:
	if not is_rescued:
		return
	var to := retreat_point - position
	to.y = 0.0
	if to.length() < 1.0:
		queue_free()
		return
	position += to.normalized() * limp_speed * delta
	rotation.y = atan2(to.x, to.z)
