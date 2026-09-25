class_name Inquisitor
extends EnemyBase
## Boss/chaser: very fast, regenerates, and cannot be Pushed/Pulled by its own
## spikes (shielded Metallic). Pulls itself toward anchored metals near the
## player to close distance fast, pushes the player's thrown coins away, and
## retreats briefly under 20% health. Uses the generic `Allomancer` when it
## exists; degrades gracefully to melee-only behaviour otherwise.

const ALLOMANCER_PATH := "res://src/allomancy/allomancer.gd"

@export var attack_damage: float = 45.0
@export var attack_reach: float = 2.5
@export var windup_time: float = 0.4
@export var attack_cooldown: float = 0.9
@export var regen_rate: float = 15.0
@export var retreat_fraction: float = 0.2
@export var retreat_duration: float = 4.0
@export var pull_check_interval: float = 1.2
@export var pull_check_radius: float = 10.0
@export var coin_push_radius: float = 8.0

var allomancer: Node = null
var hitbox: MeleeHitbox
var _attacking: bool = false
var _windup_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _pull_timer: float = 0.0
var _retreating: bool = false
var _retreat_timer: float = 0.0


func _ready() -> void:
	body_mass = 110.0
	move_speed = 6.0
	chase_speed = 9.0
	flee_health_fraction = retreat_fraction
	can_flee = true
	placeholder_color = Color(0.1, 0.1, 0.12)
	super._ready()
	engage_range = attack_reach
	hitbox = get_node_or_null(^"MeleeHitbox") as MeleeHitbox
	if hitbox:
		hitbox.attacker = self
		hitbox.damage = attack_damage
		hitbox.damage_kind = &"blade"
	if health:
		health.regen_per_second = regen_rate
		health.regen_delay = 0.5
	if ResourceLoader.exists(ALLOMANCER_PATH):
		var script: GDScript = load(ALLOMANCER_PATH)
		allomancer = script.new()
		allomancer.name = "Allomancer"
		add_child(allomancer)
		if allomancer.has_method("set_burning"):
			for mt: int in [Metal.Type.STEEL, Metal.Type.IRON, Metal.Type.PEWTER, Metal.Type.TIN]:
				allomancer.call("set_burning", mt, true)
	AudioManager.play_3d(&"inquisitor_scream", global_position)


func _get_model_path() -> String:
	return "res://assets/models/characters/inquisitor.tscn"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != State.DEAD and Engine.get_physics_frames() % 45 == 0:
		Events.allomantic_pulse.emit(self, Metal.Type.STEEL, global_position)


## Overrides the base flee behaviour: the Inquisitor only retreats briefly,
## it never fully disengages or searches afterwards.
func _combat_tick(delta: float) -> void:
	if target == null:
		return
	if not _retreating and health and health.ratio() < retreat_fraction:
		_retreating = true
		_retreat_timer = retreat_duration
	if _retreating:
		_retreat_timer -= delta
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_move_toward(global_position + away.normalized() * 8.0, chase_speed, delta)
		_face_point(target.global_position, delta)
		if _retreat_timer <= 0.0:
			_retreating = false
		return

	_pull_timer -= delta
	if _pull_timer <= 0.0:
		_pull_toward_target()
		_pull_timer = pull_check_interval
	_repel_coins()

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


## The Inquisitor never gives up the chase from low health alone; retreat is
## handled inline above instead of the base FLEE state.
func _update_combat(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_change_state(State.SEARCH)
		return
	last_known_target_pos = target.global_position
	_combat_tick(delta)


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


func _pull_toward_target() -> void:
	if allomancer == null or not allomancer.has_method("pull") or target == null:
		return
	var anchors: Array[Metallic] = MetalRegistry.query_radius(target.global_position, pull_check_radius)
	var best: Metallic = null
	var best_d := INF
	for m in anchors:
		if not m.anchored or m.shielded:
			continue
		var d := m.global_position.distance_to(target.global_position)
		if d < best_d:
			best_d = d
			best = m
	if best:
		allomancer.call("pull", best, 1.0, get_physics_process_delta_time())


func _repel_coins() -> void:
	if allomancer == null or not allomancer.has_method("push"):
		return
	for c in get_tree().get_nodes_in_group(&"coin"):
		if not (c is Node3D):
			continue
		if (c as Node3D).global_position.distance_to(global_position) > coin_push_radius:
			continue
		var m := c.get_node_or_null(^"Metallic")
		if m:
			allomancer.call("push", m, 1.0, get_physics_process_delta_time())
