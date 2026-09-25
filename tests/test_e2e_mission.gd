extends TestCase
## End-to-end: loads the real streamed game scene (scenes/game.tscn) and drives
## the real player through "Mistwalk to Keep Venture": burns steel through the
## Allomancer API, travels to every objective marker in order (letting chunks
## stream in), collects the ledger, checks the Inquisitor spawns exactly once,
## and reaches extraction. Also covers death -> checkpoint respawn and a
## mid-mission save/load round trip. Every wait is bounded; no fixed sleeps.

const GAME_SCENE := "res://scenes/game.tscn"
const ROUTE: Array[StringName] = [&"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1", &"cp_2", &"cp_3",
		&"keep_courtyard", &"ledger", &"extraction"]
## Physics frames allowed for a unit to stream in / an objective to trigger.
const STREAM_WAIT := 1200
const TRIGGER_WAIT := 240

var game: Node3D
var world: LuthadelWorld
var player: Player
var director: MissionDirector
var _completed_missions: Array[StringName] = []
var _events: Array[String] = []


func before_each() -> void:
	GameState.reset_run()
	_completed_missions.clear()
	_events.clear()
	Events.mission_completed.connect(_on_mission_completed)
	Events.objective_updated.connect(_on_objective_updated)


func after_each() -> void:
	Events.mission_completed.disconnect(_on_mission_completed)
	Events.objective_updated.disconnect(_on_objective_updated)
	if is_instance_valid(game):
		game.free()
	game = null
	Engine.time_scale = 1.0
	GameState.reset_run()
	for slot in [7]:
		var path := "user://saves/slot_%d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_mission_completed(id: StringName) -> void:
	_completed_missions.append(id)


func _on_objective_updated(id: StringName, _text: String, done: bool) -> void:
	if done:
		_events.append(String(id))


# --- Helpers ---------------------------------------------------------------

func _start_game() -> void:
	game = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child(game)
	world = game.get_node(^"World") as LuthadelWorld
	player = get_tree().get_first_node_in_group(&"player") as Player
	director = game.get_node(^"MissionDirector") as MissionDirector
	await physics_frames(2)


## Waits up to `max_frames` physics frames for `cond` to become true.
func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _marker(id: StringName) -> Vector3:
	for e: Dictionary in world.get_marker_data(&"objective_point"):
		if StringName(str((e["meta"] as Dictionary).get("objective_id", ""))) == id:
			return e["position"]
	return Vector3.INF


func _done(id: StringName) -> bool:
	return GameState.completed_objectives.has(id)


## Teleports the player onto `pos`, waits for the ground there to stream in
## and for the player to settle on it.
func _travel_to(pos: Vector3) -> bool:
	player.global_position = pos + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	player.camera_rig.snap()
	var loaded := await _wait_until(func() -> bool: return world.is_area_loaded(pos), STREAM_WAIT)
	if not loaded:
		return false
	return await _wait_until(func() -> bool: return player.is_on_floor(), TRIGGER_WAIT)


func _reach(id: StringName) -> void:
	var pos := _marker(id)
	assert_true(pos != Vector3.INF, "marker %s exists" % id)
	if pos == Vector3.INF:
		return
	var arrived := await _travel_to(pos)
	assert_true(arrived, "player arrived and stands at %s %s (at %s)" % [id, pos, player.global_position])
	var ok := await _wait_until(_done.bind(id), TRIGGER_WAIT)
	assert_true(ok, "objective %s completed (player at %s)" % [id, player.global_position])


func _inquisitors() -> Array[Node]:
	var out: Array[Node] = []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if e is Inquisitor and not (e as Node).is_queued_for_deletion():
			out.append(e)
	return out


func _burn_steel() -> void:
	player.allomancer.add_reserve(Metal.Type.STEEL, 100.0)
	assert_true(player.allomancer.set_burning(Metal.Type.STEEL, true), "steel burns")
	assert_true(_done(&"learn_steel"), "learn_steel completes when steel burns")
	assert_gt(player.allomancer.lines_in_range().size(), 0, "steel lines visible from the spawn roof")


# --- Tests -----------------------------------------------------------------

func test_full_mission_playthrough() -> void:
	await _start_game()
	assert_true(player != null and world != null and director != null, "game assembled")
	assert_true(player.is_on_floor() or await _wait_until(func() -> bool: return player.is_on_floor(), 120),
		"player spawns on solid ground")
	assert_true(_done(&"kelsier_intro"), "intro hint shown")
	_burn_steel()
	for id in ROUTE:
		if id == &"extraction":
			var inqs := _inquisitors()
			assert_eq(inqs.size(), 1, "exactly one Inquisitor after the ledger")
		await _reach(id)
		if not _failures.is_empty():
			return
		if id == &"ledger":
			await physics_frames(3)
		if id == &"cp_3":
			# cp_3's chunk streams in after startup; its checkpoint must still register.
			assert_eq(GameState.last_checkpoint_id, &"cp_3", "streamed-in checkpoint recorded")
	assert_eq(_completed_missions, [&"mistwalk_to_keep_venture"] as Array[StringName], "mission_completed fired once")
	assert_eq(_inquisitors().size(), 1, "still exactly one Inquisitor")
	assert_eq(_events.count("ledger"), 1, "ledger completed once")
	assert_eq(GameState.mission_stage, director.mission.stages.size(), "all stages done")


func test_death_respawns_at_last_checkpoint() -> void:
	await _start_game()
	_burn_steel()
	for id: StringName in [&"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1", &"cp_2"]:
		await _reach(id)
	assert_eq(GameState.last_checkpoint_id, &"cp_2", "cp_2 checkpoint recorded")
	var cp_pos := GameState.last_checkpoint_transform.origin
	# Wander off (to the keep's courtyard, which is not a checkpoint), then die.
	assert_true(await _travel_to(_marker(&"keep_courtyard")), "wandered off")
	assert_false(_done(&"keep_courtyard"), "courtyard objective is not active yet")
	var coins_at_cp := GameState.checkpoint_coins
	player.coins = 0
	player.health.take_damage(100000.0, null, &"blunt")
	assert_true(player.dead, "player died")
	var respawned := await _wait_until(func() -> bool: return not player.dead, 600)
	assert_true(respawned, "player respawned")
	assert_lt(player.global_position.distance_to(cp_pos), 3.0, "respawned at the cp_2 checkpoint")
	assert_eq(player.coins, coins_at_cp, "coins restored from the checkpoint snapshot")
	assert_almost(Engine.time_scale, 1.0, 0.001, "time scale normal")
	assert_false(player.health.dead, "health revived")
	# Control restored: walking input moves the player.
	await _wait_until(func() -> bool: return player.is_on_floor(), 120)
	var p0 := player.global_position
	Input.action_press(&"move_forward")
	await physics_frames(20)
	Input.action_release(&"move_forward")
	assert_gt(Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length(), 0.5,
		"player moves after respawn")
	# The mission still continues from where it was.
	await _reach(&"cp_3")


func test_save_load_round_trip_mid_mission() -> void:
	await _start_game()
	_burn_steel()
	for id: StringName in [&"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1", &"cp_2"]:
		await _reach(id)
	var saved_stage := GameState.mission_stage
	var saved_done := GameState.completed_objectives.duplicate()
	assert_true(GameState.save_game(7), "saved")
	# Progress further, then load the save.
	await _reach(&"cp_3")
	await _reach(&"keep_courtyard")
	assert_true(_done(&"keep_courtyard"))
	assert_true(GameState.load_game(7), "loaded")
	await physics_frames(3)
	assert_eq(GameState.mission_stage, saved_stage, "stage restored")
	assert_eq(GameState.completed_objectives, saved_done, "objectives restored")
	assert_eq(director.stage_index, saved_stage, "director resynced to the saved stage")
	assert_true(director._active_objectives.has(&"cp_3"), "cp_3 is the active objective again")
	assert_lt(player.global_position.distance_to(GameState.last_checkpoint_transform.origin), 3.0,
		"player moved back to the saved checkpoint")
	# And the mission can be finished from the loaded state.
	for id: StringName in [&"cp_3", &"keep_courtyard", &"ledger", &"extraction"]:
		await _reach(id)
	assert_eq(_completed_missions.size(), 1, "mission completes after loading")
	assert_eq(_inquisitors().size(), 1, "one Inquisitor after loading")
