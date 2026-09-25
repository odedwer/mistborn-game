extends TestCase
## Perception: vision cone + line-of-sight raycast blocked by geometry.

const GuardScene := preload("res://src/enemies/guard.tscn")


func _make_wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at
	return wall


func test_sees_player_with_clear_line_of_sight() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(0, 0, -3)
	await physics_frames(2)
	assert_true(guard._can_perceive(player), "nothing should block line of sight here")


func test_wall_blocks_line_of_sight() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	_make_wall(Vector3(0, 1, -1.5))
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(0, 0, -3)
	await physics_frames(3)
	assert_false(guard._can_perceive(player), "a wall between the guard and player should block sight")


func test_target_outside_vision_cone_is_not_seen() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(0, 0, 5)  # directly behind the guard
	await physics_frames(2)
	assert_false(guard._can_perceive(player), "a target behind the guard should be outside its vision cone")


func test_target_beyond_vision_range_is_not_seen() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(0, 0, -(guard.vision_range_base + 5.0))
	await physics_frames(2)
	assert_false(guard._can_perceive(player), "a target far beyond vision range should not be seen")
