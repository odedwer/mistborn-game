class_name Seeker
extends EnemyBase
## Obligator Seeker (Act II): a bronze-burning sentry that senses the
## player's own allomantic pulses instead of relying on sight/sound alone.
## Used in the Canton of Resource heist so copper (Coppercloud) is the real
## counter, not just staying out of lantern light.
##
## `Allomancer._tick_pulses` already skips emitting `Events.allomantic_pulse`
## while the source is burning copper (see `src/allomancy/allomancer.gd`), so
## this script needs no copper-awareness of its own: it simply reacts to
## pulses that *do* arrive. A Seeker that senses a pulse within `sense_range`
## investigates it exactly like a noise, and repeated/close pulses escalate it
## straight to combat.

@export var sense_range: float = 22.0
## A pulse this close is treated as spotting the source outright.
@export var alarm_range: float = 9.0

var _sensed_count: int = 0


func _ready() -> void:
	body_mass = 78.0
	placeholder_color = Color(0.35, 0.3, 0.5)
	super._ready()
	Events.allomantic_pulse.connect(_on_allomantic_pulse)


func _get_model_path() -> String:
	return "res://assets/models/characters/seeker.tscn"


func _on_allomantic_pulse(source: Node, _metal: int, position: Vector3) -> void:
	if state == State.DEAD or state == State.COMBAT:
		return
	if source == self or not is_instance_valid(source):
		return
	var dist := global_position.distance_to(position)
	if dist > sense_range:
		return
	if dist <= alarm_range and source is Node3D:
		target = source as Node3D
		last_known_target_pos = position
		_change_state(State.COMBAT)
		return
	investigate_point = position
	_sensed_count += 1
	if state != State.INVESTIGATE:
		_change_state(State.INVESTIGATE)
