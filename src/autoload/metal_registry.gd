extends Node
## Registry of every Metallic in the world, with a uniform spatial hash for
## fast "metals within radius" queries (used every physics frame by steel
## sight and Push/Pull targeting, so it must stay cheap with 1000+ metals).

const CELL_SIZE := 8.0

var _all: Array[Metallic] = []
var _grid: Dictionary = {}       # Vector3i -> Array[Metallic]
var _cell_of: Dictionary = {}    # Metallic -> Vector3i
var _dirty_frame := -1


func register(m: Metallic) -> void:
	if m in _cell_of:
		return
	_all.append(m)
	_insert(m)


func unregister(m: Metallic) -> void:
	if not m in _cell_of:
		return
	_all.erase(m)
	var c: Vector3i = _cell_of[m]
	var bucket: Array = _grid.get(c, [])
	bucket.erase(m)
	if bucket.is_empty():
		_grid.erase(c)
	_cell_of.erase(m)


func count() -> int:
	return _all.size()


func all() -> Array[Metallic]:
	return _all


## Metals within `radius` of `origin`, excluding shielded ones unless asked.
func query_radius(origin: Vector3, radius: float, include_shielded := false) -> Array[Metallic]:
	_refresh()
	var out: Array[Metallic] = []
	var r2 := radius * radius
	var lo := _cell(origin - Vector3.ONE * radius)
	var hi := _cell(origin + Vector3.ONE * radius)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var bucket = _grid.get(Vector3i(x, y, z))
				if bucket == null:
					continue
				for m: Metallic in bucket:
					if not include_shielded and m.shielded:
						continue
					if m.global_position.distance_squared_to(origin) <= r2:
						out.append(m)
	return out


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL_SIZE), floori(p.y / CELL_SIZE), floori(p.z / CELL_SIZE))


func _insert(m: Metallic) -> void:
	var c := _cell(m.global_position) if m.is_inside_tree() else Vector3i.ZERO
	_cell_of[m] = c
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(m)


## Re-bucket metals that moved. Done lazily at most once per physics frame.
func _refresh() -> void:
	var f := Engine.get_physics_frames()
	if f == _dirty_frame:
		return
	_dirty_frame = f
	for m in _all:
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var nc := _cell(m.global_position)
		var oc: Vector3i = _cell_of[m]
		if nc != oc:
			var bucket: Array = _grid[oc]
			bucket.erase(m)
			if bucket.is_empty():
				_grid.erase(oc)
			_cell_of[m] = nc
			if not _grid.has(nc):
				_grid[nc] = []
			_grid[nc].append(m)
