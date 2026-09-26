extends TestCase
## Robustness soak of the full game (tests/soak_bot.gd): a scripted bot flies
## the route (chunks stream in and out), throws/pushes/pulls coins, burns and
## flares every metal, uses duralumin and atium, drinks vials, gets hit,
## starts side activities, opens the pause menu, saves and loads. Asserts no
## engine/script errors or warnings, no leaks, no enemies lost below the
## world, a bounded coin pool and a normal time scale after atium.
## The full-length run with a perf report is `tools/soak.sh`.

const FRAMES := 1800


func after_each() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	GameState.reset_run()
	for slot: int in [8, GameState.AUTOSAVE_SLOT]:
		var path := "user://saves/slot_%d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_soak_full_game() -> void:
	GameState.reset_run()
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var bot: Node = (load("res://tests/soak_bot.gd") as GDScript).new()
	bot.frames = FRAMES
	add_child(bot)
	var rep: Dictionary = await bot.finished
	print("    soak: %d frames, coins thrown %d, atium %d, duralumin %d, activities %d, saves %d, loads %d, deaths %d" % [
			rep["frames"], rep["coins_thrown"], rep["atium_uses"], rep["duralumin_uses"],
			rep["activities_started"], rep["saves"], rep["loads"], rep["deaths"]])
	assert_eq(rep["frames"], FRAMES, "bot ran to the end")
	assert_eq(rep["errors"], [], "no engine/script errors")
	assert_eq(rep["warnings"], [], "no warnings")
	assert_eq(rep["time_scale_violations"], 0, "time scale back to 1 whenever atium isn't burning")
	assert_eq(rep["fallen_enemies"], [], "no enemy fell out of the world")
	assert_true(int(rep["max_coin_nodes"]) <= 256, "coin count stays within the pool cap (%d)" % rep["max_coin_nodes"])
	assert_gt(float(rep["coins_thrown"]), 100.0, "coins were thrown")
	assert_gt(float(rep["atium_uses"]), 0.0, "atium was used")
	assert_gt(float(rep["duralumin_uses"]), 0.0, "duralumin was used")
	assert_gt(float(rep["activities_started"]), 0.0, "side activities were started")
	var objs: Array = rep["objects_at_revisits"]
	if objs.size() >= 3:
		# Same places revisited: the object count must not keep climbing.
		assert_lt(float(objs[objs.size() - 1]), float(objs[1]) * 1.3, "no ObjectDB growth across revisits %s" % [objs])
	bot.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if orphans > orphans_before:
		Node.print_orphan_nodes()
	assert_true(orphans <= orphans_before, "no orphan nodes left behind (%d -> %d)" % [orphans_before, orphans])
