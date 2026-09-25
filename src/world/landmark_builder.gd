class_name LandmarkBuilder
extends RefCounted
## Builds hand-placed landmarks from the city plan into ChunkBuildData.
## Each landmark is its own streaming unit; its far-LOD silhouette is built
## from the same data.

const M := WorldMaterials.Mat


## Generates the landmark `lm` (thread-safe).
static func build(plan: CityPlan, seed_value: int, lm: CityPlan.Landmark) -> ChunkBuildData:
	var data := ChunkBuildData.new()
	data.key = "lm:%s" % lm.id
	data.coord = plan.chunk_of(lm.center)
	match lm.type:
		&"keep_venture":
			KeepBuilder.build_venture(data, lm, seed_value)
		&"keep":
			KeepBuilder.build_generic(data, lm, seed_value)
		&"kredik_shaw":
			_kredik_shaw(data, lm, seed_value)
		&"fountain_square":
			_fountain_square(data, lm, seed_value)
		&"shop", &"hideout":
			_house(data, lm, seed_value)
		&"dock":
			_dock(data, lm, plan)
	if not lm.type in [&"keep"]:
		data.add_marker(&"landmark", Vector3(lm.center.x, 0.05, lm.center.y), {"landmark_id": lm.id})
	return data


## Kredik Shaw: the Lord Ruler's palace, a forest of black obsidian spires.
static func _kredik_shaw(data: ChunkBuildData, lm: CityPlan.Landmark, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, 4242)
	var c := lm.center
	var ob := data.mb(M.OBSIDIAN)
	var dark := Color(0.9, 0.9, 0.95)
	# Stepped base halls.
	for tier in 3:
		var half := 70.0 - float(tier) * 18.0
		var y0 := float(tier) * 12.0
		var lo := Vector3(c.x - half, y0, c.y - half * 0.8)
		var hi := Vector3(c.x + half, y0 + 12.0, c.y + half * 0.8)
		ob.add_banded_box(lo, hi, y0 + 3.0, dark * 0.5, dark, dark * 0.8, dark * 0.7, 0, true)
		data.add_box_shape_lohi(lo, hi)
		data.add_occluder_box(lo + Vector3(1, 0, 1), hi - Vector3(1, 1, 1))
		if tier == 0:
			data.add_nav_box(lo, hi, true)
			data.add_nav_obstruction(Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z), -1.0, 11.5)
	# Spires: a tall central one and a ring of lesser ones.
	var spires: Array[Vector4] = [Vector4(c.x, c.y, 16.0, lm.height)]
	var n := 14
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.15, 0.15)
		var rad := rng.randf_range(40.0, 150.0)
		var hgt := rng.randf_range(0.3, 0.85) * lm.height
		spires.append(Vector4(c.x + sin(a) * rad, c.y + cos(a) * rad, rng.randf_range(6.0, 12.0), hgt))
	for s in spires:
		var base := Vector3(s.x, 0, s.y)
		var w := s.z
		var h := s.w
		var h1 := h * 0.72
		ob.add_frustum(base, w, w * 0.45, h1, dark * 0.5, dark)
		ob.add_frustum(base + Vector3(0, h1, 0), w * 0.45, 0.05, h - h1, dark, dark * 1.1)
		data.add_convex_shape(PackedVector3Array([
			base + Vector3(-w, 0, -w), base + Vector3(w, 0, -w), base + Vector3(w, 0, w), base + Vector3(-w, 0, w),
			base + Vector3(-w * 0.45, h1, -w * 0.45), base + Vector3(w * 0.45, h1, -w * 0.45),
			base + Vector3(w * 0.45, h1, w * 0.45), base + Vector3(-w * 0.45, h1, w * 0.45)]))
		data.add_convex_shape(PackedVector3Array([
			base + Vector3(-w * 0.45, h1, -w * 0.45), base + Vector3(w * 0.45, h1, -w * 0.45),
			base + Vector3(w * 0.45, h1, w * 0.45), base + Vector3(-w * 0.45, h1, w * 0.45), base + Vector3(0, h, 0)]))
		data.add_nav_obstruction(Rect2(s.x - w, s.y - w, w * 2.0, w * 2.0), -1.0, 20.0)
		# Iron crowns on the spire tips: huge anchors for steel-jumping.
		data.add_metal(base + Vector3(0, h - 1.0, 0), 300.0)
		data.add_metal(base + Vector3(0, h1, 0), 120.0)
		# Sparse slit windows glowing red-orange.
		var win := data.db(M.WINDOW)
		for k in int(h1 / 14.0):
			if rng.randf() > 0.45:
				continue
			var y := 8.0 + float(k) * 14.0
			var t := y / h1
			var ww := lerpf(w, w * 0.45, t) + 0.05
			var col := Color(rng.randf_range(0.6, 1.0), rng.randf(), 0, 1)
			win.add_quad(base + Vector3(-0.35, y, ww), base + Vector3(0.35, y, ww), base + Vector3(0.35, y + 3.0, ww),
					base + Vector3(-0.35, y + 3.0, ww), Vector3.BACK, col, col)
	# Braziers at the gates.
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(c.x + 20.0 * sx, 0, c.y + 70.0)
		data.lamp_posts.append({"pos": p, "dir": Vector2(-sx, 0), "lit": true, "shadow": false})
		data.metal_count += 1
		data.add_light(p + Vector3(-sx * 0.75, 3.75, 0), Color(1.0, 0.45, 0.2), 12.0, 3.0)


## Fountain Square: open plaza with a fountain, execution platform, lamps.
static func _fountain_square(data: ChunkBuildData, lm: CityPlan.Landmark, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, 99)
	var c := Vector3(lm.center.x, 0, lm.center.y)
	var stone := data.mb(M.KEEP_STONE)
	var sc := Color(0.6, 0.58, 0.55)
	# Octagonal basin approximated with boxes, and a central column.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := c + Vector3(sin(a), 0, cos(a)) * 7.0
		stone.add_obox(p + Vector3(0, 0.45, 0), Vector3(2.9, 0.45, 0.4), a, sc * 0.6, sc)
	data.add_box_shape(c + Vector3(0, 0.45, 0), Vector3(14.5, 0.9, 14.5))
	data.add_nav_box(c - Vector3(7.2, 0, 7.2), c + Vector3(7.2, 0.9, 7.2), false)
	stone.add_frustum(c, 1.2, 0.8, 5.0, sc * 0.5, sc)
	data.add_box_shape(c + Vector3(0, 2.5, 0), Vector3(2.2, 5.0, 2.2))
	data.mb(M.WATER).add_quad(c + Vector3(-6.6, 0.6, 6.6), c + Vector3(6.6, 0.6, 6.6), c + Vector3(6.6, 0.6, -6.6),
			c + Vector3(-6.6, 0.6, -6.6), Vector3.UP, Color.WHITE, Color.WHITE)
	# Iron statue of the Lord Ruler atop the column.
	var iron := data.mb(M.IRON)
	var ic := Color(1, 1, 1)
	iron.add_box(c + Vector3(-0.5, 5.0, -0.35), c + Vector3(0.5, 7.4, 0.35), ic, ic, ic)
	iron.add_box(c + Vector3(-0.25, 7.4, -0.25), c + Vector3(0.25, 7.9, 0.25), ic, ic, ic)
	data.add_metal(c + Vector3(0, 6.5, 0), 250.0)
	# Execution platform with iron cages.
	var plat := c + Vector3(0, 0, -30)
	var wood := data.mb(M.WOOD)
	wood.add_box(plat + Vector3(-8, 0, -4), plat + Vector3(8, 1.6, 4), Color(0.5, 0.45, 0.4), Color(0.7, 0.65, 0.6), Color(0.8, 0.75, 0.7))
	data.add_box_shape(plat + Vector3(0, 0.8, 0), Vector3(16, 1.6, 8))
	data.add_nav_box(plat + Vector3(-8, 0, -4), plat + Vector3(8, 1.6, 4), true)
	for k in 3:
		var cp := plat + Vector3(-5.0 + 5.0 * k, 1.6, 0)
		for bx in 5:
			for bz: float in [-0.9, 0.9]:
				var x := cp.x - 0.9 + 0.45 * bx
				iron.add_box(Vector3(x - 0.03, cp.y, cp.z + bz - 0.03), Vector3(x + 0.03, cp.y + 2.4, cp.z + bz + 0.03), ic, ic, ic)
		iron.add_box(cp + Vector3(-1, 2.4, -1), cp + Vector3(1, 2.5, 1), ic, ic, ic, true)
		data.add_metal(cp + Vector3(0, 1.8, 0), 80.0)
	# Ring of lamp posts.
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := c + Vector3(sin(a), 0, cos(a)) * 42.0
		var dir := Vector2(-sin(a), -cos(a))
		data.lamp_posts.append({"pos": p, "dir": dir, "lit": rng.randf() < 0.8, "shadow": false})
		data.metal_count += 1
		if data.lamp_posts[-1]["lit"]:
			data.add_light(p + Vector3(dir.x * 0.75, 3.75, dir.y * 0.75), PropPlacer.LAMP_LIGHT_COLOR, 10.0, 2.0)
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 36.0)
		var p := c + Vector3(sin(a), 0, cos(a)) * r
		if absf(p.z - plat.z) < 6.0 and absf(p.x - plat.x) < 10.0:
			continue
		data.add_instance(&"stall", Transform3D(Basis(Vector3.UP, a + PI), p))
		data.add_box_shape(p + Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 1.1), a + PI)


## Small landmark houses (Clubs' shop, the crew hideout).
static func _house(data: ChunkBuildData, lm: CityPlan.Landmark, seed_value: int) -> void:
	var f := lm.footprint.grow(-2.0)
	var lot := ChunkLayout.Lot.new()
	lot.rect = f
	lot.floors = 3
	lot.height = ChunkLayout._height_for(3)
	lot.roof = ChunkLayout.Roof.GABLE_X if f.size.x > f.size.y else ChunkLayout.Roof.GABLE_Z
	lot.mat = ChunkLayout.WallMat.PLASTER if lm.type == &"shop" else ChunkLayout.WallMat.BRICK
	lot.tint = 0.62
	lot.lot_seed = CityPlan.hash_ints(seed_value, hash(lm.id))
	lot.front = ChunkLayout.FACE_S
	lot.style = {"lit": 0.55, "bars": 0.3, "wall_lantern": 0.4, "chimneys": [1, 2], "roof_metal": 1.0}
	BuildingBuilder.build_lot(data, lot)
	# Carpentry yard / back court with loose metal clutter.
	var rng := RandomNumberGenerator.new()
	rng.seed = lot.lot_seed
	for i in 4:
		var p := Vector3(rng.randf_range(f.position.x, f.end.x), 0, f.end.y + 1.2 + rng.randf() * 0.5)
		data.add_rigid(&"barrel" if i % 2 == 0 else &"crate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 0.5, 0)))
	var lp := Vector3(f.get_center().x + 1.5, 3.0, f.end.y + 0.42)
	data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(Vector3.FORWARD), lp))
	data.add_metal(lp + Vector3(0, 0.35, 0), 4.0)
	data.add_light(lp, Color(1.0, 0.6, 0.28), 8.0, 2.0)


## Extraction dock on the canal: wooden jetty, steps from the quay, a boat.
static func _dock(data: ChunkBuildData, lm: CityPlan.Landmark, plan: CityPlan) -> void:
	var canal: CityPlan.Canal = null
	for cn in plan.canals:
		if cn.reserved_rect().intersects(lm.footprint):
			canal = cn
			break
	var wy := canal.water_y if canal != null else -2.2
	var x_edge := canal.rect.position.x if canal != null else lm.center.x
	var z0 := lm.footprint.position.y + 5.0
	var z1 := lm.footprint.end.y - 5.0
	var wood := data.mb(M.WOOD)
	var wc := Color(0.55, 0.5, 0.45)
	var deck_y := -0.9
	var deck_lo := Vector3(x_edge, deck_y - 0.25, z0)
	var deck_hi := Vector3(x_edge + 7.0, deck_y, z1)
	wood.add_box(deck_lo, deck_hi, wc * 0.6, wc, wc * 1.1, true)
	data.add_box_shape_lohi(deck_lo, deck_hi)
	data.add_nav_rect(Rect2(deck_lo.x, deck_lo.z, 7.0, z1 - z0), deck_y)
	for px: float in [x_edge + 0.3, x_edge + 6.7]:
		var pz := z0 + 0.3
		while pz < z1:
			wood.add_box(Vector3(px - 0.15, -4.5, pz - 0.15), Vector3(px + 0.15, deck_y + 0.9, pz + 0.15), wc * 0.4, wc * 0.8, wc)
			pz += 3.0
	# Steps down from the quay (three treads).
	for k in 3:
		var y := -0.3 * float(k + 1)
		var lo := Vector3(x_edge, y - 0.3, z0 - 3.0 + float(k))
		var hi := Vector3(x_edge + 2.0, y, z0 - 2.0 + float(k))
		data.mb(M.KEEP_STONE).add_box(lo, hi, Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.6), Color(0.65, 0.65, 0.65))
		data.add_box_shape_lohi(lo, hi)
	# The boat.
	var bx := x_edge + 9.5
	var bz := (z0 + z1) * 0.5
	var hull_lo := Vector3(bx - 2.0, wy - 0.6, bz - 6.0)
	var hull_hi := Vector3(bx + 2.0, wy + 0.8, bz + 6.0)
	wood.add_box(hull_lo, hull_hi, wc * 0.3, wc * 0.7, wc * 0.9, true)
	wood.add_pyramid(Vector3(bx, wy + 0.8, bz + 6.0), 2.0, 0.01, wc)
	data.add_box_shape_lohi(hull_lo, hull_hi)
	var mast := Vector3(bx, wy + 0.8, bz - 3.5)
	data.mb(M.IRON).add_box(mast + Vector3(-0.05, 0, -0.05), mast + Vector3(0.05, 3.2, 0.05), Color.WHITE, Color.WHITE, Color.WHITE)
	data.add_instance(&"wall_lantern", Transform3D(Basis(), mast + Vector3(0, 3.2, 0.3)))
	data.add_metal(mast + Vector3(0, 3.0, 0), 10.0)
	data.add_light(mast + Vector3(0, 3.2, 0.3), Color(1.0, 0.6, 0.3), 10.0, 2.4, true)
	# Mooring rings (metal) and lamp posts at the quay.
	for k in 3:
		data.add_metal(Vector3(x_edge + 6.8, deck_y + 0.2, lerpf(z0 + 1.0, z1 - 1.0, float(k) / 2.0)), 10.0)
	data.lamp_posts.append({"pos": Vector3(x_edge - 2.0, 0, z0 - 2.0), "dir": Vector2(1, 0), "lit": true, "shadow": false})
	data.lamp_posts.append({"pos": Vector3(x_edge - 2.0, 0, z1 + 2.0), "dir": Vector2(1, 0), "lit": true, "shadow": false})
	data.metal_count += 2
	for zz: float in [z0 - 2.0, z1 + 2.0]:
		data.add_light(Vector3(x_edge - 1.25, 3.75, zz), PropPlacer.LAMP_LIGHT_COLOR, 10.0, 2.0)
	var ep := Vector3(x_edge + 3.5, deck_y + 0.05, bz)
	data.add_marker(&"objective_point", ep, {"objective_id": &"extraction", "checkpoint_id": &"extraction"})
	data.fog_volumes.append({"pos": Vector3(x_edge + 9.0, wy + 3.0, bz), "size": Vector3(20.0, 8.0, 30.0), "density": 1.3})
