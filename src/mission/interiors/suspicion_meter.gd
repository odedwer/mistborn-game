class_name SuspicionMeter
extends Node
## "Lady Valette" social stealth: a suspicion meter that rises when the
## disguised player Pushes/Pulls or flares any metal near a noble (any
## `NPCTalker`, since the ball's nobles are the only ones in this scene), and
## decays otherwise. Reaching `max_value` fails the mission. Self-contained —
## add as a child of an interior scene; it needs no wiring from
## `MissionDirector` beyond that scene existing while the mission runs.

@export var max_value := 100.0
@export var decay_per_sec := 6.0
## How close a noble has to be to notice a Push/Pull or a flare at all.
@export var alert_radius := 9.0
@export var push_gain := 22.0
@export var flare_gain := 35.0
@export var mission_id: StringName = &"lady_valette"

var value := 0.0
var _active := true


func _ready() -> void:
	Events.allomantic_line_used.connect(_on_line_used)
	Events.metal_flare_changed.connect(_on_flare_changed)


func _process(delta: float) -> void:
	if value <= 0.0:
		return
	value = maxf(0.0, value - decay_per_sec * delta)
	Events.suspicion_changed.emit(value, max_value)


func _on_line_used(allomancer: Node, _target: Node, _metal: int, _strength: float) -> void:
	if _active and _is_player(allomancer):
		_gain(push_gain)


func _on_flare_changed(allomancer: Node, _metal: int, flaring: bool) -> void:
	if _active and flaring and _is_player(allomancer):
		_gain(flare_gain)


func _gain(amount: float) -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not _near_noble(player):
		return
	value = clampf(value + amount, 0.0, max_value)
	Events.suspicion_changed.emit(value, max_value)
	if value >= max_value:
		_active = false
		Events.hint_requested.emit("A noble's eyes narrow. You've been seen.", 4.0)
		Events.mission_failed.emit(mission_id, "detected")


func _near_noble(player: Node) -> bool:
	if not (player is Node3D):
		return false
	for n in get_tree().get_nodes_in_group(&"npc_talker"):
		if n is Node3D and (n as Node3D).global_position.distance_to((player as Node3D).global_position) <= alert_radius:
			return true
	return false


func _is_player(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group(&"player"):
			return true
		n = n.get_parent()
	return false
