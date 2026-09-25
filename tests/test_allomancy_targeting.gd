extends TestCase
## LineTargeting (crosshair selection, locking, cycling, traversal assist)
## and coin damage scaling.


func _metal_at(pos: Vector3, anchored := true) -> Metallic:
	var n: Node3D = StaticBody3D.new() if anchored else Node3D.new()
	add_child(n)
	n.global_position = pos
	var m := Metallic.new()
	n.add_child(m)
	return m


func test_picks_metal_nearest_crosshair() -> void:
	var a := _metal_at(Vector3(0, 0, -20))       # dead ahead
	var b := _metal_at(Vector3(3, 0, -20))       # ~8.5 deg off
	var c := _metal_at(Vector3(0, 10, -5))       # far off-axis
	var lines: Array[Metallic] = [c, b, a]
	var t := LineTargeting.new()
	assert_eq(t.update(lines, Vector3.ZERO, Vector3.FORWARD), a)
	assert_eq(t.candidates.size(), 2, "c is outside the cone")
	assert_eq(t.candidates[1], b)


func test_distance_breaks_ties() -> void:
	var near := _metal_at(Vector3(0, 0, -5))
	var far := _metal_at(Vector3(0, 0, -30))
	var lines: Array[Metallic] = [far, near]
	var t := LineTargeting.new()
	assert_eq(t.update(lines, Vector3(0, 0.01, 0), Vector3.FORWARD), near)


func test_lock_keeps_target_when_aim_moves() -> void:
	var a := _metal_at(Vector3(0, 0, -10))
	var b := _metal_at(Vector3(10, 0, 0))
	var lines: Array[Metallic] = [a, b]
	var t := LineTargeting.new()
	t.update(lines, Vector3.ZERO, Vector3.FORWARD)
	t.lock()
	assert_eq(t.update(lines, Vector3.ZERO, Vector3.RIGHT), a, "locked")
	t.release()
	assert_eq(t.update(lines, Vector3.ZERO, Vector3.RIGHT), b, "released")


func test_lock_drops_target_out_of_range() -> void:
	var a := _metal_at(Vector3(0, 0, -10))
	var lines: Array[Metallic] = [a]
	var t := LineTargeting.new()
	t.update(lines, Vector3.ZERO, Vector3.FORWARD)
	t.lock()
	var empty: Array[Metallic] = []
	assert_eq(t.update(empty, Vector3.ZERO, Vector3.FORWARD), null)
	assert_false(t.locked)


func test_cycle_through_candidates() -> void:
	var a := _metal_at(Vector3(0, 0, -10))
	var b := _metal_at(Vector3(1, 0, -10))
	var c := _metal_at(Vector3(2, 0, -10))
	var lines: Array[Metallic] = [a, b, c]
	var t := LineTargeting.new()
	t.update(lines, Vector3.ZERO, Vector3.FORWARD)
	assert_eq(t.target, a)
	assert_eq(t.cycle(1), b)
	assert_eq(t.update(lines, Vector3.ZERO, Vector3.FORWARD), b, "cycled choice sticks")
	assert_eq(t.cycle(1), c)
	assert_eq(t.cycle(1), a, "wraps")
	assert_eq(t.cycle(-1), c)


func test_ignores_metal_between_camera_and_player() -> void:
	var behind_player := _metal_at(Vector3(0, 0, -1))
	var ahead := _metal_at(Vector3(0.5, 0, -15))
	var lines: Array[Metallic] = [behind_player, ahead]
	var t := LineTargeting.new()
	assert_eq(t.update(lines, Vector3.ZERO, Vector3.FORWARD, 3.0), ahead)


func test_traversal_assist_prefers_anchor_behind_and_below() -> void:
	var player := Vector3(0, 10, 0)
	var ahead := _metal_at(Vector3(0, 10, -8))        # pushing it would slow us
	var behind_below := _metal_at(Vector3(0, 4, 6))   # pushes us forward and up
	var below := _metal_at(Vector3(0, 2, 0))          # pushes straight up
	var lines: Array[Metallic] = [ahead, below, behind_below]
	var t := LineTargeting.new()
	var desired := (Vector3.FORWARD + Vector3.UP * 0.65).normalized()
	assert_eq(t.pick_traversal_anchor(lines, player, desired, 40.0, 60.0), behind_below)
	assert_eq(LineTargeting.traversal_score(ahead, player, desired, 40.0, 60.0, 0.25), 0.0)
	assert_gt(LineTargeting.traversal_score(below, player, desired, 40.0, 60.0, 0.25), 0.0)


func test_traversal_assist_prefers_anchored_over_light() -> void:
	var player := Vector3(0, 10, 0)
	var rb := RigidBody3D.new()
	add_child(rb)
	rb.mass = 1.0
	rb.global_position = Vector3(0, 5, 3)
	var light := Metallic.new()
	rb.add_child(light)
	rb.sleeping = false
	var post := _metal_at(Vector3(0, 5, 3.5))
	var desired := (Vector3.FORWARD + Vector3.UP * 0.65).normalized()
	var s_light := LineTargeting.traversal_score(light, player, desired, 40.0, 60.0, 0.25)
	var s_post := LineTargeting.traversal_score(post, player, desired, 40.0, 60.0, 0.25)
	assert_gt(s_post, s_light * 5.0, "anchored post beats a 1 kg loose prop")


func test_coin_damage_scales_with_speed() -> void:
	assert_eq(Coin.damage_for_speed(5.0), 0.0, "slow coins are harmless")
	var mid := Coin.damage_for_speed(40.0)
	var fast := Coin.damage_for_speed(80.0)
	assert_gt(mid, 0.0)
	assert_gt(fast, mid)
	assert_eq(Coin.damage_for_speed(500.0), 95.0, "capped")


func test_coin_hits_health_with_speed_damage() -> void:
	var target := StaticBody3D.new()
	target.collision_layer = 1 << 2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.5)
	cs.shape = box
	target.add_child(cs)
	var h := Health.new()
	h.name = "Health"
	target.add_child(h)
	add_child(target)
	target.global_position = Vector3(0, 200, -6)
	var pool := CoinPool.get_for(self)
	var coin := pool.spawn(Transform3D(Basis.IDENTITY, Vector3(0, 200, 0)), Vector3(0, 0, -60), null)
	await physics_frames(20)
	assert_lt(h.current, h.max_health, "coin damaged the target")
	assert_almost(h.max_health - h.current, Coin.damage_for_speed(60.0), 6.0, "damage ~ impact speed")
	pool.recycle(coin)
	assert_false(coin.active)
	assert_false(coin.is_inside_tree(), "parked coins leave the tree (and the registry)")
