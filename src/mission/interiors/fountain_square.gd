extends Node3D
## "Fountain Square" (Act III): the public executions of the captured rebels,
## in the great plaza under the night sky (a `MissionBackdrop` anchored on
## the real Fountain Square, so Kredik Shaw's spires loom to the north).
##
## A scripted, emotional set piece. The player fights through a packed skaa
## crowd guarded by obligator guards and a patrolling Steel Inquisitor to the
## front of the crowd — but the execution platform itself is sealed off by an
## invisible barrier: nothing Vin does can change what happens next. The
## `kelsier_last_stand` cutscene (camera pans via `CutsceneSystem`) stages
## the beats through this scene's methods (group `"fountain_square"`):
## `kelsier_strikes`, `duel_clash`, `lord_ruler_strikes`, `kelsier_falls`,
## `crowd_recoils`. Afterwards `unleash()` sets the Inquisitors loose for the
## escape.
##
## The Lord Ruler stands on the platform as a `LordRuler` in its `DORMANT`
## phase — the same boss actor the finale fights.
##
## The crowd is one MultiMesh of ~170 swaying placeholder figures (no nodes,
## no physics), recoiling from the platform on cue.
##
## Layout: spawn at the south edge (+z), platform to the north (-z).
## Markers (`objective_point`): `fountain_crowd_edge`, `fountain_front`,
## `fountain_escape`.

const PLAZA := 84.0
const PLATFORM_Z := -24.0
const CROWD_COUNT := 170

var lord_ruler: LordRuler
var platform_inquisitor: Node3D
var patrol_inquisitor: Node3D
var kelsier: NPCTalker
var _crowd: MultiMeshInstance3D
var _crowd_pos: PackedVector3Array = PackedVector3Array()
var _crowd_phase: PackedFloat32Array = PackedFloat32Array()
var _recoil := 0.0
var _recoiling := false
var _t := 0.0
var _nav: NavigationRegion3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"fountain_square")
	_rng.seed = 404
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(-250.0, -500.0)
	bd.clear_radius = 70.0
	bd.hide_landmarks = [&"fountain_square"]
	add_child(bd)
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_plaza()
	InteriorKit.bake_nav(_nav)
	_build_fountain()
	_build_platform()
	_build_facades()
	_build_crowd()
	_build_actors()
	_build_guards()
	_build_lighting()
	_build_markers()
	InteriorKit.exit_door(self, Vector3(-PLAZA * 0.5 + 1.0, 0, 30), PI * 0.5, Color(0.3, 0.25, 0.2))


func _build_plaza() -> void:
	InteriorKit.box(_nav, Vector3(PLAZA, 1.0, PLAZA), Vector3(0, -0.5, 0), InteriorKit.mat(Color(0.3, 0.29, 0.28)))
	# Worn paving bands.
	for i in 8:
		InteriorKit.box(self, Vector3(PLAZA, 0.02, 0.4), Vector3(0, 0.01, -36 + float(i) * 10.0), InteriorKit.mat(Color(0.22, 0.21, 0.2)), 0.0, false)


func _build_fountain() -> void:
	var stone := InteriorKit.mat(Color(0.5, 0.48, 0.45))
	var c := Vector3(0, 0, 8)
	for i in 8:
		var a := TAU * float(i) / 8.0
		InteriorKit.box(self, Vector3(4.8, 0.9, 0.5), c + Vector3(sin(a), 0, cos(a)) * 5.8 + Vector3(0, 0.45, 0), stone, a)
	InteriorKit.box(self, Vector3(11, 0.1, 11), c + Vector3(0, 0.35, 0), InteriorKit.mat(Color(0.12, 0.14, 0.16), 0.2, 0.1), 0.0, false)
	InteriorKit.spire(self, c, 0.9, 0.6, 6.0, stone, true, 8)
	InteriorKit.spire(self, c + Vector3(0, 6.0, 0), 1.8, 0.1, 0.8, stone, false, 8)


## The execution platform, its steps, the prisoners' cages, and the barrier
## that keeps the outcome out of Vin's hands.
func _build_platform() -> void:
	var dark := InteriorKit.mat(Color(0.12, 0.11, 0.11))
	var iron := InteriorKit.mat(Color(0.3, 0.3, 0.32), 0.85, 0.35)
	InteriorKit.box(self, Vector3(24, 2.5, 10), Vector3(0, 1.25, PLATFORM_Z), dark)
	InteriorKit.box(self, Vector3(8, 1.2, 2.0), Vector3(0, 0.6, PLATFORM_Z + 6.0), dark)
	# Cages of prisoners along the back of the platform.
	for i in 5:
		var x := -9.0 + float(i) * 4.5
		var cage := InteriorKit.box(self, Vector3(2.4, 0.2, 2.4), Vector3(x, 2.6, PLATFORM_Z - 3.0), iron)
		InteriorKit.add_metal(cage, 90.0, Vector3(0, 1.2, 0))
		for k in 4:
			var bx := -1.1 + float(k % 2) * 2.2
			var bz := -1.1 + float(k / 2) * 2.2
			InteriorKit.box(cage, Vector3(0.12, 2.6, 0.12), Vector3(bx, 1.3, bz), iron, 0.0, false)
		InteriorKit.box(cage, Vector3(2.4, 0.15, 2.4), Vector3(0, 2.6, 0), iron, 0.0, false)
		var prisoner := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.6
		prisoner.mesh = cap
		prisoner.material_override = InteriorKit.mat(Color(0.45, 0.38, 0.3))
		prisoner.position = Vector3(0, 0.9, 0)
		cage.add_child(prisoner)
	# Iron banner poles at the corners (anchors, and they frame the shot).
	for x: float in [-11.5, 11.5]:
		var pole := InteriorKit.spire(self, Vector3(x, 2.5, PLATFORM_Z + 4.5), 0.12, 0.12, 9.0, iron, true, 6)
		InteriorKit.add_metal(pole, 120.0, Vector3(0, 8.0, 0))
		InteriorKit.box(pole, Vector3(0.05, 4.0, 2.0), Vector3(0, 6.5, -1.0), InteriorKit.mat(Color(0.35, 0.06, 0.06)), 0.0, false)
	# The barrier: a ring of obligator pikes and, in practice, an invisible
	# wall. The platform is not Vin's to reach tonight.
	var barrier := StaticBody3D.new()
	barrier.name = "PlatformBarrier"
	# A hollow box (four walls and a cap), so the actors *on* the platform
	# aren't inside a solid collider.
	var front := PLATFORM_Z + 7.6
	var back := PLATFORM_Z - 9.0
	var mid := (front + back) * 0.5
	var depth := front - back
	for w: Array in [
		[Vector3(30, 30, 0.5), Vector3(0, 15, front)],
		[Vector3(30, 30, 0.5), Vector3(0, 15, back)],
		[Vector3(0.5, 30, depth), Vector3(-15, 15, mid)],
		[Vector3(0.5, 30, depth), Vector3(15, 15, mid)],
		[Vector3(30, 0.5, depth), Vector3(0, 30, mid)],
	]:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[0]
		cs.shape = shape
		cs.position = w[1]
		barrier.add_child(cs)
	add_child(barrier)
	for i in 13:
		var x := -15.0 + float(i) * 2.5
		var pike := InteriorKit.box(self, Vector3(0.06, 2.6, 0.06), Vector3(x, 1.3, PLATFORM_Z + 7.2), iron, 0.0, false)
		pike.rotation.x = -0.15


func _build_facades() -> void:
	var walls := [InteriorKit.mat(Color(0.26, 0.24, 0.23)), InteriorKit.mat(Color(0.3, 0.27, 0.25)), InteriorKit.mat(Color(0.22, 0.21, 0.21))]
	var window := InteriorKit.mat(Color(1.0, 0.6, 0.3), 0.0, 1.0, Color(1.0, 0.55, 0.25), 1.6)
	var h := PLAZA * 0.5
	for side in 4:
		var n := 7
		for i in n:
			var along := -h + (float(i) + 0.5) * (PLAZA / float(n))
			var height := _rng.randf_range(12.0, 20.0)
			var depth := 8.0
			var pos: Vector3
			var size: Vector3
			match side:
				0: pos = Vector3(along, height * 0.5, -h - depth * 0.5); size = Vector3(PLAZA / float(n), height, depth)
				1: pos = Vector3(along, height * 0.5, h + depth * 0.5); size = Vector3(PLAZA / float(n), height, depth)
				2: pos = Vector3(-h - depth * 0.5, height * 0.5, along); size = Vector3(depth, height, PLAZA / float(n))
				_: pos = Vector3(h + depth * 0.5, height * 0.5, along); size = Vector3(depth, height, PLAZA / float(n))
			if side == 2 and absf(along - 30.0) < 5.0:
				continue  # the west alley: the escape route
			var b := InteriorKit.box(self, size, pos, walls[_rng.randi() % walls.size()])
			for k in 3:
				if _rng.randf() < 0.5:
					continue
				var wy := 4.0 + float(k) * 4.5 - height * 0.5
				var off := Vector3(0, wy, 0)
				var wsize := Vector3(1.0, 1.6, 0.1)
				match side:
					0: off.z = depth * 0.5 + 0.02
					1: off.z = -depth * 0.5 - 0.02
					2: off.x = depth * 0.5 + 0.02; wsize = Vector3(0.1, 1.6, 1.0)
					_: off.x = -depth * 0.5 - 0.02; wsize = Vector3(0.1, 1.6, 1.0)
				InteriorKit.box(b, wsize, off, window, 0.0, false)


## ~170 skaa in a packed band between the fountain and the platform, drawn
## as one MultiMesh and animated in `_process` (sway, and the recoil).
func _build_crowd() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.65
	cap.radial_segments = 8
	cap.rings = 2
	mm.mesh = cap
	var placed := 0
	var tries := 0
	while placed < CROWD_COUNT and tries < CROWD_COUNT * 20:
		tries += 1
		var p := Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(PLATFORM_Z + 10.0, 24.0))
		if p.distance_to(Vector3(0, 0, 8)) < 7.5:
			continue  # fountain
		if absf(p.x) < 2.2 or absf(p.x - 16.0) < 1.8 or absf(p.x + 16.0) < 1.8:
			continue  # lanes through the crowd, where the guards stand
		_crowd_pos.append(p)
		_crowd_phase.append(_rng.randf() * TAU)
		placed += 1
	mm.instance_count = _crowd_pos.size()
	for i in _crowd_pos.size():
		var shade := _rng.randf_range(0.75, 1.15)
		mm.set_instance_color(i, Color(shade, shade * _rng.randf_range(0.92, 1.0), shade * _rng.randf_range(0.85, 1.0)))
	_crowd = MultiMeshInstance3D.new()
	_crowd.name = "Crowd"
	_crowd.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.36, 0.3, 0.25)  # ash-stained skaa browns
	mat.roughness = 1.0
	_crowd.material_override = mat
	_crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crowd)
	_update_crowd(0.0)


func _build_actors() -> void:
	lord_ruler = (load("res://src/enemies/lord_ruler.tscn") as PackedScene).instantiate() as LordRuler
	lord_ruler.name = "LordRuler"
	add_child(lord_ruler)
	lord_ruler.global_position = Vector3(0, 2.5, PLATFORM_Z - 1.0)
	lord_ruler.rotation.y = PI  # facing the crowd (+z)
	var inq_scene: PackedScene = load("res://src/enemies/inquisitor.tscn")
	platform_inquisitor = inq_scene.instantiate()
	platform_inquisitor.name = "PlatformInquisitor"
	add_child(platform_inquisitor)
	platform_inquisitor.global_position = Vector3(6, 2.5, PLATFORM_Z + 2.0)
	platform_inquisitor.rotation.y = PI
	platform_inquisitor.process_mode = Node.PROCESS_MODE_DISABLED
	# One Inquisitor stalks the crowd's southern edge from the start.
	patrol_inquisitor = inq_scene.instantiate()
	patrol_inquisitor.name = "CrowdInquisitor"
	add_child(patrol_inquisitor)
	patrol_inquisitor.global_position = Vector3(26, 0, 22)
	patrol_inquisitor.call("set_patrol_points", PackedVector3Array([Vector3(26, 0, 22), Vector3(26, 0, -6), Vector3(-26, 0, -6), Vector3(-26, 0, 22)]))
	# Kelsier waits out of sight until his moment.
	kelsier = InteriorKit.npc(self, "Kelsier", "", Color("#c9a227"), Vector3(-30, 0, -14))
	kelsier.visible = false


func _build_guards() -> void:
	var scene: PackedScene = load("res://src/enemies/guard.tscn")
	for p: Vector3 in [Vector3(0, 0, 14), Vector3(0, 0, -6), Vector3(16, 0, 4), Vector3(-16, 0, 4), Vector3(-16, 0, -10), Vector3(16, 0, -10)]:
		var g := scene.instantiate()
		add_child(g)
		g.global_position = p
		g.call("set_patrol_points", PackedVector3Array([p, p + Vector3(0, 0, -6)]))


func _build_lighting() -> void:
	for p: Vector3 in [Vector3(-12, 2.5, PLATFORM_Z + 4.0), Vector3(12, 2.5, PLATFORM_Z + 4.0), Vector3(-20, 0, 18), Vector3(20, 0, 18), Vector3(0, 0, 28)]:
		InteriorKit.brazier(self, p, 3.0, 18.0)


func _build_markers() -> void:
	InteriorKit.spawn_point(self, Vector3(0, 0.1, 36))
	InteriorKit.marker(self, &"objective_point", "fountain_crowd_edge", Vector3(0, 0.1, 24))
	InteriorKit.marker(self, &"objective_point", "fountain_front", Vector3(0, 0.1, PLATFORM_Z + 11.0))
	InteriorKit.marker(self, &"objective_point", "fountain_escape", Vector3(-PLAZA * 0.5 + 3.0, 0.1, 30))


func _process(delta: float) -> void:
	_t += delta
	if _recoiling:
		_recoil = minf(_recoil + delta * 0.8, 1.0)
	_update_crowd(_t)


func _update_crowd(t: float) -> void:
	if _crowd == null:
		return
	var mm := _crowd.multimesh
	for i in _crowd_pos.size():
		var p := _crowd_pos[i]
		var sway := sin(t * 1.3 + _crowd_phase[i]) * 0.05
		var back := Vector3(0, 0, 1) * _recoil * (6.0 - clampf((p.z - PLATFORM_Z) * 0.1, 0.0, 5.0))
		var xf := Transform3D(Basis(Vector3.FORWARD, sway), p + back + Vector3(0, 0.83, 0))
		mm.set_instance_transform(i, xf)


# --- Scripted beats (called from the kelsier_last_stand cutscene) -----------

func kelsier_strikes() -> void:
	kelsier.visible = true
	kelsier.global_position = Vector3(-3, 2.5, PLATFORM_Z + 3.5)
	kelsier.rotation.y = 0.0
	if platform_inquisitor != null:
		platform_inquisitor.global_position = Vector3(2, 2.5, PLATFORM_Z + 3.0)


func duel_clash() -> void:
	if platform_inquisitor != null:
		platform_inquisitor.global_position = Vector3(3.5, 2.5, PLATFORM_Z + 1.5)
		platform_inquisitor.rotation.z = 0.25


func lord_ruler_strikes() -> void:
	if lord_ruler != null:
		lord_ruler.global_position = Vector3(-4.5, 2.5, PLATFORM_Z + 2.5)
		lord_ruler.look_at(Vector3(kelsier.global_position.x, lord_ruler.global_position.y, kelsier.global_position.z), Vector3.UP)


func kelsier_falls() -> void:
	kelsier.rotation.x = -PI * 0.5
	kelsier.global_position.y = 2.8
	if platform_inquisitor != null:
		platform_inquisitor.rotation.z = 0.0


func crowd_recoils() -> void:
	_recoiling = true


## After the execution: the Inquisitors come for the crowd — and for Vin.
func unleash() -> void:
	if platform_inquisitor != null:
		platform_inquisitor.process_mode = Node.PROCESS_MODE_INHERIT
		platform_inquisitor.global_position = Vector3(8, 0, PLATFORM_Z + 8.0)
	var barrier := get_node_or_null(^"PlatformBarrier")
	if barrier != null:
		barrier.queue_free()
	if lord_ruler != null:
		lord_ruler.visible = false
		lord_ruler.process_mode = Node.PROCESS_MODE_DISABLED
