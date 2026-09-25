extends TestCase
## World generator tests: determinism, required markers, metal density,
## generation budget, spawn placement and streaming basics.

const REQUIRED_OBJECTIVES := [&"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1", &"cp_2", &"cp_3",
		&"keep_courtyard", &"ledger", &"extraction"]
## Budget for LuthadelWorld._ready (headless; the target machine is faster).
const READY_BUDGET_MS := 3000.0

static var _plan: CityPlan


func _get_plan() -> CityPlan:
	if _plan == null:
		_plan = CityPlan.load_from_file()
	return _plan


func _make_world(seed_value := 1337) -> LuthadelWorld:
	var w: LuthadelWorld = (load("res://src/world/luthadel.tscn") as PackedScene).instantiate()
	w.seed = seed_value
	w.build_far_lod = false
	add_child(w)
	return w


func test_plan_loads() -> void:
	var plan := _get_plan()
	assert_true(plan != null, "plan parsed")
	assert_gt(plan.landmarks.size(), 5, "landmarks")
	assert_true(plan.landmark_by_id(&"keep_venture") != null, "Keep Venture in plan")
	assert_true(plan.landmark_by_id(&"kredik_shaw") != null, "Kredik Shaw in plan")
	assert_true(plan.inside_city(Vector2(0, 0)), "slice is inside the wall")
	assert_false(plan.inside_city(Vector2(2150, 1100)), "outside the wall")
	# Keep the city within +-3 km of the origin (32-bit float precision).
	assert_lt(maxf(absf(plan.bounds.position.x), absf(plan.bounds.end.x)), 3000.0)
	assert_lt(maxf(absf(plan.bounds.position.y), absf(plan.bounds.end.y)), 3000.0)


func test_layout_is_deterministic() -> void:
	var plan := _get_plan()
	for c: Vector2i in [Vector2i(-1, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-5, -7)]:
		var a := ChunkLayout.generate(plan, 1337, c)
		var b := ChunkLayout.generate(plan, 1337, c)
		assert_eq(a.signature(), b.signature(), "same seed, same chunk %s" % c)
	var x := ChunkLayout.generate(plan, 1337, Vector2i(-1, 0))
	var y := ChunkLayout.generate(plan, 99, Vector2i(-1, 0))
	assert_true(x.signature() != y.signature(), "different seeds differ")


func test_chunk_build_is_deterministic() -> void:
	var plan := _get_plan()
	var a := ChunkGenerator.generate_chunk(plan, 7, Vector2i(-1, 0))
	var b := ChunkGenerator.generate_chunk(plan, 7, Vector2i(-1, 0))
	assert_eq(a.shapes.size(), b.shapes.size())
	assert_eq(a.metal_count, b.metal_count)
	assert_eq(a.nav_faces.size(), b.nav_faces.size())
	var va: WorldMeshBuilder = a.builders[WorldMaterials.Mat.STONE]
	var vb: WorldMeshBuilder = b.builders[WorldMaterials.Mat.STONE]
	assert_eq(hash(va.verts), hash(vb.verts), "identical geometry")


func test_boundary_streets_agree() -> void:
	# Neighbouring chunks must agree on the width of the street they share.
	var plan := _get_plan()
	var w1 := ChunkLayout.boundary_width(plan, 5, true, 1, 0)
	var w2 := ChunkLayout.boundary_width(plan, 5, true, 1, 0)
	assert_eq(w1, w2)
	var L0 := ChunkLayout.generate(plan, 5, Vector2i(0, 0))
	var L1 := ChunkLayout.generate(plan, 5, Vector2i(1, 0))
	for a in L0.lots:
		assert_true(a.rect.end.x <= L1.rect.position.x - w1 * 0.5 + 0.01, "lots stay off the shared street")


func test_world_generation() -> void:
	var t0 := Time.get_ticks_usec()
	var w := _make_world()
	var ready_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("    world _ready: %.0f ms, units %d, metals %d" % [ready_ms, w.streamer.unit_count(), MetalRegistry.count()])
	assert_lt(ready_ms, READY_BUDGET_MS, "generation time budget")
	# Required objective markers exist as data (even if not loaded).
	var ids := {}
	for e in w.get_marker_data(&"objective_point"):
		ids[e["meta"].get("objective_id", &"")] = e["position"]
	for id: StringName in REQUIRED_OBJECTIVES:
		assert_true(ids.has(id), "objective %s" % id)
	assert_eq(w.get_marker_data(&"player_spawn").size(), 1, "one player spawn")
	var enemies := w.get_marker_data(&"enemy_spawn")
	assert_true(enemies.size() >= 10, "enough enemy spawns (%d)" % enemies.size())
	var types := {}
	for e in enemies:
		types[e["meta"]["enemy_type"]] = true
		if e["meta"]["enemy_type"] == &"guard" and e["meta"].has("patrol"):
			assert_true((e["meta"]["patrol"] as PackedVector3Array).size() >= 2, "patrol waypoints")
	for t: StringName in [&"guard", &"hazekiller", &"thug", &"coinshot", &"inquisitor"]:
		assert_true(types.has(t), "enemy type %s" % t)
	var kinds := {}
	for e in w.get_marker_data(&"pickup_spawn"):
		kinds[e["meta"]["pickup_kind"]] = kinds.get(e["meta"]["pickup_kind"], 0) + 1
	assert_true(kinds.get(&"atium", 0) >= 3, "atium on the escape route")
	# Spawn: live marker node exists and sits on a roof near a metal.
	var spawns := w.get_markers(&"player_spawn")
	assert_eq(spawns.size(), 1, "player spawn node loaded")
	if spawns.size() == 1:
		var sp := spawns[0].global_position
		assert_gt(sp.y, 8.0, "spawn is on a rooftop")
		var q := PhysicsRayQueryParameters3D.create(sp + Vector3.UP, sp + Vector3.DOWN * 3.0, 1)
		await physics_frames(2)
		var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
		assert_false(hit.is_empty(), "roof collider under the spawn")
		var near := MetalRegistry.query_radius(sp, 25.0)
		var has_lamp := false
		for m in near:
			if m.metal_mass >= 60.0 and m.anchored:
				has_lamp = true
		assert_true(has_lamp, "lamp post within 25 m of spawn")
		var lesson: Array = w.get_marker_data(&"objective_point").filter(
				func(e: Dictionary) -> bool: return e["meta"].get("objective_id") == &"rooftop_lesson_1")
		assert_lt((lesson[0]["position"] as Vector3).distance_to(sp), 25.0, "lesson lamp near spawn")
	w.queue_free()
	await get_tree().process_frame


func test_slice_metal_density_and_streaming() -> void:
	var w := _make_world()
	w.streamer.fallback_focus = Vector3(0, 0, 0)
	w.streamer.load_radius = 260.0
	# Stream the whole slice district.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 500 and not w.streamer.is_busy():
			break
	var sb := w.slice_bounds()
	var n := 0
	for m in MetalRegistry.all():
		if is_instance_valid(m) and sb.has_point(m.global_position):
			n += 1
	print("    metals in slice district: %d (units %d)" % [n, w.streamer.unit_count()])
	assert_gt(n, 800.0, "enough metals for steel-pushing")
	assert_lt(n, 2200.0, "metal count stays reasonable")
	assert_true(w.streamer.is_loaded("lm:keep_venture"), "Keep Venture streamed in")
	assert_eq(w.get_markers(&"checkpoint").size(), 4, "cp_1..3 + extraction checkpoint areas")
	for a in w.get_markers(&"checkpoint"):
		assert_true(a is Area3D and (a as Area3D).collision_layer == 1 << 5, "checkpoint on trigger layer")
	# Unloading frees metals.
	var before := MetalRegistry.count()
	w.streamer.fallback_focus = Vector3(-1800, 0, -700)
	w.streamer.update_interval = 0.0
	# Unloading is spread over frames and depends on streamer load; wait for
	# it (bounded) instead of a fixed frame count.
	var t1 := Time.get_ticks_msec()
	while MetalRegistry.count() >= before and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
	assert_lt(float(MetalRegistry.count()), float(before), "unloaded chunks free their metals")
	w.queue_free()
	await get_tree().process_frame


func test_navigation_bakes() -> void:
	var w := _make_world()
	var done := [false]
	w.navigation_ready.connect(func() -> void: done[0] = true)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	assert_true(done[0], "navigation_ready emitted")
	await physics_frames(3)
	var sp := w.spawn_position()
	var map := w.get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(sp.x, 0, sp.z + 12))
	var b := NavigationServer3D.map_get_closest_point(map, Vector3(sp.x + 60, 0, sp.z - 60))
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	print("    nav regions %d, a %s, b %s, path %d" % [NavigationServer3D.map_get_regions(map).size(), a, b, path.size()])
	assert_gt(float(path.size()), 1.0, "street path found")
	w.queue_free()
	await get_tree().process_frame
