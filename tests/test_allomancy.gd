extends TestCase
## Allomancer: Push/Pull physics, falloff, flaring, burn drain, duralumin.


## Minimal allomancer body: integrates allomantic forces into `velocity`.
class ForceBody:
	extends Node3D
	var velocity := Vector3.ZERO
	var mass := 60.0

	func get_allomantic_mass() -> float:
		return mass

	func receive_allomantic_force(force: Vector3, delta: float, _from: Metallic) -> void:
		velocity += force / mass * delta


var body: ForceBody
var allo: Allomancer


func before_each() -> void:
	body = ForceBody.new()
	add_child(body)
	body.global_position = Vector3(0, 50, 0)
	allo = Allomancer.new()
	allo.chest_offset = Vector3.ZERO
	body.add_child(allo)
	for m in Metal.COUNT:
		allo.set_reserve(m, 100.0)


func _anchored_metal(pos: Vector3, mass := 10.0) -> Metallic:
	var sb := StaticBody3D.new()
	add_child(sb)
	sb.global_position = pos
	var m := Metallic.new()
	m.metal_mass = mass
	sb.add_child(m)
	return m


func _rigid_metal(pos: Vector3, kg: float) -> Metallic:
	var rb := RigidBody3D.new()
	rb.mass = kg
	rb.gravity_scale = 0.0
	rb.collision_layer = 1 << 3
	rb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.1
	cs.shape = sh
	rb.add_child(cs)
	add_child(rb)
	rb.global_position = pos
	var m := Metallic.new()
	rb.add_child(m)
	return m


func test_push_on_anchored_metal_accelerates_allomancer_away() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var m := _anchored_metal(body.global_position + Vector3(0, -2, 0))
	var f := allo.push(m, 1.0, 1.0 / 60.0)
	assert_gt(f, 0.0, "force applied")
	assert_gt(body.velocity.y, 0.0, "pushed up, away from metal below")
	assert_almost(body.velocity.length(), f / 60.0 / 60.0, 0.0001, "full reaction F/m*dt")


func test_pull_on_anchored_metal_accelerates_toward_it() -> void:
	allo.set_burning(Metal.Type.IRON, true)
	var m := _anchored_metal(body.global_position + Vector3(5, 0, 0))
	allo.pull(m, 1.0, 1.0 / 60.0)
	assert_gt(body.velocity.x, 0.0, "pulled toward metal")


func test_push_requires_burning_steel() -> void:
	var m := _anchored_metal(body.global_position + Vector3(0, -2, 0))
	assert_eq(allo.push(m, 1.0, 0.016), 0.0)
	assert_eq(body.velocity, Vector3.ZERO)


func test_shielded_metal_cannot_be_pushed() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var m := _anchored_metal(body.global_position + Vector3(0, -2, 0))
	m.shielded = true
	assert_eq(allo.push(m, 1.0, 0.016), 0.0)


func test_push_on_light_rigid_body_moves_body_not_allomancer() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var m := _rigid_metal(body.global_position + Vector3(5, 0, 0), 0.1)
	await physics_frames(1)
	for i in 10:
		allo.push(m, 1.0, 1.0 / 60.0)
		await physics_frames(1)
	var rb := m.body as RigidBody3D
	assert_gt(rb.linear_velocity.x, 5.0, "coin flies away")
	assert_lt(body.velocity.length(), 0.1, "allomancer barely moves")


func test_heavy_rigid_body_splits_reaction_by_mass() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var m := _rigid_metal(body.global_position + Vector3(5, 0, 0), 60.0)
	allo.push(m, 1.0, 1.0 / 60.0)
	var f := allo.line_force(Metal.Type.STEEL, 5.0)
	assert_almost(body.velocity.length(), f * 0.5 / 60.0 / 60.0, 0.001, "equal masses share equally")
	assert_lt(body.velocity.x, 0.0, "recoil away from target")


func test_braced_coin_on_floor_gives_full_reaction() -> void:
	# Floor (layer 1) with a free coin resting on it, allomancer above.
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, 9.5, 0)
	var coin_metal := _rigid_metal(Vector3(0, 10.05, 0), 0.1)
	body.global_position = Vector3(0, 12, 0)
	allo.set_burning(Metal.Type.STEEL, true)
	await physics_frames(2)
	var brace := allo.brace_factor(coin_metal, Vector3.DOWN)
	assert_gt(brace, 0.9, "coin pressed into floor counts as braced")
	body.velocity = Vector3.ZERO
	var f := allo.push(coin_metal, 1.0, 1.0 / 60.0)
	assert_almost(body.velocity.y, f / 60.0 / 60.0, 0.001, "steel-jump gets full reaction")
	# Pushing sideways along the floor isn't braced.
	assert_lt(allo.brace_factor(coin_metal, Vector3.RIGHT), 0.1, "sideways push slides the coin")


func test_falloff_curve() -> void:
	assert_almost(Allomancer.falloff(0.0, 40.0, 3.0), 1.0)
	assert_almost(Allomancer.falloff(3.0, 40.0, 3.0), 1.0)
	assert_almost(Allomancer.falloff(40.0, 40.0, 3.0), 0.0)
	assert_almost(Allomancer.falloff(60.0, 40.0, 3.0), 0.0)
	var prev := 1.0
	for d in range(4, 40, 4):
		var v := Allomancer.falloff(float(d), 40.0, 3.0)
		assert_lt(v, prev, "monotonic at %d" % d)
		prev = v


func test_push_force_falls_off_with_distance() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var near := allo.push(_anchored_metal(body.global_position + Vector3(0, -2, 0)), 1.0, 0.016)
	var far := allo.push(_anchored_metal(body.global_position + Vector3(0, -30, 0)), 1.0, 0.016)
	var out := allo.push(_anchored_metal(body.global_position + Vector3(0, -45, 0)), 1.0, 0.016)
	assert_gt(near, far)
	assert_gt(far, 0.0)
	assert_eq(out, 0.0, "beyond range")


func test_flare_multiplies_force_and_range() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	var normal := allo.line_force(Metal.Type.STEEL, 2.0)
	allo.set_flaring(true)
	var flared := allo.line_force(Metal.Type.STEEL, 2.0)
	assert_almost(flared / normal, Metal.FLARE_EFFECT_MULT, 0.001)
	assert_almost(allo.current_range(), allo.line_range * allo.flare_range_mult)
	assert_almost(allo.effect_strength(Metal.Type.STEEL), Metal.FLARE_EFFECT_MULT)
	assert_eq(allo.effect_strength(Metal.Type.IRON), 0.0, "not burning -> 0")


func test_burn_drain_rates() -> void:
	allo.set_burning(Metal.Type.STEEL, true)
	allo.set_burning(Metal.Type.TIN, true)
	allo.tick(1.0)
	assert_almost(allo.get_reserve(Metal.Type.STEEL), 100.0 - Metal.BURN_RATE[Metal.Type.STEEL], 0.001)
	assert_almost(allo.get_reserve(Metal.Type.TIN), 100.0 - Metal.BURN_RATE[Metal.Type.TIN], 0.001)
	assert_almost(allo.get_reserve(Metal.Type.IRON), 100.0, 0.001, "not burning, no drain")
	allo.set_flaring(true)
	allo.tick(1.0)
	assert_almost(allo.get_reserve(Metal.Type.STEEL), 100.0 - Metal.BURN_RATE[Metal.Type.STEEL] * (1.0 + Metal.FLARE_BURN_MULT), 0.001)


func test_depletion_stops_burning_and_emits() -> void:
	var got := []
	var cb := func(a: Node, metal: int) -> void:
		if a == allo:
			got.append(metal)
	Events.metal_depleted.connect(cb)
	allo.set_reserve(Metal.Type.PEWTER, 1.0)
	allo.set_burning(Metal.Type.PEWTER, true)
	allo.tick(2.0)
	Events.metal_depleted.disconnect(cb)
	assert_eq(allo.get_reserve(Metal.Type.PEWTER), 0.0)
	assert_false(allo.is_burning(Metal.Type.PEWTER), "auto-stopped")
	assert_true(got.has(Metal.Type.PEWTER), "metal_depleted emitted")
	assert_false(allo.set_burning(Metal.Type.PEWTER, true), "can't burn an empty metal")


func test_reserve_clamp() -> void:
	assert_eq(allo.add_reserve(Metal.Type.STEEL, 500.0), Metal.MAX_RESERVE)
	assert_eq(allo.add_reserve(Metal.Type.STEEL, -500.0), 0.0)
	assert_eq(allo.set_reserve(Metal.Type.IRON, -3.0), 0.0)


func test_duralumin_burst_multiplies_then_empties_other_metals() -> void:
	allo.set_reserve(Metal.Type.STEEL, 50.0)
	allo.set_burning(Metal.Type.STEEL, true)
	allo.set_burning(Metal.Type.PEWTER, true)
	var bursts := []
	var cb := func(a: Node, metals: Array) -> void:
		if a == allo:
			bursts.append(metals)
	Events.duralumin_burst.connect(cb)
	var normal := allo.line_force(Metal.Type.STEEL, 2.0)
	assert_true(allo.burn_duralumin())
	Events.duralumin_burst.disconnect(cb)
	assert_eq(bursts.size(), 1)
	assert_true((bursts[0] as Array).has(Metal.Type.STEEL))
	assert_almost(allo.line_force(Metal.Type.STEEL, 2.0) / normal, Allomancer.DURALUMIN_MULT, 0.001, "x10 burst")
	assert_true(allo.is_duralumin_active())
	for i in 30:
		allo.tick(1.0 / 60.0)
	assert_false(allo.is_duralumin_active(), "burst over")
	assert_eq(allo.get_reserve(Metal.Type.STEEL), 0.0, "steel burned away")
	assert_eq(allo.get_reserve(Metal.Type.PEWTER), 0.0, "pewter burned away")
	assert_false(allo.is_burning(Metal.Type.STEEL))
	assert_gt(allo.get_reserve(Metal.Type.IRON), 99.0, "non-burning metal untouched")
	assert_lt(allo.get_reserve(Metal.Type.DURALUMIN), 100.0, "duralumin consumed")


func test_duralumin_needs_reserve_and_a_burning_metal() -> void:
	assert_false(allo.burn_duralumin(), "nothing else burning")
	allo.set_burning(Metal.Type.STEEL, true)
	allo.set_reserve(Metal.Type.DURALUMIN, 0.0)
	assert_false(allo.burn_duralumin(), "no duralumin")


func test_pewter_multipliers_and_damage_reduction() -> void:
	var h := Health.new()
	h.name = "Health"
	body.add_child(h)
	allo.bind_health(h)
	assert_eq(allo.speed_multiplier(), 1.0)
	h.take_damage(10.0)
	assert_almost(h.current, 90.0)
	allo.set_burning(Metal.Type.PEWTER, true)
	assert_almost(allo.speed_multiplier(), 1.0 + allo.pewter_speed_bonus)
	h.take_damage(10.0)
	assert_almost(h.current, 85.0, 0.001, "50% reduction")
	assert_lt(allo.get_reserve(Metal.Type.PEWTER), 100.0, "absorbing costs pewter")
	allo.set_flaring(true)
	h.take_damage(10.0)
	assert_almost(h.current, 82.0, 0.001, "70% reduction flared")


func test_tin_strength() -> void:
	assert_eq(allo.tin_strength(), 0.0)
	allo.set_burning(Metal.Type.TIN, true)
	assert_gt(allo.tin_strength(), 0.5)
	allo.set_flaring(true)
	assert_almost(allo.tin_strength(), 1.0)


func test_lines_in_range_excludes_own_and_far_metals() -> void:
	var near := _anchored_metal(body.global_position + Vector3(10, 0, 0))
	var far := _anchored_metal(body.global_position + Vector3(80, 0, 0))
	var own := Metallic.new()
	body.add_child(own)
	assert_eq(allo.lines_in_range(true).size(), 0, "no lines unless steel/iron burns")
	allo.set_burning(Metal.Type.IRON, true)
	var lines := allo.lines_in_range(true)
	assert_true(lines.has(near))
	assert_false(lines.has(far))
	assert_false(lines.has(own), "own metal excluded")


func test_bronze_senses_other_pulses_unless_copper() -> void:
	allo.set_burning(Metal.Type.BRONZE, true)
	var other := Node3D.new()
	add_child(other)
	Events.allomantic_pulse.emit(other, Metal.Type.STEEL, Vector3(1, 2, 3))
	var p := allo.get_recent_pulses()
	assert_eq(p.size(), 1)
	assert_eq(p[0]["source"], other)
	# A coppercloud allomancer emits no pulses.
	var hits := []
	var cb := func(src: Node, _m: int, _p: Vector3) -> void:
		if src == body:
			hits.append(1)
	Events.allomantic_pulse.connect(cb)
	allo.set_burning(Metal.Type.COPPER, true)
	allo.tick(allo.pulse_interval + 0.01)
	var with_copper := hits.size()
	allo.set_burning(Metal.Type.COPPER, false)
	allo.tick(allo.pulse_interval + 0.01)
	Events.allomantic_pulse.disconnect(cb)
	assert_eq(with_copper, 0, "copper hides pulses")
	assert_gt(hits.size(), 0, "pulses without copper")
