extends TestCase
## Mastery: upgrade costs/levels and applying tuning values to a player.


func test_cost_and_level_progression() -> void:
	assert_eq(Mastery.max_level(&"push_force"), 2)
	assert_eq(Mastery.cost_for_next(&"push_force", 0), 1)
	assert_eq(Mastery.cost_for_next(&"push_force", 1), 2)
	assert_eq(Mastery.cost_for_next(&"push_force", 2), -1, "maxed")


func test_try_upgrade_fails_without_enough_points() -> void:
	var levels := {}
	var points := [1]
	assert_false(Mastery.try_upgrade(levels, points, &"steel_range"), "steel_range level 1 costs 2 points")
	assert_eq(int(levels.get(&"steel_range", 0)), 0)
	assert_eq(int(points[0]), 1, "points untouched on failure")


func test_try_upgrade_succeeds_with_enough_points() -> void:
	var levels := {}
	var points := [2]
	assert_true(Mastery.try_upgrade(levels, points, &"steel_range"))
	assert_eq(int(levels[&"steel_range"]), 1)
	assert_eq(int(points[0]), 0)


func test_apply_to_sets_allomancer_and_player_fields() -> void:
	var player: Node3D = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await physics_frames(1)
	var levels := {&"push_force": 2, &"steel_range": 1, &"coin_pouch": 1, &"vial_capacity": 1}
	Mastery.apply_to(player, levels)
	assert_almost(player.allomancer.base_force, Mastery.BASE_PUSH_FORCE * 1.20)
	assert_almost(player.allomancer.line_range, Mastery.BASE_LINE_RANGE * 1.15)
	assert_eq(player.coin_pouch_max, 320)
	assert_eq(player.vial_capacity_max, 8)
	# Reapplying with different (lower) levels must not compound: it resets
	# from the fixed base each time.
	Mastery.apply_to(player, {})
	assert_almost(player.allomancer.base_force, Mastery.BASE_PUSH_FORCE)
	assert_almost(player.allomancer.line_range, Mastery.BASE_LINE_RANGE)
	player.queue_free()


func test_flare_and_pewter_and_tin_hooks_applied() -> void:
	var player: Node3D = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await physics_frames(1)
	Mastery.apply_to(player, {&"flare_efficiency": 1, &"pewter_endurance": 1, &"tin_range": 1})
	assert_almost(player.allomancer.flare_burn_efficiency, 0.85)
	assert_almost(player.allomancer.pewter_burn_efficiency, 0.8)
	assert_almost(player.allomancer.tin_strength_mult, 1.2)
	player.queue_free()


func test_coin_pouch_and_vial_caps_clamp_pickups() -> void:
	var player: Node3D = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await physics_frames(1)
	player.coin_pouch_max = 10
	player.coins = 0
	player.call("add_pickup", &"coins", 999.0)
	assert_eq(player.coins, 10)
	player.vial_capacity_max = 2
	player.vials = 0
	player.call("add_pickup", &"vial", 999.0)
	assert_eq(player.vials, 2)
	player.queue_free()


func test_game_state_buy_mastery_persists_across_save_load() -> void:
	GameState.reset_run()
	GameState.mastery_points = 3
	assert_true(GameState.buy_mastery(&"tin_range"))
	assert_eq(GameState.mastery_points, 2)
	assert_eq(GameState.mastery_level(&"tin_range"), 1)
	assert_true(GameState.save_game(11))
	GameState.reset_run()
	assert_true(GameState.load_game(11))
	assert_eq(GameState.mastery_points, 2)
	assert_eq(GameState.mastery_level(&"tin_range"), 1)
	DirAccess.remove_absolute("user://saves/slot_11.json")
