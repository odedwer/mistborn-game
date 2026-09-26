class_name LordRuler
extends EnemyBase
## The Lord Ruler: the final boss of *The Final Empire* arc (Act III, "The
## Lord Ruler"), also standing silent on the execution platform in "Fountain
## Square". A placeholder "boss model": a tall imperial figure in white and
## black, crowned, with a metal bracer on each forearm — built in code until a
## real character model replaces `_make_placeholder_mesh`.
##
## Behaviour is phase-driven (`set_phase`, called by the mission JSON's
## `call_group` action on group `"lord_ruler"`), so the fight's story beats
## stay in data:
## - `DORMANT`: stands still, no perception or attacks (Fountain Square).
## - `SURVIVE` ("survive and learn"): he regenerates almost instantly and
##   coins/blades barely scratch him. Every `push_interval` he Pushes on the
##   metal inside the player — their unburned reserves and carried coins
##   (`metal_exposure`) — knocking them back and hurting them in proportion.
##   Burning the reserves away (flaring drains fastest) and spending coins is
##   the counter. Draining exposure below `learned_exposure` (or surviving
##   `learn_timeout`) sets flag `lr_learned_drain`.
## - `CROWD`: same pressure while the player works the skaa mob outside
##   (soothe their fear, then riot them to rise; the mission's `crowd_mood`
##   objectives).
## - `BRACERS`: he now telegraphs a slam; after it — or after taking a burst
##   of `stagger_burst` damage within `stagger_window` — he is *staggered*
##   for a few seconds. Only while staggered are his bracers (his Feruchemical
##   metalminds) exposed: their `Metallic`s unshield and an Iron Pull on one
##   (`Events.allomantic_line_used` with IRON) rips it off
##   (`try_pull_bracer`), setting `lr_bracer_left` / `lr_bracer_right`.
## - `MORTAL`: both bracers gone. No regeneration, no damage reduction, and
##   he can finally die (the mission's `defeat` objective, target group
##   `"lord_ruler"`).
## Before `MORTAL` his health can never drop below 1.

enum Phase { DORMANT, SURVIVE, CROWD, BRACERS, MORTAL }

const BRACER_LEFT := 0
const BRACER_RIGHT := 1

@export var attack_damage := 32.0
@export var attack_reach := 2.8
@export var attack_cooldown := 1.6
@export var push_interval := 3.5
@export var push_damage := 22.0
@export var push_knockback := 16.0
## Exposure below this (0..1) counts as "the player drained their metals".
@export var learned_exposure := 0.25
@export var learn_timeout := 45.0
@export var slam_interval := 7.0
@export var slam_windup := 1.2
@export var slam_radius := 6.0
@export var slam_damage := 28.0
@export var stagger_time := 3.5
@export var stagger_burst := 90.0
@export var stagger_window := 1.5
@export var immortal_regen := 80.0
## Damage multipliers while he still wears a bracer.
@export var coin_resist := 0.12
@export var blade_resist := 0.3

var phase: int = Phase.DORMANT
var staggered := false
var bracers: Array[Node3D] = [null, null]
var bracer_metals: Array[Metallic] = [null, null]
var times_pushed_player := 0

var _push_timer := 2.0
var _slam_timer := 0.0
var _slam_windup_left := -1.0
var _stagger_left := 0.0
var _attack_cd := 0.0
var _phase_time := 0.0
var _burst: Array[Vector2] = []  # (time, amount)
var _clock := 0.0
var _hinted_push := false
var _learned := false
var _first_exposure := -1.0


func _ready() -> void:
	body_mass = 400.0
	move_speed = 2.2
	chase_speed = 3.6
	can_flee = false
	placeholder_color = Color(0.92, 0.9, 0.86)
	vision_range_base = 60.0
	vision_range_lit = 60.0
	vision_angle_deg = 360.0
	super._ready()
	add_to_group(&"lord_ruler")
	engage_range = attack_reach
	if health:
		health.add_modifier(_modify_damage)
		health.damaged.connect(_on_damaged)
	_build_bracers()
	Events.allomantic_line_used.connect(_on_line_used)
	set_phase(phase)


func _get_model_path() -> String:
	return ""  # placeholder figure below until a real model exists


## Tall imperial figure: flared white robe, black mantle, pale head, a
## crown of gold points. ~2.7 m, a head taller than anyone else in the game.
func _make_placeholder_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "LordRulerFigure"
	var white := _mat(Color(0.93, 0.92, 0.88), 0.0, 0.6)
	var black := _mat(Color(0.05, 0.05, 0.06), 0.0, 0.5)
	var skin := _mat(Color(0.82, 0.74, 0.66), 0.0, 0.7)
	var gold := _mat(Color(0.85, 0.7, 0.3), 0.9, 0.3)
	_part(root, _cyl(0.85, 0.34, 1.7), Vector3(0, 0.85, 0), white)       # robe
	_part(root, _cyl(0.38, 0.46, 0.8), Vector3(0, 2.05, 0), black)        # torso/mantle
	_part(root, _cyl(0.62, 0.5, 0.12), Vector3(0, 2.4, 0), black)         # shoulder mantle
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.44
	_part(root, head, Vector3(0, 2.68, 0), skin)
	for i in 7:
		var a := TAU * float(i) / 7.0
		var spike := _cyl(0.035, 0.0, 0.22)
		_part(root, spike, Vector3(sin(a) * 0.17, 2.9, cos(a) * 0.17), gold)
	for side: float in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.1
		arm.height = 1.0
		var a := _part(root, arm, Vector3(side * 0.52, 1.95, 0.05), white)
		a.rotation.z = side * 0.18
	return root


func _build_bracers() -> void:
	for side in 2:
		var s := -1.0 if side == BRACER_LEFT else 1.0
		var b := Node3D.new()
		b.name = "BracerLeft" if side == BRACER_LEFT else "BracerRight"
		b.position = Vector3(s * 0.6, 1.6, 0.08)
		var mesh := MeshInstance3D.new()
		mesh.mesh = _cyl(0.13, 0.13, 0.32)
		mesh.material_override = _mat(Color(0.8, 0.78, 0.72), 1.0, 0.25)
		b.add_child(mesh)
		add_child(b)
		var m := Metallic.new()
		m.metal_mass = 25.0
		m.shielded = true  # hidden under his power until he's staggered
		b.add_child(m)
		bracers[side] = b
		bracer_metals[side] = m


# --- Phases ----------------------------------------------------------------------

func set_phase(p: int) -> void:
	phase = p
	_phase_time = 0.0
	_slam_timer = slam_interval
	_slam_windup_left = -1.0
	if health:
		health.regen_per_second = 0.0 if p == Phase.MORTAL else immortal_regen
		health.regen_delay = 0.4
	if p == Phase.DORMANT:
		_change_state(State.IDLE)
		target = null
	elif state != State.COMBAT and state != State.DEAD:
		var player := _get_player()
		if player != null:
			target = player
			last_known_target_pos = player.global_position
			_change_state(State.COMBAT)
	if p == Phase.MORTAL:
		_set_staggered(false)
		if health and health.current > health.max_health * 0.3:
			health.current = health.max_health * 0.3
	Events.boss_phase_changed.emit(self, p)


func bracers_remaining() -> int:
	var n := 0
	for b in bracers:
		if b != null:
			n += 1
	return n


## Staggers him for `duration` seconds: his bracers' `Metallic`s unshield so
## an Iron Pull can take them. Only meaningful in `BRACERS`.
func stagger(duration: float = -1.0) -> void:
	if phase != Phase.BRACERS:
		return
	_stagger_left = stagger_time if duration < 0.0 else duration
	_slam_windup_left = -1.0
	_set_staggered(true)
	Events.hint_requested.emit("He's reeling — the bracers! Pull them free with iron!", 2.5)


func _set_staggered(on: bool) -> void:
	staggered = on
	for m in bracer_metals:
		if m != null and is_instance_valid(m):
			m.shielded = not on
	if on:
		_stop_moving()


## Rips bracer `side` off if (and only if) he's staggered in the `BRACERS`
## phase. Returns true when a bracer came off. Both gone -> `MORTAL`.
func try_pull_bracer(side: int, toward: Vector3 = Vector3.INF) -> bool:
	if phase != Phase.BRACERS or not staggered:
		return false
	if side < 0 or side > 1 or bracers[side] == null:
		return false
	var b := bracers[side]
	var m := bracer_metals[side]
	bracers[side] = null
	bracer_metals[side] = null
	if m != null and is_instance_valid(m):
		m.queue_free()
	_fling_bracer(b, toward)
	GameState.set_dialogue_flag(StringName("lr_bracer_left" if side == BRACER_LEFT else "lr_bracer_right"), true)
	AudioManager.play_3d(&"pull", global_position)
	if bracers_remaining() == 0:
		Events.hint_requested.emit("Without them, he's only a man. Finish it.", 3.0)
		set_phase(Phase.MORTAL)
	else:
		Events.hint_requested.emit("One torn away. He's weaker — but the other still holds him together.", 3.0)
	return true


func _fling_bracer(b: Node3D, toward: Vector3) -> void:
	if b == null or not is_instance_valid(b):
		return
	var xf := b.global_transform if b.is_inside_tree() else Transform3D.IDENTITY
	var parent := get_parent()
	remove_child(b)
	if parent == null or not is_inside_tree():
		b.queue_free()
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 1 << 3
	rb.collision_mask = 1
	rb.mass = 3.0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.13
	shape.height = 0.32
	cs.shape = shape
	rb.add_child(cs)
	for c in b.get_children():
		b.remove_child(c)
		rb.add_child(c)
	b.queue_free()
	parent.add_child(rb)
	rb.global_transform = xf
	var dir := Vector3.UP
	if toward != Vector3.INF:
		dir = (toward - xf.origin).normalized() + Vector3.UP * 0.3
	rb.apply_central_impulse(dir * 18.0)
	var m := Metallic.new()
	m.metal_mass = 25.0
	rb.add_child(m)


## How much metal the Lord Ruler can grip inside/on the player, 0..1:
## unburned reserves of the Push/Pull-able and physical metals plus carried
## coins. Burning metal away (or throwing coins) lowers it.
static func metal_exposure(reserves: Dictionary, coins: int) -> float:
	var total := 0.0
	var n := 0
	for m: int in [Metal.Type.STEEL, Metal.Type.IRON, Metal.Type.TIN, Metal.Type.PEWTER, Metal.Type.ZINC, Metal.Type.BRASS, Metal.Type.COPPER, Metal.Type.BRONZE]:
		total += clampf(float(reserves.get(m, 0.0)) / Metal.MAX_RESERVE, 0.0, 1.0)
		n += 1
	var metal_part := total / float(n)
	var coin_part := clampf(float(coins) / 120.0, 0.0, 1.0)
	return clampf(metal_part * 0.75 + coin_part * 0.25, 0.0, 1.0)


## "Survive and learn" is done once the player has drained what he Pushes on:
## nearly empty, or well below what they carried at his first Push — or
## they've simply outlasted `learn_timeout`.
func has_learned(exposure: float, first_exposure: float, phase_time: float) -> bool:
	if phase_time >= learn_timeout:
		return true
	if exposure <= 0.05:
		return true
	return first_exposure > 0.0 and exposure <= minf(learned_exposure, first_exposure * 0.6)


func player_exposure() -> float:
	var player := _get_player()
	if player == null or not ("allomancer" in player) or player.allomancer == null:
		return 0.0
	var coins: int = int(player.coins) if "coins" in player else 0
	return metal_exposure(player.allomancer.reserves, coins)


# --- Damage ----------------------------------------------------------------------

func _modify_damage(amount: float, kind: StringName, _source: Node) -> float:
	if phase == Phase.DORMANT:
		return 0.0
	if phase != Phase.MORTAL:
		if kind == &"coin":
			amount *= coin_resist
		elif kind == &"blade" or kind == &"blunt":
			amount *= blade_resist
		if health:
			amount = minf(amount, maxf(health.current - 1.0, 0.0))
	return amount


func _on_damaged(amount: float, _source: Node, _kind: StringName) -> void:
	# Burst tracking for the stagger (pre-resistance damage isn't visible
	# here, so the burst threshold is tuned against resisted damage).
	_burst.append(Vector2(_clock, amount))
	var sum := 0.0
	var keep: Array[Vector2] = []
	for e in _burst:
		if _clock - e.x <= stagger_window:
			keep.append(e)
			sum += e.y
	_burst = keep
	if phase == Phase.BRACERS and not staggered and sum >= stagger_burst * blade_resist:
		_burst.clear()
		stagger()


func _on_line_used(allomancer: Node, t: Node, metal: int, _strength: float) -> void:
	if metal != Metal.Type.IRON or t == null:
		return
	for side in 2:
		if bracer_metals[side] != null and t == bracer_metals[side]:
			var toward := Vector3.INF
			if allomancer != null and "body" in allomancer and allomancer.body != null:
				toward = (allomancer.body as Node3D).global_position
			try_pull_bracer(side, toward)
			return


# --- Behaviour -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	if phase == Phase.DORMANT:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	super._physics_process(delta)


func _run_perception(_delta: float) -> void:
	if phase == Phase.DORMANT:
		return
	super._run_perception(_delta)


func _update_combat(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = _get_player()
		if target == null:
			return
	last_known_target_pos = target.global_position
	_combat_tick(delta)


func _combat_tick(delta: float) -> void:
	if target == null:
		return
	_phase_time += delta
	if staggered:
		_stagger_left -= delta
		if _stagger_left <= 0.0:
			_set_staggered(false)
		return
	# Pushing on the metal inside the player.
	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = push_interval
		_push_player()
	if phase == Phase.SURVIVE and not _learned and has_learned(player_exposure(), _first_exposure, _phase_time):
		_learned = true
		GameState.set_dialogue_flag(&"lr_learned_drain", true)
		Events.hint_requested.emit("Less metal in you, less for him to grip. Keep it that way.", 3.0)
	# The telegraphed slam, and the stagger that follows it.
	if phase == Phase.BRACERS:
		if _slam_windup_left >= 0.0:
			_slam_windup_left -= delta
			_stop_moving()
			if _slam_windup_left < 0.0:
				_slam()
				stagger()
			return
		_slam_timer -= delta
		if _slam_timer <= 0.0:
			_slam_timer = slam_interval
			_slam_windup_left = slam_windup
			Events.hint_requested.emit("He's gathering himself for a blow — get clear!", 1.2)
			return
	var dist := global_position.distance_to(target.global_position)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if dist <= attack_reach:
		_stop_moving()
		if _attack_cd <= 0.0:
			_attack_cd = attack_cooldown
			var h := target.get_node_or_null(^"Health") as Health
			if h != null:
				h.take_damage(attack_damage, self, &"blunt")
			AudioManager.play_3d(&"hit_flesh", global_position)
	else:
		_move_toward(target.global_position, chase_speed, delta)
	_face_point(target.global_position, delta)


func _push_player() -> void:
	var player := _get_player()
	if player == null:
		return
	var exposure := player_exposure()
	if exposure <= 0.05:
		return
	times_pushed_player += 1
	if _first_exposure < 0.0:
		_first_exposure = exposure
	var dir := player.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity += (dir + Vector3.UP * 0.35) * push_knockback * exposure
	var h := player.get_node_or_null(^"Health") as Health
	if h != null:
		h.take_damage(push_damage * exposure, self, &"crush")
	Events.allomantic_pulse.emit(self, Metal.Type.STEEL, global_position)
	AudioManager.play_3d(&"push", global_position)
	if not _hinted_push:
		_hinted_push = true
		Events.hint_requested.emit("He's Pushing on the metal inside you. Burn your reserves away — flare to empty them fast — and let the coins go.", 5.0)


func _slam() -> void:
	var player := _get_player()
	if player == null:
		return
	if player.global_position.distance_to(global_position) <= slam_radius:
		var h := player.get_node_or_null(^"Health") as Health
		if h != null:
			h.take_damage(slam_damage, self, &"crush")
		if player is CharacterBody3D:
			var away := (player.global_position - global_position)
			away.y = 0.0
			(player as CharacterBody3D).velocity += away.normalized() * 10.0 + Vector3.UP * 5.0
	AudioManager.play_3d(&"hit_flesh", global_position)


## He can't be shoved around by ordinary Pushes.
func receive_allomantic_force(_force: Vector3, _delta: float, _from: Metallic) -> void:
	pass


## Emotional allomancy has no hold on him.
func receive_emotional_allomancy(_kind: StringName, _strength: float) -> void:
	pass


static func _mat(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


static func _cyl(bottom: float, top: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = h
	c.radial_segments = 12
	return c


static func _part(root: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	root.add_child(mi)
	return mi
