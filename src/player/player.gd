class_name Player
extends CharacterBody3D
## The player: a Mistborn with a momentum-preserving character controller.
##
## Movement: responsive ground acceleration, coyote time, jump buffering,
## variable jump height, crouch, sprint with stamina (free with pewter), and
## air control that only *adds* limited steering: it never clamps the
## horizontal speed that allomancy gives you. Landing fast rolls and keeps
## your speed. Fall/impact damage unless pewter is burning.
##
## Allomancy: crosshair targeting (LineTargeting), locked while LMB/RMB is
## held, scroll to cycle. Traversal assist (on by default): holding Push in
## the air picks the anchor that best drives you where you're heading. Pull on
## a heavy anchor tethers you (swing) and reels you in (zip) with a soft
## arrival; release to fling. Dropping a coin in the air and Pushing it gives
## a vertical boost (coin-jump). Pulling one of your coins to you pockets it.
##
## Everything other systems need goes through Events, `add_pickup`,
## `get_allomantic_mass` and `receive_allomantic_force`.

const MODEL_PATH := "res://assets/models/characters/vin.tscn"
const WORLD_MASK := 1
const ENEMY_MASK := 1 << 2
const PROPS_MASK := 1 << 3
const TRIGGER_MASK := 1 << 5

@export_group("Movement")
@export var walk_speed := 5.5
@export var sprint_speed := 8.5
@export var crouch_speed := 2.6
@export var ground_accel := 55.0
@export var ground_decel := 45.0
## Deceleration (m/s^2) when moving faster than the run speed on the ground.
@export var overspeed_friction := 9.0
## How fast (rad/s) input steers an overspeed slide.
@export var overspeed_steer := 2.5
## Air acceleration (m/s^2) toward the input direction.
@export var air_accel := 14.0
## Air steering can only build speed up to this (m/s) along the input
## direction; faster momentum is kept, never clamped.
@export var air_control_speed := 8.0
@export var jump_velocity := 5.4
## Gravity multiplier while rising with jump released (variable jump height).
@export var low_jump_gravity_mult := 2.2
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15
## Hard cap on speed (m/s).
@export var max_velocity := 120.0
## Body mass (kg) for allomantic forces.
@export var mass_kg := 60.0
@export var stand_height := 1.8
@export var crouch_height := 1.15
## Stamina drained per second of sprinting (without pewter).
@export var sprint_stamina_drain := 0.12
@export var stamina_regen := 0.3

@export_group("Landing")
## Impacts slower than this (m/s) are harmless.
@export var safe_impact_speed := 18.0
## Damage per m/s above safe_impact_speed.
@export var impact_damage_per_speed := 4.5
## Scale on horizontal speed lost in wall impacts before computing damage.
@export var wall_impact_scale := 0.45
## Landing this fast (vertical m/s) is a hard landing (shake, sound, noise).
@export var hard_landing_speed := 9.0
## Landing with at least this horizontal speed rolls (keeps momentum).
@export var roll_speed_threshold := 7.0
@export var roll_time := 0.55
## Ground friction (m/s^2) during a roll.
@export var roll_friction := 2.5
## Fall damage multiplier when the landing turns into a roll.
@export var roll_damage_scale := 0.6

@export_group("Allomancy")
## Holding Push while airborne auto-selects the best anchor.
@export var traversal_assist := true
## Upward bias of the desired direction for assist anchors.
@export var assist_up_bias := 0.65
## Pull on a heavy anchor acts as a tether (swing) while airborne.
@export var pull_tether := true
## Max approach speed (m/s per metre of distance) when zipping to an anchor.
@export var zip_arrival_rate := 6.0
## Pulled coins closer than this (m) go back into the pouch.
@export var coin_collect_distance := 1.3
## Seconds a coin dropped in mid-air acts as an anchor (coin-jump).
@export var coin_jump_window := 0.5
## Coins thrown together are Pushed together for this long (s).
@export var volley_time := 1.5
## Range for zinc/brass targeting (m).
@export var emotional_range := 30.0

@export_group("Combat")
@export var melee_damage := 35.0
@export var melee_cooldown := 0.45
@export var melee_range := 1.4
@export var throw_count := 6
@export var throw_speed := 16.0
@export var throw_spread_deg := 5.0
@export var throw_cooldown := 0.35
@export var interact_distance := 3.0

@export_group("Inventory")
@export var starting_coins := 60
@export var starting_vials := 2
## Reserve restored to steel, iron, pewter and tin by one vial.
@export var vial_amount := 40.0

@export_group("Misc")
@export var capture_mouse := true
## Added to the model's facing yaw (degrees). Models are assumed to face +Z.
@export var model_yaw_offset_deg := 0.0
## Physics frames between streaming/ground checks while falling.
@export var stream_check_interval := 8
## Longest time (s) to hover waiting for an unloaded chunk.
@export var stream_hold_max := 8.0
## Below this height the player is returned to the last safe ground.
@export var void_height := -400.0

## Coins in the pouch.
var coins := 0
## Metal vials carried.
var vials := 0
## Sprint stamina, 0..1.
var stamina := 1.0
var crouching := false
var dead := false

var allomancer: Allomancer
var health: Health
var camera_rig: PlayerCamera
var targeting := LineTargeting.new()
var steel_lines: SteelLines
var model: Node3D

var _visual: Node3D
var _chest: Node3D
var _shape: CapsuleShape3D
var _collision: CollisionShape3D
var _melee_cast: ShapeCast3D
var _gravity := 9.81
var _wish := Vector3.ZERO
var _coyote := 0.0
var _jump_buffer := 0.0
var _jumping := false
var _was_on_floor := true
var _pre_move_velocity := Vector3.ZERO
var _allo_frame := -10
var _roll_timer := 0.0
var _melee_timer := 0.0
var _throw_timer := 0.0
var _stride := 0.0
var _sprint_locked := false
var _aim_timer := 0.0
var _duralumin_armed := false
var _tether_len := -1.0
var _coin_jump_metal: Metallic
var _volley: Array[Coin] = []
var _volley_time := 0.0
var _last_target: Metallic
var _manual_cycle_time := 0.0
var _emotional_timer := 0.0
var _stream_hold := false
var _stream_hold_time := 0.0
var _last_safe := Vector3.ZERO
var _safe_timer := 0.0
var _model_locomotion := false
var _model_actions := false
var _ray := PhysicsRayQueryParameters3D.new()
var _head_query := PhysicsShapeQueryParameters3D.new()
var _head_sphere := SphereShape3D.new()
var _melee_hits: Array[Health] = []


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = 1 << 1
	collision_mask = WORLD_MASK | ENEMY_MASK | PROPS_MASK
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	allomancer = get_node(^"Allomancer") as Allomancer
	health = get_node(^"Health") as Health
	camera_rig = get_node(^"CameraRig") as PlayerCamera
	steel_lines = get_node(^"SteelLines") as SteelLines
	_visual = get_node(^"Visual") as Node3D
	_chest = get_node(^"Visual/Chest") as Node3D
	_collision = get_node(^"CollisionShape3D") as CollisionShape3D
	_shape = _collision.shape as CapsuleShape3D
	_melee_cast = get_node(^"MeleeCast") as ShapeCast3D
	_melee_cast.add_exception(self)
	_melee_cast.enabled = false
	allomancer.controls_local_view = true
	camera_rig.target = self
	camera_rig.snap()
	steel_lines.allomancer = allomancer
	steel_lines.origin_node = _chest
	_ray.exclude = [get_rid()]
	_head_sphere.radius = 0.3
	_head_query.shape = _head_sphere
	_head_query.collision_mask = WORLD_MASK
	_head_query.exclude = [get_rid()]
	_setup_model()
	var fwd := -camera_rig.yaw_basis().z
	_visual.rotation.y = atan2(fwd.x, fwd.z) + deg_to_rad(model_yaw_offset_deg)
	coins = starting_coins
	vials = starting_vials
	_last_safe = global_position
	health.damaged.connect(_on_damaged)
	health.healed.connect(_on_healed)
	health.died.connect(_on_died)
	Events.pause_toggled.connect(_on_pause_toggled)
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_emit_initial_state.call_deferred()


# --- Contracts ----------------------------------------------------------------

func get_allomantic_mass() -> float:
	return mass_kg


## Applies an allomantic force (N) for `delta` seconds: v += F / m * dt.
func receive_allomantic_force(force: Vector3, delta: float, _from: Metallic) -> void:
	var dv := force / mass_kg * delta
	velocity += dv
	if dv.length() > 0.02:
		_allo_frame = Engine.get_physics_frames()


## Pickups call this. kinds: coins, vial, atium, duralumin, health.
func add_pickup(kind: StringName, amount: float) -> void:
	match kind:
		&"coins":
			coins += int(amount)
			_emit_inventory()
		&"vial":
			vials += int(amount)
			_emit_inventory()
		&"atium":
			allomancer.add_reserve(Metal.Type.ATIUM, amount)
		&"duralumin":
			allomancer.add_reserve(Metal.Type.DURALUMIN, amount)
		&"health":
			health.heal(amount)
		_:
			push_warning("Player.add_pickup: unknown kind %s" % kind)
			return
	Events.pickup_collected.emit(kind, amount)


## Restores metal reserves from one vial. Returns false if none left.
func drink_vial() -> bool:
	if vials <= 0 or dead:
		return false
	vials -= 1
	for m: int in [Metal.Type.STEEL, Metal.Type.IRON, Metal.Type.PEWTER, Metal.Type.TIN]:
		allomancer.add_reserve(m, vial_amount)
	AudioManager.play_3d(&"vial_drink", global_position)
	_emit_inventory()
	return true


## Revives and teleports the player (checkpoints).
func respawn(xform: Transform3D) -> void:
	dead = false
	health.revive(1.0)
	global_transform = Transform3D(Basis.IDENTITY, xform.origin)
	velocity = Vector3.ZERO
	_stream_hold = false
	_last_safe = xform.origin
	camera_rig.yaw = xform.basis.get_euler().y
	camera_rig.snap()
	var fwd := -camera_rig.yaw_basis().z
	_visual.rotation.y = atan2(fwd.x, fwd.z) + deg_to_rad(model_yaw_offset_deg)
	Engine.time_scale = 1.0
	Events.player_health_changed.emit(health.current, health.max_health)


## Damage a collision at `speed` m/s deals with the given tuning.
static func impact_damage(speed: float, safe_speed: float = 18.0, per_speed: float = 4.5) -> float:
	return maxf(speed - safe_speed, 0.0) * per_speed


# --- Main loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		_dead_process(delta)
		return
	_tick_timers(delta)
	_read_move_input()
	_handle_metal_input()
	_handle_allomancy(delta)
	_handle_actions()
	_update_crouch()
	_move(delta)
	_after_move(delta)
	_update_facing(delta)


func _process(_delta: float) -> void:
	# Predict the visual between physics ticks (the camera does the same), so
	# the model and the steel lines stay glued to the camera at high speed.
	var frac := Engine.get_physics_interpolation_fraction()
	_visual.position = velocity * (frac / float(Engine.physics_ticks_per_second))


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event.is_action_pressed(&"target_cycle_next"):
		_cycle_target(1)
	elif event.is_action_pressed(&"target_cycle_prev"):
		_cycle_target(-1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and capture_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not get_tree().paused and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _tick_timers(delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_melee_timer = maxf(_melee_timer - delta, 0.0)
	_throw_timer = maxf(_throw_timer - delta, 0.0)
	_roll_timer = maxf(_roll_timer - delta, 0.0)
	_aim_timer = maxf(_aim_timer - delta, 0.0)
	_volley_time = maxf(_volley_time - delta, 0.0)
	_manual_cycle_time = maxf(_manual_cycle_time - delta, 0.0)
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = jump_buffer_time


func _read_move_input() -> void:
	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	_wish = camera_rig.yaw_basis() * Vector3(v.x, 0.0, v.y)
	if _wish.length_squared() > 1.0:
		_wish = _wish.normalized()


func _handle_metal_input() -> void:
	for action: String in InputSetup.TOGGLE_TO_METAL:
		if Input.is_action_just_pressed(action):
			allomancer.toggle_burn(InputSetup.TOGGLE_TO_METAL[action])
	if Input.is_action_just_pressed(&"burn_all_basic"):
		var basics: Array[int] = [Metal.Type.STEEL, Metal.Type.IRON, Metal.Type.PEWTER, Metal.Type.TIN]
		var all_on := true
		for m in basics:
			if not allomancer.is_burning(m) and allomancer.get_reserve(m) > 0.0:
				all_on = false
		for m in basics:
			allomancer.set_burning(m, not all_on)
	if Input.is_action_just_pressed(&"burn_duralumin"):
		if allomancer.get_reserve(Metal.Type.DURALUMIN) > 0.0:
			_duralumin_armed = true
			if allomancer.is_using_line(Metal.Type.STEEL) or allomancer.is_using_line(Metal.Type.IRON):
				_duralumin_armed = not allomancer.burn_duralumin()
	allomancer.set_flaring(Input.is_action_pressed(&"flare"))


# --- Allomancy ----------------------------------------------------------------

func _handle_allomancy(delta: float) -> void:
	var lines := allomancer.lines_in_range()
	var aim_o := camera_rig.aim_origin()
	var aim_d := camera_rig.aim_direction()
	targeting.update(lines, aim_o, aim_d, maxf(camera_rig.distance_to_pivot() - 0.5, 0.0))
	var push_held := Input.is_action_pressed(&"push") and allomancer.is_burning(Metal.Type.STEEL)
	var pull_held := Input.is_action_pressed(&"pull") and allomancer.is_burning(Metal.Type.IRON)
	var push_start := push_held and Input.is_action_just_pressed(&"push")
	var pull_start := pull_held and Input.is_action_just_pressed(&"pull")

	if push_held:
		_aim_timer = 0.3
		if push_start or not targeting.locked:
			_select_push_target(lines)
		elif targeting.from_assist:
			var a := _assist_anchor(lines)
			if a != null and a != targeting.target:
				targeting.lock_on(a, true)
		if _coin_jump_metal != null and is_instance_valid(_coin_jump_metal) \
				and (_coin_jump_metal.body as Coin).is_virtual_anchor() and targeting.target != _coin_jump_metal:
			targeting.lock_on(_coin_jump_metal, true)
		var t := targeting.target
		if t != null:
			if _duralumin_armed:
				_duralumin_armed = not allomancer.burn_duralumin()
			allomancer.push(t, 1.0, delta)
			_push_volley(t, delta)
			_play_model_action_once(&"push", push_start)
	elif pull_held:
		_aim_timer = 0.3
		if pull_start or not targeting.locked:
			targeting.lock()
			_tether_len = -1.0
		var t := targeting.target
		if t != null:
			if _duralumin_armed:
				_duralumin_armed = not allomancer.burn_duralumin()
			allomancer.pull(t, 1.0, delta)
			_play_model_action_once(&"pull", pull_start)
			_apply_tether(t)
			_try_collect_coin(t, delta)
	elif targeting.locked:
		targeting.release()
		_tether_len = -1.0

	steel_lines.highlight = targeting.target
	if targeting.target != _last_target:
		_last_target = targeting.target
		Events.line_target_changed.emit(allomancer, _last_target)
	_update_emotional_target(delta)


func _select_push_target(lines: Array[Metallic]) -> void:
	var manual_ok := targeting.target != null and (targeting.is_precise() or _manual_cycle_time > 0.0)
	var use_assist := traversal_assist and not manual_ok \
		and (not is_on_floor() or targeting.target == null)
	if use_assist:
		var a := _assist_anchor(lines)
		if a != null:
			targeting.lock_on(a, true)
			return
	targeting.lock()


## Best anchor for the direction the player wants to travel.
func _assist_anchor(lines: Array[Metallic]) -> Metallic:
	var h := _wish
	if h.length_squared() < 0.01:
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		if hv.length() > 3.0:
			h = hv.normalized()
		else:
			h = -camera_rig.yaw_basis().z
	var desired := (h.normalized() + Vector3.UP * assist_up_bias).normalized()
	return targeting.pick_traversal_anchor(lines, allomancer.line_origin(), desired,
		allomancer.current_range(), mass_kg)


## Pushes the rest of a freshly thrown volley along with its targeted coin.
func _push_volley(t: Metallic, delta: float) -> void:
	if _volley_time <= 0.0 or not (t.body is Coin) or not _volley.has(t.body as Coin):
		return
	for c in _volley:
		if is_instance_valid(c) and c.active and c.metallic != t:
			allomancer.push(c.metallic, 1.0, delta)


func _apply_tether(t: Metallic) -> void:
	if not pull_tether or is_on_floor():
		return
	if t.get_body_mass() < mass_kg:
		return
	var to_self := allomancer.line_origin() - t.global_position
	var dist := to_self.length()
	if dist < 0.5:
		return
	var r := to_self / dist
	if _tether_len < 0.0:
		_tether_len = dist
	_tether_len = minf(_tether_len, dist)
	var vr := velocity.dot(r)
	# Swing: never drift outward past the tether length.
	if vr > 0.0 and dist >= _tether_len - 0.05:
		velocity -= r * vr
	# Zip: soft arrival so reeling in doesn't smash you into the anchor.
	var approach := -velocity.dot(r)
	var max_approach := 4.0 + maxf(dist - 1.0, 0.0) * zip_arrival_rate
	if approach > max_approach:
		velocity += r * (approach - max_approach)


func _try_collect_coin(t: Metallic, delta: float) -> void:
	if not (t.body is Coin):
		return
	var coin := t.body as Coin
	var reach := coin_collect_distance + coin.linear_velocity.length() * delta
	if t.global_position.distance_to(allomancer.line_origin()) <= reach:
		CoinPool.get_for(self).recycle(coin)
		coins += 1
		targeting.release()
		AudioManager.play_3d(&"coin_clink", global_position)
		_emit_inventory()


func _cycle_target(step: int) -> void:
	_manual_cycle_time = 1.5
	var was_locked := targeting.locked
	var t := targeting.cycle(step)
	if was_locked:
		targeting.lock_on(t, false)


func _update_emotional_target(delta: float) -> void:
	if not (allomancer.is_burning(Metal.Type.ZINC) or allomancer.is_burning(Metal.Type.BRASS)):
		allomancer.emotional_target = null
		return
	_emotional_timer -= delta
	if _emotional_timer > 0.0:
		return
	_emotional_timer = 0.1
	var o := camera_rig.aim_origin()
	var d := camera_rig.aim_direction()
	var best: Node3D = null
	var best_angle := deg_to_rad(12.0)
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null:
			continue
		var to := e.global_position + Vector3.UP - o
		var dist := to.length()
		if dist > emotional_range or dist < 0.1:
			continue
		var ang := acos(clampf(d.dot(to / dist), -1.0, 1.0))
		if ang < best_angle:
			best_angle = ang
			best = e
	allomancer.emotional_target = best


# --- Actions --------------------------------------------------------------------

func _handle_actions() -> void:
	if Input.is_action_just_pressed(&"throw_coins"):
		throw_coins()
	if Input.is_action_just_pressed(&"drop_coin"):
		drop_coin()
	if Input.is_action_just_pressed(&"melee"):
		melee()
	if Input.is_action_just_pressed(&"drink_vial"):
		drink_vial()
	if Input.is_action_just_pressed(&"interact"):
		interact()
	if Input.is_action_just_pressed(&"toggle_camera"):
		camera_rig.toggle_first_person()


## Throws a handful of coins toward the crosshair. Returns how many.
func throw_coins() -> int:
	if _throw_timer > 0.0 or coins <= 0:
		return 0
	_throw_timer = throw_cooldown
	_aim_timer = 0.4
	var n := mini(throw_count, coins)
	coins -= n
	var aim_point := _crosshair_point(200.0)
	var hand := allomancer.line_origin() + camera_rig.global_basis.x * 0.25 + camera_rig.aim_direction() * 0.5
	var dir := (aim_point - hand).normalized()
	var aim_basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var pool := CoinPool.get_for(self)
	var spread := tan(deg_to_rad(throw_spread_deg))
	_volley.clear()
	for i in n:
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0) * spread
		var d := (aim_basis * Vector3(off.x, off.y, -1.0)).normalized()
		var p := hand + aim_basis * Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), 0.0)
		_volley.append(pool.spawn(Transform3D(Basis.IDENTITY, p), d * throw_speed + velocity, self))
	_volley_time = volley_time
	AudioManager.play_3d(&"coin_throw", hand)
	Events.noise_emitted.emit(global_position, 0.15, self)
	_model_action(&"throw")
	_emit_inventory()
	return n


## Drops a coin beneath the player (a steel-jump anchor). In mid-air it is
## flung down and briefly counts as an anchor (coin-jump).
func drop_coin() -> Coin:
	if coins <= 0:
		return null
	coins -= 1
	var airborne := not is_on_floor()
	var v := Vector3.ZERO
	if airborne:
		v = velocity + Vector3.DOWN * 12.0
	var coin := CoinPool.get_for(self).spawn(Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.15), v, self)
	if airborne:
		coin.virtual_anchor_time = coin_jump_window
		_coin_jump_metal = coin.metallic
	AudioManager.play_3d(&"coin_clink", global_position)
	_emit_inventory()
	return coin


## Obsidian dagger strike. Returns the number of actors hit.
func melee() -> int:
	if _melee_timer > 0.0:
		return 0
	_melee_timer = melee_cooldown
	_aim_timer = 0.4
	var fwd := -camera_rig.yaw_basis().z
	_melee_cast.global_position = global_position + Vector3.UP * 1.1
	_melee_cast.target_position = _melee_cast.global_basis.inverse() * (fwd * melee_range)
	_melee_cast.force_shapecast_update()
	_melee_hits.clear()
	for i in _melee_cast.get_collision_count():
		var h := Health.find_on(_melee_cast.get_collider(i) as Node)
		if h != null and h != health and not _melee_hits.has(h):
			_melee_hits.append(h)
			h.take_damage(melee_damage * allomancer.damage_multiplier(), self, &"blade")
	AudioManager.play_3d(&"dagger_swing", global_position)
	if not _melee_hits.is_empty():
		AudioManager.play_3d(&"dagger_hit", global_position + fwd)
		camera_rig.add_trauma(0.15)
	Events.noise_emitted.emit(global_position, 0.3 if _melee_hits.is_empty() else 0.5, self)
	_model_action(&"melee")
	return _melee_hits.size()


## Calls interact(player) on whatever the crosshair points at within reach.
func interact() -> bool:
	var o := camera_rig.aim_origin()
	var d := camera_rig.aim_direction()
	_ray.from = o
	_ray.to = o + d * (interact_distance + camera_rig.distance_to_pivot() + 1.0)
	_ray.collision_mask = WORLD_MASK | ENEMY_MASK | PROPS_MASK | TRIGGER_MASK
	_ray.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	_ray.collide_with_areas = false
	if hit.is_empty():
		return false
	if (hit["position"] as Vector3).distance_to(allomancer.line_origin()) > interact_distance:
		return false
	var n := hit["collider"] as Node
	while n != null:
		if n.has_method(&"interact"):
			n.interact(self)
			return true
		n = n.get_parent()
	return false


func _crosshair_point(max_dist: float) -> Vector3:
	var o := camera_rig.aim_origin()
	var d := camera_rig.aim_direction()
	_ray.from = o
	_ray.to = o + d * max_dist
	_ray.collision_mask = WORLD_MASK | ENEMY_MASK | PROPS_MASK
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit["position"] if not hit.is_empty() else _ray.to


# --- Movement -----------------------------------------------------------------

func _update_crouch() -> void:
	var want := Input.is_action_pressed(&"crouch") and is_on_floor()
	if want == crouching:
		return
	if not want and not _can_stand():
		return
	crouching = want
	_shape.height = crouch_height if crouching else stand_height
	_collision.position.y = _shape.height * 0.5
	camera_rig.crouching = crouching


func _can_stand() -> bool:
	_head_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (stand_height - 0.3))
	return get_world_3d().direct_space_state.intersect_shape(_head_query, 1).is_empty()


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	var pushed := Engine.get_physics_frames() - _allo_frame <= 1
	if on_floor:
		_coyote = coyote_time
		_jumping = false
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# Sprint and stamina (pewter makes sprinting free).
	var pewter := allomancer.is_burning(Metal.Type.PEWTER)
	var sprinting := Input.is_action_pressed(&"sprint") and not crouching and not _sprint_locked \
		and _wish.length_squared() > 0.01
	if sprinting and not pewter:
		stamina = maxf(stamina - sprint_stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			_sprint_locked = true
	else:
		stamina = minf(stamina + stamina_regen * delta, 1.0)
		if stamina > 0.25:
			_sprint_locked = false

	var max_speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	max_speed *= allomancer.speed_multiplier()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var vy := velocity.y

	if on_floor:
		var hs := hv.length()
		if pushed:
			hv += _wish * (ground_accel * 0.25 * delta)
		elif hs > max_speed + 0.5:
			# Overspeed slide (landing from a flight): keep momentum, steer, bleed slowly.
			var fr := roll_friction if _roll_timer > 0.0 else overspeed_friction
			var dir := hv / hs
			if _wish.length_squared() > 0.01:
				var ang := dir.signed_angle_to(_wish.normalized(), Vector3.UP)
				dir = dir.rotated(Vector3.UP, clampf(ang, -overspeed_steer * delta, overspeed_steer * delta))
			hv = dir * maxf(hs - fr * delta, max_speed)
		else:
			var rate := ground_accel if _wish.length_squared() > 0.01 else ground_decel
			hv = hv.move_toward(_wish * max_speed, rate * delta)
	else:
		# Quake-style air control: add speed toward the input only up to
		# air_control_speed along it. Allomantic momentum is never clamped.
		if _wish.length_squared() > 0.01:
			var wdir := _wish.normalized()
			var add := air_control_speed * _wish.length() - hv.dot(wdir)
			if add > 0.0:
				hv += wdir * minf(air_accel * delta, add)
		var gm := 1.0
		if _jumping and vy > 0.0 and not Input.is_action_pressed(&"jump") and not pushed:
			gm = low_jump_gravity_mult
		if _stream_hold:
			vy = maxf(vy, 0.0)
		else:
			vy -= _gravity * gm * delta

	# Jump (buffered, with coyote time).
	if _jump_buffer > 0.0 and (on_floor or _coyote > 0.0) and not crouching:
		vy = maxf(vy, jump_velocity * allomancer.jump_multiplier())
		_jump_buffer = 0.0
		_coyote = 0.0
		_jumping = true
		AudioManager.play_3d(&"jump", global_position)
		Events.noise_emitted.emit(global_position, 0.15, self)
		_model_action(&"jump")

	velocity = hv + Vector3.UP * vy
	if velocity.length() > max_velocity:
		velocity = velocity.normalized() * max_velocity

	_update_streaming(delta, on_floor)
	_pre_move_velocity = velocity
	_was_on_floor = on_floor
	move_and_slide()


func _after_move(delta: float) -> void:
	var on_floor := is_on_floor()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var pewter := allomancer.is_burning(Metal.Type.PEWTER)

	# Impacts (landing, slamming into walls): speed lost to collisions.
	if get_slide_collision_count() > 0:
		# Vertical impacts count fully; glancing wall slams are softened so
		# high-speed traversal mistakes hurt without being instantly lethal.
		var lost := _pre_move_velocity - velocity
		var loss := Vector2(Vector2(lost.x, lost.z).length() * wall_impact_scale, lost.y).length()
		var landed := on_floor and not _was_on_floor
		var rolled := false
		if landed:
			var impact := -_pre_move_velocity.y
			rolled = hspeed > roll_speed_threshold or impact > hard_landing_speed
			_on_landed(impact, rolled)
		if loss > safe_impact_speed and not pewter:
			var dmg := impact_damage(loss, safe_impact_speed, impact_damage_per_speed)
			if rolled:
				dmg *= roll_damage_scale
			health.take_damage(dmg, null, &"fall")

	# Footsteps.
	if on_floor and hspeed > 0.5:
		_stride += hspeed * delta
		var stride_len := 2.4 if hspeed > walk_speed + 0.5 else 1.8
		if _stride >= stride_len:
			_stride = 0.0
			var loud := 0.06 if crouching else (0.4 if hspeed > walk_speed + 0.5 else 0.22)
			AudioManager.play_3d(&"footstep", global_position, -18.0 if crouching else -8.0)
			Events.noise_emitted.emit(global_position, loud, self)

	# Safe ground for void recovery.
	if on_floor:
		_safe_timer += delta
		if _safe_timer > 1.0:
			_safe_timer = 0.0
			_last_safe = global_position
	if global_position.y < void_height:
		global_position = _last_safe + Vector3.UP * 0.5
		velocity = Vector3.ZERO
		camera_rig.snap()

	if _model_locomotion:
		model.set_locomotion(hspeed, on_floor, velocity.y)


func _on_landed(impact: float, rolled: bool) -> void:
	if impact < 3.0:
		return
	if rolled:
		_roll_timer = roll_time
		camera_rig.add_dip(clampf(impact * 0.02, 0.05, 0.4))
	else:
		camera_rig.add_dip(clampf(impact * 0.015, 0.02, 0.25))
	_model_action(&"land")
	if impact > hard_landing_speed:
		camera_rig.add_trauma(clampf((impact - hard_landing_speed) / 25.0, 0.1, 0.7))
		AudioManager.play_3d(&"land_hard", global_position)
	Events.noise_emitted.emit(global_position, clampf(impact / 25.0, 0.1, 1.0), self)


## Hovers instead of falling into a world chunk that hasn't streamed in yet.
func _update_streaming(delta: float, on_floor: bool) -> void:
	if on_floor or velocity.y > 0.0:
		_stream_hold = false
		_stream_hold_time = 0.0
		return
	if _stream_hold:
		_stream_hold_time += delta
		if _stream_hold_time > stream_hold_max:
			_stream_hold = false
	if Engine.get_physics_frames() % stream_check_interval != 0:
		return
	_ray.from = global_position + Vector3.UP * 0.5
	_ray.to = global_position + Vector3.DOWN * 200.0
	_ray.collision_mask = WORLD_MASK
	if not get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
		_stream_hold = false
		return
	var streamer := get_tree().get_first_node_in_group(&"world_streamer")
	if streamer != null and streamer.has_method(&"is_area_loaded"):
		var loaded: bool = streamer.is_area_loaded(global_position)
		if not loaded and _stream_hold_time <= stream_hold_max:
			_stream_hold = true
			velocity.y = maxf(velocity.y, 0.0)
		elif loaded:
			_stream_hold = false


func _update_facing(delta: float) -> void:
	var face := Vector3.ZERO
	if _aim_timer > 0.0 or camera_rig.first_person:
		face = -camera_rig.yaw_basis().z
	else:
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		if hv.length() > 0.8:
			face = hv
		elif _wish.length_squared() > 0.01:
			face = _wish
	if face.length_squared() > 0.001:
		var goal := atan2(face.x, face.z) + deg_to_rad(model_yaw_offset_deg)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, goal, 1.0 - exp(-14.0 * delta))
	_visual.visible = camera_rig.first_person_blend() < 0.7


func _dead_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	move_and_slide()


# --- Model / events -------------------------------------------------------------

func _setup_model() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var ps := load(MODEL_PATH) as PackedScene
		if ps != null:
			model = ps.instantiate() as Node3D
	if model == null:
		model = PlayerPlaceholder.build()
	model.name = "Model"
	_visual.add_child(model)
	_model_locomotion = model.has_method(&"set_locomotion")
	_model_actions = model.has_method(&"play_action")


func _model_action(action: StringName) -> void:
	if _model_actions:
		model.play_action(action)


func _play_model_action_once(action: StringName, starting: bool) -> void:
	if starting:
		_model_action(action)


func _emit_initial_state() -> void:
	_emit_inventory()
	Events.player_health_changed.emit(health.current, health.max_health)


func _emit_inventory() -> void:
	Events.player_inventory_changed.emit(coins, vials)


func _on_damaged(_amount: float, _source: Node, kind: StringName) -> void:
	Events.player_health_changed.emit(health.current, health.max_health)
	if not health.dead:
		camera_rig.add_trauma(0.35 if kind != &"fall" else 0.5)
		_model_action(&"hit")


func _on_healed(_amount: float) -> void:
	Events.player_health_changed.emit(health.current, health.max_health)


func _on_died(_killer: Node) -> void:
	dead = true
	allomancer.stop_all()
	targeting.release()
	Engine.time_scale = 1.0
	_model_action(&"die")
	Events.player_died.emit()


func _on_pause_toggled(paused: bool) -> void:
	if not capture_mouse or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
