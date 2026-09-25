extends Node
## Registry of every Metallic in the world, with a uniform spatial hash for
## fast "metals within radius" queries (used every physics frame by steel
## sight and Push/Pull targeting, so it must stay cheap with 5000+ metals).
##
## The hash is 2D (XZ columns of CELL_SIZE metres): the city is flat compared
## with its extent, so a column lookup plus a per-metal distance check beats
## walking a 3D cell cube. Only metals that can move (not anchored, not on a
## static body) are re-bucketed each physics frame; registering and
## unregistering are O(1) (swap-remove), so streaming a chunk with hundreds
## of metals out doesn't hitch.

const CELL_SIZE := 16.0

var _all: Array[Metallic] = []
var _index: Dictionary = {}      # Metallic -> index in _all
var _dynamic: Array[Metallic] = []
var _dyn_index: Dictionary = {}  # Metallic -> index in _dynamic
var _grid: Dictionary = {}       # Vector2i -> Array[Metallic]
var _cell_of: Dictionary = {}    # Metallic -> Vector2i
var _dirty_frame := -1


func register(m: Metallic) -> void:
	if _index.has(m):
		return
	_index[m] = _all.size()
	_all.append(m)
	if _is_dynamic(m):
		_dyn_index[m] = _dynamic.size()
		_dynamic.append(m)
	_insert(m)


func unregister(m: Metallic) -> void:
	if not _index.has(m):
		return
	_swap_remove(_all, _index, m)
	if _dyn_index.has(m):
		_swap_remove(_dynamic, _dyn_index, m)
	var c: Vector2i = _cell_of[m]
	var bucket: Array = _grid.get(c, [])
	bucket.erase(m)
	if bucket.is_empty():
		_grid.erase(c)
	_cell_of.erase(m)


static func _swap_remove(arr: Array[Metallic], index: Dictionary, m: Metallic) -> void:
	var i: int = index[m]
	var last := arr.size() - 1
	if i != last:
		var moved := arr[last]
		arr[i] = moved
		index[moved] = i
	arr.resize(last)
	index.erase(m)


static func _is_dynamic(m: Metallic) -> bool:
	if m.anchored:
		return false
	var b := m.body if m.body != null else m.get_parent()
	return not (b is StaticBody3D)


func count() -> int:
	return _all.size()


func all() -> Array[Metallic]:
	return _all


## Number of metals that can move (re-bucketed every physics frame).
func dynamic_count() -> int:
	return _dynamic.size()


## Metals within `radius` of `origin`, excluding shielded ones unless asked.
func query_radius(origin: Vector3, radius: float, include_shielded := false) -> Array[Metallic]:
	_refresh()
	var out: Array[Metallic] = []
	var r2 := radius * radius
	var x0 := floori((origin.x - radius) / CELL_SIZE)
	var x1 := floori((origin.x + radius) / CELL_SIZE)
	var z0 := floori((origin.z - radius) / CELL_SIZE)
	var z1 := floori((origin.z + radius) / CELL_SIZE)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var bucket = _grid.get(Vector2i(x, z))
			if bucket == null:
				continue
			for m: Metallic in bucket:
				if not include_shielded and m.shielded:
					continue
				if m.global_position.distance_squared_to(origin) <= r2:
					out.append(m)
	return out


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.z / CELL_SIZE))


func _insert(m: Metallic) -> void:
	var c := _cell(m.global_position) if m.is_inside_tree() else Vector2i.ZERO
	_cell_of[m] = c
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(m)


## Re-bucket metals that moved. Done lazily at most once per physics frame,
## and only for metals that can move.
func _refresh() -> void:
	var f := Engine.get_physics_frames()
	if f == _dirty_frame:
		return
	_dirty_frame = f
	for m in _dynamic:
		if not m.is_inside_tree():
			continue
		var nc := _cell(m.global_position)
		var oc: Vector2i = _cell_of[m]
		if nc != oc:
			var bucket: Array = _grid[oc]
			bucket.erase(m)
			if bucket.is_empty():
				_grid.erase(oc)
			_cell_of[m] = nc
			if not _grid.has(nc):
				_grid[nc] = []
			_grid[nc].append(m)
