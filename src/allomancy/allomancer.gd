class_name Allomancer
extends Node
## Generic allomancy component, shared by the player and enemy allomancers.
##
## Add it as a child of the actor body. The body should implement
## `get_allomantic_mass() -> float` and
## `receive_allomantic_force(force: Vector3, delta: float, from: Metallic)`.
##
## Responsibilities:
## - Metal reserves (0..Metal.MAX_RESERVE), the burning set, and flaring.
## - Burn drain per physics tick (Metal.BURN_RATE, times Metal.FLARE_BURN_MULT
##   while flaring). A metal stops burning automatically when it runs out.
## - Push/Pull (Newton's third law, see docs/ARCHITECTURE.md). The reaction
##   splits by mass: a free light coin takes nearly all the motion, while an
##   anchored or *braced* metal (pressed against static geometry in the push
##   direction) gives the allomancer the full reaction.
## - Duralumin: a short burst that multiplies every other burning metal by
##   DURALUMIN_MULT, then burns their reserves away completely.
## - Internal metals: pewter multipliers and a Health modifier, tin strength,
##   atium time dilation, bronze pulse sensing, copper cloud, zinc/brass on a
##   target.
## - Periodic Events.allomantic_pulse while burning, unless copper is burning.

## Emitted when atium starts or stops affecting this allomancer.
signal atium_changed(active: bool)
## Emitted when a burst of duralumin starts.
signal duralumin_started(metals: Array)
## Emitted when bronze senses a pulse from another allomancer.
signal pulse_sensed(source: Node, metal: int, position: Vector3)

## Effect multiplier applied to every other burning metal during a duralumin burst.
const DURALUMIN_MULT := 10.0
## Collision layer 1: static level geometry.
const WORLD_MASK := 1
## Pewter/tin multipliers are clamped to this effect strength so a duralumin
## burst does not produce absurd movement speeds.
const MAX_INTERNAL_STRENGTH := 3.0

## The body this allomancer acts for. Defaults to the parent.
@export var body: Node3D
## Starting reserves (metal -> amount), applied in `_ready`.
@export var starting_reserves: Dictionary[int, float] = {}
## True for the locally controlled player: tin drives the mist controller's
## vision and atium slows Engine.time_scale. Enemy allomancers leave it off.
@export var controls_local_view := false
## Where lines start, in the body's local space (roughly the chest).
@export var chest_offset := Vector3(0.0, 1.3, 0.0)

@export_group("Push / Pull")
## Force (N) of a full-strength Push/Pull at close range, before flaring.
@export var base_force := 3000.0
## Steel sight and Push/Pull range (m) at normal burn.
@export var line_range := 40.0
## Range multiplier while flaring.
@export var flare_range_mult := 1.5
## Distance (m) up to which the force stays at full strength.
@export var full_strength_distance := 10.0
## Exponent applied to the smoothstep falloff (1 = plain smoothstep).
@export var falloff_exponent := 1.0
## The reaction on the allomancer fades out as they already move away from
## (Push) / toward (Pull) the metal at this speed (m/s), times the effect
## strength (flaring/duralumin raise it). Keeps a held steel-jump to roughly
## rooftop height while chains and dives can still reach 30-80 m/s.
@export var line_speed_limit := 34.0
## Fraction of line_speed_limit where the fade begins.
@export var line_speed_fade_start := 0.45
## Caps the acceleration given to light targets (m/s^2), so a pushed coin
## ramps up to its terminal speed in a few ticks instead of one.
@export var max_target_accel := 1500.0
## How far (m) to look past the metal for static geometry that braces it.
@export var brace_check_distance := 0.35
## Extra reserve per second spent while actively Pushing/Pulling at full intensity.
@export var line_use_drain := 1.0
## Fallback mass when the body does not implement get_allomantic_mass().
@export var default_mass := 60.0

@export_group("Pewter")
@export var pewter_speed_bonus := 0.5
@export var pewter_jump_bonus := 0.5
@export var pewter_damage_bonus := 0.5
@export var pewter_damage_reduction := 0.5
@export var pewter_flared_damage_reduction := 0.7
## Pewter reserve spent per point of damage absorbed.
@export var pewter_absorb_cost := 0.15

@export_group("Timing")
## Seconds between bronze-detectable pulses while burning.
@export var pulse_interval := 0.6
## Length of a duralumin burst (s).
@export var duralumin_burst_duration := 0.25
## Engine.time_scale while atium burns (local view only).
@export var atium_time_scale := 0.6
## How long bronze remembers a sensed pulse (s).
@export var bronze_memory := 3.0
## Seconds between zinc/brass applications on the emotional target.
@export var emotional_interval := 0.1

## Metal reserves, metal -> amount (0..Metal.MAX_RESERVE).
var reserves: Dictionary[int, float] = {}
## True while flaring (applies to every burning metal).
var flaring := false
## Target of zinc (Riot) and brass (Soothe). The controller sets it.
var emotional_target: Node

var _burning := PackedByteArray()
var _last_emitted := PackedFloat32Array()
var _last_line_frame := PackedInt64Array()
var _lines: Array[Metallic] = []
var _lines_frame := -1
var _health: Health
var _pewter_modifier: Callable
var _ray := PhysicsRayQueryParameters3D.new()
var _motion_params := PhysicsTestMotionParameters3D.new()
var _motion_result := PhysicsTestMotionResult3D.new()
var _time := 0.0
var _pulse_timer := 0.0
var _emotional_timer := 0.0
var _last_tin := -1.0
var _atium_active := false
var _dura_active := false
var _dura_time := 0.0
var _dura_flags := PackedByteArray()
var _dura_rate := PackedFloat32Array()
var _pulses: Array[Dictionary] = []


func _init() -> void:
	_burning.resize(Metal.COUNT)
	_dura_flags.resize(Metal.COUNT)
	_dura_rate.resize(Metal.COUNT)
	_last_emitted.resize(Metal.COUNT)
	_last_line_frame.resize(Metal.COUNT)
	for i in Metal.COUNT:
		reserves[i] = 0.0
		_last_emitted[i] = -1.0
		_last_line_frame[i] = -10
	_ray.collision_mask = WORLD_MASK
	_ray.hit_from_inside = false
	_motion_params.margin = 0.02
	_motion_params.recovery_as_collision = true


func _ready() -> void:
	if body == null:
		body = get_parent() as Node3D
	for metal: int in starting_reserves:
		set_reserve(metal, starting_reserves[metal])
	_pewter_modifier = _modify_damage
	if body != null:
		bind_health(body.get_node_or_null(^"Health") as Health)
	Events.allomantic_pulse.connect(_on_allomantic_pulse)


func _exit_tree() -> void:
	if _atium_active and controls_local_view:
		Engine.time_scale = 1.0
		_atium_active = false


func _physics_process(delta: float) -> void:
	tick(delta)


## Registers the pewter damage modifier on `h` (done automatically for a
## sibling named "Health").
func bind_health(h: Health) -> void:
	if _health != null:
		_health.remove_modifier(_pewter_modifier)
	_health = h
	if _health != null:
		_health.add_modifier(_pewter_modifier)


# --- Reserves ---------------------------------------------------------------

func get_reserve(metal: int) -> float:
	return reserves.get(metal, 0.0)


## Adds `amount` (may be negative) and clamps to 0..Metal.MAX_RESERVE.
## Returns the new reserve.
func add_reserve(metal: int, amount: float) -> float:
	return set_reserve(metal, get_reserve(metal) + amount)


func set_reserve(metal: int, amount: float) -> float:
	var v := clampf(amount, 0.0, Metal.MAX_RESERVE)
	reserves[metal] = v
	_emit_reserve(metal, true)
	if v <= 0.0 and is_burning(metal):
		_deplete(metal)
	return v


# --- Burning ----------------------------------------------------------------

func is_burning(metal: int) -> bool:
	return metal >= 0 and metal < Metal.COUNT and _burning[metal] != 0


## Starts or stops burning `metal`. Returns true if the metal is burning
## afterwards (false when the reserve is empty). Burning duralumin triggers a
## burst (see `burn_duralumin`).
func set_burning(metal: int, on: bool) -> bool:
	if metal < 0 or metal >= Metal.COUNT:
		return false
	if metal == Metal.Type.DURALUMIN:
		if on:
			return burn_duralumin()
		if _dura_active:
			_end_duralumin()
		return false
	if on and get_reserve(metal) <= 0.0:
		return false
	if is_burning(metal) == on:
		return on
	_burning[metal] = 1 if on else 0
	_lines_frame = -1
	Events.metal_burn_changed.emit(self, metal, on)
	if flaring:
		Events.metal_flare_changed.emit(self, metal, on)
	if on and body != null and body.is_inside_tree():
		AudioManager.play_3d(&"metal_burn_start", body.global_position)
	if metal == Metal.Type.ATIUM:
		_update_atium()
	elif metal == Metal.Type.TIN:
		_update_tin()
	return on


func toggle_burn(metal: int) -> bool:
	return set_burning(metal, not is_burning(metal))


## Stops every metal (e.g. on death).
func stop_all() -> void:
	for i in Metal.COUNT:
		if is_burning(i):
			set_burning(i, false)
	set_flaring(false)


func set_flaring(on: bool) -> void:
	if flaring == on:
		return
	flaring = on
	_lines_frame = -1
	var any := false
	for i in Metal.COUNT:
		if is_burning(i):
			any = true
			Events.metal_flare_changed.emit(self, i, on)
	if on and any and body != null and body.is_inside_tree():
		AudioManager.play_3d(&"flare", body.global_position)
	_update_tin()


func is_flaring(metal: int) -> bool:
	return flaring and is_burning(metal)


## 0 if `metal` isn't burning, 1 normally, Metal.FLARE_EFFECT_MULT while
## flaring, and times DURALUMIN_MULT during a duralumin burst.
func effect_strength(metal: int) -> float:
	if not is_burning(metal):
		return 0.0
	var s := Metal.FLARE_EFFECT_MULT if flaring else 1.0
	if _dura_active and _dura_flags[metal] != 0:
		s *= DURALUMIN_MULT
	return s


func is_duralumin_active() -> bool:
	return _dura_active


## Triggers a duralumin burst. Needs duralumin in reserve and at least one
## other burning metal. Returns true if the burst started.
func burn_duralumin() -> bool:
	if _dura_active or get_reserve(Metal.Type.DURALUMIN) <= 0.0:
		return false
	var metals: Array = []
	for i in Metal.COUNT:
		_dura_flags[i] = 0
		if i != Metal.Type.DURALUMIN and is_burning(i):
			metals.append(i)
			_dura_flags[i] = 1
			_dura_rate[i] = get_reserve(i) / maxf(duralumin_burst_duration, 0.001)
	if metals.is_empty():
		return false
	_dura_active = true
	_dura_time = duralumin_burst_duration
	_burning[Metal.Type.DURALUMIN] = 1
	_lines_frame = -1
	Events.metal_burn_changed.emit(self, Metal.Type.DURALUMIN, true)
	Events.duralumin_burst.emit(self, metals)
	duralumin_started.emit(metals)
	if body != null and body.is_inside_tree():
		AudioManager.play_3d(&"flare", body.global_position, 6.0, 0.6)
	_update_tin()
	return true


# --- Simulation -------------------------------------------------------------

## Advances burn drain, duralumin, pulses and internal metals by `delta`.
## Called from `_physics_process`; tests call it directly.
func tick(delta: float) -> void:
	_time += delta
	var flare_mult := Metal.FLARE_BURN_MULT if flaring else 1.0
	for i in Metal.COUNT:
		if _burning[i] == 0 or i == Metal.Type.DURALUMIN:
			continue
		var rate: float = Metal.BURN_RATE[i] * flare_mult
		if _dura_active and _dura_flags[i] != 0:
			rate = maxf(rate, _dura_rate[i])
		_drain(i, rate * delta)
	if _dura_active:
		_dura_time -= delta
		_drain(Metal.Type.DURALUMIN, Metal.BURN_RATE[Metal.Type.DURALUMIN] * delta)
		if _dura_active and _dura_time <= 0.0:
			_end_duralumin()
	_tick_pulses(delta)
	_tick_emotional(delta)


func _drain(metal: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var v := maxf(get_reserve(metal) - amount, 0.0)
	reserves[metal] = v
	_emit_reserve(metal, v <= 0.0)
	if v <= 0.0:
		_deplete(metal)


func _deplete(metal: int) -> void:
	if not is_burning(metal):
		return
	set_burning(metal, false)
	Events.metal_depleted.emit(self, metal)
	if body != null and body.is_inside_tree():
		AudioManager.play_3d(&"metal_depleted", body.global_position)


func _end_duralumin() -> void:
	_dura_active = false
	for i in Metal.COUNT:
		if _dura_flags[i] != 0:
			_dura_flags[i] = 0
			reserves[i] = 0.0
			_emit_reserve(i, true)
			_deplete(i)
	if _burning[Metal.Type.DURALUMIN] != 0:
		_burning[Metal.Type.DURALUMIN] = 0
		Events.metal_burn_changed.emit(self, Metal.Type.DURALUMIN, false)
	_lines_frame = -1
	_update_tin()


func _emit_reserve(metal: int, force: bool) -> void:
	var v := get_reserve(metal)
	if force or absf(v - _last_emitted[metal]) >= 0.25:
		_last_emitted[metal] = v
		Events.metal_reserve_changed.emit(self, metal, v)


func _tick_pulses(delta: float) -> void:
	_pulse_timer += delta
	if _pulse_timer >= pulse_interval:
		_pulse_timer = 0.0
		if not is_burning(Metal.Type.COPPER) and body != null and body.is_inside_tree():
			var p := body.global_position
			for i in Metal.COUNT:
				if _burning[i] != 0:
					Events.allomantic_pulse.emit(body, i, p)
	if not _pulses.is_empty() and _time - float(_pulses[0]["time"]) > bronze_memory:
		_pulses.pop_front()


func _tick_emotional(delta: float) -> void:
	var zinc := is_burning(Metal.Type.ZINC)
	var brass := is_burning(Metal.Type.BRASS)
	if not (zinc or brass):
		return
	_emotional_timer += delta
	if _emotional_timer < emotional_interval:
		return
	_emotional_timer = 0.0
	if emotional_target == null or not is_instance_valid(emotional_target):
		return
	if not emotional_target.has_method(&"receive_emotional_allomancy"):
		return
	if zinc:
		emotional_target.receive_emotional_allomancy(&"riot", effect_strength(Metal.Type.ZINC))
	if brass:
		emotional_target.receive_emotional_allomancy(&"soothe", effect_strength(Metal.Type.BRASS))


# --- Push / Pull ------------------------------------------------------------

## Falloff 1.0 up to `near`, smoothstepping to 0 at `far`.
static func falloff(distance: float, far: float, near: float = 3.0, exponent: float = 1.0) -> float:
	if distance >= far:
		return 0.0
	return pow(1.0 - smoothstep(near, far, distance), exponent)


## Current Push/Pull and steel-sight range (m).
func current_range() -> float:
	var r := line_range
	if flaring:
		r *= flare_range_mult
	if _dura_active:
		r *= 1.5
	return r


## World-space point lines start from.
func line_origin() -> Vector3:
	if body == null:
		return Vector3.ZERO
	return body.global_transform * chest_offset


## True if `target` can be Pushed/Pulled at all.
func can_affect(target: Metallic) -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() \
		and not target.shielded and target.body != body


## Push `target` (steel). `intensity` is 0..1. Returns the force (N) applied.
func push(target: Metallic, intensity: float, delta: float) -> float:
	return _apply_line(target, intensity, delta, 1.0, Metal.Type.STEEL)


## Pull `target` (iron). `intensity` is 0..1. Returns the force (N) applied.
func pull(target: Metallic, intensity: float, delta: float) -> float:
	return _apply_line(target, intensity, delta, -1.0, Metal.Type.IRON)


## Force (N) a Push/Pull on a metal at `distance` would have right now,
## ignoring bracing and mass split. 0 if the metal isn't burning.
func line_force(metal: int, distance: float, intensity: float = 1.0) -> float:
	var rng := current_range()
	return base_force * effect_strength(metal) * clampf(intensity, 0.0, 1.0) \
		* falloff(distance, rng, full_strength_distance, falloff_exponent)


func _apply_line(target: Metallic, intensity: float, delta: float, polarity: float, metal: int) -> float:
	if not is_burning(metal) or not can_affect(target) or body == null:
		return 0.0
	var origin := line_origin()
	var to := target.global_position - origin
	var dist := to.length()
	if dist < 0.001:
		return 0.0
	var f := line_force(metal, dist, intensity)
	if f <= 0.0:
		return 0.0
	var dir := to / dist
	var move_dir := dir * polarity  # direction the target is driven
	var self_mass := get_self_mass()
	var target_mass := target.get_body_mass()
	var self_share := 1.0
	var target_share := 0.0
	if not is_inf(target_mass):
		var free_share := target_mass / (target_mass + self_mass)
		target_share = 1.0 - free_share
		self_share = lerpf(free_share, 1.0, brace_factor(target, move_dir))
	# The target (if movable) gets its share, capped for very light objects.
	if target_share > 0.0:
		var tf := minf(f * target_share, target_mass * max_target_accel)
		target.apply_allomantic_force(move_dir * tf, delta)
	if self_share > 0.0 and body is CharacterBody3D:
		self_share *= _speed_limit_factor((body as CharacterBody3D).velocity.dot(-move_dir), effect_strength(metal))
	if self_share > 0.0 and body.has_method(&"receive_allomantic_force"):
		body.receive_allomantic_force(-move_dir * (f * self_share), delta, target)
	if target.body != null and target.body.has_method(&"set_last_pusher"):
		target.body.set_last_pusher(body)
	_drain(metal, line_use_drain * clampf(intensity, 0.0, 1.0) * delta * (Metal.FLARE_BURN_MULT if flaring else 1.0))
	var frame := Engine.get_physics_frames()
	if frame - _last_line_frame[metal] > 2:
		AudioManager.play_3d(&"push" if polarity > 0.0 else &"pull", origin)
	_last_line_frame[metal] = frame
	Events.allomantic_line_used.emit(self, target, metal, clampf(f / (base_force * Metal.FLARE_EFFECT_MULT), 0.0, 1.0))
	return f


## 1 below the fade start, falling to 0 at the (strength-scaled) line speed limit.
func _speed_limit_factor(speed_along: float, strength: float) -> float:
	var limit := line_speed_limit * maxf(strength, 1.0)
	var start := limit * line_speed_fade_start
	if speed_along <= start:
		return 1.0
	return clampf((limit - speed_along) / (limit - start), 0.0, 1.0)


## True if a Push/Pull on `metal` was applied during this or the last tick.
func is_using_line(metal: int) -> bool:
	return Engine.get_physics_frames() - _last_line_frame[metal] <= 1


func get_self_mass() -> float:
	if body != null and body.has_method(&"get_allomantic_mass"):
		return body.get_allomantic_mass()
	return default_mass


## 0..1: how firmly `target` is pressed against static geometry when driven
## along `move_dir`. 1 means it acts as an anchor (the allomancer gets the
## full reaction), e.g. a coin on the floor Pushed from above.
func brace_factor(target: Metallic, move_dir: Vector3) -> float:
	if target.body != null and target.body.has_method(&"is_virtual_anchor") \
			and target.body.is_virtual_anchor():
		return 1.0
	if body == null or not body.is_inside_tree():
		return 0.0
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var normal := Vector3.ZERO
	_ray.from = target.global_position
	_ray.to = target.global_position + move_dir * brace_check_distance
	var hit := space.intersect_ray(_ray)
	if not hit.is_empty():
		normal = hit["normal"]
	elif target.body is PhysicsBody3D:
		# The metal may sit well inside a big body (a crate): test the whole body.
		var pb := target.body as PhysicsBody3D
		_motion_params.from = pb.global_transform
		_motion_params.motion = move_dir * brace_check_distance
		if PhysicsServer3D.body_test_motion(pb.get_rid(), _motion_params, _motion_result):
			var collider := _motion_result.get_collider()
			if _is_static_collider(collider):
				normal = _motion_result.get_collision_normal()
	if normal == Vector3.ZERO:
		return 0.0
	return smoothstep(0.2, 0.7, -move_dir.dot(normal))


static func _is_static_collider(o: Object) -> bool:
	if o is StaticBody3D or o is AnimatableBody3D:
		return true
	if o is CollisionObject3D:
		return ((o as CollisionObject3D).collision_layer & WORLD_MASK) != 0
	return false


## Every unshielded Metallic within range, excluding the allomancer's own
## metal. Empty unless steel or iron is burning. Cached per physics frame;
## the returned array is reused, so copy it if you need to keep it.
func lines_in_range(force_refresh: bool = false) -> Array[Metallic]:
	var frame := Engine.get_physics_frames()
	if frame == _lines_frame and not force_refresh:
		return _lines
	_lines_frame = frame
	_lines.clear()
	if body == null or not body.is_inside_tree():
		return _lines
	if not (is_burning(Metal.Type.STEEL) or is_burning(Metal.Type.IRON)):
		return _lines
	var found := MetalRegistry.query_radius(line_origin(), current_range())
	for m in found:
		if is_instance_valid(m) and m.body != body:
			_lines.append(m)
	return _lines


# --- Internal metals --------------------------------------------------------

func pewter_strength() -> float:
	return minf(effect_strength(Metal.Type.PEWTER), MAX_INTERNAL_STRENGTH)


## Movement speed multiplier (1 when pewter isn't burning).
func speed_multiplier() -> float:
	return 1.0 + pewter_speed_bonus * pewter_strength()


## Jump velocity multiplier (1 when pewter isn't burning).
func jump_multiplier() -> float:
	return 1.0 + pewter_jump_bonus * pewter_strength()


## Melee damage multiplier (1 when pewter isn't burning).
func damage_multiplier() -> float:
	return 1.0 + pewter_damage_bonus * pewter_strength()


## Fraction of incoming damage pewter currently absorbs (0..1).
func damage_reduction() -> float:
	var s := effect_strength(Metal.Type.PEWTER)
	if s <= 0.0:
		return 0.0
	if s > DURALUMIN_MULT * 0.9:
		return 0.95
	return pewter_flared_damage_reduction if s > 1.01 else pewter_damage_reduction


func _modify_damage(amount: float, _kind: StringName, _source: Node) -> float:
	var red := damage_reduction()
	if red <= 0.0:
		return amount
	var absorbed := amount * red
	_drain(Metal.Type.PEWTER, absorbed * pewter_absorb_cost)
	return amount - absorbed


## 0..1 tin sense strength: 0 off, 0.65 burning, 1 flared.
func tin_strength() -> float:
	return clampf(effect_strength(Metal.Type.TIN) * 0.65, 0.0, 1.0)


func _update_tin() -> void:
	if not controls_local_view or not is_inside_tree():
		return
	var v := tin_strength()
	if absf(v - _last_tin) < 0.001:
		return
	_last_tin = v
	var mc := get_tree().get_first_node_in_group(&"mist_controller")
	if mc != null and mc.has_method(&"set_tin_vision"):
		mc.set_tin_vision(v)


func is_atium_active() -> bool:
	return _atium_active


func _update_atium() -> void:
	var on := is_burning(Metal.Type.ATIUM)
	if on == _atium_active:
		return
	_atium_active = on
	if controls_local_view:
		Engine.time_scale = atium_time_scale if on else 1.0
	atium_changed.emit(on)
	Events.atium_vision_changed.emit(self, on)


## Pulses sensed by bronze in the last `bronze_memory` seconds, oldest first.
## Each entry: {source: Node, metal: int, position: Vector3, age: float}.
func get_recent_pulses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _pulses:
		var age := _time - float(p["time"])
		if age <= bronze_memory:
			out.append({"source": p["source"], "metal": p["metal"], "position": p["position"], "age": age})
	return out


func _on_allomantic_pulse(source: Node, metal: int, position: Vector3) -> void:
	if source == body or not is_burning(Metal.Type.BRONZE):
		return
	_pulses.append({"source": source, "metal": metal, "position": position, "time": _time})
	if _pulses.size() > 64:
		_pulses.pop_front()
	pulse_sensed.emit(source, metal, position)
	if controls_local_view:
		Events.allomantic_pulse_sensed.emit(source, metal, position)
