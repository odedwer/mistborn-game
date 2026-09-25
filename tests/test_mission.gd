extends TestCase
## MissionDirector stage progression, driven by simulated Events.

var _director: MissionDirector


func before_each() -> void:
	GameState.reset_run()
	_director = MissionDirector.new()
	add_child(_director)


func after_each() -> void:
	_director.queue_free()


func test_loads_mistwalk_mission() -> void:
	assert_true(_director.mission != null, "mission data loaded")
	assert_eq(_director.mission.id, &"mistwalk_to_keep_venture")
	assert_eq(_director.stage_index, 0)


func test_cutscene_hint_completes_immediately() -> void:
	assert_true(GameState.completed_objectives.has(&"kelsier_intro"))


func test_use_metal_objective_completes_on_burn() -> void:
	assert_false(GameState.completed_objectives.has(&"learn_steel"))
	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	add_child(fake_player)
	var fake_allomancer := Node.new()
	fake_player.add_child(fake_allomancer)
	Events.metal_burn_changed.emit(fake_allomancer, Metal.Type.STEEL, true)
	assert_true(GameState.completed_objectives.has(&"learn_steel"))
	fake_player.queue_free()


func test_stage_objectives_activate_one_at_a_time() -> void:
	# Stage 0 is sequential: after the intro hint only "learn_steel" is active;
	# the rooftop markers wait until steel has been burned.
	assert_true(_director._active_objectives.has(&"learn_steel"))
	assert_false(_director._active_objectives.has(&"rooftop_lesson_1"))
	_director.complete_objective(_director._active_objectives[&"learn_steel"])
	assert_true(_director._active_objectives.has(&"rooftop_lesson_1"))
	assert_false(_director._active_objectives.has(&"rooftop_lesson_2"))


func test_completing_all_stage_objectives_advances_stage() -> void:
	# Manually complete every objective of stage 0 (skipping trigger geometry,
	# which needs real markers) and confirm the director moves to stage 1.
	for obj: Dictionary in _director.mission.stages[0].get("objectives", []):
		_director.complete_objective(obj)
	assert_eq(_director.stage_index, 1)
	assert_eq(GameState.mission_stage, 1)


func test_ledger_objective_spawns_inquisitor_and_advances() -> void:
	var spawner := Node.new()
	spawner.add_to_group("enemy_spawner")
	# Attach a minimal script with spawn_type so we can observe the call.
	var src := "extends Node\nvar calls: Array = []\nfunc spawn_type(t):\n\tcalls.append(t)\n"
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	spawner.set_script(script)
	add_child(spawner)

	for i in [0, 1]:
		for obj: Dictionary in _director.mission.stages[i].get("objectives", []):
			_director.complete_objective(obj)
	# Now at stage 2 ("the_courtyard"): complete its objectives.
	for obj: Dictionary in _director.mission.stages[2].get("objectives", []):
		_director.complete_objective(obj)

	assert_eq(_director.stage_index, 3)
	assert_true(spawner.calls.has(&"inquisitor"))
	spawner.queue_free()


func test_mission_complete_emits_events() -> void:
	var got := [false]
	Events.mission_completed.connect(func(_id): got[0] = true)
	for i in _director.mission.stages.size():
		for obj: Dictionary in _director.mission.stages[i].get("objectives", []):
			_director.complete_objective(obj)
	assert_true(got[0])
	assert_true(GameState.completed_missions.has(&"mistwalk_to_keep_venture"))


func test_respawn_after_death_restores_control() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	var player: Node3D = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await physics_frames(2)
	player.health.take_damage(10000.0, null, &"blunt")
	assert_true(player.dead, "player died")
	_director._respawn_player()
	assert_false(player.dead, "player.dead cleared on respawn")
	assert_false(player.health.dead, "health revived")
	player.queue_free()
	floor_body.queue_free()
