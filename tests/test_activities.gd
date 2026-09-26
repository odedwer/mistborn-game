extends TestCase
## ActivityManager: data loading and the start/complete/fail lifecycle for
## coin races, rooftop pursuits and obligator ambushes.

var _mgr: ActivityManager


func before_each() -> void:
	GameState.reset_run()
	_mgr = ActivityManager.new()
	add_child(_mgr)


func after_each() -> void:
	_mgr.queue_free()
	if FileAccess.file_exists("user://saves/slot_99.json"):
		DirAccess.remove_absolute("user://saves/slot_99.json")


func _fake_player() -> Node3D:
	var p := Node3D.new()
	p.add_to_group(&"player")
	add_child(p)
	return p


func test_loads_activity_data() -> void:
	assert_true(_mgr.activities.has(&"coin_race_skaa"))
	assert_true(_mgr.activities.has(&"pursuit_skaa"))
	assert_true(_mgr.activities.has(&"ambush_market"))
	var a: ActivityData = _mgr.activities[&"coin_race_skaa"]
	assert_eq(String(a.type), "coin_race")
	assert_true(a.params.has("ring_offsets"))


func test_medal_thresholds() -> void:
	assert_eq(_mgr.medal_for_time(&"coin_race_skaa", 10.0), &"gold")
	assert_eq(_mgr.medal_for_time(&"coin_race_skaa", 18.0), &"silver")
	assert_eq(_mgr.medal_for_time(&"coin_race_skaa", 23.0), &"bronze")
	assert_eq(_mgr.medal_for_time(&"coin_race_skaa", 99.0), &"")


func test_coin_race_start_and_complete_all_rings() -> void:
	var player := _fake_player()
	assert_true(_mgr.start_activity(&"coin_race_skaa", Vector3(100, 0, 100)))
	assert_true(_mgr.is_running(&"coin_race_skaa"))
	var st: Dictionary = _mgr._active[&"coin_race_skaa"]
	var rings: Array = st["rings"]
	assert_eq(rings.size(), 5)
	var got_complete := [false]
	_mgr.activity_completed.connect(func(id, _medal, _t): got_complete[0] = (id == &"coin_race_skaa"))
	for i in rings.size():
		# Entering out of order (skip ahead) must not count.
		if i == 0:
			_mgr._on_ring_entered(player, &"coin_race_skaa", 2)
			assert_true(_mgr.is_running(&"coin_race_skaa"), "out-of-order ring ignored")
		_mgr._on_ring_entered(player, &"coin_race_skaa", i)
	assert_true(got_complete[0])
	assert_false(_mgr.is_running(&"coin_race_skaa"))
	var rec := GameState.activity_record(&"coin_race_skaa")
	assert_true(rec["completed"])
	assert_eq(rec["medal"], "gold")
	player.queue_free()


func test_coin_race_times_out_and_fails() -> void:
	_mgr.start_activity(&"coin_race_skaa", Vector3.ZERO)
	var got_failed := [false]
	_mgr.activity_failed.connect(func(id, _reason): got_failed[0] = (id == &"coin_race_skaa"))
	_mgr._tick_activity(&"coin_race_skaa", 999.0, Vector3.INF)
	assert_true(got_failed[0])
	assert_false(_mgr.is_running(&"coin_race_skaa"))
	var rec := GameState.activity_record(&"coin_race_skaa")
	assert_false(rec["completed"])
	assert_eq(int(rec["attempts"]), 1)


func test_activity_cooldown_prevents_immediate_restart() -> void:
	_mgr.start_activity(&"coin_race_skaa", Vector3.ZERO)
	_mgr.fail_activity(&"coin_race_skaa", "test")
	assert_false(_mgr.start_activity(&"coin_race_skaa", Vector3.ZERO), "cooling down")


func test_rooftop_pursuit_catch_completes() -> void:
	assert_true(_mgr.start_activity(&"pursuit_skaa", Vector3(50, 0, 50)))
	var st: Dictionary = _mgr._active[&"pursuit_skaa"]
	var thief: Node3D = st["thief"]
	var got_complete := [false]
	_mgr.activity_completed.connect(func(id, _medal, _t): got_complete[0] = (id == &"pursuit_skaa"))
	_mgr._tick_activity(&"pursuit_skaa", 0.1, thief.global_position)
	assert_true(got_complete[0])


func test_rooftop_pursuit_thief_escape_fails() -> void:
	assert_true(_mgr.start_activity(&"pursuit_skaa", Vector3(50, 0, 50)))
	var st: Dictionary = _mgr._active[&"pursuit_skaa"]
	var thief: ThiefRunner = st["thief"]
	thief._seg = 999  # force reached_end()
	var got_failed := [false]
	_mgr.activity_failed.connect(func(id, reason): got_failed[0] = (id == &"pursuit_skaa" and reason == "thief_escaped"))
	_mgr._tick_activity(&"pursuit_skaa", 0.1, Vector3(999, 999, 999))
	assert_true(got_failed[0])


func _fake_spawner() -> Node:
	var spawner := Node.new()
	spawner.add_to_group(&"enemy_spawner")
	var src := "extends Node\nfunc spawn_type(_t, at):\n\tvar e := Node3D.new()\n\tvar h := Node.new()\n\th.name = \"Health\"\n\th.set_script(load(\"res://src/combat/health.gd\"))\n\te.add_child(h)\n\tadd_child(e)\n\te.global_position = at.global_position\n\treturn e\n"
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	spawner.set_script(script)
	add_child(spawner)
	return spawner


func test_obligator_ambush_completes_when_all_defeated() -> void:
	var spawner := _fake_spawner()
	assert_true(_mgr.start_activity(&"ambush_market", Vector3(20, 0, 20)))
	var st: Dictionary = _mgr._active[&"ambush_market"]
	var alive: Array = st["alive"]
	assert_eq(alive.size(), 3)
	var got_complete := [false]
	_mgr.activity_completed.connect(func(id, _medal, _t): got_complete[0] = (id == &"ambush_market"))
	for enemy in alive.duplicate():
		var h: Health = enemy.get_node(^"Health")
		h.take_damage(10000.0)
	assert_true(got_complete[0])
	spawner.queue_free()


func test_loads_act2_activities() -> void:
	assert_true(_mgr.activities.has(&"obligator_courier_intercept"))
	assert_true(_mgr.activities.has(&"soothing_riots"))
	assert_true(_mgr.activities.has(&"noble_carriage_heist"))
	assert_eq(String(_mgr.activities[&"soothing_riots"].type), "crowd_riot")


## "Soothing riots" (Act II): a `CrowdMoodMeter` starts already boiling over;
## soothing it below `calm_threshold` completes the activity.
func test_crowd_riot_start_and_soothe_completes() -> void:
	assert_true(_mgr.start_activity(&"soothing_riots", Vector3(30, 0, 30)))
	assert_true(_mgr.is_running(&"soothing_riots"))
	var st: Dictionary = _mgr._active[&"soothing_riots"]
	var meter: CrowdMoodMeter = st["meter"]
	assert_true(meter.mood > 70.0, "riot should start already boiling over")
	var got_complete := [false]
	_mgr.activity_completed.connect(func(id, _medal, _t): got_complete[0] = (id == &"soothing_riots"))
	meter.apply(&"soothe", 1.0)
	meter.apply(&"soothe", 1.0)
	meter.apply(&"soothe", 1.0)
	meter.apply(&"soothe", 1.0)
	meter.apply(&"soothe", 1.0)
	_mgr._tick_activity(&"soothing_riots", 0.1, Vector3.INF)
	assert_true(got_complete[0])
	assert_false(_mgr.is_running(&"soothing_riots"))


func test_crowd_riot_times_out_and_fails() -> void:
	_mgr.start_activity(&"soothing_riots", Vector3.ZERO)
	var got_failed := [false]
	_mgr.activity_failed.connect(func(id, _reason): got_failed[0] = (id == &"soothing_riots"))
	_mgr._tick_activity(&"soothing_riots", 999.0, Vector3.INF)
	assert_true(got_failed[0])


func test_collectible_marker_grants_and_persists() -> void:
	var marker := Node3D.new()
	marker.add_to_group(&"collectible_spawn")
	marker.set_meta("collectible_id", &"crew_note_1")
	marker.set_meta("collectible_kind", &"crew_note")
	add_child(marker)
	_mgr._spawn_collectibles([marker])
	assert_true(_mgr._collectible_nodes.has("crew_note_1"))
	var player := _fake_player()
	var got := [false]
	_mgr.collectible_found.connect(func(id, _kind): got[0] = (id == &"crew_note_1"))
	_mgr._on_collectible_entered(player, "crew_note_1", &"crew_note")
	assert_true(got[0])
	assert_true(GameState.is_collected(&"crew_note_1"))
	# Re-entering the same id (already collected) must not re-grant.
	got[0] = false
	_mgr._on_collectible_entered(player, "crew_note_1", &"crew_note")
	assert_false(got[0])
	player.queue_free()
	marker.queue_free()
