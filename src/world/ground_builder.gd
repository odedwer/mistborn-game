class_name GroundBuilder
extends RefCounted
## Ground slabs, canals (water, bed, embankments, quay bollards, mist) and
## bridges for one chunk. Thread-safe, data only.

const M := WorldMaterials.Mat
const SLAB_BOTTOM := -7.0
const TILE := 16.0


## Subtracts every rect in `holes` from `r`; returns the remaining pieces.
static func subtract_rects(r: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array[Rect2] = [r]
	for hole in holes:
		var next: Array[Rect2] = []
		for p in pieces:
			if not p.intersects(hole):
				next.append(p)
				continue
			var i := p.intersection(hole)
			if i.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				next.append(Rect2(p.position.x, i.end.y, p.size.x, p.end.y - i.end.y))
			if i.position.x > p.position.x:
				next.append(Rect2(p.position.x, i.position.y, i.position.x - p.position.x, i.size.y))
			if i.end.x < p.end.x:
				next.append(Rect2(i.end.x, i.position.y, p.end.x - i.end.x, i.size.y))
		pieces = next
	return pieces


static func water_rects(plan: CityPlan) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in plan.canals:
		out.append(c.rect)
	return out


## Builds ground, canals and bridges into `data` for chunk layout `L`.
static func build(data: ChunkBuildData, plan: CityPlan, L: ChunkLayout, seed_value: int, nav_border: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, L.coord.x, L.coord.y, 91)
	var holes := water_rects(plan)
	var ground_type := str(L.style.get("ground", "cobble"))
	var mat := M.COBBLE
	if ground_type == "ash":
		mat = M.ASH
	elif ground_type == "dark":
		mat = M.GROUND_DARK
	var gb := data.mb(mat)
	for piece in subtract_rects(L.rect, holes):
		if piece.size.x < 0.01 or piece.size.y < 0.01:
			continue
		data.add_box_shape_lohi(Vector3(piece.position.x, SLAB_BOTTOM, piece.position.y), Vector3(piece.end.x, 0.0, piece.end.y))
		_tiles(gb, piece, rng)
	# Nav ground covers the chunk plus a border so neighbouring tiles line up.
	for piece in subtract_rects(L.rect.grow(nav_border), holes):
		data.add_nav_rect(piece, 0.0)
	for canal in plan.canals:
		var w := canal.rect.intersection(L.rect)
		if w.size.x <= 0.01 or w.size.y <= 0.01:
			continue
		_canal(data, canal, w, L, plan)
	for b in L.bridges:
		_bridge(data, b, plan)


## Ground surface split into tiles with random soot/ash tint per corner.
static func _tiles(b: WorldMeshBuilder, r: Rect2, rng: RandomNumberGenerator) -> void:
	var nx := maxi(1, int(ceil(r.size.x / TILE)))
	var nz := maxi(1, int(ceil(r.size.y / TILE)))
	var sx := r.size.x / float(nx)
	var sz := r.size.y / float(nz)
	for i in nx:
		for j in nz:
			var x0 := r.position.x + sx * i
			var z0 := r.position.y + sz * j
			var c0 := Color.WHITE * _ground_tint(x0, z0 + sz)
			var c1 := Color.WHITE * _ground_tint(x0 + sx, z0 + sz)
			var c2 := Color.WHITE * _ground_tint(x0 + sx, z0)
			var c3 := Color.WHITE * _ground_tint(x0, z0)
			var base := b.verts.size()
			b.add_quad(Vector3(x0, 0, z0 + sz), Vector3(x0 + sx, 0, z0 + sz), Vector3(x0 + sx, 0, z0),
					Vector3(x0, 0, z0), Vector3.UP, c0, c3)
			b.colors[base + 1] = c1
			b.colors[base + 2] = c2


## Position-hashed tint so neighbouring tiles/chunks agree at shared corners.
static func _ground_tint(x: float, z: float) -> float:
	var h := CityPlan.hash01(7, roundi(x * 4.0), roundi(z * 4.0))
	return lerpf(0.5, 0.85, h)


static func _canal(data: ChunkBuildData, canal: CityPlan.Canal, w: Rect2, L: ChunkLayout, plan: CityPlan) -> void:
	var wy := canal.water_y
	var by := canal.bed_y
	# Water surface.
	var wc := Color(1, 1, 1)
	data.mb(M.WATER).add_quad(Vector3(w.position.x, wy, w.end.y), Vector3(w.end.x, wy, w.end.y),
			Vector3(w.end.x, wy, w.position.y), Vector3(w.position.x, wy, w.position.y), Vector3.UP, wc, wc)
	# Bed.
	var bed_c := Color(0.25, 0.24, 0.23)
	data.mb(M.GROUND_DARK).add_quad(Vector3(w.position.x, by, w.end.y), Vector3(w.end.x, by, w.end.y),
			Vector3(w.end.x, by, w.position.y), Vector3(w.position.x, by, w.position.y), Vector3.UP, bed_c, bed_c)
	data.add_box_shape_lohi(Vector3(w.position.x, by - 1.0, w.position.y), Vector3(w.end.x, by, w.end.y))
	# Embankment walls facing the water (collision comes from the ground slabs).
	var cw := data.mb(M.CANAL_WALL)
	var top := Color(0.55, 0.55, 0.55)
	var low := Color(0.18, 0.2, 0.2)
	var kerb := data.mb(M.TRIM)
	var kc := Color(0.45, 0.44, 0.43)
	if canal.is_vertical():
		var xw := canal.rect.position.x
		var xe := canal.rect.end.x
		if xw >= L.rect.position.x and xw <= L.rect.end.x:
			cw.add_quad(Vector3(xw, by, w.end.y), Vector3(xw, by, w.position.y), Vector3(xw, 0, w.position.y),
					Vector3(xw, 0, w.end.y), Vector3.RIGHT, low, top)
			kerb.add_box(Vector3(xw - 0.6, 0.0, w.position.y), Vector3(xw, 0.18, w.end.y), kc, kc, kc)
		if xe >= L.rect.position.x and xe <= L.rect.end.x:
			cw.add_quad(Vector3(xe, by, w.position.y), Vector3(xe, by, w.end.y), Vector3(xe, 0, w.end.y),
					Vector3(xe, 0, w.position.y), Vector3.LEFT, low, top)
			kerb.add_box(Vector3(xe, 0.0, w.position.y), Vector3(xe + 0.6, 0.18, w.end.y), kc, kc, kc)
		# Iron mooring bollards along both quays.
		var z := w.position.y + 6.0
		while z < w.end.y - 3.0:
			for bx: float in [xw - 1.2, xe + 1.2]:
				var p := Vector3(bx, 0.0, z)
				if L.rect.has_point(Vector2(p.x, p.z)) and not _near_bridge(L, Vector2(p.x, p.z)) and plan.landmark_overlapping(Rect2(p.x - 1, p.z - 1, 2, 2)) == null:
					_bollard(data, p)
			z += 16.0
		data.fog_volumes.append({"pos": Vector3(w.get_center().x, wy + 3.0, w.get_center().y),
				"size": Vector3(w.size.x + 8.0, 9.0, w.size.y), "density": 1.0})
	else:
		var zn := canal.rect.position.y
		var zs := canal.rect.end.y
		if zn >= L.rect.position.y and zn <= L.rect.end.y:
			cw.add_quad(Vector3(w.position.x, by, zn), Vector3(w.end.x, by, zn), Vector3(w.end.x, 0, zn),
					Vector3(w.position.x, 0, zn), Vector3.BACK, low, top)
			kerb.add_box(Vector3(w.position.x, 0.0, zn - 0.6), Vector3(w.end.x, 0.18, zn), kc, kc, kc)
		if zs >= L.rect.position.y and zs <= L.rect.end.y:
			cw.add_quad(Vector3(w.end.x, by, zs), Vector3(w.position.x, by, zs), Vector3(w.position.x, 0, zs),
					Vector3(w.end.x, 0, zs), Vector3.FORWARD, low, top)
			kerb.add_box(Vector3(w.position.x, 0.0, zs), Vector3(w.end.x, 0.18, zs + 0.6), kc, kc, kc)
		var x := w.position.x + 6.0
		while x < w.end.x - 3.0:
			for bz: float in [zn - 1.2, zs + 1.2]:
				var p := Vector3(x, 0.0, bz)
				if L.rect.has_point(Vector2(p.x, p.z)) and not _near_bridge(L, Vector2(p.x, p.z)) and plan.landmark_overlapping(Rect2(p.x - 1, p.z - 1, 2, 2)) == null:
					_bollard(data, p)
			x += 16.0
		data.fog_volumes.append({"pos": Vector3(w.get_center().x, wy + 3.0, w.get_center().y),
				"size": Vector3(w.size.x, 9.0, w.size.y + 8.0), "density": 1.0})


static func _near_bridge(L: ChunkLayout, p: Vector2) -> bool:
	for b in L.bridges:
		if (b["rect"] as Rect2).grow(2.0).has_point(p):
			return true
	return false


static func _bollard(data: ChunkBuildData, p: Vector3) -> void:
	data.add_instance(&"bollard", Transform3D(Basis(), p))
	data.add_box_shape(p + Vector3(0, 0.4, 0), Vector3(0.45, 0.8, 0.45))
	data.add_metal(p + Vector3(0, 0.6, 0), 30.0)


## Stone bridge deck with an arch skirt and iron railings full of metal.
static func _bridge(data: ChunkBuildData, b: Dictionary, plan: CityPlan) -> void:
	var r: Rect2 = b["rect"]
	var along_x: bool = b["along_x"]
	var stone := data.mb(M.KEEP_STONE)
	var c := Color(0.55, 0.54, 0.52)
	var lo := Vector3(r.position.x, -1.1, r.position.y)
	var hi := Vector3(r.end.x, 0.02, r.end.y)
	stone.add_box(lo, hi, c * 0.6, c, c * 0.9, true)
	data.add_box_shape_lohi(lo, hi)
	data.add_nav_rect(r, 0.02)
	# Arch skirt below the deck (visual).
	var skirt_lo := Vector3(r.position.x + (1.5 if along_x else 0.3), -2.2, r.position.y + (0.3 if along_x else 1.5))
	var skirt_hi := Vector3(r.end.x - (1.5 if along_x else 0.3), -1.1, r.end.y - (0.3 if along_x else 1.5))
	stone.add_box(skirt_lo, skirt_hi, c * 0.4, c * 0.6, c * 0.6, true)
	# Iron railings on both sides.
	var iron := data.mb(M.IRON)
	var wc := Color(1, 1, 1)
	var sides: Array = []
	if along_x:
		sides = [[Vector3(r.position.x, 0, r.position.y + 0.2), Vector3(r.end.x, 0, r.position.y + 0.2)],
				[Vector3(r.position.x, 0, r.end.y - 0.2), Vector3(r.end.x, 0, r.end.y - 0.2)]]
	else:
		sides = [[Vector3(r.position.x + 0.2, 0, r.position.y), Vector3(r.position.x + 0.2, 0, r.end.y)],
				[Vector3(r.end.x - 0.2, 0, r.position.y), Vector3(r.end.x - 0.2, 0, r.end.y)]]
	for s: Array in sides:
		var a: Vector3 = s[0]
		var e: Vector3 = s[1]
		var d := (e - a)
		var seg_len := d.length()
		var dn := d / seg_len
		var perp := Vector3(-dn.z, 0, dn.x) * 0.03
		var rail_lo := a - perp + Vector3(0, 1.0, 0)
		var rail_hi := e + perp + Vector3(0, 1.08, 0)
		iron.add_box(Vector3(minf(rail_lo.x, rail_hi.x), 1.0, minf(rail_lo.z, rail_hi.z)),
				Vector3(maxf(rail_lo.x, rail_hi.x), 1.08, maxf(rail_lo.z, rail_hi.z)), wc, wc, wc, true)
		iron.add_box(Vector3(minf(rail_lo.x, rail_hi.x), 0.5, minf(rail_lo.z, rail_hi.z)),
				Vector3(maxf(rail_lo.x, rail_hi.x), 0.55, maxf(rail_lo.z, rail_hi.z)), wc, wc, wc, true)
		var n := int(seg_len / 1.2)
		for i in n + 1:
			var p := a + dn * (float(i) * seg_len / float(n))
			iron.add_box(p + Vector3(-0.03, 0.0, -0.03), p + Vector3(0.03, 1.0, 0.03), wc, wc, wc)
		var mid := (a + e) * 0.5
		var size := Vector3(absf(d.x) + 0.1, 1.1, absf(d.z) + 0.1)
		data.add_box_shape(mid + Vector3(0, 0.55, 0), size)
		# Metal anchors every ~4 m along the railing.
		var m := maxi(2, int(seg_len / 4.5))
		for i in m:
			var t := (float(i) + 0.5) / float(m)
			data.add_metal(a.lerp(e, t) + Vector3(0, 1.0, 0), 25.0)
