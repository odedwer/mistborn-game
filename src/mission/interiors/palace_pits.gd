extends Node3D
## "The Pits Beneath the Palace" (Act III): the prison cut beneath Kredik
## Shaw. Vin wakes in a cell with every reserve burned out of her (the
## mission's `drain_metals` action). A vaulted cell corridor runs north;
## Sazed arrives to open her cell (`open_cell()`, called when his dialogue
## ends), Elend is freed from the next cell along, and the way out is to
## rebuild her reserves from metal vials stashed in the open cells, get past
## the guards, and climb an old ventilation shaft by Pulling on its iron
## rungs.
##
## Layout: spawn inside the south-west cell (+z), the shaft to the north (-z).
## Markers (`objective_point`): `pits_cell_door`, `pits_shaft_base`,
## `pits_shaft_top`. Vial pickups (`WorldPickup`, kind `vial`) in three cells.

const CORRIDOR_W := 6.0
const CORRIDOR_H := 5.0
const CELL := 4.0
const CELL_ROWS := 6
const SHAFT_Z := -32.0
const SHAFT_H := 20.0

var _stone: StandardMaterial3D
var _iron: StandardMaterial3D
var _nav: NavigationRegion3D
var _cell_bars: Node3D


func _ready() -> void:
	add_to_group(&"palace_pits")
	_stone = InteriorKit.mat(Color(0.2, 0.19, 0.19))
	_iron = InteriorKit.mat(Color(0.3, 0.28, 0.27), 0.85, 0.45)
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_build_corridor()
	_build_cells()
	_build_shaft()
	InteriorKit.bake_nav(_nav)
	_build_vials()
	_build_people()
	_build_guards()
	InteriorKit.enclosed_environment(self, Color(0.08, 0.08, 0.1), 1.0, Color(0.04, 0.04, 0.05), 0.02)
	for i in 4:
		var l := InteriorKit.light(self, Vector3(0, CORRIDOR_H - 0.8, 6.0 - float(i) * 10.0), Color(1.0, 0.55, 0.28), 1.3, 9.0)
		l.add_to_group(&"lantern")
	InteriorKit.light(self, Vector3(0, SHAFT_H - 2.0, SHAFT_Z - 3.0), Color(0.55, 0.62, 0.85), 1.4, 14.0)
	InteriorKit.spawn_point(self, Vector3(-CORRIDOR_W * 0.5 - CELL * 0.5, 0.1, 8.0), -PI * 0.5)
	InteriorKit.marker(self, &"objective_point", "pits_cell_door", Vector3(0, 0.1, 8.0))
	InteriorKit.marker(self, &"objective_point", "pits_shaft_base", Vector3(0, 0.1, SHAFT_Z - 3.0))
	InteriorKit.marker(self, &"objective_point", "pits_shaft_top", Vector3(0, SHAFT_H + 0.1, SHAFT_Z - 7.5))
	InteriorKit.exit_door(self, Vector3(0, SHAFT_H, SHAFT_Z - 9.5), 0.0, Color(0.3, 0.26, 0.22))


func _build_corridor() -> void:
	var z1 := 12.0
	var z0 := SHAFT_Z
	var len := z1 - z0
	var cz := (z1 + z0) * 0.5
	var full_w := CORRIDOR_W + CELL * 2.0 + 1.0
	InteriorKit.box(_nav, Vector3(full_w, 1.0, len), Vector3(0, -0.5, cz), InteriorKit.mat(Color(0.17, 0.16, 0.16)))
	InteriorKit.box(self, Vector3(full_w, 1.0, len), Vector3(0, CORRIDOR_H + 0.5, cz), _stone)
	InteriorKit.box(_nav, Vector3(0.6, CORRIDOR_H, len), Vector3(-full_w * 0.5, CORRIDOR_H * 0.5, cz), _stone)
	InteriorKit.box(_nav, Vector3(0.6, CORRIDOR_H, len), Vector3(full_w * 0.5, CORRIDOR_H * 0.5, cz), _stone)
	InteriorKit.box(_nav, Vector3(full_w, CORRIDOR_H, 0.6), Vector3(0, CORRIDOR_H * 0.5, z1), _stone)
	# Vault ribs.
	for i in 8:
		InteriorKit.box(self, Vector3(full_w, 0.5, 0.5), Vector3(0, CORRIDOR_H - 0.25, z1 - 2.0 - float(i) * 5.5), _stone, 0.0, false)


## Cells line both sides; each has iron bars toward the corridor with a gap
## (its opened door), except Vin's, whose bars are whole until Sazed comes.
func _build_cells() -> void:
	var hw := CORRIDOR_W * 0.5
	for row in CELL_ROWS:
		var z := 8.0 - float(row) * (CELL + 0.6)
		for side: float in [-1.0, 1.0]:
			var x_mid := side * (hw + CELL * 0.5)
			# Divider walls between cells.
			InteriorKit.box(_nav, Vector3(CELL, CORRIDOR_H, 0.5), Vector3(x_mid, CORRIDOR_H * 0.5, z + CELL * 0.5 + 0.05), _stone)
			var is_vins := row == 0 and side < 0.0
			var bars := Node3D.new()
			bars.position = Vector3(side * hw, 0, z)
			add_child(bars)
			for k in 7:
				var bz := -CELL * 0.5 + 0.3 + float(k) * 0.57
				if not is_vins and k >= 2 and k <= 4:
					continue  # an open cell door
				var bar := InteriorKit.box(bars, Vector3(0.1, CORRIDOR_H, 0.1), Vector3(0, CORRIDOR_H * 0.5, bz), _iron)
				InteriorKit.add_metal(bar, 6.0)
			if is_vins:
				_cell_bars = bars
			# A straw pallet in each cell.
			InteriorKit.box(self, Vector3(1.2, 0.2, 2.0), Vector3(x_mid + side * 0.8, 0.1, z), InteriorKit.mat(Color(0.35, 0.3, 0.18)), 0.0, false)
	InteriorKit.box(_nav, Vector3(CELL, CORRIDOR_H, 0.5), Vector3(-(hw + CELL * 0.5), CORRIDOR_H * 0.5, 8.0 - float(CELL_ROWS) * (CELL + 0.6) + CELL * 0.5 + 0.05), _stone)
	InteriorKit.box(_nav, Vector3(CELL, CORRIDOR_H, 0.5), Vector3(hw + CELL * 0.5, CORRIDOR_H * 0.5, 8.0 - float(CELL_ROWS) * (CELL + 0.6) + CELL * 0.5 + 0.05), _stone)


## The ventilation shaft: an open well rising from the corridor's north end,
## iron rungs set into its wall every few metres (anchored Pull targets),
## and a ledge at the top with the way out.
func _build_shaft() -> void:
	var sz := SHAFT_Z - 3.0
	InteriorKit.box(_nav, Vector3(8.0, 1.0, 8.0), Vector3(0, -0.5, sz), InteriorKit.mat(Color(0.15, 0.14, 0.14)))
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(self, Vector3(0.8, SHAFT_H + 4.0, 8.0), Vector3(side * 4.4, (SHAFT_H + 4.0) * 0.5, sz), _stone)
	# Back wall stops at the ledge height: above it the passage runs north.
	InteriorKit.box(self, Vector3(8.8, SHAFT_H, 0.8), Vector3(0, SHAFT_H * 0.5, sz - 4.4), _stone)
	# Close the corridor's north end either side of the shaft mouth.
	var full_w := CORRIDOR_W + CELL * 2.0 + 1.0
	for side: float in [-1.0, 1.0]:
		var w := full_w * 0.5 - 4.0
		InteriorKit.box(_nav, Vector3(w, CORRIDOR_H, 0.6), Vector3(side * (4.0 + w * 0.5), CORRIDOR_H * 0.5, SHAFT_Z), _stone)
	# Front face above the corridor mouth.
	InteriorKit.box(self, Vector3(8.8, SHAFT_H + 4.0 - CORRIDOR_H, 0.8), Vector3(0, CORRIDOR_H + (SHAFT_H + 4.0 - CORRIDOR_H) * 0.5, SHAFT_Z + 0.9), _stone)
	for i in 6:
		var y := 3.0 + float(i) * 3.2
		var x := -1.8 if i % 2 == 0 else 1.8
		var rung := InteriorKit.box(self, Vector3(1.0, 0.12, 0.3), Vector3(x, y, sz - 3.8), _iron)
		InteriorKit.add_metal(rung, 200.0)
	# The top ledge and a short passage out.
	InteriorKit.box(self, Vector3(8.0, 0.6, 5.0), Vector3(0, SHAFT_H - 0.3, sz - 6.5), _stone)
	InteriorKit.box(self, Vector3(8.0, 0.6, 5.0), Vector3(0, SHAFT_H + 4.3, sz - 6.5), _stone)
	InteriorKit.box(self, Vector3(8.8, 5.0, 0.6), Vector3(0, SHAFT_H + 2.0, sz - 9.3), _stone)
	for side: float in [-1.0, 1.0]:
		InteriorKit.box(self, Vector3(0.8, 5.0, 5.4), Vector3(side * 4.4, SHAFT_H + 2.0, sz - 6.6), _stone)


func _build_vials() -> void:
	var hw := CORRIDOR_W * 0.5
	var scene: PackedScene = load("res://src/world/pickup.tscn")
	for spot: Vector3 in [Vector3(hw + CELL * 0.5, 0.0, 8.0 - (CELL + 0.6) * 1.0), Vector3(-(hw + CELL * 0.5), 0.0, 8.0 - (CELL + 0.6) * 3.0), Vector3(hw + CELL * 0.5, 0.0, 8.0 - (CELL + 0.6) * 5.0)]:
		var p := scene.instantiate()
		p.set("pickup_kind", &"vial")
		p.position = spot
		add_child(p)


func _build_people() -> void:
	var hw := CORRIDOR_W * 0.5
	InteriorKit.npc(self, "Sazed", "sazed_rescue", Color("#c2a878"), Vector3(-hw + 1.2, 0, 8.0), -PI * 0.5)
	InteriorKit.npc(self, "Elend Venture", "elend_cell", Color("#8f7fbf"), Vector3(hw + 1.0, 0, 8.0), PI * 0.5)


func _build_guards() -> void:
	var scene: PackedScene = load("res://src/enemies/guard.tscn")
	for lane: Array in [[Vector3(-1.2, 0, -8), Vector3(-1.2, 0, -24)], [Vector3(1.2, 0, -26), Vector3(1.2, 0, -12)]]:
		var g := scene.instantiate()
		add_child(g)
		g.global_position = lane[0]
		g.call("set_patrol_points", PackedVector3Array(lane))


## Sazed's work: Vin's cell bars come away.
func open_cell() -> void:
	if _cell_bars != null and is_instance_valid(_cell_bars):
		_cell_bars.queue_free()
		_cell_bars = null
