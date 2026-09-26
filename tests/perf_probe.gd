extends Node
## CPU frame-time probe for the full game (tools/perf.gd runs it). At each
## location it waits for streaming to settle, then measures the average and
## max of Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS with steel burning,
## and (optionally) bisects by disabling one subsystem at a time.

signal finished(report: Dictionary)

const GAME_SCENE := "res://scenes/game.tscn"

var bisect := false
var sample_frames := 600
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
		var far_busy := world.far_lod != null and not (world.far_lod._queue.is_empty() and world.far_lod._tasks.is_empty())
		if not world.streamer.is_busy() and not world.streamer.is_baking() and not far_busy \
				and world.is_area_loaded(pos):
			break
	for i in 30:
		await get_tree().process_frame


const FrameTimer := preload("res://tests/frame_timer.gd")


func _measure(frames: int) -> Dictionary:
	var ft := FrameTimer.new(get_tree())
	ft.hitch_hook = func(a: float, b: float) -> void:
		print("    hitch proc %.1f phys %.1f  nav_iter %d baking %d building %d tasks %d units %d" % [a, b,
				NavigationServer3D.map_get_iteration_id(world.get_world_3d().navigation_map),
				world.streamer._baking.size(), world.streamer._building.size(), world.streamer._tasks.size(),
				world.streamer.unit_count()])
	for i in frames:
		await get_tree().process_frame
	ft.stop()
	var m := ft.summary()
	return {"process": m["avg_process_ms"], "physics": m["avg_physics_tick_ms"], "max": m["max_frame_ms"],
			"cpu": m["avg_cpu_ms"], "hitches": m["hitches"]}


## Flies the player along the route at `speed` m/s (moved every physics tick,
## so chunks stream in and out exactly as in play) and times every frame.
func _fly_route(speed: float) -> Dictionary:
	var pts: Array[Vector3] = []
	for id: String in ["spawn", "rooftop_lesson_2", "cp_1", "cp_2", "cp_3", "keep_courtyard", "extraction"]:
		pts.append(_marker(id) + Vector3.UP * 25.0)
	_hold(pts[0])
	await _settle(pts[0])
	var ft := FrameTimer.new(get_tree())
	var marker := EndMarker.new()
	marker.ft = ft
	marker.process_physics_priority = 1000000
	add_child(marker)
	ft.hitch_hook = func(a: float, b: float) -> void:
		print("    fly hitch proc %.1f phys %.1f (scripts %.1f) units %d building %d baking %d tasks %d" % [a, b,
				ft.last_phys_scripts_ms, world.streamer.unit_count(), world.streamer._building.size(),
				world.streamer._baking.size(), world.streamer._tasks.size()])
		if not world.streamer._building.is_empty():
			var bi: ChunkInstancer = world.streamer._building[0]
			print("      building %s stage %d cursor %d shapes %d rigid %d" % [bi.data.key, bi._stage, bi._cursor,
					bi.data.shapes.size(), bi.data.rigid.size()])
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := int(a.distance_to(b) / speed * 60.0)
		for k in n:
			await get_tree().physics_frame
			player.global_position = a.lerp(b, float(k) / n)
			player.velocity = Vector3.ZERO
	for i in 120:
		await get_tree().process_frame
	ft.stop()
	return ft.summary()


class EndMarker:
	extends Node
	var ft: RefCounted

	func _physics_process(_d: float) -> void:
		ft.script_end_usec = Time.get_ticks_usec()


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
		"activities": [game.get_node(^"ActivityManager")] if game.has_node(^"ActivityManager") else [],
		"game_state": [get_node(^"/root/GameState")],
		"coins": get_tree().get_nodes_in_group(&"coin_pool"),
		"pause_menu": [game.get_node(^"PauseMenu")] if game.has_node(^"PauseMenu") else [],
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
		var ft := FrameTimer.new(get_tree())
		ft.hitch_ms = 8.0
		ft.hitch_hook = func(a: float, b: float) -> void: print("    after-add frame proc %.1f phys %.1f" % [a, b])
		for i in 20:
			await get_tree().process_frame
		var baked := inst.bake_navigation()
		for i in 200:
			await get_tree().process_frame
			if baked and inst.poll_navigation():
				print("    nav assigned at frame %d" % i)
				baked = false
		ft.hitch_hook = func(a: float, b: float) -> void: print("    after-free frame proc %.1f phys %.1f" % [a, b])
		inst.free_nodes()
		parent.queue_free()
		for i in 10:
			await get_tree().process_frame
		ft.stop()


func _micro() -> void:
	await _settle(world.spawn_position())
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
		if loc == "keep_courtyard":
			# The enemies there should be awake and patrolling.
			pos += Vector3(0, 0, 20)
			_hold(pos)
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
				var m := await _measure(150)
				for i in nodes.size():
					if is_instance_valid(nodes[i]):
						(nodes[i] as Node).process_mode = modes[i]
				entry["without_" + k] = m
				_hold(pos)
		report[loc] = entry
		print("%s: %s" % [loc, JSON.stringify(entry)])
	var fly := await _fly_route(30.0)
	report["fly_route_30mps"] = fly
	print("fly: %s" % JSON.stringify(fly))
	finished.emit(report)
