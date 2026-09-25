extends TestCase
## EnemySpawner: spawns the right type per marker, and defers the Inquisitor.

func test_spawner_spawns_correct_types() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var root := Node3D.new()
	add_child(root)

	var m1 := Marker3D.new()
	m1.set_meta("enemy_type", &"guard")
	m1.add_to_group(&"enemy_spawn")
	root.add_child(m1)

	var m2 := Marker3D.new()
	m2.set_meta("enemy_type", &"thug")
	m2.add_to_group(&"enemy_spawn")
	root.add_child(m2)

	spawner.spawn_all(root)
	await physics_frames(1)

	assert_eq(spawner.spawned_enemies().size(), 2, "should spawn one enemy per marker")
	var found_guard := false
	var found_thug := false
	for e in spawner.spawned_enemies():
		if e is Guard:
			found_guard = true
		if e is Thug:
			found_thug = true
	assert_true(found_guard, "should have spawned a Guard")
	assert_true(found_thug, "should have spawned a Thug")


func test_spawner_defers_inquisitor_until_objective_done() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var root := Node3D.new()
	add_child(root)

	var m := Marker3D.new()
	m.set_meta("enemy_type", &"inquisitor")
	m.add_to_group(&"enemy_spawn")
	root.add_child(m)

	spawner.spawn_all(root)
	await physics_frames(1)
	assert_eq(spawner.spawned_enemies().size(), 0, "inquisitor should be deferred until the ledger objective is done")

	Events.objective_updated.emit(&"ledger", "Recover the ledger", true)
	await physics_frames(1)
	assert_eq(spawner.spawned_enemies().size(), 1, "inquisitor should spawn once the ledger objective completes")
	assert_true(spawner.spawned_enemies()[0] is Inquisitor)


func test_spawner_applies_patrol_points() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var root := Node3D.new()
	add_child(root)

	var m := Marker3D.new()
	m.set_meta("enemy_type", &"guard")
	m.set_meta("patrol", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]))
	m.add_to_group(&"enemy_spawn")
	root.add_child(m)

	spawner.spawn_all(root)
	await physics_frames(1)
	var guard: Guard = spawner.spawned_enemies()[0]
	assert_eq(guard.patrol_points.size(), 2, "patrol points from the marker's meta should be applied")
