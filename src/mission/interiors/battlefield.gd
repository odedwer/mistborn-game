extends Node3D
## "The Army in the Caves" (Act III), part two: the plain outside Luthadel's
## south wall where Yeden's army attacks too early and is crushed by the
## garrison. A battlefield set piece under the open night sky, with the
## city's wall and Kredik Shaw's spires on the northern skyline (a
## `MissionBackdrop` anchored just outside the wall).
##
## The fighting itself is a `MassBattle`: the rebels' broken line in front,
## the garrison's ranks advancing from the north with reinforcements queued
## behind them (never more than 60 soldiers simulated at once). The
## garrison's advance target creeps south over the course of the stage, so
## the whole field slowly closes on the ridge the player must retreat to.
## A handful of real `Guard`s fight among the survivors for the player to
## engage directly. Five wounded rebels (`BattleSurvivor`) lie across the
## field; reaching one sets `battle_survivor_<n>`, and the mission's
## `flag_count` objective wants three.
##
## Layout: spawn on the southern ridge (+z), the battle toward -z.
## Markers (`objective_point`): `battle_front`, `battle_retreat`.

const FIELD := 240.0
const RIDGE_Z := 70.0
## Seconds for the garrison's advance to sweep from the front to the ridge.
const ADVANCE_TIME := 150.0
const SURVIVOR_SPOTS := [Vector3(-18, 0, 4), Vector3(12, 0, -4), Vector3(-6, 0, -14), Vector3(26, 0, 10), Vector3(-30, 0, -6)]

var battle: MassBattle
var _advance_t := 0.0
var _nav: NavigationRegion3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"battlefield")
	_rng.seed = 1911
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(0.0, 1400.0)
	bd.clear_radius = 60.0
	bd.skyline_radius = 1000.0
	add_child(bd)
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_ground()
	InteriorKit.bake_nav(_nav, 0.25)
	_build_debris()
	_build_battle()
	_build_survivors()
	_build_guards()
	_build_people()
	_build_markers()
	InteriorKit.exit_door(self, Vector3(24, 1.2, RIDGE_Z + 12.0), 0.0, Color(0.3, 0.26, 0.22))


func _build_ground() -> void:
	var earth := InteriorKit.mat(Color(0.13, 0.125, 0.12))
	InteriorKit.box(_nav, Vector3(FIELD, 1.0, FIELD), Vector3(0, -0.5, 0), earth)
	# The ridge the survivors fall back to: a low shelf with a ramp up.
	var ridge := InteriorKit.mat(Color(0.24, 0.22, 0.2))
	InteriorKit.box(_nav, Vector3(70.0, 1.2, 24.0), Vector3(0, 0.6, RIDGE_Z + 6.0), ridge)
	var ramp := InteriorKit.box(_nav, Vector3(70.0, 0.6, 12.0), Vector3(0, 0.3, RIDGE_Z - 11.0), ridge)
	ramp.rotation.x = -0.1
	# Ash drifts: long low mounds breaking up the plain.
	for i in 12:
		var p := Vector3(_rng.randf_range(-100, 100), 0.25, _rng.randf_range(-100, 40))
		if absf(p.x) < 40.0 and p.z > -30.0:
			continue  # keep the main field clear
		InteriorKit.box(_nav, Vector3(_rng.randf_range(8, 20), 0.6, _rng.randf_range(3, 6)), p, InteriorKit.mat(Color(0.3, 0.29, 0.28)), _rng.randf_range(0, PI))


func _build_debris() -> void:
	var wood := InteriorKit.mat(Color(0.22, 0.15, 0.1))
	var char_mat := InteriorKit.mat(Color(0.08, 0.07, 0.07))
	# Overturned supply wagons, some burning.
	for p: Vector3 in [Vector3(-22, 0, 14), Vector3(18, 0, 20), Vector3(34, 0, -8), Vector3(-36, 0, 2)]:
		var wagon := InteriorKit.box(self, Vector3(2.4, 1.3, 4.2), p + Vector3(0, 0.65, 0), char_mat, _rng.randf_range(0, PI))
		wagon.rotation.z = 0.35
		InteriorKit.add_metal(wagon, 30.0, Vector3(0, 0.4, 1.8))
	for p: Vector3 in [Vector3(-22, 0, 17), Vector3(34, 0, -5), Vector3(-4, 0, 22), Vector3(8, 0, -20)]:
		InteriorKit.brazier(self, p, 3.0, 16.0)
	# A broken palisade where the rebel line stood.
	for i in 14:
		var x := -26.0 + float(i) * 4.0
		if _rng.randf() < 0.35:
			continue
		var stake := InteriorKit.box(self, Vector3(0.3, _rng.randf_range(1.0, 2.4), 0.3), Vector3(x, 0.9, 6.0 + _rng.randf_range(-1, 1)), wood)
		stake.rotation.z = _rng.randf_range(-0.5, 0.5)
	# Abandoned rebel spears stuck in the ash: Push/Pull anchors.
	for i in 10:
		var p := Vector3(_rng.randf_range(-35, 35), 0.8, _rng.randf_range(-20, 30))
		var spear := InteriorKit.box(self, Vector3(0.06, 1.6, 0.06), p, InteriorKit.mat(Color(0.4, 0.38, 0.36), 0.7, 0.4))
		spear.rotation.z = _rng.randf_range(-0.4, 0.4)
		InteriorKit.add_metal(spear, 15.0)


func _build_battle() -> void:
	battle = MassBattle.new()
	battle.name = "Battle"
	battle.max_active = 60
	add_child(battle)
	var R := MassBattle.Faction.REBEL
	var G := MassBattle.Faction.GARRISON
	battle.start_morale[R] = 45.0
	battle.advance_target[R] = Vector3(0, 0, -40)
	battle.retreat_point[R] = Vector3(0, 0, RIDGE_Z + 8.0)
	battle.spawn_point[R] = Vector3(0, 0, 20)
	battle.advance_target[G] = Vector3(0, 0, -4)
	battle.retreat_point[G] = Vector3(0, 0, -110)
	battle.spawn_point[G] = Vector3(0, 0, -80)
	battle.spawn_spread = 30.0
	# What's left of the rebel line, scattered, and the garrison's front.
	for i in 26:
		battle.spawn(R, Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-6, 14)))
	battle.spawn_block(G, Vector3(0, 0, -26), 32, 16, 2.0)
	battle.add_reserves(G, 45)


func _build_survivors() -> void:
	for i in SURVIVOR_SPOTS.size():
		var s := BattleSurvivor.new()
		s.flag = "battle_survivor_%d" % (i + 1)
		s.retreat_point = Vector3(_rng.randf_range(-10, 10), 1.2, RIDGE_Z + 6.0)
		s.position = SURVIVOR_SPOTS[i]
		add_child(s)


func _build_guards() -> void:
	var scene: PackedScene = load("res://src/enemies/guard.tscn")
	for p: Vector3 in [Vector3(-14, 0, -6), Vector3(8, 0, -10), Vector3(22, 0, 2)]:
		var g := scene.instantiate()
		add_child(g)
		g.global_position = p
		g.call("set_patrol_points", PackedVector3Array([p, p + Vector3(0, 0, 12)]))


func _build_people() -> void:
	InteriorKit.npc(self, "Ham", "battlefield_arrival", Color("#8a4b3d"), Vector3(-4, 1.2, RIDGE_Z + 2.0), 0.0)
	InteriorKit.npc(self, "Kelsier", "kelsier_aftermath", Color("#c9a227"), Vector3(4, 1.2, RIDGE_Z + 4.0), 0.0)


func _build_markers() -> void:
	InteriorKit.spawn_point(self, Vector3(0, 1.3, RIDGE_Z + 12.0))
	InteriorKit.marker(self, &"objective_point", "battle_front", Vector3(0, 0.1, 8))
	InteriorKit.marker(self, &"objective_point", "battle_retreat", Vector3(0, 1.3, RIDGE_Z + 3.0))


func _physics_process(delta: float) -> void:
	if battle == null:
		return
	if battle.rally_node == null:
		battle.rally_node = get_tree().get_first_node_in_group(&"player") as Node3D
	# The garrison's advance: its march target sweeps toward the ridge.
	_advance_t = minf(_advance_t + delta / ADVANCE_TIME, 1.0)
	battle.advance_target[MassBattle.Faction.GARRISON] = Vector3(0, 0, -4).lerp(Vector3(0, 0, RIDGE_Z - 6.0), _advance_t)


## Called once the player reaches the ridge: the garrison halts short of it
## and the field falls quiet behind the retreat.
func halt_garrison() -> void:
	_advance_t = 0.0
	set_physics_process(false)
	if battle != null:
		battle.advance_target[MassBattle.Faction.GARRISON] = Vector3(0, 0, -10)
