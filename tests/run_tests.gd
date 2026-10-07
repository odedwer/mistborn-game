extends SceneTree
## Headless test runner:
##   godot --headless -s res://tests/run_tests.gd [-- [filter] [options]]
## Runs every tests/test_*.gd whose name contains `filter`, file by file, each
## test method on a fresh instance. Exit code = number of failed tests.
## Options:
##   --claim-dir=<abs dir>  shard mode (tools/run_tests.sh): several runners
##       share the dir and each file is run by whichever runner claims it
##       first (an atomic mkdir), heaviest files first, so the shards balance
##       themselves.
##   --reverse, --shuffle=<seed>  run the files in another order (to check
##       that no file depends on what ran before it).
##   --test=<text>  only the test methods whose name contains <text> (to
##       bisect a failure or a leak at exit down to one test).
## Prints the time of every test over SLOW_TEST_MS, and a table of the
## slowest files and tests at the end (TEST_SLOWEST=<n> rows).


## Tests at or over this many milliseconds get their time printed after "ok".
const SLOW_TEST_MS := 2000
## How many rows of the slowest files / tests to print at the end
## (env TEST_SLOWEST overrides it, e.g. TEST_SLOWEST=1000 for all).
const SLOWEST_ROWS := 10
## Rough seconds per file (sequential, 4-core machine; see docs/PERFORMANCE.md),
## only used to start the heaviest files first in shard mode. Unlisted files
## count as light. Stale numbers only cost balance, never correctness.
const FILE_WEIGHTS := {
	"test_story_sweep.gd": 41.0,
	"test_traversal.gd": 40.0,
	"test_soak.gd": 31.0,
	"test_crowd_member.gd": 10.0,
	"test_characters.gd": 9.0,
	"test_e2e_mission.gd": 7.0,
	"test_scene_transition.gd": 6.0,
	"test_act3_missions.gd": 6.0,
	"test_player.gd": 5.0,
	"test_world_gen.gd": 4.0,
	"test_open_world_content.gd": 3.0,
	"test_npc_models.gd": 2.0,
	"test_activity_validation.gd": 2.0,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var claim_dir := ""
	var order := "name"
	var shuffle_seed := 0
	var test_filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--claim-dir="):
			claim_dir = a.trim_prefix("--claim-dir=")
		elif a.begins_with("--test="):
			test_filter = a.trim_prefix("--test=")
		elif a == "--reverse":
			order = "reverse"
		elif a.begins_with("--shuffle="):
			order = "shuffle"
			shuffle_seed = int(a.trim_prefix("--shuffle="))
		elif a.begins_with("--"):
			printerr("run_tests.gd: unknown option %s" % a)
			quit(1)
			return
		else:
			filter = a
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			if filter == "" or f.contains(filter):
				files.append(f)
	files.sort()
	if order == "reverse":
		files.reverse()
	elif order == "shuffle":
		var rng := RandomNumberGenerator.new()
		rng.seed = shuffle_seed
		for i in range(files.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := files[i]
			files[i] = files[j]
			files[j] = t
		print("file order (--shuffle=%d): %s" % [shuffle_seed, " ".join(files)])
	if claim_dir != "":
		# Heaviest first (stable for equal weights), so no shard is left
		# running a long file alone at the end.
		var by_weight := func(a: String, b: String) -> bool:
			var wa: float = FILE_WEIGHTS.get(a, 0.0)
			var wb: float = FILE_WEIGHTS.get(b, 0.0)
			return wa > wb if wa != wb else a < b
		files.sort_custom(by_weight)
	# Private per-run folder for saves and settings: parallel runs (other
	# worktrees) share user://, and must never touch each other's slots or
	# the player's own saves.
	var run_dir := "user://test_runs/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# Autoloads by node: this SceneTree script compiles before they exist.
	root.get_node("GameState").call("use_save_dir", run_dir + "/saves")
	root.get_node("GameSettings").set("settings_path", run_dir + "/settings.cfg")
	var passed := 0
	var failed := 0
	var suite_t0 := Time.get_ticks_msec()
	var file_times: Array = []  # [msec, file]
	var test_times: Array = []  # [msec, file::test]
	for f in files:
		if claim_dir != "" and DirAccess.make_dir_absolute(claim_dir.path_join(f)) != OK:
			continue  # another shard has it
		var file_t0 := Time.get_ticks_msec()
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			printerr("FAIL  %s: could not load" % f)
			failed += 1
			file_times.append([0, f])
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (test_filter != "" and not name.contains(test_filter)):
				continue
			var test_t0 := Time.get_ticks_msec()
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
			var test_ms := Time.get_ticks_msec() - test_t0
			test_times.append([test_ms, "%s::%s" % [f, name]])
			if test_ms >= SLOW_TEST_MS:
				print("      (%.1f s)" % (test_ms / 1000.0))
		file_times.append([Time.get_ticks_msec() - file_t0, f])
	print("\n%d passed, %d failed" % [passed, failed])
	if claim_dir != "":
		print("files run: %d" % file_times.size())  # checked by tools/run_tests.sh
	_print_timing(file_times, test_times, Time.get_ticks_msec() - suite_t0, claim_dir != "")
	_remove_tree(run_dir)
	DirAccess.remove_absolute("user://test_runs")  # only succeeds once empty
	# Sounds still playing would otherwise leak at exit (see
	# AudioManager.shutdown); tools/run_tests.sh fails a shard that leaks.
	await root.get_node("AudioManager").call("shutdown")
	quit(failed)


## Prints the slowest files and tests, one row per line with a "TIMEF" /
## "TIMET" prefix. A shard (`quiet`) prints only the rows, which
## tools/run_tests.sh merges into one table for the whole suite.
func _print_timing(file_times: Array, test_times: Array, total_ms: int, quiet: bool) -> void:
	var by_time := func(a: Array, b: Array) -> bool: return a[0] > b[0]
	file_times.sort_custom(by_time)
	test_times.sort_custom(by_time)
	var rows := int(OS.get_environment("TEST_SLOWEST")) if OS.has_environment("TEST_SLOWEST") else SLOWEST_ROWS
	print("Godot tests took %.1f s." % (total_ms / 1000.0))
	if not quiet:
		print("Slowest files:")
	for row in file_times.slice(0, rows):
		print("TIMEF %7.1f s  %s" % [row[0] / 1000.0, row[1]])
	if not quiet:
		print("Slowest tests:")
	for row in test_times.slice(0, rows):
		print("TIMET %7.1f s  %s" % [row[0] / 1000.0, row[1]])


## Deletes `dir` and everything under it.
static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir + "/" + sub)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
