class_name NPCTalker
extends CharacterBody3D
## Simple talkable NPC used for hub/social scenes (the crew at Clubs' shop,
## nobles at Keep Venture's ball). Not an enemy: no AI, health or combat.
##
## Visuals are a colour-tinted capsule with a floating name label — the same
## placeholder look `EnemyBase._make_placeholder_mesh` falls back to when a
## full `CharacterModel` GLB isn't wired up yet (see docs/GAME_DESIGN.md's
## Act I notes on crew/noble variants for the follow-up work). `wander_radius`
## above 0 makes the NPC idle-wander around its spawn point (nobles at the
## ball); 0 keeps it still (the crew, standing at their usual spot).
##
## `interact()` (called by `Player.interact()`) starts `dialogue_id` via
## `DialogueSystem`.

@export var display_name := ""
@export var dialogue_id := ""
@export var body_color := Color(0.6, 0.6, 0.6)
@export var wander_radius := 0.0
@export var wander_speed := 1.0

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0


func _ready() -> void:
	add_to_group(&"npc_talker")
	collision_layer = 1  # world layer: hit by the player's interact raycast.
	collision_mask = 1
	_home = global_position
	_target = _home
	_build_visual()


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.75
	mesh.mesh = cap
	mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.material_override = mat
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.35
	cap_shape.height = 1.75
	shape.shape = cap_shape
	shape.position.y = 0.9
	add_child(shape)

	if display_name != "":
		var label := Label3D.new()
		label.text = display_name
		label.position.y = 2.05
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.outline_size = 8
		label.modulate = Color(0.95, 0.95, 0.9, 0.9)
		add_child(label)


func _physics_process(delta: float) -> void:
	if wander_radius <= 0.0:
		return
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


func _pick_new_target() -> void:
	var ang := randf() * TAU
	var r := randf() * wander_radius
	_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	_wait = randf_range(2.5, 6.0)


## Called by `Player.interact()`.
func interact(_player: Node) -> void:
	if dialogue_id != "":
		DialogueSystem.play(StringName(dialogue_id))
