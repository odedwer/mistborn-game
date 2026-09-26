extends TestCase
## `MassBattle` (Act III, "The Army in the Caves"): faction logic, morale,
## the active-agent cap and reinforcements. Driven with `step()` directly, no
## rendering needed.

const REBEL := MassBattle.Faction.REBEL
const GARRISON := MassBattle.Faction.GARRISON


func _battle() -> MassBattle:
	var b := MassBattle.new()
	b.set_simulating(false)  # tests step it by hand
	add_child(b)
	return b


func test_factions_are_mutually_hostile_but_not_to_themselves() -> void:
	assert_true(MassBattle.is_hostile(REBEL, GARRISON))
	assert_true(MassBattle.is_hostile(GARRISON, REBEL))
	assert_false(MassBattle.is_hostile(REBEL, REBEL))
	assert_false(MassBattle.is_hostile(GARRISON, GARRISON))


func test_soldiers_only_target_the_other_faction() -> void:
	var b := _battle()
	var r1 := b.spawn(REBEL, Vector3(0, 0, 0))
	b.spawn(REBEL, Vector3(1, 0, 0))
	var g := b.spawn(GARRISON, Vector3(0, 0, 6))
	b.step(0.05)
	assert_true(r1.target == g, "rebel should pick the garrison soldier, not an ally")
	assert_eq(r1.state, MassBattle.SoldierState.ENGAGE)


func test_active_agents_are_capped_and_overflow_queues_as_reserves() -> void:
	var b := _battle()
	b.max_active = 60
	b.spawn_block(REBEL, Vector3(0, 0, 20), 50)
	b.spawn_block(GARRISON, Vector3(0, 0, -20), 30)
	assert_eq(b.active_count(), 60, "never more than max_active simulated")
	assert_eq(b.reserve_count(GARRISON), 20)
	# Freeing slots lets reinforcements march in, still under the cap.
	b.damage_at(Vector3(0, 0, 20), 100.0, 9999.0, REBEL)
	b.step(0.05)
	assert_eq(b.reserve_count(GARRISON), 0)
	assert_true(b.active_count() <= 60)
	assert_eq(b.active_count(GARRISON), 30)


func test_outnumbered_soldier_loses_morale_and_routs() -> void:
	var b := _battle()
	b.damage = [0.0, 0.0]  # isolate morale from casualties
	var r := b.spawn(REBEL, Vector3.ZERO)
	for i in 6:
		b.spawn(GARRISON, Vector3(cos(i) * 3.0, 0, sin(i) * 3.0))
	var start := r.morale
	for i in 20:
		b.step(0.1)
	assert_lt(r.morale, start, "surrounded soldier should lose heart")
	for i in 200:
		b.step(0.1)
		if r.state == MassBattle.SoldierState.ROUT:
			break
	assert_eq(r.state, MassBattle.SoldierState.ROUT, "morale below the threshold should rout")


func test_morale_holds_with_no_enemies_near() -> void:
	var b := _battle()
	var r := b.spawn(REBEL, Vector3.ZERO)
	var start := r.morale
	for i in 30:
		b.step(0.1)
	assert_true(r.morale >= start, "an unthreatened soldier should not lose morale")


func test_ally_death_nearby_shakes_morale() -> void:
	var b := _battle()
	var a := b.spawn(REBEL, Vector3.ZERO)
	var victim := b.spawn(REBEL, Vector3(2, 0, 0))
	var before := a.morale
	b.damage_at(victim.pos, 0.5, 9999.0)
	assert_eq(victim.state, MassBattle.SoldierState.DEAD)
	assert_lt(a.morale, before)
	assert_eq(b.dead_count(REBEL), 1)


func test_damage_at_respects_faction_filter() -> void:
	var b := _battle()
	b.spawn(REBEL, Vector3.ZERO)
	b.spawn(GARRISON, Vector3(0.5, 0, 0))
	assert_eq(b.damage_at(Vector3.ZERO, 2.0, 9999.0, GARRISON), 1)
	assert_eq(b.dead_count(REBEL), 0)
	assert_eq(b.dead_count(GARRISON), 1)


func test_routers_escape_at_the_retreat_point_and_free_their_slot() -> void:
	var b := _battle()
	b.retreat_point[REBEL] = Vector3(0, 0, 5)
	var r := b.spawn(REBEL, Vector3(0, 0, 4))
	r.morale = 0.0
	r.state = MassBattle.SoldierState.ROUT
	for i in 40:
		b.step(0.1)
	assert_eq(b.escaped_count(REBEL), 1)
	assert_eq(b.active_count(REBEL), 0)


## The canon beat: Yeden's half-trained army breaks against the garrison.
func test_garrison_crushes_an_even_rebel_force() -> void:
	var b := _battle()
	var broken: Array = [-1]
	b.faction_broken.connect(func(f: int) -> void: if broken[0] < 0: broken[0] = f)
	b.advance_target[REBEL] = Vector3(0, 0, -20)
	b.advance_target[GARRISON] = Vector3(0, 0, 20)
	b.retreat_point[REBEL] = Vector3(0, 0, 40)
	b.retreat_point[GARRISON] = Vector3(0, 0, -40)
	b.spawn_block(REBEL, Vector3(0, 0, 8), 20)
	b.spawn_block(GARRISON, Vector3(0, 0, -8), 20)
	for i in 1500:
		b.step(0.1)
		if broken[0] >= 0:
			break
	assert_eq(broken[0], REBEL, "the rebels should break first")
	assert_gt(float(b.dead_count(REBEL) + b.escaped_count(REBEL)), float(b.dead_count(GARRISON)))


func test_drilling_soldiers_stay_put() -> void:
	var b := _battle()
	var s := b.spawn(REBEL, Vector3(3, 0, 3), MassBattle.SoldierState.DRILL)
	for i in 50:
		b.step(0.05)
	assert_lt(s.pos.distance_to(Vector3(3, 0, 3)), 0.6)
	assert_eq(s.state, MassBattle.SoldierState.DRILL)
