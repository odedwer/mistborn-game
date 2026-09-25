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
