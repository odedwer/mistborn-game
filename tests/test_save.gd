extends TestCase
## GameState save/load roundtrip and versioning.


func before_each() -> void:
	GameState.reset_run()


func test_save_load_roundtrip() -> void:
	GameState.mission_id = &"mistwalk_to_keep_venture"
	GameState.mission_stage = 2
	GameState.completed_objectives = [&"rooftop_lesson_1", &"cp_1"]
	GameState.last_checkpoint_id = &"cp_2"
	GameState.last_checkpoint_transform = Transform3D(Basis(), Vector3(10, 2, -5))
	GameState.checkpoint_reserves = {Metal.Type.STEEL: 50.0, Metal.Type.PEWTER: 80.0}
	GameState.checkpoint_coins = 12
	GameState.checkpoint_vials = 3
	GameState.checkpoint_health = 65.0
	GameState.stat_kills = 4
	GameState.stat_deaths = 1
	GameState.completed_missions = [&"tutorial"]

	assert_true(GameState.save_game(9))

	GameState.reset_run()
	assert_true(GameState.load_game(9))

	assert_eq(GameState.mission_id, &"mistwalk_to_keep_venture")
	assert_eq(GameState.mission_stage, 2)
	assert_true(GameState.completed_objectives.has(&"rooftop_lesson_1"))
	assert_eq(GameState.last_checkpoint_id, &"cp_2")
	assert_almost(GameState.last_checkpoint_transform.origin.x, 10.0)
	assert_almost(GameState.checkpoint_reserves.get(Metal.Type.STEEL, 0.0), 50.0)
	assert_eq(GameState.checkpoint_coins, 12)
	assert_eq(GameState.stat_kills, 4)
	assert_eq(GameState.stat_deaths, 1)
	assert_true(GameState.completed_missions.has(&"tutorial"))

	DirAccess.remove_absolute("user://saves/slot_9.json")


func test_load_missing_slot_returns_false() -> void:
	assert_false(GameState.load_game(999))


func test_has_save_reflects_disk_state() -> void:
	GameState.save_game(8)
	assert_true(GameState.has_save(8))
	DirAccess.remove_absolute("user://saves/slot_8.json")
	assert_false(GameState.has_save(8))


func test_latest_slot_picks_most_recent() -> void:
	GameState.save_game(6)
	await get_tree().create_timer(1.1).timeout
	GameState.save_game(7)
	assert_eq(GameState.latest_slot(), 7)
	DirAccess.remove_absolute("user://saves/slot_6.json")
	DirAccess.remove_absolute("user://saves/slot_7.json")


func test_save_version_is_stamped() -> void:
	GameState.save_game(5)
	var f := FileAccess.open("user://saves/slot_5.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert_eq(int(parsed.get("version", -1)), GameState.SAVE_VERSION)
	DirAccess.remove_absolute("user://saves/slot_5.json")
