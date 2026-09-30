extends TestCase
## TimeOfDay: the clock and its phases, forced phases (night missions,
## interiors), save round-trip, and everything it gates or drives: phase-gated
## activities and patrols, the crowd's obligator share, the safehouse "wait"
## and the DayNightDriver's lighting (a forced night must reproduce the
## authored night exactly).


func before_each() -> void:
	GameState.reset_run()


func after_each() -> void:
	GameState.reset_run()
	for slot in [22]:
		var p := GameState.slot_path(slot)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func test_default_is_night_and_phases_follow_the_clock() -> void:
	assert_almost(TimeOfDay.hour, TimeOfDay.DEFAULT_HOUR)
	assert_true(TimeOfDay.is_night())
	TimeOfDay.set_hour(12.0)
	assert_false(TimeOfDay.is_night())
	assert_almost(TimeOfDay.night_factor(), 0.0)
	TimeOfDay.set_hour(2.0)
	assert_true(TimeOfDay.is_night())
	assert_almost(TimeOfDay.night_factor(), 1.0)
	TimeOfDay.set_hour(25.0)
	assert_almost(TimeOfDay.hour, 1.0, 0.001, "wraps past midnight")
	var dusk := TimeOfDay.night_factor_at(19.25)
	assert_gt(dusk, 0.0)
	assert_lt(dusk, 1.0)


func test_phase_changed_fires_and_clock_advances_only_when_running() -> void:
	var seen: Array = []
	var cb := func(p: int) -> void: seen.append(p)
	TimeOfDay.phase_changed.connect(cb)
	TimeOfDay.set_hour(12.0)
	TimeOfDay.set_hour(21.0)
	TimeOfDay.phase_changed.disconnect(cb)
	assert_eq(seen, [TimeOfDay.Phase.DAY, TimeOfDay.Phase.NIGHT])
	TimeOfDay.set_hour(10.0)
	TimeOfDay._process(60.0)
	assert_almost(TimeOfDay.hour, 10.0, 0.001, "stopped clock")
	TimeOfDay.clock_running = true
	TimeOfDay._process(TimeOfDay.day_length_seconds / 24.0)
	assert_almost(TimeOfDay.hour, 11.0, 0.001, "one in-game hour")


func test_forced_phase_overrides_and_pauses_the_clock() -> void:
	TimeOfDay.set_hour(12.0)
	TimeOfDay.clock_running = true
	TimeOfDay.force_phase(&"test", TimeOfDay.Phase.NIGHT)
	assert_true(TimeOfDay.is_night())
	assert_almost(TimeOfDay.night_factor(), 1.0)
	TimeOfDay._process(600.0)
	assert_almost(TimeOfDay.hour, 12.0, 0.001, "paused while forced")
	assert_false(TimeOfDay.wait_until(TimeOfDay.Phase.DAY), "can't wait out a forced phase")
	TimeOfDay.force_phase(&"other", TimeOfDay.Phase.DAY)
	assert_true(TimeOfDay.is_night(), "night wins a conflict")
	TimeOfDay.release(&"test")
	assert_false(TimeOfDay.is_night())
	TimeOfDay.release(&"other")
	assert_false(TimeOfDay.is_forced())


func test_interiors_force_night() -> void:
	TimeOfDay.set_hour(12.0)
	Events.interior_entered.emit("res://x.tscn")
	assert_true(TimeOfDay.is_night())
	Events.interior_exited.emit()
	assert_false(TimeOfDay.is_night())


func test_time_round_trips_through_save() -> void:
	TimeOfDay.set_hour(13.5)
	assert_true(GameState.save_game(22))
	TimeOfDay.set_hour(3.0)
	assert_true(GameState.load_game(22))
	assert_almost(TimeOfDay.hour, 13.5)
	assert_almost(float(GameState.to_dict()["time_of_day"]), 13.5)
	GameState.reset_run()
	assert_almost(TimeOfDay.hour, TimeOfDay.DEFAULT_HOUR)
	# Old saves without the key load at the default (night).
	GameState.from_dict({"version": 1})
	assert_almost(TimeOfDay.hour, TimeOfDay.DEFAULT_HOUR)


func test_night_missions_force_night() -> void:
	var story := StoryManager.new()
	story.refresh()
	var mistwalk: MissionData = story.get_mission(&"mistwalk_to_keep_venture")
	assert_eq(mistwalk.time_of_day, "night")
	var offer: MissionData = story.get_mission(&"survivors_offer")
	assert_eq(offer.time_of_day, "")
	var d := MissionDirector.new()
	TimeOfDay.set_hour(12.0)
	d.mission = mistwalk
	d._apply_time_of_day()
	assert_true(TimeOfDay.is_night())
	assert_true(TimeOfDay.is_forced())
	assert_almost(TimeOfDay.hour, TimeOfDay.NIGHT_HOUR, 0.001, "clock moved to night too")
	d.mission = offer
	d._apply_time_of_day()
	assert_false(TimeOfDay.is_forced(), "an any-time mission releases the clock")
	d.free()


func test_night_only_activity_is_gated() -> void:
	var mgr := ActivityManager.new()
	add_child(mgr)
	var a: ActivityData = mgr.activities[&"ambush_noble"]
	assert_eq(a.phase, "night")
	TimeOfDay.set_hour(12.0)
	assert_false(mgr.is_available_now(&"ambush_noble"))
	assert_false(mgr.start_activity(&"ambush_noble", Vector3(600, 0, -1500)))
	assert_true(mgr.is_available_now(&"coin_race_skaa"), "ungated activity runs by day")
	mgr._cooldowns.clear()
	TimeOfDay.set_hour(22.0)
	assert_true(mgr.start_activity(&"ambush_noble", Vector3(600, 0, -1500)))
	mgr.queue_free()
	await physics_frames(1)


func test_night_patrol_markers_carry_the_phase() -> void:
	var plan := CityPlan.load_from_file()
	var n := 0
	for m: Dictionary in plan.markers:
		if str(m.get("phase", "")) == "night" and m["group"] == "enemy_spawn":
			n += 1
			var p := Vector2(float(m["pos"][0]), float(m["pos"][1]))
			assert_true(plan.district_at(p) in [&"noble", &"kredik_shaw"], "night patrol %s is in the keep quarter" % p)
			var L := ChunkLayout.generate(plan, 1337, plan.chunk_of(p))
			var found := false
			for mk: Dictionary in L.markers:
				if mk["group"] == &"enemy_spawn" and str(mk["meta"].get("phase", "")) == "night":
					found = true
			assert_true(found, "phase meta survives layout at %s" % p)
	assert_gt(n, 3)


func test_enemy_spawner_night_only_patrol() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var root := Node3D.new()
	add_child(root)
	var m := Marker3D.new()
	m.set_meta("enemy_type", &"guard")
	m.set_meta("phase", &"night")
	m.add_to_group(&"enemy_spawn")
	root.add_child(m)
	TimeOfDay.set_hour(12.0)
	assert_eq(spawner.spawn_for_marker(m), null, "no night patrol by day")
	TimeOfDay.set_hour(22.0)
	await physics_frames(1)
	assert_eq(spawner.spawned_enemies().size(), 1, "patrol turns out at nightfall")
	TimeOfDay.set_hour(8.0)
	await physics_frames(2)
	var alive := 0
	for e in spawner.spawned_enemies():
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			alive += 1
	assert_eq(alive, 0, "patrol goes home at dawn")
	spawner.queue_free()
	root.queue_free()


func test_crowd_obligators_patrol_at_night() -> void:
	var crowd := CrowdSystem.new()
	crowd.plan = CityPlan.load_from_file()
	add_child(crowd)
	var root := Node3D.new()
	add_child(root)
	TimeOfDay.set_hour(12.0)
	var coords: Array[Vector2i] = []
	for p: Vector2 in [Vector2(600, -1500), Vector2(-600, -1300), Vector2(300, -1700), Vector2(-800, -1700), Vector2(700, -1000), Vector2(-700, -600)]:
		coords.append(crowd.plan.chunk_of(p))
	for c in coords:
		crowd.populate_unit(root, c)
	var day := crowd.obligator_count()
	TimeOfDay.set_hour(22.0)
	var night := crowd.obligator_count()
	assert_gt(crowd.agent_count(), 10)
	assert_gt(float(night), float(day), "more obligators at night (%d vs %d)" % [night, day])
	assert_gt(float(night), crowd.agent_count() * 0.35, "noble nights are mostly obligators")
	crowd.queue_free()
	root.queue_free()


func test_safehouse_wait_until_night() -> void:
	var ft := FastTravelManager.new()
	add_child(ft)
	TimeOfDay.set_hour(9.0)
	assert_true(await ft.wait_at_safehouse(TimeOfDay.Phase.NIGHT, false))
	assert_true(TimeOfDay.is_night())
	assert_almost(TimeOfDay.hour, TimeOfDay.NIGHT_HOUR)
	TimeOfDay.force_phase(&"mission", TimeOfDay.Phase.NIGHT)
	assert_false(await ft.wait_at_safehouse(TimeOfDay.Phase.DAY, false), "refused during a night mission")
	ft.queue_free()


func test_driver_day_lighting_and_exact_night() -> void:
	var host := Node3D.new()
	add_child(host)
	var env_d := EnvironmentBuilder.build(host)
	var env: Environment = env_d["environment"]
	var moon: DirectionalLight3D = env_d["moon"]
	var night_basis := moon.basis
	var night_energy := moon.light_energy
	var night_color := moon.light_color
	var night_ambient := env.ambient_light_color
	var mist := MistController.new()
	host.add_child(mist)
	mist.setup(env)
	var night_fog := env.fog_density
	var night_exposure := env.tonemap_exposure
	var lamp := OmniLight3D.new()
	lamp.light_energy = 3.0
	lamp.set_meta(&"base_energy", 3.0)
	lamp.add_to_group(&"street_light")
	host.add_child(lamp)
	var drv := DayNightDriver.new()
	host.add_child(drv)
	drv.setup(env, moon, mist, null)
	var sky := env.sky.sky_material as ShaderMaterial
	var win := WorldMaterials.get_mat(WorldMaterials.Mat.WINDOW) as ShaderMaterial

	TimeOfDay.set_hour(12.0)
	assert_almost(float(sky.get_shader_parameter("day_amount")), 1.0)
	assert_gt((moon.basis.z - night_basis.z).length(), 0.1, "sun, not moon")
	assert_lt(-moon.basis.z.y, -0.1, "sunlight shines downward")
	assert_lt(float(win.get_shader_parameter("lit_energy")), 0.5, "windows dim by day")
	assert_false(lamp.visible, "street lamps off by day")
	assert_lt(mist.daylight, 1.01)
	assert_gt(mist.daylight, 0.99)

	TimeOfDay.force_phase(&"mission", TimeOfDay.Phase.NIGHT)
	assert_almost(float(sky.get_shader_parameter("day_amount")), 0.0)
	assert_true(moon.basis.is_equal_approx(night_basis), "authored moon angle")
	assert_almost(moon.light_energy, night_energy)
	assert_true(moon.light_color.is_equal_approx(night_color))
	assert_true(env.ambient_light_color.is_equal_approx(night_ambient))
	assert_almost(env.fog_density, night_fog, 0.00001)
	assert_almost(env.tonemap_exposure, night_exposure)
	assert_almost(float(win.get_shader_parameter("lit_energy")), DayNightDriver.NIGHT_WINDOW_ENERGY)
	assert_true(lamp.visible)
	assert_almost(lamp.light_energy, 3.0)
	host.queue_free()
