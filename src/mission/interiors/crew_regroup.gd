extends Node3D
## "The Survivor's Legacy" (Act III), part one: the crew regroups in the
## workshop under Clubs' shop the night after Fountain Square. Same crew,
## one empty chair. Talkable `NPCTalker`s for Sazed (the logbook), Dockson
## (what's left of the plan), Breeze, Ham, Spook and Clubs; Kelsier's things
## laid out on the workbench (the eleventh-metal thread) and the Lord Ruler's
## logbook open under Sazed's lamp.
##
## Layout: spawn at the stair foot (+z), the table toward -z.
## Markers (`objective_point`): `regroup_logbook`, `regroup_kelsier_things`.

const ROOM := Vector3(18.0, 4.0, 14.0)


func _ready() -> void:
	add_to_group(&"crew_regroup")
	_build_room()
	_build_props()
	_build_crew()
	InteriorKit.enclosed_environment(self, Color(0.13, 0.11, 0.1), 1.3, Color(0.08, 0.06, 0.05), 0.02)
	InteriorKit.light(self, Vector3(-3, 2.2, -3), Color(1.0, 0.62, 0.32), 1.6, 7.0, true)
	InteriorKit.light(self, Vector3(4, 3.0, 2), Color(1.0, 0.66, 0.38), 0.9, 8.0)
	InteriorKit.light(self, Vector3(-5, 3.0, 4), Color(1.0, 0.66, 0.38), 0.7, 8.0)
	InteriorKit.spawn_point(self, Vector3(0, 0.1, ROOM.z * 0.5 - 1.5))
	InteriorKit.marker(self, &"objective_point", "regroup_logbook", Vector3(-3, 0.1, -3.5))
	InteriorKit.marker(self, &"objective_point", "regroup_kelsier_things", Vector3(5.5, 0.1, -5))
	InteriorKit.exit_door(self, Vector3(0, 0, ROOM.z * 0.5 - 0.3), 0.0, Color(0.45, 0.32, 0.2))


func _build_room() -> void:
	var wall := InteriorKit.mat(Color(0.25, 0.21, 0.18))
	var hx := ROOM.x * 0.5
	var hz := ROOM.z * 0.5
	InteriorKit.box(self, Vector3(ROOM.x, 0.4, ROOM.z), Vector3(0, -0.2, 0), InteriorKit.mat(Color(0.3, 0.23, 0.16)))
	InteriorKit.box(self, Vector3(ROOM.x, 0.3, ROOM.z), Vector3(0, ROOM.y + 0.15, 0), wall)
	InteriorKit.box(self, Vector3(ROOM.x, ROOM.y, 0.3), Vector3(0, ROOM.y * 0.5, -hz), wall)
	InteriorKit.box(self, Vector3(0.3, ROOM.y, ROOM.z), Vector3(-hx, ROOM.y * 0.5, 0), wall)
	InteriorKit.box(self, Vector3(0.3, ROOM.y, ROOM.z), Vector3(hx, ROOM.y * 0.5, 0), wall)
	# South wall with the doorway gap for the exit.
	var gap := 1.3
	InteriorKit.box(self, Vector3(hx - gap, ROOM.y, 0.3), Vector3(-(hx + gap) * 0.5, ROOM.y * 0.5, hz), wall)
	InteriorKit.box(self, Vector3(hx - gap, ROOM.y, 0.3), Vector3((hx + gap) * 0.5, ROOM.y * 0.5, hz), wall)
	InteriorKit.box(self, Vector3(gap * 2.0, ROOM.y - 2.6, 0.3), Vector3(0, 2.6 + (ROOM.y - 2.6) * 0.5, hz), wall)
	# Timber posts and beams.
	var timber := InteriorKit.mat(Color(0.28, 0.19, 0.12))
	for x: float in [-4.5, 4.5]:
		for z: float in [-3.0, 3.0]:
			InteriorKit.box(self, Vector3(0.35, ROOM.y, 0.35), Vector3(x, ROOM.y * 0.5, z), timber)
	for z: float in [-3.0, 3.0]:
		InteriorKit.box(self, Vector3(ROOM.x, 0.3, 0.3), Vector3(0, ROOM.y - 0.2, z), timber, 0.0, false)


func _build_props() -> void:
	var wood := InteriorKit.mat(Color(0.38, 0.27, 0.17))
	# The long table, one chair pushed in and left empty.
	InteriorKit.box(self, Vector3(5.0, 0.8, 1.6), Vector3(-2, 0.4, -3.2), wood)
	for i in 5:
		var x := -4.0 + float(i) * 1.0
		InteriorKit.box(self, Vector3(0.5, 0.5, 0.5), Vector3(x, 0.25, -1.9), wood)
	InteriorKit.box(self, Vector3(0.5, 0.5, 0.5), Vector3(0.6, 0.25, -4.4), InteriorKit.mat(Color(0.2, 0.14, 0.09)))
	# The logbook: an open book under the lamp.
	InteriorKit.box(self, Vector3(0.6, 0.06, 0.45), Vector3(-3, 0.83, -3.3), InteriorKit.mat(Color(0.85, 0.8, 0.66)), 0.2, false)
	# Clubs' workbench with Kelsier's things: his mistcloak folded, a vial,
	# and the bead of the eleventh metal glinting in a dish.
	InteriorKit.box(self, Vector3(3.0, 0.9, 1.2), Vector3(5.5, 0.45, -5.8), wood)
	InteriorKit.box(self, Vector3(0.9, 0.15, 0.7), Vector3(4.8, 0.97, -5.8), InteriorKit.mat(Color(0.2, 0.22, 0.24)), 0.0, false)
	var bead := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	bead.mesh = s
	bead.material_override = InteriorKit.mat(Color(0.9, 0.9, 0.95), 1.0, 0.15, Color(0.7, 0.75, 1.0), 1.2)
	bead.position = Vector3(6.2, 0.98, -5.7)
	add_child(bead)
	# Clubs' anvil (anchored iron).
	var anvil := InteriorKit.box(self, Vector3(0.8, 0.7, 0.5), Vector3(7.5, 0.35, -2.0), InteriorKit.mat(Color(0.2, 0.2, 0.22), 0.9, 0.4))
	InteriorKit.add_metal(anvil, 80.0)


func _build_crew() -> void:
	InteriorKit.npc(self, "Sazed", "sazed_logbook", Color("#c2a878"), Vector3(-3.6, 0, -4.6), 0.0)
	InteriorKit.npc(self, "Dockson", "dockson_regroup", Color("#6b7280"), Vector3(-0.2, 0, -1.3), PI)
	InteriorKit.npc(self, "Breeze", "breeze_regroup", Color("#90743a"), Vector3(-6.5, 0, 1.5), PI * 0.5)
	InteriorKit.npc(self, "Ham", "ham_regroup", Color("#8a4b3d"), Vector3(3.0, 0, 1.0), -PI * 0.5)
	InteriorKit.npc(self, "Spook", "spook_regroup", Color("#5c7a99"), Vector3(7.2, 0, 3.5), -PI * 0.7)
	InteriorKit.npc(self, "Clubs", "clubs_regroup", Color("#4a4a4a"), Vector3(7.8, 0, -4.0), -PI * 0.5)
