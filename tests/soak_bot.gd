extends Node
## Robustness/perf soak for the full game scene (used by tests/test_soak.gd
## and tools/soak.sh). Loads scenes/game.tscn and, for `frames` physics
## frames, a scripted bot:
## - teleports the player along the mission route and far away and back, so
##   chunks stream in and out;
## - flies around holding Push/Pull (the player's own targeting and traversal
##   assist), throws and drops coins, stabs, burns and flares every metal,
##   uses duralumin and atium, drinks vials;
## - takes hits from enemies;
## - starts side activities (ActivityManager), flies through their rings,
##   opens the pause menu (map/journal), saves and loads mid-run.
## It records every engine/script error and warning (through a Logger), leak
## counters, coin pool size, enemies that fell out of the world, the time
## scale after atium, and CPU frame times per route stop.

signal finished(report: Dictionary)

const GAME_SCENE := "res://scenes/game.tscn"
## Route stops (objective ids, or "@x,y,z" for raw positions).
const STOPS: Array[String] = ["spawn", "rooftop_lesson_2", "cp_1", "cp_2", "cp_3", "keep_courtyard",
		"ledger", "extraction", "@-600,30,250", "@-420,30,-150", "cp_2", "keep_courtyard", "spawn",
		"cp_1", "extraction", "@300,30,-600"]


class ErrorCatcher:
	extends Logger
	var mutex := Mutex.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var msg := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(msg)
		else:
			errors.append(msg)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var frames := 3000
## Physics frames spent at each stop.
var dwell := 190
var game: Node3D
var world: LuthadelWorld
var player: Player
var catcher := ErrorCatcher.new()

var _f := 0
var _stop := -1
var _stop_name := ""
var _rng := RandomNumberGenerator.new()
const FrameTimer := preload("res://tests/frame_timer.gd")
const SoakStory := preload("res://tests/story_jump.gd")
var _timer: RefCounted
## stop name -> {frames, proc, phys, max_frame_ms, max_phys_ms}
var _perf: Dictionary = {}
var _time_scale_violations := 0
var _fallen: Array[String] = []
var _max_coins := 0
var _max_pool := 0
var _deaths := 0
var _objects_at: Array[int] = []
var _orphans_at: Array[int] = []
var _atium_uses := 0
var _dura_uses := 0
var _coins_thrown := 0
var _hits := 0
var _stream_hitches: Array[String] = []
var _fallen_detail: Array[String] = []
var _activities := 0
var _saves := 0
var _loads := 0
const SOAK_SLOT := 8


## Story mission to play while soaking ("" keeps GameState's). Its
## prerequisites are marked complete first.
var mission_id: StringName = &"mistwalk_to_keep_venture"


func _ready() -> void:
	_rng.seed = 12345
	OS.add_logger(catcher)
	if mission_id != &"":
		SoakStory.jump_to(mission_id)
	game = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child(game)
	world = game.get_node(^"World") as LuthadelWorld
	player = get_tree().get_first_node_in_group(&"player") as Player
	player.capture_mouse = false
	Events.player_died.connect(func() -> void: _deaths += 1)
	get_tree().physics_frame.connect(_on_physics_frame)
	_timer = FrameTimer.new(get_tree())
	_timer.hitch_hook = func(a: float, b: float) -> void:
		_stream_hitches.append("%s f%d: proc %.1f + phys %.1f ms" % [_stop_name, _f, a, b])


func _exit_tree() -> void:
	OS.remove_logger(catcher)
	if _timer != null:
		_timer.stop()
	if get_tree().physics_frame.is_connected(_on_physics_frame):
		get_tree().physics_frame.disconnect(_on_physics_frame)
	_release_all()


func _release_all() -> void:
	for a: StringName in [&"push", &"pull", &"move_forward", &"jump", &"flare"]:
		Input.action_release(a)


func _process(_delta: float) -> void:
	# Skip the frames right after a teleport (a deliberate jump across the city).
	if _timer != null:
		_timer.paused = _f % dwell < 3


func _close_stop() -> void:
	if _timer == null or _stop_name == "":
		return
	_perf[_stop_name] = _timer.summary()
	_timer.reset()


func _on_physics_frame() -> void:
	if _f >= frames:
		return
	if not is_instance_valid(player):
		return
	if _f % dwell == 0:
		_next_stop()
	_act(_f % dwell)
	_check()
	_f += 1
	if _f >= frames:
		_release_all()
		finished.emit.call_deferred(report())


func _next_stop() -> void:
	_close_stop()
	_stop = (_stop + 1) % STOPS.size()
	var s := STOPS[_stop]
	var pos := Vector3.INF
	if s == "spawn":
		pos = world.spawn_position()
	elif s.begins_with("@"):
		var c := s.substr(1).split(",")
		pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
	else:
		for e: Dictionary in world.get_marker_data(&"objective_point"):
			if str((e["meta"] as Dictionary).get("objective_id", "")) == s:
				pos = e["position"]
	_stop_name = "%02d %s" % [_stop, s]
	if s == "spawn" or s == "cp_2":
		_objects_at.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		_orphans_at.append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	if pos != Vector3.INF:
		player.global_position = pos + Vector3.UP * 1.0
		player.velocity = Vector3.ZERO
		player.camera_rig.snap()


func _act(t: int) -> void:
	var al := player.allomancer
	_release_all()
	if player.dead:
		return
	# Keep metals flowing so every action stays possible (and lift any
	# story-mandated metal restriction: the bot exercises all of them).
	if t % 60 == 0:
		al.allowed_metals = [] as Array[int]
		for m: int in Metal.Type.values():
			if m != Metal.Type.ATIUM and m != Metal.Type.DURALUMIN:
				al.add_reserve(m, 30.0)
		player.coins = maxi(player.coins, 30)
	# Wander: new heading every 45 frames, always moving.
	if t % 45 == 0:
		player.camera_rig.yaw = _rng.randf_range(-PI, PI)
		player.camera_rig.pitch_angle = _rng.randf_range(-0.6, 0.3)
	Input.action_press(&"move_forward")
	if t % 50 == 5:
		Input.action_press(&"jump")
	# Steel/iron: fly with Push (traversal assist) and Pull.
	if not al.is_burning(Metal.Type.STEEL):
		al.set_burning(Metal.Type.STEEL, true)
	if not al.is_burning(Metal.Type.IRON):
		al.set_burning(Metal.Type.IRON, true)
	if (t >= 10 and t < 60) or (t >= 110 and t < 150):
		Input.action_press(&"push")
	elif t >= 70 and t < 95:
		Input.action_press(&"pull")
	if t % 23 == 0:
		_coins_thrown += player.throw_coins()
	if t % 37 == 0:
		player.drop_coin()
	if t % 29 == 0:
		player.melee()
	# Burn/flare every metal in turn.
	if t % 17 == 0:
		var m: int = [Metal.Type.PEWTER, Metal.Type.TIN, Metal.Type.BRONZE, Metal.Type.COPPER,
				Metal.Type.ZINC, Metal.Type.BRASS][(_f / 17) % 6]
		al.toggle_burn(m)
	if (t / 40) % 3 == 1:
		Input.action_press(&"flare")
	# Duralumin and atium, once per stop.
	if t == 120:
		al.add_reserve(Metal.Type.DURALUMIN, 20.0)
		if al.burn_duralumin():
			_dura_uses += 1
	if t == 30:
		player.add_pickup(&"atium", 8.0)
		if al.set_burning(Metal.Type.ATIUM, true):
			_atium_uses += 1
	if t == 100:
		player.add_pickup(&"vial", 1.0)
		player.drink_vial()
	# Open-world systems: side activities, pause menu (map + journal), save/load.
	var am := get_tree().get_first_node_in_group(&"activity_manager")
	if am != null and t == 15:
		var ids: Array = am.activities.keys()
		ids.sort()
		if not ids.is_empty():
			var aid: StringName = ids[_stop % ids.size()]
			if am.start_activity(aid, player.global_position):
				_activities += 1
	if am != null and t % 20 == 10:
		# Fly through the next ring of a running race.
		for aid: StringName in am._active:
			var st: Dictionary = am._active[aid]
			var rings: Array = st.get("rings", [])
			var ri := int(st.get("ring_index", 0))
			if ri < rings.size() and is_instance_valid(rings[ri]):
				player.global_position = (rings[ri] as Node3D).global_position - Vector3.UP * 0.9
				break
	var pm := game.get_node_or_null(^"PauseMenu")
	if pm != null and pm.has_method(&"set_paused"):
		if t == 160:
			pm.set_paused(true)
		elif t == 163:
			pm.set_paused(false)
	if t == 170 and _stop % 4 == 1:
		GameState.save_game(SOAK_SLOT)
		_saves += 1
	if t == 175 and _stop % 4 == 3 and GameState.has_save(SOAK_SLOT):
		GameState.load_game(SOAK_SLOT)
		_loads += 1
	# Get hit by the nearest enemy (they also attack on their own).
	if t % 50 == 25:
		var e := _nearest_enemy(60.0)
		if e != null:
			var h := Health.find_on(e)
			player.health.take_damage(12.0, e, &"blunt")
			_hits += 1
			if h != null and _rng.randf() < 0.3:
				h.take_damage(40.0, player, &"blade")


func _nearest_enemy(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null:
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _check() -> void:
	var al := player.allomancer
	if not al.is_atium_active() and not is_equal_approx(Engine.time_scale, 1.0):
		_time_scale_violations += 1
	if _f % 10 != 0:
		return
	var pool := get_tree().get_first_node_in_group(CoinPool.GROUP) as CoinPool
	if pool != null:
		_max_pool = maxi(_max_pool, pool.active_count())
	_max_coins = maxi(_max_coins, get_tree().get_nodes_in_group(&"coin").size())
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e != null and e.global_position.y < -30.0:
			var desc := "%s (%s)" % [e.get_path(), e.get_script().get_global_name() if e.get_script() else ""]
			if not _fallen.has(desc):
				_fallen.append(desc)
				_fallen_detail.append("%s at %s, stop %s, frame %d" % [desc, e.global_position, _stop_name, _f])


func report() -> Dictionary:
	catcher.mutex.lock()
	var errors := catcher.errors.duplicate()
	var warnings := catcher.warnings.duplicate()
	catcher.mutex.unlock()
	_close_stop()
	var perf := _perf
	return {
		"frames": _f,
		"errors": errors,
		"warnings": warnings,
		"time_scale_violations": _time_scale_violations,
		"fallen_enemies": _fallen,
		"fallen_detail": _fallen_detail,
		"max_coin_nodes": _max_coins,
		"max_pool_active": _max_pool,
		"deaths": _deaths,
		"objects_at_revisits": _objects_at,
		"orphans_at_revisits": _orphans_at,
		"orphans_end": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects_end": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"atium_uses": _atium_uses,
		"duralumin_uses": _dura_uses,
		"coins_thrown": _coins_thrown,
		"hits": _hits,
		"activities_started": _activities,
		"saves": _saves,
		"loads": _loads,
		"cpu_hitches": _stream_hitches,
		"perf": perf,
		"metals": MetalRegistry.count(),
		"enemies": get_tree().get_nodes_in_group(&"enemy").size(),
	}
