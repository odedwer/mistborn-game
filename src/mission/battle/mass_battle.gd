class_name MassBattle
extends Node3D
## Lightweight mass-battle simulation for Act III's set pieces (Yeden's skaa
## army drilling in the caves, then crushed by the Luthadel garrison).
##
## Soldiers are plain data (`Soldier`, no nodes, no physics bodies) stepped by
## this one manager in `_physics_process`, per docs/ARCHITECTURE.md's
## performance rules, and drawn with one `MultiMeshInstance3D` per faction
## (plus one for the fallen). At most `max_active` soldiers are simulated at
## once; `spawn()` beyond that queues them as reinforcements that march in as
## slots free up (a death, or a routed soldier escaping off the field).
##
## Per-soldier logic is deliberately cheap:
## - **Factions**: `REBEL` (skaa army) and `GARRISON`. Everyone of the other
##   faction is hostile (`is_hostile`); no friendly fire.
## - **States**: `ADVANCE` (march on the faction's `advance_target`),
##   `ENGAGE` (close on and strike the nearest hostile in `sight_radius`),
##   `ROUT` (run for `retreat_point`; escaping there frees the slot),
##   `DRILL` (spar in place, the caves), `DEAD`.
## - **Morale** (0..100): drops when outnumbered nearby, when an ally dies
##   close by and when badly wounded; recovers when not threatened and near a
##   rallying player (`rally_node`, for rebels). Below `rout_threshold` a
##   soldier routs; a router that recovers past `rally_threshold` turns back.
## - **LOD**: soldiers beyond `lod_distance` from the camera/player think at
##   `lod_tick` Hz instead of every tick; the MultiMesh itself has a
##   visibility range.
##
## The player interacts through `damage_at()` (coins in flight are checked
## automatically: any active `Coin` faster than `coin_kill_speed` fells a
## garrison soldier it passes through), and garrison soldiers adjacent to
## the player strike them.
##
## Soldier positions (and `advance_target`/`retreat_point`/`spawn_point`,
## and `damage_at`'s point) are in this node's local space.

signal soldier_died(faction: int, position: Vector3)
signal soldier_routed(faction: int)
signal soldier_escaped(faction: int)
## A faction has no active soldiers left and no reinforcements queued, or
## every active one is routing.
signal faction_broken(faction: int)

enum Faction { REBEL, GARRISON }
enum SoldierState { ADVANCE, ENGAGE, ROUT, DRILL, DEAD }

class Soldier:
	var id: int
	var faction: int
	var pos: Vector3
	var vel: Vector3 = Vector3.ZERO
	var facing: float = 0.0
	var hp: float = 100.0
	var max_hp: float = 100.0
	var morale: float = 60.0
	var state: int = SoldierState.ADVANCE
	var target: Soldier = null
	var attack_cd: float = 0.0
	var think_accum: float = 0.0
	var drill_home: Vector3 = Vector3.ZERO
	var drill_phase: float = 0.0

@export var max_active := 60
@export var ground_y := 0.0
@export var sight_radius := 16.0
@export var engage_reach := 1.3
@export var march_speed := 2.4
@export var charge_speed := 3.6
@export var rout_speed := 4.2
@export var separation := 0.9
@export var rout_threshold := 25.0
@export var rally_threshold := 50.0
@export var lod_distance := 45.0
@export var lod_tick := 5.0
@export var coin_kill_speed := 10.0
## Damage a garrison soldier's strike does to the player.
@export var player_strike_damage := 9.0
@export var visibility_range := 260.0
## Rebels within this distance of `rally_node` gain morale over time.
@export var rally_radius := 10.0
@export var max_corpses := 90

## Per-faction tuning, indexed by `Faction`.
var start_morale: Array[float] = [55.0, 85.0]
var damage: Array[float] = [9.0, 16.0]
var max_hp: Array[float] = [80.0, 110.0]
var attack_interval: Array[float] = [1.1, 0.9]
## Where each faction marches when it has nobody to fight.
var advance_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Where routers run (and escape) to.
var retreat_point: Array[Vector3] = [Vector3(0, 0, 60), Vector3(0, 0, -60)]
## Where queued reinforcements appear.
var spawn_point: Array[Vector3] = [Vector3(0, 0, 30), Vector3(0, 0, -30)]
var spawn_spread := 8.0

## Optional: the player node (for strikes, coins, rally, LOD focus).
var rally_node: Node3D

var soldiers: Array[Soldier] = []
var _reserve: Array[int] = [0, 0]
var _dead: Array[int] = [0, 0]
var _escaped: Array[int] = [0, 0]
var _routed_total: Array[int] = [0, 0]
var _broken: Array[bool] = [false, false]
var _next_id := 0
var _rng := RandomNumberGenerator.new()
var _mm: Array[MultiMeshInstance3D] = []
var _corpse_mm: MultiMeshInstance3D
var _corpses: Array[Transform3D] = []
var _corpse_next := 0
var _player_strike_cd := 0.0
var _simulate := true


func _init() -> void:
	_rng.seed = 7331


func _ready() -> void:
	add_to_group(&"mass_battle")
	_build_visuals()


# --- Public API ---------------------------------------------------------------

static func is_hostile(a: int, b: int) -> bool:
	return a != b


## Spawns a soldier of `faction` at `pos` (or queues it as a reinforcement at
## the faction's `spawn_point` when `max_active` is already reached). Returns
## the soldier, or null if it was queued.
func spawn(faction: int, pos: Vector3, state: int = SoldierState.ADVANCE) -> Soldier:
	if active_count() >= max_active:
		_reserve[faction] += 1
		return null
	var s := Soldier.new()
	s.id = _next_id
	_next_id += 1
	s.faction = faction
	s.pos = Vector3(pos.x, ground_y, pos.z)
	s.max_hp = max_hp[faction]
	s.hp = s.max_hp
	s.morale = start_morale[faction]
	s.state = state
	s.drill_home = s.pos
	s.drill_phase = _rng.randf() * TAU
	s.facing = 0.0 if faction == Faction.REBEL else PI
	s.think_accum = _rng.randf() / lod_tick
	soldiers.append(s)
	_broken[faction] = false
	return s


## Spawns `count` soldiers in a loose block centred on `center` (rows along
## X). Anything over the cap is queued as reinforcements.
func spawn_block(faction: int, center: Vector3, count: int, columns: int = 8, spacing: float = 1.6, state: int = SoldierState.ADVANCE) -> void:
	for i in count:
		var col := i % columns
		var row := i / columns
		var off := Vector3((float(col) - float(columns - 1) * 0.5) * spacing, 0.0, float(row) * spacing * (1.0 if faction == Faction.REBEL else -1.0))
		off += Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		spawn(faction, center + off, state)


## Queues `count` reinforcements for `faction` without spawning any now.
func add_reserves(faction: int, count: int) -> void:
	_reserve[faction] += count


func active_count(faction: int = -1) -> int:
	var n := 0
	for s in soldiers:
		if s.state != SoldierState.DEAD and (faction < 0 or s.faction == faction):
			n += 1
	return n


func reserve_count(faction: int) -> int:
	return _reserve[faction]


func dead_count(faction: int) -> int:
	return _dead[faction]


func escaped_count(faction: int) -> int:
	return _escaped[faction]


func routing_count(faction: int) -> int:
	var n := 0
	for s in soldiers:
		if s.faction == faction and s.state == SoldierState.ROUT:
			n += 1
	return n


func average_morale(faction: int) -> float:
	var total := 0.0
	var n := 0
	for s in soldiers:
		if s.faction == faction and s.state != SoldierState.DEAD:
			total += s.morale
			n += 1
	return total / float(n) if n > 0 else 0.0


func is_broken(faction: int) -> bool:
	return _broken[faction]


## Applies `amount` damage to every soldier of `faction` (-1 = any) within
## `radius` of `point`. Returns how many were hit.
func damage_at(point: Vector3, radius: float, amount: float, faction: int = -1) -> int:
	var hits := 0
	for s in soldiers:
		if s.state == SoldierState.DEAD or (faction >= 0 and s.faction != faction):
			continue
		var d := Vector2(s.pos.x - point.x, s.pos.z - point.z).length()
		if d <= radius:
			_hurt(s, amount)
			hits += 1
	return hits


## Drops morale of `faction` soldiers within `radius` of `point` by `amount`
## (a terrifying Inquisitor arriving, a charge, a Push through the ranks).
func shock_at(point: Vector3, radius: float, amount: float, faction: int = -1) -> void:
	for s in soldiers:
		if s.state == SoldierState.DEAD or (faction >= 0 and s.faction != faction):
			continue
		if Vector2(s.pos.x - point.x, s.pos.z - point.z).length() <= radius:
			s.morale = clampf(s.morale - amount, 0.0, 100.0)


## Switches every drilling soldier to `state` (the caves' drill ends).
func set_all_state(faction: int, state: int) -> void:
	for s in soldiers:
		if s.faction == faction and s.state != SoldierState.DEAD:
			s.state = state


## Pauses/resumes the simulation (visuals keep drawing).
func set_simulating(on: bool) -> void:
	_simulate = on


# --- Simulation -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _simulate:
		step(delta)


func _process(_delta: float) -> void:
	_update_visuals()


## Advances the whole battle by `delta` seconds. Public so tests (and a
## scripted fast-forward) can drive it without a running scene.
func step(delta: float) -> void:
	var focus := _focus_position()
	_player_strike_cd = maxf(_player_strike_cd - delta, 0.0)
	for s in soldiers:
		if s.state == SoldierState.DEAD:
			continue
		s.attack_cd = maxf(s.attack_cd - delta, 0.0)
		# LOD: far soldiers think at lod_tick Hz, but still move every tick.
		var far := focus != Vector3.INF and s.pos.distance_to(focus) > lod_distance
		s.think_accum += delta
		if not far or s.think_accum >= 1.0 / lod_tick:
			_think(s, s.think_accum)
			s.think_accum = 0.0
		_move(s, delta)
	_check_coins()
	_cleanup_and_reinforce()
	_check_broken()


func _think(s: Soldier, dt: float) -> void:
	match s.state:
		SoldierState.DRILL:
			return
		SoldierState.ROUT:
			var threat := _count_near(s.pos, 1 - s.faction, 12.0)
			if threat == 0:
				s.morale = minf(s.morale + 4.0 * dt, 100.0)
			if s.morale >= rally_threshold:
				s.state = SoldierState.ADVANCE
			return
	_update_morale(s, dt)
	if s.morale < rout_threshold:
		s.state = SoldierState.ROUT
		s.target = null
		_routed_total[s.faction] += 1
		soldier_routed.emit(s.faction)
		return
	if s.target == null or s.target.state == SoldierState.DEAD or s.target.pos.distance_to(s.pos) > sight_radius * 1.2:
		s.target = _nearest_hostile(s)
	s.state = SoldierState.ENGAGE if s.target != null else SoldierState.ADVANCE
	if s.target != null and s.pos.distance_to(s.target.pos) <= engage_reach and s.attack_cd <= 0.0:
		s.attack_cd = attack_interval[s.faction] * _rng.randf_range(0.85, 1.2)
		_hurt(s.target, damage[s.faction] * _rng.randf_range(0.7, 1.3))


## Local odds and wounds drive morale; see the class doc.
func _update_morale(s: Soldier, dt: float) -> void:
	var allies := _count_near(s.pos, s.faction, 8.0)  # includes self
	var foes := _count_near(s.pos, 1 - s.faction, 8.0)
	if foes > 0:
		var ratio := float(foes) / float(maxi(allies, 1))
		if ratio > 1.0:
			s.morale -= (ratio - 1.0) * 6.0 * dt
	else:
		s.morale += 1.5 * dt
	if s.hp < s.max_hp * 0.35:
		s.morale -= 4.0 * dt
	if s.faction == Faction.REBEL and rally_node != null and is_instance_valid(rally_node):
		if s.pos.distance_to(_local(rally_node.global_position)) <= rally_radius:
			s.morale += 5.0 * dt
	s.morale = clampf(s.morale, 0.0, 100.0)


func _move(s: Soldier, delta: float) -> void:
	var goal := s.pos
	var speed := 0.0
	match s.state:
		SoldierState.ADVANCE:
			goal = advance_target[s.faction]
			speed = march_speed
		SoldierState.ENGAGE:
			if s.target != null:
				goal = s.target.pos
				speed = charge_speed if s.pos.distance_to(goal) > engage_reach * 0.9 else 0.0
		SoldierState.ROUT:
			goal = retreat_point[s.faction]
			speed = rout_speed
		SoldierState.DRILL:
			# Sparring in place: a small lunge back and forth.
			s.drill_phase += delta * 2.6
			goal = s.drill_home + Vector3(0, 0, sin(s.drill_phase) * 0.35)
			speed = 1.2
	var to := goal - s.pos
	to.y = 0.0
	var want := Vector3.ZERO
	if speed > 0.0 and to.length() > 0.15:
		want = to.normalized() * speed
	# Cheap separation from nearby soldiers (n <= 60, so O(n^2) is fine).
	if s.state != SoldierState.DRILL:
		for o in soldiers:
			if o == s or o.state == SoldierState.DEAD:
				continue
			var d := s.pos - o.pos
			d.y = 0.0
			var l := d.length()
			if l < separation and l > 0.001:
				want += d / l * (separation - l) * 3.0
	s.vel = s.vel.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	s.pos += s.vel * delta
	s.pos.y = ground_y
	var look := (s.target.pos - s.pos) if s.state == SoldierState.ENGAGE and s.target != null else s.vel
	if Vector2(look.x, look.z).length() > 0.05:
		s.facing = lerp_angle(s.facing, atan2(look.x, look.z), clampf(delta * 8.0, 0.0, 1.0))
	# Garrison soldiers next to the player strike them.
	if s.faction == Faction.GARRISON and rally_node != null and is_instance_valid(rally_node) and _player_strike_cd <= 0.0:
		if s.pos.distance_to(_local(rally_node.global_position)) <= engage_reach + 0.3:
			_player_strike_cd = 0.9
			var h := rally_node.get_node_or_null(^"Health") as Health
			if h != null:
				h.take_damage(player_strike_damage, null, &"blade")


func _hurt(s: Soldier, amount: float) -> void:
	if s.state == SoldierState.DEAD:
		return
	s.hp -= amount
	if s.hp <= 0.0:
		_kill(s)


func _kill(s: Soldier) -> void:
	s.state = SoldierState.DEAD
	s.target = null
	_dead[s.faction] += 1
	_add_corpse(s)
	# Allies who saw it lose heart.
	for o in soldiers:
		if o.state != SoldierState.DEAD and o.faction == s.faction and o.pos.distance_to(s.pos) <= 10.0:
			o.morale = maxf(o.morale - 8.0, 0.0)
	soldier_died.emit(s.faction, s.pos)


func _nearest_hostile(s: Soldier) -> Soldier:
	var best: Soldier = null
	var best_d := sight_radius
	for o in soldiers:
		if o.state == SoldierState.DEAD or not is_hostile(s.faction, o.faction):
			continue
		var d := s.pos.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


func _count_near(p: Vector3, faction: int, r: float) -> int:
	var n := 0
	var r2 := r * r
	for o in soldiers:
		if o.faction == faction and o.state != SoldierState.DEAD and o.state != SoldierState.ROUT:
			if (o.pos - p).length_squared() <= r2:
				n += 1
	return n


func _check_coins() -> void:
	if not is_inside_tree():
		return
	for c in get_tree().get_nodes_in_group(&"coin"):
		var coin := c as RigidBody3D
		if coin == null or ("active" in coin and not coin.active):
			continue
		if coin.linear_velocity.length() < coin_kill_speed:
			continue
		if damage_at(_local(coin.global_position), 0.7, 200.0, Faction.GARRISON) > 0:
			coin.linear_velocity *= 0.3


func _cleanup_and_reinforce() -> void:
	var keep: Array[Soldier] = []
	for s in soldiers:
		if s.state == SoldierState.DEAD:
			continue
		if s.state == SoldierState.ROUT and s.pos.distance_to(retreat_point[s.faction]) < 2.5:
			_escaped[s.faction] += 1
			soldier_escaped.emit(s.faction)
			continue
		keep.append(s)
	soldiers = keep
	for f in [Faction.REBEL, Faction.GARRISON]:
		while _reserve[f] > 0 and active_count() < max_active:
			_reserve[f] -= 1
			var p: Vector3 = spawn_point[f] + Vector3(_rng.randf_range(-spawn_spread, spawn_spread), 0, _rng.randf_range(-2.0, 2.0))
			spawn(f, p)


func _check_broken() -> void:
	for f in [Faction.REBEL, Faction.GARRISON]:
		if _broken[f]:
			continue
		var active := 0
		var routing := 0
		for s in soldiers:
			if s.faction == f and s.state != SoldierState.DEAD:
				active += 1
				if s.state == SoldierState.ROUT:
					routing += 1
		var ever := _dead[f] + _escaped[f] + active
		if ever == 0:
			continue
		if (active == 0 and _reserve[f] == 0) or (active > 0 and routing == active):
			_broken[f] = true
			faction_broken.emit(f)


func _focus_position() -> Vector3:
	if rally_node != null and is_instance_valid(rally_node):
		return _local(rally_node.global_position)
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			return _local(cam.global_position)
	return Vector3.INF


## Soldier positions live in this node's local space; convert world points.
func _local(p: Vector3) -> Vector3:
	return to_local(p) if is_inside_tree() else p


# --- Visuals ---------------------------------------------------------------------

func _build_visuals() -> void:
	var colors := [Color(0.42, 0.33, 0.24), Color(0.36, 0.38, 0.42)]
	for f in 2:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Faction%d" % f
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _soldier_mesh(f)
		mm.instance_count = max_active
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = colors[f]
		mat.roughness = 0.9
		mat.metallic = 0.35 if f == Faction.GARRISON else 0.0
		mmi.material_override = mat
		mmi.visibility_range_end = visibility_range
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mm.append(mmi)
	_corpse_mm = MultiMeshInstance3D.new()
	_corpse_mm.name = "Fallen"
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.use_colors = true
	cm.mesh = _soldier_mesh(Faction.REBEL)
	cm.instance_count = max_corpses
	cm.visible_instance_count = 0
	_corpse_mm.multimesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.albedo_color = Color(0.25, 0.22, 0.2)
	_corpse_mm.material_override = cmat
	_corpse_mm.visibility_range_end = visibility_range
	_corpse_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_corpse_mm)


## Body capsule plus a weapon: a spear and helm for the garrison, a short
## staff for the skaa rebels. Merged into one mesh so each soldier is one
## MultiMesh instance.
static func _soldier_mesh(faction: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CapsuleMesh.new()
	body.radius = 0.3
	body.height = 1.7
	body.radial_segments = 8
	body.rings = 3
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)))
	var weapon := BoxMesh.new()
	if faction == Faction.GARRISON:
		weapon.size = Vector3(0.05, 2.4, 0.05)
		st.append_from(weapon, 0, Transform3D(Basis.IDENTITY, Vector3(0.38, 1.2, 0.12)))
		var helm := BoxMesh.new()
		helm.size = Vector3(0.4, 0.18, 0.4)
		st.append_from(helm, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.72, 0)))
	else:
		weapon.size = Vector3(0.06, 1.3, 0.06)
		st.append_from(weapon, 0, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.35, 1.0, 0.2)))
	return st.commit()


func _update_visuals() -> void:
	if _mm.size() < 2:
		return
	var counts := [0, 0]
	for s in soldiers:
		if s.state == SoldierState.DEAD:
			continue
		var f := s.faction
		var i: int = counts[f]
		if i >= max_active:
			continue
		var bob := 0.0
		if s.state == SoldierState.DRILL:
			bob = absf(sin(s.drill_phase)) * 0.05
		var xf := Transform3D(Basis(Vector3.UP, s.facing), s.pos + Vector3(0, bob, 0))
		_mm[f].multimesh.set_instance_transform(i, xf)
		var tint := Color(1, 1, 1)
		if s.state == SoldierState.ROUT:
			tint = Color(0.75, 0.75, 0.8)
		elif s.hp < s.max_hp * 0.35:
			tint = Color(0.8, 0.55, 0.5)
		_mm[f].multimesh.set_instance_color(i, tint)
		counts[f] = i + 1
	for f in 2:
		_mm[f].multimesh.visible_instance_count = counts[f]


func _add_corpse(s: Soldier) -> void:
	if _corpse_mm == null:
		return
	var xf := Transform3D(Basis(Vector3.UP, s.facing) * Basis(Vector3.RIGHT, PI * 0.5), s.pos + Vector3(0, 0.3, 0))
	var i := _corpse_next % max_corpses
	_corpse_mm.multimesh.set_instance_transform(i, xf)
	_corpse_mm.multimesh.set_instance_color(i, Color(0.6, 0.55, 0.5) if s.faction == Faction.REBEL else Color(0.55, 0.58, 0.62))
	_corpse_next += 1
	_corpse_mm.multimesh.visible_instance_count = mini(_corpse_next, max_corpses)
