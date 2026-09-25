extends SceneTree
## CPU frame-time probe of the full game (see tests/perf_probe.gd).
##   godot --headless -s res://tools/perf.gd -- [bisect]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var probe: Node = (load("res://tests/perf_probe.gd") as GDScript).new()
	probe.bisect = args.has("bisect")
	probe.timeline = args.has("timeline")
	probe.micro = args.has("micro")
	root.add_child(probe)
	var rep: Dictionary = await probe.finished
	print("\nlocation          process  physics  max    lines metals enemies")
	for loc: String in rep:
		var e: Dictionary = rep[loc]
		var b: Dictionary = e["base"]
		print("%-16s %7.2f %8.2f %6.1f %6d %6d %6d" % [loc, b["process"], b["physics"], b["max"], e["lines"],
				e["metals"], e["enemies"]])
		for k: String in e:
			if k.begins_with("without_"):
				var m: Dictionary = e[k]
				print("   %-22s %7.2f %8.2f" % [k, m["process"], m["physics"]])
	probe.queue_free()
	await process_frame
	quit()
