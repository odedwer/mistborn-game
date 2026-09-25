class_name Hazekiller
extends EnemyBase
## No metal, wooden weapons. Blocks coins from the front with a wooden shield
## (a Health modifier reduces frontal &"coin" damage by 90%), throws javelins
## at range and fights with a staff up close. Seeks cover away from the
## player when it can't hold a good javelin range.

@export var melee_damage: float = 16.0
@export var melee_reach: float = 2.0
@export var windup_time: float = 0.4
@export var attack_cooldown: float = 1.1
@export var javelin_min_range: float = 8.0
@export var javelin_max_range: float = 25.0
@export var javelin_damage: float = 25.0
@export var javelin_speed: float = 22.0
@export var javelin_cooldown: float = 3.0
@export var shield_reduction: float = 0.9  ## fraction of frontal coin damage blocked

var hitbox: MeleeHitbox
var _attacking: bool = false
var _windup_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _javelin_timer: float = 0.0


func _ready() -> void:
	body_mass = 78.0
	placeholder_color = Color(0.4, 0.32, 0.2)
	super._ready()
	engage_range = javelin_max_range
	hitbox = get_node_or_null(^"MeleeHitbox") as MeleeHitbox
	if hitbox:
		hitbox.attacker = self
		hitbox.damage = melee_damage
		hitbox.damage_kind = &"blunt"
	if health:
		health.add_modifier(_shield_modifier)


func _get_model_path() -> String:
	return "res://assets/models/characters/hazekiller.tscn"


## Wooden shield blocks 90% of coin damage arriving from the front 180° arc.
func _shield_modifier(amount: float, kind: StringName, source: Node) -> float:
	if kind != &"coin" or source == null or not (source is Node3D):
		return amount
	var to_source: Vector3 = (source as Node3D).global_position - global_position
	to_source.y = 0.0
	if to_source.length() < 0.01:
		return amount
	to_source = to_source.normalized()
	var forward := -global_transform.basis.z
	var angle := rad_to_deg(acos(clampf(forward.dot(to_source), -1.0, 1.0)))
	if angle <= 90.0:
		return amount * (1.0 - shield_reduction)
	return amount


func _combat_tick(delta: float) -> void:
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	_javelin_timer = maxf(_javelin_timer - delta, 0.0)

	if dist <= melee_reach:
		_stop_moving()
		if not _attacking and _cooldown_timer <= 0.0:
			_start_melee()
	elif dist < javelin_min_range:
		_move_toward(_find_cover_point(), chase_speed, delta)
	elif dist <= javelin_max_range:
		_stop_moving()
		if _javelin_timer <= 0.0:
			_throw_javelin()
			_javelin_timer = javelin_cooldown
	else:
		_move_toward(target.global_position, chase_speed, delta)

	_face_point(target.global_position, delta)
	if _attacking:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_perform_melee()


func _start_melee() -> void:
	_attacking = true
	_windup_timer = windup_time
	if model and model.has_method("play_action"):
		model.call("play_action", &"attack")


func _perform_melee() -> void:
	_attacking = false
	_cooldown_timer = attack_cooldown
	if hitbox:
		hitbox.begin_swing()
		var swing_timer := get_tree().create_timer(0.15)
		swing_timer.timeout.connect(hitbox.end_swing)
	AudioManager.play_3d(&"hit_flesh", global_position)


func _throw_javelin() -> void:
	if target == null:
		return
	var javelin := Javelin.new()
	javelin.damage = javelin_damage
	var parent := get_tree().current_scene if get_tree().current_scene else get_parent()
	parent.add_child(javelin)
	javelin.launch(global_position + Vector3.UP * 1.4, target.global_position + Vector3.UP * 1.0, javelin_speed, self)
	AudioManager.play_3d(&"javelin_throw", global_position)
	if model and model.has_method("play_action"):
		model.call("play_action", &"throw")


## Picks a point on the far side of the nearest obstacle behind the hazekiller
## (relative to the player), so the player's line of sight gets blocked.
func _find_cover_point() -> Vector3:
	if target == null:
		return global_position
	var away := global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = -global_transform.basis.z
	away = away.normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP
	var to := from + away * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return global_position + away * 6.0
	var hit_pos: Vector3 = result["position"]
	return hit_pos + away * 1.5
