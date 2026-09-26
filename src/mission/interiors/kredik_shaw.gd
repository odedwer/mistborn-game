extends Node3D
## "Into Kredik Shaw" (Act III): the Lord Ruler's palace of spires, hand-built
## and deliberately unlike the procedural noble keeps. Three spaces in one
## scene, walked south to north (+z to -z):
##
## 1. **The Spire Court** — an open forecourt under the night sky, ringed by
##    black obsidian spires 40–120 m tall with red slit windows, the city's
##    skyline beyond (`MissionBackdrop` anchored on Kredik Shaw, its far
##    silhouette hidden because this scene *is* the palace). Iron crowns on
##    the lesser spires are steel-jump anchors; obligator guards patrol.
## 2. **The Hall of Spires** — one enormous vaulted hall, 36 m wide, 90 m
##    long and 30 m high: a double colonnade of obsidian pillars with iron
##    braziers hung high on each (Push/Pull anchors for crossing above the
##    patrols), red-lit floor inlays, and two Steel Inquisitors pacing its
##    length plus a bronze-burning `Seeker` at the far end.
## 3. **The Hall of Gazes** — a round chamber past the hall where an
##    Inquisitor with `senses_pulses` (Seeker mechanics: it hunts by bronze;
##    copper hides you) duels Vin. Its end is scripted: more Inquisitors
##    arrive and she is taken (`vin_captured` cutscene; `surround()`).
##
## Markers (`objective_point`): `ks_gate`, `ks_hall_midpoint`, `ks_hall_far`,
## `ks_gazes`.

const COURT_Z0 := 30.0
const COURT_Z1 := 84.0
const HALL_W := 36.0
const HALL_H := 30.0
const HALL_Z1 := 30.0
const HALL_Z0 := -60.0
const GAZES_R := 15.0
const GAZES_C := Vector3(0, 0, -76.0)

var duel_inquisitor: Node3D
var _obsidian: StandardMaterial3D
var _obsidian_floor: StandardMaterial3D
var _red: StandardMaterial3D
var _iron: StandardMaterial3D
var _nav: NavigationRegion3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"kredik_shaw")
	_rng.seed = 1024
	_obsidian = InteriorKit.mat(Color(0.05, 0.05, 0.06), 0.2, 0.25)
	_obsidian_floor = InteriorKit.mat(Color(0.07, 0.065, 0.07), 0.1, 0.15)
	_red = InteriorKit.mat(Color(0.8, 0.12, 0.05), 0.0, 1.0, Color(1.0, 0.18, 0.05), 2.2)
	_iron = InteriorKit.mat(Color(0.28, 0.27, 0.27), 0.85, 0.4)
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(-100.0, -1060.0)
	bd.clear_radius = 260.0
	bd.hide_landmarks = [&"kredik_shaw"]
	add_child(bd)
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_court()
	_build_hall()
	_build_gazes()
	InteriorKit.bake_nav(_nav)
	_build_spires()
	_build_guards()
	_build_inquisitors()
	_build_markers()
	InteriorKit.exit_door(self, Vector3(0, 0, COURT_Z1 - 0.5), 0.0, Color(0.15, 0.13, 0.13))


func _build_court() -> void:
	var len := COURT_Z1 - COURT_Z0
	InteriorKit.box(_nav, Vector3(80, 1.0, len + 2.0), Vector3(0, -0.5, (COURT_Z0 + COURT_Z1) * 0.5), InteriorKit.mat(Color(0.12, 0.115, 0.12), 0.0, 0.6))
	# Low obsidian walls closing the court's sides.
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(_nav, Vector3(1.5, 8.0, len), Vector3(side * 40.0, 4.0, (COURT_Z0 + COURT_Z1) * 0.5), _obsidian)
	# A processional path of red inlays toward the doors.
	for i in 10:
		InteriorKit.box(_nav, Vector3(1.0, 0.03, 2.5), Vector3(0, 0.02, COURT_Z1 - 6.0 - float(i) * 4.8), _red, 0.0, false)
	# The palace facade: a wall of black stone with the great doors open.
	var door_w := 8.0
	var door_h := 14.0
	var w := 80.0
	InteriorKit.box(_nav, Vector3((w - door_w) * 0.5, 34.0, 3.0), Vector3(-(w + door_w) * 0.25, 17.0, COURT_Z0), _obsidian)
	InteriorKit.box(_nav, Vector3((w - door_w) * 0.5, 34.0, 3.0), Vector3((w + door_w) * 0.25, 17.0, COURT_Z0), _obsidian)
	InteriorKit.box(_nav, Vector3(door_w, 34.0 - door_h, 3.0), Vector3(0, door_h + (34.0 - door_h) * 0.5, COURT_Z0), _obsidian)
	for side: float in [-1.0, 1.0]:
		InteriorKit.brazier(self, Vector3(side * 7.0, 0, COURT_Z0 + 4.0), 3.0, 16.0)


## The Hall of Spires: walls, vault, colonnade, braziers hung high.
func _build_hall() -> void:
	var len := HALL_Z1 - HALL_Z0
	var cz := (HALL_Z1 + HALL_Z0) * 0.5
	InteriorKit.box(_nav, Vector3(HALL_W, 1.0, len), Vector3(0, -0.5, cz), _obsidian_floor)
	InteriorKit.box(_nav, Vector3(HALL_W + 4.0, 2.0, len), Vector3(0, HALL_H + 1.0, cz), _obsidian)
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(_nav, Vector3(2.0, HALL_H, len), Vector3(side * (HALL_W * 0.5 + 1.0), HALL_H * 0.5, cz), _obsidian)
		# Tall red lancet windows high in the side walls.
		for i in 6:
			var z := HALL_Z1 - 10.0 - float(i) * 14.0
			InteriorKit.box(_nav, Vector3(0.1, 9.0, 1.4), Vector3(side * (HALL_W * 0.5 - 0.05), 17.0, z), _red, 0.0, false)
	# North wall with the arch into the Hall of Gazes.
	var arch_w := 7.0
	InteriorKit.box(_nav, Vector3((HALL_W - arch_w) * 0.5, HALL_H, 2.0), Vector3(-(HALL_W + arch_w) * 0.25, HALL_H * 0.5, HALL_Z0), _obsidian)
	InteriorKit.box(_nav, Vector3((HALL_W - arch_w) * 0.5, HALL_H, 2.0), Vector3((HALL_W + arch_w) * 0.25, HALL_H * 0.5, HALL_Z0), _obsidian)
	InteriorKit.box(_nav, Vector3(arch_w, HALL_H - 12.0, 2.0), Vector3(0, 12.0 + (HALL_H - 12.0) * 0.5, HALL_Z0), _obsidian)
	# The colonnade: pillars with hanging iron braziers.
	for i in 7:
		var z := HALL_Z1 - 8.0 - float(i) * 12.5
		for side: float in [-1.0, 1.0]:
			var x := side * 10.0
			InteriorKit.spire(_nav, Vector3(x, 0, z), 1.7, 1.2, HALL_H, _obsidian, true, 8)
			var brazier := InteriorKit.box(_nav, Vector3(1.2, 0.8, 1.2), Vector3(x - side * 2.2, 9.0, z), _iron)
			InteriorKit.add_metal(brazier, 150.0)
			InteriorKit.box(brazier, Vector3(0.9, 0.1, 0.9), Vector3(0, 0.45, 0), _red, 0.0, false)
			var l := InteriorKit.light(self, Vector3(x - side * 2.2, 10.0, z), Color(1.0, 0.3, 0.1), 2.4, 14.0)
			l.add_to_group(&"lantern")
		# Red floor inlays between the pillars.
		InteriorKit.box(_nav, Vector3(14.0, 0.03, 0.5), Vector3(0, 0.02, z), _red, 0.0, false)
	# Upper balconies along both walls (vantage points over the patrols).
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var z := HALL_Z1 - 18.0 - float(i) * 28.0
			InteriorKit.box(_nav, Vector3(4.0, 0.6, 10.0), Vector3(side * (HALL_W * 0.5 - 2.0), 14.0, z), _obsidian)
	# The Lord Ruler's banners: long black-and-red drops from the vault.
	for i in 4:
		var z := HALL_Z1 - 20.0 - float(i) * 20.0
		InteriorKit.box(_nav, Vector3(3.0, 16.0, 0.1), Vector3(0, HALL_H - 8.0, z), InteriorKit.mat(Color(0.25, 0.03, 0.03)), 0.0, false)


## The round Hall of Gazes: a ring of pillars, an oculus of moonlight.
func _build_gazes() -> void:
	InteriorKit.box(_nav, Vector3(GAZES_R * 2.0 + 2.0, 1.0, GAZES_R * 2.0 + 2.0), GAZES_C + Vector3(0, -0.5, 0), _obsidian_floor)
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := GAZES_C + Vector3(sin(a), 0, cos(a)) * GAZES_R
		if cos(a) > 0.9:
			continue  # the arch from the hall
		InteriorKit.box(_nav, Vector3(6.2, 20.0, 1.5), p + Vector3(0, 10.0, 0), _obsidian, a)
	InteriorKit.box(_nav, Vector3(GAZES_R * 2.0 + 4.0, 1.5, GAZES_R * 2.0 + 4.0), GAZES_C + Vector3(0, 20.75, 0), _obsidian)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		var p := GAZES_C + Vector3(sin(a), 0, cos(a)) * (GAZES_R - 4.0)
		InteriorKit.spire(_nav, p, 0.9, 0.6, 12.0, _obsidian, true, 6)
		var ring := StaticBody3D.new()
		ring.position = p + Vector3(0, 11.0, 0)
		add_child(ring)
		InteriorKit.add_metal(ring, 120.0)
	InteriorKit.light(self, GAZES_C + Vector3(0, 16.0, 0), Color(0.6, 0.65, 0.9), 2.0, 26.0, true)
	InteriorKit.brazier(self, GAZES_C + Vector3(-6, 0, -6), 2.4, 12.0)
	InteriorKit.brazier(self, GAZES_C + Vector3(6, 0, -6), 2.4, 12.0)


## Black spires around and above the palace: the skyline Kredik Shaw is
## known for, up close. Iron crowns near the tips are real anchors.
func _build_spires() -> void:
	var spots: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		for i in 4:
			spots.append(Vector3(side * _rng.randf_range(46.0, 70.0), 0, COURT_Z0 + 8.0 + float(i) * 14.0))
		for i in 5:
			spots.append(Vector3(side * _rng.randf_range(26.0, 40.0), 0, HALL_Z1 - 10.0 - float(i) * 20.0))
	spots.append(Vector3(0, 0, -110))
	spots.append(Vector3(-30, 0, -100))
	spots.append(Vector3(34, 0, -96))
	for p in spots:
		var h := _rng.randf_range(45.0, 125.0)
		var r := _rng.randf_range(3.0, 7.0)
		InteriorKit.spire(self, p, r, r * 0.35, h * 0.72, _obsidian, true, 6)
		InteriorKit.spire(self, p + Vector3(0, h * 0.72, 0), r * 0.35, 0.05, h * 0.28, _obsidian, false, 6)
		var crown := StaticBody3D.new()
		crown.position = p + Vector3(0, h * 0.72, 0)
		add_child(crown)
		InteriorKit.add_metal(crown, 300.0)
		for k in 3:
			if _rng.randf() < 0.4:
				continue
			var y := 10.0 + float(k) * 16.0
			InteriorKit.box(self, Vector3(0.6, 3.0, 0.1), p + Vector3(0, y, lerpf(r, r * 0.35, y / (h * 0.72)) + 0.05), _red, 0.0, false)


func _build_guards() -> void:
	var scene: PackedScene = load("res://src/enemies/guard.tscn")
	for p: Vector3 in [Vector3(-18, 0, 60), Vector3(18, 0, 50), Vector3(0, 0, 40)]:
		var g := scene.instantiate()
		add_child(g)
		g.global_position = p
		g.call("set_patrol_points", PackedVector3Array([p, p + Vector3(12.0 if p.x <= 0.0 else -12.0, 0, 0)]))


func _build_inquisitors() -> void:
	var scene: PackedScene = load("res://src/enemies/inquisitor.tscn")
	# Two pace the hall's length, out of step with each other.
	for lane: Array in [[Vector3(-5, 0, 20), Vector3(-5, 0, -50)], [Vector3(5, 0, -50), Vector3(5, 0, 20)]]:
		var inq := scene.instantiate()
		add_child(inq)
		inq.global_position = lane[0]
		inq.set("chase_speed", 7.0)
		inq.call("set_patrol_points", PackedVector3Array(lane))
	var seeker: Node3D = (load("res://src/enemies/seeker.tscn") as PackedScene).instantiate()
	add_child(seeker)
	seeker.global_position = Vector3(0, 0, -52)
	seeker.call("set_patrol_points", PackedVector3Array([Vector3(-8, 0, -52), Vector3(8, 0, -52)]))
	# The duellist waits in the Hall of Gazes, hunting by bronze.
	duel_inquisitor = scene.instantiate()
	duel_inquisitor.name = "DuelInquisitor"
	duel_inquisitor.set("senses_pulses", true)
	add_child(duel_inquisitor)
	duel_inquisitor.global_position = GAZES_C + Vector3(0, 0, -8)
	duel_inquisitor.process_mode = Node.PROCESS_MODE_DISABLED


func _build_markers() -> void:
	InteriorKit.spawn_point(self, Vector3(0, 0.1, COURT_Z1 - 4.0))
	InteriorKit.marker(self, &"objective_point", "ks_gate", Vector3(0, 0.1, COURT_Z0 + 3.0))
	InteriorKit.marker(self, &"objective_point", "ks_hall_midpoint", Vector3(0, 0.1, -12.0))
	InteriorKit.marker(self, &"objective_point", "ks_hall_far", Vector3(0, 0.1, HALL_Z0 + 5.0))
	InteriorKit.marker(self, &"objective_point", "ks_gazes", GAZES_C + Vector3(0, 0.1, 6.0))


## Called as the player enters the Hall of Gazes: the duellist wakes.
func begin_duel() -> void:
	if duel_inquisitor != null and is_instance_valid(duel_inquisitor):
		duel_inquisitor.process_mode = Node.PROCESS_MODE_INHERIT
		Events.hint_requested.emit("It hunts by bronze. Every metal you burn rings like a bell to it — burn copper to go quiet.", 5.0)


## The capture: three more Inquisitors close the ring (the `vin_captured`
## cutscene calls this), and every enemy stands down.
func surround() -> void:
	var scene: PackedScene = load("res://src/enemies/inquisitor.tscn")
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var inq := scene.instantiate()
		add_child(inq)
		inq.global_position = GAZES_C + Vector3(sin(a), 0, cos(a)) * 5.0
		inq.process_mode = Node.PROCESS_MODE_DISABLED
		inq.look_at(Vector3(GAZES_C.x, inq.global_position.y, GAZES_C.z), Vector3.UP)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if is_ancestor_of(e):
			e.process_mode = Node.PROCESS_MODE_DISABLED
	# He comes to see the intruder for himself.
	var lr := (load("res://src/enemies/lord_ruler.tscn") as PackedScene).instantiate()
	add_child(lr)
	lr.global_position = GAZES_C + Vector3(0, 0, -7.0)
