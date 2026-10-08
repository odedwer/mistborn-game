extends Node
## Bot for tools/record_gameplay.gd (loaded at runtime, after the autoloads
## exist): plays the mission and flies the rooftop route.

const SoakStory := preload("res://tests/story_jump.gd")
const ROUTE: Array[StringName] = [&"player_spawn", &"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1",
		&"cp_2", &"cp_3", &"keep_courtyard"]
## A leg that has not arrived by now is cut (a long stall is dead footage).
const LEG_FRAMES := 720
const REACH := 3.5
const TERMINAL_RADIUS := 30.0
const TERMINAL_SPEED := 14.0
## How quickly the camera turns toward the steering direction (per physics
## frame); the test snaps it, which looks jerky on video.
const YAW_FOLLOW := 0.12

var game: Node3D
var world: LuthadelWorld
var player: Player
var _pick := LineTargeting.new()
var _hour := -1.0
var _legs := ROUTE.size() - 1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			_hour = float(a.substr(7))
		elif a.begins_with("--legs="):
			_legs = clampi(int(a.substr(7)), 1, ROUTE.size() - 1)
	_run.call_deferred()


func _run() -> void:
	SoakStory.jump_to(&"mistwalk_to_keep_venture")
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	if _hour >= 0.0:
		TimeOfDay.set_hour(_hour)
	world = game.get_node(^"World") as LuthadelWorld
	player = get_tree().get_first_node_in_group(&"player") as Player
	player.capture_mouse = false
	var pts: Array[Vector3] = []
	for id in ROUTE:
		pts.append(world.spawn_position() if id == &"player_spawn" else _marker(id))
	# Stream the route in up front, like the traversal test (a hitch here is
	# invisible: Movie Maker records at a fixed step).
	for i in pts.size() - 1:
		world.streamer.load_now((pts[i] + pts[i + 1]) * 0.5, pts[i].distance_to(pts[i + 1]) * 0.5 + 60.0)
	for i in _legs:
		# Each leg starts standing on its objective, like the traversal test:
		# landing "inside reach" can leave the player somewhere (a street, an
		# alley) the autopilot can't launch from. On video this is a cut.
		await _start_leg(pts[i], pts[i + 1])
		var r := await _fly_leg(pts[i + 1])
		print("leg %s -> %s: %s" % [ROUTE[i], ROUTE[i + 1], r])
		for f in 20:
			await get_tree().physics_frame
	for a: StringName in [&"move_forward", &"jump"]:
		Input.action_release(a)
	# Hold on the landing for a beat.
	for f in 60:
		await get_tree().physics_frame
	get_tree().quit()


## Drops the player onto `at`, facing `toward`, and waits until it has stood
## there a few frames (tests/test_traversal.gd `_start_leg`).
func _start_leg(at: Vector3, toward: Vector3) -> void:
	player.allomancer.set_flaring(false)
	player.respawn(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.5))
	var d := toward - at
	player.camera_rig.yaw = atan2(-d.x, -d.z)
	var grounded := 0
	for f in 60:
		await get_tree().physics_frame
		grounded = grounded + 1 if player.is_on_floor() else 0
		if grounded >= 20:
			break


func _marker(id: StringName) -> Vector3:
	for e: Dictionary in world.get_marker_data(&"objective_point"):
		if StringName(str((e["meta"] as Dictionary).get("objective_id", ""))) == id:
			return e["position"]
	return Vector3.INF


func _capsule_distance(target: Vector3) -> float:
	var p := player.global_position
	var q := Geometry3D.get_closest_point_to_segment(target, p + Vector3.UP * 0.35, p + Vector3.UP * 1.45)
	return q.distance_to(target)


## The traversal test's autopilot (tests/test_traversal.gd `_fly_leg`), with
## the camera turning smoothly instead of snapping.
func _fly_leg(goal: Vector3) -> String:
	var al := player.allomancer
	for m: int in [Metal.Type.STEEL, Metal.Type.PEWTER]:
		al.set_reserve(m, Metal.MAX_RESERVE)
		al.set_burning(m, true)
	var launched := false
	var last_jump := -100
	for f in LEG_FRAMES:
		await get_tree().physics_frame
		if player.dead:
			return "died"
		var p := player.global_position
		var to := goal - p
		var h := Vector2(to.x, to.z).length()
		var on_floor := player.is_on_floor()
		Input.action_release(&"jump")
		if _capsule_distance(goal) < REACH:
			Input.action_release(&"move_forward")
			al.set_flaring(false)
			return "reached in %d frames" % f
		var v := player.velocity
		var hv := Vector2(v.x, v.z)
		var dirh := Vector2(to.x, to.z) / maxf(h, 0.001)
		var t_fall := _fall_time(p.y, v.y, goal.y + 0.8)
		var terminal := not on_floor and h < TERMINAL_RADIUS and is_finite(t_fall)
		var err := Vector2.ZERO
		if terminal:
			err = dirh * minf(h / maxf(t_fall, 0.25), TERMINAL_SPEED) - hv
		var steer := err if terminal and err.length() > 0.5 else Vector2(to.x, to.z)
		if h > 0.3:
			var want := atan2(-steer.x, -steer.y)
			player.camera_rig.yaw = lerp_angle(player.camera_rig.yaw, want, YAW_FOLLOW)
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		var level := p.y >= goal.y - 0.6
		if on_floor and hv.length() < 1.0 and h > 1.0 and f - last_jump > 20:
			Input.action_press(&"jump")
			last_jump = f
		if on_floor and level and h < 12.0:
			continue
		var desired: Vector3
		var intensity := 1.0
		if terminal:
			var fixable := player.air_accel * t_fall * 0.7
			if err.length() <= fixable:
				continue
			intensity = clampf((err.length() - fixable) / 10.0, 0.25, 1.0)
			var e := err / err.length()
			var rise := 0.3 if h / maxf(t_fall, 0.25) > TERMINAL_SPEED else -0.4
			desired = Vector3(e.x, rise, e.y).normalized()
		else:
			if not on_floor and not _needs_push(p, v, goal):
				continue
			if on_floor and launched and h < 4.0:
				continue
			var dir := Vector3(dirh.x, 0.0, dirh.y) if h > 0.5 else Vector3.ZERO
			var climb := clampf((goal.y + 4.0 - p.y) / 6.0, 0.2, 1.6)
			desired = (dir + Vector3.UP * climb).normalized()
		var anchor := _pick.pick_traversal_anchor(al.lines_in_range(), al.line_origin(), desired,
				al.current_range(), player.mass_kg)
		if anchor == null:
			continue
		al.set_flaring(h > 45.0 and v.length() < 20.0)
		if al.push(anchor, intensity, 1.0 / Engine.physics_ticks_per_second) > 0.0:
			launched = true
	al.set_flaring(false)
	Input.action_release(&"move_forward")
	return "timed out"


func _needs_push(p: Vector3, v: Vector3, goal: Vector3) -> bool:
	var to := goal - p
	var h := Vector2(to.x, to.z).length()
	var hv := Vector2(v.x, v.z)
	var dirh := Vector2(to.x, to.z) / maxf(h, 0.001)
	var along := hv.dot(dirh)
	var disc := v.y * v.y + 2.0 * 9.81 * (p.y - (goal.y + 0.8))
	if disc < 0.0:
		return true
	var t := (v.y + sqrt(disc)) / 9.81
	var reach := along * t + minf(8.0 - minf(along, 8.0), 14.0 * t) * t * 0.5
	return reach < h - 1.0


static func _fall_time(y: float, vy: float, floor_y: float) -> float:
	var disc := vy * vy + 2.0 * 9.81 * (y - floor_y)
	if disc < 0.0:
		return INF
	var t := (vy + sqrt(disc)) / 9.81
	return t if t > 0.0 else INF
