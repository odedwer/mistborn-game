extends TestCase
## Automated objective runs for each Act II mission, mirroring
## `test_act1_missions.gd`: every mission's stages complete in order and
## `mission_completed`/`GameState.completed_missions` fire, by driving
## `MissionDirector.complete_objective` directly (no real world geometry
## needed) — the same approach works for the new Act II objective types
## (`crowd_mood`, `push_target`, `survive`) since `complete_objective` doesn't
## care how an objective would normally finish.

const ACT2_MISSIONS: Array[StringName] = [
	&"dinner_at_keep_venture", &"the_canton_of_resource", &"soothing_the_masses",
	&"house_war", &"the_pits_of_hathsin", &"the_inquisitors_shadow",
]


func _director_for(mission_id: StringName) -> MissionDirector:
	GameState.reset_run()
	GameState.mission_id = mission_id
	var d := MissionDirector.new()
	add_child(d)
	return d


func _complete_all_objectives(d: MissionDirector) -> void:
	for i in d.mission.stages.size():
		for obj: Dictionary in d.mission.stages[i].get("objectives", []):
			d.complete_objective(obj)


func test_each_act2_mission_completes_end_to_end() -> void:
	for mission_id in ACT2_MISSIONS:
		var d := _director_for(mission_id)
		assert_true(d.mission != null, "%s: mission data failed to load" % mission_id)
		assert_eq(d.mission.id, mission_id)
		var finished: Array = [false]
		Events.mission_completed.connect(func(id): if id == mission_id: finished[0] = true)
		_complete_all_objectives(d)
		assert_true(finished[0], "%s: mission_completed never fired" % mission_id)
		assert_true(GameState.completed_missions.has(mission_id), "%s: not recorded as completed" % mission_id)
		d.queue_free()


## Act II continues the same chain gating as Act I.
func test_act2_chain_continues_from_act1() -> void:
	var story := StoryManager.new()
	story.refresh()
	var completed: Array[StringName] = [
		&"survivors_offer", &"the_crew", &"mistwalk_to_keep_venture",
		&"lessons_in_the_mists", &"lady_valette",
	]
	for expected in ACT2_MISSIONS:
		var next := story.next_story_mission(completed)
		assert_true(next != null, "no next mission after completing %s" % str(completed))
		assert_eq(next.id, expected, "expected '%s' next, got '%s'" % [expected, next.id if next != null else &"<null>"])
		completed.append(expected)


## "Dinner at Keep Venture": talking to Elend with a choice sets one of the
## three relationship flags.
func test_elend_dialogue_sets_relationship_flag() -> void:
	GameState.reset_run()
	var lines := DialogueSystem.load_dialogue(&"elend_venture_intro")
	assert_false(lines.is_empty())
	DialogueSystem.play(&"elend_venture_intro")
	DialogueSystem.advance()  # past Elend's opening line to Valette's question (the choices)
	DialogueSystem.choose(0)  # pick the first of the three responses
	assert_true(GameState.has_dialogue_flag(&"elend_curious"))
	assert_false(GameState.has_dialogue_flag(&"elend_guarded"))


## The Canton of Resource's alarm state: one guard going hostile is a quiet
## takedown (no fail), but a second going hostile at the same time means the
## alarm has spread and the heist fails.
func test_canton_alarm_fails_only_once_several_guards_are_hostile() -> void:
	var d := _director_for(&"the_canton_of_resource")
	var failed: Array = [false, ""]
	Events.mission_failed.connect(func(id, reason): if id == &"the_canton_of_resource": failed[0] = true; failed[1] = reason)

	var e1 := _fake_enemy_in_combat()
	d._on_alert_level_changed(2)
	assert_false(failed[0], "a single hostile guard should not fail the heist")

	var e2 := _fake_enemy_in_combat()
	d._on_alert_level_changed(2)
	assert_true(failed[0], "two simultaneously hostile guards should fail the heist")
	assert_eq(failed[1], "combat_count")

	e1.queue_free()
	e2.queue_free()
	d.queue_free()


func _fake_enemy_in_combat() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar state: int = %d\n" % EnemyBase.State.COMBAT
	script.reload()
	var e: Node = script.new()
	e.add_to_group(&"enemy")
	add_child(e)
	return e


## "Soothing the Masses": the `crowd_mood` objective completes once the
## scene's `CrowdMoodMeter` drops below the target.
func test_crowd_mood_objective_completes_when_soothed() -> void:
	var d := _director_for(&"soothing_the_masses")
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	meter.mood = 80.0
	var stage0: Dictionary = d.mission.stages[0]
	var obj: Dictionary
	for o: Dictionary in stage0.get("objectives", []):
		if StringName(o.get("id", "")) == &"calm_the_crowd":
			obj = o
	assert_true(not obj.is_empty())
	d._active_objectives[&"calm_the_crowd"] = obj
	d._process(0.0)
	assert_false(GameState.completed_objectives.has(&"calm_the_crowd"), "still above target")
	meter.mood = 20.0
	d._process(0.0)
	assert_true(GameState.completed_objectives.has(&"calm_the_crowd"))
	meter.queue_free()
	d.queue_free()


## "House War": the `push_target` objective completes on any Push/Pull whose
## target's meta `objective_id` matches the marker id — any metal.
func test_push_target_objective_completes_on_matching_target() -> void:
	var d := _director_for(&"house_war")
	var stage: Dictionary = d.mission.stages[1]
	var obj: Dictionary = stage.get("objectives", [])[0]
	assert_eq(obj.get("id"), "topple_gate")
	d._active_objectives[&"topple_gate"] = obj

	var wrong_target := Node.new()
	wrong_target.set_meta("objective_id", "not_the_gate")
	add_child(wrong_target)
	var allomancer := Node.new()
	var player := Node.new()
	player.add_to_group(&"player")
	add_child(player)
	player.add_child(allomancer)
	d._on_allomantic_line_used(allomancer, wrong_target, Metal.Type.STEEL, 1.0)
	assert_false(GameState.completed_objectives.has(&"topple_gate"))

	var gate := Node.new()
	gate.set_meta("objective_id", "tekiel_gate")
	add_child(gate)
	d._on_allomantic_line_used(allomancer, gate, Metal.Type.IRON, 1.0)
	assert_true(GameState.completed_objectives.has(&"topple_gate"))
	d.queue_free()


## "The Inquisitor's Shadow": the `survive` objective completes `duration`
## seconds after it activates, purely from elapsed time.
func test_survive_objective_completes_after_duration() -> void:
	var d := _director_for(&"the_inquisitors_shadow")
	var obj := {"id": "survive_clash", "type": "survive", "duration": 5.0}
	d._active_objectives[&"survive_clash"] = obj
	d._process(2.0)
	assert_false(GameState.completed_objectives.has(&"survive_clash"))
	d._process(4.0)
	assert_true(GameState.completed_objectives.has(&"survive_clash"))
	d.queue_free()
