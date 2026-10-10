extends TestCase
## CrowdMember grounding: a member is often positioned *after* it enters the
## tree (ActivityManager adds it to its chunk, then moves it to its spawn
## point). Its home must be where it actually stands, not where `_ready`
## happened to see it (the parent's origin), or it wanders off toward the
## world origin, walks off roofs/quays and falls out of the world (the
## test_story_sweep "CrowdMember in c_m1_1 fell" flake).


func _floor(at: Vector3, size: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = at + Vector3.DOWN * 0.5
	return body


func test_member_positioned_after_add_stays_home() -> void:
	var spot := Vector3(400.0, 12.0, -350.0)   # a small "roof", far from the origin
	var roof := _floor(spot, 14.0)   # wider than the 5.5 m wander envelope
	var parent := Node3D.new()                  # a chunk root at the world origin
	add_child(parent)
	var members: Array[CrowdMember] = []
	for i in 5:
		var m := CrowdMember.new()
		m.wander_radius = 3.0
		parent.add_child(m)
		var ang := TAU * float(i) / 5.0
		m.global_position = spot + Vector3(cos(ang), 0.0, sin(ang)) * 2.5
		members.append(m)
	await physics_frames(400)
	# home is 2.5 m out and wandering reaches 3 m from home (+ jostling):
	# 6 m still tells "stayed on its roof" from "teleported to the origin"
	for m in members:
		assert_lt(Vector2(m.global_position.x - spot.x, m.global_position.z - spot.z).length(), 6.0,
				"member stays on its roof (at %s)" % m.global_position)
		assert_gt(m.global_position.y, spot.y - 1.0, "member did not fall (y %.1f)" % m.global_position.y)
	parent.queue_free()
	roof.queue_free()


func test_member_that_falls_off_is_sent_home_quickly() -> void:
	var spot := Vector3(-300.0, 20.0, 260.0)
	var roof := _floor(spot, 4.0)
	var m := CrowdMember.new()
	m.position = spot
	add_child(m)
	await physics_frames(5)
	# Shove it off the roof edge into the void.
	m.global_position = spot + Vector3(6.0, 0.0, 0.0)
	var lowest := INF
	for i in 180:
		await physics_frames(1)
		lowest = minf(lowest, m.global_position.y)
	assert_gt(lowest, spot.y - 25.0, "returned home long before dropping out of the world (lowest %.1f)" % lowest)
	m.queue_free()
	roof.queue_free()
