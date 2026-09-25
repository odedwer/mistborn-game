extends TestCase
## State transitions: patrol -> investigate on noise, -> combat on sight.

const GuardScene := preload("res://src/enemies/guard.tscn")


func test_patrol_transitions_to_investigate_on_noise() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	guard.set_patrol_points(PackedVector3Array([Vector3(5, 0, 0)]))
	await physics_frames(2)
	guard._change_state(EnemyBase.State.PATROL)
	Events.noise_emitted.emit(Vector3(1, 0, 0), 10.0, null)
	await physics_frames(2)
	assert_eq(guard.state, EnemyBase.State.INVESTIGATE, "guard should investigate a nearby noise")


func test_noise_outside_range_is_ignored() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO
	guard._change_state(EnemyBase.State.IDLE)
	await physics_frames(1)
	Events.noise_emitted.emit(Vector3(100, 0, 0), 5.0, null)
	await physics_frames(1)
	assert_eq(guard.state, EnemyBase.State.IDLE, "noise far beyond its loudness radius should be ignored")


func test_sees_player_and_enters_combat() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard.global_position = Vector3.ZERO

	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(0, 0, -3)  # directly ahead (forward is -Z)

	await physics_frames(2)
	guard._change_state(EnemyBase.State.INVESTIGATE)
	guard.investigate_point = Vector3(0, 0, -1)
	await physics_frames(3)
	assert_eq(guard.state, EnemyBase.State.COMBAT, "guard should spot the player in its vision cone and engage")


func test_riot_forces_combat_ignoring_flee() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.global_position = Vector3(20, 0, 20)
	await physics_frames(1)
	guard.receive_emotional_allomancy(&"riot", 1.0)
	await physics_frames(1)
	assert_eq(guard.state, EnemyBase.State.COMBAT, "riot should force combat even without line of sight")
	assert_true(guard._riled, "riot should mark the enemy as riled")


func test_soothe_returns_to_idle_and_suppresses_perception() -> void:
	var guard: EnemyBase = GuardScene.instantiate()
	add_child(guard)
	guard._change_state(EnemyBase.State.COMBAT)
	guard.receive_emotional_allomancy(&"soothe", 1.0)
	assert_eq(guard.state, EnemyBase.State.IDLE, "soothe should calm the enemy back to idle")
	assert_gt(guard._soothed_timer, 0.0, "soothe should set a cooldown before it can re-alert")
