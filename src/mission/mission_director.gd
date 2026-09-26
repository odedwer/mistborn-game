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
## Objectives whose marker could not be found yet (typically because the
## stage's `enter_interior`/`switch_interior` is still fading in and the
## scene holding the marker isn't instantiated). Retried from `_process` and
## on `Events.interior_entered` until the marker appears.
var _unresolved_triggers: Array[Dictionary] = []
var _retry_timer := 0.0
## Inside an interior, deaths respawn here rather than at the open-world
## checkpoint: the interior's spawn marker, then the latest `reach_marker`/
## `escape` objective the player reached in it (a mid-scene checkpoint).
var _interior_respawn: Vector3 = Vector3.INF
var _hinted_metal_use := false
## `chain_pushes` objective id -> {last: float (ticks sec), count: int}.
var _chain_state: Dictionary = {}
## `survive` objective id -> seconds of `_process` time accumulated so far.
var _survive_start: Dictionary = {}
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
	Events.metal_flare_changed.connect(_on_metal_flare_changed)
	Events.allomantic_line_used.connect(_on_allomantic_line_used)
	Events.pickup_collected.connect(_on_pickup_collected)
	Events.actor_died.connect(_on_actor_died)
	GameState.load_completed.connect(_on_game_loaded)
	# Checkpoint areas stream in with their chunks: connect them as they load.
	var world := _find_world_node()
	if world != null and world.has_signal(&"unit_loaded"):
		world.connect(&"unit_loaded", _on_unit_loaded)
	Events.dialogue_finished.connect(_on_dialogue_finished)
	Events.dialogue_flag_set.connect(_on_dialogue_flag_set)
	Events.cutscene_finished.connect(_on_cutscene_finished)
	Events.alert_level_changed.connect(_on_alert_level_changed)
	Events.interior_entered.connect(_on_interior_entered)
	Events.interior_exited.connect(func() -> void: _interior_respawn = Vector3.INF)
	_build_fade_layer()
	_start_or_resume()
	if GameState.last_checkpoint_id != &"":
		_restore_checkpoint_snapshot(get_tree().get_first_node_in_group("player"))
	_restore_saved_interior.call_deferred()


func _exit_tree() -> void:
	_clear_triggers()
	Engine.time_scale = 1.0


func _on_unit_loaded(_key: String) -> void:
	_connect_checkpoints()


## A save was loaded while playing: resync the mission to the loaded
## progress and put the player back at the saved checkpoint.
func _on_game_loaded(_slot: int) -> void:
	# Leave any interior first: the loaded stage re-enters one if it needs to.
	if SceneTransition.is_inside_interior():
		await SceneTransition.exit_interior()
	if not is_inside_tree():
		return
	_pending_objectives.clear()
	_active_objectives.clear()
	_clear_triggers()
	_start_or_resume()
	respawn_at_checkpoint()
	# Save anywhere: resume at the exact saved position rather than the
	# checkpoint, with the ground there streamed in first.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if GameState.has_open_world_position and player != null:
		var target := GameState.open_world_position
		var world := _find_world_node()
		if world != null and "streamer" in world and world.streamer != null \
				and not world.streamer.is_area_loaded(target.origin):
			world.streamer.load_now(target.origin, world.streamer.load_radius)
		player.global_transform = Transform3D(Basis.IDENTITY, target.origin)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		if "camera_rig" in player and player.camera_rig != null:
			player.camera_rig.snap()
	_restore_saved_interior()


## Saved inside an interior: go back in (the stage's own `enter_interior`,
## if any, has already started and makes this a no-op).
func _restore_saved_interior() -> void:
	if GameState.interior_scene != "" and not SceneTransition.is_inside_interior() and not SceneTransition.busy:
		SceneTransition.enter_interior(GameState.interior_scene)


## Polls `reach_speed` objectives (e.g. "hit a coin-jump chain at 12 m/s");
## everything else here is event-driven, so this stays a cheap no-op most of
## the time.
func _process(delta: float) -> void:
	if not _unresolved_triggers.is_empty():
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = 0.25
			_retry_unresolved_triggers()
	if _active_objectives.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	if Engine.get_process_frames() % 6 == 0:
		_recheck_gated_triggers(player)
	var speed := 0.0
	if player is CharacterBody3D:
		speed = (player as CharacterBody3D).velocity.length()
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		var t: String = obj.get("type", "")
		if t == "reach_speed" and player is CharacterBody3D and speed >= float(obj.get("min_speed", 10.0)):
			complete_objective(obj)
		elif t == "crowd_mood" and _crowd_mood_reached(obj):
			complete_objective(obj)
		elif t == "survive":
			var elapsed: float = float(_survive_start.get(id, 0.0)) + delta
			_survive_start[id] = elapsed
			if elapsed >= float(obj.get("duration", 10.0)):
				_survive_start.erase(id)
				complete_objective(obj)


func _start_or_resume() -> void:
	# Post-game free roam (after "The Lord Ruler" and the credits): no story
	# mission runs; the open world and every side activity stay available.
	if GameState.post_game:
		mission = null
		return
	mission = story.get_mission(GameState.mission_id)
	# A save made on the mission-complete screen still names the mission
	# just finished: move on to the next one in the chain instead of
	# replaying it.
	if mission != null and GameState.completed_missions.has(mission.id):
		mission = story.next_story_mission(GameState.completed_missions)
		GameState.mission_stage = 0
		GameState.last_checkpoint_id = &""
		if mission == null:
			GameState.post_game = true
			return
	if mission == null:
		mission = story.next_story_mission(GameState.completed_missions)
	if mission == null and not story.all_missions.is_empty():
		mission = story.all_missions[0]
	if mission == null:
		push_warning("MissionDirector: no mission data found under res://src/mission/missions/")
		return
	GameState.mission_id = mission.id
	stage_index = clampi(GameState.mission_stage, 0, maxi(mission.stages.size() - 1, 0))
	_activate_stage(stage_index)


## Starts the next story mission in place (the mission-complete screen's
## "Continue" button). Returns false once the story is over (post-game).
func start_next_mission() -> bool:
	_clear_triggers()
	_active_objectives.clear()
	_pending_objectives.clear()
	GameState.mission_stage = 0
	_start_or_resume()
	return mission != null


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
	if mission == null:
		return
	_clear_triggers()
	_active_objectives.clear()
	_survive_start.clear()
	if index >= mission.stages.size():
		return
	var stage: Dictionary = mission.stages[index]
	stage_advanced.emit(index, stage.get("label", ""))
	_ensure_stage_interior(stage)
	# Stage-level setup actions (locking/unlocking metals, starting a cutscene
	# or dialogue) run once, before the stage's own objectives activate.
	for action: Dictionary in stage.get("on_enter", []):
		_run_action(action)
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


## Optional stage key `"interior"` (Act III): the mission space the stage
## takes place in. When a save resumes mid-mission, the stage that would
## normally have been entered by an earlier objective's `switch_interior`
## still puts the player in the right place. Skipped when the stage's own
## `on_enter` handles the transition, or one is already under way.
func _ensure_stage_interior(stage: Dictionary) -> void:
	var path := String(stage.get("interior", ""))
	if path == "" or SceneTransition.busy:
		return
	for action: Dictionary in stage.get("on_enter", []):
		if String(action.get("action", "")) in ["enter_interior", "switch_interior", "exit_interior"]:
			return
	var current: Node = SceneTransition.current_interior()
	if current != null and current.scene_file_path == path:
		return
	SceneTransition.switch_interior(path)


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
		"use_metal", "flare_metal":
			# Driven by Events, but the metal may already be burning (burned
			# during an earlier beat): that must count, or the stage soft-locks
			# until the player happens to toggle it off and on.
			_check_metal_already_active.call_deferred(obj)
		"defeat", "defeat_in_duel", "collect", "dialogue", "reach_speed", "chain_pushes", "push_target", "cutscene":
			pass # driven by Events, see the handlers below.
		"crowd_mood", "survive":
			pass # polled in _process, see above.
		"flag_count":
			_check_flag_count(obj)


func _check_metal_already_active(obj: Dictionary) -> void:
	if not _active_objectives.has(StringName(obj.get("id", ""))):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("allomancer" in player) or player.allomancer == null:
		return
	var al: Allomancer = player.allomancer
	var metal := int(obj.get("metal", -1))
	var ok := al.is_burning(metal)
	if obj.get("type", "") == "flare_metal":
		ok = ok and al.is_flaring(metal)
	if ok:
		complete_objective(obj)


func _spawn_trigger_for(obj: Dictionary) -> void:
	var pos := _find_marker_position(obj.get("marker_group", "objective_point"), obj.get("marker_id", ""))
	if pos == Vector3.INF:
		if not _unresolved_triggers.has(obj):
			_unresolved_triggers.append(obj)
		return
	var area := Area3D.new()
	area.name = "Objective_%s" % obj.get("id", "")
	area.collision_layer = 0
	area.collision_mask = 1 << 1  # "player" physics layer
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	area.add_child(shape)
	# Top-level so it ignores this Node's lack of a transform; freed with the
	# director when the game scene goes away.
	area.top_level = true
	add_child(area)
	area.global_position = pos
	area.body_entered.connect(_on_objective_trigger_entered.bind(obj))
	area.set_meta(&"objective", obj)
	_triggers.append(area)
	# Mark the mission's opening objective with a subtle beacon (story
	# gating: tells the player where to go before they've picked up the
	# invisible trigger radius), reusing the side-activity beacon visual.
	if stage_index == 0:
		var beacon := ActivityBeacon.new()
		beacon.beacon_color = Color(0.55, 0.78, 0.95)
		area.add_child(beacon)


func _on_interior_entered(_path: String) -> void:
	_interior_respawn = Vector3.INF
	var spawn := get_tree().get_first_node_in_group(&"interior_spawn") as Node3D
	var interior: Node = SceneTransition.current_interior()
	if interior != null:
		for n in get_tree().get_nodes_in_group(&"interior_spawn"):
			if interior.is_ancestor_of(n):
				spawn = n as Node3D
	if spawn != null:
		_interior_respawn = spawn.global_position
	_retry_unresolved_triggers()


func _retry_unresolved_triggers() -> void:
	var pending := _unresolved_triggers.duplicate()
	_unresolved_triggers.clear()
	for obj: Dictionary in pending:
		if _active_objectives.has(StringName(obj.get("id", ""))):
			_spawn_trigger_for(obj)


func _on_objective_trigger_entered(body: Node, obj: Dictionary) -> void:
	if not body.is_in_group("player"):
		return
	# Optional gate (the ball's eavesdropping): the objective only completes
	# while a given metal is burning, e.g. tin to make out a hushed rumor.
	var req_metal := int(obj.get("require_metal", -1))
	if req_metal >= 0:
		var allomancer := _find_allomancer(body)
		if allomancer == null or not allomancer.call("is_burning", req_metal):
			Events.hint_requested.emit(obj.get("hint_locked", "Burn %s to make it out." % Metal.NAMES.get(req_metal, "that metal")), 3.0)
			return
	# Deferred: completing an objective can spawn enemies and triggers, which
	# is not allowed from inside a physics in/out callback.
	_complete_from_trigger.call_deferred(obj, body)


## A metal-gated trigger (eavesdrop with tin) only sees the player *enter*;
## if they were already standing in it when they started burning the metal
## (e.g. spawned inside it), re-check while they stay inside.
func _recheck_gated_triggers(player: Node) -> void:
	if player == null or not (player is PhysicsBody3D):
		return
	for area in _triggers:
		if not is_instance_valid(area) or not area.monitoring:
			continue
		var obj: Dictionary = area.get_meta(&"objective", {})
		var req := int(obj.get("require_metal", -1))
		if req < 0 or not _active_objectives.has(StringName(obj.get("id", ""))):
			continue
		var al := _find_allomancer(player)
		if al != null and al.call("is_burning", req) and area.overlaps_body(player):
			_complete_from_trigger(obj, player)


func _complete_from_trigger(obj: Dictionary, body: Node = null) -> void:
	if not _active_objectives.has(StringName(obj.get("id", ""))):
		return
	if obj.get("type", "") == "interact":
		Events.pickup_collected.emit(StringName(obj.get("interact_kind", "")), 1.0)
	elif SceneTransition.is_inside_interior() and is_instance_valid(body) and body is Node3D:
		_interior_respawn = (body as Node3D).global_position
	complete_objective(obj)


func _find_allomancer(player: Node) -> Node:
	if "allomancer" in player:
		return player.allomancer
	return player.get_node_or_null("Allomancer")


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
	_unresolved_triggers.erase(obj)
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
	if mission == null:
		return
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
				_spawn_enemy(spawner, StringName(action.get("enemy_type", "")))
		"hint":
			Events.hint_requested.emit(action.get("text", ""), action.get("duration", 4.0))
		"mission_complete":
			_finish_mission()
		"set_allowed_metals":
			_set_allowed_metals(action.get("metals", []))
		"start_dialogue":
			DialogueSystem.play(StringName(action.get("dialogue_id", "")))
		"start_cutscene":
			CutsceneSystem.play(StringName(action.get("cutscene_id", "")))
		"enter_interior":
			SceneTransition.enter_interior(String(action.get("scene", "")))
		"exit_interior":
			SceneTransition.exit_interior()
		"set_flag":
			GameState.set_dialogue_flag(StringName(action.get("flag", "")), action.get("value", true))
		"switch_interior":
			SceneTransition.switch_interior(String(action.get("scene", "")))
		"call_group":
			_call_group(action)
		"drain_metals":
			_drain_metals(action.get("metals", []))
		"grant_metals":
			_grant_metals(action.get("metals", []), float(action.get("amount", 100.0)))
		"roll_credits":
			_roll_credits()


## `call_group` action. When the same `on_enter` just started an interior
## transition, the target scene doesn't exist yet: wait for it to load.
func _call_group(action: Dictionary) -> void:
	if SceneTransition.busy:
		await Events.interior_entered
	var call_args: Array = [StringName(action.get("group", "")), StringName(action.get("method", ""))]
	call_args.append_array(action.get("args", []))
	get_tree().callv(&"call_group", call_args)


## Act III ("Into Kredik Shaw" capture / "The Pits Beneath the Palace"):
## empties the player's reserves of `metals` (all metals when empty) and stops
## them burning — the Inquisitors made sure Vin woke with nothing to burn.
func _drain_metals(metals: Array) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("allomancer" in player) or player.allomancer == null:
		return
	var list: Array = metals if not metals.is_empty() else Metal.Type.values()
	for m in list:
		player.allomancer.set_burning(int(m), false)
		player.allomancer.set_reserve(int(m), 0.0)
	if "vials" in player:
		player.vials = 0


## Tops the player's reserves of `metals` (all when empty) up to `amount`
## (a crewmate's vial, a story beat that hands Vin her metals back).
func _grant_metals(metals: Array, amount: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("allomancer" in player) or player.allomancer == null:
		return
	var list: Array = metals if not metals.is_empty() else Metal.Type.values()
	for m in list:
		if int(m) == Metal.Type.ATIUM or int(m) == Metal.Type.DURALUMIN:
			if metals.is_empty():
				continue  # "all" means the ordinary metals
		player.allomancer.set_reserve(int(m), maxf(player.allomancer.get_reserve(int(m)), amount))


## The finale: records the last story mission as done, then plays the
## credits (`CreditsScreen`); once they end the game drops into post-game
## free roam instead of the usual mission-complete screen.
func _roll_credits() -> void:
	var final_id: StringName = mission.id if mission != null else &""
	GameState.post_game = true
	if final_id != &"":
		GameState.record_mission_complete(final_id)
	var credits := CreditsScreen.new()
	get_tree().root.add_child(credits)
	credits.finished.connect(_on_credits_finished.bind(final_id))
	credits.play()


func _on_credits_finished(final_id: StringName) -> void:
	# Post-game free roam happens in the open world: leave the finale's
	# interior (back to where the Act III chain of interiors began).
	if SceneTransition.is_inside_interior():
		SceneTransition.exit_interior()
	mission = null
	_active_objectives.clear()
	_pending_objectives.clear()
	_clear_triggers()
	if final_id != &"":
		# `MissionComplete` skips its screen in post-game; `GameState`
		# still records + autosaves off this signal.
		Events.mission_completed.emit(final_id)
		mission_finished.emit(final_id)
	Events.post_game_started.emit(final_id)


## Spawns `etype` at its world marker when one is loaded (the Inquisitor at
## Keep Venture); otherwise (a scripted opponent like Ham in a lesson, where
## the city has no marker of that type nearby) in front of the player.
func _spawn_enemy(spawner: Node, etype: StringName) -> Node:
	if not spawner.has_method("has_marker_for") or spawner.call("has_marker_for", etype):
		return spawner.call("spawn_type", etype)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var parent: Node = player.get_parent() if player != null else null
	if player == null or parent == null:
		push_warning("MissionDirector: nowhere to spawn '%s'" % etype)
		return null
	var fwd := -player.global_basis.z
	if "camera_rig" in player and player.camera_rig != null:
		fwd = -(player.camera_rig as PlayerCamera).yaw_basis().z
	var marker := Marker3D.new()
	parent.add_child(marker)
	marker.global_position = player.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 8.0 + Vector3.UP * 0.5
	marker.look_at(player.global_position + Vector3.UP * 0.5, Vector3.UP, true)
	var enemy: Node = spawner.call("spawn_type", etype, marker)
	marker.queue_free()
	return enemy


## Restricts the player's `Allomancer` to `metals` (a list of `Metal.Type`
## ints); an empty list unlocks every metal again. Drives the pewter-only
## tutorial opening and any story-mandated allomancy lock/unlock.
func _set_allowed_metals(metals: Array) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("allomancer" in player) or player.allomancer == null:
		return
	var arr: Array[int] = []
	for m in metals:
		arr.append(int(m))
	player.allomancer.allowed_metals = arr


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


func _on_allomantic_line_used(allomancer: Node, target: Node, metal: int, _strength: float) -> void:
	if not _is_player_owned(allomancer):
		return
	var target_obj_id := ""
	if target != null and is_instance_valid(target):
		target_obj_id = str(target.get_meta("objective_id", ""))
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		var t: String = obj.get("type", "")
		if t == "use_metal" and int(obj.get("metal", -1)) == metal:
			complete_objective(obj)
		elif t == "chain_pushes" and int(obj.get("metal", Metal.Type.STEEL)) == metal:
			_tick_chain(id, obj)
		elif t == "push_target" and target_obj_id != "" and target_obj_id == str(obj.get("marker_id", "")):
			complete_objective(obj)


## Counts distinct Pushes/Pulls (debounced so one held button-press is one
## count, not one per physics frame) toward a `chain_pushes` objective, e.g.
## "chain 3 pushes within 1.5s of each other" for the coin-jump lesson.
func _tick_chain(id: StringName, obj: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var st: Dictionary = _chain_state.get(id, {"last": -999.0, "count": 0})
	var max_gap := float(obj.get("max_gap", 1.5))
	var debounce := 0.2
	var last: float = st["last"]
	if now - last > max_gap:
		st["count"] = 0
	if now - last > debounce:
		st["count"] = int(st["count"]) + 1
	st["last"] = now
	_chain_state[id] = st
	if int(st["count"]) >= int(obj.get("count", 3)):
		_chain_state.erase(id)
		complete_objective(obj)


## `flare_metal` objective type: complete the first time the player flares
## `metal` (used for the pewter-flare lesson).
func _on_metal_flare_changed(allomancer: Node, metal: int, flaring: bool) -> void:
	if not flaring or not _is_player_owned(allomancer):
		return
	for id in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[id]
		if obj.get("type", "") == "flare_metal" and int(obj.get("metal", -1)) == metal:
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
		var t: String = obj.get("type", "")
		if (t == "defeat" or t == "defeat_in_duel") and actor.is_in_group(obj.get("target_group", "enemy")):
			complete_objective(obj)
	if actor.is_in_group("enemy"):
		GameState.record_kill()


func _on_dialogue_finished(id: StringName) -> void:
	for oid in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[oid]
		if obj.get("type", "") == "dialogue" and StringName(obj.get("dialogue_id", "")) == id:
			complete_objective(obj)


## `cutscene` objective (Act III): complete when `Events.cutscene_finished`
## fires for `cutscene_id` (usually started by the stage's `on_enter`).
func _on_cutscene_finished(id: StringName) -> void:
	for oid in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[oid]
		if obj.get("type", "") == "cutscene" and StringName(obj.get("cutscene_id", "")) == id:
			complete_objective(obj)


func _on_dialogue_flag_set(_flag: StringName, _value: Variant) -> void:
	for oid in _active_objectives.keys():
		var obj: Dictionary = _active_objectives[oid]
		if obj.get("type", "") == "flag_count":
			_check_flag_count(obj)


## The Canton of Resource heist's alarm state: a stage may carry
## `"fail_conditions"` (see `MissionData`) checked against the district-wide
## alert level. Exceeding a condition's `max` fails the mission — matches how
## `SuspicionMeter` fails "Lady Valette" on detection, but driven by
## `AlertDirector`/`EnemyBase` instead of a bespoke meter.
func _on_alert_level_changed(level: int) -> void:
	if mission == null or stage_index >= mission.stages.size():
		return
	var stage: Dictionary = mission.stages[stage_index]
	for cond: Dictionary in stage.get("fail_conditions", []):
		var kind := String(cond.get("type", ""))
		if kind == "alert_level" and level > int(cond.get("max", 2)):
			_fail_for(cond, "alert_level")
			return
		# One guard clocking you can still be handled quietly (a takedown
		# before they shout); the heist only fails once several are hostile
		# at once — the alarm has genuinely spread.
		if kind == "combat_count" and level >= 2 and _enemies_in_combat() > int(cond.get("max", 1)):
			_fail_for(cond, "combat_count")
			return


func _fail_for(cond: Dictionary, reason: String) -> void:
	Events.hint_requested.emit(cond.get("reason", "The alarm is raised!"), 4.0)
	Events.mission_failed.emit(mission.id, reason)


func _enemies_in_combat() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if "state" in e and int(e.state) == EnemyBase.State.COMBAT:
			n += 1
	return n


## "Talk to 3 nobles"-style objective: complete once `count` of `flags` are
## set in `GameState.dialogue_flags`.
func _check_flag_count(obj: Dictionary) -> void:
	var flags: Array = obj.get("flags", [])
	var need := int(obj.get("count", flags.size()))
	var have := 0
	for f in flags:
		if GameState.has_dialogue_flag(StringName(f)):
			have += 1
	if have >= need:
		complete_objective(obj)


## `crowd_mood` objective: true once the first node in group `mood_group`
## (default `"crowd_mood"`, see `CrowdMoodMeter`) has crossed `target` in the
## requested `direction`.
func _crowd_mood_reached(obj: Dictionary) -> bool:
	var group := StringName(obj.get("mood_group", "crowd_mood"))
	var meter := get_tree().get_first_node_in_group(group)
	if meter == null or not ("mood" in meter):
		return false
	var mood: float = meter.mood
	var target := float(obj.get("target", 50.0))
	if String(obj.get("direction", "below")) == "above":
		return mood >= target
	return mood <= target


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
	if not is_inside_tree():
		return
	_respawn_player()
	await _fade_in()


## Puts the player back at the last checkpoint (or the spawn) with the
## checkpoint's health, coins, vials and reserves.
func respawn_at_checkpoint() -> void:
	_respawn_player()


func _respawn_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var xform := (player as Node3D).global_transform
	if SceneTransition.is_inside_interior() and _interior_respawn != Vector3.INF:
		xform = Transform3D(Basis.IDENTITY, _interior_respawn + Vector3.UP * 0.2)
	elif GameState.last_checkpoint_id != &"":
		xform = GameState.last_checkpoint_transform
	else:
		var spawn := get_tree().get_first_node_in_group("player_spawn") as Node3D
		if spawn != null:
			xform = spawn.global_transform
	# player.respawn() clears the dead state, physics and death animation;
	# health is then set to the checkpoint snapshot below.
	if player.has_method("respawn"):
		player.call("respawn", xform)
	else:
		(player as Node3D).global_transform = xform
	_restore_checkpoint_snapshot(player)


func _restore_checkpoint_snapshot(player: Node) -> void:
	if player == null:
		return
	if "health" in player and player.health != null:
		player.health.revive(clampf(GameState.checkpoint_health / maxf(player.health.max_health, 1.0), 0.01, 1.0))
		Events.player_health_changed.emit(player.health.current, player.health.max_health)
	if "coins" in player:
		player.coins = GameState.checkpoint_coins
	if "vials" in player:
		player.vials = GameState.checkpoint_vials
	if "allomancer" in player and player.allomancer != null:
		for metal in GameState.checkpoint_reserves:
			if player.allomancer.has_method("add_reserve"):
				var current: float = player.allomancer.get_reserve(metal)
				player.allomancer.add_reserve(metal, GameState.checkpoint_reserves[metal] - current)
	if player.has_method("_emit_inventory"):
		player.call("_emit_inventory")


func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_layer.visible = false
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


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
