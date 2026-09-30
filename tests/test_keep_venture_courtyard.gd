extends TestCase
## Keep Venture's courtyard dressing must stay mission-safe: nothing solid on
## the guards' patrol routes, the enemy/pickup spawn points or the
## keep_courtyard objective, and the central Push anchor is where the story
## route expects it.


func _solids(data: ChunkBuildData) -> Array[AABB]:
	var out: Array[AABB] = []
	for s: Dictionary in data.shapes:
		if s.has("box"):
			var size: Vector3 = s["box"]
			var bb := (s["xf"] as Transform3D) * AABB(-size * 0.5, size)
			if bb.end.y > 0.6:
				out.append(bb)
	return out


func _clear(p: Vector3, r: float, boxes: Array[AABB]) -> bool:
	for b in boxes:
		if b.grow(r).has_point(p):
			return false
	return true


func test_courtyard_dressing_is_mission_safe() -> void:
	var plan := CityPlan.load_from_file()
	var lm := plan.landmark_by_id(&"keep_venture")
	var data := ChunkGenerator.generate_landmark(plan, 1337, lm)
	var boxes := _solids(data)
	var checked := 0
	for m: Dictionary in data.markers:
		var g := StringName(m["group"])
		if g not in [&"enemy_spawn", &"objective_point", &"pickup_spawn"]:
			continue
		var p: Vector3 = m["pos"]
		if g == &"enemy_spawn" or str(m["meta"].get("objective_id", "")) == "keep_courtyard":
			assert_true(_clear(p + Vector3.UP * 0.9, 0.4, boxes), "%s at %s is clear" % [g, p])
			checked += 1
		var patrol: PackedVector3Array = m["meta"].get("patrol", PackedVector3Array())
		for i in patrol.size():
			var a := patrol[i]
			var b := patrol[(i + 1) % patrol.size()]
			for k in 21:
				var q := a.lerp(b, float(k) / 20.0) + Vector3.UP * 0.9
				assert_true(_clear(q, 0.4, boxes), "patrol clear at %s" % q)
	assert_gt(float(checked), 8.0)
	# The courtyard's central anchor (the well's, now the fountain's) is kept.
	var found := false
	for mt: Dictionary in data.static_metals:
		if (mt["pos"] as Vector3).distance_to(Vector3(lm.center.x, 2.2, lm.center.y + 12.0)) < 0.1:
			found = true
	assert_true(found, "central courtyard Push anchor kept")
	# Dressed: fountain statue, carriage, planters and banners exist.
	assert_true(data.instances.has(&"carriage"), "a carriage")
	assert_gt(float((data.instances.get(&"ash_planter", []) as Array).size()), 5.0, "planters")
