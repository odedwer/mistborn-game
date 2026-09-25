class_name PlayerCamera
extends Node3D
## Over-the-shoulder camera rig with a first-person toggle.
##
## Hierarchy (see player.tscn): CameraRig (this, top_level) > Pitch >
## SpringArm3D > Camera3D (+ SpeedLines quad). The rig follows the player's
## (predicted) position with exponential smoothing and a clamped lag, handles
## mouse and gamepad look, pulls back and widens FOV at high speed, leads the
## view along the direction of travel, and adds trauma-based shake.

const WORLD_MASK := 1

@export_group("Framing")
@export var pivot_height := 1.6
@export var crouch_pivot_height := 1.05
@export var first_person_height := 1.62
@export var shoulder_offset := 0.55
@export var distance := 3.2
## Extra arm length (m) at full speed.
@export var speed_pullback := 1.8
## Horizontal look-ahead (m) along velocity at full speed.
@export var look_ahead := 1.2
@export var pitch_min_deg := -85.0
@export var pitch_max_deg := 80.0

@export_group("Follow")
## Exponential follow sharpness (1/s).
@export var follow_sharpness := 18.0
## Maximum distance (m) the pivot may lag behind the player.
@export var max_lag := 0.9
## Seconds for the first-person/third-person blend.
@export var mode_blend_time := 0.2

@export_group("Speed")
## Speed (m/s) where the speed effects start / reach full strength.
@export var speed_effect_start := 14.0
@export var speed_effect_full := 70.0
## FOV added at full speed (degrees).
@export var fov_kick := 20.0

@export_group("Input")
## Gamepad look speed (rad/s at full stick).
@export var gamepad_look_speed := 3.2

@export_group("Shake")
@export var shake_decay := 1.6
@export var max_shake_offset := 0.12
@export var max_shake_roll_deg := 2.5

## The body being followed. Set by the player.
var target: CharacterBody3D
var yaw := 0.0
var pitch_angle := -0.15
var first_person := false
var crouching := false
var trauma := 0.0
## 0..1 speed effect amount (read by the player for footstep/camera effects).
var speed_amount := 0.0

var _pitch: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _speed_lines: MeshInstance3D
var _speed_mat: ShaderMaterial
var _fp_blend := 0.0
var _pivot := Vector3.ZERO
var _height := 1.6
var _time := 0.0
var _dip := 0.0
var _dip_vel := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _base_fov := 80.0


func _ready() -> void:
	top_level = true
	_pitch = get_node(^"Pitch") as Node3D
	_arm = get_node(^"Pitch/SpringArm3D") as SpringArm3D
	_camera = get_node(^"Pitch/SpringArm3D/Camera3D") as Camera3D
	_speed_lines = get_node_or_null(^"Pitch/SpringArm3D/Camera3D/SpeedLines") as MeshInstance3D
	if _speed_lines != null:
		_speed_mat = _speed_lines.material_override as ShaderMaterial
		_speed_lines.visible = false
	_arm.collision_mask = WORLD_MASK
	_ray.collision_mask = WORLD_MASK
	_height = pivot_height
	_apply_settings()
	Events.settings_changed.connect(_apply_settings)


func _apply_settings() -> void:
	_base_fov = GameSettings.fov
	if _camera != null:
		_camera.fov = _base_fov


func get_camera() -> Camera3D:
	return _camera


## Snaps the rig to the target (after spawning/teleporting).
func snap() -> void:
	if target == null:
		return
	_pivot = target.global_position
	global_position = _pivot + Vector3.UP * _height


## Horizontal basis the player moves in.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Crosshair ray origin (camera position).
func aim_origin() -> Vector3:
	return _camera.global_position


## Crosshair ray direction (camera forward).
func aim_direction() -> Vector3:
	return -_camera.global_basis.z


## Distance from the camera to the player's pivot along the view (to ignore
## metals between the camera and the player when targeting).
func distance_to_pivot() -> float:
	return (global_position - _camera.global_position).dot(aim_direction())


func add_look(dyaw: float, dpitch: float) -> void:
	yaw = wrapf(yaw + dyaw, -PI, PI)
	pitch_angle = clampf(pitch_angle + dpitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## A downward camera kick (landing), in metres.
func add_dip(amount: float) -> void:
	_dip_vel -= amount * 12.0


func set_first_person(on: bool) -> void:
	first_person = on


func toggle_first_person() -> void:
	first_person = not first_person


## 0 = third person, 1 = first person (blended).
func first_person_blend() -> float:
	return _fp_blend


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens: float = GameSettings.mouse_sensitivity
		var inv := -1.0 if GameSettings.invert_y else 1.0
		add_look(-mm.relative.x * sens, -mm.relative.y * sens * inv)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Engine.time_scale (atium) slows the world, but the camera stays responsive.
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	_time += real_dt
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		var inv := -1.0 if GameSettings.invert_y else 1.0
		add_look(-stick.x * gamepad_look_speed * real_dt, -stick.y * gamepad_look_speed * real_dt * inv)

	# Predict the body position between physics ticks for smooth high-speed follow.
	var vel := target.velocity
	var frac := Engine.get_physics_interpolation_fraction()
	var predicted := target.global_position + vel * (frac / float(Engine.physics_ticks_per_second))
	var speed := vel.length()
	speed_amount = clampf((speed - speed_effect_start) / (speed_effect_full - speed_effect_start), 0.0, 1.0)

	var h_vel := Vector3(vel.x, 0.0, vel.z)
	var ahead := Vector3.ZERO
	if h_vel.length() > 0.5:
		ahead = h_vel.normalized() * look_ahead * speed_amount
	var goal := predicted + ahead
	_pivot = _pivot.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	var lag := goal - _pivot
	if lag.length() > max_lag:
		_pivot = goal - lag.normalized() * max_lag

	_fp_blend = move_toward(_fp_blend, 1.0 if first_person else 0.0, real_dt / maxf(mode_blend_time, 0.01))
	var tp_height := crouch_pivot_height if crouching else pivot_height
	var fp_height := first_person_height - (0.55 if crouching else 0.0)
	_height = lerpf(_height, lerpf(tp_height, fp_height, _fp_blend), 1.0 - exp(-12.0 * real_dt))

	# Landing dip: critically damped spring back to 0.
	_dip_vel += (-_dip * 180.0 - _dip_vel * 22.0) * real_dt
	_dip += _dip_vel * real_dt

	global_position = _pivot + Vector3.UP * (_height + _dip)
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch.rotation = Vector3(pitch_angle, 0.0, 0.0)

	# Shoulder offset, pulled in if a wall is beside the head.
	var shoulder := shoulder_offset * (1.0 - _fp_blend)
	if shoulder > 0.01:
		_ray.from = global_position
		_ray.to = global_position + global_basis.x * (shoulder + 0.2)
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			shoulder = maxf(global_position.distance_to(hit["position"]) - 0.25, 0.0)
	_arm.position = Vector3(shoulder, 0.0, 0.0)
	_arm.spring_length = (distance + speed_pullback * speed_amount) * (1.0 - _fp_blend)

	# FOV kick.
	var fov_goal := _base_fov + fov_kick * speed_amount * speed_amount * (1.0 - 0.5 * _fp_blend)
	_camera.fov = lerpf(_camera.fov, fov_goal, 1.0 - exp(-6.0 * real_dt))

	# Shake.
	trauma = maxf(trauma - shake_decay * real_dt, 0.0)
	var s := trauma * trauma
	_camera.h_offset = max_shake_offset * s * sin(_time * 37.0 + 1.3) * cos(_time * 23.0)
	_camera.v_offset = max_shake_offset * s * sin(_time * 41.0 + 4.1) * cos(_time * 17.0)
	_camera.rotation.z = deg_to_rad(max_shake_roll_deg) * s * sin(_time * 29.0 + 2.7)

	if _speed_lines != null:
		var amt := speed_amount * speed_amount
		_speed_lines.visible = amt > 0.02
		if _speed_lines.visible:
			_speed_mat.set_shader_parameter(&"amount", amt)
