extends Node
## CPU frame-time probe for the full game (tools/perf.gd runs it). At each
## location it waits for streaming to settle, then measures the average and
## max of Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS with steel burning,
## and (optionally) bisects by disabling one subsystem at a time.

signal finished(report: Dictionary)

const GAME_SCENE := "res://scenes/game.tscn"

var bisect := false
var sample_frames := 180
var game: Node3D
var world: LuthadelWorld
var player: Player
var report := {}


func _ready() -> void:
	game = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child(game)
	world = game.get_node(^"World") as LuthadelWorld
	player = get_tree().get_first_node_in_group(&"player") as Player
	player.capture_mouse = false
	_run.call_deferred()


func _marker(id: String) -> Vector3:
	if id == "spawn":
		return world.spawn_position()
	for e: Dictionary in world.get_marker_data(&"objective_point"):
		if str((e["meta"] as Dictionary).get("objective_id", "")) == id:
			return e["position"]
	return Vector3.INF


func _hold(pos: Vector3) -> void:
	player.global_position = pos + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO


func _settle(pos: Vector3) -> void:
	_hold(pos)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not world.streamer.is_busy() and world.is_area_loaded(pos):
			break
	for i in 30:
		await get_tree().process_frame


func _measure(frames: int) -> Dictionary:
	var proc := 0.0
	var phys := 0.0
	var mx := 0.0
	var n := 0
	for i in frames:
		await get_tree().process_frame
		var a := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var b := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += a
		phys += b
		mx = maxf(mx, a + b)
		n += 1
	return {"process": proc / n, "physics": phys / n, "max": mx}


func _groups() -> Dictionary:
	var hud := game.get_node_or_null(^"HUD")
	return {
		"enemies": get_tree().get_nodes_in_group(&"enemy"),
		"hud": [hud] if hud != null else [],
		"streamer": [world.streamer],
		"far_lod": [world.far_lod] if world.far_lod != null else [],
		"mist": [world.mist],
		"steel_lines": [player.steel_lines],
		"player": [player],
		"pickups": get_tree().get_nodes_in_group(&"pickup"),
		"director": [game.get_node(^"MissionDirector")],
		"audio": [get_node(^"/root/AudioManager")],
	}


var timeline := false
var micro := false


func _bench(label: String, fn: Callable, n := 20) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		fn.call()
	print("  %-34s %8.3f ms" % [label, float(Time.get_ticks_usec() - t0) / 1000.0 / n])


func _instancer_profile() -> void:
	for key: String in ["c:-1,1", "c:0,-1", "lm:keep_venture"]:
		var data := WorldStreamer.generate_unit(world.plan, world.seed, key)
		var parent := Node3D.new()
		add_child(parent)
		var inst := ChunkInstancer.new(data, parent, null)
		var line := ""
		var worst := 0.0
		var total := 0.0
		while not inst.is_done():
			var st := inst._stage
			var t0 := Time.get_ticks_usec()
			inst._step_once()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			if ms > 1.0:
				line += " s%d:%.1f" % [st, ms]
		print("  instancer %s: total %.1f ms, worst step %.1f ms,%s" % [key, total, worst, line])
		inst.free_nodes()
		parent.queue_free()
		await get_tree().process_frame


func _micro() -> void:
	await _instancer_profile()
	for loc: String in ["spawn", "cp_2", "keep_courtyard"]:
		var pos := _marker(loc)
		await _settle(pos)
		player.allomancer.set_reserve(Metal.Type.STEEL, 100.0)
		player.allomancer.set_burning(Metal.Type.STEEL, true)
		print("%s: metals %d, enemies %d" % [loc, MetalRegistry.count(), get_tree().get_nodes_in_group(&"enemy").size()])
		_bench("MetalRegistry._refresh", func() -> void:
			MetalRegistry._dirty_frame = -1
			MetalRegistry._refresh())
		_bench("MetalRegistry.query_radius 40", func() -> void: MetalRegistry.query_radius(pos + Vector3.UP, 40.0))
		_bench("MetalRegistry.query_radius 60", func() -> void: MetalRegistry.query_radius(pos + Vector3.UP, 60.0))
		_bench("allomancer.lines_in_range", func() -> void: player.allomancer.lines_in_range(true))
		_bench("steel_lines._process", func() -> void: player.steel_lines._process(0.016))
		_bench("player._physics_process", func() -> void: player._physics_process(1.0 / 60.0))
		var enemies := get_tree().get_nodes_in_group(&"enemy")
		_bench("all enemies._physics_process", func() -> void:
			for e: Node in enemies:
				if is_instance_valid(e):
					e._physics_process(1.0 / 60.0))
		var hud := game.get_node_or_null(^"HUD")
		if hud != null:
			_bench("hud._process", func() -> void: hud._process(0.016))
		_bench("mist._process", func() -> void: world.mist._process(0.016))
		_bench("streamer._update_wanted", func() -> void: world.streamer._update_wanted(), 5)
		_bench("streamer._poll_tasks", func() -> void: world.streamer._poll_tasks(), 5)
		_bench("streamer._build_step", func() -> void: world.streamer._build_step(), 5)
		_bench("streamer._poll_baking", func() -> void: world.streamer._poll_baking(), 5)
		print("  dynamic metals %d, building %d, baking %d, tasks %d" % [MetalRegistry.dynamic_count(),
				world.streamer._building.size(), world.streamer._baking.size(), world.streamer._tasks.size()])
		for e: Node in enemies:
			var t0 := Time.get_ticks_usec()
			for i in 10:
				e._physics_process(1.0 / 60.0)
			print("    %-12s state %d  %.3f ms" % [e.get_script().get_global_name(), e.state, float(Time.get_ticks_usec() - t0) / 10000.0])
		_bench("audio._process", func() -> void: AudioManager._process(0.016))
		_bench("director (none)", func() -> void: pass)


func _run() -> void:
	if micro:
		await _micro()
		finished.emit({})
		return
	if timeline:
		player.allomancer.set_reserve(Metal.Type.STEEL, 100.0)
		player.allomancer.set_burning(Metal.Type.STEEL, true)
		for k in 40:
			var m := await _measure(30)
			print("t%3d proc %6.2f phys %6.2f max %6.1f busy %s far %s" % [k, m["process"], m["physics"], m["max"],
					world.streamer.is_busy(), world.far_lod._queue.size() + world.far_lod._tasks.size()])
		finished.emit({})
		return
	for loc: String in ["spawn", "cp_2", "keep_courtyard", "extraction"]:
		var pos := _marker(loc)
		await _settle(pos)
		player.allomancer.set_reserve(Metal.Type.STEEL, 100.0)
		player.allomancer.set_burning(Metal.Type.STEEL, true)
		var base := await _measure(sample_frames)
		var entry := {"base": base, "lines": player.allomancer.lines_in_range().size(),
				"metals": MetalRegistry.count(), "enemies": get_tree().get_nodes_in_group(&"enemy").size(),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}
		if bisect:
			var g := _groups()
			for k: String in g:
				var nodes: Array = g[k]
				var modes := []
				for nd: Node in nodes:
					modes.append(nd.process_mode)
					nd.process_mode = Node.PROCESS_MODE_DISABLED
				var m := await _measure(90)
				for i in nodes.size():
					if is_instance_valid(nodes[i]):
						(nodes[i] as Node).process_mode = modes[i]
				entry["without_" + k] = m
				_hold(pos)
		report[loc] = entry
		print("%s: %s" % [loc, JSON.stringify(entry)])
	finished.emit(report)
