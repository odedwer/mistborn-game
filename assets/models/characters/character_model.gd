class_name CharacterModel
extends Node3D
## Visual character: the imported GLB (skeleton, skinned mesh, animations) plus
## an AnimationTree built at runtime, mistcloak spring bones, look-at and attachments.
##
## Gameplay code only talks to this API:
##   set_locomotion(speed, grounded, vertical_speed)
##   set_crouching(on)
##   play_action(&"jump" | &"land" | &"throw" | &"melee" | &"attack" | &"hit" | &"die"
##               | &"block" | &"alert" | &"push" | &"pull" | &"drink" | &"talk") -> bool
##   set_aim(world_dir)            (Vector3.ZERO disables)
##   get_attachment(&"hand_r" | &"hand_l" | &"chest" | &"head" | &"lantern" | <bone name>)
##   revive()
##   apply_variant(garments, dyes, scale) / randomize_variant(seed)   (nobles, skaa: crowd variety)

signal action_started(action: StringName)
signal action_finished(action: StringName)

const LOOPING_ANIMATIONS: Array[StringName] = [
	&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk", &"fall"]
const ACTIONS: Array[StringName] = [
	&"jump", &"land", &"throw", &"melee", &"attack", &"hit", &"die", &"block", &"alert",
	&"push", &"pull", &"drink", &"talk"]
## Actions that only drive the spine, arms and head (so they can play while running).
const UPPER_BODY_ACTIONS: Array[StringName] = [&"throw", &"melee", &"push", &"pull", &"drink", &"talk"]
## Optional garment meshes are named G_<garment> in the GLB.
const GARMENT_PREFIX := "G_"
const DYE_PARAMS: Array[StringName] = [&"dye_1", &"dye_2", &"dye_3"]
const UPPER_BODY_BONES: Array[StringName] = [
	&"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand"]
const HUMANOID_BONES: Array[StringName] = [
	&"Root", &"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand",
	&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"LeftToes",
	&"RightUpperLeg", &"RightLowerLeg", &"RightFoot", &"RightToes"]

@export var character_id: StringName = &""
@export_group("Locomotion")
## Ground speeds (m/s) at which the walk / run / sprint cycles match foot contact.
@export var walk_speed := 1.3
@export var run_speed := 4.2
@export var sprint_speed := 7.5
@export var crouch_walk_speed := 1.4
## Landing faster than this (negative, m/s) automatically plays `land`. 0 disables.
@export var auto_land_speed := -6.0
@export_group("Secondary motion")
@export var cloak_physics := true
@export var cloak_stiffness := 0.9
@export var cloak_drag := 0.45
@export var cloak_gravity := 1.2
@export_group("Attachments")
## name -> [bone name, Vector3 position in model space (rest pose)]
@export var sockets: Dictionary = {}
@export var lantern_light := true
@export_group("Variant")
## Optional garments (G_<name> meshes) that are shown; all others are hidden.
@export var garments: PackedStringArray = PackedStringArray()
## sRGB dye per dye slot (1..3) of the model; alpha 0 (or a missing entry) keeps the authored colour.
@export var dye_colors: Array[Color] = []
## Uniform scale of the Model (height variation within a crowd).
@export var body_scale := 1.0
## What randomize_variant() may pick: {"garment_groups": [[name|"", ...], ...] (one pick per
## group), "palettes": [[Color, ...] per dye slot], "scale": Vector2(min, max)}.
@export var variant_pool: Dictionary = {}

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var spring_bones: SpringBoneSimulator3D
var aim_modifier: CharacterAimModifier

var _playback: AnimationNodeStateMachinePlayback
var _full_anim: AnimationNodeAnimation
var _upper_anim: AnimationNodeAnimation
var _crouching := false
var _dead := false
var _grounded := true
var _speed := 0.0
var _current_action: StringName = &""
var _action_left := 0.0
var _attachments: Dictionary = {}
var _state: StringName = &"ground"


func _ready() -> void:
	_find_nodes()
	if animation_player == null or skeleton == null:
		push_error("CharacterModel: model is missing an AnimationPlayer or Skeleton3D")
		return
	_apply_variant_now()
	_build_tree()
	_setup_aim()
	if cloak_physics:
		_setup_cloak()
	if lantern_light and sockets.has("lantern"):
		_setup_lantern()


func _find_nodes() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0]
	var skels := find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skeleton = skels[0]


# --------------------------------------------------------------------- public API
## Drives the locomotion blend. `speed` is horizontal ground speed in m/s.
func set_locomotion(speed: float, grounded: bool, vertical_speed: float = 0.0) -> void:
	if animation_tree == null or _dead:
		return
	_speed = maxf(speed, 0.0)
	if grounded and not _grounded and auto_land_speed < 0.0 and vertical_speed < auto_land_speed:
		play_action(&"land")
	_grounded = grounded
	var target: StringName = &"ground"
	if not grounded:
		target = &"air"
	elif _crouching:
		target = &"crouch"
	_travel(target)
	# ground: idle <-> moving mix, then walk/run/sprint blend space
	var move_amount := clampf(_speed / maxf(walk_speed * 0.6, 0.01), 0.0, 1.0)
	animation_tree.set(&"parameters/loco/ground/mix/blend_amount", move_amount)
	animation_tree.set(&"parameters/loco/ground/move/blend_position", clampf(_speed, walk_speed, sprint_speed))
	var ts := 1.0
	if _speed > sprint_speed:
		ts = minf(_speed / sprint_speed, 1.6)
	elif _speed < walk_speed:
		ts = clampf(_speed / walk_speed, 0.6, 1.0)
	animation_tree.set(&"parameters/loco/ground/scale/scale", ts)
	var c := clampf(_speed / crouch_walk_speed, 0.0, 1.0)
	animation_tree.set(&"parameters/loco/crouch/mix/blend_amount", c)
	animation_tree.set(&"parameters/loco/crouch/scale/scale", clampf(_speed / crouch_walk_speed, 0.6, 1.8))


func set_crouching(on: bool) -> void:
	_crouching = on
	if _grounded and not _dead and animation_tree != null:
		_travel(&"crouch" if on else &"ground")


func is_crouching() -> bool:
	return _crouching


func is_dead() -> bool:
	return _dead


## Plays a one-shot. Returns false for unknown actions. `die` is terminal until revive().
func play_action(action: StringName) -> bool:
	if animation_tree == null or not has_animation(action):
		return false
	if _dead and action != &"die":
		return false
	if action == &"die":
		_dead = true
		animation_tree.set(&"parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		animation_tree.set(&"parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_travel(&"dead")
	elif action in UPPER_BODY_ACTIONS:
		_upper_anim.animation = action
		animation_tree.set(&"parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		_full_anim.animation = action
		animation_tree.set(&"parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if _current_action != &"" and _action_left > 0.0:
		action_finished.emit(_current_action)
	_current_action = action
	_action_left = animation_player.get_animation(action).length
	action_started.emit(action)
	return true


func is_action_playing() -> bool:
	return _action_left > 0.0


## Clears the dead state and returns to idle.
func revive() -> void:
	_dead = false
	_travel(&"ground")


## Look-at: world-space direction (Vector3.ZERO to disable).
func set_aim(dir: Vector3) -> void:
	if aim_modifier == null:
		return
	if dir.length_squared() < 1e-6:
		aim_modifier.set_direction(Vector3.ZERO)
		return
	aim_modifier.set_direction(skeleton.global_basis.inverse() * dir)


func has_animation(anim_name: StringName) -> bool:
	return animation_player != null and animation_player.has_animation(anim_name)


## Returns a Node3D that follows a socket (hand_r, hand_l, chest, head, lantern) or
## any bone by name. Created on demand; null if unknown.
func get_attachment(attach_name: StringName) -> Node3D:
	if _attachments.has(attach_name):
		return _attachments[attach_name]
	if skeleton == null:
		_find_nodes()
		if skeleton == null:
			return null
	var bone_name: String = ""
	var pos := Vector3.ZERO
	var has_pos := false
	if sockets.has(String(attach_name)):
		var s: Array = sockets[String(attach_name)]
		bone_name = s[0]
		pos = s[1]
		has_pos = true
	elif attach_name == &"head":
		bone_name = "Head"
	elif skeleton.find_bone(attach_name) >= 0:
		bone_name = attach_name
	else:
		return null
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Attach_%s" % attach_name
	ba.bone_name = bone_name
	skeleton.add_child(ba)
	var socket := Node3D.new()
	socket.name = String(attach_name)
	ba.add_child(socket)
	if has_pos:
		var rest := skeleton.get_bone_global_rest(bone)
		socket.transform = Transform3D(Basis(), rest.affine_inverse() * pos)
	_attachments[attach_name] = socket
	return socket


## Standing height of the rest pose (metres), from the visible meshes' AABBs.
func get_model_height() -> float:
	var h := 0.0
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var aabb := mi.get_aabb()
		h = maxf(h, aabb.end.y)
	return h * body_scale


# ------------------------------------------------------------------- variants
## Names of the optional garments this model has (without the G_ prefix).
func get_garment_names() -> PackedStringArray:
	var out := PackedStringArray()
	for mi: MeshInstance3D in find_children(GARMENT_PREFIX + "*", "MeshInstance3D", true, false):
		out.append(mi.name.trim_prefix(GARMENT_PREFIX))
	return out


## Shows exactly `p_garments`, dyes the dye slots with `dyes` (sRGB; alpha 0 = authored
## colour) and scales the model. Works before or after the node enters the tree.
func apply_variant(p_garments: PackedStringArray, dyes: Array = [], scale_factor := 1.0) -> void:
	garments = p_garments
	dye_colors.clear()
	for c in dyes:
		dye_colors.append(c)
	body_scale = scale_factor
	if is_inside_tree():
		_apply_variant_now()


## Picks garments, dyes and scale from `variant_pool`, deterministically from `seed_value`.
## Models without a pool keep their look (returns false).
func randomize_variant(seed_value: int) -> bool:
	if variant_pool.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var picked := PackedStringArray()
	for group: Array in variant_pool.get("garment_groups", []):
		if group.is_empty():
			continue
		var g := String(group[rng.randi() % group.size()])
		if g != "" and not picked.has(g):
			picked.append(g)
	var dyes: Array = []
	for pal: Array in variant_pool.get("palettes", []):
		dyes.append(pal[rng.randi() % pal.size()] if not pal.is_empty() else Color(1, 1, 1, 0))
	var sr: Vector2 = variant_pool.get("scale", Vector2.ONE)
	apply_variant(picked, dyes, rng.randf_range(sr.x, sr.y))
	return true


func _apply_variant_now() -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with(GARMENT_PREFIX):
			mi.visible = garments.has(mi.name.trim_prefix(GARMENT_PREFIX))
		if dye_colors.is_empty() and mi.get_instance_shader_parameter(DYE_PARAMS[0]) == null:
			continue  # never dyed: leave the shader defaults (authored colours)
		for i in DYE_PARAMS.size():
			var c := dye_colors[i] if i < dye_colors.size() else Color(1, 1, 1, 0)
			mi.set_instance_shader_parameter(DYE_PARAMS[i], c)
	var model := get_node_or_null(^"Model") as Node3D
	if model != null:
		model.scale = Vector3.ONE * body_scale


# ------------------------------------------------------------------- internals
func _process(delta: float) -> void:
	if _action_left > 0.0:
		_action_left -= delta
		if _action_left <= 0.0:
			var a := _current_action
			_current_action = &""
			action_finished.emit(a)


func _travel(state: StringName) -> void:
	if _playback == null or state == _state:
		return
	_state = state
	_playback.travel(state)


func _anim_node(anim: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim
	return n


func _build_tree() -> void:
	# locomotion: ground (idle <-> [walk|run|sprint]), crouch, air, dead
	var ground := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = walk_speed
	move.max_space = sprint_speed
	move.add_blend_point(_anim_node(&"walk"), walk_speed, -1, &"walk")
	move.add_blend_point(_anim_node(&"run"), run_speed, -1, &"run")
	move.add_blend_point(_anim_node(&"sprint"), sprint_speed, -1, &"sprint")
	move.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	ground.add_node(&"idle", _anim_node(&"idle"), Vector2(0, 0))
	ground.add_node(&"move", move, Vector2(0, 150))
	ground.add_node(&"scale", AnimationNodeTimeScale.new(), Vector2(200, 150))
	ground.add_node(&"mix", AnimationNodeBlend2.new(), Vector2(400, 0))
	ground.connect_node(&"scale", 0, &"move")
	ground.connect_node(&"mix", 0, &"idle")
	ground.connect_node(&"mix", 1, &"scale")
	ground.connect_node(&"output", 0, &"mix")

	var crouch := AnimationNodeBlendTree.new()
	crouch.add_node(&"idle", _anim_node(&"crouch_idle"), Vector2(0, 0))
	crouch.add_node(&"walk", _anim_node(&"crouch_walk"), Vector2(0, 150))
	crouch.add_node(&"scale", AnimationNodeTimeScale.new(), Vector2(200, 150))
	crouch.add_node(&"mix", AnimationNodeBlend2.new(), Vector2(400, 0))
	crouch.connect_node(&"scale", 0, &"walk")
	crouch.connect_node(&"mix", 0, &"idle")
	crouch.connect_node(&"mix", 1, &"scale")
	crouch.connect_node(&"output", 0, &"mix")

	var sm := AnimationNodeStateMachine.new()
	sm.add_node(&"ground", ground, Vector2(0, 0))
	sm.add_node(&"crouch", crouch, Vector2(0, 150))
	sm.add_node(&"air", _anim_node(&"fall"), Vector2(250, 0))
	sm.add_node(&"dead", _anim_node(&"die"), Vector2(250, 150))
	var states: Array[StringName] = [&"ground", &"crouch", &"air", &"dead"]
	for a in states:
		for b in states:
			if a == b or a == &"dead" and b != &"ground":
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.12 if b == &"ground" and a == &"air" else 0.22
			if b == &"dead":
				t.xfade_time = 0.1
			sm.add_transition(a, b, t)
	var start := AnimationNodeStateMachineTransition.new()
	sm.add_transition(&"Start", &"ground", start)

	var root := AnimationNodeBlendTree.new()
	root.add_node(&"loco", sm, Vector2(0, 0))
	_full_anim = _anim_node(&"hit")
	_upper_anim = _anim_node(&"throw")
	root.add_node(&"full_anim", _full_anim, Vector2(0, 200))
	root.add_node(&"upper_anim", _upper_anim, Vector2(250, 200))
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.08
	full.fadeout_time = 0.18
	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.08
	upper.fadeout_time = 0.2
	upper.filter_enabled = true
	var prefix := _bone_track_prefix()
	for b in UPPER_BODY_BONES:
		upper.set_filter_path(NodePath("%s:%s" % [prefix, b]), true)
	root.add_node(&"full", full, Vector2(250, 0))
	root.add_node(&"upper", upper, Vector2(500, 0))
	root.connect_node(&"full", 0, &"loco")
	root.connect_node(&"full", 1, &"full_anim")
	root.connect_node(&"upper", 0, &"full")
	root.connect_node(&"upper", 1, &"upper_anim")
	root.connect_node(&"output", 0, &"upper")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	var model_root := animation_player.get_node(animation_player.root_node)
	model_root.add_child(animation_tree)
	animation_tree.root_node = animation_tree.get_path_to(model_root)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.tree_root = root
	animation_tree.active = true
	_playback = animation_tree.get(&"parameters/loco/playback")
	_playback.start(&"ground")
	_state = &"ground"
	set_locomotion(0.0, true, 0.0)


func _bone_track_prefix() -> String:
	var anim := animation_player.get_animation(&"idle")
	for i in anim.get_track_count():
		var p := String(anim.track_get_path(i))
		var c := p.find(":")
		if c > 0:
			return p.substr(0, c)
	return "Armature/Skeleton3D"


func _setup_aim() -> void:
	aim_modifier = CharacterAimModifier.new()
	aim_modifier.name = "Aim"
	skeleton.add_child(aim_modifier)


func _setup_cloak() -> void:
	var roots: Array[String] = []
	var ends: Array[String] = []
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n.begins_with("Tassel_") and n.ends_with("_0"):
			var stem := n.substr(0, n.length() - 1)
			var last := 0
			while skeleton.find_bone(stem + str(last + 1)) >= 0:
				last += 1
			roots.append(n)
			ends.append(stem + str(last))
	if roots.is_empty():
		return
	spring_bones = SpringBoneSimulator3D.new()
	spring_bones.name = "CloakSprings"
	skeleton.add_child(spring_bones)
	# body colliders so tassels drape around the legs instead of through them
	var cols: Array[Array] = [[&"Hips", 0.11], [&"LeftUpperLeg", 0.085], [&"RightUpperLeg", 0.085],
		[&"LeftLowerLeg", 0.065], [&"RightLowerLeg", 0.065]]
	for c in cols:
		var bi := skeleton.find_bone(c[0])
		if bi < 0:
			continue
		var length := 0.25
		var ch := skeleton.get_bone_children(bi)
		for child in ch:
			if not skeleton.get_bone_name(child).begins_with("Tassel"):
				length = skeleton.get_bone_rest(child).origin.length()
				break
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Col_%s" % c[0]
		cap.bone_name = c[0]
		cap.radius = c[1] * _scale_hint()
		cap.height = length + cap.radius * 2.0
		cap.position_offset = Vector3(0, length * 0.5, 0)
		spring_bones.add_child(cap)
	spring_bones.setting_count = roots.size()
	for k in roots.size():
		spring_bones.set_root_bone_name(k, roots[k])
		spring_bones.set_end_bone_name(k, ends[k])
		spring_bones.set_extend_end_bone(k, true)
		spring_bones.set_end_bone_length(k, 0.06)
		spring_bones.set_radius(k, 0.02)
		spring_bones.set_stiffness(k, cloak_stiffness)
		spring_bones.set_drag(k, cloak_drag)
		spring_bones.set_gravity(k, cloak_gravity)
		spring_bones.set_enable_all_child_collisions(k, true)


func _scale_hint() -> float:
	var h := skeleton.get_bone_global_rest(skeleton.find_bone(&"Head")).origin.y
	return maxf(h / 1.56, 0.5)


func _setup_lantern() -> void:
	var socket := get_attachment(&"lantern")
	if socket == null:
		return
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = Color(1.0, 0.68, 0.36)
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	socket.add_child(light)
