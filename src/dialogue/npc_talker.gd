class_name NPCTalker
extends CharacterBody3D
## Simple talkable NPC used for hub/social scenes (the crew at Clubs' shop,
## nobles at Keep Venture's ball). Not an enemy: no AI, health or combat.
##
## Visuals are a `CharacterModel` (see docs/CHARACTERS.md): `model_id` names a
## scene in res://assets/models/characters/ (e.g. &"kelsier", &"noble_woman_2");
## left empty, it is guessed from the first word of `display_name` ("Ham" ->
## ham.tscn). Unknown ids fall back to the old colour-tinted capsule
## (`body_color`). `variant_seed` >= 0 re-rolls garments/dyes/scale on base
## models (noble_man, skaa_woman, ...) so extras don't look cloned.
##
## Animation: idle breathing, `walk` while wandering (`wander_radius` > 0 makes
## the NPC idle-wander around its spawn point; 0 keeps it still), and the
## one-shot `talk` gesture when interacted with (plus now and then while idle
## with `idle_chatter`). The model turns to face the player on `interact()`.
##
## `interact()` (called by `Player.interact()`) starts `dialogue_id` via
## `DialogueSystem`.

const MODEL_DIR := "res://assets/models/characters/"
const TURN_SPEED := 6.0

@export var display_name := ""
@export var dialogue_id := ""
## Tint of the capsule fallback when no model resolves.
@export var body_color := Color(0.6, 0.6, 0.6)
## Character scene id under res://assets/models/characters/ ("" = guess from display_name).
@export var model_id: StringName = &""
## >= 0: CharacterModel.randomize_variant(variant_seed) (crowd variety on base models).
@export var variant_seed := -1
## Initial facing of the model (degrees around +Y; 0 = +Z).
@export var facing_deg := 0.0
@export var wander_radius := 0.0
@export var wander_speed := 1.0
## Plays the talk gesture every so often while standing (chatting crew/nobles).
@export var idle_chatter := false

var model: CharacterModel
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _yaw := 0.0
var _yaw_goal := 0.0
var _chatter_t := 0.0
var _hold := 0.0


func _ready() -> void:
	add_to_group(&"npc_talker")
	collision_layer = 1  # world layer: hit by the player's interact raycast.
	collision_mask = 1
	_home = global_position
	_target = _home
	_yaw = deg_to_rad(facing_deg)
	_yaw_goal = _yaw
	_chatter_t = randf_range(3.0, 9.0)
	_build_visual()


## The character scene id this NPC shows (validated), or &"" for the capsule.
static func resolve_model_id(explicit: StringName, p_display_name: String) -> StringName:
	if explicit != &"":
		return explicit if ResourceLoader.exists(MODEL_DIR + String(explicit) + ".tscn") else &""
	var words := p_display_name.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return &""
	var guess := words[0]
	return StringName(guess) if ResourceLoader.exists(MODEL_DIR + guess + ".tscn") else &""


func _build_visual() -> void:
	var height := 1.75
	var id := resolve_model_id(model_id, display_name)
	if id != &"":
		var ps := load(MODEL_DIR + String(id) + ".tscn") as PackedScene
		model = ps.instantiate() as CharacterModel if ps != null else null
	if model != null:
		model.name = "Model"
		if variant_seed >= 0:
			model.randomize_variant(variant_seed)
		add_child(model)
		model.rotation.y = _yaw
		height = maxf(model.get_model_height(), 1.0)
		# desynchronise idle breathing between neighbours
		if model.animation_tree != null:
			model.animation_tree.advance(randf() * 3.0)
	else:
		var mesh := MeshInstance3D.new()
		mesh.name = "Model"
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
	cap_shape.height = maxf(height, 0.8)
	shape.shape = cap_shape
	shape.position.y = cap_shape.height * 0.5
	add_child(shape)

	if display_name != "":
		var label := Label3D.new()
		label.name = "NameLabel"
		label.text = display_name
		label.position.y = height + 0.3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.outline_size = 8
		label.modulate = Color(0.95, 0.95, 0.9, 0.9)
		add_child(label)


func _physics_process(delta: float) -> void:
	_hold = maxf(_hold - delta, 0.0)
	if wander_radius > 0.0 and _hold <= 0.0:
		_wander(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		if wander_radius > 0.0:
			move_and_slide()
	if model == null:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.2 and _hold <= 0.0:
		_yaw_goal = atan2(velocity.x, velocity.z)  # CharacterModel roots face +Z
	_yaw = lerp_angle(_yaw, _yaw_goal, clampf(TURN_SPEED * delta, 0.0, 1.0))
	model.rotation.y = _yaw
	model.set_locomotion(hspeed, true)


func _process(delta: float) -> void:
	if not idle_chatter or model == null:
		return
	_chatter_t -= delta
	if _chatter_t <= 0.0:
		_chatter_t = randf_range(6.0, 14.0)
		if Vector2(velocity.x, velocity.z).length() < 0.2 and not model.is_action_playing():
			model.play_action(&"talk")


func _wander(delta: float) -> void:
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


## Turns to face `node` (anything Node3D) and plays the talk gesture.
func greet(node: Node) -> void:
	if node is Node3D:
		var d := (node as Node3D).global_position - global_position
		if Vector2(d.x, d.z).length() > 0.05:
			_yaw_goal = atan2(d.x, d.z)
	_hold = 4.0  # stop wandering for the conversation
	if model != null:
		model.play_action(&"talk")


## Called by `Player.interact()`.
func interact(player: Node) -> void:
	greet(player)
	if dialogue_id != "":
		DialogueSystem.play(StringName(dialogue_id))
