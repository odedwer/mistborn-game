extends TestCase
## Player controller: pickups, allomantic forces, momentum, steel-jumping.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

var player: Player
var ground: StaticBody3D


func before_each() -> void:
	ground = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	ground.add_child(cs)
	add_child(ground)
	ground.global_position = Vector3(0, 999.5, 0)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = Vector3(0, 1000.05, 0)
	player.camera_rig.snap()


func test_scene_contract() -> void:
	assert_true(player.is_in_group(&"player"))
	assert_eq(player.collision_layer, 2)
	assert_eq(player.collision_mask, 1 | 4 | 8)
	assert_true(player.get_node(^"Allomancer") is Allomancer)
	assert_true(player.get_node(^"Health") is Health)
	assert_eq(player.allomancer.get_reserve(Metal.Type.STEEL), 100.0)
	assert_eq(player.allomancer.get_reserve(Metal.Type.BRONZE), 50.0)
	assert_eq(player.allomancer.get_reserve(Metal.Type.ZINC), 40.0)
	assert_eq(player.allomancer.get_reserve(Metal.Type.ATIUM), 0.0)
	assert_eq(player.coins, 60)
	assert_eq(player.get_allomantic_mass(), 60.0)


func test_add_pickup() -> void:
	var got := []
	var cb := func(kind: StringName, amount: float) -> void:
		got.append([kind, amount])
	Events.pickup_collected.connect(cb)
	player.add_pickup(&"coins", 10)
	player.add_pickup(&"vial", 1)
	player.add_pickup(&"atium", 25)
	player.add_pickup(&"duralumin", 30)
	player.health.take_damage(50.0)
	player.add_pickup(&"health", 20)
	Events.pickup_collected.disconnect(cb)
	assert_eq(player.coins, 70)
	assert_eq(player.vials, player.starting_vials + 1)
	assert_eq(player.allomancer.get_reserve(Metal.Type.ATIUM), 25.0)
	assert_eq(player.allomancer.get_reserve(Metal.Type.DURALUMIN), 30.0)
	assert_almost(player.health.current, 70.0)
	assert_eq(got.size(), 5)


func test_drink_vial_restores_basic_metals() -> void:
	player.allomancer.set_reserve(Metal.Type.STEEL, 10.0)
	player.allomancer.set_reserve(Metal.Type.TIN, 90.0)
	var before := player.vials
	assert_true(player.drink_vial())
	assert_eq(player.vials, before - 1)
	assert_almost(player.allomancer.get_reserve(Metal.Type.STEEL), 50.0)
	assert_almost(player.allomancer.get_reserve(Metal.Type.TIN), 100.0, 0.001, "clamped")


func test_receive_allomantic_force() -> void:
	player.velocity = Vector3.ZERO
	player.receive_allomantic_force(Vector3(600, 0, 0), 0.5, null)
	assert_almost(player.velocity.x, 5.0, 0.001, "F/m*dt")


func test_air_momentum_is_not_clamped() -> void:
	player.global_position = Vector3(0, 1100, 0)
	player.velocity = Vector3(40, 0, 0)
	await physics_frames(30)
	var h := Vector2(player.velocity.x, player.velocity.z).length()
	assert_gt(h, 39.9, "horizontal allomantic momentum kept in the air")


func test_velocity_cap() -> void:
	player.global_position = Vector3(0, 1100, 0)
	player.receive_allomantic_force(Vector3(0, 0, -1e6), 1.0, null)
	await physics_frames(2)
	assert_lt(player.velocity.length(), player.max_velocity + 0.01)


func test_steel_jump_off_dropped_coin() -> void:
	await physics_frames(10)
	assert_true(player.is_on_floor(), "starts grounded")
	var coin := player.drop_coin()
	assert_eq(player.coins, 59)
	await physics_frames(30)  # coin settles on the floor under the player
	player.allomancer.set_burning(Metal.Type.STEEL, true)
	for i in 20:
		player.allomancer.push(coin.metallic, 1.0, 1.0 / 60.0)
		await physics_frames(1)
	assert_gt(player.global_position.y, 1001.0, "launched upward off the coin")
	assert_gt(player.velocity.y, 5.0)
	CoinPool.get_for(self).recycle(coin)


func test_impact_damage_and_pewter() -> void:
	assert_eq(Player.impact_damage(10.0, 15.0, 7.0), 0.0)
	assert_almost(Player.impact_damage(25.0, 15.0, 7.0), 70.0)
	# A real fall: drop from 40 m onto the ground.
	player.global_position = Vector3(0, 1040, 0)
	player.velocity = Vector3(0, -32, 0)
	await physics_frames(90)
	assert_lt(player.health.current, 100.0, "hard landing hurts")
	var hp := player.health.current
	player.allomancer.set_burning(Metal.Type.PEWTER, true)
	player.global_position = Vector3(0, 1040, 0)
	player.velocity = Vector3(0, -32, 0)
	await physics_frames(90)
	assert_almost(player.health.current, hp, 0.5, "pewter prevents fall damage")
