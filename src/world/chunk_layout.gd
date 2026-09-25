class_name ChunkLayout
extends RefCounted
## Pure-data street/lot layout of one streamed chunk.
##
## Deterministic from (world seed, chunk coordinates, plan): the same inputs
## always yield the same streets, lots, lamps, bridges and markers, on any
## thread. Chunks are separated by "boundary" streets centred on the chunk
## borders (their widths are hashed from the shared border, so neighbours
## agree); inside, rows and blocks are split independently per chunk, which
## gives staggered T-junctions and an irregular old-city feel.
##
## This pass is cheap (no meshes), so it also feeds the far-LOD skyline and
## the always-available marker index.

const FLOOR_H := 3.2
const GROUND_FLOOR_H := 3.6

enum Roof { FLAT, GABLE_X, GABLE_Z }
enum WallMat { STONE, BRICK, PLASTER }

## Face bits (shared with BuildingBuilder).
const FACE_S := 1   # +Z
const FACE_N := 2   # -Z
const FACE_E := 4   # +X
const FACE_W := 8   # -X


## One building lot.
class Lot:
	var rect: Rect2
	var floors: int = 3
	## Height of the wall top (flat roof surface / eaves).
	var height: float = 10.0
	var roof: int = Roof.GABLE_X
	var mat: int = WallMat.STONE
	## Base colour multiplier (lower = sootier).
	var tint: float = 0.7
	var lot_seed: int = 0
	var district: StringName = &""
	var style: Dictionary = {}
	## Faces that touch a neighbour (no windows).
	var shared: int = 0
	## The face that looks onto the street (doors).
	var front: int = FACE_S
	## True if a mission marker forced its shape.
	var forced: bool = false

	## Height of the gable above the eaves (0 for flat roofs).
	func roof_rise() -> float:
		if roof == Roof.FLAT:
			return 0.0
		var span := rect.size.y if roof == Roof.GABLE_X else rect.size.x
		return minf(span * 0.5 * 0.72, 5.5)

	## Highest point of the roof (ridge or parapet).
	func top() -> float:
		return height + (roof_rise() if roof != Roof.FLAT else 0.7)

	func center() -> Vector2:
		return rect.get_center()


## One street centre-line segment.
class Street:
	var a: Vector2
	var b: Vector2
	var width: float
	var boundary: bool

	func length() -> float:
		return a.distance_to(b)

	func direction() -> Vector2:
		return (b - a).normalized()


var coord := Vector2i.ZERO
var rect := Rect2()
var district: StringName = &""
var style: Dictionary = {}
var lots: Array[Lot] = []
var streets: Array[Street] = []
## Open squares inside blocks (market plazas, yards).
var plazas: Array[Rect2] = []
## Lamp post bases (y = ground) and the XZ direction their arm points.
var lamps: PackedVector3Array = PackedVector3Array()
var lamp_dirs: PackedVector2Array = PackedVector2Array()
## Bridges: {rect: Rect2 (XZ deck), along_x: bool, deck_y: float}
var bridges: Array[Dictionary] = []
## Markers: {group: StringName, pos: Vector3, meta: Dictionary}
var markers: Array[Dictionary] = []
## True if nothing but ground/streets is generated here.
var empty := false


## Width of a boundary street segment. `vertical` lines run along Z at
## x = line * size; `seg` is the chunk index along the line.
static func boundary_width(plan: CityPlan, seed_value: int, vertical: bool, line: int, seg: int) -> float:
	var s := plan.chunk_size
	var mid := Vector2(line * s, seg * s + s * 0.5) if vertical else Vector2(seg * s + s * 0.5, line * s)
	var st := plan.style_at(mid)
	var r: Array = st.get("arterial", [7.0, 9.0])
	var t := CityPlan.hash01(seed_value, 1 if vertical else 2, line, seg)
	return lerpf(float(r[0]), float(r[1]), t)


## Builds the layout for chunk `c`.
static func generate(plan: CityPlan, seed_value: int, c: Vector2i) -> ChunkLayout:
	var L := ChunkLayout.new()
	L._build(plan, seed_value, c)
	return L


func _build(plan: CityPlan, seed_value: int, c: Vector2i) -> void:
	coord = c
	rect = plan.chunk_rect(c)
	var s := plan.chunk_size
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, c.x, c.y, 17)
	district = plan.district_at(rect.get_center())
	style = plan.style(district)

	var w_w := boundary_width(plan, seed_value, true, c.x, c.y)
	var w_e := boundary_width(plan, seed_value, true, c.x + 1, c.y)
	var w_n := boundary_width(plan, seed_value, false, c.y, c.x)
	var w_s := boundary_width(plan, seed_value, false, c.y + 1, c.x)

	# This chunk owns its west and north boundary street segments.
	_add_street(Vector2(x0, z0), Vector2(x0, z1), w_w, true)
	_add_street(Vector2(x0, z0), Vector2(x1, z0), w_n, true)

	var inner := Rect2(x0 + w_w * 0.5, z0 + w_n * 0.5, s - (w_w + w_e) * 0.5, s - (w_n + w_s) * 0.5)
	empty = bool(style.get("empty", false))
	if not empty:
		_build_blocks(plan, rng, inner)
	_place_bridges(plan, w_w, w_n)
	_place_lamps(plan, rng)
	_place_markers(plan, seed_value)


func _add_street(a: Vector2, b: Vector2, w: float, boundary: bool) -> void:
	var st := Street.new()
	st.a = a
	st.b = b
	st.width = w
	st.boundary = boundary
	streets.append(st)


## Splits [start, end] into alternating blocks and streets.
## Returns an array of Vector2(block_start, block_end); street centres/widths
## are appended to `gaps` as Vector2(centre, width).
static func _split(rng: RandomNumberGenerator, start: float, end: float, bmin: float, bmax: float,
		smin: float, smax: float, gaps: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pos := start
	while true:
		var remaining := end - pos
		if remaining <= bmax * 1.25:
			out.append(Vector2(pos, end))
			break
		var blen := rng.randf_range(bmin, bmax)
		var sw := rng.randf_range(smin, smax)
		if remaining - blen - sw < bmin:
			out.append(Vector2(pos, end))
			break
		out.append(Vector2(pos, pos + blen))
		gaps.append(Vector2(pos + blen + sw * 0.5, sw))
		pos += blen + sw
	return out


func _build_blocks(plan: CityPlan, rng: RandomNumberGenerator, inner: Rect2) -> void:
	var br: Array = style.get("block", [30, 45])
	var sr: Array = style.get("street", [4.0, 7.0])
	var bmin := float(br[0])
	var bmax := float(br[1])
	var smin := float(sr[0])
	var smax := float(sr[1])
	var row_gaps := PackedVector2Array()
	var rows := _split(rng, inner.position.y, inner.end.y, bmin, bmax, smin, smax, row_gaps)
	for g in row_gaps:
		_add_street(Vector2(rect.position.x, g.x), Vector2(rect.end.x, g.x), g.y, false)
	for row in rows:
		var col_gaps := PackedVector2Array()
		var cols := _split(rng, inner.position.x, inner.end.x, bmin * 0.9, bmax * 1.1, smin, smax, col_gaps)
		for g in col_gaps:
			_add_street(Vector2(g.x, row.x - 1.0), Vector2(g.x, row.y + 1.0), g.y, false)
		for col in cols:
			var block := Rect2(col.x, row.x, col.y - col.x, row.y - row.x)
			# Irregular edges: nudge each block edge inward a little.
			var gx0 := rng.randf_range(0.0, 1.2)
			var gz0 := rng.randf_range(0.0, 1.2)
			var gx1 := rng.randf_range(0.0, 1.2)
			var gz1 := rng.randf_range(0.0, 1.2)
			block = Rect2(block.position.x + gx0, block.position.y + gz0,
					block.size.x - gx0 - gx1, block.size.y - gz0 - gz1)
			_process_block(plan, rng, block)


func _process_block(plan: CityPlan, rng: RandomNumberGenerator, block: Rect2) -> void:
	var sub_seed := rng.randi()
	var center := block.get_center()
	var btype := plan.district_at(center)
	var bstyle := plan.style(btype)
	if bool(bstyle.get("empty", false)):
		return
	if plan.landmark_overlapping(block.grow(2.0)) != null:
		return
	# Clip against canals (keep the larger remaining side).
	for canal in plan.canals_overlapping(block):
		var rr := canal.reserved_rect()
		if canal.is_vertical():
			var left := Rect2(block.position.x, block.position.y, rr.position.x - block.position.x, block.size.y)
			var right := Rect2(rr.end.x, block.position.y, block.end.x - rr.end.x, block.size.y)
			block = left if left.size.x >= right.size.x else right
		else:
			var top := Rect2(block.position.x, block.position.y, block.size.x, rr.position.y - block.position.y)
			var bot := Rect2(block.position.x, rr.end.y, block.size.x, block.end.y - rr.end.y)
			block = top if top.size.y >= bot.size.y else bot
		if block.size.x < 8.0 or block.size.y < 8.0:
			return
	# Stay clear of the city wall.
	var corners := [block.position, Vector2(block.end.x, block.position.y), block.end,
			Vector2(block.position.x, block.end.y)]
	for p: Vector2 in corners:
		if not plan.inside_city(p):
			return
	if plan.distance_to_wall(block.get_center()) < block.size.length() * 0.5 + plan.wall_thickness + 6.0:
		return
	var brng := RandomNumberGenerator.new()
	brng.seed = sub_seed
	if brng.randf() < float(bstyle.get("plaza", 0.0)):
		plazas.append(block)
		return
	_fill_block(brng, block, btype, bstyle)


func _fill_block(brng: RandomNumberGenerator, block: Rect2, btype: StringName, bstyle: Dictionary) -> void:
	var long_x := block.size.x >= block.size.y
	var length := block.size.x if long_x else block.size.y
	var depth := block.size.y if long_x else block.size.x
	var dr: Array = bstyle.get("lot_d", [9.0, 13.0])
	var d_min := float(dr[0])
	var d_max := float(dr[1])
	var gr: Array = bstyle.get("backgap", [0.0, 4.0])
	# Rows as Vector3(start_offset, depth, front_is_min_side(1/0))
	var rows: Array[Vector3] = []
	if depth >= d_min * 2.0 + 1.0:
		var gap := brng.randf_range(float(gr[0]), float(gr[1]))
		if brng.randf() < 0.45:
			gap = 0.0
		var each := (depth - gap) * 0.5
		if each > d_max * 1.35:
			each = d_max * 1.35
		rows.append(Vector3(0.0, each, 1.0))
		rows.append(Vector3(depth - each, each, 0.0))
	else:
		rows.append(Vector3(0.0, depth, 1.0))
	var touching := rows.size() == 2 and absf(rows[0].y - rows[1].x) < 0.05
	var wr: Array = bstyle.get("lot_w", [7.0, 11.0])
	var w_min := float(wr[0])
	var w_max := float(wr[1])
	var alley := float(bstyle.get("alley_chance", 0.1))
	for row in rows:
		var pos := 0.0
		var prev: Lot = null
		while pos < length - 0.5:
			var remaining := length - pos
			var w := brng.randf_range(w_min, w_max)
			if remaining - w < w_min:
				w = remaining
			var lot := _make_lot(brng, btype, bstyle)
			var a := pos
			var b := pos + w
			if long_x:
				lot.rect = Rect2(block.position.x + a, block.position.y + row.x, b - a, row.y)
				lot.front = FACE_N if row.z > 0.5 else FACE_S
				if touching:
					lot.shared |= FACE_S if row.z > 0.5 else FACE_N
			else:
				lot.rect = Rect2(block.position.x + row.x, block.position.y + a, row.y, b - a)
				lot.front = FACE_W if row.z > 0.5 else FACE_E
				if touching:
					lot.shared |= FACE_E if row.z > 0.5 else FACE_W
			if prev != null:
				prev.shared |= FACE_E if long_x else FACE_S
				lot.shared |= FACE_W if long_x else FACE_N
			# Pitched roof ridge: usually parallel to the street.
			if lot.roof != Roof.FLAT:
				var ridge_along_row := brng.randf() < 0.75
				var along_x := long_x == ridge_along_row
				lot.roof = Roof.GABLE_X if along_x else Roof.GABLE_Z
			lots.append(lot)
			prev = lot
			pos = b
			if remaining - w > w_min + 4.0 and brng.randf() < alley:
				pos += brng.randf_range(2.5, 4.5)
				prev = null


func _make_lot(brng: RandomNumberGenerator, btype: StringName, bstyle: Dictionary) -> Lot:
	var lot := Lot.new()
	lot.lot_seed = brng.randi()
	lot.district = btype
	lot.style = bstyle
	var fr: Array = bstyle.get("floors", [3, 5])
	lot.floors = brng.randi_range(int(fr[0]), int(fr[1]))
	lot.height = _height_for(lot.floors) + brng.randf_range(-0.2, 0.7)
	lot.roof = Roof.FLAT if brng.randf() < float(bstyle.get("roof_flat", 0.25)) else Roof.GABLE_X
	var mats: Array = bstyle.get("mats", [0.4, 0.4, 0.2])
	var r := brng.randf() * (float(mats[0]) + float(mats[1]) + float(mats[2]))
	if r < float(mats[0]):
		lot.mat = WallMat.STONE
	elif r < float(mats[0]) + float(mats[1]):
		lot.mat = WallMat.BRICK
	else:
		lot.mat = WallMat.PLASTER
	var tr: Array = bstyle.get("tint", [0.5, 0.8])
	lot.tint = brng.randf_range(float(tr[0]), float(tr[1]))
	return lot


static func _height_for(floors: int) -> float:
	return GROUND_FLOOR_H + float(floors - 1) * FLOOR_H


func _place_bridges(plan: CityPlan, w_w: float, w_n: float) -> void:
	for canal in plan.canals:
		var cr := canal.rect
		if canal.is_vertical():
			# North boundary street (z = rect.position.y) crossing the canal.
			var z := rect.position.y
			if cr.position.x >= rect.position.x and cr.end.x <= rect.end.x and z > cr.position.y + 4.0 and z < cr.end.y - 4.0:
				var br := Rect2(cr.position.x - 1.5, z - w_n * 0.5, cr.size.x + 3.0, w_n)
				if plan.landmark_overlapping(br) == null:
					bridges.append({"rect": br, "along_x": true, "deck_y": 0.35, "canal": canal.id})
		else:
			var x := rect.position.x
			if cr.position.y >= rect.position.y and cr.end.y <= rect.end.y and x > cr.position.x + 4.0 and x < cr.end.x - 4.0:
				var br := Rect2(x - w_w * 0.5, cr.position.y - 1.5, w_w, cr.size.y + 3.0)
				if plan.landmark_overlapping(br) == null:
					bridges.append({"rect": br, "along_x": false, "deck_y": 0.35, "canal": canal.id})


func _in_water(plan: CityPlan, p: Vector2, margin: float) -> bool:
	for canal in plan.canals:
		if canal.rect.grow(margin).has_point(p):
			return true
	return false


func _blocked(plan: CityPlan, p: Vector2) -> bool:
	if _in_water(plan, p, 1.0):
		return true
	for lm in plan.landmarks:
		if lm.footprint.grow(1.0).has_point(p):
			return true
	if not plan.inside_city(p) or plan.distance_to_wall(p) < plan.wall_thickness + 2.0:
		return true
	for lot in lots:
		if lot.rect.grow(0.4).has_point(p):
			return true
	return false


func _place_lamps(plan: CityPlan, rng: RandomNumberGenerator) -> void:
	var spacing := float(style.get("lamp_spacing", 20.0))
	if spacing > 0.0:
		for st in streets:
			var seg_len := st.length()
			if seg_len < 12.0:
				continue
			var dir := st.direction()
			var perp := Vector2(-dir.y, dir.x)
			var sp := spacing * (1.0 if st.boundary else 1.5)
			var n := int(floor((seg_len - 8.0) / sp)) + 1
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			for i in n:
				var t := (float(i) + 0.5) / float(n)
				var base := st.a.lerp(st.b, t)
				var off := maxf(st.width * 0.5 - 0.55, 1.0)
				var p := base + perp * side * off
				var this_side := side
				side = -side
				if _blocked(plan, p):
					continue
				lamps.append(Vector3(p.x, 0.0, p.y))
				lamp_dirs.append(-perp * this_side)
	# Quay-side lamps along canals.
	for canal in plan.canals_overlapping(rect):
		var cr := canal.rect
		if canal.is_vertical():
			var zz := maxf(rect.position.y, cr.position.y) + 10.0
			while zz < minf(rect.end.y, cr.end.y) - 4.0:
				for sx: float in [cr.position.x - 1.0, cr.end.x + 1.0]:
					var p := Vector2(sx, zz)
					if rect.has_point(p) and not _blocked_quay(plan, p):
						lamps.append(Vector3(p.x, 0.0, p.y))
						lamp_dirs.append(Vector2(signf(cr.get_center().x - sx), 0.0))
				zz += 24.0
		else:
			var xx := maxf(rect.position.x, cr.position.x) + 10.0
			while xx < minf(rect.end.x, cr.end.x) - 4.0:
				for sz: float in [cr.position.y - 1.0, cr.end.y + 1.0]:
					var p := Vector2(xx, sz)
					if rect.has_point(p) and not _blocked_quay(plan, p):
						lamps.append(Vector3(p.x, 0.0, p.y))
						lamp_dirs.append(Vector2(0.0, signf(cr.get_center().y - sz)))
				xx += 24.0


func _blocked_quay(plan: CityPlan, p: Vector2) -> bool:
	for lm in plan.landmarks:
		if lm.footprint.grow(1.0).has_point(p):
			return true
	for b in bridges:
		if (b["rect"] as Rect2).grow(1.5).has_point(p):
			return true
	return not plan.inside_city(p)


# --- Markers ------------------------------------------------------------------

func _place_markers(plan: CityPlan, seed_value: int) -> void:
	var used: Array[Lot] = []
	# Two passes: lots claimed by exclusive markers first, then shared ones.
	for pass_i in 2:
		for m: Dictionary in plan.markers:
			var pa: Array = m.get("pos", [0, 0])
			var p := Vector2(float(pa[0]), float(pa[1]))
			if not rect.has_point(p):
				continue
			var share := bool(m.get("share", false))
			if (pass_i == 0) == share:
				continue
			_place_marker(m, p, used, seed_value)


func _place_marker(m: Dictionary, p: Vector2, used: Array[Lot], seed_value: int) -> void:
	var group := StringName(str(m.get("group", "")))
	var meta := {}
	# "activity_id"/"collectible_id"/"collectible_kind" back the open-world
	# side-activity and collectible systems (src/mission/activities/); added
	# here, minimally, alongside the existing marker meta keys.
	for key: String in ["objective_id", "enemy_type", "pickup_kind", "activity_id", "collectible_id", "collectible_kind"]:
		if m.has(key):
			meta[key] = StringName(str(m[key]))
	if m.has("checkpoint"):
		meta["checkpoint_id"] = StringName(str(m["checkpoint"]))
	var placement := str(m.get("placement", "street"))
	var pos := Vector3(p.x, 0.05, p.y)
	match placement:
		"rooftop":
			var lot := _nearest_lot(p, used if not bool(m.get("share", false)) else [])
			if lot == null:
				return
			if not bool(m.get("share", false)):
				used.append(lot)
				lot.forced = true
				if m.has("floors"):
					lot.floors = int(m["floors"])
					lot.height = _height_for(lot.floors) + 0.2
				if bool(m.get("flat", false)):
					lot.roof = Roof.FLAT
			var off := Vector2.ZERO
			if m.has("offset"):
				var oa: Array = m["offset"]
				off = Vector2(float(oa[0]), float(oa[1]))
			var cc := lot.center() + off
			pos = Vector3(cc.x, lot.height + 0.15, cc.y)
			if lot.roof != Roof.FLAT:
				pos.y = lot.top() + 0.2
		"lamp":
			var best := -1
			var bd := INF
			for i in lamps.size():
				var d := Vector2(lamps[i].x, lamps[i].z).distance_to(p)
				if d < bd:
					bd = d
					best = i
			if best < 0:
				return
			pos = lamps[best] + Vector3(0.0, 4.3, 0.0)
		"street", "patrol":
			var st := _nearest_street(p)
			if st == null:
				return
			var q := Geometry2D.get_closest_point_to_segment(p, st.a, st.b)
			pos = Vector3(q.x, 0.05, q.y)
			if placement == "patrol":
				var d := st.direction()
				var seg_len := st.length()
				var inset := minf(4.0, seg_len * 0.2)
				var a := st.a + d * inset
				var b := st.b - d * inset
				var patrol := PackedVector3Array([Vector3(a.x, 0.05, a.y), Vector3((a.x + b.x) * 0.5, 0.05, (a.y + b.y) * 0.5), Vector3(b.x, 0.05, b.y)])
				meta["patrol"] = patrol
		_:
			pass
	markers.append({"group": group, "pos": pos, "meta": meta})


func _nearest_lot(p: Vector2, exclude: Array) -> Lot:
	var best: Lot = null
	var bd := INF
	for lot in lots:
		if lot in exclude:
			continue
		var d := lot.center().distance_squared_to(p)
		if d < bd:
			bd = d
			best = lot
	return best


func _nearest_street(p: Vector2) -> Street:
	var best: Street = null
	var bd := INF
	for st in streets:
		var q := Geometry2D.get_closest_point_to_segment(p, st.a, st.b)
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = st
	return best


## True if `p` (XZ) is inside any lot footprint.
func point_in_lot(p: Vector2, margin := 0.0) -> bool:
	for lot in lots:
		if lot.rect.grow(margin).has_point(p):
			return true
	return false


## Deterministic signature of the layout (used by tests).
func signature() -> int:
	var parts: Array = [coord, lots.size(), streets.size(), lamps.size()]
	for lot in lots:
		parts.append(lot.rect)
		parts.append(lot.floors)
		parts.append(lot.roof)
	for m in markers:
		parts.append(m["pos"])
	return hash(parts)
