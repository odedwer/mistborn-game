class_name Thug
extends EnemyBase
## Pewterarm thug: fast, heavy melee hits with knockback, no metal (only
## coins can hurt it "through" its toughness), and takes 50% less blunt/blade
## damage.

@export var attack_damage: float = 35.0
@export var attack_reach: float = 1.9
@export var attack_knockback: float = 6.0
@export var windup_time: float = 0.35
@export var attack_cooldown: float = 1.0
@export var damage_resist: float = 0.5  ## fraction of blunt/blade damage resisted

var hitbox: MeleeHitbox
var _attacking: bool = false
var _windup_timer: float = 0.0
var _cooldown_timer: float = 0.0


func _ready() -> void:
	body_mass = 100.0
	move_speed = 4.0
	chase_speed = 7.0
	placeholder_color = Color(0.35, 0.2, 0.18)
	super._ready()
	engage_range = attack_reach
	hitbox = get_node_or_null(^"MeleeHitbox") as MeleeHitbox
	if hitbox:
		hitbox.attacker = self
		hitbox.damage = attack_damage
		hitbox.damage_kind = &"blunt"
		hitbox.knockback = attack_knockback
	if health:
		health.add_modifier(_toughness_modifier)
	AudioManager.play_3d(&"thug_roar", global_position)


func _get_model_path() -> String:
	return "res://assets/models/characters/thug.tscn"


func _toughness_modifier(amount: float, kind: StringName, _source: Node) -> float:
	if kind == &"blunt" or kind == &"blade":
		return amount * (1.0 - damage_resist)
	return amount


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
