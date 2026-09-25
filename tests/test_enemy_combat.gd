extends TestCase
## Per-type combat quirks: hazekiller shield, thug toughness, guard push, and
## the shared allomantic-force reaction on EnemyBase.

const GuardScene := preload("res://src/enemies/guard.tscn")
const HazekillerScene := preload("res://src/enemies/hazekiller.tscn")
const ThugScene := preload("res://src/enemies/thug.tscn")


func test_hazekiller_shield_blocks_frontal_coin_damage() -> void:
	var hk: EnemyBase = HazekillerScene.instantiate()
	add_child(hk)
	hk.rotation.y = 0.0  # forward is -Z
	var attacker := Node3D.new()
	add_child(attacker)
	attacker.global_position = hk.global_position + Vector3(0, 0, -5)  # in front
	await physics_frames(1)
	var dealt := hk.health.take_damage(10.0, attacker, &"coin")
	assert_almost(dealt, 1.0, 0.01, "frontal coin damage should be reduced by 90%")


func test_hazekiller_shield_does_not_block_from_behind() -> void:
	var hk: EnemyBase = HazekillerScene.instantiate()
	add_child(hk)
	hk.rotation.y = 0.0
	var attacker := Node3D.new()
	add_child(attacker)
	attacker.global_position = hk.global_position + Vector3(0, 0, 5)  # behind
	await physics_frames(1)
	var dealt := hk.health.take_damage(10.0, attacker, &"coin")
	assert_almost(dealt, 10.0, 0.01, "a coin from behind should not be blocked by the shield")


func test_thug_takes_less_blunt_and_blade_damage() -> void:
	var thug: EnemyBase = ThugScene.instantiate()
	add_child(thug)
	await physics_frames(1)
	var dealt_blunt := thug.health.take_damage(20.0, null, &"blunt")
	assert_almost(dealt_blunt, 10.0, 0.01, "thug should take half blunt damage")
	var dealt_coin := thug.health.take_damage(20.0, null, &"coin")
	assert_almost(dealt_coin, 20.0, 0.01, "thug toughness only reduces blunt/blade, not coins")


func test_guard_is_pushable_by_allomantic_force() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	await physics_frames(1)
	var before := guard.velocity
	var fake_source := Metallic.new()
	add_child(fake_source)
	guard.receive_allomantic_force(Vector3(500, 0, 0), 0.1, fake_source)
	assert_gt(guard.velocity.x, before.x, "a Push should increase the guard's velocity")


func test_strong_push_stuns_guard() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	await physics_frames(1)
	guard._change_state(EnemyBase.State.PATROL)
	var fake_source := Metallic.new()
	add_child(fake_source)
	guard.receive_allomantic_force(Vector3(0, 0, 5000), 0.1, fake_source)
	assert_eq(guard.state, EnemyBase.State.STUNNED, "a very strong push should knock the guard down")


func test_guard_has_unshielded_breastplate_metallic() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	await physics_frames(1)
	var metallic := guard.get_node_or_null(^"Metallic") as Metallic
	assert_true(metallic != null, "guard should carry a Metallic breastplate")
	assert_false(metallic.shielded, "the player must be able to Push/Pull a guard's breastplate")
	assert_almost(metallic.metal_mass, 12.0, 0.01)
