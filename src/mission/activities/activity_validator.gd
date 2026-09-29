class_name ActivityValidator
extends RefCounted
## Geometry validation for open-world activities, plus a small deterministic
## path finder used to author them (see `tools/gen_activities.gd`).
##
## Activities are authored as offsets from a plan marker whose real position is
## resolved by `ChunkLayout` (rooftop/street placement), so whether a ring or
## a thief path clips a building can only be checked against the generated
## city. This regenerates the chunks (and landmarks) around an activity, keeps
## their collision boxes as AABBs (convex roof shapes as their bounding box, a
## conservative approximation), and tests:
## - coin race: every ring sphere and every leg between rings is clear;
## - rooftop pursuit: every path point and leg is clear at capsule height, and
##   the thief never has to jump more than `MAX_STEP_UP`;
## - ambush / riot: each spawn point around the start is clear ground.
## `tests/test_activity_validation.gd` runs it over every activity in the plan.

const RING_RADIUS := 2.5
const BODY_RADIUS := 1.0
const THIEF_RADIUS := 0.6
const MAX_STEP_UP := 6.0
## Boxes whose top is below this are ground/curbs, not obstacles.
const GROUND_TOP := 0.6

var plan: CityPlan
var seed_value := 1337

var _solids: Dictionary = {}   # unit key -> Array[AABB]
var _markers: Dictionary = {}  # unit key -> Array[Dictionary]


func _init(p_plan: CityPlan, p_seed := 1337) -> void:
	plan = p_plan
	seed_value = p_seed


# --- Geometry cache -------------------------------------------------------------

func _load_unit(key: String, data: ChunkBuildData) -> void:
	var boxes: Array[AABB] = []
	for s: Dictionary in data.shapes:
		var bb := AABB()
		if s.has("box"):
			var size: Vector3 = s["box"]
			bb = (s["xf"] as Transform3D) * AABB(-size * 0.5, size)
		elif s.has("convex"):
			var pts: PackedVector3Array = s["convex"]
			if pts.is_empty():
				continue
			bb = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				bb = bb.expand(p)
		else:
			continue
		if bb.end.y > GROUND_TOP:
			boxes.append(bb)
	_solids[key] = boxes
	_markers[key] = data.markers


func _ensure_chunk(c: Vector2i) -> String:
	var key := ChunkGenerator.chunk_key(c)
	if not _solids.has(key):
		_load_unit(key, ChunkGenerator.generate_chunk(plan, seed_value, c))
	return key


func _ensure_landmark(lm: CityPlan.Landmark) -> void:
	var key := ChunkGenerator.landmark_key(lm.id)
	if not _solids.has(key):
		_load_unit(key, ChunkGenerator.generate_landmark(plan, seed_value, lm))


## Drops cached geometry (call after changing `plan.markers`).
func clear() -> void:
	_solids.clear()
	_markers.clear()


## Drops one chunk's cache (a marker only reshapes the lot it forces, in its own chunk).
func invalidate_chunk(c: Vector2i) -> void:
	var key := ChunkGenerator.chunk_key(c)
	_solids.erase(key)
	_markers.erase(key)


## Solid boxes intersecting the XZ `area` (chunks and landmarks around it).
func solids_in(area: Rect2) -> Array[AABB]:
	var out: Array[AABB] = []
	var c0 := plan.chunk_of(area.position)
	var c1 := plan.chunk_of(area.end)
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			out.append_array(_solids[_ensure_chunk(Vector2i(x, z))])
	for lm in plan.landmarks:
		if lm.footprint.intersects(area):
			_ensure_landmark(lm)
			out.append_array(_solids[ChunkGenerator.landmark_key(lm.id)])
	return out


## The resolved world position of an `activity_start` plan marker.
func resolve_start(activity_id: StringName) -> Vector3:
	for m: Dictionary in plan.markers:
		if str(m.get("activity_id", "")) != String(activity_id):
			continue
		var pa: Array = m["pos"]
		var key := _ensure_chunk(plan.chunk_of(Vector2(float(pa[0]), float(pa[1]))))
		for e: Dictionary in _markers[key]:
			if e["group"] == &"activity_start" and str(e["meta"].get("activity_id", "")) == String(activity_id):
				return e["pos"]
	return Vector3.INF


# --- Clearance tests ------------------------------------------------------------

static func point_clear(p: Vector3, radius: float, boxes: Array[AABB]) -> bool:
	for b in boxes:
		if b.grow(radius).has_point(p):
			return false
	return true


static func segment_clear(a: Vector3, b: Vector3, radius: float, boxes: Array[AABB]) -> bool:
	for bx in boxes:
		var g := bx.grow(radius)
		if g.has_point(a) or g.has_point(b) or g.intersects_segment(a, b) != null:
			return false
	return true


## Highest solid top over (x, z), or 0.0 over open ground.
static func top_at(x: float, z: float, boxes: Array[AABB]) -> float:
	var top := 0.0
	for b in boxes:
		if x >= b.position.x and x <= b.end.x and z >= b.position.z and z <= b.end.z:
			top = maxf(top, b.end.y)
	return top


func _area_around(points: Array[Vector3], margin: float) -> Rect2:
	var r := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(margin)


func _ring_points(start: Vector3, params: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for off: Array in params.get("ring_offsets", []):
		pts.append(start + Vector3(float(off[0]), float(off[1]), float(off[2])))
	return pts


func _path_points(start: Vector3, params: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for off: Array in params.get("path_offsets", []):
		pts.append(start + Vector3(float(off[0]), float(off[1]), float(off[2])))
	return pts


func _spawn_points(start: Vector3, count: int, radius: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in count:
		var ang := TAU * float(i) / maxf(float(count), 1.0)
		pts.append(start + Vector3(cos(ang), 0.0, sin(ang)) * radius)
	return pts


## Problems with `a` placed at `start`, as human-readable strings (empty = valid).
func validate(a: ActivityData, start: Vector3) -> Array[String]:
	var errs: Array[String] = []
	if start == Vector3.INF:
		errs.append("no resolved start marker")
		return errs
	match String(a.type):
		"coin_race":
			var pts := _ring_points(start, a.params)
			if pts.is_empty():
				errs.append("no rings")
				return errs
			var all: Array[Vector3] = [start]
			all.append_array(pts)
			var boxes := solids_in(_area_around(all, 12.0))
			var prev := start + Vector3.UP * 2.0
			for i in pts.size():
				var p := pts[i]
				if not plan.inside_city(Vector2(p.x, p.z)):
					errs.append("ring %d outside the wall" % i)
				if p.y < 1.5:
					errs.append("ring %d below ground clearance" % i)
				if not point_clear(p, RING_RADIUS, boxes):
					errs.append("ring %d intersects a building" % i)
				if not segment_clear(prev, p, BODY_RADIUS, boxes):
					errs.append("leg to ring %d is blocked" % i)
				prev = p
		"rooftop_pursuit":
			var pts := _path_points(start, a.params)
			if pts.size() < 2:
				errs.append("path too short")
				return errs
			var boxes := solids_in(_area_around(pts, 12.0))
			var up := Vector3.UP * 1.0
			for i in pts.size():
				if not point_clear(pts[i] + up, THIEF_RADIUS, boxes):
					errs.append("path point %d is inside a building" % i)
				if i > 0:
					if not segment_clear(pts[i - 1] + up, pts[i] + up, THIEF_RADIUS, boxes):
						errs.append("path leg %d is blocked" % i)
					if pts[i].y - pts[i - 1].y > MAX_STEP_UP:
						errs.append("path leg %d climbs too steeply" % i)
		"obligator_ambush", "crowd_riot":
			var count := (a.params.get("enemy_types", []) as Array).size() if a.type == &"obligator_ambush" \
					else int(a.params.get("member_count", 5))
			var radius := float(a.params.get("spawn_radius", 8.0))
			var pts := _spawn_points(start, count, radius)
			pts.append(start)
			var boxes := solids_in(_area_around(pts, 6.0))
			for i in pts.size():
				if not point_clear(pts[i] + Vector3.UP * 0.9, 0.5, boxes):
					errs.append("spawn point %d is inside a building" % i)
				if not plan.inside_city(Vector2(pts[i].x, pts[i].z)):
					errs.append("spawn point %d outside the wall" % i)
		_:
			errs.append("unknown type %s" % a.type)
	return errs


# --- Authoring helpers (deterministic) -------------------------------------------

## A clear coin-race ring chain from `start`, as offsets, or [] if none found.
func find_ring_offsets(start: Vector3, count: int, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var area := Rect2(Vector2(start.x, start.z), Vector2.ZERO).grow(count * 22.0 + 20.0)
	var boxes := solids_in(area)
	for restart in 40:
		var heading := rng.randf() * TAU
		var prev := start + Vector3.UP * 2.0
		var out: Array = []
		var ok := true
		for i in count:
			var found := false
			for attempt in 60:
				var ang := heading + rng.randf_range(-0.7, 0.7)
				var step := rng.randf_range(13.0, 20.0)
				var y := clampf(prev.y + rng.randf_range(-1.5, 4.0), start.y + 2.0, start.y + 9.0)
				var cand := Vector3(prev.x + sin(ang) * step, y, prev.z + cos(ang) * step)
				cand = Vector3(snappedf(cand.x, 0.5), snappedf(cand.y, 0.5), snappedf(cand.z, 0.5))
				if not plan.inside_city(Vector2(cand.x, cand.z)) or plan.distance_to_wall(Vector2(cand.x, cand.z)) < 30.0:
					continue
				if not point_clear(cand, RING_RADIUS + 0.4, boxes):
					continue
				if not segment_clear(prev, cand, BODY_RADIUS + 0.3, boxes):
					continue
				out.append([cand.x - start.x, cand.y - start.y, cand.z - start.z])
				prev = cand
				heading = ang
				found = true
				break
			if not found:
				ok = false
				break
		if ok:
			return out
	return []


## A clear rooftop chase path from `start`, as offsets, or [] if none found.
func find_path_offsets(start: Vector3, count: int, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var area := Rect2(Vector2(start.x, start.z), Vector2.ZERO).grow(count * 18.0 + 20.0)
	var boxes := solids_in(area)
	var up := Vector3.UP * 1.0
	for restart in 120:
		var heading := rng.randf() * TAU
		var prev := start
		var out: Array = [[0.0, 0.0, 0.0]]
		var ok := true
		for i in count - 1:
			var found := false
			for attempt in 200:
				var ang := heading + rng.randf_range(-1.0, 1.0)
				var step := rng.randf_range(6.0, 15.0)
				var x := snappedf(prev.x + sin(ang) * step, 0.5)
				var z := snappedf(prev.z + cos(ang) * step, 0.5)
				if not plan.inside_city(Vector2(x, z)) or plan.distance_to_wall(Vector2(x, z)) < 30.0:
					continue
				var y := top_at(x, z, boxes) + 0.25
				if y < start.y - 6.0 or y > start.y + 8.0 or y - prev.y > MAX_STEP_UP:
					continue
				var cand := Vector3(x, y, z)
				if not point_clear(cand + up, THIEF_RADIUS + 0.2, boxes):
					continue
				if not segment_clear(prev + up, cand + up, THIEF_RADIUS + 0.2, boxes):
					continue
				out.append([cand.x - start.x, cand.y - start.y, cand.z - start.z])
				prev = cand
				heading = ang
				found = true
				break
			if not found:
				ok = false
				break
		if ok:
			return out
	return []
