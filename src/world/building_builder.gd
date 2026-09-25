class_name BuildingBuilder
extends RefCounted
## Turns ChunkLayout lots into merged geometry, colliders, occluders, nav
## source, windows and rooftop metals (thread-safe, data only).

const M := WorldMaterials.Mat
const WIN_SPACING := 2.7


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
	match lot.mat:
		ChunkLayout.WallMat.BRICK:
			return M.BRICK
		ChunkLayout.WallMat.PLASTER:
			return M.PLASTER
	return M.STONE


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
	walls.add_banded_box(lo, hi, 3.2, cols[0], cols[1], cols[2], cols[3], lot.shared, false)
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
					if rng.randf() < lantern_p * 3.0:
						var lp := o + rv * (u + 1.05) + n * 0.42 + Vector3.UP * 2.9
						data.add_instance(&"wall_lantern", Transform3D(Basis.looking_at(-n), lp))
						data.add_metal(lp + Vector3.UP * 0.35, 4.0)
						data.add_light(lp, Color(1.0, 0.6, 0.28), 7.0, 1.6)
					continue
				var p0 := o + rv * (u - ww * 0.5) + n * 0.04 + Vector3.UP * y0
				var p1 := o + rv * (u + ww * 0.5) + n * 0.04 + Vector3.UP * y0
				var lit := 0.0
				if rng.randf() < facade_lit:
					lit = rng.randf_range(0.55, 1.0)
				var shutter := 1.0 if rng.randf() < 0.22 else 0.0
				var c := Color(lit, rng.randf(), shutter, 1.0)
				win.add_quad(p0, p1, p1 + Vector3.UP * wh, p0 + Vector3.UP * wh, n, c, c)
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
			data.add_light(lp2, Color(1.0, 0.6, 0.28), 7.0, 1.6)


static func _chimney(data: ChunkBuildData, rng: RandomNumberGenerator, x: float, z: float,
		base_y: float, top_y: float, lot: ChunkLayout.Lot) -> void:
	var c := Color(0.3, 0.27, 0.25) * (0.6 + lot.tint * 0.5)
	var lo := Vector3(x - 0.45, base_y, z - 0.35)
	var hi := Vector3(x + 0.45, top_y, z + 0.35)
	data.mb(M.BRICK).add_banded_box(lo, hi, top_y - 0.6, c, c, c * 0.35, c * 0.2, 0, false)
	data.mb(M.TRIM).add_box(Vector3(lo.x - 0.1, top_y, lo.z - 0.1), Vector3(hi.x + 0.1, top_y + 0.14, hi.z + 0.1),
			c * 0.5, c * 0.4, c * 0.25)
	data.add_box_shape_lohi(lo, Vector3(hi.x, top_y + 0.14, hi.z))
	var metal_p := 0.33 * float(lot.style.get("roof_metal", 1.0))
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
	for b: Array in boxes:
		walls.add_box(b[0], b[1], c, c * 0.8, cols[3])
		data.add_box_shape_lohi(b[0], b[1])
	# Chimneys.
	var cr: Array = lot.style.get("chimneys", [1, 2])
	var n := rng.randi_range(int(cr[0]), int(cr[1]))
	for i in n:
		var x := rng.randf_range(r.position.x + 1.2, r.end.x - 1.2)
		var z := rng.randf_range(r.position.y + 1.2, r.end.y - 1.2)
		_chimney(data, rng, x, z, h, h + rng.randf_range(1.2, 2.3), lot)
	var metal_scale := float(lot.style.get("roof_metal", 1.0))
	if rng.randf() < 0.24 * metal_scale:
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
	var metal_scale := float(lot.style.get("roof_metal", 1.0))
	if rng.randf() < 0.22 * metal_scale:
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
	# Dormer-ish roof lantern glow: skipped for cost; windows carry the light.
