class_name CityWallBuilder
extends RefCounted
## The great city wall: the plan's ring polygon, clipped per chunk into
## oriented wall boxes with crenellations, plus towers at the ring vertices.

const M := WorldMaterials.Mat


static func build(data: ChunkBuildData, plan: CityPlan, rect: Rect2) -> void:
	var h := plan.wall_height
	var t := plan.wall_thickness
	var stone := data.mb(M.KEEP_STONE)
	var merlons := data.db(M.KEEP_STONE)
	var c := Color(0.42, 0.41, 0.4)
	for seg in plan.wall_segments_in(rect):
		var a := seg[0]
		var b := seg[1]
		var d := b - a
		var seg_len := d.length()
		if seg_len < 0.5:
			continue
		var yaw := atan2(-d.y, d.x)
		var mid := (a + b) * 0.5
		stone.add_obox(Vector3(mid.x, h * 0.5, mid.y), Vector3(seg_len * 0.5 + 0.2, h * 0.5, t * 0.5), yaw, c * 0.45, c)
		data.add_box_shape(Vector3(mid.x, h * 0.5, mid.y), Vector3(seg_len + 0.4, h, t), yaw)
		# Crenellations along both edges of the wall walk.
		var dn := d / seg_len
		var perp := Vector2(-dn.y, dn.x)
		var n := int(seg_len / 3.0)
		for i in n:
			var p := a + dn * (float(i) + 0.5) * 3.0
			for side: float in [-1.0, 1.0]:
				var q := p + perp * side * (t * 0.5 - 0.3)
				merlons.add_obox(Vector3(q.x, h + 0.5, q.y), Vector3(0.75, 0.5, 0.3), yaw, c, c)
		# Occluder: a thin box approximating the wall segment (axis-aligned pieces).
		if absf(d.x) < 1.0 or absf(d.y) < 1.0:
			var lo := Vector3(minf(a.x, b.x) - t * 0.4, 0, minf(a.y, b.y) - t * 0.4)
			var hi := Vector3(maxf(a.x, b.x) + t * 0.4, h - 1.0, maxf(a.y, b.y) + t * 0.4)
			data.add_occluder_box(lo, hi)
	# Towers at ring vertices inside this chunk.
	for p in plan.wall_points:
		if not rect.has_point(p):
			continue
		var th := h + 10.0
		var lo := Vector3(p.x - 7.0, 0, p.y - 7.0)
		var hi := Vector3(p.x + 7.0, th, p.y + 7.0)
		stone.add_banded_box(lo, hi, 4.0, c * 0.4, c * 0.9, c * 0.75, c * 0.6, 0, true)
		data.add_box_shape_lohi(lo, hi)
		data.add_occluder_box(lo + Vector3(0.5, 0, 0.5), hi - Vector3(0.5, 1, 0.5))
		data.mb(M.SLATE).add_pyramid(Vector3(p.x, th, p.y), 7.6, 9.0, Color(0.7, 0.7, 0.75))
		data.add_instance(&"lightning_rod", Transform3D(Basis(), Vector3(p.x, th + 9.0, p.y)))
		data.add_metal(Vector3(p.x, th + 12.0, p.y), 20.0)
