extends TestCase
## AI tick throttling by distance to the player: full rate < 40m, ~5Hz
## 40-100m, and effectively asleep beyond 120m.

const GuardScene := preload("res://src/enemies/guard.tscn")


func test_ai_tick_interval_scales_with_distance() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)

	guard.global_position = Vector3.ZERO

	player.global_position = Vector3(10, 0, 0)
	await physics_frames(1)
	assert_eq(guard._ai_interval_for_distance(), 0.0, "close range should tick every physics frame")

	player.global_position = Vector3(60, 0, 0)
	assert_almost(guard._ai_interval_for_distance(), 0.2, 0.001, "mid range should throttle to ~5Hz")

	player.global_position = Vector3(150, 0, 0)
	assert_gt(guard._ai_interval_for_distance(), 1.0, "far beyond 120m should tick very rarely")


func test_ai_does_not_tick_faster_than_its_interval() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	guard.global_position = Vector3.ZERO
	player.global_position = Vector3(60, 0, 0)  # 0.2s interval

	var first_tick := guard._ai_should_tick(0.05)
	assert_false(first_tick, "should not tick before its throttled interval elapses")
	var second_tick := guard._ai_should_tick(0.2)
	assert_true(second_tick, "should tick once the accumulated time reaches the interval")
