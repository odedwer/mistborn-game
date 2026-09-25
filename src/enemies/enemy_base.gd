class_name EnemyBase
extends CharacterBody3D
## Base actor for every enemy type (guard, hazekiller, thug, coinshot, inquisitor).
##
## Provides navigation + avoidance movement, perception (vision cone + LOS +
## hearing), a table-driven state machine, allomantic-force reception,
## emotional allomancy (Riot/Soothe), knockback/fall damage and a
## ragdoll-lite death. Subclasses override [method _combat_tick] and
## [method _get_model_path] to specialise combat behaviour and appearance.

## High level behaviour states. Kept intentionally small and explicit so the
## transition table stays easy to audit.
enum State { IDLE, PATROL, INVESTIGATE, COMBAT, SEARCH, FLEE, STUNNED, DEAD }

## Maps a state to the alert level (0 calm, 1 suspicious, 2 combat) it reports
## to the shared [AlertDirector].
const _ALERT_LEVEL_BY_STATE := {
	State.IDLE: 0, State.PATROL: 0, State.INVESTIGATE: 1, State.SEARCH: 1,
	State.COMBAT: 2, State.FLEE: 2, State.STUNNED: 0, State.DEAD: 0,
}

@export_group("Movement")
@export var move_speed: float = 3.5
@export var chase_speed: float = 4.5
@export var gravity: float = 20.0
## kg-equivalent for allomantic force reactions (get_allomantic_mass).
@export var body_mass: float = 75.0

@export_group("Perception")
@export var vision_range_base: float = 18.0
@export var vision_range_lit: float = 35.0
@export var vision_angle_deg: float = 100.0
@export var eye_height: float = 1.6
@export var lit_check_radius: float = 10.0
@export var lose_sight_time: float = 4.0

@export_group("Combat")
## Distance at which [method _combat_tick] should stop closing and attack.
@export var engage_range: float = 2.0
@export var flee_health_fraction: float = 0.15
@export var can_flee: bool = true
@export var alert_radius: float = 20.0

@export_group("Reactions")
@export var stun_force_threshold: float = 400.0
@export var stun_duration: float = 1.5
@export var max_fall_damage_speed: float = 10.0
@export var fall_damage_scale: float = 4.0
@export var despawn_after_death: float = 30.0
@export var placeholder_color: Color = Color(0.6, 0.6, 0.6)

var health: Health
var nav_agent: NavigationAgent3D
## The instantiated character model (or placeholder mesh). May expose
## set_locomotion(speed, grounded, vertical_speed) / play_action(name).
var model: Node

var state: int = State.IDLE
var target: Node3D = null
var last_known_target_pos: Vector3 = Vector3.ZERO
var patrol_points: PackedVector3Array = PackedVector3Array()
var patrol_index: int = 0
var investigate_point: Vector3 = Vector3.ZERO

var _state_table: Dictionary = {}
var _search_timer: float = 0.0
var _flee_timer: float = 0.0
var _stun_timer: float = 0.0
var _pre_stun_state: int = State.SEARCH
var _lost_los_timer: float = 0.0
var _riled: bool = false
var _soothed_timer: float = 0.0
var _desired_velocity: Vector3 = Vector3.ZERO
var _alert_director: Node = null
var _player_cache: Node3D = null
var _ai_tick_accum: float = 0.0
var _despawn_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	collision_layer = 1 << 2  # enemies
	collision_mask = 1        # world only; other bodies are handled via Areas/raycasts
	health = get_node_or_null(^"Health") as Health
	if health:
		health.died.connect(_on_died)
	nav_agent = get_node_or_null(^"NavAgent") as NavigationAgent3D
	if nav_agent:
		nav_agent.avoidance_enabled = true
		nav_agent.velocity_computed.connect(_on_nav_velocity_computed)
	Events.noise_emitted.connect(_on_noise_emitted)
	_build_state_table()
	_setup_model()
	_change_state(State.IDLE)


func _build_state_table() -> void:
	_state_table = {
		State.IDLE: {"enter": Callable(self, "_enter_idle"), "update": Callable(self, "_update_idle"), "exit": Callable()},
		State.PATROL: {"enter": Callable(self, "_enter_patrol"), "update": Callable(self, "_update_patrol"), "exit": Callable()},
		State.INVESTIGATE: {"enter": Callable(self, "_enter_investigate"), "update": Callable(self, "_update_investigate"), "exit": Callable()},
		State.COMBAT: {"enter": Callable(self, "_enter_combat"), "update": Callable(self, "_update_combat"), "exit": Callable()},
		State.SEARCH: {"enter": Callable(self, "_enter_search"), "update": Callable(self, "_update_search"), "exit": Callable()},
		State.FLEE: {"enter": Callable(self, "_enter_flee"), "update": Callable(self, "_update_flee"), "exit": Callable()},
		State.STUNNED: {"enter": Callable(self, "_enter_stunned"), "update": Callable(self, "_update_stunned"), "exit": Callable()},
		State.DEAD: {"enter": Callable(), "update": Callable(), "exit": Callable()},
	}


# --- Model / placeholder ----------------------------------------------------

## Subclasses return the path to their character model scene.
func _get_model_path() -> String:
	return ""


func _setup_model() -> void:
	var container := get_node_or_null(^"Model") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "Model"
		add_child(container)
	var path := _get_model_path()
	if path != "" and ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		if scene:
			model = scene.instantiate()
			container.add_child(model)
	if model == null:
		model = _make_placeholder_mesh()
		container.add_child(model)


func _make_placeholder_mesh() -> Node3D:
	var mesh_inst := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	mesh_inst.mesh = cap
	mesh_inst.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = placeholder_color
	mesh_inst.material_override = mat
	return mesh_inst


## Registers this enemy's patrol route (called by the spawner).
func set_patrol_points(points: PackedVector3Array) -> void:
	patrol_points = points
	patrol_index = 0


# --- Main loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_despawn_timer -= delta
		if _despawn_timer <= 0.0:
			queue_free()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	var fall_speed_before := velocity.y

	if _soothed_timer > 0.0:
		_soothed_timer = maxf(_soothed_timer - delta, 0.0)

	if _ai_should_tick(delta):
		_run_perception(delta)
		_run_state(delta)

	var was_airborne := not is_on_floor()
	move_and_slide()
	if was_airborne and is_on_floor() and fall_speed_before < -max_fall_damage_speed:
		var over := -fall_speed_before - max_fall_damage_speed
		if health:
			health.take_damage(over * fall_damage_scale, null, &"fall")

	if model and model.has_method("set_locomotion"):
		var horiz := Vector2(velocity.x, velocity.z).length()
		model.call("set_locomotion", horiz, is_on_floor(), velocity.y)


func _run_state(delta: float) -> void:
	var entry: Dictionary = _state_table.get(state, {})
	var update: Callable = entry.get("update", Callable())
	if update.is_valid():
		update.call(delta)


func _change_state(new_state: int) -> void:
	if new_state == state:
		return
	var old_entry: Dictionary = _state_table.get(state, {})
	var exit_fn: Callable = old_entry.get("exit", Callable())
	if exit_fn.is_valid():
		exit_fn.call()
	state = new_state
	_report_alert()
	var new_entry: Dictionary = _state_table.get(state, {})
	var enter_fn: Callable = new_entry.get("enter", Callable())
	if enter_fn.is_valid():
		enter_fn.call()


# --- AI tick throttling -------------------------------------------------------

## 0 => tick every physics frame. <40m from the player: full rate.
## 40-100m: ~5Hz. 100-120m: ~2Hz. Beyond 120m: effectively asleep.
func _ai_interval_for_distance() -> float:
	var player := _get_player()
	if player == null:
		return 0.0
	var d := global_position.distance_to(player.global_position)
	if d < 40.0:
		return 0.0
	elif d < 100.0:
		return 0.2
	elif d < 120.0:
		return 0.5
	return 2.0


func _ai_should_tick(delta: float) -> bool:
	var interval := _ai_interval_for_distance()
	if interval <= 0.0:
		return true
	_ai_tick_accum += delta
	if _ai_tick_accum >= interval:
		_ai_tick_accum = 0.0
		return true
	return false


func _get_player() -> Node3D:
	if _player_cache != null and is_instance_valid(_player_cache):
		return _player_cache
	_player_cache = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player_cache


# --- Perception ----------------------------------------------------------------

func _run_perception(_delta: float) -> void:
	if _soothed_timer > 0.0:
		return
	if state == State.COMBAT or state == State.FLEE or state == State.STUNNED or state == State.DEAD:
		return
	var player := _get_player()
	if player == null:
		return
	if _can_perceive(player):
		target = player
		last_known_target_pos = player.global_position
		_change_state(State.COMBAT)


func _can_perceive(who: Node3D) -> bool:
	var to_target := who.global_position - global_position
	var dist := to_target.length()
	var range_now := vision_range_lit if _is_lit(who.global_position) else vision_range_base
	if dist > range_now:
		return false
	if dist > 0.01:
		var forward := -global_transform.basis.z
		var dir := to_target.normalized()
		var angle := rad_to_deg(acos(clampf(forward.dot(dir), -1.0, 1.0)))
		if angle > vision_angle_deg * 0.5:
			return false
	return _has_line_of_sight(who)


func _has_line_of_sight(who: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * eye_height
	var to := who.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # static world geometry only
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _is_lit(pos: Vector3) -> bool:
	for lantern in get_tree().get_nodes_in_group(&"lantern"):
		if lantern is Node3D and (lantern as Node3D).global_position.distance_to(pos) <= lit_check_radius:
			return true
	return false


func _on_noise_emitted(position: Vector3, loudness: float, source: Node) -> void:
	if state == State.DEAD or state == State.COMBAT or _soothed_timer > 0.0:
		return
	if source == self:
		return
	if global_position.distance_to(position) <= loudness:
		investigate_point = position
		if state != State.INVESTIGATE:
			_change_state(State.INVESTIGATE)


## Called by a nearby ally that just spotted the target (see [method _enter_combat]).
func receive_alert(_from: Node, at_position: Vector3) -> void:
	if state == State.DEAD or state == State.COMBAT or _soothed_timer > 0.0:
		return
	investigate_point = at_position
	_change_state(State.INVESTIGATE)


func _alert_nearby_allies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if e == self or not (e is EnemyBase):
			continue
		var ally := e as EnemyBase
		if global_position.distance_to(ally.global_position) <= alert_radius:
			ally.receive_alert(self, last_known_target_pos)
	AudioManager.play_3d(&"guard_alert", global_position)


func _report_alert() -> void:
	if _alert_director == null or not is_instance_valid(_alert_director):
		_alert_director = get_tree().get_first_node_in_group(&"alert_director")
	if _alert_director:
		_alert_director.call("report", self, _ALERT_LEVEL_BY_STATE.get(state, 0))


# --- Movement helpers ----------------------------------------------------------

func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z


## Steers toward `point` at `speed`, using nav-agent avoidance when present.
func _move_toward(point: Vector3, speed: float, _delta: float) -> void:
	if nav_agent:
		nav_agent.target_position = point
		if nav_agent.is_navigation_finished():
			_desired_velocity = Vector3.ZERO
		else:
			var next_pos := nav_agent.get_next_path_position()
			var dir := next_pos - global_position
			dir.y = 0.0
			_desired_velocity = dir.normalized() * speed if dir.length() > 0.05 else Vector3.ZERO
		nav_agent.set_velocity(_desired_velocity)
	else:
		var dir := point - global_position
		dir.y = 0.0
		_desired_velocity = dir.normalized() * speed if dir.length() > 0.05 else Vector3.ZERO
		velocity.x = _desired_velocity.x
		velocity.z = _desired_velocity.z


func _stop_moving() -> void:
	_desired_velocity = Vector3.ZERO
	if nav_agent:
		nav_agent.set_velocity(Vector3.ZERO)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _face_point(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var target_rot := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, clampf(delta * 6.0, 0.0, 1.0))


# --- States ----------------------------------------------------------------

func _enter_idle() -> void:
	_stop_moving()


func _update_idle(_delta: float) -> void:
	if not patrol_points.is_empty():
		_change_state(State.PATROL)


func _enter_patrol() -> void:
	pass


func _update_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		_change_state(State.IDLE)
		return
	var wp: Vector3 = patrol_points[patrol_index]
	_move_toward(wp, move_speed, delta)
	_face_point(wp, delta)
	if global_position.distance_to(wp) < 1.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()


func _enter_investigate() -> void:
	_search_timer = 5.0


func _update_investigate(delta: float) -> void:
	_move_toward(investigate_point, move_speed, delta)
	_face_point(investigate_point, delta)
	_search_timer -= delta
	if global_position.distance_to(investigate_point) < 1.0 or _search_timer <= 0.0:
		_change_state(State.SEARCH)


func _enter_combat() -> void:
	_lost_los_timer = 0.0
	AudioManager.play_3d(&"guard_alert", global_position)
	_alert_nearby_allies()


func _update_combat(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_change_state(State.SEARCH)
		return
	last_known_target_pos = target.global_position
	if not _riled and can_flee and health and health.ratio() < flee_health_fraction:
		_change_state(State.FLEE)
		return
	if not _riled:
		if _has_line_of_sight(target):
			_lost_los_timer = 0.0
		else:
			_lost_los_timer += delta
			if _lost_los_timer > lose_sight_time:
				_change_state(State.SEARCH)
				return
	_combat_tick(delta)


## Overridden by subclasses to implement type-specific attacks/movement while
## in COMBAT. Default: close to engage_range and stop.
func _combat_tick(delta: float) -> void:
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > engage_range:
		_move_toward(target.global_position, chase_speed, delta)
	else:
		_stop_moving()
	_face_point(target.global_position, delta)


func _enter_search() -> void:
	_search_timer = 6.0


func _update_search(delta: float) -> void:
	_move_toward(last_known_target_pos, move_speed, delta)
	_search_timer -= delta
	if _search_timer <= 0.0:
		_change_state(State.IDLE if patrol_points.is_empty() else State.PATROL)


func _enter_flee() -> void:
	_flee_timer = 3.0


func _update_flee(delta: float) -> void:
	if target and is_instance_valid(target):
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_move_toward(global_position + away.normalized() * 8.0, chase_speed, delta)
	_flee_timer -= delta
	if _flee_timer <= 0.0:
		if health and health.ratio() > flee_health_fraction * 1.5 and target and is_instance_valid(target):
			_change_state(State.COMBAT)
		else:
			_change_state(State.SEARCH)


func _enter_stunned() -> void:
	_stop_moving()


func _update_stunned(delta: float) -> void:
	_stun_timer -= delta
	if _stun_timer <= 0.0:
		_change_state(_pre_stun_state)


# --- Allomantic / emotional reactions ---------------------------------------

## kg-equivalent mass used when resolving allomantic Push/Pull forces.
func get_allomantic_mass() -> float:
	return body_mass


## `Metallic.apply_allomantic_force` calls this for any non-RigidBody target.
func receive_allomantic_force(force: Vector3, delta: float, _from: Metallic) -> void:
	if state == State.DEAD:
		return
	velocity += (force / body_mass) * delta
	if force.length() > stun_force_threshold:
		_stun_timer = stun_duration
		if state != State.STUNNED:
			_pre_stun_state = State.SEARCH if state == State.COMBAT else state
			_change_state(State.STUNNED)


## &"riot" (zinc) makes the enemy aggressive and ignore caution/fleeing.
## &"soothe" (brass) calms them: they lose alert state for a few seconds
## scaled by `strength` (0..1).
func receive_emotional_allomancy(kind: StringName, strength: float) -> void:
	if state == State.DEAD:
		return
	strength = clampf(strength, 0.0, 1.0)
	if kind == &"riot":
		_riled = true
		_soothed_timer = 0.0
		var player := _get_player()
		if player:
			target = player
			last_known_target_pos = player.global_position
			_change_state(State.COMBAT)
		else:
			_change_state(State.SEARCH)
	elif kind == &"soothe":
		_riled = false
		_soothed_timer = 3.0 + strength * 7.0
		_change_state(State.IDLE)


# --- Death -------------------------------------------------------------------

func _on_died(_killer: Node) -> void:
	_change_state(State.DEAD)
	velocity = Vector3.ZERO
	set_collision_layer_value(3, false)
	set_collision_layer_value(7, true)
	AudioManager.play_3d(&"enemy_death", global_position)
	if model and model.has_method("play_action"):
		model.call("play_action", &"die")
		_despawn_timer = despawn_after_death
	else:
		_spawn_ragdoll()
		if model:
			model.visible = false
		_despawn_timer = despawn_after_death


func _spawn_ragdoll() -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1 << 6  # ragdoll
	rb.collision_mask = 1        # world only
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	shape.shape = capsule
	rb.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.4
	cap_mesh.height = 1.7
	mesh_inst.mesh = cap_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = placeholder_color
	mesh_inst.material_override = mat
	rb.add_child(mesh_inst)
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(rb)
	rb.global_transform = global_transform
	rb.apply_impulse(velocity * 0.3 + Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)))
	rb.apply_torque_impulse(Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)))
	var timer := get_tree().create_timer(despawn_after_death)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.queue_free()
	)
