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
	m2.position = Vector3(6, 0, 0)  # markers are identified by position

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


func test_chunk_reload_respawns_alive_but_not_killed() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var chunk := Node3D.new()
	add_child(chunk)
	var m := Marker3D.new()
	m.set_meta("enemy_type", &"guard")
	m.add_to_group(&"enemy_spawn")
	chunk.add_child(m)
	var e: Node = spawner.spawn_for_marker(m)
	assert_true(e != null)
	assert_true(spawner.spawn_for_marker(m) == null, "no duplicate while alive")
	# Chunk unloads (enemy freed with it), then reloads: enemy comes back.
	chunk.free()
	chunk = Node3D.new()
	add_child(chunk)
	m = Marker3D.new()
	m.set_meta("enemy_type", &"guard")
	chunk.add_child(m)
	e = spawner.spawn_for_marker(m)
	assert_true(e != null, "respawned after reload")
	Health.find_on(e).take_damage(10000.0)
	e.free()
	assert_true(spawner.spawn_for_marker(m) == null, "killed enemies stay dead")
	chunk.queue_free()


func test_spawn_type_without_marker_does_not_duplicate() -> void:
	var spawner := EnemySpawner.new()
	add_child(spawner)
	var root := Node3D.new()
	add_child(root)
	var m := Marker3D.new()
	m.set_meta("enemy_type", &"inquisitor")
	m.add_to_group(&"enemy_spawn")
	root.add_child(m)
	spawner.spawn_all(root)
	assert_eq(spawner.spawned_enemies().size(), 0, "inquisitor deferred")
	Events.objective_updated.emit(&"ledger", "", true)
	var again: Node = spawner.spawn_type(&"inquisitor")
	assert_eq(spawner.spawned_enemies().size(), 1, "objective hook + mission call spawn one inquisitor")
	assert_true(again == spawner.spawned_enemies()[0])
	root.queue_free()
