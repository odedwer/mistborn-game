extends SceneTree
## Headless robustness/perf soak of the full game (see tests/soak_bot.gd).
##   godot --headless -s res://tools/soak.gd -- [frames] [report.json]
## Prints a summary; the full report is written as JSON if a path is given.
## Exit code: number of errors + leak/robustness violations.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var bot: Node = (load("res://tests/soak_bot.gd") as GDScript).new()
	bot.frames = int(args[0]) if args.size() > 0 else 3000
	bot.name = "SoakBot"
	root.add_child(bot)
	var rep: Dictionary = await bot.finished
	var out := JSON.stringify(rep, "  ")
	if args.size() > 1:
		var f := FileAccess.open(args[1], FileAccess.WRITE)
		f.store_string(out)
		f.close()
	print("\n=== soak: %d frames ===" % rep["frames"])
	for k: String in ["time_scale_violations", "fallen_enemies", "max_coin_nodes", "max_pool_active", "deaths",
			"objects_at_revisits", "orphans_at_revisits", "orphans_end", "objects_end", "atium_uses",
			"duralumin_uses", "coins_thrown", "hits", "metals", "enemies"]:
		print("%-22s %s" % [k, str(rep[k])])
	print("errors (%d):" % rep["errors"].size())
	var seen := {}
	for e: String in rep["errors"]:
		seen[e] = seen.get(e, 0) + 1
	for e: String in seen:
		print("  %dx %s" % [seen[e], e])
	print("warnings (%d):" % rep["warnings"].size())
	seen.clear()
	for e: String in rep["warnings"]:
		seen[e] = seen.get(e, 0) + 1
	for e: String in seen:
		print("  %dx %s" % [seen[e], e])
	print("cpu hitches > 30 ms (%d):" % rep["cpu_hitches"].size())
	for h: String in rep["cpu_hitches"]:
		print("  ", h)
	print("perf per stop (ms): avg process / avg physics / avg cpu / max cpu / max frame")
	var keys: Array = rep["perf"].keys()
	keys.sort()
	for k: String in keys:
		var p: Dictionary = rep["perf"][k]
		print("  %-22s %6.2f %6.2f %6.2f %7.1f %7.1f" % [k, p["avg_process_ms"], p["avg_physics_ms"],
				p["avg_cpu_ms"], p["max_cpu_ms"], p["max_frame_ms"]])
	var bad: int = rep["errors"].size() + rep["time_scale_violations"] + rep["fallen_enemies"].size()
	bot.queue_free()
	await process_frame
	quit(bad)
