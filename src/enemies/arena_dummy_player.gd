extends CharacterBody3D
## Stand-in "player" for src/enemies test scenes: a body in group "player"
## with a Health component that just walks in a circle, so enemy AI (vision,
## hearing, combat) has something to react to without a real player present.

@export var radius: float = 14.0
@export var angular_speed: float = 0.25
@export var move_speed: float = 3.0

var _angle: float = 0.0
var _center: Vector3


func _ready() -> void:
	add_to_group(&"player")
	_center = global_position


func get_allomantic_mass() -> float:
	return 70.0


func receive_allomantic_force(force: Vector3, delta: float, _from: Metallic) -> void:
	velocity += (force / 70.0) * delta


func _physics_process(delta: float) -> void:
	_angle += delta * angular_speed
	var goal := _center + Vector3(cos(_angle), 0.0, sin(_angle)) * radius
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	if to_goal.length() > 0.05:
		var dir := to_goal.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	move_and_slide()
