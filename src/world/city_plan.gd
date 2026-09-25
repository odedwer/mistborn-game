class_name CityPlan
extends RefCounted
## Data-driven description of the whole city of Luthadel.
##
## Loaded from `res://src/world/data/luthadel_plan.json`. It holds the city
## bounds, the city wall ring, canals, district polygons with generator styles,
## hand-placed landmarks and mission marker anchors. Every query here is pure
## and read-only after `load_from_file`, so worker threads can share one plan.

const DEFAULT_PATH := "res://src/world/data/luthadel_plan.json"

## One hand-placed landmark (a keep, Kredik Shaw, Fountain Square, ...).
class Landmark:
	var id: StringName
	var type: StringName
	var display_name: String
	var center: Vector2
	## Reserved XZ rectangle. Generic city blocks never overlap it.
	var footprint: Rect2
	var height: float
	var params: Dictionary

	## World-space bounding box (ground to top).
	func aabb() -> AABB:
		return AABB(Vector3(footprint.position.x, -6.0, footprint.position.y),
				Vector3(footprint.size.x, height + 12.0, footprint.size.y))


## One straight, axis-aligned canal.
class Canal:
	var id: StringName
	var rect: Rect2
	var quay: float
	var water_y: float
	var bed_y: float

	## True if the canal runs north-south (long along Z).
	func is_vertical() -> bool:
		return rect.size.y > rect.size.x

	## The water rectangle grown by the quay walkway on the two long sides.
	func reserved_rect() -> Rect2:
		if is_vertical():
			return Rect2(rect.position.x - quay, rect.position.y, rect.size.x + quay * 2.0, rect.size.y)
		return Rect2(rect.position.x, rect.position.y - quay, rect.size.x, rect.size.y + quay * 2.0)


var plan_name := "Luthadel"
var chunk_size := 128.0
## XZ rectangle covering the whole generated city (chunk-aligned).
var bounds := Rect2()
## XZ rectangle of the vertical-slice district.
var slice_bounds := Rect2()
var wall_points: PackedVector2Array = PackedVector2Array()
var wall_height := 20.0
var wall_thickness := 6.0
var canals: Array[Canal] = []
var landmarks: Array[Landmark] = []
var default_district: StringName = &"skaa_slums"
## Array of {id, type: StringName, polygon: PackedVector2Array, aabb: Rect2}.
var districts: Array[Dictionary] = []
## type -> style Dictionary (see luthadel_plan.json).
var styles: Dictionary = {}
## Raw marker anchor dictionaries from the plan.
var markers: Array[Dictionary] = []


## Loads and parses the plan. Returns null (and prints an error) on failure.
static func load_from_file(path: String = DEFAULT_PATH) -> CityPlan:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("CityPlan: cannot read %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CityPlan: invalid JSON in %s" % path)
		return null
	var plan := CityPlan.new()
	plan._parse(data as Dictionary)
	return plan


func _parse(d: Dictionary) -> void:
	plan_name = str(d.get("name", "Luthadel"))
	chunk_size = float(d.get("chunk_size", 128))
	bounds = _rect_from(d.get("bounds", [-256, -256, 256, 256]))
	slice_bounds = _rect_from(d.get("slice_bounds", [-256, -256, 256, 256]))
	var wall: Dictionary = d.get("city_wall", {})
	wall_height = float(wall.get("height", 20.0))
	wall_thickness = float(wall.get("thickness", 6.0))
	wall_points = _points_from(wall.get("points", []))
	for c: Dictionary in d.get("canals", []):
		var canal := Canal.new()
		canal.id = StringName(str(c.get("id", "canal")))
		canal.rect = _rect_from(c.get("rect", [0, 0, 1, 1]))
		canal.quay = float(c.get("quay", 8.0))
		canal.water_y = float(c.get("water_y", -2.2))
		canal.bed_y = float(c.get("bed_y", -4.5))
		canals.append(canal)
	default_district = StringName(str(d.get("default_district", "skaa_slums")))
	for dd: Dictionary in d.get("districts", []):
		var poly := _points_from(dd.get("polygon", []))
		districts.append({
			"id": StringName(str(dd.get("id", ""))),
			"type": StringName(str(dd.get("type", default_district))),
			"polygon": poly,
			"aabb": _poly_aabb(poly),
		})
	var st: Dictionary = d.get("styles", {})
	for k: String in st:
		styles[StringName(k)] = st[k]
	for ld: Dictionary in d.get("landmarks", []):
		var lm := Landmark.new()
		lm.id = StringName(str(ld.get("id", "")))
		lm.type = StringName(str(ld.get("type", "")))
		lm.display_name = str(ld.get("name", lm.id))
		var c: Array = ld.get("center", [0, 0])
		lm.center = Vector2(float(c[0]), float(c[1]))
		lm.footprint = _rect_from(ld.get("footprint", [0, 0, 1, 1]))
		lm.height = float(ld.get("height", 30.0))
		lm.params = ld
		landmarks.append(lm)
	for m: Dictionary in d.get("markers", []):
		markers.append(m)


static func _rect_from(a: Array) -> Rect2:
	var x0 := float(a[0])
	var z0 := float(a[1])
	return Rect2(x0, z0, float(a[2]) - x0, float(a[3]) - z0)


static func _points_from(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


# --- Queries ----------------------------------------------------------------

## Range of chunk coordinates covering `bounds` (inclusive min, exclusive max).
func chunk_range() -> Rect2i:
	var x0 := floori(bounds.position.x / chunk_size)
	var z0 := floori(bounds.position.y / chunk_size)
	var x1 := ceili(bounds.end.x / chunk_size)
	var z1 := ceili(bounds.end.y / chunk_size)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / chunk_size), floori(p.y / chunk_size))


func chunk_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * chunk_size, c.y * chunk_size, chunk_size, chunk_size)


## True if `p` lies inside the city wall.
func inside_city(p: Vector2) -> bool:
	if wall_points.size() < 3:
		return bounds.has_point(p)
	return Geometry2D.is_point_in_polygon(p, wall_points)


## District type at a point ("outside" beyond the wall).
func district_at(p: Vector2) -> StringName:
	if not inside_city(p):
		return &"outside"
	for d in districts:
		var ab: Rect2 = d["aabb"]
		if ab.has_point(p) and Geometry2D.is_point_in_polygon(p, d["polygon"]):
			return d["type"]
	return default_district


## Generator style for a district type (falls back to the default district).
func style(type: StringName) -> Dictionary:
	if styles.has(type):
		return styles[type]
	return styles.get(default_district, {})


func style_at(p: Vector2) -> Dictionary:
	return style(district_at(p))


## The landmark whose footprint overlaps `r` (null if none).
func landmark_overlapping(r: Rect2) -> Landmark:
	for lm in landmarks:
		if lm.footprint.intersects(r):
			return lm
	return null


func landmark_by_id(id: StringName) -> Landmark:
	for lm in landmarks:
		if lm.id == id:
			return lm
	return null


## Canals whose reserved rect (water + quays) overlaps `r`.
func canals_overlapping(r: Rect2) -> Array[Canal]:
	var out: Array[Canal] = []
	for c in canals:
		if c.reserved_rect().intersects(r):
			out.append(c)
	return out


## Shortest distance from `p` to the city wall centre line.
func distance_to_wall(p: Vector2) -> float:
	var best := INF
	var n := wall_points.size()
	for i in n:
		var a := wall_points[i]
		var b := wall_points[(i + 1) % n]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, q.distance_to(p))
	return best


## Wall segments (pairs of points) that intersect rectangle `r`, clipped to it.
func wall_segments_in(r: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := wall_points.size()
	for i in n:
		var seg := clip_segment(wall_points[i], wall_points[(i + 1) % n], r)
		if seg.size() == 2:
			out.append(seg)
	return out


## Liang-Barsky clip of segment a-b to rectangle r. Empty if outside.
static func clip_segment(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		var pi: float = p[i]
		var qi: float = q[i]
		if absf(pi) < 1e-9:
			if qi < 0.0:
				return PackedVector2Array()
		else:
			var t := qi / pi
			if pi < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


## Deterministic hash of integers mixed with the world seed.
static func hash_ints(seed_value: int, a: int, b: int = 0, c: int = 0, d: int = 0) -> int:
	return hash([seed_value, a, b, c, d])


## Deterministic 0..1 value from integer keys.
static func hash01(seed_value: int, a: int, b: int = 0, c: int = 0, d: int = 0) -> float:
	return float(hash_ints(seed_value, a, b, c, d) & 0xFFFFFF) / float(0xFFFFFF)
