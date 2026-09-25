extends TestCase
## `SuspicionMeter` rules for the Lady Valette ball: Pushes/flares raise it
## only near a noble, it decays over time, and maxing it out fails the
## mission.


func _make_meter() -> SuspicionMeter:
	var m := SuspicionMeter.new()
	add_child(m)
	return m


func _make_actor(group: StringName, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group(group)
	add_child(n)
	n.global_position = pos
	return n


func test_push_near_noble_raises_suspicion() -> void:
	var meter := _make_meter()
	var player := _make_actor(&"player", Vector3.ZERO)
	var allomancer := Node.new()
	player.add_child(allomancer)
	_make_actor(&"npc_talker", Vector3(2, 0, 0))
	Events.allomantic_line_used.emit(allomancer, null, 0, 1.0)
	assert_gt(meter.value, 0.0)


func test_push_far_from_any_noble_does_not_raise() -> void:
	var meter := _make_meter()
	var player := _make_actor(&"player", Vector3.ZERO)
	var allomancer := Node.new()
	player.add_child(allomancer)
	_make_actor(&"npc_talker", Vector3(500, 0, 0))
	Events.allomantic_line_used.emit(allomancer, null, 0, 1.0)
	assert_eq(meter.value, 0.0)


func test_flare_near_noble_raises_more_than_a_push() -> void:
	var meter_a := _make_meter()
	var meter_b := _make_meter()
	var player := _make_actor(&"player", Vector3.ZERO)
	var allomancer := Node.new()
	player.add_child(allomancer)
	_make_actor(&"npc_talker", Vector3(1, 0, 0))
	meter_a._gain(meter_a.push_gain)
	meter_b._gain(meter_b.flare_gain)
	assert_gt(meter_b.value, meter_a.value)


func test_decays_over_time() -> void:
	var meter := _make_meter()
	meter.value = 50.0
	meter._process(2.0)
	assert_lt(meter.value, 50.0)
	assert_gt(meter.value, 0.0)


func test_max_suspicion_fails_the_mission() -> void:
	var meter := _make_meter()
	meter.max_value = 50.0
	meter.push_gain = 30.0
	var player := _make_actor(&"player", Vector3.ZERO)
	var allomancer := Node.new()
	player.add_child(allomancer)
	_make_actor(&"npc_talker", Vector3(1, 0, 0))
	var failed: Array = [false, ""]
	var on_failed := func(id: StringName, reason: String) -> void:
		if id == meter.mission_id:
			failed[0] = true
			failed[1] = reason
	Events.mission_failed.connect(on_failed)
	Events.allomantic_line_used.emit(allomancer, null, 0, 1.0)
	Events.allomantic_line_used.emit(allomancer, null, 0, 1.0)
	assert_true(failed[0], "maxing suspicion should fail lady_valette")
	assert_eq(failed[1], "detected")
	assert_eq(meter.value, meter.max_value)
