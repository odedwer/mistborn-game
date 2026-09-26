class_name Guard
extends EnemyBase
## Obligator's guard: spear melee with a telegraphed windup, wears a steel
## breastplate (a NOT-shielded [Metallic] child — the player can Push/Pull
## guards), and carries a lantern at night.

@export var attack_damage: float = 20.0
@export var attack_reach: float = 2.2
@export var windup_time: float = 0.5
@export var attack_cooldown: float = 1.2

var hitbox: MeleeHitbox
var lantern: OmniLight3D
var _attacking: bool = false
var _windup_timer: float = 0.0
var _cooldown_timer: float = 0.0


func _ready() -> void:
	body_mass = 80.0
	placeholder_color = Color(0.5, 0.5, 0.55)
	super._ready()
	engage_range = attack_reach
	hitbox = get_node_or_null(^"MeleeHitbox") as MeleeHitbox
	if hitbox:
		hitbox.attacker = self
		hitbox.damage = attack_damage
		hitbox.damage_kind = &"blade"
	lantern = get_node_or_null(^"Lantern") as OmniLight3D
	# The character model carries its own lantern light in the hand; the
	# scene's placeholder light doubled it into a blown-out ball in the mist.
	var model_light := find_child("LanternLight", true, false) as OmniLight3D
	if model_light != null:
		if lantern != null:
			lantern.queue_free()
		lantern = model_light
		lantern.light_volumetric_fog_energy = 0.35


func _get_model_path() -> String:
	return "res://assets/models/characters/guard.tscn"


func _combat_tick(delta: float) -> void:
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if dist <= attack_reach:
		_stop_moving()
		if not _attacking and _cooldown_timer <= 0.0:
			_start_attack()
	else:
		_attacking = false
		_windup_timer = 0.0
		_move_toward(target.global_position, chase_speed, delta)
	_face_point(target.global_position, delta)
	if _attacking:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_perform_attack()


func _start_attack() -> void:
	_attacking = true
	_windup_timer = windup_time
	AudioManager.play_3d(&"spear_swing", global_position)
	if model and model.has_method("play_action"):
		model.call("play_action", &"attack")


func _perform_attack() -> void:
	_attacking = false
	_cooldown_timer = attack_cooldown
	if hitbox:
		hitbox.begin_swing()
		var swing_timer := get_tree().create_timer(0.15)
		swing_timer.timeout.connect(hitbox.end_swing)
	AudioManager.play_3d(&"hit_flesh", global_position)
