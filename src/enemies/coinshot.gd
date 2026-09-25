class_name Coinshot
extends EnemyBase
## Enemy allomancer: keeps mid range, throws/Pushes coins at the player, and
## steel-jumps between anchored metals to cross roofs. Uses the generic
## `Allomancer` component when it exists (src/allomancy/allomancer.gd);
## otherwise falls back to direct-velocity heuristics so the enemy still
## works before that component lands.

const ALLOMANCER_PATH := "res://src/allomancy/allomancer.gd"
const COIN_SCENE_PATH := "res://src/combat/coin.tscn"

@export var min_range: float = 10.0
@export var max_range: float = 25.0
@export var throw_cooldown: float = 1.6
@export var coin_damage: float = 12.0
@export var coin_speed: float = 30.0
@export var jump_force: float = 14.0
@export var jump_check_radius: float = 12.0

var allomancer: Node = null
var _throw_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _pulse_timer: float = 0.0


func _ready() -> void:
	body_mass = 65.0
	move_speed = 4.5
	chase_speed = 5.5
	placeholder_color = Color(0.3, 0.3, 0.45)
	super._ready()
	engage_range = max_range
	if ResourceLoader.exists(ALLOMANCER_PATH):
		var script: GDScript = load(ALLOMANCER_PATH)
		allomancer = script.new()
		allomancer.name = "Allomancer"
		add_child(allomancer)
		if allomancer.has_method("set_burning"):
			allomancer.call("set_burning", Metal.Type.STEEL, true)


func _get_model_path() -> String:
	return "res://assets/models/characters/coinshot.tscn"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	var burning := true
	if allomancer and allomancer.has_method("is_burning"):
		burning = allomancer.call("is_burning", Metal.Type.STEEL)
	if burning:
		_pulse_timer -= delta
		if _pulse_timer <= 0.0:
			_pulse_timer = 1.0
			Events.allomantic_pulse.emit(self, Metal.Type.STEEL, global_position)


func _combat_tick(delta: float) -> void:
	if target == null:
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var desired := Vector3.ZERO
	if to_target.length() > 0.01:
		var dir := to_target.normalized()
		if dist < min_range:
			desired = -dir
		elif dist > max_range:
			desired = dir
		else:
			desired = dir.rotated(Vector3.UP, PI * 0.5)
	_move_toward(global_position + desired * 4.0, chase_speed, delta)
	_face_point(target.global_position, delta)

	_throw_timer -= delta
	if _throw_timer <= 0.0 and dist <= max_range * 1.2:
		_throw_coin()
		_throw_timer = throw_cooldown

	_jump_cooldown -= delta
	if _jump_cooldown <= 0.0 and randf() < 0.03:
		_try_steel_jump()


func _throw_coin() -> void:
	if target == null:
		return
	var dir := (target.global_position + Vector3.UP * 1.0 - global_position)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var vel := dir * coin_speed
	var from := global_position + Vector3.UP * 1.4
	var m: Metallic = null
	if ResourceLoader.exists(COIN_SCENE_PATH):
		# Pooled like the player's coins: capped and recycled (thrown coins
		# used to be instanced into the scene and never freed).
		var coin := CoinPool.get_for(self).spawn(Transform3D(Basis.IDENTITY, from), vel, self)
		m = coin.metallic
	else:
		var projectile := FallbackCoin.new()
		var parent := get_tree().current_scene if get_tree().current_scene else get_parent()
		parent.add_child(projectile)
		projectile.call("launch", from, vel, self)
		m = projectile.get_node_or_null(^"Metallic") as Metallic
	if m != null and allomancer and allomancer.has_method("push"):
		allomancer.call("push", m, 1.0, get_physics_process_delta_time())
	AudioManager.play_3d(&"javelin_throw", global_position)


## Steel-jumps by pushing off a nearby anchored metal below/behind, so the
## coinshot can vault between roofs. Falls back to a direct velocity boost
## when there is no `Allomancer` component.
func _try_steel_jump() -> void:
	var anchors: Array[Metallic] = MetalRegistry.query_radius(global_position, jump_check_radius)
	var best: Metallic = null
	var best_score := -INF
	for m in anchors:
		if not m.anchored:
			continue
		var to_m := m.global_position - global_position
		if to_m.y > 1.0:
			continue  # only jump off things below/level, not straight up
		var score := -to_m.y
		if score > best_score:
			best_score = score
			best = m
	if best == null:
		return
	var dir := (global_position - best.global_position)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	if allomancer and allomancer.has_method("push"):
		allomancer.call("push", best, 1.0, get_physics_process_delta_time())
	else:
		velocity += dir * jump_force + Vector3.UP * jump_force * 0.6
	_jump_cooldown = 2.5
