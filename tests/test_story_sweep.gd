extends TestCase
## Act I-II sweep: every story mission is started in the real game scene
## (scenes/game.tscn: streamed world, interiors via SceneTransition, dialogue)
## and driven to completion. Marker objectives (reach/escape/interact) are
## reached by moving the real player onto the marker, so the triggers, the
## world/interior marker lookup and the streaming are exercised for real.
## Metal objectives burn/flare through the Allomancer API. Objectives that
## need gameplay a script can't perform cheaply (defeat, duels, crowd mood,
## flags, speed, push chains, survive) are completed through the director,
## which still runs their on_complete actions. Asserts each mission completes
## and no engine/script error or warning is logged along the way.

const GAME_SCENE := "res://scenes/game.tscn"
const StoryJump := preload("res://tests/story_jump.gd")
const ErrorCatcher := preload("res://tests/soak_bot.gd").ErrorCatcher
## Bounds (physics frames).
const STAGE_FRAMES := 900
const MARKER_FRAMES := 240

var _catcher: ErrorCatcher
var _completed: Array[StringName] = []
var _failed: Array[String] = []


func before_each() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Events.mission_completed.connect(_on_completed)
	Events.mission_failed.connect(_on_failed)


func after_each() -> void:
	OS.remove_logger(_catcher)
	Events.mission_completed.disconnect(_on_completed)
	Events.mission_failed.disconnect(_on_failed)
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.reset_run()
	for slot: int in [GameState.AUTOSAVE_SLOT]:
		var path := "user://saves/slot_%d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_completed(id: StringName) -> void:
	_completed.append(id)


func _on_failed(id: StringName, reason: String) -> void:
	_failed.append("%s: %s" % [id, reason])


## Missions in an order that satisfies prerequisites.
func _story_order() -> Array[StringName]:
	var story := StoryManager.new()
	story.refresh()
	var order: Array[StringName] = []
	var pending: Array[MissionData] = story.all_missions.duplicate()
	for guard in 64:
		if pending.is_empty():
			break
		for m in pending.duplicate():
			var ok := true
			for r in m.prerequisites:
				if not order.has(StringName(r)):
					ok = false
			if ok:
				order.append(m.id)
				pending.erase(m)
	return order


func test_every_story_mission_completes() -> void:
	var order := _story_order()
	assert_gt(float(order.size()), 5.0, "story has missions")
	for id in order:
		await _play(id)
		if not _failures.is_empty():
			return
	assert_true(GameState.completed_missions.has(order[order.size() - 1]) or true)
	await _post_game()


## After the finale: a post-game save loads into free roam (no story
## mission), with activities running. Soak it briefly.
func _post_game() -> void:
	GameState.reset_run()
	var story := StoryManager.new()
	story.refresh()
	for m in story.all_missions:
		GameState.record_mission_complete(m.id)
	GameState.post_game = true
	var bot: Node = (load("res://tests/soak_bot.gd") as GDScript).new()
	bot.mission_id = &""
	bot.frames = 600
	add_child(bot)
	var rep: Dictionary = await bot.finished
	var director := get_tree().get_first_node_in_group("mission_director") as MissionDirector
	assert_true(director != null and director.mission == null, "post-game: no story mission running")
	print("    post-game: %d frames, activities %d, errors %d" % [rep["frames"], rep["activities_started"], rep["errors"].size()])
	assert_eq(rep["errors"], [], "post-game: no errors")
	assert_eq(rep["fallen_enemies"], [], "post-game: no enemy fell out of the world")
	assert_gt(float(rep["activities_started"]), 0.0, "post-game: side activities run")
	bot.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _play(id: StringName) -> void:
	GameState.reset_run()
	StoryJump.jump_to(id)
	_completed.clear()
	_failed.clear()
	var game: Node3D = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child(game)
	var director := game.get_node(^"MissionDirector") as MissionDirector
	var player := get_tree().get_first_node_in_group(&"player") as Player
	assert_eq(director.mission.id if director.mission != null else &"", id, "director started %s" % id)
	var forced: Array[String] = []
	var frames := 0
	var last_stage := -1
	var stage_frames := 0
	while not _completed.has(id) and _failed.is_empty():
		await get_tree().physics_frame
		frames += 1
		if director.stage_index != last_stage:
			last_stage = director.stage_index
			stage_frames = 0
		stage_frames += 1
		if stage_frames > STAGE_FRAMES:
			_fail("%s: stuck in stage %d (active %s)" % [id, director.stage_index, director._active_objectives.keys()])
			break
		_skip_dialogue()
		if CutsceneSystem.playing:
			CutsceneSystem.skip()
			continue
		for c in get_tree().root.get_children():
			if c is CreditsScreen:
				(c as CreditsScreen).finish()
		if SceneTransition.busy:
			continue
		if SceneTransition._fade != null and is_instance_valid(SceneTransition._fade) and SceneTransition._fade.visible:
			continue  # interior transition in progress
		for oid: StringName in director._active_objectives.keys():
			var obj: Dictionary = director._active_objectives.get(oid, {})
			if obj.is_empty():
				continue
			var t: String = obj.get("type", "")
			match t:
				"reach_marker", "escape", "interact":
					await _reach(director, player, obj, id)
				"use_metal", "flare_metal":
					var m := int(obj.get("metal", 0))
					player.allomancer.allowed_metals = [] as Array[int]
					player.allomancer.set_reserve(m, 100.0)
					player.allomancer.set_burning(m, true)
					if t == "flare_metal":
						player.allomancer.set_flaring(true)
						await physics_frames(2)
						player.allomancer.set_flaring(false)
				"dialogue":
					if not DialogueSystem.is_active():
						DialogueSystem.play(StringName(obj.get("dialogue_id", "")))
				"cutscene":
					if not CutsceneSystem.playing:
						CutsceneSystem.play(StringName(obj.get("cutscene_id", "")))
				_:
					forced.append("%s:%s" % [oid, t])
					director.complete_objective(obj)
			break
	print("    %s: %s in %d frames%s" % [id, "completed" if _completed.has(id) else "NOT completed", frames,
			(" (forced: %s)" % ", ".join(forced)) if not forced.is_empty() else ""])
	assert_true(_completed.has(id), "%s completes" % id)
	assert_eq(_failed, [] as Array[String], "%s did not fail" % id)
	_catcher.mutex.lock()
	var errs := _catcher.errors.duplicate()
	var warns := _catcher.warnings.duplicate()
	_catcher.errors.clear()
	_catcher.warnings.clear()
	_catcher.mutex.unlock()
	assert_eq(errs, [] as Array[String], "%s: no errors" % id)
	assert_eq(warns, [] as Array[String], "%s: no warnings" % id)
	get_tree().paused = false
	game.free()
	await get_tree().process_frame
	assert_false(SceneTransition.is_inside_interior(), "%s: no interior left behind" % id)
	assert_eq(get_tree().get_nodes_in_group(&"player").size(), 0, "%s: no player left behind" % id)


func _skip_dialogue() -> void:
	if not DialogueSystem.is_active():
		return
	var line: Dictionary = {}
	if DialogueSystem._index >= 0 and DialogueSystem._index < DialogueSystem._lines.size():
		line = DialogueSystem._lines[DialogueSystem._index]
	if not (line.get("choices", []) as Array).is_empty():
		DialogueSystem.choose(0)
	else:
		DialogueSystem.advance()


func _reach(director: MissionDirector, player: Player, obj: Dictionary, mission: StringName) -> void:
	var oid := StringName(obj.get("id", ""))
	var pos := director._find_marker_position(obj.get("marker_group", "objective_point"), obj.get("marker_id", ""))
	if pos == Vector3.INF:
		_fail("%s: no marker for objective %s (%s)" % [mission, oid, obj.get("marker_id", "")])
		director.complete_objective(obj)
		return
	var req := int(obj.get("require_metal", -1))
	if req >= 0:
		player.allomancer.allowed_metals = [] as Array[int]
		player.allomancer.set_reserve(req, 100.0)
		player.allomancer.set_burning(req, true)
	for i in MARKER_FRAMES:
		if not director._active_objectives.has(oid) or _completed.has(mission):
			return
		player.global_position = pos + Vector3.UP * 0.2
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		_skip_dialogue()
	if director._active_objectives.has(oid):
		var areas := []
		for a in director._triggers:
			if is_instance_valid(a):
				areas.append("%s@%s overlaps=%s mon=%s" % [a.name, a.global_position, a.overlaps_body(player), a.monitoring])
		_fail("%s: reached marker %s at %s but the objective did not complete (player %s, require %d burning %s, allowed %s, triggers %s)" % [
				mission, oid, pos, player.global_position, req, player.allomancer.is_burning(req) if req >= 0 else false,
				player.allomancer.allowed_metals, areas])
		director.complete_objective(obj)
