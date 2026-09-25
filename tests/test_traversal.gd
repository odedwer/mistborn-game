extends TestCase
## Traversal validation for the slice's rooftop route
## (spawn -> rooftop_lesson_1 -> rooftop_lesson_2 -> cp_1 -> cp_2 -> cp_3 ->
## keep_courtyard):
## 1. metal coverage: every point of each leg has an anchor within Push range;
## 2. a real steel-jump simulation: the real Player (its CharacterBody physics,
##    air control and landing) is placed at the start of each leg, and a small
##    autopilot holds Push on the best anchor through the Allomancer API
##    (anchor chosen with LineTargeting's traversal scoring, like the game's
##    traversal assist) until the player lands on the next objective.

const ROUTE: Array[StringName] = [&"player_spawn", &"rooftop_lesson_1", &"rooftop_lesson_2", &"cp_1",
		&"cp_2", &"cp_3", &"keep_courtyard"]
## Every sample point along a leg needs an anchor (heavy or anchored metal)
## this close: a Push is at full strength to 10 m and fades to 0 at 40 m.
const MAX_ANCHOR_GAP := 22.0
## Physics frames allowed per leg (all waits are bounded).
const LEG_FRAMES := 1500
## Objective triggers are 4 m spheres; the capsule must reach inside.
const REACH := 3.5

var world: LuthadelWorld
var player: Player
var _pick := LineTargeting.new()


func after_each() -> void:
	for a: StringName in [&"move_forward", &"jump"]:
		Input.action_release(a)
	if is_instance_valid(player):
		player.free()
	if is_instance_valid(world):
		world.free()
	Engine.time_scale = 1.0


func _setup() -> Array[Vector3]:
	world = (load("res://src/world/luthadel.tscn") as PackedScene).instantiate() as LuthadelWorld
	world.build_far_lod = false
	add_child(world)
	var pts: Array[Vector3] = []
	for id in ROUTE:
		pts.append(world.spawn_position() if id == &"player_spawn" else _marker(id))
	# Make the whole route resident (a real player streams it on the way).
	for i in pts.size() - 1:
		world.streamer.load_now((pts[i] + pts[i + 1]) * 0.5, pts[i].distance_to(pts[i + 1]) * 0.5 + 60.0)
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	player.capture_mouse = false
	add_child(player)
	player.global_position = pts[0]
	await physics_frames(3)
	return pts


func _marker(id: StringName) -> Vector3:
	for e: Dictionary in world.get_marker_data(&"objective_point"):
		if StringName(str((e["meta"] as Dictionary).get("objective_id", ""))) == id:
			return e["position"]
	return Vector3.INF


static func _is_anchor(m: Metallic) -> bool:
	return m.anchored or m.metal_mass >= 30.0


func test_route_has_anchors_within_push_range() -> void:
	var pts := await _setup()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var cruise := maxf(a.y, b.y) + 4.0
		var n := maxi(int(ceil(a.distance_to(b) / 4.0)), 1)
		var worst := 0.0
		for k in n + 1:
			var t := float(k) / n
			var p := a.lerp(b, t)
			# Sample the flight path: at the ends, and at cruise height between.
			p.y = lerpf(p.y, cruise, sin(t * PI))
			var best := INF
			for m in MetalRegistry.query_radius(p, 40.0):
				if _is_anchor(m):
					best = minf(best, m.global_position.distance_to(p))
			worst = maxf(worst, best)
		print("    %s -> %s: %.0f m, worst anchor gap %.1f m" % [ROUTE[i], ROUTE[i + 1],
				Vector2(b.x - a.x, b.z - a.z).length(), worst])
		assert_lt(worst, MAX_ANCHOR_GAP, "anchor within Push range all along %s -> %s" % [ROUTE[i], ROUTE[i + 1]])


func test_route_is_traversable_with_steel_jumps() -> void:
	var pts := await _setup()
	for i in pts.size() - 1:
		# Start each leg standing at the previous objective, like a player would.
		player.respawn(Transform3D(Basis.IDENTITY, pts[i] + Vector3.UP * 0.1))
		await physics_frames(2)
		var result := await _fly_leg(pts[i + 1])
		print("    %s -> %s: %s" % [ROUTE[i], ROUTE[i + 1], result["log"]])
		assert_true(result["ok"], "steel-jumped %s -> %s (%s)" % [ROUTE[i], ROUTE[i + 1], result["log"]])
		assert_false(player.dead, "survived %s -> %s" % [ROUTE[i], ROUTE[i + 1]])
		if not result["ok"] or player.dead:
			return


## Distance from `target` to the player's capsule axis.
func _capsule_distance(target: Vector3) -> float:
	var p := player.global_position
	var q := Geometry3D.get_closest_point_to_segment(target, p + Vector3.UP * 0.35, p + Vector3.UP * 1.45)
	return q.distance_to(target)


## Autopilot for one leg. Returns {ok, log}.
func _fly_leg(goal: Vector3) -> Dictionary:
	var al := player.allomancer
	for m: int in [Metal.Type.STEEL, Metal.Type.PEWTER]:
		al.set_reserve(m, Metal.MAX_RESERVE)
		al.set_burning(m, true)
	var start := player.global_position
	var pushes := 0
	var max_h := start.y
	var launched := false
	var last_jump := -100
	for f in LEG_FRAMES:
		await get_tree().physics_frame
		if player.dead:
			return {"ok": false, "log": "died after %d frames" % f}
		var p := player.global_position
		max_h = maxf(max_h, p.y)
		var to := goal - p
		var h := Vector2(to.x, to.z).length()
		var on_floor := player.is_on_floor()
		Input.action_release(&"jump")
		# Same rule as the objective trigger: the capsule touches its sphere.
		if _capsule_distance(goal) < REACH:
			Input.action_release(&"move_forward")
			return {"ok": true, "log": "%d frames, %d push frames, apex %.1f m, landed %s" % [f, pushes, max_h, p]}
		# Face and steer toward the goal (air control brakes an overshoot).
		if h > 0.3:
			player.camera_rig.yaw = atan2(-to.x, -to.z)
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		# On the right level and close: just walk/drop in.
		var level := p.y >= goal.y - 0.6
		# Blocked on the ground (a parapet, a kerb): hop.
		if on_floor and Vector2(player.velocity.x, player.velocity.z).length() < 1.0 and h > 1.0 \
				and f - last_jump > 20:
			Input.action_press(&"jump")
			last_jump = f
		if on_floor and level and h < 12.0:
			continue
		if not on_floor and not _needs_push(p, player.velocity, goal):
			continue
		if on_floor and launched and h < 4.0:
			continue
		var dir := Vector3(to.x, 0.0, to.z).normalized() if h > 0.5 else Vector3.ZERO
		var climb := clampf((goal.y + 4.0 - p.y) / 6.0, 0.2, 1.6)
		var desired := (dir + Vector3.UP * climb).normalized()
		var anchor := _pick.pick_traversal_anchor(al.lines_in_range(), al.line_origin(), desired,
				al.current_range(), player.mass_kg)
		if anchor == null:
			continue
		# Flare for long legs when an ordinary Push can't carry us.
		al.set_flaring(h > 45.0 and player.velocity.length() < 20.0)
		if al.push(anchor, 1.0, get_physics_process_delta_time()) > 0.0:
			pushes += 1
			launched = true
	al.set_flaring(false)
	Input.action_release(&"move_forward")
	return {"ok": false, "log": "timed out at %s (goal %s, dist %.1f), %d push frames, apex %.1f" % [
			player.global_position, goal, player.global_position.distance_to(goal), pushes, max_h]}


## True if the current ballistic arc (with air braking) falls short of the
## goal or lands below its level.
func _needs_push(p: Vector3, v: Vector3, goal: Vector3) -> bool:
	var g := 9.81
	var to := goal - p
	var h := Vector2(to.x, to.z).length()
	var hv := Vector2(v.x, v.z)
	var dirh := Vector2(to.x, to.z) / maxf(h, 0.001)
	var along := hv.dot(dirh)
	# Time until we fall back to the goal's level (+ margin).
	var dy := p.y - (goal.y + 0.8)
	var disc := v.y * v.y + 2.0 * g * dy
	if disc < 0.0:
		return true  # can't even reach the goal's height
	var t := (v.y + sqrt(disc)) / g
	# Air control adds up to ~8 m/s toward the goal.
	var reach := along * t + minf(8.0 - minf(along, 8.0), 14.0 * t) * t * 0.5
	return reach < h - 1.0
