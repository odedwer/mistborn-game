class_name Coin
extends RigidBody3D
## A clip: a small metal coin, thrown by hand and then Pushed as a projectile,
## or dropped as a steel-jump anchor. Pooled by CoinPool (never free coins
## yourself; call CoinPool.recycle).
##
## Damage on impact scales with speed (kind &"coin"). The pool clamps the
## speed and updates `impact_speed` every physics tick, so this script has no
## per-frame processing of its own.

const LAYER_PLAYER := 1 << 1
## world | enemies | metal_props | coins
const BASE_MASK := 1 | (1 << 2) | (1 << 3) | (1 << 4)

## Impacts slower than this (m/s) do no damage.
@export var min_damage_speed := 12.0
## Damage per m/s above min_damage_speed.
@export var damage_per_speed := 1.0
## Damage cap for one impact.
@export var max_damage := 95.0

## The Metallic child (cached).
var metallic: Metallic
## Last actor that threw/Pushed/Pulled this coin (kill credit, friendly fire).
var last_pusher: Node
## Seconds since the coin was last thrown or affected by allomancy.
var idle_time := 0.0
## Speed at the start of the current physics tick (set by the pool).
var impact_speed := 0.0
## True while in play (false while parked in the pool).
var active := false
## While > 0 the coin counts as an anchor even in mid-air (coin-jump assist).
var virtual_anchor_time := 0.0

var _hit_cooldown := 0.0


## Damage a coin hitting something at `speed` m/s deals with default tuning.
static func damage_for_speed(speed: float, min_speed: float = 12.0, per_speed: float = 1.0, cap: float = 95.0) -> float:
	return clampf((speed - min_speed) * per_speed, 0.0, cap)


func _ready() -> void:
	add_to_group(&"coin")
	metallic = get_node(^"Metallic") as Metallic
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	collision_layer = 1 << 4
	collision_mask = BASE_MASK
	body_entered.connect(_on_body_entered)


## Called by Allomancer on every Push/Pull (and when thrown).
func set_last_pusher(n: Node) -> void:
	idle_time = 0.0
	if n == last_pusher:
		return
	last_pusher = n
	# Coins sent by enemies can hit the player; the player's own coins pass through.
	var by_player := n != null and n.is_in_group(&"player")
	collision_mask = BASE_MASK if by_player else BASE_MASK | LAYER_PLAYER


## True while this coin should act as an anchor although it's airborne.
func is_virtual_anchor() -> bool:
	return virtual_anchor_time > 0.0


## Pool tick: timers and speed bookkeeping.
func pool_tick(delta: float, speed: float) -> void:
	impact_speed = speed
	idle_time += delta
	if _hit_cooldown > 0.0:
		_hit_cooldown -= delta
	if virtual_anchor_time > 0.0:
		virtual_anchor_time -= delta


func _on_body_entered(other: Node) -> void:
	var speed := maxf(impact_speed, linear_velocity.length())
	if _hit_cooldown > 0.0 or speed < 2.0:
		return
	_hit_cooldown = 0.12
	var h := Health.find_on(other)
	if speed >= min_damage_speed and h != null and h.get_parent() != last_pusher:
		var src: Node = last_pusher if is_instance_valid(last_pusher) else self
		h.take_damage(damage_for_speed(speed, min_damage_speed, damage_per_speed, max_damage), src, &"coin")
		AudioManager.play_3d(&"coin_hit", global_position)
		Events.noise_emitted.emit(global_position, 0.35, self)
		linear_velocity *= 0.15
	else:
		AudioManager.play_3d(&"coin_clink", global_position, clampf(speed * 0.5 - 12.0, -12.0, 0.0))
		Events.noise_emitted.emit(global_position, clampf(speed / 40.0, 0.08, 0.4), self)
