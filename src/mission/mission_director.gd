class_name MissionDirector
extends Node
## Generic, data-driven mission runner.
##
## Loads `MissionData` (see `mission_data.gd` for the JSON schema and the
## objective types it understands) and drives stages/objectives from it,
## using `objective_point` markers, `checkpoint` areas, and `Events` signals.
## The vertical slice mission "Mistwalk to Keep Venture" is just the first
## JSON file under `res://src/mission/missions/`; nothing here is specific to
## it, so the whole story and side activities (coin races, rooftop pursuits,
## ambushes, collectibles) can ship as more `MissionData` files later.
##
## Add one `MissionDirector` to the game scene. It self-configures from
## `GameState.mission_id` / `GameState.mission_stage` on `_ready`, so a loaded
## save resumes at the right objective.

signal mission_finished(id: StringName)
signal stage_advanced(stage_index: int, stage_label: String)

const TRIGGER_RADIUS := 4.0
const FADE_TIME := 0.5

var story := StoryManager.new()
var mission: MissionData
var stage_index: int = 0
## objective id (StringName) -> objective dict, for the current stage's
## not-yet-completed objectives.
var _active_objectives: Dictionary = {}
## Remaining objectives of a sequential stage, activated one at a time.
var _pending_objectives: Array[Dictionary] = []
var _triggers: Array[Area3D] = []
var _hinted_metal_use := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
## Optional player-set waypoint (from the map screen) overriding the current
## objective marker in the HUD. Set via `set_waypoint` / cleared via
## `clear_waypoint`.
var waypoint: Vector3 = Vector3.INF


func _ready() -> void:
	add_to_group("mission_director")
	story.refresh()
	_connect_checkpoints()
	Events.player_died.connect(_on_player_died)
	Events.metal_burn_changed.connect(_on_metal_burn_changed)
	Events.allomantic_line_used.connect(_on_allomantic_line_used)
	Events.pickup_collected.connect(_on_pickup_collected)
	Events.actor_died.connect(_on_actor_died)
	_build_fade_layer()
	_start_or_resume()


func _start_or_resume() -> void:
	mission = story.get_mission(GameState.mission_id)
	if mission == null:
		mission = story.next_story_mission(GameState.completed_objectives.map(func(x): return x))
	if mission == null and not story.all_missions.is_empty():
		mission = story.all_missions[0]
	if mission == null:
		push_warning("MissionDirector: no mission data found under res://src/mission/missions/")
		return
	GameState.mission_id = mission.id
	stage_index = clampi(GameState.mission_stage, 0, maxi(mission.stages.size() - 1, 0))
	_activate_stage(stage_index)


func _connect_checkpoints() -> void:
	for area in get_tree().get_nodes_in_group("checkpoint"):
		if area is Area3D and not area.body_entered.is_connected(_on_checkpoint_body_entered):
			area.body_entered.connect(_on_checkpoint_body_entered.bind(area))


func _on_checkpoint_body_entered(body: Node, area: Area3D) -> void:
	if not body.is_in_group("player"):
		return
	var cp_id: StringName = area.get_meta("checkpoint_id", &"")
	if cp_id != &"":
		Events.checkpoint_reached.emit(cp_id)


# --- Stage / objective lifecycle --------------------------------------------

func _activate_stage(index: int) -> void:
	_clear_triggers()
	_active_objectives.clear()
	if index >= mission.stages.size():
		return
	var stage: Dictionary = mission.stages[index]
	stage_advanced.emit(index, stage.get("label", ""))
	# Stages are sequential by default (tutorial beats one at a time); set
	# "parallel": true on a stage to activate all its objectives together.
	_pending_objectives.clear()
	for obj: Dictionary in stage.get("objectives", []):
		if not GameState.completed_objectives.has(StringName(obj.get("id", ""))):
			_pending_objectives.append(obj)
	if _pending_objectives.is_empty():
		_advance_stage.call_deferred()
		return
	if stage.get("parallel", false):
		var batch := _pending_objectives.duplicate()
		_pending_objectives.clear()
		# Register all as active *before* activating any, so one that completes
		# instantly (cutscene_hint) can't advance the stage early.
		for obj: Dictionary in batch:
			_active_objectives[StringName(obj.get("id", ""))] = obj
		for obj: Dictionary in batch:
			_activate_objective(obj)
	else:
		_activate_next_pending()


## Activates the next queued objective of a sequential stage.
func _activate_next_pending() -> void:
	var obj: Dictionary = _pending_objectives.pop_front()
	_active_objectives[StringName(obj.get("id", ""))] = obj
	_activate_objective(obj)


func _activate_objective(obj: Dictionary) -> void:
	var type: String = obj.get("type", "")
	# Announce before activating: instant objectives (cutscene_hint) complete
	# inside the match and chain into the next one, which must be the last
	# "not done" update the tracker sees.
	if type != "cutscene_hint":
		Events.objective_updated.emit(StringName(obj.get("id", "")), obj.get("text", ""), false)
	match type:
		"cutscene_hint":
			Events.hint_requested.emit(obj.get("text", ""), obj.get("duration", 4.0))
			complete_objective(obj)
		"reach_marker", "escape", "interact":
			_spawn_trigger_for(obj)
		"use_metal", "defeat", "collect":
			pass # driven by Events, see the handlers below.


func _spawn_trigger_for(obj: Dictionary) -> void:
	var pos := _find_marker_position(obj.get("marker_group", "objective_point"), obj.get("marker_id", ""))
	if pos == Vector3.INF:
		return
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1  # "player" physics layer
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	area.add_child(shape)
	get_tree().root.add_child(area)
	area.global_position = pos
	area.body_entered.connect(_on_objective_trigger_entered.bind(obj))
	_triggers.append(area)


func _on_objective_trigger_entered(body: Node, obj: Dictionary) -> void:
	if not body.is_in_group("player"):
		return
	if obj.get("type", "") == "interact":
		Events.pickup_collected.emit(StringName(obj.get("interact_kind", "")), 1.0)
	complete_objective(obj)


## Finds a marker's world position. Prefers live `Marker3D`/`Area3D` nodes in
## `group`, then falls back to `LuthadelWorld.get_marker_data(group)` (any
## node in the tree exposing that method) so far-away, unloaded chunks still
## report their marker positions.
func _find_marker_position(group: String, marker_id: String) -> Vector3:
	for n in get_tree().get_nodes_in_group(group):
		var id: String = str(n.get_meta("objective_id", n.get_meta("checkpoint_id", "")))
		if id == marker_id and n is Node3D:
			return (n as Node3D).global_position
	var world := _find_world_node()
	if world != null and world.has_method("get_marker_data"):
		var data: Array = world.call("get_marker_data", group)
		for entry: Dictionary in data:
			var meta: Dictionary = entry.get("meta", {})
			if str(meta.get("objective_id", meta.get("checkpoint_id", ""))) == marker_id:
				return entry.get("position", Vector3.INF)
	return Vector3.INF


func _find_world_node() -> Node:
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		return world
	return get_node_or_null(^"/root/Game/World")


func complete_objective(obj: Dictionary) -> void:
	var id := StringName(obj.get("id", ""))
	if GameState.completed_objectives.has(id):
		return
	_active_objectives.erase(id)
	_pending_objectives.erase(obj)
	Events.objective_updated.emit(id, obj.get("text", ""), true)
	AudioManager.play_ui(&"objective_complete")
	for action: Dictionary in obj.get("on_complete", []):
		_run_action(action)
	if not _active_objectives.is_empty():
		return
	if not _pending_objectives.is_empty():
		_activate_next_pending()
	else:
		_advance_stage()


func _advance_stage() -> void:
	stage_index += 1
	GameState.mission_stage = stage_index
	if stage_index >= mission.stages.size():
		return
	_activate_stage(stage_index)


func _run_action(action: Dictionary) -> void:
	match action.get("action", ""):
		"spawn_enemy":
			var spawner := get_tree().get_first_node_in_group("enemy_spawner")
			if spawner != null and spawner.has_method("spawn_type"):
				spawner.call("spawn_type", StringName(action.get("enemy_type", "")))
		"hint":
			Events.hint_requested.emit(action.get("text", ""), action.get("duration", 4.0))
		"mission_complete":
			_finish_mission()


func _finish_mission() -> void:
	Events.mission_completed.emit(mission.id)
	AudioManager.play_ui(&"mission_complete")
	mission_finished.emit(mission.id)


# --- Event-driven objective types --------------------------------------------

func _on_metal_burn_changed(allomancer: Node, metal: int, burning: bool) -> void:
	if not burning or not _is_player_owned(allomancer):
		return
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		if obj.get("type", "") == "use_metal" and int(obj.get("metal", -1)) == metal:
			complete_objective(obj)
	if not _hinted_metal_use and metal == Metal.Type.STEEL:
		_hinted_metal_use = true


func _on_allomantic_line_used(allomancer: Node, _target: Node, metal: int, _strength: float) -> void:
	if not _is_player_owned(allomancer):
		return
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		if obj.get("type", "") == "use_metal" and int(obj.get("metal", -1)) == metal:
			complete_objective(obj)


func _on_pickup_collected(kind: StringName, _amount: float) -> void:
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		var t: String = obj.get("type", "")
		if t == "collect" and StringName(obj.get("kind", "")) == kind:
			complete_objective(obj)
		elif t == "interact" and StringName(obj.get("interact_kind", "")) == kind:
			complete_objective(obj)


func _on_actor_died(actor: Node, _killer: Node) -> void:
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		if obj.get("type", "") == "defeat" and actor.is_in_group(obj.get("target_group", "enemy")):
			complete_objective(obj)
	if actor.is_in_group("enemy"):
		GameState.record_kill()


func _is_player_owned(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group("player"):
			return true
		n = n.get_parent()
	return false


# --- Waypoints (set from the pause-menu map) --------------------------------

func set_waypoint(pos: Vector3) -> void:
	waypoint = pos


func clear_waypoint() -> void:
	waypoint = Vector3.INF


## The position the HUD should point its objective marker at: the player's
## waypoint if set, else the first active objective's marker.
func current_marker_position() -> Vector3:
	if waypoint != Vector3.INF:
		return waypoint
	for id in _active_objectives:
		var obj: Dictionary = _active_objectives[id]
		var t: String = obj.get("type", "")
		if t in ["reach_marker", "escape", "interact"]:
			return _find_marker_position(obj.get("marker_group", "objective_point"), obj.get("marker_id", ""))
	return Vector3.INF


# --- Death / respawn ---------------------------------------------------------

func _on_player_died() -> void:
	GameState.record_death()
	await _fade_out()
	_respawn_player()
	await _fade_in()


func _respawn_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player is Node3D and GameState.last_checkpoint_id != &"":
		(player as Node3D).global_transform = GameState.last_checkpoint_transform
	if "health" in player and player.health != null:
		player.health.revive(GameState.checkpoint_health / maxf(player.health.max_health, 1.0))
	if "coins" in player:
		player.coins = GameState.checkpoint_coins
	if "vials" in player:
		player.vials = GameState.checkpoint_vials
	if "allomancer" in player and player.allomancer != null:
		for metal in GameState.checkpoint_reserves:
			if player.allomancer.has_method("add_reserve"):
				var current: float = player.allomancer.get_reserve(metal)
				player.allomancer.add_reserve(metal, GameState.checkpoint_reserves[metal] - current)


func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_layer.visible = false
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	get_tree().root.add_child.call_deferred(_fade_layer)


func _fade_out() -> void:
	_fade_layer.visible = true
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	await tw.finished


func _fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)
	await tw.finished
	_fade_layer.visible = false


func _clear_triggers() -> void:
	for a in _triggers:
		if is_instance_valid(a):
			a.queue_free()
	_triggers.clear()
