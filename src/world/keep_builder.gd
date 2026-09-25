class_name KeepBuilder
extends RefCounted
## Noble keeps. `build_venture` is the hand-authored vertical-slice keep:
## walled 60x60 m courtyard, gatehouse with an enterable office (ledger
## objective), tall hall with towers and a central spire, iron gates,
## gardens with iron statues, and the courtyard enemy/objective markers.
## `build_generic` produces the other keeps of the city plan.

const M := WorldMaterials.Mat
const STONE_C := Color(0.62, 0.6, 0.58)


## Builds a windowed tower/hall block via a synthetic lot.
static func block(data: ChunkBuildData, r: Rect2, height: float, floors: int, lit: float,
		seed_value: int, mat := M.KEEP_STONE, front := ChunkLayout.FACE_S, shared := 0) -> void:
	var lo := Vector3(r.position.x, 0, r.position.y)
	var hi := Vector3(r.end.x, height, r.end.y)
	var c := STONE_C
	data.mb(mat).add_banded_box(lo, hi, 4.0, c * 0.4, c * 0.95, c * 0.7, c * 0.55, shared, true)
	data.mb(M.TRIM).add_banded_box(lo - Vector3(0.15, 0, 0.15), Vector3(hi.x + 0.15, 1.2, hi.z + 0.15), 0.5,
			c * 0.3, c * 0.45, c * 0.5, c * 0.5, shared, true)
	data.add_box_shape_lohi(lo, hi)
	data.add_occluder_box(lo + Vector3(0.3, 0, 0.3), hi - Vector3(0.3, 0.5, 0.3))
	data.add_nav_box(lo, hi, true)
	data.add_nav_obstruction(r, -1.0, height - 0.5)
	var lot := ChunkLayout.Lot.new()
	lot.rect = r
	lot.height = height
	lot.floors = floors
	lot.front = front
	lot.shared = shared
	lot.lot_seed = seed_value
	lot.style = {"lit": lit, "bars": 0.0, "wall_lantern": 0.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cols: Array[Color] = [c, c, c, c]
	BuildingBuilder._windows(data, lot, rng, cols)


## Square tower with a pyramid spire and an iron finial (anchored metal).
static func tower(data: ChunkBuildData, center: Vector2, half: float, height: float, spire: float,
		lit: float, seed_value: int, finial_mass := 30.0) -> void:
	var r := Rect2(center.x - half, center.y - half, half * 2.0, half * 2.0)
	block(data, r, height, int(height / 3.4), lit, seed_value)
	var c := STONE_C
	data.mb(M.TRIM).add_box(Vector3(r.position.x - 0.4, height, r.position.y - 0.4),
			Vector3(r.end.x + 0.4, height + 0.6, r.end.y + 0.4), c * 0.5, c * 0.5, c * 0.5)
	data.mb(M.SLATE).add_pyramid(Vector3(center.x, height + 0.6, center.y), half + 0.5, spire, Color(0.75, 0.78, 0.85))
	var hh := half + 0.5
	data.add_convex_shape(PackedVector3Array([
		Vector3(center.x - hh, height + 0.6, center.y - hh), Vector3(center.x + hh, height + 0.6, center.y - hh),
		Vector3(center.x + hh, height + 0.6, center.y + hh), Vector3(center.x - hh, height + 0.6, center.y + hh),
		Vector3(center.x, height + 0.6 + spire, center.y)]))
	var tip := Vector3(center.x, height + 0.6 + spire, center.y)
	data.add_instance(&"lightning_rod", Transform3D(Basis(), tip - Vector3(0, 0.3, 0)))
	data.add_metal(tip + Vector3(0, 2.6, 0), finial_mass)


## Crenellated wall segment (axis-aligned box) with merlons.
static func wall(data: ChunkBuildData, lo: Vector3, hi: Vector3) -> void:
	var c := STONE_C * 0.85
	data.mb(M.KEEP_STONE).add_banded_box(lo, hi, 2.5, c * 0.4, c, c * 0.8, c * 0.7, 0, true)
	data.add_box_shape_lohi(lo, hi)
	data.add_occluder_box(lo + Vector3(0.2, 0, 0.2), hi - Vector3(0.2, 0.5, 0.2))
	data.add_nav_box(lo, hi, true)
	data.add_nav_obstruction(Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z), -1.0, hi.y - 0.5)
	var along_x := (hi.x - lo.x) >= (hi.z - lo.z)
	var length := (hi.x - lo.x) if along_x else (hi.z - lo.z)
	var n := int(length / 2.4)
	var det := data.db(M.KEEP_STONE)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		for side in 2:
			var p: Vector3
			if along_x:
				p = Vector3(lerpf(lo.x, hi.x, t), hi.y, lo.z + 0.25 if side == 0 else hi.z - 0.25)
			else:
				p = Vector3(lo.x + 0.25 if side == 0 else hi.x - 0.25, hi.y, lerpf(lo.z, hi.z, t))
			det.add_box(p - Vector3(0.45 if along_x else 0.2, 0, 0.2 if along_x else 0.45),
					p + Vector3(0.45 if along_x else 0.2, 0.9, 0.2 if along_x else 0.45), c, c, c)


static func _lamp(data: ChunkBuildData, p: Vector3, dir: Vector2, lit: bool, shadow := false) -> void:
	data.lamp_posts.append({"pos": p, "dir": dir, "lit": lit, "shadow": shadow})
	data.metal_count += 1
	data.add_nav_box(p - Vector3(0.15, 0, 0.15), p + Vector3(0.15, 4.2, 0.15), false)
	if lit:
		data.add_light(p + Vector3(dir.x * 0.75, 3.75, dir.y * 0.75), PropPlacer.LAMP_LIGHT_COLOR, 11.0, 2.3, shadow)


static func _static_crates(data: ChunkBuildData, center: Vector3, count: int, rng: RandomNumberGenerator) -> void:
	var wood := data.mb(M.WOOD)
	for i in count:
		var s := rng.randf_range(1.1, 1.6)
		var p := center + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var y := 0.0
		if i > 0 and rng.randf() < 0.4:
			y = 1.2
			p = center
		var lo := Vector3(p.x - s * 0.5, y, p.z - s * 0.5)
		var hi := Vector3(p.x + s * 0.5, y + s * (0.9 if y > 0.0 else 1.0), p.z + s * 0.5)
		wood.add_box(lo, hi, Color(0.55, 0.5, 0.45), Color(0.7, 0.65, 0.6), Color(0.75, 0.7, 0.65))
		data.add_box_shape_lohi(lo, hi)
		data.add_nav_box(lo, hi, false)


## Keep Venture (vertical slice). World coordinates are hand-authored around
## the landmark centre (0, -190).
static func build_venture(data: ChunkBuildData, lm: CityPlan.Landmark, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, 777)
	var ox := lm.center.x
	var oz := lm.center.y + 190.0  # keeps the layout valid if the landmark is moved
	var o := Vector3(ox, 0, oz)

	# --- Keep hall -------------------------------------------------------
	var hall := Rect2(ox - 24, oz - 245, 48, 40)
	block(data, hall, 26.0, 7, 0.45, seed_value + 1, M.KEEP_STONE, ChunkLayout.FACE_S)
	data.mb(M.SLATE).add_gable_roof(hall.position, hall.end, 26.0, 9.0, true, 0.6, Color(0.8, 0.82, 0.9),
			data.mb(M.KEEP_STONE), STONE_C * 0.7)
	data.add_convex_shape(PackedVector3Array([
		Vector3(hall.position.x, 26, hall.position.y), Vector3(hall.end.x, 26, hall.position.y),
		Vector3(hall.end.x, 26, hall.end.y), Vector3(hall.position.x, 26, hall.end.y),
		Vector3(hall.position.x, 35, hall.get_center().y), Vector3(hall.end.x, 35, hall.get_center().y)]))
	# Buttresses along the courtyard face.
	var c := STONE_C * 0.8
	for i in 6:
		var bx := ox - 21.0 + float(i) * 8.4
		if absf(bx - ox) < 4.0:
			continue
		var lo := Vector3(bx - 0.7, 0, oz - 205)
		var hi := Vector3(bx + 0.7, 18, oz - 203.4)
		data.mb(M.KEEP_STONE).add_box(lo, hi, c * 0.4, c, c)
		data.add_box_shape_lohi(lo, hi)
	# Iron main doors (anchored heavy metal).
	var door_lo := Vector3(ox - 2.6, 0, oz - 205.0)
	var door_hi := Vector3(ox + 2.6, 6.0, oz - 204.75)
	data.mb(M.IRON).add_box(door_lo, door_hi, Color(0.8, 0.8, 0.8), Color(1, 1, 1), Color(1, 1, 1))
	data.add_box_shape_lohi(door_lo, door_hi)
	data.add_metal(Vector3(ox - 1.3, 3.0, oz - 204.6), 200.0)
	data.add_metal(Vector3(ox + 1.3, 3.0, oz - 204.6), 200.0)
	data.add_light(Vector3(ox, 6.8, oz - 204.2), Color(1.0, 0.58, 0.28), 10.0, 2.5, false)
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.BACK), Vector3(ox - 3.6, 4.0, oz - 204.6)))
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.BACK), Vector3(ox + 3.6, 4.0, oz - 204.6)))
	# Towers and central spire.
	tower(data, Vector2(ox - 24, oz - 205), 4.5, 40.0, 16.0, 0.4, seed_value + 2)
	tower(data, Vector2(ox + 24, oz - 205), 4.5, 40.0, 16.0, 0.4, seed_value + 3)
	tower(data, Vector2(ox - 24, oz - 245), 4.0, 34.0, 12.0, 0.3, seed_value + 4)
	tower(data, Vector2(ox + 24, oz - 245), 4.0, 34.0, 12.0, 0.3, seed_value + 5)
	var spire_r := Rect2(ox - 3.5, oz - 228.5, 7, 7)
	var sc := STONE_C
	data.mb(M.KEEP_STONE).add_banded_box(Vector3(spire_r.position.x, 26, spire_r.position.y),
			Vector3(spire_r.end.x, 48, spire_r.end.y), 30, sc * 0.6, sc, sc * 0.8, sc * 0.7, 0, true)
	data.add_box_shape_lohi(Vector3(spire_r.position.x, 26, spire_r.position.y), Vector3(spire_r.end.x, 48, spire_r.end.y))
	data.mb(M.SLATE).add_pyramid(Vector3(ox, 48, oz - 225), 4.2, 24.0, Color(0.7, 0.72, 0.8))
	data.add_convex_shape(PackedVector3Array([Vector3(ox - 4.2, 48, oz - 229.2), Vector3(ox + 4.2, 48, oz - 229.2),
			Vector3(ox + 4.2, 48, oz - 220.8), Vector3(ox - 4.2, 48, oz - 220.8), Vector3(ox, 72, oz - 225)]))
	data.add_instance(&"lightning_rod", Transform3D(Basis(), Vector3(ox, 71.7, oz - 225)))
	data.add_metal(Vector3(ox, 74.5, oz - 225), 40.0)
	for k in 4:
		var wy := 30.0 + float(k) * 4.5
		var wc := Color(rng.randf_range(0.5, 1.0), rng.randf(), 0, 1)
		var z := spire_r.end.y + 0.04
		data.db(M.WINDOW).add_quad(Vector3(ox - 0.5, wy, z), Vector3(ox + 0.5, wy, z), Vector3(ox + 0.5, wy + 1.8, z),
				Vector3(ox - 0.5, wy + 1.8, z), Vector3.BACK, wc, wc)

	# --- Courtyard walls and corner towers ---------------------------------
	wall(data, Vector3(ox - 32, 0, oz - 205), Vector3(ox - 30, 8, oz - 144))
	wall(data, Vector3(ox + 30, 0, oz - 205), Vector3(ox + 32, 8, oz - 144))
	wall(data, Vector3(ox - 32, 0, oz - 146), Vector3(ox - 10, 8, oz - 144))
	wall(data, Vector3(ox + 10, 0, oz - 146), Vector3(ox + 32, 8, oz - 144))
	wall(data, Vector3(ox - 32, 0, oz - 207), Vector3(ox - 24, 8, oz - 205))
	wall(data, Vector3(ox + 24, 0, oz - 207), Vector3(ox + 32, 8, oz - 205))
	tower(data, Vector2(ox - 31, oz - 145), 3.2, 13.0, 6.0, 0.3, seed_value + 6, 20.0)
	tower(data, Vector2(ox + 31, oz - 145), 3.2, 13.0, 6.0, 0.3, seed_value + 7, 20.0)

	_gatehouse(data, o, rng, seed_value)

	# --- Courtyard furniture -------------------------------------------------
	data.add_instance(&"well", Transform3D(Basis(), Vector3(ox, 0, oz - 178)))
	data.add_box_shape(Vector3(ox, 0.45, oz - 178), Vector3(2.2, 0.9, 2.2))
	data.add_nav_box(Vector3(ox - 1.1, 0, oz - 179.1), Vector3(ox + 1.1, 0.9, oz - 176.9), false)
	data.add_metal(Vector3(ox, 2.2, oz - 178), 30.0)
	_lamp(data, Vector3(ox - 20, 0, oz - 158), Vector2(1, 0), true, true)
	_lamp(data, Vector3(ox + 20, 0, oz - 158), Vector2(-1, 0), true)
	_lamp(data, Vector3(ox - 20, 0, oz - 192), Vector2(1, 0), true)
	_lamp(data, Vector3(ox + 20, 0, oz - 192), Vector2(-1, 0), true, true)
	_static_crates(data, Vector3(ox - 16, 0, oz - 172), 3, rng)
	_static_crates(data, Vector3(ox + 14, 0, oz - 183), 3, rng)
	_static_crates(data, Vector3(ox - 8, 0, oz - 195), 2, rng)
	_static_crates(data, Vector3(ox + 22, 0, oz - 152), 2, rng)
	for p: Vector3 in [Vector3(-12, 0, -165), Vector3(10, 0, -168), Vector3(-24, 0, -186), Vector3(24, 0, -175), Vector3(4, 0, -196)]:
		var kind := &"barrel" if rng.randf() < 0.5 else &"crate"
		var def: Array = PropMeshes.RIGID[kind]
		var sz: Vector3 = def[3]
		data.add_rigid(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o + p + Vector3(0, sz.y * 0.5 + 0.02, 0)))
	data.add_rigid(&"cart", Transform3D(Basis(Vector3.UP, 0.3), o + Vector3(-18, 0.42, -150)))
	data.add_rigid(&"cart", Transform3D(Basis(Vector3.UP, -1.2), o + Vector3(18, 0.42, -198)))
	for p: Vector3 in [Vector3(-10, 0, -150), Vector3(12, 0, -152), Vector3(-26, 0, -198)]:
		data.add_rigid(&"bucket", Transform3D(Basis(), o + p + Vector3(0, 0.2, 0)))
	# Iron weapon racks along the west wall (anchored).
	for z: float in [-160.0, -185.0]:
		var rp := o + Vector3(-29.3, 0, z)
		data.mb(M.IRON).add_box(rp + Vector3(-0.2, 0, -1.2), rp + Vector3(0.2, 1.8, 1.2), Color(0.8, 0.8, 0.8), Color(1, 1, 1), Color(1, 1, 1))
		data.add_box_shape(rp + Vector3(0, 0.9, 0), Vector3(0.4, 1.8, 2.4))
		data.add_metal(rp + Vector3(0.2, 1.2, 0), 20.0)

	# --- Gardens, statues, front fence, plaza --------------------------------
	for sx: float in [-1.0, 1.0]:
		var sp := o + Vector3(46.0 * sx, 0, -165)
		data.mb(M.TRIM).add_box(sp + Vector3(-1.2, 0, -1.2), sp + Vector3(1.2, 1.6, 1.2), c, c, c)
		data.mb(M.IRON).add_box(sp + Vector3(-0.45, 1.6, -0.35), sp + Vector3(0.45, 4.2, 0.35), Color(0.8, 0.8, 0.8), Color(1, 1, 1), Color(1, 1, 1))
		data.mb(M.IRON).add_box(sp + Vector3(-0.3, 4.2, -0.3), sp + Vector3(0.3, 4.8, 0.3), Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1))
		data.add_box_shape(sp + Vector3(0, 2.4, 0), Vector3(2.4, 4.8, 2.4))
		data.add_nav_box(sp + Vector3(-1.2, 0, -1.2), sp + Vector3(1.2, 4.8, 1.2), false)
		data.add_metal(sp + Vector3(0, 3.2, 0), 150.0)
		for z: float in [-140.0, -175.0, -210.0, -245.0]:
			_lamp(data, o + Vector3(40.0 * sx, 0, z), Vector2(-sx, 0), rng.randf() < 0.8)
		# Low garden walls.
		wall(data, o + Vector3(minf(34 * sx, 60 * sx), 0, -250), o + Vector3(maxf(34 * sx, 60 * sx), 1.3, -249))
		# Iron front fence with gate posts.
		var fx0 := minf(12.0 * sx, 60.0 * sx)
		var fx1 := maxf(12.0 * sx, 60.0 * sx)
		var iron := data.mb(M.IRON)
		var wc := Color(1, 1, 1)
		iron.add_box(o + Vector3(fx0, 1.6, -131.05), o + Vector3(fx1, 1.7, -130.95), wc, wc, wc, true)
		var x := fx0
		while x <= fx1:
			iron.add_box(o + Vector3(x - 0.03, 0, -131.03), o + Vector3(x + 0.03, 1.9, -130.97), wc, wc, wc)
			x += 0.5
		data.add_box_shape(o + Vector3((fx0 + fx1) * 0.5, 0.95, -131.0), Vector3(fx1 - fx0, 1.9, 0.12))
		data.add_nav_box(o + Vector3(fx0, 0, -131.1), o + Vector3(fx1, 1.9, -130.9), false)
		var mx := fx0 + 3.0
		while mx < fx1:
			data.add_metal(o + Vector3(mx, 1.4, -131.0), 15.0)
			mx += 6.0
	_lamp(data, o + Vector3(-8, 0, -134), Vector2(1, 0), true)
	_lamp(data, o + Vector3(8, 0, -134), Vector2(-1, 0), true)

	# --- Markers ---------------------------------------------------------------
	data.add_marker(&"objective_point", o + Vector3(0, 0.05, -175), {"objective_id": &"keep_courtyard"})
	data.add_marker(&"objective_point", o + Vector3(-7.2, 0.95, -145.7), {"objective_id": &"ledger"})
	var loop := PackedVector3Array([o + Vector3(-22, 0.05, -156), o + Vector3(22, 0.05, -156),
			o + Vector3(22, 0.05, -196), o + Vector3(-22, 0.05, -196)])
	var loop_rev := loop.duplicate()
	loop_rev.reverse()
	data.add_marker(&"enemy_spawn", o + Vector3(-22, 0.05, -156), {"enemy_type": &"guard", "patrol": loop})
	data.add_marker(&"enemy_spawn", o + Vector3(22, 0.05, -196), {"enemy_type": &"guard", "patrol": loop_rev})
	data.add_marker(&"enemy_spawn", o + Vector3(-5, 0.05, -151), {"enemy_type": &"guard",
			"patrol": PackedVector3Array([o + Vector3(-5, 0.05, -151), o + Vector3(5, 0.05, -151)])})
	data.add_marker(&"enemy_spawn", o + Vector3(6, 0.05, -202), {"enemy_type": &"guard",
			"patrol": PackedVector3Array([o + Vector3(-6, 0.05, -202), o + Vector3(6, 0.05, -202)])})
	data.add_marker(&"enemy_spawn", o + Vector3(-20, 0.05, -178), {"enemy_type": &"hazekiller"})
	data.add_marker(&"enemy_spawn", o + Vector3(18, 0.05, -170), {"enemy_type": &"hazekiller"})
	data.add_marker(&"enemy_spawn", o + Vector3(2, 0.05, -186), {"enemy_type": &"thug"})
	data.add_marker(&"enemy_spawn", o + Vector3(0, 0.05, -136), {"enemy_type": &"inquisitor", "stage": 4})
	data.add_marker(&"pickup_spawn", o + Vector3(-9.0, 1.35, -143.2), {"pickup_kind": &"duralumin"})
	data.add_marker(&"pickup_spawn", o + Vector3(-27, 0.3, -149), {"pickup_kind": &"vial"})
	data.add_marker(&"pickup_spawn", o + Vector3(27, 0.3, -149), {"pickup_kind": &"health"})


static func _gatehouse(data: ChunkBuildData, o: Vector3, rng: RandomNumberGenerator, seed_value: int) -> void:
	var stone := data.mb(M.KEEP_STONE)
	var c := STONE_C * 0.9
	var boxes: Array = [
		# Office walls (west room), with a door to the passage and two windows.
		[Vector3(-10, 0, -150), Vector3(-9.4, 5, -140)],
		[Vector3(-3.1, 0, -150), Vector3(-2.5, 5, -146.2)],
		[Vector3(-3.1, 0, -145.0), Vector3(-2.5, 5, -140)],
		[Vector3(-3.1, 2.4, -146.2), Vector3(-2.5, 5, -145.0)],
		[Vector3(-9.4, 0, -150), Vector3(-7.0, 5, -149.4)],
		[Vector3(-5.5, 0, -150), Vector3(-3.1, 5, -149.4)],
		[Vector3(-7.0, 0, -150), Vector3(-5.5, 1.2, -149.4)],
		[Vector3(-7.0, 2.6, -150), Vector3(-5.5, 5, -149.4)],
		[Vector3(-9.4, 0, -140.6), Vector3(-7.0, 5, -140)],
		[Vector3(-5.5, 0, -140.6), Vector3(-3.1, 5, -140)],
		[Vector3(-7.0, 0, -140.6), Vector3(-5.5, 1.2, -140)],
		[Vector3(-7.0, 2.6, -140.6), Vector3(-5.5, 5, -140)],
		# Office ceiling slab.
		[Vector3(-9.4, 4.5, -149.4), Vector3(-3.1, 5, -140.6)],
		# Guard room (solid) east of the passage.
		[Vector3(2.5, 0, -150), Vector3(10, 5, -140)],
		# Passage vault and upper storey.
		[Vector3(-2.5, 4.6, -150), Vector3(2.5, 5, -140)],
		[Vector3(-10, 5, -150), Vector3(10, 11, -140)],
	]
	for b: Array in boxes:
		var lo: Vector3 = o + b[0]
		var hi: Vector3 = o + b[1]
		stone.add_banded_box(lo, hi, lo.y + 1.5, c * 0.45, c, c * 0.8, c * 0.7, 0, true)
		data.add_box_shape_lohi(lo, hi)
		stone.add_quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z),
				Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, c * 0.5, c * 0.5)
	data.add_nav_box(o + Vector3(2.5, 0, -150), o + Vector3(10, 11, -140), true)
	data.add_nav_obstruction(Rect2(o.x + 2.5, o.z - 150, 7.5, 10), -1.0, 10.5)
	for b: Array in [[Vector3(-10, 0, -150), Vector3(-9.4, 5, -140)], [Vector3(-3.1, 0, -150), Vector3(-2.5, 5, -146.2)],
			[Vector3(-3.1, 0, -145.0), Vector3(-2.5, 5, -140)], [Vector3(-9.4, 0, -150), Vector3(-3.1, 5, -149.4)],
			[Vector3(-9.4, 0, -140.6), Vector3(-3.1, 5, -140)]]:
		data.add_nav_box(o + b[0], o + b[1], false)
	data.add_occluder_box(o + Vector3(-10, 5.2, -150), o + Vector3(10, 10.5, -140))
	data.add_occluder_box(o + Vector3(2.7, 0, -149.8), o + Vector3(9.8, 5, -140.2))
	# Upper storey windows + crenellations + turrets.
	var lot := ChunkLayout.Lot.new()
	lot.rect = Rect2(o.x - 10, o.z - 150, 20, 10)
	lot.height = 11.0
	lot.floors = 1
	lot.front = 0
	lot.style = {"lit": 0.6, "bars": 0.0, "wall_lantern": 0.0}
	for k in 4:
		var wc := Color(rng.randf_range(0.6, 1.0), rng.randf(), 0, 1)
		for zf: float in [-150.04, -139.96]:
			var x := -7.5 + float(k) * 5.0
			if absf(x) < 3.0:
				x += 1.5 * signf(x + 0.001)
			var n := Vector3.FORWARD if zf < -145 else Vector3.BACK
			var a := o + Vector3(x - 0.5, 6.8, zf)
			var b2 := o + Vector3(x + 0.5, 6.8, zf)
			if n == Vector3.FORWARD:
				var t := a
				a = b2
				b2 = t
			data.db(M.WINDOW).add_quad(a, b2, b2 + Vector3.UP * 1.8, a + Vector3.UP * 1.8, n, wc, wc)
	wall(data, o + Vector3(-10, 11, -150), o + Vector3(10, 11.8, -149.6))
	wall(data, o + Vector3(-10, 11, -140.4), o + Vector3(10, 11.8, -140))
	tower(data, Vector2(o.x - 10, o.z - 145), 2.2, 14.0, 5.0, 0.2, seed_value + 8, 15.0)
	tower(data, Vector2(o.x + 10, o.z - 145), 2.2, 14.0, 5.0, 0.2, seed_value + 9, 15.0)
	# Office interior: floor, desk, shelf, strongbox, lantern.
	var wood := data.mb(M.WOOD)
	var wc2 := Color(0.6, 0.55, 0.5)
	wood.add_quad(o + Vector3(-9.4, 0.03, -140.6), o + Vector3(-3.1, 0.03, -140.6), o + Vector3(-3.1, 0.03, -149.4),
			o + Vector3(-9.4, 0.03, -149.4), Vector3.UP, wc2, wc2)
	var desk_lo := o + Vector3(-8.2, 0, -146.4)
	var desk_hi := o + Vector3(-6.2, 0.85, -145.0)
	wood.add_box(desk_lo, desk_hi, wc2 * 0.7, wc2, wc2 * 1.2)
	data.add_box_shape_lohi(desk_lo, desk_hi)
	data.add_nav_box(desk_lo, desk_hi, false)
	var shelf_lo := o + Vector3(-9.4, 0, -145.0)
	var shelf_hi := o + Vector3(-8.9, 2.3, -141.5)
	wood.add_box(shelf_lo, shelf_hi, wc2 * 0.6, wc2 * 0.8, wc2)
	data.add_box_shape_lohi(shelf_lo, shelf_hi)
	for y: float in [0.6, 1.2, 1.8]:
		wood.add_box(o + Vector3(-8.9, y, -145.0), o + Vector3(-8.6, y + 0.05, -141.5), wc2, wc2, wc2)
	# Ledger book on the desk.
	data.mb(M.TRIM).add_box(o + Vector3(-7.45, 0.85, -145.9), o + Vector3(-6.95, 0.93, -145.5),
			Color(0.35, 0.12, 0.08), Color(0.35, 0.12, 0.08), Color(0.4, 0.14, 0.1))
	var sb := o + Vector3(-4.0, 0, -148.6)
	data.mb(M.IRON).add_box(sb + Vector3(-0.4, 0, -0.3), sb + Vector3(0.4, 0.55, 0.3), Color(0.8, 0.8, 0.8), Color(1, 1, 1), Color(1, 1, 1))
	data.add_box_shape(sb + Vector3(0, 0.275, 0), Vector3(0.8, 0.55, 0.6))
	data.add_metal(sb + Vector3(0, 0.4, 0), 30.0)
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.BACK), o + Vector3(-6.2, 2.6, -149.0)))
	data.add_metal(o + Vector3(-6.2, 2.9, -149.0), 4.0)
	data.add_light(o + Vector3(-6.2, 2.5, -148.8), Color(1.0, 0.6, 0.3), 8.0, 2.2, true)
	# Barred office windows (metal) and gate-passage portcullis (raised, heavy anchor).
	for zf: float in [-150.1, -139.9]:
		var n := Vector3.FORWARD if zf < -145 else Vector3.BACK
		var center := o + Vector3(-6.25, 1.9, zf)
		data.add_instance(&"window_bars", Transform3D(Basis(Vector3.RIGHT * 1.5, Vector3.UP * 1.4, n), center))
		data.add_metal(center, 12.0)
	var iron := data.mb(M.IRON)
	var ic := Color(1, 1, 1)
	for i in 17:
		var x := -2.4 + float(i) * 0.3
		iron.add_box(o + Vector3(x - 0.04, 3.1, -145.1), o + Vector3(x + 0.04, 4.6, -144.9), ic, ic, ic, true)
		iron.add_pyramid(o + Vector3(x, 3.1, -145.0), 0.05, -0.25, ic)
	for y: float in [3.4, 4.2]:
		iron.add_box(o + Vector3(-2.45, y, -145.12), o + Vector3(2.45, y + 0.08, -144.88), ic, ic, ic, true)
	data.add_metal(o + Vector3(0, 3.9, -145.0), 200.0)
	data.add_light(o + Vector3(0, 4.0, -141.0), Color(1.0, 0.58, 0.28), 8.0, 1.8, false)
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.BACK), o + Vector3(-3.8, 3.6, -139.6)))
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.BACK), o + Vector3(3.8, 3.6, -139.6)))
	data.add_metal(o + Vector3(-3.8, 3.9, -139.6), 4.0)
	data.add_metal(o + Vector3(3.8, 3.9, -139.6), 4.0)
	data.add_light(o + Vector3(-3.8, 3.5, -139.3), Color(1.0, 0.6, 0.3), 7.0, 1.8, true)


## Generic noble keep: walled grounds, main hall, N towers with spires.
static func build_generic(data: ChunkBuildData, lm: CityPlan.Landmark, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, hash(lm.id))
	var f := lm.footprint
	var cx := f.get_center().x
	var cz := f.get_center().y
	var half := minf(f.size.x, f.size.y) * 0.5 - 3.0
	# Perimeter wall with a south gate gap.
	var wh := 7.0
	wall(data, Vector3(cx - half, 0, cz - half), Vector3(cx + half, wh, cz - half + 2))
	wall(data, Vector3(cx - half, 0, cz - half + 2), Vector3(cx - half + 2, wh, cz + half))
	wall(data, Vector3(cx + half - 2, 0, cz - half + 2), Vector3(cx + half, wh, cz + half))
	wall(data, Vector3(cx - half + 2, 0, cz + half - 2), Vector3(cx - 5, wh, cz + half))
	wall(data, Vector3(cx + 5, 0, cz + half - 2), Vector3(cx + half - 2, wh, cz + half))
	data.add_metal(Vector3(cx, 3.0, cz + half - 1), 200.0)
	_lamp(data, Vector3(cx - 7, 0, cz + half + 2), Vector2(1, 0), true)
	_lamp(data, Vector3(cx + 7, 0, cz + half + 2), Vector2(-1, 0), true)
	# Main hall.
	var hw := half * 0.9
	var hd := half * 0.7
	var hall := Rect2(cx - hw * 0.5, cz - hd * 0.5 - half * 0.2, hw, hd)
	var hh := clampf(lm.height * 0.35, 18.0, 30.0)
	block(data, hall, hh, int(hh / 3.4), 0.4, seed_value + 11)
	data.mb(M.SLATE).add_gable_roof(hall.position, hall.end, hh, minf(hd * 0.35, 9.0), true, 0.6,
			Color(0.8, 0.82, 0.9), data.mb(M.KEEP_STONE), STONE_C * 0.7)
	# Towers.
	var towers := int(lm.params.get("towers", 2))
	var corners := [Vector2(hall.position.x, hall.end.y), Vector2(hall.end.x, hall.end.y),
			Vector2(hall.position.x, hall.position.y), Vector2(hall.end.x, hall.position.y)]
	for i in towers:
		var p: Vector2 = corners[i % 4]
		var th := lm.height * (0.72 if i > 0 else 0.78) + rng.randf_range(-4.0, 4.0)
		tower(data, p, rng.randf_range(3.5, 5.0), th, lm.height - th + 6.0, 0.35, seed_value + 20 + i)
	# Central tall tower (Keep Hasting-style) when the keep is very tall.
	if lm.height > 80.0:
		tower(data, hall.get_center(), 6.0, lm.height * 0.8, lm.height * 0.2, 0.35, seed_value + 30, 50.0)
	data.add_marker(&"landmark", Vector3(cx, 0.05, cz + half + 4), {"landmark_id": lm.id})
