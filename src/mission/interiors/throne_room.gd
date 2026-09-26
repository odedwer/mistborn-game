extends Node3D
## "The Lord Ruler" (Act III finale): the throne hall at the heart of Kredik
## Shaw, the boss arena. A towering obsidian hall with the throne on a
## stepped dais at the north end, iron braziers hung on the pillars (anchors
## for staying mobile), metal vials in the corners for iron when the bracers
## phase comes, and — the whole south side — a colonnaded gallery open to
## the city, twelve metres above the square where the skaa mob has gathered
## (the Venture masons' ledger mentioned it in "The Survivor's Legacy").
##
## The mob is a `CrowdMoodMeter` fed by a front rank of `CrowdMember`s (so
## brass and zinc can reach them from the gallery) and a MultiMesh throng
## behind them that surges forward as the mood rises. A `MissionBackdrop`
## anchored on Kredik Shaw puts the night city beyond the square.
##
## Group `"throne_room"` methods for the finale cutscene: `crowd_surges`,
## `elend_arrives`.
##
## Markers (`objective_point`): `throne_gallery` (the balcony),
## `throne_dais`.

const HALL := Vector3(44.0, 28.0, 56.0)
const DAIS_Z := -22.0
const SQUARE_Y := -12.0
const GALLERY_Z := 28.0
const THRONG := 240

var lord_ruler: LordRuler
var mood: CrowdMoodMeter
var _nav: NavigationRegion3D
var _throng: MultiMeshInstance3D
var _throng_base: PackedVector3Array = PackedVector3Array()
var _throng_phase: PackedFloat32Array = PackedFloat32Array()
var _surge := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _obsidian: StandardMaterial3D
var _iron: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"throne_room")
	_rng.seed = 1000
	_obsidian = InteriorKit.mat(Color(0.05, 0.05, 0.06), 0.2, 0.25)
	_iron = InteriorKit.mat(Color(0.3, 0.28, 0.27), 0.85, 0.4)
	var bd := MissionBackdrop.new()
	bd.anchor = Vector2(-100.0, -860.0)
	bd.ground_y = SQUARE_Y
	bd.clear_radius = 120.0
	bd.hide_landmarks = [&"kredik_shaw"]
	bd.volumetric_density = 0.0025  # mostly roofed halls: keep lanterns crisp
	add_child(bd)
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_hall()
	_build_dais()
	InteriorKit.bake_nav(_nav)
	_build_gallery()
	_build_square()
	_build_pickups()
	_build_lord_ruler()
	InteriorKit.spawn_point(self, Vector3(-12, 0.1, 20))
	InteriorKit.marker(self, &"objective_point", "throne_gallery", Vector3(0, 0.1, GALLERY_Z - 2.0))
	InteriorKit.marker(self, &"objective_point", "throne_dais", Vector3(0, 0.1, DAIS_Z + 8.0))
	# The way the player came up from the pits doubles as the exit.
	InteriorKit.exit_door(self, Vector3(-HALL.x * 0.5 + 0.6, 0, 20), PI * 0.5, Color(0.15, 0.13, 0.13))


func _build_hall() -> void:
	var hx := HALL.x * 0.5
	var z0 := DAIS_Z - 8.0
	var z1 := GALLERY_Z
	var cz := (z0 + z1) * 0.5
	var len := z1 - z0
	InteriorKit.box(_nav, Vector3(HALL.x, 1.0, len), Vector3(0, -0.5, cz), InteriorKit.mat(Color(0.07, 0.065, 0.07), 0.15, 0.12))
	InteriorKit.box(self, Vector3(HALL.x + 4.0, 2.0, len), Vector3(0, HALL.y + 1.0, cz), _obsidian)
	InteriorKit.box(_nav, Vector3(HALL.x, HALL.y, 2.0), Vector3(0, HALL.y * 0.5, z0), _obsidian)
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(_nav, Vector3(2.0, HALL.y, len), Vector3(side * (hx + 1.0), HALL.y * 0.5, cz), _obsidian)
	# Colonnade and hanging braziers.
	for i in 5:
		var z := DAIS_Z + 6.0 + float(i) * 9.5
		for side: float in [-1.0, 1.0]:
			var x := side * 13.0
			InteriorKit.spire(_nav, Vector3(x, 0, z), 1.6, 1.2, HALL.y, _obsidian, true, 8)
			var brazier := InteriorKit.box(self, Vector3(1.2, 0.8, 1.2), Vector3(x - side * 2.1, 8.0, z), _iron)
			InteriorKit.add_metal(brazier, 150.0)
			InteriorKit.box(brazier, Vector3(0.9, 0.1, 0.9), Vector3(0, 0.45, 0), InteriorKit.mat(Color(1.0, 0.35, 0.1), 0.0, 1.0, Color(1.0, 0.35, 0.1), 2.5), 0.0, false)
			var l := InteriorKit.light(self, Vector3(x - side * 2.1, 9.0, z), Color(1.0, 0.45, 0.2), 2.0, 14.0)
			l.light_volumetric_fog_energy = 0.15
			l.add_to_group(&"lantern")
	# A great disc of red glass behind the throne.
	InteriorKit.box(self, Vector3(12.0, 12.0, 0.2), Vector3(0, 14.0, z0 + 1.1), InteriorKit.mat(Color(0.6, 0.1, 0.05), 0.0, 0.4, Color(0.9, 0.15, 0.05), 1.6), 0.0, false)
	InteriorKit.light(self, Vector3(0, 12.0, DAIS_Z), Color(1.0, 0.3, 0.15), 2.0, 22.0)


func _build_dais() -> void:
	for i in 4:
		var w := 20.0 - float(i) * 3.5
		InteriorKit.box(_nav, Vector3(w, 0.5, 8.0 - float(i) * 1.2), Vector3(0, 0.25 + float(i) * 0.5, DAIS_Z - float(i) * 0.6), _obsidian)
	# The throne itself: a tall black seat with a white stone back.
	InteriorKit.box(self, Vector3(2.4, 1.2, 1.8), Vector3(0, 2.6, DAIS_Z - 2.2), _obsidian)
	InteriorKit.box(self, Vector3(2.4, 5.0, 0.4), Vector3(0, 4.5, DAIS_Z - 3.0), InteriorKit.mat(Color(0.85, 0.83, 0.8)))


## The open south side: colonnade, parapet, and an invisible wall so the
## fight stays in the hall (brass and zinc still reach the crowd below).
func _build_gallery() -> void:
	var hx := HALL.x * 0.5
	for i in 9:
		var x := -hx + 2.0 + float(i) * ((HALL.x - 4.0) / 8.0)
		InteriorKit.spire(self, Vector3(x, 0, GALLERY_Z), 1.0, 0.8, HALL.y, _obsidian, true, 8)
	InteriorKit.box(self, Vector3(HALL.x, 1.1, 0.6), Vector3(0, 0.55, GALLERY_Z + 0.4), _obsidian)
	var wall := StaticBody3D.new()
	wall.name = "GalleryWall"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALL.x, HALL.y, 0.4)
	cs.shape = shape
	wall.add_child(cs)
	wall.position = Vector3(0, HALL.y * 0.5, GALLERY_Z + 0.9)
	add_child(wall)
	# The cliff face of the palace below the gallery.
	InteriorKit.box(self, Vector3(HALL.x + 20.0, -SQUARE_Y, 2.0), Vector3(0, SQUARE_Y * 0.5, GALLERY_Z + 1.0), _obsidian)


## The square below: the mob. A front rank of real `CrowdMember`s for brass
## and zinc to target, and a MultiMesh throng behind them.
func _build_square() -> void:
	InteriorKit.box(self, Vector3(120.0, 1.0, 80.0), Vector3(0, SQUARE_Y - 0.5, GALLERY_Z + 40.0), InteriorKit.mat(Color(0.2, 0.19, 0.18)))
	mood = CrowdMoodMeter.new()
	mood.name = "CrowdMood"
	mood.drift_per_sec = 2.0
	add_child(mood)
	for i in 14:
		var member := CrowdMember.new()
		member.position = Vector3(-26.0 + float(i) * 4.0 + _rng.randf_range(-1, 1), SQUARE_Y, GALLERY_Z + 6.0 + _rng.randf_range(0, 3))
		member.wander_radius = 1.2
		add_child(member)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.65
	cap.radial_segments = 8
	cap.rings = 2
	mm.mesh = cap
	for i in THRONG:
		_throng_base.append(Vector3(_rng.randf_range(-50, 50), SQUARE_Y + 0.83, GALLERY_Z + _rng.randf_range(11.0, 60.0)))
		_throng_phase.append(_rng.randf() * TAU)
	mm.instance_count = THRONG
	for i in THRONG:
		var shade := _rng.randf_range(0.75, 1.15)
		mm.set_instance_color(i, Color(shade, shade, shade))
	_throng = MultiMeshInstance3D.new()
	_throng.name = "Throng"
	_throng.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.36, 0.3, 0.25)
	_throng.material_override = mat
	_throng.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_throng)
	for p: Vector3 in [Vector3(-30, SQUARE_Y, GALLERY_Z + 20), Vector3(30, SQUARE_Y, GALLERY_Z + 20), Vector3(0, SQUARE_Y, GALLERY_Z + 40)]:
		InteriorKit.brazier(self, p, 3.0, 20.0)
	_update_throng()


func _build_pickups() -> void:
	var scene: PackedScene = load("res://src/world/pickup.tscn")
	for spot: Array in [[Vector3(-19, 0, -14), &"vial"], [Vector3(19, 0, -14), &"vial"], [Vector3(19, 0, 22), &"vial"], [Vector3(-19, 0, 4), &"coins"]]:
		var p := scene.instantiate()
		p.set("pickup_kind", spot[1])
		p.position = spot[0]
		add_child(p)


func _build_lord_ruler() -> void:
	lord_ruler = (load("res://src/enemies/lord_ruler.tscn") as PackedScene).instantiate() as LordRuler
	lord_ruler.name = "LordRuler"
	add_child(lord_ruler)
	lord_ruler.global_position = Vector3(0, 2.1, DAIS_Z + 1.0)


func _process(delta: float) -> void:
	_t += delta
	if mood != null:
		# The throng presses toward the palace as the mood climbs past calm.
		var want := clampf((mood.mood - 50.0) / 50.0, 0.0, 1.0)
		_surge = move_toward(_surge, maxf(want, _surge * 0.999), delta * 0.5)
	_update_throng()


func _update_throng() -> void:
	if _throng == null:
		return
	var mm := _throng.multimesh
	var agitation := 0.04 + (mood.mood / 100.0 if mood != null else 0.5) * 0.2
	for i in _throng_base.size():
		var p := _throng_base[i]
		p.z -= _surge * 6.0
		var bob := absf(sin(_t * (1.5 + agitation * 8.0) + _throng_phase[i])) * agitation
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p + Vector3(0, bob, 0)))


# --- Finale beats (the lord_ruler_falls cutscene) -----------------------------

func crowd_surges() -> void:
	_surge = 1.0
	if mood != null:
		mood.mood = 100.0


func elend_arrives() -> void:
	InteriorKit.npc(self, "Elend Venture", "", Color("#8f7fbf"), Vector3(3, 0, GALLERY_Z - 3.0), 0.0)
	InteriorKit.npc(self, "Sazed", "", Color("#c2a878"), Vector3(-3, 0, GALLERY_Z - 4.0), 0.0)
