extends Node3D
## "The Army in the Caves" (Act III), part one: the skaa rebellion's hidden
## training caverns in the hills outside Luthadel. A new mission space: an
## entrance tunnel opening onto one vast lamp-lit chamber, where Yeden's
## recruits drill in blocks (a `MassBattle` running in DRILL mode, so the
## army is dozens of cheap MultiMesh soldiers, not dozens of nodes), with
## Ham running the drills, Yeden at his command tent and an armory of
## scavenged weapons along the west wall.
##
## When the news comes that Yeden has taken the army out early, the mission
## calls `march_out()` (via the `call_group` action on group
## `"rebel_caves"`): the drilling blocks turn and file out down the tunnel.
##
## Layout: spawn at the tunnel mouth (+z), progress toward -z.
## Markers (`objective_point`): `caves_training_ground`, `caves_armory`,
## `caves_exit_tunnel`. Talkable NPCs: Ham (`ham_training`), Yeden
## (`yeden_impatience`), Kelsier (`kelsier_caves`).

const HALL := Vector3(64.0, 16.0, 52.0)
const TUNNEL_LEN := 16.0

var battle: MassBattle
var _rock: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"rebel_caves")
	_rng.seed = 2207
	_rock = InteriorKit.mat(Color(0.19, 0.17, 0.16))
	_build_cavern()
	_build_tunnel()
	_build_camp()
	_build_army()
	_build_people()
	_build_lighting()
	_build_markers()
	InteriorKit.exit_door(self, Vector3(0, 0, HALL.z * 0.5 + TUNNEL_LEN - 0.5))


func _build_cavern() -> void:
	var hx := HALL.x * 0.5
	var hz := HALL.z * 0.5
	# Floor, packed earth.
	InteriorKit.box(self, Vector3(HALL.x + 8.0, 1.0, HALL.z + 8.0), Vector3(0, -0.5, 0), InteriorKit.mat(Color(0.23, 0.2, 0.17)))
	# Ceiling slab, well overhead.
	InteriorKit.box(self, Vector3(HALL.x + 8.0, 2.0, HALL.z + 8.0), Vector3(0, HALL.y + 1.0, 0), _rock)
	# Walls built from jittered, tilted rock slabs so the chamber reads as
	# natural stone, not a box. The south wall leaves the tunnel mouth open.
	var step := 6.0
	var x := -hx
	while x <= hx:
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and absf(x) < 7.5:
				continue  # tunnel mouth
			var h := HALL.y + _rng.randf_range(-1.0, 2.0)
			var d := _rng.randf_range(2.5, 5.0)
			InteriorKit.box(self, Vector3(step + 1.5, h, d), Vector3(x, h * 0.5, side * (hz + d * 0.3)), _rock, _rng.randf_range(-0.2, 0.2))
		x += step
	var z := -hz
	while z <= hz:
		for side: float in [-1.0, 1.0]:
			var h := HALL.y + _rng.randf_range(-1.0, 2.0)
			var d := _rng.randf_range(2.5, 5.0)
			InteriorKit.box(self, Vector3(d, h, step + 1.5), Vector3(side * (hx + d * 0.3), h * 0.5, z), _rock, _rng.randf_range(-0.2, 0.2))
		z += step
	# Stalactites and a few stalagmite columns (the columns double as cover).
	for i in 26:
		var p := Vector3(_rng.randf_range(-hx + 3, hx - 3), HALL.y, _rng.randf_range(-hz + 3, hz - 3))
		var length := _rng.randf_range(2.0, 6.0)
		var st := InteriorKit.spire(self, p, _rng.randf_range(0.6, 1.4), 0.05, length, _rock, false, 5)
		st.rotation.x = PI  # hanging down from the ceiling
	for p: Vector3 in [Vector3(-22, 0, -14), Vector3(22, 0, -10), Vector3(-24, 0, 12), Vector3(20, 0, 14)]:
		InteriorKit.spire(self, p, 2.2, 1.0, HALL.y, _rock, true, 7)


func _build_tunnel() -> void:
	var z0 := HALL.z * 0.5
	InteriorKit.box(self, Vector3(8.0, 1.0, TUNNEL_LEN + 2.0), Vector3(0, -0.5, z0 + TUNNEL_LEN * 0.5), InteriorKit.mat(Color(0.22, 0.19, 0.16)))
	InteriorKit.box(self, Vector3(8.0, 1.0, TUNNEL_LEN + 2.0), Vector3(0, 5.5, z0 + TUNNEL_LEN * 0.5), _rock)
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(self, Vector3(1.5, 6.0, TUNNEL_LEN + 2.0), Vector3(side * 4.0, 3.0, z0 + TUNNEL_LEN * 0.5), _rock)
	InteriorKit.box(self, Vector3(8.0, 6.0, 1.0), Vector3(0, 3.0, z0 + TUNNEL_LEN + 0.5), _rock)


func _build_camp() -> void:
	var canvas := InteriorKit.mat(Color(0.42, 0.36, 0.28))
	var wood := InteriorKit.mat(Color(0.3, 0.21, 0.13))
	# Yeden's command tent and map table.
	InteriorKit.box(self, Vector3(7.0, 3.2, 5.0), Vector3(-12, 1.6, -20), canvas)
	InteriorKit.box(self, Vector3(2.4, 0.9, 1.4), Vector3(-12, 0.45, -16.5), wood)
	# Bedrolls in rows along the east wall.
	for i in 10:
		InteriorKit.box(self, Vector3(0.9, 0.2, 2.0), Vector3(24 - float(i % 2) * 2.2, 0.1, -18 + float(i / 2) * 3.0), canvas, 0.0, false)
	# The armory: racks of scavenged spears and clubs along the west wall.
	for i in 4:
		var rack := InteriorKit.box(self, Vector3(0.4, 2.0, 3.0), Vector3(-27, 1.0, 2 + float(i) * 3.4), wood)
		for k in 5:
			var spear := InteriorKit.box(rack, Vector3(0.06, 2.2, 0.06), Vector3(0.3, 0.2, -1.2 + float(k) * 0.6), InteriorKit.mat(Color(0.45, 0.42, 0.4), 0.7, 0.4), 0.0, false)
			spear.rotation.z = 0.15
		InteriorKit.add_metal(rack, 20.0, Vector3(0.3, 1.0, 0))
	# Training posts in the yard (metal-banded, handy Push anchors).
	for p: Vector3 in [Vector3(-14, 0, 2), Vector3(14, 0, 2), Vector3(-14, 0, -8), Vector3(14, 0, -8)]:
		var post := InteriorKit.box(self, Vector3(0.4, 2.2, 0.4), p + Vector3(0, 1.1, 0), wood)
		InteriorKit.add_metal(post, 40.0, Vector3(0, 0.6, 0))


## Yeden's recruits: blocks of drilling soldiers, simulated and drawn by one
## `MassBattle`. Nothing hostile is in the caves, so they just spar.
func _build_army() -> void:
	battle = MassBattle.new()
	battle.name = "Army"
	add_child(battle)
	for block: Vector3 in [Vector3(-7, 0, -2), Vector3(7, 0, -2), Vector3(0, 0, -11)]:
		battle.spawn_block(MassBattle.Faction.REBEL, block, 14, 7, 1.7, MassBattle.SoldierState.DRILL)
	# When they march out, they head down the tunnel and "escape" at its end.
	battle.advance_target[MassBattle.Faction.REBEL] = Vector3(0, 0, HALL.z * 0.5 + TUNNEL_LEN - 2.0)
	battle.retreat_point[MassBattle.Faction.REBEL] = battle.advance_target[MassBattle.Faction.REBEL]


func _build_people() -> void:
	InteriorKit.npc(self, "Ham", "ham_training", Color("#8a4b3d"), Vector3(0, 0, 4), PI)
	InteriorKit.npc(self, "Yeden", "yeden_impatience", Color("#6d5a3a"), Vector3(-12, 0, -15), 0.3)
	InteriorKit.npc(self, "Kelsier", "kelsier_caves", Color("#c9a227"), Vector3(10, 0, -16), -0.4)


func _build_lighting() -> void:
	InteriorKit.enclosed_environment(self, Color(0.2, 0.17, 0.15), 0.7, Color(0.12, 0.08, 0.05), 0.012)
	for p: Vector3 in [Vector3(0, 0, 10), Vector3(-10, 0, -6), Vector3(10, 0, -6), Vector3(-12, 0, -13), Vector3(20, 0, -14), Vector3(-22, 0, 5), Vector3(0, 0, -20)]:
		InteriorKit.brazier(self, p, 2.6, 14.0)
	InteriorKit.light(self, Vector3(0, 3.5, HALL.z * 0.5 + 6.0), Color(0.6, 0.65, 0.85), 0.8, 10.0)


func _build_markers() -> void:
	InteriorKit.spawn_point(self, Vector3(0, 0.1, HALL.z * 0.5 + 8.0))
	InteriorKit.marker(self, &"objective_point", "caves_training_ground", Vector3(0, 0.1, 0))
	InteriorKit.marker(self, &"objective_point", "caves_armory", Vector3(-25, 0.1, 7))
	InteriorKit.marker(self, &"objective_point", "caves_exit_tunnel", Vector3(0, 0.1, HALL.z * 0.5 + 6.0))


## The news arrives: Yeden's army leaves to attack. The drilling blocks turn
## and file out down the tunnel (and are culled as they reach its end).
func march_out() -> void:
	if battle == null:
		return
	battle.set_all_state(MassBattle.Faction.REBEL, MassBattle.SoldierState.ROUT)
	for s in battle.soldiers:
		s.morale = 0.0  # keep them walking out; they're leaving, not fleeing
	battle.rout_speed = 3.0
	battle.rally_threshold = 1000.0  # never turn back
	# Yeden rides out at their head.
	var yeden := get_node_or_null(^"Yeden")
	if yeden != null:
		yeden.queue_free()
