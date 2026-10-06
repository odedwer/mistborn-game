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
		seed_value: int, mat := M.ASHLAR, front := ChunkLayout.FACE_S, shared := 0) -> void:
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
	# Dressed ashlar curtain walls (the old rubble stone read as crazy paving).
	data.mb(M.ASHLAR).add_banded_box(lo, hi, 2.5, c * 0.45, c, c * 0.85, c * 0.75, 0, true)
	data.add_box_shape_lohi(lo, hi)
	data.add_occluder_box(lo + Vector3(0.2, 0, 0.2), hi - Vector3(0.2, 0.5, 0.2))
	data.add_nav_box(lo, hi, true)
	data.add_nav_obstruction(Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z), -1.0, hi.y - 0.5)
	_crenellate(data, lo, hi, c)


## Regular battlements along both faces of a wall's top: a continuous parapet
## band (0.35 m) with evenly pitched merlons (1.2 m wide, 1.0 m tall, 2.0 m
## pitch), a merlon at each end so corners close cleanly. Replaces a sparse
## row of lone teeth that read as a zig-zag from above.
static func _crenellate(data: ChunkBuildData, lo: Vector3, hi: Vector3, c: Color) -> void:
	var along_x := (hi.x - lo.x) >= (hi.z - lo.z)
	var length := (hi.x - lo.x) if along_x else (hi.z - lo.z)
	var a0 := lo.x if along_x else lo.z
	var det := data.db(M.ASHLAR)
	var depth := 0.45
	var band := 0.35
	var merlon := 1.2
	var pitch := 2.0
	var n := maxi(1, int(floor((length - merlon) / pitch)) + 1)
	var span := length - merlon
	var step := span / float(n - 1) if n > 1 else 0.0
	var top := c * 1.05
	for side in 2:
		# Parapet band along the whole face.
		var b_lo: Vector3
		var b_hi: Vector3
		if along_x:
			b_lo = Vector3(lo.x, hi.y, lo.z if side == 0 else hi.z - depth)
			b_hi = Vector3(hi.x, hi.y + band, lo.z + depth if side == 0 else hi.z)
		else:
			b_lo = Vector3(lo.x if side == 0 else hi.x - depth, hi.y, lo.z)
			b_hi = Vector3(lo.x + depth if side == 0 else hi.x, hi.y + band, hi.z)
		det.add_box(b_lo, b_hi, c * 0.9, c, top)
		for i in n:
			var u0 := a0 + (step * float(i) if n > 1 else span * 0.5)
			var m_lo := b_lo
			var m_hi := b_hi
			if along_x:
				m_lo = Vector3(u0, hi.y + band, b_lo.z)
				m_hi = Vector3(u0 + merlon, hi.y + 1.0, b_hi.z)
			else:
				m_lo = Vector3(b_lo.x, hi.y + band, u0)
				m_hi = Vector3(b_hi.x, hi.y + 1.0, u0 + merlon)
			det.add_box(m_lo, m_hi, c, c, top)


## `s` scales the whole post (the courtyard uses smaller garden lamps).
static func _lamp(data: ChunkBuildData, p: Vector3, dir: Vector2, lit: bool, shadow := false, s := 1.0) -> void:
	var lp := {"pos": p, "dir": dir, "lit": lit, "shadow": shadow}
	if not is_equal_approx(s, 1.0):
		lp["scale"] = s
	data.lamp_posts.append(lp)
	data.metal_count += 1
	data.add_nav_box(p - Vector3(0.15, 0, 0.15), p + Vector3(0.15, 4.2 * s, 0.15), false)
	if lit:
		data.add_light(p + Vector3(dir.x * 0.75 * s, 3.75 * s, dir.y * 0.75 * s), PropPlacer.LAMP_LIGHT_COLOR, 11.0 * s, 2.3, shadow)


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
	# Dressed ashlar masonry (the rubble keep_stone read as crazy paving).
	block(data, hall, 26.0, 7, 0.45, seed_value + 1, M.ASHLAR, ChunkLayout.FACE_S)
	data.mb(M.SLATE).add_gable_roof(hall.position, hall.end, 26.0, 9.0, true, 0.6, Color(0.8, 0.82, 0.9),
			data.mb(M.ASHLAR), STONE_C * 0.7)
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
		data.mb(M.ASHLAR).add_box(lo, hi, c * 0.4, c, c)
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
	data.mb(M.ASHLAR).add_banded_box(Vector3(spire_r.position.x, 26, spire_r.position.y),
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
	# A small fountain where the well stood (same Push anchor spot and height,
	# footprint kept clear of the keep_courtyard objective 3 m south of it).
	_courtyard_fountain(data, Vector3(ox, 0, oz - 178))
	data.add_metal(Vector3(ox, 2.2, oz - 178), 30.0)
	_courtyard_dressing(data, o)
	_courtyard_layout(data, o)
	_lamp(data, Vector3(ox - 20, 0, oz - 158), Vector2(1, 0), true, true)
	_lamp(data, Vector3(ox + 20, 0, oz - 158), Vector2(-1, 0), true)
	_lamp(data, Vector3(ox - 20, 0, oz - 192), Vector2(1, 0), true)
	_lamp(data, Vector3(ox + 20, 0, oz - 192), Vector2(-1, 0), true, true)
	_static_crates(data, Vector3(ox - 16, 0, oz - 172), 3, rng)
	_static_crates(data, Vector3(ox + 14, 0, oz - 183), 3, rng)
	_static_crates(data, Vector3(ox + 22, 0, oz - 152), 2, rng)
	for p: Vector3 in [Vector3(-12, 0, -171), Vector3(10, 0, -168.8), Vector3(-24, 0, -186), Vector3(24, 0, -175), Vector3(4, 0, -196)]:
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


## Mid-scale structure for the yard (it read as a vast empty plaza): a pale
## paved carriage loop around the fountain, paved walks from the gate and to
## the hall doors, four box-hedged lawns in the quarters between them, lamp
## posts along the approach, and sentry posts (static guards, spawned by
## `SentryPosts`) at the gate, the doors and the lawns' corners. All of it
## stays inside the guards' patrol loop (x = +-22, z = -156..-196), off their
## door/gate beats and clear of the enemy spawns (see
## tests/test_keep_venture_courtyard.gd). Hedges are 0.5 m: low enough to
## step over and to leave the yard readable, high enough to break it up.
static func _courtyard_layout(data: ChunkBuildData, o: Vector3) -> void:
	var pave := data.mb(M.KEEP_STONE)
	var pc := Color(0.95, 0.92, 0.86)
	var y := 0.025
	var fc := o + Vector3(0, 0, -178)
	# Carriage loop: an octagonal ring, r 6.5..10.
	for k in 16:
		var a0 := TAU * float(k) / 16.0
		var a1 := TAU * float(k + 1) / 16.0
		var i0 := fc + Vector3(sin(a0), 0, cos(a0)) * 6.5
		var i1 := fc + Vector3(sin(a1), 0, cos(a1)) * 6.5
		var o0 := fc + Vector3(sin(a0), 0, cos(a0)) * 10.0
		var o1 := fc + Vector3(sin(a1), 0, cos(a1)) * 10.0
		i0.y = y; i1.y = y; o0.y = y; o1.y = y
		pave.add_quad(o0, o1, i1, i0, Vector3.UP, pc, pc)
	# Walks: gate -> loop, loop -> hall doors.
	for zr: Array in [[-146.5, -168.2], [-187.8, -204.6]]:
		var z0: float = zr[0]
		var z1: float = zr[1]
		pave.add_quad(o + Vector3(-3.0, y, z0), o + Vector3(3.0, y, z0), o + Vector3(3.0, y, z1), o + Vector3(-3.0, y, z1),
				Vector3.UP, pc * 0.95, pc * 0.95)
	# Hedged lawns in the four quarters.
	var lawn := data.mb(M.GROUND_DARK)
	var lc := Color(0.62, 0.66, 0.5)
	var hedge := data.mb(M.STONE)
	var hc := Color(0.26, 0.29, 0.19)
	for r: Rect2 in [Rect2(-19, -194, 13, 5.5), Rect2(6, -194, 13, 5.5), Rect2(-19, -167.5, 13, 8), Rect2(6, -167.5, 13, 8)]:
		var x0 := o.x + r.position.x
		var z0 := o.z + r.position.y
		var x1 := x0 + r.size.x
		var z1 := z0 + r.size.y
		lawn.add_quad(Vector3(x0, 0.03, z1), Vector3(x1, 0.03, z1), Vector3(x1, 0.03, z0), Vector3(x0, 0.03, z0), Vector3.UP, lc, lc)
		var t := 0.4
		var h := 0.5
		for b: Array in [[Vector3(x0, 0, z0), Vector3(x1, h, z0 + t)], [Vector3(x0, 0, z1 - t), Vector3(x1, h, z1)],
				[Vector3(x0, 0, z0 + t), Vector3(x0 + t, h, z1 - t)], [Vector3(x1 - t, 0, z0 + t), Vector3(x1, h, z1 - t)]]:
			hedge.add_box(b[0], b[1], hc * 0.8, hc, hc * 1.15)
			data.add_box_shape_lohi(b[0], b[1])
		# Clipped topiary at the corners.
		for cp: Vector3 in [Vector3(x0 + 1.0, 0, z0 + 1.0), Vector3(x1 - 1.0, 0, z0 + 1.0), Vector3(x0 + 1.0, 0, z1 - 1.0), Vector3(x1 - 1.0, 0, z1 - 1.0)]:
			data.add_instance(&"topiary", Transform3D(Basis(), cp))
	# Garden lamps along the approach walk: 0.8 scale (a 3.3 m post, the
	# lantern at ~3 m) so they sit in proportion with the 1.8 m figures and the
	# 0.5 m hedges, and set back from the gate so a camera just inside it
	# doesn't have a lantern filling the lower frame.
	for z: float in [-157.0, -164.5]:
		_lamp(data, o + Vector3(-3.6, 0, z), Vector2(1, 0), true, false, 0.8)
		_lamp(data, o + Vector3(3.6, 0, z), Vector2(-1, 0), true, false, 0.8)
	# Sentry posts: static guards at the doors, the inner gate and the loop.
	for sp: Array in [[Vector3(-3.05, 0, -203.8), 0.0], [Vector3(3.05, 0, -203.8), 0.0],
			[Vector3(-7.2, 0, -151.6), PI], [Vector3(7.2, 0, -151.6), PI],
			[Vector3(-10.8, 0, -178.0), PI * 0.5], [Vector3(10.8, 0, -178.0), -PI * 0.5]]:
		data.add_marker(&"sentry_post", o + (sp[0] as Vector3), {"yaw": sp[1]})


## Octagonal basin (r 1.7 m), dark water, a pedestal and a small iron figure.
static func _courtyard_fountain(data: ChunkBuildData, c: Vector3) -> void:
	var st := data.mb(M.ASHLAR)
	var col := STONE_C
	var r := 1.7
	for k in 8:
		var a := TAU * (float(k) + 0.5) / 8.0
		var mid := c + Vector3(sin(a), 0.0, cos(a)) * r
		st.add_obox(mid + Vector3(0, 0.32, 0), Vector3(0.74, 0.32, 0.18), a, col * 0.7, col)
	var wm := data.mb(M.WATER)
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		var a1 := TAU * float(k + 1) / 8.0
		var w0 := c + Vector3(0, 0.45, 0)
		wm.add_tri(w0, w0 + Vector3(sin(a0), 0, cos(a0)) * r, w0 + Vector3(sin(a1), 0, cos(a1)) * r, Color(1, 1, 1))
	st.add_box(c + Vector3(-0.35, 0.0, -0.35), c + Vector3(0.35, 1.2, 0.35), col * 0.7, col, col)
	data.add_instance(&"statue", Transform3D(Basis().scaled(Vector3.ONE * 0.55), c + Vector3(0, 1.2, 0)))
	data.add_box_shape(c + Vector3(0, 0.32, 0), Vector3(r * 2.0, 0.64, r * 2.0))
	data.add_box_shape(c + Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 0.7))
	data.add_nav_box(c - Vector3(r, 0, r), c + Vector3(r, 0.64, r), false)


## Keep Venture's yard: ash-dead planters along the hall and the gate wall,
## sentry booths inside the gate, a parked carriage against the west wall and
## house banners hung between the hall's buttresses. Everything is placed
## off the guards' patrol loop (x = +-22, z = -156/-196), their short gate and
## door beats, the lamps, crates and weapon racks, and the objective markers.
static func _courtyard_dressing(data: ChunkBuildData, o: Vector3) -> void:
	# Planters: hall front and inside the gate wall.
	for p: Vector3 in [Vector3(-10, 0, -202.8), Vector3(10, 0, -202.8), Vector3(-16.5, 0, -202.8), Vector3(16.5, 0, -202.8),
			Vector3(-14, 0, -147.6), Vector3(14, 0, -147.6), Vector3(-21.5, 0, -147.6), Vector3(26.5, 0, -160)]:
		data.add_instance(&"ash_planter", Transform3D(Basis(), o + p))
		data.add_box_shape(o + p + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9))
	# Sentry booths flanking the gate passage.
	var wood := data.mb(M.WOOD)
	var wc := Color(0.5, 0.45, 0.4)
	for sx: float in [-1.0, 1.0]:
		var b := o + Vector3(12.8 * sx, 0, -149.4)
		var lo := b + Vector3(-0.8, 0, -0.8)
		var hi := b + Vector3(0.8, 2.5, 0.8)
		# Back and sides, open to the courtyard (-z).
		wood.add_box(Vector3(lo.x, 0, hi.z - 0.1), Vector3(hi.x, 2.5, hi.z), wc * 0.7, wc, wc)
		wood.add_box(Vector3(lo.x, 0, lo.z), Vector3(lo.x + 0.1, 2.5, hi.z), wc * 0.7, wc, wc)
		wood.add_box(Vector3(hi.x - 0.1, 0, lo.z), Vector3(hi.x, 2.5, hi.z), wc * 0.7, wc, wc)
		data.mb(M.SLATE).add_pyramid(b + Vector3(0, 2.5, 0), 1.05, 0.7, Color(0.7, 0.72, 0.78))
		data.add_box_shape_lohi(Vector3(lo.x, 0, hi.z - 0.1), Vector3(hi.x, 2.5, hi.z))
		data.add_box_shape_lohi(Vector3(lo.x, 0, lo.z), Vector3(lo.x + 0.1, 2.5, hi.z))
		data.add_box_shape_lohi(Vector3(hi.x - 0.1, 0, lo.z), Vector3(hi.x, 2.5, hi.z))
		data.add_nav_box(lo, hi, false)
		data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.FORWARD), b + Vector3(0.9 * -sx, 2.2, -0.85)))
	# A noble carriage parked along the west wall (static; its wheel rims and
	# fittings are iron, so it is a Push/Pull anchor).
	var cp := o + Vector3(-26.4, 0, -171.0)
	data.add_instance(&"carriage", Transform3D(Basis(), cp))
	data.add_box_shape(cp + Vector3(0, 1.2, 0), Vector3(1.9, 2.4, 3.6))
	data.add_nav_box(cp + Vector3(-0.95, 0, -2.6), cp + Vector3(0.95, 2.4, 2.6), false)
	data.add_metal(cp + Vector3(0, 0.7, 1.2), 60.0)
	# House banners between the hall's buttresses (crimson with a gold band).
	var ban := data.mb(M.BANNER)
	var cloth := Color(0.42, 0.06, 0.07)
	var gold := Color(0.62, 0.48, 0.18)
	for x: float in [-16.8, -8.4, 8.4, 16.8]:
		var z := o.z - 204.7
		var x0 := o.x + x - 1.1
		var x1 := o.x + x + 1.1
		ban.add_quad(Vector3(x0, 8.6, z), Vector3(x1, 8.6, z), Vector3(x1, 16.5, z), Vector3(x0, 16.5, z), Vector3.BACK, cloth * 0.8, cloth)
		ban.add_quad(Vector3(x0, 15.6, z + 0.02), Vector3(x1, 15.6, z + 0.02), Vector3(x1, 16.0, z + 0.02), Vector3(x0, 16.0, z + 0.02), Vector3.BACK, gold, gold)
		# Swallow-tail hem.
		ban.add_tri(Vector3(x0, 8.6, z), Vector3(o.x + x, 9.4, z), Vector3(x0, 7.6, z), cloth * 0.75)
		ban.add_tri(Vector3(o.x + x, 9.4, z), Vector3(x1, 8.6, z), Vector3(x1, 7.6, z), cloth * 0.75)
		data.mb(M.IRON).add_box(Vector3(x0 - 0.15, 16.5, z - 0.05), Vector3(x1 + 0.15, 16.62, z + 0.1), Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1))


static func _gatehouse(data: ChunkBuildData, o: Vector3, rng: RandomNumberGenerator, seed_value: int) -> void:
	var stone := data.mb(M.ASHLAR)
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
	_garden(data, cx, cz, half)
	# Main hall.
	var hw := half * 0.9
	var hd := half * 0.7
	var hall := Rect2(cx - hw * 0.5, cz - hd * 0.5 - half * 0.2, hw, hd)
	var hh := clampf(lm.height * 0.35, 18.0, 30.0)
	block(data, hall, hh, int(hh / 3.4), 0.4, seed_value + 11)
	data.mb(M.SLATE).add_gable_roof(hall.position, hall.end, hh, minf(hd * 0.35, 9.0), true, 0.6,
			Color(0.8, 0.82, 0.9), data.mb(M.ASHLAR), STONE_C * 0.7)
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


## Walled garden inside a generic keep's perimeter: trimmed, soot-dulled hedges
## lining the inner faces of the wall (one collision/nav box per run), ash-dead
## planters at intervals and flanking the gate. Pure geometry, no RNG, so it
## can't shift the keep's other generation.
static func _garden(data: ChunkBuildData, cx: float, cz: float, half: float) -> void:
	var inner := half - 2.0 - 0.7
	var step := 1.8
	var runs: Array = [
		# [axis_is_x, fixed coordinate, from, to]
		[false, cx - inner, cz - inner + 1.5, cz + inner - 1.5],
		[false, cx + inner, cz - inner + 1.5, cz + inner - 1.5],
		[true, cz - inner, cx - inner + 1.5, cx + inner - 1.5],
		[true, cz + inner, cx - inner + 1.5, cx - 6.5],
		[true, cz + inner, cx + 6.5, cx + inner - 1.5],
	]
	for run: Array in runs:
		var along_x: bool = run[0]
		var fixed: float = run[1]
		var a: float = run[2]
		var b: float = run[3]
		var n := int(floor((b - a) / step))
		if n < 1:
			continue
		for i in n:
			var t := a + step * (float(i) + 0.5)
			var pos := Vector3(t, 0.0, fixed) if along_x else Vector3(fixed, 0.0, t)
			var kind := &"ash_planter" if i % 7 == 6 else &"hedge"
			var yaw := 0.0 if along_x else PI * 0.5
			data.add_instance(kind, Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, 0.35 if kind == &"hedge" else 0.0, 0.0)))
		var lo := Vector3(a, 0.0, fixed - 0.3) if along_x else Vector3(fixed - 0.3, 0.0, a)
		var hi := Vector3(a + step * n, 0.9, fixed + 0.3) if along_x else Vector3(fixed + 0.3, 0.9, a + step * n)
		data.add_box_shape_lohi(lo, hi)
	# Ash-dead planters flanking the gate on the street side.
	for sx: float in [-8.5, 8.5]:
		var p := Vector3(cx + sx, 0.0, cz + half + 2.5)
		data.add_instance(&"ash_planter", Transform3D(Basis(), p))
		data.add_box_shape(p + Vector3(0.0, 0.3, 0.0), Vector3(0.9, 0.6, 0.9))
	_parterre(data, cx, cz, half)


## The garden proper, laid out in the free ground around the hall (see
## `build_generic`: the hall spans x in cx +- 0.45 half and z from
## cz - 0.55 half to cz + 0.15 half). South forecourt: a flagged walk from the
## gate to the hall steps, crossed by a second walk at a paved plaza
## with a fountain and an iron statue (a Push/Pull anchor), and four box-edged
## parterre beds of dark soil with clipped topiary. East/west lawns: a
## walk and a row of beds. All deterministic (no RNG), a few dozen quads and
## boxes, instanced topiary.
static func _parterre(data: ChunkBuildData, cx: float, cz: float, half: float) -> void:
	# Pale flagged walks (keep stone) so they read against the dark cobbles.
	var gravel := data.mb(M.KEEP_STONE)
	var gc := Color(0.9, 0.87, 0.82)
	var soil := data.mb(M.GROUND_DARK)
	var sc := Color(0.55, 0.5, 0.45)
	var box := data.mb(M.STONE)
	var hc := Color(0.26, 0.29, 0.19)
	var hc_top := Color(0.31, 0.34, 0.22)
	var inner := half - 2.0 - 1.6   # inside the hedge line
	var z_hall := cz + half * 0.15 + 1.0
	var z_wall := cz + inner
	var zc := (z_hall + z_wall) * 0.5
	var ground := func(b: WorldMeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, c: Color) -> void:
		b.add_quad(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0), Vector3.UP, c, c)
	# Gravel walks: gate -> hall, and across the forecourt.
	ground.call(gravel, cx - 2.2, z_hall, cx + 2.2, cz + half, 0.03, gc)
	ground.call(gravel, cx - inner, zc - 1.8, cx - 7.0, zc + 1.8, 0.03, gc)
	ground.call(gravel, cx + 7.0, zc - 1.8, cx + inner, zc + 1.8, 0.03, gc)
	# Round-ish plaza (an octagon of quads) around the fountain.
	var pr := 7.0
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		var a1 := TAU * float(k + 1) / 8.0
		var c0 := Vector3(cx, 0.035, zc)
		gravel.add_tri(c0, c0 + Vector3(sin(a0), 0, cos(a0)) * pr, c0 + Vector3(sin(a1), 0, cos(a1)) * pr, gc)
	_fountain(data, Vector3(cx, 0.0, zc))
	# Four forecourt beds, one per quadrant between the walks.
	var bx0 := cx + 3.5
	var bx1 := cx + inner - 1.0
	# Beds stop short of the fountain plaza (radius `pr`) along z.
	var bz_n0 := z_hall + 1.5
	var bz_n1 := zc - pr - 1.0
	var bz_s0 := zc + pr + 1.0
	var bz_s1 := z_wall - 1.0
	for sx: float in [-1.0, 1.0]:
		for zr: Array in [[bz_n0, bz_n1], [bz_s0, bz_s1]]:
			var xa := cx + sx * (bx0 - cx)
			var xb := cx + sx * (bx1 - cx)
			_bed(data, Rect2(Vector2(minf(xa, xb), zr[0]), Vector2(absf(xb - xa), zr[1] - zr[0])), soil, sc, box, hc, hc_top)
	# East/west lawns beside the hall: a gravel walk and a row of beds.
	var z_n := cz - half * 0.55
	var hall_x := half * 0.45 + 1.5
	for sx: float in [-1.0, 1.0]:
		var xa := cx + sx * hall_x
		var xb := cx + sx * inner
		var x0 := minf(xa, xb)
		var x1 := maxf(xa, xb)
		if x1 - x0 < 8.0:
			continue
		var xm := (x0 + x1) * 0.5
		ground.call(gravel, xm - 1.5, z_n, xm + 1.5, z_hall, 0.03, gc)
		var zz := z_n + 1.0
		while zz + 7.0 < z_hall - 1.0:
			_bed(data, Rect2(Vector2(x0 + 1.0, zz), Vector2(xm - 2.5 - x0 - 1.0, 6.0)), soil, sc, box, hc, hc_top)
			_bed(data, Rect2(Vector2(xm + 2.5, zz), Vector2(x1 - 1.0 - xm - 2.5, 6.0)), soil, sc, box, hc, hc_top)
			zz += 8.0


## One parterre bed: dark soil edged with a clipped box hedge (0.45 m, one
## low collision box per side) and topiary (instanced ash planters) in a grid.
static func _bed(data: ChunkBuildData, r: Rect2, soil: WorldMeshBuilder, sc: Color, box: WorldMeshBuilder,
		hc: Color, hc_top: Color) -> void:
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var y := 0.04
	soil.add_quad(Vector3(r.position.x, y, r.end.y), Vector3(r.end.x, y, r.end.y), Vector3(r.end.x, y, r.position.y),
			Vector3(r.position.x, y, r.position.y), Vector3.UP, sc, sc)
	var t := 0.35
	var h := 0.45
	var sides := [
		[Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, h, r.position.y + t)],
		[Vector3(r.position.x, 0, r.end.y - t), Vector3(r.end.x, h, r.end.y)],
		[Vector3(r.position.x, 0, r.position.y + t), Vector3(r.position.x + t, h, r.end.y - t)],
		[Vector3(r.end.x - t, 0, r.position.y + t), Vector3(r.end.x, h, r.end.y - t)],
	]
	for sd: Array in sides:
		box.add_box(sd[0], sd[1], hc * 0.8, hc, hc_top)
		data.add_box_shape_lohi(sd[0], sd[1])
	# Topiary on a ~3 m grid, inset from the edging.
	var nx := maxi(1, int(r.size.x / 3.0))
	var nz := maxi(1, int(r.size.y / 3.0))
	for i in nx:
		for j in nz:
			var p := Vector3(r.position.x + r.size.x * (float(i) + 0.5) / float(nx), 0.0,
					r.position.y + r.size.y * (float(j) + 0.5) / float(nz))
			data.add_instance(&"topiary", Transform3D(Basis(), p))


## Octagonal stone basin with dark water, a pedestal and an iron statue.
static func _fountain(data: ChunkBuildData, c: Vector3) -> void:
	var st := data.mb(M.KEEP_STONE)
	var col := STONE_C
	var r := 3.6
	for k in 8:
		var a := TAU * (float(k) + 0.5) / 8.0
		var mid := c + Vector3(sin(a), 0.0, cos(a)) * r
		st.add_obox(mid + Vector3(0, 0.35, 0), Vector3(1.55, 0.35, 0.3), a, col * 0.7, col)
	# Water surface and basin floor.
	var wm := data.mb(M.WATER)
	var wc := Color(1, 1, 1)
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		var a1 := TAU * float(k + 1) / 8.0
		var w0 := c + Vector3(0, 0.45, 0)
		wm.add_tri(w0, w0 + Vector3(sin(a0), 0, cos(a0)) * r, w0 + Vector3(sin(a1), 0, cos(a1)) * r, wc)
	data.add_box_shape(c + Vector3(0, 0.35, 0), Vector3(r * 2.0, 0.7, r * 2.0))
	# Pedestal and statue (iron: a Push/Pull anchor in the middle of the garden).
	st.add_box(c + Vector3(-0.7, 0.0, -0.7), c + Vector3(0.7, 2.0, 0.7), col * 0.7, col, col)
	data.add_box_shape(c + Vector3(0, 1.0, 0), Vector3(1.4, 2.0, 1.4))
	data.add_instance(&"statue", Transform3D(Basis(), c + Vector3(0, 2.0, 0)))
	data.add_metal(c + Vector3(0, 3.2, 0), 120.0)
