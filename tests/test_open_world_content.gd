extends TestCase
## City-wide open-world content: activity beacons stream in and out with
## their own chunk (GameState remembers progress regardless of the node's
## lifetime), and fast travel to an unlocked safehouse actually streams the
## destination's ground in before handing control back.

func _make_world(seed_value := 1337) -> LuthadelWorld:
	var w: LuthadelWorld = (load("res://src/world/luthadel.tscn") as PackedScene).instantiate()
	w.seed = seed_value
	w.build_far_lod = false
	add_child(w)
	w.add_to_group(&"world")  # scenes/game.gd normally does this
	return w


func before_each() -> void:
	GameState.reset_run()


func after_each() -> void:
	GameState.reset_run()


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func test_activity_beacon_streams_with_its_chunk_and_record_survives_unload() -> void:
	var w := _make_world()
	var mgr := ActivityManager.new()
	add_child(mgr)
	await get_tree().physics_frame

	# "coin_race_merchant" is a merchant-district activity, far from the
	# origin spawn: its position resolves city-wide before its chunk streams.
	var pos := mgr.start_marker_position(&"coin_race_merchant")
	assert_true(pos != Vector3.INF, "activity has a citywide position")
	assert_false(w.is_area_loaded(pos), "starts unloaded (far from spawn)")

	w.streamer.fallback_focus = pos
	w.streamer.load_radius = 200.0
	var loaded := await _wait_until(func() -> bool: return w.is_area_loaded(pos), 2000)
	assert_true(loaded, "its chunk streamed in")
	await get_tree().physics_frame

	var beacon: Area3D = null
	for a in mgr._start_triggers:
		if is_instance_valid(a) and (a as Node3D).global_position.distance_to(pos) < 1.0:
			beacon = a
	assert_true(beacon != null, "beacon created once its chunk streamed in")
	if beacon != null:
		assert_true(beacon.get_parent() != get_tree().root, "beacon streams with its chunk, not parented to the root")

	assert_true(mgr.start_activity(&"coin_race_merchant", pos), "activity starts")
	mgr.complete_activity(&"coin_race_merchant")
	assert_true(GameState.activity_record(&"coin_race_merchant")["completed"])

	# Move the focus far away: the chunk (and the beacon on it) unloads.
	w.streamer.fallback_focus = Vector3(2000, 0, 1000)
	w.streamer.update_interval = 0.0
	var unloaded := await _wait_until(func() -> bool: return not w.is_area_loaded(pos), 2000)
	assert_true(unloaded, "far chunk unloaded")
	assert_true(GameState.activity_record(&"coin_race_merchant")["completed"], "record survives the chunk unloading")

	# Move back: the beacon rebuilds exactly once (no duplicate).
	w.streamer.fallback_focus = pos
	loaded = await _wait_until(func() -> bool: return w.is_area_loaded(pos), 2000)
	assert_true(loaded, "chunk reloaded")
	await get_tree().physics_frame
	var count := 0
	for a in mgr._start_triggers:
		if is_instance_valid(a) and (a as Node3D).global_position.distance_to(pos) < 1.0:
			count += 1
	assert_eq(count, 1, "beacon rebuilt exactly once on reload")

	mgr.queue_free()
	w.queue_free()
	await get_tree().process_frame


func test_fast_travel_reaches_destination_with_ground_loaded() -> void:
	var w := _make_world()
	var player := Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = w.spawn_position()

	var ft := FastTravelManager.new()
	add_child(ft)
	await get_tree().physics_frame

	assert_true(GameState.discover_safehouse(&"safehouse_docks"))
	var list := ft.unlocked_list()
	assert_eq(list.size(), 1)
	var dest: Vector3 = list[0]["position"]
	assert_true(dest != Vector3.INF)
	assert_false(w.is_area_loaded(dest), "destination starts unloaded (far from spawn)")

	var ok: bool = await ft.travel_to(&"safehouse_docks")
	assert_true(ok, "fast travel succeeds")
	assert_true(w.is_area_loaded(dest), "destination ground is loaded after fast travel")
	assert_almost(player.global_position.x, dest.x, 1.0)
	assert_almost(player.global_position.z, dest.z, 1.0)

	ft.queue_free()
	player.queue_free()
	w.queue_free()
	await get_tree().process_frame


func test_fast_travel_refuses_a_locked_safehouse() -> void:
	var w := _make_world()
	var player := Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = w.spawn_position()
	var ft := FastTravelManager.new()
	add_child(ft)
	await get_tree().physics_frame
	assert_false(GameState.is_safehouse_unlocked(&"safehouse_noble"))
	var ok: bool = await ft.travel_to(&"safehouse_noble")
	assert_false(ok, "can't fast-travel to an undiscovered safehouse")
	ft.queue_free()
	player.queue_free()
	w.queue_free()
	await get_tree().process_frame


func test_discovered_safehouses_round_trip_through_save_load() -> void:
	GameState.discover_safehouse(&"safehouse_docks")
	assert_true(GameState.save_game(22))
	GameState.reset_run()
	assert_false(GameState.is_safehouse_unlocked(&"safehouse_docks"))
	assert_true(GameState.load_game(22))
	assert_true(GameState.is_safehouse_unlocked(&"safehouse_docks"))
	DirAccess.remove_absolute(GameState.slot_path(22))
