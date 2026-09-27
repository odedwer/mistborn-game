extends TestCase


func _make_metal(pos: Vector3) -> Metallic:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	var m := Metallic.new()
	body.add_child(m)
	return m


func test_query_radius_finds_nearby_only() -> void:
	var near := _make_metal(Vector3(1, 0, 0))
	var far := _make_metal(Vector3(40, 0, 0))
	var found := MetalRegistry.query_radius(Vector3.ZERO, 5.0)
	assert_true(near in found, "near metal found")
	assert_false(far in found, "far metal excluded")


func test_static_body_metal_is_anchored() -> void:
	var m := _make_metal(Vector3.ZERO)
	assert_true(m.anchored)
	assert_eq(m.get_body_mass(), INF)


func test_unregister_on_free() -> void:
	var m := _make_metal(Vector3(2, 0, 0))
	var before := MetalRegistry.count()
	m.get_parent().free()
	assert_eq(MetalRegistry.count(), before - 1)


func test_moving_metal_is_rebucketed_and_static_ones_are_not_tracked() -> void:
	var dyn_before := MetalRegistry.dynamic_count()
	var rb := RigidBody3D.new()
	rb.freeze = true
	add_child(rb)
	rb.global_position = Vector3(1000, 0, 1000)
	var m := Metallic.new()
	rb.add_child(m)
	assert_eq(MetalRegistry.dynamic_count(), dyn_before + 1, "movable metal tracked")
	var s := _make_metal(Vector3(1000, 0, 1010))
	assert_eq(MetalRegistry.dynamic_count(), dyn_before + 1, "static metal not re-bucketed every frame")
	assert_true(m in MetalRegistry.query_radius(Vector3(1000, 0, 1000), 3.0))
	rb.global_position = Vector3(1100, 0, 1000)
	await physics_frames(1)
	assert_true(m in MetalRegistry.query_radius(Vector3(1100, 0, 1000), 3.0), "found at its new cell")
	assert_false(m in MetalRegistry.query_radius(Vector3(1000, 0, 1000), 3.0), "gone from the old cell")
	assert_true(s in MetalRegistry.query_radius(Vector3(1000, 0, 1010), 1.0))
	rb.free()
	assert_eq(MetalRegistry.dynamic_count(), dyn_before, "dynamic metal unregistered")


func test_mass_unregister_keeps_registry_consistent() -> void:
	var bodies: Array[Node] = []
	for i in 300:
		bodies.append(_make_metal(Vector3(2000 + i * 0.5, 0, 2000)).get_parent())
	var before := MetalRegistry.count()
	# Free every other one (swap-remove must keep the index map right).
	for i in range(0, 300, 2):
		bodies[i].free()
	assert_eq(MetalRegistry.count(), before - 150)
	var found := MetalRegistry.query_radius(Vector3(2075, 0, 2000), 100.0)
	assert_eq(found.size(), 150, "exactly the survivors are found")
	for m in MetalRegistry.all():
		assert_true(is_instance_valid(m) and m.is_inside_tree(), "no stale entries")
