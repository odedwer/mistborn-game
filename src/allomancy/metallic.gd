class_name Metallic
extends Node3D
## Marks its parent physics body as containing metal that can be Pushed/Pulled.
##
## Add as a direct child of a RigidBody3D, StaticBody3D, CharacterBody3D or
## AnimatableBody3D. The node registers itself in MetalRegistry so allomancers
## can query nearby metals quickly without scanning the scene tree.
##
## The line anchor point is this node's global position, so place it where the
## metal actually is (e.g. on a guard's breastplate, the head of a spike).

## Grams-equivalent "metal content" used to scale how strongly the line pulls.
## A coin is ~1, a door hinge ~5, a lamp post ~60, an iron gate ~200.
@export var metal_mass: float = 1.0

## If true, the metal is inside a living body or otherwise "pierced" and can't
## be affected (Hemalurgic spikes, metal inside a person's body).
@export var shielded: bool = false

## If true, the object cannot move (rebar in a wall, anchored lamp post). The
## allomancer receives the full reaction force. RigidBodies are never anchored:
## the physics engine resolves their movement.
@export var anchored: bool = false

## Optional: the body that receives forces. Defaults to the parent.
var body: Node3D


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	if body is StaticBody3D:
		anchored = true
	MetalRegistry.register(self)


func _exit_tree() -> void:
	MetalRegistry.unregister(self)


## Effective mass (kg) of the object that moves when this metal is Pushed.
func get_body_mass() -> float:
	if anchored:
		return INF
	if body is RigidBody3D:
		return (body as RigidBody3D).mass
	if body != null and body.has_method("get_allomantic_mass"):
		return body.get_allomantic_mass()
	return INF


## Apply an allomantic force (Newtons, world space) for `delta` seconds.
## Returns true if the object actually accepted the force.
func apply_allomantic_force(force: Vector3, delta: float) -> bool:
	if anchored or shielded or body == null:
		return false
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.sleeping = false
		rb.apply_force(force, global_position - rb.global_position)
		return true
	if body.has_method("receive_allomantic_force"):
		body.receive_allomantic_force(force, delta, self)
		return true
	return false
