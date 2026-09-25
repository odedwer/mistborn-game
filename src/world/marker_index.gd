class_name MarkerIndex
extends RefCounted
## Spatial index of marker *data* (spawns, objectives, pickups, landmarks),
## available whether or not the owning chunk is loaded. Each entry is
## {"group": StringName, "pos": Vector3, "meta": Dictionary, "unit": String}.

const CELL := 64.0

var _entries: Array[Dictionary] = []
var _by_group: Dictionary = {}   # StringName -> Array[Dictionary]
var _grid: Dictionary = {}       # Vector2i -> Array[Dictionary]
var _units: Dictionary = {}      # unit key -> true (already indexed)


func has_unit(key: String) -> bool:
	return _units.has(key)


## Indexes every marker of a generated unit (idempotent per unit).
func add_unit(key: String, markers: Array[Dictionary]) -> void:
	if _units.has(key):
		return
	_units[key] = true
	for m in markers:
		var e := {"group": m["group"], "pos": m["pos"], "meta": m["meta"], "unit": key}
		_entries.append(e)
		var g: StringName = e["group"]
		if not _by_group.has(g):
			_by_group[g] = []
		_by_group[g].append(e)
		var p: Vector3 = e["pos"]
		var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(e)


func size() -> int:
	return _entries.size()


func all() -> Array[Dictionary]:
	return _entries


func by_group(group: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _by_group.get(group, []):
		out.append(e)
	return out


## First entry whose meta[key] == value (e.g. find("objective_id", &"ledger")).
func find(meta_key: StringName, value: Variant, group: StringName = &"") -> Dictionary:
	var src: Array = _entries if group == &"" else _by_group.get(group, [])
	for e: Dictionary in src:
		var meta: Dictionary = e["meta"]
		if meta.get(meta_key) == value:
			return e
	return {}


## Entries within `radius` of `p` (optionally filtered by group).
func query_radius(p: Vector3, radius: float, group: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c0 := Vector2i(floori((p.x - radius) / CELL), floori((p.z - radius) / CELL))
	var c1 := Vector2i(floori((p.x + radius) / CELL), floori((p.z + radius) / CELL))
	var r2 := radius * radius
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			for e: Dictionary in _grid.get(Vector2i(x, z), []):
				if group != &"" and e["group"] != group:
					continue
				if (e["pos"] as Vector3).distance_squared_to(p) <= r2:
					out.append(e)
	return out
