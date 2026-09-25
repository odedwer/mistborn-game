extends TestCase
## "Save anywhere": open-world position, activity records, collectibles and
## mastery all round-trip through GameState.save_game/load_game, and are
## captured automatically at save time from the live player.


func before_each() -> void:
	GameState.reset_run()


func after_each() -> void:
	if FileAccess.file_exists("user://saves/slot_99.json"):
		DirAccess.remove_absolute("user://saves/slot_99.json")


func test_capture_open_world_position_from_live_player() -> void:
	var player: Node3D = Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(12.0, 3.0, -44.0)
	assert_false(GameState.has_open_world_position)
	GameState.capture_open_world_position()
	assert_true(GameState.has_open_world_position)
	assert_almost(GameState.open_world_position.origin.x, 12.0)
	assert_almost(GameState.open_world_position.origin.z, -44.0)
	player.queue_free()


func test_save_game_captures_position_without_a_checkpoint() -> void:
	var player: Node3D = Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(5.0, 0.0, 7.0)
	assert_true(GameState.save_game(20))
	assert_true(GameState.has_open_world_position)
	assert_almost(GameState.open_world_position.origin.x, 5.0)
	player.queue_free()
	DirAccess.remove_absolute("user://saves/slot_20.json")


func test_open_world_state_round_trips() -> void:
	GameState.open_world_position = Transform3D(Basis(), Vector3(100, 2, -300))
	GameState.has_open_world_position = true
	GameState.activity_records = {"coin_race_skaa": {"completed": true, "best_time": 12.5, "medal": "gold", "attempts": 3}}
	GameState.collectibles = {"atium_bead_1": true}
	GameState.mastery_points = 4
	GameState.mastery_levels = {&"push_force": 2, &"tin_range": 1}

	assert_true(GameState.save_game(21))
	GameState.reset_run()
	assert_true(GameState.load_game(21))

	assert_true(GameState.has_open_world_position)
	assert_almost(GameState.open_world_position.origin.x, 100.0)
	assert_almost(GameState.open_world_position.origin.z, -300.0)
	assert_true(GameState.activity_record(&"coin_race_skaa")["completed"])
	assert_almost(float(GameState.activity_record(&"coin_race_skaa")["best_time"]), 12.5)
	assert_true(GameState.is_collected(&"atium_bead_1"))
	assert_eq(GameState.mastery_points, 4)
	assert_eq(GameState.mastery_level(&"push_force"), 2)
	assert_eq(GameState.mastery_level(&"tin_range"), 1)
	DirAccess.remove_absolute("user://saves/slot_21.json")


func test_collect_item_is_idempotent_and_persists() -> void:
	assert_true(GameState.collect_item(&"crew_note_2"))
	assert_false(GameState.collect_item(&"crew_note_2"), "second find does not re-grant")
	assert_true(GameState.is_collected(&"crew_note_2"))
