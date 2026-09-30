class_name FastTravelManager
extends Node
## Crew safehouses (world landmarks, `res://src/world/data/luthadel_plan.json`
## `landmarks` with `type: "safehouse"`) double as fast-travel points.
##
## Walking within range of a safehouse's "fast_travel_point" world marker
## unlocks it (`GameState.discover_safehouse`), persisted across saves. The
## trigger area is parented to the safehouse's own streamed landmark unit
## (like `ActivityManager`'s beacons/`CrowdSystem`'s pedestrians), so it exists
## only while that unit is loaded and is rebuilt when it streams back in —
## unlocking itself does not depend on the node being alive, since it is
## recorded in `GameState` the moment the player enters it once.
##
## Standing at a discovered safehouse, `interact` waits there until nightfall
## (or, at night, until morning): `wait_at_safehouse` skips the `TimeOfDay`
## clock under a fade. Not while a mission pins the phase.
##
## `travel_to(id)` (called from the map's fast-travel list) hands off to
## `SceneTransition.fast_travel_to`, which fades out, streams the destination
## chunk in synchronously, teleports, then fades back in.

const TRIGGER_RADIUS := 6.0

var _triggers: Array[Area3D] = []
## Safehouse the player is standing at (&"" = none).
var near_safehouse: StringName = &""


func _ready() -> void:
	add_to_group(&"fast_travel_manager")
	_build_triggers.call_deferred()
	var world := _find_world_node()
	if world != null and world.has_signal(&"markers_spawned"):
		world.connect(&"markers_spawned", _on_markers_spawned)


func _exit_tree() -> void:
	for a in _triggers:
		if is_instance_valid(a):
			a.queue_free()
	_triggers.clear()


func _find_world_node() -> Node:
	return get_tree().get_first_node_in_group(&"world")


func _build_triggers() -> void:
	for m in get_tree().get_nodes_in_group(&"fast_travel_point"):
		_add_trigger_for_marker(m)


func _on_markers_spawned(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n) and n.is_in_group(&"fast_travel_point"):
			_add_trigger_for_marker(n)


func _add_trigger_for_marker(marker: Node) -> void:
	if not (marker is Node3D):
		return
	var sid: StringName = marker.get_meta("safehouse_id", &"")
	if sid == &"":
		return
	var sname := str(marker.get_meta("safehouse_name", String(sid)))
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1  # "player" physics layer
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	area.add_child(shape)
	# Streams with the safehouse's own unit, like activity beacons and pickups.
	var parent: Node = marker.get_parent() if marker.get_parent() != null else self
	parent.add_child(area)
	area.global_position = (marker as Node3D).global_position
	area.body_entered.connect(_on_entered.bind(sid, sname))
	area.body_exited.connect(_on_exited.bind(sid))
	_triggers.append(area)


func _on_entered(body: Node, sid: StringName, sname: String) -> void:
	if not body.is_in_group(&"player"):
		return
	near_safehouse = sid
	if GameState.discover_safehouse(sid):
		Events.hint_requested.emit("Safehouse discovered: %s — fast travel unlocked." % sname, 3.5)
	elif not TimeOfDay.is_forced():
		Events.hint_requested.emit("%s — press Interact to wait until %s." % [sname, "morning" if TimeOfDay.is_night() else "nightfall"], 3.0)


func _on_exited(body: Node, sid: StringName) -> void:
	if body.is_in_group(&"player") and near_safehouse == sid:
		near_safehouse = &""


func _unhandled_input(event: InputEvent) -> void:
	if near_safehouse != &"" and event.is_action_pressed(&"interact") and not SceneTransition.busy:
		wait_at_safehouse(TimeOfDay.Phase.DAY if TimeOfDay.is_night() else TimeOfDay.Phase.NIGHT)


## "Wait until night" (or day): skips the clock to the start of `target`
## under a fade. Refused while a mission forces the phase. With `fade` false
## (tests) the clock jumps immediately.
func wait_at_safehouse(target: int = TimeOfDay.Phase.NIGHT, fade := true) -> bool:
	if TimeOfDay.is_forced():
		Events.hint_requested.emit("No time to rest now.", 2.5)
		return false
	if TimeOfDay.phase == target:
		return true
	var jump := func() -> void: TimeOfDay.wait_until(target)
	if fade and is_inside_tree():
		await SceneTransition.fade_through(jump)
	else:
		jump.call()
	Events.hint_requested.emit("You wait at the safehouse until %s (%s)." % ["nightfall" if target == TimeOfDay.Phase.NIGHT else "morning", TimeOfDay.clock_text()], 3.0)
	return true


## Unlocked safehouses, city-wide (works even if their unit is unloaded), as
## `{id: StringName, name: String, position: Vector3}` for the map's list.
func unlocked_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in GameState.discovered_safehouses.keys():
		var sid := StringName(key)
		var entry := _entry_for(sid)
		if entry.get("position", Vector3.INF) != Vector3.INF:
			out.append(entry)
	return out


func _entry_for(sid: StringName) -> Dictionary:
	for n in get_tree().get_nodes_in_group(&"fast_travel_point"):
		if n is Node3D and StringName(str(n.get_meta("safehouse_id", ""))) == sid:
			return {"id": sid, "name": str(n.get_meta("safehouse_name", String(sid))), "position": (n as Node3D).global_position}
	var world := _find_world_node()
	if world != null and world.has_method("get_marker_data"):
		for e: Dictionary in world.call("get_marker_data", &"fast_travel_point"):
			var meta: Dictionary = e.get("meta", {})
			if StringName(str(meta.get("safehouse_id", ""))) == sid:
				return {"id": sid, "name": str(meta.get("safehouse_name", String(sid))), "position": e.get("position", Vector3.INF)}
	return {"id": sid, "name": String(sid), "position": Vector3.INF}


## Fast-travels the player to safehouse `sid` (must already be unlocked).
func travel_to(sid: StringName) -> bool:
	if not GameState.is_safehouse_unlocked(sid):
		return false
	var pos: Vector3 = _entry_for(sid).get("position", Vector3.INF)
	if pos == Vector3.INF:
		return false
	return await SceneTransition.fast_travel_to(pos)
