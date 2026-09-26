class_name MeleeHitbox
extends Area3D
## Reusable melee weapon hitbox (spear, staff, axe...). The owning enemy calls
## [method begin_swing] on the attack's active frame and [method end_swing]
## when it ends, so the shape only deals damage during that window and never
## hits the same body twice per swing.

signal hit_landed(target: Node, amount: float)

@export var damage: float = 20.0
@export var damage_kind: StringName = &"blade"
## Extra velocity (m/s) added to the victim along the hit direction.
@export var knockback: float = 0.0
## Bodies in this group are never hit (own faction).
@export var friendly_group: StringName = &"enemy"

## The attacking actor; set by the owner in _ready(). Excluded from hits and
## passed as `source` to Health.take_damage.
var attacker: Node

var _hit_this_swing: Array[Node] = []


func _ready() -> void:
	# Deferred: enemies can be spawned from inside a physics callback (a
	# trigger completing an objective), where these setters are blocked.
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	body_entered.connect(_on_body_entered)


func begin_swing() -> void:
	_hit_this_swing.clear()
	monitoring = true


func end_swing() -> void:
	monitoring = false


func _on_body_entered(body: Node) -> void:
	if body == attacker or body in _hit_this_swing:
		return
	if friendly_group != &"" and body.is_in_group(friendly_group):
		return
	var health := Health.find_on(body)
	if health == null:
		return
	_hit_this_swing.append(body)
	health.take_damage(damage, attacker, damage_kind)
	hit_landed.emit(body, damage)
	if knockback > 0.0 and body is CharacterBody3D:
		var dir := (body as Node3D).global_position - global_position
		dir.y = 0.3
		if dir.length() > 0.01:
			dir = dir.normalized()
		else:
			dir = Vector3.FORWARD
		(body as CharacterBody3D).velocity += dir * knockback
