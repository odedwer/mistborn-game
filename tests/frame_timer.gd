extends RefCounted
## Per-frame CPU timing from SceneTree signals (headless: no render cost).
## Each main-loop iteration runs 0..n physics steps (each starts with
## `physics_frame`, then scripts, then the Jolt step) and then one process
## frame (`process_frame`, then scripts). So:
##   physics time = first physics_frame of the iteration -> process_frame
##   process time = process_frame -> the next iteration's first event.
## Unlike Performance.TIME_* (a max over the last second), this gives true
## per-frame averages and maxima.

var tree: SceneTree
var frames := 0
var physics_steps := 0
var total_process_ms := 0.0
var total_physics_ms := 0.0
var max_frame_ms := 0.0
var max_physics_ms := 0.0
var max_process_ms := 0.0
## Frames whose process+physics exceeded `hitch_ms`.
var hitches := 0
var hitch_ms := 30.0
var paused := false
## Optional: called as hitch_hook.call(process_ms, physics_ms) on a hitch.
var hitch_hook: Callable

var _t_proc := -1
var _t_phys := -1
var _steps := 0
var _last_proc_ms := 0.0
## Time (usec) the last physics script ran (set by an end-of-physics marker
## node), to split script time from the engine's physics step.
var script_end_usec := -1
## Script part of the last hitching physics tick (ms).
var last_phys_scripts_ms := 0.0


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	# Headless (no drawable window) sleeps low_processor_usage_mode_sleep_usec
	# (~7 ms) every frame;
	# that sleep would otherwise be counted as process time.
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	tree.physics_frame.connect(_on_physics)
	tree.process_frame.connect(_on_process)


func stop() -> void:
	hitch_hook = Callable()  # break the timer <-> hook reference cycle
	if tree.physics_frame.is_connected(_on_physics):
		tree.physics_frame.disconnect(_on_physics)
	if tree.process_frame.is_connected(_on_process):
		tree.process_frame.disconnect(_on_process)


func reset() -> void:
	frames = 0
	physics_steps = 0
	total_process_ms = 0.0
	total_physics_ms = 0.0
	max_frame_ms = 0.0
	max_physics_ms = 0.0
	max_process_ms = 0.0
	hitches = 0


func _close_process(now: int) -> void:
	if _t_proc >= 0:
		_last_proc_ms = float(now - _t_proc) / 1000.0
		_t_proc = -1


func _on_physics() -> void:
	var now := Time.get_ticks_usec()
	_close_process(now)
	if _t_phys < 0:
		_t_phys = now
	_steps += 1


func _on_process() -> void:
	var now := Time.get_ticks_usec()
	var phys := 0.0
	if _t_phys >= 0:
		phys = float(now - _t_phys) / 1000.0
	else:
		_close_process(now)
	var proc := _last_proc_ms
	last_phys_scripts_ms = float(script_end_usec - _t_phys) / 1000.0 if _t_phys >= 0 and script_end_usec > _t_phys else -1.0
	if not paused:
		frames += 1
		physics_steps += _steps
		total_process_ms += proc
		total_physics_ms += phys
		max_frame_ms = maxf(max_frame_ms, proc + phys)
		max_physics_ms = maxf(max_physics_ms, phys / maxf(float(_steps), 1.0))
		max_process_ms = maxf(max_process_ms, proc)
		if proc + phys > hitch_ms:
			hitches += 1
			if hitch_hook.is_valid():
				hitch_hook.call(proc, phys)
	_t_phys = -1
	_steps = 0
	_last_proc_ms = 0.0
	_t_proc = now


func summary() -> Dictionary:
	var n := maxf(float(frames), 1.0)
	var steps := maxf(float(physics_steps), 1.0)
	return {
		"frames": frames,
		"avg_process_ms": total_process_ms / n,
		## Average cost of one 60 Hz physics tick.
		"avg_physics_tick_ms": total_physics_ms / steps,
		## Process + one physics tick: the per-frame cost at 60 fps.
		"avg_cpu_ms": total_process_ms / n + total_physics_ms / steps,
		"max_frame_ms": max_frame_ms,
		"max_physics_tick_ms": max_physics_ms,
		"max_process_ms": max_process_ms,
		"hitches": hitches,
	}
