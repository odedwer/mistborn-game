class_name CharacterAimModifier
extends SkeletonModifier3D
## Adds a yaw/pitch "look" offset on top of the animated pose, spread along the
## spine -> head chain. Driven by CharacterModel.set_aim().

const CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest", &"Neck", &"Head"]
const WEIGHTS: Array[float] = [0.12, 0.18, 0.2, 0.22, 0.28]

@export var max_yaw := deg_to_rad(75.0)
@export var max_pitch := deg_to_rad(50.0)
@export var smoothing := 10.0

var target_yaw := 0.0
var target_pitch := 0.0
var enabled := false

var _yaw := 0.0
var _pitch := 0.0
var _bones: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_cache()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_cache()


func _cache() -> void:
	_bones.clear()
	var sk := get_skeleton()
	if sk == null:
		return
	for n in CHAIN:
		_bones.append(sk.find_bone(n))


## `dir` is in skeleton space (-Z forward). Zero vector disables the look-at.
func set_direction(dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		enabled = false
		return
	dir = dir.normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := atan2(dir.y, Vector2(dir.x, dir.z).length())
	# fade out when the target is behind the character
	var fade := clampf((deg_to_rad(150.0) - absf(yaw)) / deg_to_rad(40.0), 0.0, 1.0)
	target_yaw = clampf(yaw, -max_yaw, max_yaw) * fade
	target_pitch = clampf(pitch, -max_pitch, max_pitch) * fade
	enabled = true


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _bones.size() != CHAIN.size():
		return
	var ty := target_yaw if enabled else 0.0
	var tp := target_pitch if enabled else 0.0
	var k := 1.0 - exp(-smoothing * delta)
	_yaw = lerpf(_yaw, ty, k)
	_pitch = lerpf(_pitch, tp, k)
	if absf(_yaw) < 1e-4 and absf(_pitch) < 1e-4:
		return
	for i in _bones.size():
		var b := _bones[i]
		if b < 0:
			continue
		var w := WEIGHTS[i]
		var g := sk.get_bone_global_pose(b).basis
		var r := Basis(Vector3.UP, _yaw * w) * Basis(Vector3.RIGHT, _pitch * w)
		var p := sk.get_bone_parent(b)
		var pg := sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
		sk.set_bone_pose_rotation(b, (pg.inverse() * (r * g)).get_rotation_quaternion())
