class_name BuildingBuilder
extends RefCounted
## Turns ChunkLayout lots into merged geometry, colliders, occluders, nav
## source, windows and rooftop metals (thread-safe, data only).

const M := WorldMaterials.Mat
const WIN_SPACING := 2.7
const MODILLION_SPACING := 1.2


## Soot-graded wall colours for a lot: [ground, band, top, roof-top].
static func wall_colors(lot: ChunkLayout.Lot) -> Array[Color]:
	var t := lot.tint
	var col: Color
	match lot.mat:
		ChunkLayout.WallMat.BRICK:
			col = Color(t, t * 0.95, t * 0.92)
		ChunkLayout.WallMat.PLASTER:
			col = Color(t * 1.02, t, t * 0.93)
		_:
			col = Color(t, t * 0.98, t * 0.95)
	return [col * 0.42, col, col * 0.7, col * 0.6]


static func wall_mat(lot: ChunkLayout.Lot) -> int:
	if lot.mat == ChunkLayout.WallMat.BRICK:
		return M.BRICK
	# Merchant/noble stone and render are fine-coursed ashlar (the plaster
	# texture's crack network read as metre-wide cobbles on grand facades);
	# the tint still tells render from stone. Elsewhere: rubble and plaster.
	if bool(lot.style.get("facade_ornament", false)):
		return M.ASHLAR
	return M.PLASTER if lot.mat == ChunkLayout.WallMat.PLASTER else M.STONE


## Emits one building into `data`.
static func build_lot(data: ChunkBuildData, lot: ChunkLayout.Lot) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = lot.lot_seed
	var r := lot.rect
	var h := lot.height
	var cols := wall_colors(lot)
	var wm := wall_mat(lot)
	var walls := data.mb(wm)
	var lo := Vector3(r.position.x, 0.0, r.position.y)
	var hi := Vector3(r.end.x, h, r.end.y)
	# Party walls are kept (not skipped like the trim): each faces into the
	# neighbour, hidden inside it, and shows as a blank firewall where this
	# lot rises above a lower neighbour instead of leaving a hole.
	walls.add_banded_box(lo, hi, 3.2, cols[0], cols[1], cols[2], cols[3], 0, false)
	# Plinth of dark stone.
	var trim := data.mb(M.TRIM)
	var dark := Color(0.5, 0.49, 0.48) * lot.tint
	trim.add_banded_box(lo - Vector3(0.08, 0.0, 0.08), Vector3(hi.x + 0.08, 0.85, hi.z + 0.08), 0.3,
			dark * 0.5, dark * 0.8, dark, dark, lot.shared, true)
	# String courses on stone/plaster houses.
	if lot.mat != ChunkLayout.WallMat.BRICK and rng.randf() < 0.45:
		for f in range(1, lot.floors):
			var y := ChunkLayout.GROUND_FLOOR_H + float(f - 1) * ChunkLayout.FLOOR_H - 0.12
			trim.add_banded_box(Vector3(lo.x - 0.06, y, lo.z - 0.06), Vector3(hi.x + 0.06, y + 0.16, hi.z + 0.06),
					y + 0.08, dark * 0.8, dark, dark, dark, lot.shared, true)
	data.add_box_shape_lohi(lo, hi)
	data.add_occluder_box(lo + Vector3(0.2, 0.0, 0.2), hi - Vector3(0.2, 0.3, 0.2))
	data.add_nav_box(lo, hi, lot.roof == ChunkLayout.Roof.FLAT)
	data.add_nav_obstruction(r, -1.0, h - 0.5)
	_windows(data, lot, rng, cols)
	if bool(lot.style.get("facade_ornament", false)):
		# Own RNG: must not shift the draws the roof furniture below makes.
		var orng := RandomNumberGenerator.new()
		orng.seed = lot.lot_seed ^ 0x0A4E
		_facade_ornament(data, lot, orng, dark)
	if lot.roof == ChunkLayout.Roof.FLAT:
		_flat_roof(data, lot, rng, cols)
	else:
		_gable_roof(data, lot, rng, cols)


static func _face_frame(r: Rect2, bit: int) -> Array:
	# [origin (bottom-left at ground), right vector, normal, length]
	match bit:
		ChunkLayout.FACE_S:
			return [Vector3(r.position.x, 0, r.end.y), Vector3.RIGHT, Vector3.BACK, r.size.x]
		ChunkLayout.FACE_N:
			return [Vector3(r.end.x, 0, r.position.y), Vector3.LEFT, Vector3.FORWARD, r.size.x]
		ChunkLayout.FACE_E:
			return [Vector3(r.end.x, 0, r.end.y), Vector3.FORWARD, Vector3.RIGHT, r.size.y]
	return [Vector3(r.position.x, 0, r.position.y), Vector3.BACK, Vector3.LEFT, r.size.y]


static func _windows(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator, cols: Array[Color]) -> void:
	var st := lot.style
	var lit_p := float(st.get("lit", 0.15))
	var bars_p := float(st.get("bars", 0.08))
	var lantern_p := float(st.get("wall_lantern", 0.06))
	var win := data.db(M.WINDOW)
	var wood := data.db(M.WOOD)
	var ornate := bool(st.get("facade_ornament", false))
	for bit: int in [ChunkLayout.FACE_S, ChunkLayout.FACE_N, ChunkLayout.FACE_E, ChunkLayout.FACE_W]:
		if lot.shared & bit:
			continue
		var fr := _face_frame(lot.rect, bit)
		var o: Vector3 = fr[0]
		var rv: Vector3 = fr[1]
		var n: Vector3 = fr[2]
		var length: float = fr[3]
		var count := int(floor((length - 1.0) / WIN_SPACING))
		if count < 1:
			continue
		var spacing := length / float(count)
		var door_slot := rng.randi_range(0, count - 1) if bit == lot.front else -1
		# Whole-facade "character": some houses are dark, some busy.
		var facade_lit := lit_p * rng.randf_range(0.3, 1.8)
		for f in lot.floors:
			var y0 := 0.95 if f == 0 else ChunkLayout.GROUND_FLOOR_H + float(f - 1) * ChunkLayout.FLOOR_H + 0.8
			var wh := 1.75 if f == 0 else 1.6
			var ww := 1.1 if f == 0 else 1.0
			if y0 + wh > lot.height - 0.3:
				continue
			for i in count:
				var u := (float(i) + 0.5) * spacing
				if f == 0 and i == door_slot:
					var d0 := o + rv * (u - 0.7) + n * 0.06
					var d1 := o + rv * (u + 0.7) + n * 0.06
					wood.add_quad(d0, d1, d1 + Vector3.UP * 2.5, d0 + Vector3.UP * 2.5, n,
							Color(0.5, 0.5, 0.5), Color(0.75, 0.75, 0.75))
					data.add_instance(&"door_surround", Transform3D(Basis(rv, Vector3.UP, n), o + rv * u))
					if rng.randf() < lantern_p * 3.0:
						var lp := o + rv * (u + 1.05) + n * 0.42 + Vector3.UP * 2.9
						data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(-n), lp))
						data.add_metal(lp + Vector3.UP * 0.35, 4.0)
						data.add_light(lp, Color(1.0, 0.6, 0.28), 9.0, 2.6)
					continue
				var p0 := o + rv * (u - ww * 0.5) + n * 0.04 + Vector3.UP * y0
				var p1 := o + rv * (u + ww * 0.5) + n * 0.04 + Vector3.UP * y0
				var lit := 0.0
				if rng.randf() < facade_lit:
					lit = rng.randf_range(0.55, 1.0)
				var shutter := 1.0 if rng.randf() < 0.22 else 0.0
				var c := Color(lit, rng.randf(), shutter, 1.0)
				win.add_quad(p0, p1, p1 + Vector3.UP * wh, p0 + Vector3.UP * wh, n, c, c)
				# Stone architrave (ornamented districts) or a timber frame.
				var frame: StringName = &"window_surround" if ornate else &"window_frame_wood"
				if f == 0:
					frame = StringName(String(frame) + "_g")
				data.add_instance(frame, Transform3D(Basis(rv, Vector3.UP, n), o + rv * u + Vector3.UP * y0))
				if f == 0 and rng.randf() < bars_p:
					var center := o + rv * u + n * 0.14 + Vector3.UP * (y0 + wh * 0.5)
					var bx := Basis(rv * (ww + 0.1), Vector3.UP * (wh + 0.1), n)
					data.add_instance(&"window_bars", Transform3D(bx, center))
					data.add_metal(center, 12.0)
			# Occasional wall lantern on long blank facades at first floor.
		if bit == lot.front and door_slot < 0 and rng.randf() < lantern_p:
			var lp2 := o + rv * (length * 0.5) + n * 0.42 + Vector3.UP * 3.1
			data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(-n), lp2))
			data.add_metal(lp2 + Vector3.UP * 0.35, 4.0)
			data.add_light(lp2, Color(1.0, 0.6, 0.28), 9.0, 2.6)


## Merchant/noble facade dressing: vertical pilaster strips between windows,
## and a balcony with an iron railing (itself a Push/Pull anchor) on an upper
## floor of the front face. Gated by the district style's `facade_ornament`
## flag so the skaa quarter and docks keep their plainer look.
static func _facade_ornament(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator, dark: Color) -> void:
	var trim := data.mb(M.TRIM)
	for bit: int in [ChunkLayout.FACE_S, ChunkLayout.FACE_N, ChunkLayout.FACE_E, ChunkLayout.FACE_W]:
		if lot.shared & bit:
			continue
		var fr := _face_frame(lot.rect, bit)
		var o: Vector3 = fr[0]
		var rv: Vector3 = fr[1]
		var n: Vector3 = fr[2]
		var length: float = fr[3]
		# Pilasters: slim raised piers at roughly one-window intervals.
		var count := int(floor(length / WIN_SPACING))
		if count < 2:
			continue
		var spacing := length / float(count)
		var top_y := lot.height - 0.2
		var cb := dark * 0.75
		var ct := dark * 0.85
		for i in range(1, count):
			# Only the three faces that can be seen (the back sits on the wall,
			# the top under the cornice): 40 % fewer quads than a full box.
			var p := o + rv * (spacing * float(i)) + n * 0.11
			var l := p - rv * 0.09
			var r := p + rv * 0.09
			var lb := l - n * 0.12
			var rb := r - n * 0.12
			trim.add_quad(l, r, r + Vector3.UP * top_y, l + Vector3.UP * top_y, n, cb, ct)
			trim.add_quad(r, rb, rb + Vector3.UP * top_y, r + Vector3.UP * top_y, rv, cb, ct)
			trim.add_quad(lb, l, l + Vector3.UP * top_y, lb + Vector3.UP * top_y, -rv, cb, ct)
		# One balcony, front face only, second floor if there is one.
		if bit == lot.front and lot.floors >= 2 and rng.randf() < 0.7:
			var y := ChunkLayout.GROUND_FLOOR_H + 0.05
			var bp := o + rv * (length * 0.5) + n * 0.02 + Vector3.UP * y
			var bx := Basis(rv, Vector3.UP, n)
			data.add_instance(&"balcony", Transform3D(bx, bp))
			data.add_metal(bp + n * 0.76 + Vector3.UP * 0.45, 10.0)
	_cornice(data, lot, dark)
	_shop_sign(data, lot, rng)


const SHOP_SIGNS: Array[StringName] = [&"shop_sign_board", &"shop_sign_medallion", &"shop_sign_coin"]


## A hanging trade sign over a merchant shopfront (style key `shop_signs` is
## the share of lots that get one): on the front face, at the pier between
## the first two ground-floor window slots, above the window heads (2.7 m)
## and below the first-floor sills (4.4 m), never under the balcony or
## against a door lantern. Purely visual, no collision: it
## hangs from 3.45 m down to ~2.75 m, over the pavement, never into a street
## the player runs at head height.
static func _shop_sign(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator) -> void:
	var share := float(lot.style.get("shop_signs", 0.0))
	# Always draw both, so the share never shifts which sign a lot gets.
	var roll := rng.randf()
	var pick := rng.randi_range(0, SHOP_SIGNS.size() - 1)
	if roll >= share or lot.shared & lot.front:
		return
	var fr := _face_frame(lot.rect, lot.front)
	var length: float = fr[3]
	var count := int(floor((length - 1.0) / WIN_SPACING))
	if count < 2:
		return
	var o: Vector3 = fr[0]
	var rv: Vector3 = fr[1]
	var n: Vector3 = fr[2]
	var spacing := length / float(count)
	# Left or right end pier, so neighbouring shops don't all line up; the
	# other end if that one is taken by the balcony (centred on the face,
	# its slab at 3.5 m) or a door lantern (2.9 m, 1.05 m beside the door),
	# none if both are. A quarter of signs used to hang into one of them.
	var ends := [spacing, length - spacing] if pick != 1 else [length - spacing, spacing]
	for u: float in ends:
		var p := o + rv * u + Vector3.UP * 3.45
		if _sign_spot_clear(data, p):
			data.add_instance(SHOP_SIGNS[pick], Transform3D(Basis(rv, Vector3.UP, n), p))
			return


## True if no balcony or wall lantern hangs where a shop sign at `p` would.
static func _sign_spot_clear(data: ChunkBuildData, p: Vector3) -> bool:
	for kc: Array in [[&"balcony", 1.45], [&"wall_lantern", 1.1]]:
		var r: float = kc[1]
		for xf: Transform3D in data.instances.get(kc[0], []):
			var q := xf.origin
			if absf(q.y - p.y) < 1.2 and Vector2(q.x - p.x, q.z - p.z).length() < r:
				return false
	return true


## Merchant/noble cornice: a plain frieze band and a deep, projecting crown
## moulding (with its soffit, which is what reads from the street) along the
## eaves. It only projects from free faces, never into a party wall, and it is
## purely visual (no collision), so traversal is unchanged.
static func _cornice(data: ChunkBuildData, lot: ChunkLayout.Lot, dark: Color) -> void:
	var r := lot.rect
	var h := lot.height
	var flat := lot.roof == ChunkLayout.Roof.FLAT
	# A bold crown (0.45 m tall, 1.1 m deep): on flat roofs it laps the
	# parapet's foot; on gables it swallows the plain eaves band.
	var crown_hi := h + 0.1 if flat else h
	var crown_lo := crown_hi - 0.45
	# Stay clear of the top floor's window heads.
	var win_top := ChunkLayout.GROUND_FLOOR_H + float(lot.floors - 2) * ChunkLayout.FLOOR_H + 0.8 + 1.6
	if lot.floors < 2:
		win_top = 0.95 + 1.75
	var frieze_lo := maxf(crown_lo - 0.4, win_top + 0.06)
	if crown_lo - frieze_lo < 0.08 or crown_lo < win_top:
		return
	var trim := data.mb(M.TRIM)
	var sh := lot.shared
	var grow := func(d: float) -> Array:
		# Grow only on free faces (bits: 1 = +Z/S, 2 = -Z/N, 4 = +X/E, 8 = -X/W).
		var lo := Vector2(r.position.x - (0.0 if sh & ChunkLayout.FACE_W else d), r.position.y - (0.0 if sh & ChunkLayout.FACE_N else d))
		var hi := Vector2(r.end.x + (0.0 if sh & ChunkLayout.FACE_E else d), r.end.y + (0.0 if sh & ChunkLayout.FACE_S else d))
		return [lo, hi]
	# Pale dressed stone (ashlar material, light vertex colour), so the cornice
	# reads as a bright moulding against the sooty wall rather than a dark
	# line: a frieze, a bed moulding and a deep corona (1.1 m) whose shaded
	# soffit gives the strong shadow line under the eaves.
	var stone := data.mb(M.ASHLAR)
	var pale := Color(0.95, 0.92, 0.86) * clampf(0.75 + lot.tint * 0.35, 0.8, 1.05)
	var f: Array = grow.call(0.12)
	stone.add_banded_box(Vector3(f[0].x, frieze_lo, f[0].y), Vector3(f[1].x, crown_lo, f[1].y), crown_lo,
			pale * 0.7, pale * 0.85, pale * 0.85, pale, sh, false)
	var bed_hi := crown_lo + 0.14
	var b: Array = grow.call(0.38)
	stone.add_banded_box(Vector3(b[0].x, crown_lo, b[0].y), Vector3(b[1].x, bed_hi, b[1].y), bed_hi,
			pale * 0.75, pale * 0.9, pale * 0.9, pale, sh, false)
	trim.add_quad(Vector3(b[0].x, crown_lo, b[0].y), Vector3(b[1].x, crown_lo, b[0].y), Vector3(b[1].x, crown_lo, b[1].y),
			Vector3(b[0].x, crown_lo, b[1].y), Vector3.DOWN, dark * 0.5, dark * 0.5)
	var c: Array = grow.call(1.1)
	var lo := Vector3(c[0].x, bed_hi, c[0].y)
	var hi := Vector3(c[1].x, crown_hi, c[1].y)
	stone.add_banded_box(lo, hi, bed_hi + 0.1, pale * 0.85, pale, pale, pale * 0.9, sh, true)
	# Soffit: the underside of the corona, seen from the street.
	trim.add_quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z),
			Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, dark * 0.45, dark * 0.45)
	# Modillions: a row of stone brackets carrying the corona on every free
	# face (one shared MultiMesh per chunk), which turns the slab into a
	# classical cornice with a rhythm of light and shadow under the eaves.
	for bit: int in [ChunkLayout.FACE_S, ChunkLayout.FACE_N, ChunkLayout.FACE_E, ChunkLayout.FACE_W]:
		if sh & bit:
			continue
		var fr := _face_frame(r, bit)
		var length: float = fr[3]
		var k := int(floor((length - 0.6) / MODILLION_SPACING))
		if k < 1:
			continue
		var step := (length - 0.6) / float(k)
		var fo: Vector3 = fr[0]
		var rv: Vector3 = fr[1]
		var bx := Basis(rv, Vector3.UP, fr[2])
		for i in k + 1:
			data.add_instance(&"modillion", Transform3D(bx, fo + rv * (0.3 + step * float(i)) + Vector3.UP * bed_hi))


static func _chimney(data: ChunkBuildData, rng: RandomNumberGenerator, x: float, z: float,
		base_y: float, top_y: float, lot: ChunkLayout.Lot) -> void:
	var c := Color(0.3, 0.27, 0.25) * (0.6 + lot.tint * 0.5)
	var lo := Vector3(x - 0.45, base_y, z - 0.35)
	var hi := Vector3(x + 0.45, top_y, z + 0.35)
	data.mb(M.BRICK).add_banded_box(lo, hi, top_y - 0.6, c, c, c * 0.35, c * 0.2, 0, false)
	data.mb(M.TRIM).add_box(Vector3(lo.x - 0.1, top_y, lo.z - 0.1), Vector3(hi.x + 0.1, top_y + 0.14, hi.z + 0.1),
			c * 0.5, c * 0.4, c * 0.25)
	data.add_box_shape_lohi(lo, Vector3(hi.x, top_y + 0.14, hi.z))
	var metal_p := 0.2 * float(lot.style.get("roof_metal", 1.0))
	if rng.randf() < metal_p:
		var cap := Vector3(x, top_y + 0.14, z)
		data.add_instance(&"chimney_cap", Transform3D(Basis(), cap))
		data.add_metal(cap + Vector3.UP * 0.3, 8.0)


static func _flat_roof(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator, cols: Array[Color]) -> void:
	var r := lot.rect
	var h := lot.height
	var rc := Color(0.55, 0.55, 0.57) * (0.7 + lot.tint * 0.4)
	data.mb(M.ROOF_FLAT).add_quad(Vector3(r.position.x, h + 0.02, r.end.y), Vector3(r.end.x, h + 0.02, r.end.y),
			Vector3(r.end.x, h + 0.02, r.position.y), Vector3(r.position.x, h + 0.02, r.position.y), Vector3.UP, rc, rc)
	# Parapet.
	var wm := wall_mat(lot)
	var pt := 0.3
	var ph := 0.75
	var walls := data.mb(wm)
	var c := cols[2]
	var boxes := [
		[Vector3(r.position.x, h, r.position.y), Vector3(r.end.x, h + ph, r.position.y + pt)],
		[Vector3(r.position.x, h, r.end.y - pt), Vector3(r.end.x, h + ph, r.end.y)],
		[Vector3(r.position.x, h, r.position.y + pt), Vector3(r.position.x + pt, h + ph, r.end.y - pt)],
		[Vector3(r.end.x - pt, h, r.position.y + pt), Vector3(r.end.x, h + ph, r.end.y - pt)],
	]
	# coping: a pale stone cap overhanging the parapet by 5 cm (visual only;
	# the collider stays the parapet's own box)
	var cope := data.mb(M.ASHLAR)
	var cc := Color(0.8, 0.77, 0.72) * clampf(0.7 + lot.tint * 0.35, 0.75, 1.0)
	for b: Array in boxes:
		walls.add_box(b[0], b[1], c, c * 0.8, cols[3])
		data.add_box_shape_lohi(b[0], b[1])
		var lo: Vector3 = b[0]
		var hi: Vector3 = b[1]
		cope.add_box(Vector3(lo.x - 0.05, hi.y, lo.z - 0.05), Vector3(hi.x + 0.05, hi.y + 0.08, hi.z + 0.05),
				cc * 0.8, cc * 0.9, cc, true)
	# Chimneys.
	var cr: Array = lot.style.get("chimneys", [1, 2])
	var n := rng.randi_range(int(cr[0]), int(cr[1]))
	for i in n:
		var x := rng.randf_range(r.position.x + 1.2, r.end.x - 1.2)
		var z := rng.randf_range(r.position.y + 1.2, r.end.y - 1.2)
		_chimney(data, rng, x, z, h, h + rng.randf_range(1.2, 2.3), lot)
	var metal_scale := float(lot.style.get("roof_metal", 1.0))
	if rng.randf() < 0.18 * metal_scale:
		var p := Vector3(r.position.x + 0.8, h, r.position.y + 0.8)
		if rng.randf() < 0.5:
			p = Vector3(r.end.x - 0.8, h, r.end.y - 0.8)
		data.add_instance(&"weathervane", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		data.add_metal(p + Vector3.UP * 1.5, 12.0)
	if lot.floors >= 5 and rng.randf() < 0.45 * metal_scale:
		var p2 := Vector3(r.get_center().x, h, r.get_center().y)
		data.add_instance(&"lightning_rod", Transform3D(Basis(), p2))
		data.add_metal(p2 + Vector3.UP * 3.0, 6.0)
	# Hatch.
	if rng.randf() < 0.35:
		var hx := rng.randf_range(r.position.x + 1.5, r.end.x - 2.5)
		var hz := rng.randf_range(r.position.y + 1.5, r.end.y - 2.5)
		data.db(M.WOOD).add_box(Vector3(hx, h, hz), Vector3(hx + 1.0, h + 0.35, hz + 1.0),
				Color(0.4, 0.4, 0.4), Color(0.5, 0.5, 0.5), Color(0.55, 0.55, 0.55))
	# Loose crates on some roofs (Push targets for the player).
	if rng.randf() < 0.14 and r.size.x > 5.0 and r.size.y > 5.0:
		var cp := Vector3(rng.randf_range(r.position.x + 1.5, r.end.x - 1.5), h + 0.45,
				rng.randf_range(r.position.y + 1.5, r.end.y - 1.5))
		data.add_rigid(&"crate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp))


## Gable roof trim (purely visual): a ridge cap of rounded tiles, timber
## fascia boards with a soffit along both eaves, and barge boards up the
## verges on the free gable ends, so the slate slabs read as a built roof
## with thickness instead of two paper planes.
static func _roof_trim(data: ChunkBuildData, lot: ChunkLayout.Lot, rise: float, along_x: bool, ov: float,
		sc: Color) -> void:
	var r := lot.rect
	var h := lot.height
	var ry := h + rise
	var wood := data.mb(M.WOOD)
	var cap := data.mb(M.TRIM)
	var fc := Color(0.42, 0.4, 0.38) * (0.7 + lot.tint * 0.4)
	var cc := sc * 0.55
	# Work in a frame where the ridge runs along `u` (x or z) and the slopes
	# fall along `v`.
	var u0 := (r.position.x if along_x else r.position.y) - ov * 0.5
	var u1 := (r.end.x if along_x else r.end.y) + ov * 0.5
	var vm := (r.get_center().y if along_x else r.get_center().x)
	var half := (r.size.y if along_x else r.size.x) * 0.5
	var drop := rise * ov / maxf(half, 0.1)
	var pt := func(u: float, y: float, v: float) -> Vector3:
		return Vector3(u, y, v) if along_x else Vector3(v, y, u)
	var U := Vector3.RIGHT if along_x else Vector3.BACK
	var V := Vector3.BACK if along_x else Vector3.RIGHT
	# ridge cap: a low ridge of rounded tiles (three faces)
	var cw := 0.16
	var ch := 0.13
	cap.add_quad(pt.call(u0, ry + ch, vm - cw * 0.5), pt.call(u1, ry + ch, vm - cw * 0.5),
			pt.call(u1, ry + ch, vm + cw * 0.5), pt.call(u0, ry + ch, vm + cw * 0.5), Vector3.UP, cc, cc)
	for sgn: float in [-1.0, 1.0]:
		var a: Vector3 = pt.call(u0, ry - 0.04, vm + sgn * cw * 1.2)
		var b: Vector3 = pt.call(u1, ry - 0.04, vm + sgn * cw * 1.2)
		var c: Vector3 = pt.call(u1, ry + ch, vm + sgn * cw * 0.5)
		var d: Vector3 = pt.call(u0, ry + ch, vm + sgn * cw * 0.5)
		var nrm := (V * sgn + Vector3.UP).normalized()
		if sgn > 0:
			cap.add_quad(a, b, c, d, nrm, cc * 0.8, cc)
		else:
			cap.add_quad(b, a, d, c, nrm, cc * 0.8, cc)
	# fascia + soffit along both eaves
	for sgn: float in [-1.0, 1.0]:
		var ve := vm + sgn * (half + ov)
		var ye := h - drop
		var top_a: Vector3 = pt.call(u0, ye + 0.02, ve)
		var top_b: Vector3 = pt.call(u1, ye + 0.02, ve)
		var bot_a: Vector3 = pt.call(u0, ye - 0.22, ve)
		var bot_b: Vector3 = pt.call(u1, ye - 0.22, ve)
		var out := V * sgn
		if sgn > 0:
			wood.add_quad(bot_a, bot_b, top_b, top_a, out, fc * 0.8, fc)
		else:
			wood.add_quad(bot_b, bot_a, top_a, top_b, out, fc * 0.8, fc)
		# iron gutter along the fascia, and a downpipe at one end
		var iron := data.mb(M.IRON)
		var gc := Color(0.35, 0.33, 0.31)
		var g0: Vector3 = pt.call(u0, ye - 0.2, ve + sgn * 0.02)
		var g1: Vector3 = pt.call(u1, ye - 0.06, ve + sgn * 0.12)
		iron.add_box(Vector3(minf(g0.x, g1.x), g0.y, minf(g0.z, g1.z)), Vector3(maxf(g0.x, g1.x), g1.y, maxf(g0.z, g1.z)),
				gc * 0.7, gc, gc * 0.8, true)
		var dp: Vector3 = pt.call(u0 + 0.35, 0.0, vm + sgn * (half + 0.08))
		iron.add_box(dp - Vector3(0.045, 0.0, 0.045), dp + Vector3(0.045, ye - 0.2, 0.045), gc * 0.7, gc, gc, true)
		var wall_a: Vector3 = pt.call(u0, h - 0.22, vm + sgn * half)
		var wall_b: Vector3 = pt.call(u1, h - 0.22, vm + sgn * half)
		wood.add_quad(bot_a, bot_b, wall_b, wall_a, Vector3.DOWN, fc * 0.45, fc * 0.45)
	# barge boards up the verges of free gable ends
	for end: int in [0, 1]:
		var bit: int
		if along_x:
			bit = ChunkLayout.FACE_W if end == 0 else ChunkLayout.FACE_E
		else:
			bit = ChunkLayout.FACE_N if end == 0 else ChunkLayout.FACE_S
		if lot.shared & bit:
			continue
		var ue := u0 if end == 0 else u1
		var out_u := -U if end == 0 else U
		for sgn: float in [-1.0, 1.0]:
			var e0: Vector3 = pt.call(ue, h - drop + 0.02, vm + sgn * (half + ov))
			var e1: Vector3 = pt.call(ue, ry + 0.02, vm)
			var down := Vector3.DOWN * 0.24
			if (sgn > 0) == (end == 1):
				wood.add_quad(e0 + down, e1 + down, e1, e0, out_u, fc * 0.75, fc)
			else:
				wood.add_quad(e1 + down, e0 + down, e0, e1, out_u, fc * 0.75, fc)


## Dormers: small gabled window boxes standing out of the slopes of
## taller gable roofs, a row per slope, clear of the chimneys and the gable
## ends. Each is a wall-material box whose back buries itself in the roof,
## a slate mini-gable on top and a lit-or-dark attic window in front.
static func _dormers(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator, rise: float,
		along_x: bool, sc: Color, cols: Array[Color], chim_u: Array[float]) -> void:
	if rise < 2.2 or rng.randf() > float(lot.style.get("dormers", 0.55)):
		return
	var r := lot.rect
	var h := lot.height
	var u_lo := r.position.x if along_x else r.position.y
	var u_hi := r.end.x if along_x else r.end.y
	var vm := r.get_center().y if along_x else r.get_center().x
	var half := (r.size.y if along_x else r.size.x) * 0.5
	var count := mini(int(floor((u_hi - u_lo - 2.0) / 3.4)), 3)
	if count < 1:
		return
	var pt := func(u: float, y: float, v: float) -> Vector3:
		return Vector3(u, y, v) if along_x else Vector3(v, y, u)
	var U := Vector3.RIGHT if along_x else Vector3.BACK
	var V := Vector3.BACK if along_x else Vector3.RIGHT
	var w := 1.5
	var wall_h := clampf(rise * 0.45, 1.0, 1.6)
	var mini_rise := clampf(rise * 0.16, 0.4, 0.6)
	var roof_y := func(d: float) -> float: return h + rise * (1.0 - d / half)
	var d_f := half * 0.8
	var y_b: float = roof_y.call(d_f) - 0.1
	var y_t := y_b + wall_h
	# back far enough that the mini-gable's rear triangle is under the slates
	var d_b := half * (1.0 - (y_t + mini_rise + 0.15 - h) / rise)
	if d_b < 0.2:
		return
	var walls := data.mb(wall_mat(lot))
	var wc := cols[2]
	var lit_p := float(lot.style.get("lit", 0.15)) * 0.8
	var win := data.db(M.WINDOW)
	var spacing := (u_hi - u_lo) / float(count)
	for sgn: float in [-1.0, 1.0]:
		if rng.randf() < 0.3:
			continue
		for i in count:
			var uc := u_lo + (float(i) + 0.5) * spacing
			var blocked := false
			for cu: float in chim_u:
				if absf(cu - uc) < w * 0.5 + 0.9:
					blocked = true
			if blocked:
				continue
			var a: Vector3 = pt.call(uc - w * 0.5, y_b, vm + sgn * d_b)
			var b: Vector3 = pt.call(uc + w * 0.5, y_t, vm + sgn * d_f)
			var lo := Vector3(minf(a.x, b.x), y_b, minf(a.z, b.z))
			var hi := Vector3(maxf(a.x, b.x), y_t, maxf(a.z, b.z))
			walls.add_box(lo, hi, wc * 0.85, wc, wc)
			data.add_box_shape_lohi(lo, hi)
			data.mb(M.SLATE).add_gable_roof(Vector2(lo.x, lo.z), Vector2(hi.x, hi.z), y_t, mini_rise,
					not along_x, 0.25, sc, walls, wc * 0.85)
			# attic window, with a scaled-down timber frame
			var n := V * sgn
			var rv := U * sgn
			var ww := 0.8
			var wh := wall_h - 0.55
			var y0 := y_b + 0.32
			var fc: Vector3 = pt.call(uc, 0.0, vm + sgn * d_f)
			var p0 := fc - rv * ww * 0.5 + n * 0.04 + Vector3.UP * y0
			var p1 := fc + rv * ww * 0.5 + n * 0.04 + Vector3.UP * y0
			var lit := rng.randf_range(0.5, 0.9) if rng.randf() < lit_p else 0.0
			var c := Color(lit, rng.randf(), 0.0, 1.0)
			win.add_quad(p0, p1, p1 + Vector3.UP * wh, p0 + Vector3.UP * wh, n, c, c)
			data.add_instance(&"window_frame_wood",
					Transform3D(Basis(rv * (ww / 1.0), Vector3.UP * (wh / 1.6), n), fc + Vector3.UP * y0))


static func _gable_roof(data: ChunkBuildData, lot: ChunkLayout.Lot, rng: RandomNumberGenerator, cols: Array[Color]) -> void:
	var r := lot.rect
	var h := lot.height
	var rise := lot.roof_rise()
	var along_x := lot.roof == ChunkLayout.Roof.GABLE_X
	var sc := Color(0.85, 0.87, 0.9) * rng.randf_range(0.65, 1.05)
	var walls := data.mb(wall_mat(lot))
	# Cornice.
	var dark := Color(0.5, 0.49, 0.48) * lot.tint
	data.mb(M.TRIM).add_banded_box(Vector3(r.position.x - 0.15, h - 0.35, r.position.y - 0.15),
			Vector3(r.end.x + 0.15, h, r.end.y + 0.15), h - 0.2, dark * 0.6, dark * 0.7, dark * 0.6, dark * 0.5, lot.shared, false)
	data.mb(M.SLATE).add_gable_roof(r.position, r.end, h, rise, along_x, 0.4, sc, walls, cols[2] * 0.85)
	_roof_trim(data, lot, rise, along_x, 0.4, sc)
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var pts := PackedVector3Array([Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)])
	if along_x:
		var zm := (z0 + z1) * 0.5
		pts.append(Vector3(x0, h + rise, zm))
		pts.append(Vector3(x1, h + rise, zm))
	else:
		var xm := (x0 + x1) * 0.5
		pts.append(Vector3(xm, h + rise, z0))
		pts.append(Vector3(xm, h + rise, z1))
	data.add_convex_shape(pts)
	# Chimneys on the ridge line.
	var cr: Array = lot.style.get("chimneys", [1, 2])
	var n := rng.randi_range(int(cr[0]), int(cr[1]))
	var chim_u: Array[float] = []
	for i in n:
		var t := rng.randf_range(0.12, 0.88)
		if i == 0 and n > 1:
			t = 0.1
		var x: float
		var z: float
		var side := rng.randf_range(-0.25, 0.25)
		if along_x:
			x = lerpf(x0 + 0.8, x1 - 0.8, t)
			z = (z0 + z1) * 0.5 + side * (z1 - z0) * 0.5
		else:
			z = lerpf(z0 + 0.8, z1 - 0.8, t)
			x = (x0 + x1) * 0.5 + side * (x1 - x0) * 0.5
		_chimney(data, rng, x, z, h + rise * 0.3, h + rise + rng.randf_range(0.5, 1.6), lot)
		chim_u.append(x if along_x else z)
	# Own RNG: must not shift the roof-furniture draws (metal anchors).
	var drng := RandomNumberGenerator.new()
	drng.seed = lot.lot_seed ^ 0x0D07
	_dormers(data, lot, drng, rise, along_x, sc, cols, chim_u)
	var metal_scale := float(lot.style.get("roof_metal", 1.0))
	if rng.randf() < 0.18 * metal_scale:
		var p: Vector3
		if along_x:
			p = Vector3(x0 + 0.4 if rng.randf() < 0.5 else x1 - 0.4, h + rise, (z0 + z1) * 0.5)
		else:
			p = Vector3((x0 + x1) * 0.5, h + rise, z0 + 0.4 if rng.randf() < 0.5 else z1 - 0.4)
		data.add_instance(&"weathervane", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		data.add_metal(p + Vector3.UP * 1.5, 12.0)
	if lot.floors >= 5 and rng.randf() < 0.4 * metal_scale:
		var p2 := Vector3((x0 + x1) * 0.5, h + rise, (z0 + z1) * 0.5)
		data.add_instance(&"lightning_rod", Transform3D(Basis(), p2))
		data.add_metal(p2 + Vector3.UP * 3.0, 6.0)
