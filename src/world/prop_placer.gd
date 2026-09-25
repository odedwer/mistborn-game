class_name PropPlacer
extends RefCounted
## Street furniture for one chunk: iron lamp posts (anchored Push/Pull
## anchors), loose metal props along building fronts and plaza furniture.
## Thread-safe, data only.

const M := WorldMaterials.Mat
const LAMP_LIGHT_COLOR := Color(1.0, 0.62, 0.3)

## Loose prop kinds and their relative weights.
const LOOSE_WEIGHTS := {
	&"crate": 30.0, &"barrel": 20.0, &"bucket": 14.0, &"scrap": 14.0, &"horseshoe": 10.0, &"cart": 8.0,
}


## Places lamps, loose props and plaza furniture.
static func place(data: ChunkBuildData, plan: CityPlan, L: ChunkLayout, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(seed_value, L.coord.x, L.coord.y, 53)
	_lamps(data, L, rng)
	_loose(data, plan, L, rng)
	_plazas(data, L, rng)


static func _lamps(data: ChunkBuildData, L: ChunkLayout, rng: RandomNumberGenerator) -> void:
	var lit_ratio := 0.55 if L.district == &"skaa_slums" else 0.85
	# Mission-critical lamps (near spawn and checkpoints) get the few shadowed lights.
	var shadow_lamps: Dictionary = {}
	for m in L.markers:
		var important := m["group"] == &"player_spawn"
		var oid: StringName = m["meta"].get("objective_id", &"")
		if String(oid).begins_with("cp_"):
			important = true
		if not important:
			continue
		var p: Vector3 = m["pos"]
		var best := -1
		var bd := 30.0
		for i in L.lamps.size():
			var d := Vector2(L.lamps[i].x, L.lamps[i].z).distance_to(Vector2(p.x, p.z))
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			shadow_lamps[best] = true
	for i in L.lamps.size():
		var base := L.lamps[i]
		var dir := L.lamp_dirs[i]
		var lit := rng.randf() < lit_ratio or shadow_lamps.has(i)
		var shadow := shadow_lamps.has(i)
		data.lamp_posts.append({"pos": base, "dir": dir, "lit": lit, "shadow": shadow})
		data.metal_count += 1
		data.add_nav_box(base - Vector3(0.15, 0, 0.15), base + Vector3(0.15, 4.2, 0.15), false)
		if lit:
			var lp := base + Vector3(dir.x * 0.75, 3.75, dir.y * 0.75)
			data.add_light(lp, LAMP_LIGHT_COLOR, 11.0 if shadow else 9.5, 2.4 if shadow else 1.9, shadow)


static func _pick_kind(rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for k: StringName in LOOSE_WEIGHTS:
		total += LOOSE_WEIGHTS[k]
	var r := rng.randf() * total
	for k: StringName in LOOSE_WEIGHTS:
		r -= LOOSE_WEIGHTS[k]
		if r <= 0.0:
			return k
	return &"crate"


static func _free_spot(plan: CityPlan, L: ChunkLayout, p: Vector2, radius: float) -> bool:
	if not L.rect.grow(-1.0).has_point(p):
		return false
	if L.point_in_lot(p, radius):
		return false
	for c in plan.canals:
		if c.rect.grow(1.0 + radius).has_point(p):
			return false
	if plan.landmark_overlapping(Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)) != null:
		return false
	for lp in L.lamps:
		if Vector2(lp.x, lp.z).distance_to(p) < radius + 0.6:
			return false
	return true


static func _loose(data: ChunkBuildData, plan: CityPlan, L: ChunkLayout, rng: RandomNumberGenerator) -> void:
	if L.lots.is_empty():
		return
	var target := int(L.style.get("props", 8))
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 6:
		attempts += 1
		var lot: ChunkLayout.Lot = L.lots[rng.randi_range(0, L.lots.size() - 1)]
		var fr := BuildingBuilder._face_frame(lot.rect, lot.front)
		var o: Vector3 = fr[0]
		var rv: Vector3 = fr[1]
		var n: Vector3 = fr[2]
		var length: float = fr[3]
		var kind := _pick_kind(rng)
		var def: Array = PropMeshes.RIGID[kind]
		var size: Vector3 = def[3]
		var half_h := size.y * 0.5
		var clearance := 0.5 + (size.z if kind == &"cart" else 0.4)
		var p := o + rv * rng.randf_range(1.0, maxf(1.1, length - 1.0)) + n * clearance
		if not _free_spot(plan, L, Vector2(p.x, p.z), 0.8 if kind != &"cart" else 1.6):
			continue
		var yaw := atan2(rv.x, rv.z) + (PI * 0.5 if kind == &"cart" else rng.randf_range(-0.4, 0.4))
		data.add_rigid(kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, half_h + 0.02, p.z)))
		placed += 1
		# Stacks and scatter around the main prop.
		if kind == &"crate" and rng.randf() < 0.4:
			data.add_rigid(&"crate", Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.3, 0.3)), Vector3(p.x, 1.22, p.z)))
		elif kind == &"cart" and rng.randf() < 0.6:
			var hp := p + rv * 1.8
			if _free_spot(plan, L, Vector2(hp.x, hp.z), 0.4):
				data.add_rigid(&"horseshoe", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(hp.x, 0.05, hp.z)))


static func _plazas(data: ChunkBuildData, L: ChunkLayout, rng: RandomNumberGenerator) -> void:
	for pz in L.plazas:
		var c := pz.get_center()
		# Well with an iron winch in the middle.
		data.add_instance(&"well", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, 0, c.y)))
		data.add_box_shape(Vector3(c.x, 0.45, c.y), Vector3(2.2, 0.9, 2.2))
		data.add_metal(Vector3(c.x, 2.2, c.y), 30.0)
		data.add_nav_box(Vector3(c.x - 1.1, 0, c.y - 1.1), Vector3(c.x + 1.1, 0.9, c.y + 1.1), false)
		# Market stalls around it.
		var n := rng.randi_range(2, 5)
		for i in n:
			var a := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
			var rad := minf(pz.size.x, pz.size.y) * 0.32
			var p := c + Vector2(sin(a), cos(a)) * rad
			var yaw := a + PI
			data.add_instance(&"stall", Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y)))
			data.add_box_shape(Vector3(p.x, 0.45, p.y), Vector3(2.4, 0.9, 1.1), yaw)
		# Corner lamp posts make plazas good Push hubs.
		for k in 4:
			var corner := Vector2(pz.position.x + (1.5 if k % 2 == 0 else pz.size.x - 1.5),
					pz.position.y + (1.5 if k < 2 else pz.size.y - 1.5))
			var dir := (c - corner).normalized()
			var lit := rng.randf() < 0.7
			data.lamp_posts.append({"pos": Vector3(corner.x, 0, corner.y), "dir": dir, "lit": lit, "shadow": false})
			data.metal_count += 1
			if lit:
				data.add_light(Vector3(corner.x + dir.x * 0.75, 3.75, corner.y + dir.y * 0.75), LAMP_LIGHT_COLOR, 9.5, 1.9)
		for i in rng.randi_range(2, 4):
			var p2 := c + Vector2(rng.randf_range(-pz.size.x * 0.35, pz.size.x * 0.35), rng.randf_range(-pz.size.y * 0.35, pz.size.y * 0.35))
			if p2.distance_to(c) < 2.5:
				continue
			data.add_rigid(&"barrel" if rng.randf() < 0.5 else &"crate", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p2.x, 0.5, p2.y)))
