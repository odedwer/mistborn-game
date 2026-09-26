class_name CrowdMember
extends CharacterBody3D
## A skaa crowd member for "Soothing the Masses" and the "Soothing riots"
## side activity: a wandering skaa `CharacterModel` (skaa_man/skaa_woman with a
## per-member variant; capsule fallback, same as `NPCTalker`)
## that forwards zinc/brass to the scene's `CrowdMoodMeter` instead of
## reacting to it directly, so the mood is shared across the whole crowd
## rather than tracked per-NPC.
##
## Must be in group `"enemy"` to be a valid zinc/brass target at all —
## `Player._update_emotional_target` only scans `"enemy"` and `"crowd_npc"`
## (see `src/player/player.gd`) — so it wears its group like a hostile actor
## even though it never fights back.

@export var wander_radius := 4.0
@export var wander_speed := 1.0
@export var body_color := Color(0.55, 0.5, 0.45)

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _meter: Node = null
var model: CharacterModel


func _ready() -> void:
	add_to_group(&"enemy")
	add_to_group(&"crowd_npc")
	collision_layer = 1 << 2
	collision_mask = 1
	_home = global_position
	_target = _home
	_build_visual()


func _build_visual() -> void:
	var kind := "skaa_woman" if get_instance_id() % 2 == 0 else "skaa_man"
	var ps := load("res://assets/models/characters/%s.tscn" % kind) as PackedScene
	if ps != null:
		model = ps.instantiate() as CharacterModel
	if model != null:
		model.randomize_variant(get_instance_id() & 0x7fffffff)
		add_child(model)
	else:
		_build_capsule()
	var shape := CollisionShape3D.new()
	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.32
	cap_shape.height = 1.7
	shape.shape = cap_shape
	shape.position.y = 0.85
	add_child(shape)


func _build_capsule() -> void:
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.7
	mesh.mesh = cap
	mesh.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.material_override = mat
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if global_position.distance_to(_target) < 0.4:
		velocity.x = 0.0
		velocity.z = 0.0
		_wait -= delta
		if _wait <= 0.0:
			_pick_new_target()
	else:
		var dir := _target - global_position
		dir.y = 0.0
		dir = dir.normalized() * wander_speed
		velocity.x = dir.x
		velocity.z = dir.z
	move_and_slide()
	if model != null:
		var h := Vector2(velocity.x, velocity.z)
		if h.length() > 0.2:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(h.x, h.y), minf(8.0 * delta, 1.0))
		model.set_locomotion(h.length(), true)


func _pick_new_target() -> void:
	var ang := randf() * TAU
	var r := randf() * wander_radius
	_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	_wait = randf_range(2.0, 5.0)


## Never dies for real: `EnemyBase`-shaped combat can still hit it, but the
## crowd has no `Health` node so damage callables just no-op.
func get_allomantic_mass() -> float:
	return 65.0


func receive_allomantic_force(force: Vector3, delta: float, _from: Metallic) -> void:
	velocity += (force / 65.0) * delta


## Forwards zinc (riot) / brass (soothe) to the shared `CrowdMoodMeter`
## instead of an individual soothed/riled state.
func receive_emotional_allomancy(kind: StringName, strength: float) -> void:
	if _meter == null or not is_instance_valid(_meter):
		_meter = get_tree().get_first_node_in_group(&"crowd_mood")
	if _meter != null and _meter.has_method(&"apply"):
		_meter.call(&"apply", kind, strength)
