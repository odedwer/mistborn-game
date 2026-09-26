extends TestCase
## `SceneTransition` reparents the live player node into/out of an interior
## scene instead of recreating it, so its state (and identity) survives the
## round trip; a fade/loading screen brackets each half.


func test_enter_and_exit_interior_preserves_player_state_and_identity() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	player.set_meta("carried_state", 42)
	add_child(player)
	player.global_position = Vector3(10, 0, 5)
	var original_id := player.get_instance_id()

	await SceneTransition.enter_interior("res://src/mission/interiors/canton_office.tscn")
	assert_true(SceneTransition.is_inside_interior(), "should be inside the interior after entering")
	assert_eq(player.get_instance_id(), original_id, "the same player node should be reused")
	# Moved to the interior's own spawn point, not left at the outdoor spot.
	assert_gt(player.global_position.distance_to(Vector3(10, 0, 5)), 0.5)

	await SceneTransition.exit_interior()
	assert_false(SceneTransition.is_inside_interior(), "should be back outside after exiting")
	assert_eq(player.get_instance_id(), original_id)
	assert_eq(int(player.get_meta("carried_state", -1)), 42, "arbitrary player state should survive the round trip")
	assert_almost(player.global_position.x, 10.0, 0.01, "should return to the exact outdoor transform")
	assert_almost(player.global_position.z, 5.0, 0.01)

	player.queue_free()


func test_entering_twice_is_a_no_op() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)

	await SceneTransition.enter_interior("res://src/mission/interiors/canton_office.tscn")
	var first_interior := SceneTransition._interior_root
	await SceneTransition.enter_interior("res://src/mission/interiors/clubs_shop_hub.tscn")
	assert_eq(SceneTransition._interior_root, first_interior, "already inside an interior; second enter should be ignored")

	await SceneTransition.exit_interior()
	player.queue_free()


func test_exit_without_enter_is_a_no_op() -> void:
	assert_false(SceneTransition.is_inside_interior())
	await SceneTransition.exit_interior()
	assert_false(SceneTransition.is_inside_interior())
