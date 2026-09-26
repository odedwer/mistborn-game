extends Node3D
## "The Survivor's Legacy" (Act III), part two: Keep Venture's library, late
## at night, where Elend Venture keeps the books his father would rather he
## didn't read. A tall two-level hall: rows of shelves on the floor, a
## gallery walkway around the walls (stairs at the south end, or a
## steel-jump off the iron chandelier chain), reading tables, and the door to
## Straff Venture's study, where a hushed conversation can be overheard with
## tin.
##
## Investigation objectives are the three clue spots (`interact`), one of
## them only legible with tin burning (faded marginalia on the gallery), the
## eavesdrop at the study door, and Elend himself at his desk.
##
## Layout: spawn at the south doors (+z), Elend's desk toward -z.
## Markers (`objective_point`): `library_ascension_text`,
## `library_palace_ledger`, `library_margins` (gallery, tin), `library_study_door`
## (tin), `library_elend_desk`.

const HALL := Vector3(30.0, 11.0, 34.0)
const GALLERY_Y := 5.0
const GALLERY_W := 3.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"keep_venture_library")
	_rng.seed = 1811
	_build_hall()
	_build_gallery()
	_build_shelves()
	_build_furniture()
	_build_lighting()
	InteriorKit.npc(self, "Elend Venture", "elend_library", Color("#8f7fbf"), Vector3(0, 0, -12.5), 0.0)
	InteriorKit.spawn_point(self, Vector3(0, 0.1, HALL.z * 0.5 - 2.0))
	InteriorKit.marker(self, &"objective_point", "library_ascension_text", Vector3(-9, 0.1, 2))
	InteriorKit.marker(self, &"objective_point", "library_palace_ledger", Vector3(9, 0.1, -6))
	InteriorKit.marker(self, &"objective_point", "library_margins", Vector3(-HALL.x * 0.5 + GALLERY_W * 0.5, GALLERY_Y + 0.1, -10))
	InteriorKit.marker(self, &"objective_point", "library_study_door", Vector3(HALL.x * 0.5 - 1.5, 0.1, 10))
	InteriorKit.marker(self, &"objective_point", "library_elend_desk", Vector3(0, 0.1, -10.5))
	InteriorKit.exit_door(self, Vector3(0, 0, HALL.z * 0.5 - 0.3), 0.0, Color(0.35, 0.22, 0.14))


func _build_hall() -> void:
	var stone := InteriorKit.mat(Color(0.34, 0.31, 0.29))
	var hx := HALL.x * 0.5
	var hz := HALL.z * 0.5
	InteriorKit.box(self, Vector3(HALL.x, 0.4, HALL.z), Vector3(0, -0.2, 0), InteriorKit.mat(Color(0.26, 0.17, 0.11)))
	InteriorKit.box(self, Vector3(HALL.x, 0.4, HALL.z), Vector3(0, HALL.y + 0.2, 0), InteriorKit.mat(Color(0.2, 0.15, 0.12)))
	InteriorKit.box(self, Vector3(HALL.x, HALL.y, 0.5), Vector3(0, HALL.y * 0.5, -hz), stone)
	InteriorKit.box(self, Vector3(0.5, HALL.y, HALL.z), Vector3(-hx, HALL.y * 0.5, 0), stone)
	InteriorKit.box(self, Vector3(0.5, HALL.y, HALL.z), Vector3(hx, HALL.y * 0.5, 0), stone)
	var gap := 1.4
	InteriorKit.box(self, Vector3(hx - gap, HALL.y, 0.5), Vector3(-(hx + gap) * 0.5, HALL.y * 0.5, hz), stone)
	InteriorKit.box(self, Vector3(hx - gap, HALL.y, 0.5), Vector3((hx + gap) * 0.5, HALL.y * 0.5, hz), stone)
	InteriorKit.box(self, Vector3(gap * 2.0, HALL.y - 3.2, 0.5), Vector3(0, 3.2 + (HALL.y - 3.2) * 0.5, hz), stone)
	# Tall stained windows on the north wall, lit faintly from outside.
	for x: float in [-8.0, 0.0, 8.0]:
		InteriorKit.box(self, Vector3(2.2, 5.0, 0.1), Vector3(x, 6.5, -hz + 0.3), InteriorKit.mat(Color(0.3, 0.35, 0.55), 0.0, 0.3, Color(0.25, 0.3, 0.5), 0.8), 0.0, false)
	# The study door on the east wall (closed; the eavesdrop spot).
	InteriorKit.box(self, Vector3(0.2, 2.8, 1.6), Vector3(hx - 0.3, 1.4, 10), InteriorKit.mat(Color(0.3, 0.2, 0.12)))


## A gallery walkway round three walls, reached by a stair at the south-west
## corner. The iron chandelier chain in the middle is a Pull anchor up to it.
func _build_gallery() -> void:
	var wood := InteriorKit.mat(Color(0.3, 0.2, 0.13))
	var hx := HALL.x * 0.5
	var hz := HALL.z * 0.5
	InteriorKit.box(self, Vector3(GALLERY_W, 0.3, HALL.z - 1.0), Vector3(-hx + GALLERY_W * 0.5, GALLERY_Y, 0), wood)
	InteriorKit.box(self, Vector3(GALLERY_W, 0.3, HALL.z - 1.0), Vector3(hx - GALLERY_W * 0.5, GALLERY_Y, 0), wood)
	InteriorKit.box(self, Vector3(HALL.x - 1.0, 0.3, GALLERY_W), Vector3(0, GALLERY_Y, -hz + GALLERY_W * 0.5), wood)
	# Railings.
	# (Left open at the south end of the west side, where the stair lands.)
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(self, Vector3(0.1, 1.0, 24.0), Vector3(side * (hx - GALLERY_W), GALLERY_Y + 0.65, 1.0), wood)
	# Stair: a run of steps along the south wall, climbing west to the
	# gallery's south-west corner (nothing overhead until the landing).
	var steps := 14
	for i in steps:
		var y := float(i + 1) * GALLERY_Y / float(steps)
		InteriorKit.box(self, Vector3(0.8, 0.3, 2.2), Vector3(-2.0 - float(i) * 0.75, y - 0.15, hz - 1.6), wood)
	# The chandelier: an iron ring on a chain, anchored to the ceiling.
	var ring := InteriorKit.box(self, Vector3(3.0, 0.2, 3.0), Vector3(0, 7.5, 0), InteriorKit.mat(Color(0.25, 0.24, 0.24), 0.9, 0.4), 0.0, false)
	InteriorKit.box(ring, Vector3(0.08, 3.4, 0.08), Vector3(0, 1.8, 0), InteriorKit.mat(Color(0.25, 0.24, 0.24), 0.9, 0.4), 0.0, false)
	var anchor := StaticBody3D.new()
	anchor.position = Vector3(0, 7.5, 0)
	add_child(anchor)
	InteriorKit.add_metal(anchor, 150.0)
	InteriorKit.light(self, Vector3(0, 7.0, 0), Color(1.0, 0.7, 0.4), 1.4, 16.0)


func _build_shelves() -> void:
	var wood := InteriorKit.mat(Color(0.28, 0.18, 0.11))
	var spines := [Color(0.45, 0.15, 0.12), Color(0.18, 0.25, 0.4), Color(0.3, 0.35, 0.2), Color(0.5, 0.4, 0.25), Color(0.25, 0.18, 0.3)]
	var spine_mats: Array[StandardMaterial3D] = []
	for c: Color in spines:
		spine_mats.append(InteriorKit.mat(c))
	# Freestanding rows on the floor.
	for row in 4:
		for side: float in [-1.0, 1.0]:
			var x := side * 8.5
			var z := 6.0 - float(row) * 5.0
			var shelf := InteriorKit.box(self, Vector3(6.0, 3.2, 0.8), Vector3(x, 1.6, z), wood)
			for level in 3:
				InteriorKit.box(shelf, Vector3(5.6, 0.7, 0.85), Vector3(0, -1.1 + float(level) * 1.0, 0), spine_mats[_rng.randi() % spine_mats.size()], 0.0, false)
	# Wall shelving on the gallery level.
	for z in range(-14, 16, 4):
		for side: float in [-1.0, 1.0]:
			InteriorKit.box(self, Vector3(0.6, 3.5, 3.6), Vector3(side * (HALL.x * 0.5 - 0.6), GALLERY_Y + 1.9, float(z)), spine_mats[_rng.randi() % spine_mats.size()], 0.0, false)


func _build_furniture() -> void:
	var wood := InteriorKit.mat(Color(0.4, 0.28, 0.17))
	# Elend's desk, buried in books.
	InteriorKit.box(self, Vector3(3.2, 0.85, 1.4), Vector3(0, 0.425, -11.2), wood)
	for i in 6:
		InteriorKit.box(self, Vector3(0.4, 0.12 + float(i % 3) * 0.08, 0.3), Vector3(-1.2 + float(i) * 0.45, 0.93, -11.3), InteriorKit.mat(Color(0.5, 0.3 + float(i) * 0.05, 0.2)), float(i) * 0.3, false)
	# Reading tables with lamps.
	for p: Vector3 in [Vector3(-9, 0, 4), Vector3(9, 0, -4)]:
		InteriorKit.box(self, Vector3(2.4, 0.8, 1.2), p + Vector3(0, 0.4, 0), wood)
		InteriorKit.light(self, p + Vector3(0, 1.4, 0), Color(1.0, 0.7, 0.4), 0.9, 5.0)


func _build_lighting() -> void:
	# A touch warmer/brighter than the default enclosed environment so the
	# shelves and gallery read at a distance, and Elend's desk stays legible.
	InteriorKit.enclosed_environment(self, Color(0.22, 0.18, 0.15), 1.35, Color(0.09, 0.07, 0.06), 0.012)
	for p: Vector3 in [Vector3(-6, 3.2, 12), Vector3(6, 3.2, 12), Vector3(0, 3.2, -8), Vector3(-12, GALLERY_Y + 2.5, -10), Vector3(12, GALLERY_Y + 2.5, 8)]:
		var l := InteriorKit.light(self, p, Color(1.0, 0.66, 0.38), 1.0, 10.0)
		l.add_to_group(&"lantern")
