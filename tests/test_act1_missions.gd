extends TestCase
## Automated objective runs for each Act I mission (mirrors test_mission.gd's
## coverage of the vertical slice): every mission's stages complete in order
## and `mission_completed`/`GameState.completed_missions` fire, purely by
## driving `MissionDirector.complete_objective` the way real trigger/Events
## callbacks would (no real world geometry needed).

const ACT1_MISSIONS: Array[StringName] = [
	&"survivors_offer", &"the_crew", &"lessons_in_the_mists", &"lady_valette",
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


func test_each_act1_mission_completes_end_to_end() -> void:
	for mission_id in ACT1_MISSIONS:
		var d := _director_for(mission_id)
		assert_true(d.mission != null, "%s: mission data failed to load" % mission_id)
		assert_eq(d.mission.id, mission_id)
		var finished: Array = [false]
		Events.mission_completed.connect(func(id): if id == mission_id: finished[0] = true)
		_complete_all_objectives(d)
		assert_true(finished[0], "%s: mission_completed never fired" % mission_id)
		assert_true(GameState.completed_missions.has(mission_id), "%s: not recorded as completed" % mission_id)
		d.queue_free()


## "The Survivor's Offer" locks allomancy to pewter only, then unlocks
## steel/iron/pewter/tin once Vin reaches Clubs' shop.
func test_survivors_offer_locks_then_unlocks_metals() -> void:
	var src := "extends Node3D\nvar allomancer: Allomancer\nfunc _init():\n\tallomancer = Allomancer.new()\n\tadd_child(allomancer)\n"
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	var player: Node3D = script.new()
	player.add_to_group(&"player")
	add_child(player)
	var allomancer: Allomancer = player.allomancer

	var d := _director_for(&"survivors_offer")
	assert_eq(allomancer.allowed_metals, [Metal.Type.PEWTER] as Array[int], "should be pewter-locked on entering the canton office")

	var stage0: Dictionary = d.mission.stages[0]
	for obj: Dictionary in stage0.get("objectives", []):
		d.complete_objective(obj)
	var stage1: Dictionary = d.mission.stages[1]
	for obj: Dictionary in stage1.get("objectives", []):
		d.complete_objective(obj)

	assert_true(allomancer.allowed_metals.is_empty() or allomancer.allowed_metals.size() == 4,
		"metals should be unlocked after reaching Clubs' shop")
	assert_true(allomancer.allowed_metals.has(Metal.Type.STEEL))
	assert_true(allomancer.allowed_metals.has(Metal.Type.TIN))
	d.queue_free()


## "The Crew" 's eight NPC meetings are independent (parallel) objectives;
## meeting them in any order still completes the stage.
func test_the_crew_meetings_are_order_independent() -> void:
	var d := _director_for(&"the_crew")
	var stage0: Dictionary = d.mission.stages[0]
	var objs: Array = stage0.get("objectives", [])
	assert_eq(objs.size(), 8)
	for id: StringName in [&"meet_marsh", &"meet_kelsier", &"meet_spook"]:
		for obj: Dictionary in objs:
			if StringName(obj.get("id", "")) == id:
				d.complete_objective(obj)
	assert_eq(d.stage_index, 0, "stage should not advance until all 8 are met")
	for obj: Dictionary in objs:
		d.complete_objective(obj)
	assert_eq(d.stage_index, 1, "stage should advance once every crew member is met")
	d.queue_free()


## "Lady Valette" only completes "gather_rumors" once all three noble flags
## are set (`flag_count`), regardless of the order they were talked to.
func test_lady_valette_flag_count_needs_all_three() -> void:
	GameState.reset_run()
	GameState.mission_id = &"lady_valette"
	var d := MissionDirector.new()
	add_child(d)
	var rumors: Dictionary = d.mission.stages[0].get("objectives", [])[0]
	assert_eq(rumors.get("id"), "gather_rumors")

	GameState.set_dialogue_flag(&"talked_noble_1")
	assert_false(GameState.completed_objectives.has(&"gather_rumors"))
	GameState.set_dialogue_flag(&"talked_noble_2")
	assert_false(GameState.completed_objectives.has(&"gather_rumors"))
	GameState.set_dialogue_flag(&"talked_noble_3")
	assert_true(GameState.completed_objectives.has(&"gather_rumors"), "all 3 flags should complete gather_rumors")
	d.queue_free()
