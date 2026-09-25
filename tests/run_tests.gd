extends SceneTree
## Headless test runner: godot --headless -s res://tests/run_tests.gd [-- filter]
## Exit code = number of failed tests (0 = success).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			if filter == "" or f.contains(filter):
				files.append(f)
	files.sort()
	var passed := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			printerr("FAIL  %s: could not load" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var tc: TestCase = script.new()
			root.add_child(tc)
			tc._current = "%s::%s" % [f, name]
			tc.before_each()
			await tc.call(name)
			tc.after_each()
			if tc._failures.is_empty():
				passed += 1
				print("ok    ", tc._current)
			else:
				failed += 1
				for msg in tc._failures:
					printerr("FAIL  ", msg)
			tc.queue_free()
			await process_frame
	print("\n%d passed, %d failed" % [passed, failed])
	quit(failed)
