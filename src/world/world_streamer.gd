class_name WorldStreamer
extends Node3D
## Streams the city around a focus point (the player, else the active
## camera, else the spawn point).
##
## Units are grid chunks (`c:x,z`) and landmarks (`lm:id`). A unit is
## requested when its bounds come within `load_radius` of the focus and freed
## beyond `unload_radius`. Generation runs on the WorkerThreadPool; results
## are instantiated on the main thread under a per-frame time budget, then
## the unit's navmesh is baked asynchronously.

signal unit_loaded(key: String)
signal unit_unloaded(key: String)
signal unit_navigation_ready(key: String)

@export var load_radius := 400.0
@export var unload_radius := 500.0
## Landmarks are big and tall; load them from further away.
@export var landmark_extra := 120.0
@export var max_tasks := 4
@export var frame_budget_usec := 3000
@export var update_interval := 0.25
## Navmesh bakes allowed in flight at once. Bakes run on the WorkerThreadPool
## at high priority; several at once occupy every worker, and the physics
## engine's own jobs (Jolt runs on the same pool) then wait: 30-70 ms physics
## hitches while streaming. One at a time keeps a thread free.
@export var max_bakes := 1
## Units freed per update (see `_update_wanted`).
@export var max_unloads_per_update := 2

var plan: CityPlan
var seed_value := 0
var world: Node3D
## Optional explicit focus (overrides player/camera lookup).
var focus_override: Node3D
var fallback_focus := Vector3.ZERO
var canal_fog_material: Material

## key -> ChunkInstancer (being built or loaded)
var _units: Dictionary = {}
## key -> WorkerThreadPool task id
var _tasks: Dictionary = {}
## key -> ChunkBuildData (finished generation, waiting for instancing)
var _results: Dictionary = {}
var _results_mutex := Mutex.new()
## Pending instancers in build order.
var _building: Array[ChunkInstancer] = []
## Instancers whose navmesh is baking.
var _baking: Array[ChunkInstancer] = []
## Instanced units waiting for a free bake slot (nearest first).
var _bake_queue: Array[ChunkInstancer] = []
## Prebuilt data (landmarks computed for the marker index), consumed on load.
var _prebuilt: Dictionary = {}
var _timer := 0.0
var _player: Node3D
var _range: Rect2i


func _init() -> void:
	add_to_group(&"world_streamer")


func setup(p_world: Node3D, p_plan: CityPlan, p_seed: int) -> void:
	world = p_world
	plan = p_plan
	seed_value = p_seed
	_range = plan.chunk_range()


## Hands over already-generated data so it is not generated twice.
func add_prebuilt(data: ChunkBuildData) -> void:
	_prebuilt[data.key] = data


func loaded_keys() -> Array:
	var out: Array = []
	for k: String in _units:
		if (_units[k] as ChunkInstancer).is_done():
			out.append(k)
	return out


func is_loaded(key: String) -> bool:
	return _units.has(key) and (_units[key] as ChunkInstancer).is_done()


## True if the chunk under `p` is fully instantiated (colliders present).
func is_area_loaded(p: Vector3) -> bool:
	if plan == null:
		return false
	var c := plan.chunk_of(Vector2(p.x, p.z))
	if not _range.has_point(c):
		return true
	return is_loaded(ChunkGenerator.chunk_key(c))


func is_busy() -> bool:
	return not _tasks.is_empty() or not _building.is_empty()


## True while navmeshes are still baking or queued.
func is_baking() -> bool:
	return not _baking.is_empty() or not _bake_queue.is_empty()


func focus_position() -> Vector3:
	if focus_override != null and is_instance_valid(focus_override):
		return focus_override.global_position
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player != null and _player.is_inside_tree():
		return _player.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		return cam.global_position
	return fallback_focus


## Units that should be resident for a focus at `p` within `radius`.
func wanted_units(p: Vector3, radius: float) -> Dictionary:
	var out := {}
	var p2 := Vector2(p.x, p.z)
	var cs := plan.chunk_size
	var c0 := Vector2i(floori((p2.x - radius) / cs), floori((p2.y - radius) / cs))
	var c1 := Vector2i(floori((p2.x + radius) / cs), floori((p2.y + radius) / cs))
	for x in range(maxi(c0.x, _range.position.x), mini(c1.x, _range.end.x - 1) + 1):
		for z in range(maxi(c0.y, _range.position.y), mini(c1.y, _range.end.y - 1) + 1):
			var r := plan.chunk_rect(Vector2i(x, z))
			var d := _rect_distance(r, p2)
			if d <= radius:
				out[ChunkGenerator.chunk_key(Vector2i(x, z))] = d
	for lm in plan.landmarks:
		var d2 := _rect_distance(lm.footprint, p2)
		if d2 <= radius + landmark_extra:
			out[ChunkGenerator.landmark_key(lm.id)] = d2
	return out


func _unit_distance(inst: ChunkInstancer, p: Vector3) -> float:
	var key := inst.data.key
	if key.begins_with("c:"):
		return _rect_distance(plan.chunk_rect(inst.data.coord), Vector2(p.x, p.z))
	var lm := plan.landmark_by_id(StringName(key.substr(3)))
	return _rect_distance(lm.footprint, Vector2(p.x, p.z)) if lm != null else 0.0


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dz * dz)


## Synchronously generates and instantiates every unit within `radius` of `p`.
## Used once at startup so the spawn area exists before the first frame.
func load_now(p: Vector3, radius: float) -> void:
	var wanted := wanted_units(p, radius)
	var keys: Array = wanted.keys()
	var todo: Array = []
	for k: String in keys:
		if not _units.has(k):
			todo.append(k)
	var ids: Array[int] = []
	for k: String in todo:
		if _prebuilt.has(k) or _tasks.has(k):
			continue
		ids.append(_start_task(k))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	for k: String in todo:
		var data := _take_result(k)
		if data == null:
			continue
		var inst := ChunkInstancer.new(data, world, canal_fog_material)
		_units[k] = inst
		inst.step(1 << 30)
		_on_instanced(inst)


func _start_task(key: String) -> int:
	var p := plan
	var s := seed_value
	var mutex := _results_mutex
	var results := _results
	var task := func() -> void:
		var data := WorldStreamer.generate_unit(p, s, key)
		mutex.lock()
		results[key] = data
		mutex.unlock()
	var id := WorkerThreadPool.add_task(task, false, "chunk %s" % key)
	_tasks[key] = id
	return id


## Generates the data for a unit key (thread-safe).
static func generate_unit(p: CityPlan, s: int, key: String) -> ChunkBuildData:
	if key.begins_with("c:"):
		var parts := key.substr(2).split(",")
		return ChunkGenerator.generate_chunk(p, s, Vector2i(int(parts[0]), int(parts[1])))
	var lm := p.landmark_by_id(StringName(key.substr(3)))
	if lm == null:
		return null
	return ChunkGenerator.generate_landmark(p, s, lm)


func _take_result(key: String) -> ChunkBuildData:
	if _prebuilt.has(key):
		var d: ChunkBuildData = _prebuilt[key]
		_prebuilt.erase(key)
		return d
	_results_mutex.lock()
	var data: ChunkBuildData = _results.get(key)
	_results.erase(key)
	_results_mutex.unlock()
	return data


func _process(delta: float) -> void:
	if plan == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update_wanted()
	_poll_tasks()
	_build_step()
	_poll_baking()


func _poll_baking() -> void:
	# Start queued bakes while a slot is free (nearest to the focus first).
	if _baking.size() < max_bakes and not _bake_queue.is_empty():
		var focus := focus_position()
		var best := 0
		var bd := INF
		for j in _bake_queue.size():
			var r: Rect2 = _bake_queue[j].data.nav_rect
			var d := _rect_distance(r, Vector2(focus.x, focus.z))
			if d < bd:
				bd = d
				best = j
		var inst: ChunkInstancer = _bake_queue[best]
		_bake_queue.remove_at(best)
		if inst.root != null and is_instance_valid(inst.root):
			if inst.bake_navigation():
				_baking.append(inst)
			else:
				_emit_nav_ready.call_deferred(inst.data.key)
	var i := 0
	while i < _baking.size():
		var inst := _baking[i]
		if inst.poll_navigation():
			_baking.remove_at(i)
			if inst.root != null:
				unit_navigation_ready.emit(inst.data.key)
		else:
			i += 1


func _update_wanted() -> void:
	var p := focus_position()
	var wanted := wanted_units(p, load_radius)
	# Unload far units, a few per update (farthest first): freeing a unit's
	# node tree costs a few ms, and a teleport can drop dozens at once.
	var keep := wanted_units(p, unload_radius)
	var drop: Array = []
	for k: String in _units.keys():
		if not keep.has(k):
			var inst: ChunkInstancer = _units[k]
			if not inst.is_done():
				_unload(k)  # never finished building: cheap, drop now
			else:
				drop.append([_unit_distance(inst, p), k])
	drop.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in mini(drop.size(), max_unloads_per_update):
		_unload(drop[i][1])
	# Request missing units, nearest first.
	var missing: Array = []
	for k: String in wanted:
		if not _units.has(k) and not _tasks.has(k):
			missing.append([wanted[k], k])
	missing.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item: Array in missing:
		if _tasks.size() >= max_tasks:
			break
		var k: String = item[1]
		if _prebuilt.has(k):
			_begin_instancing(k, _take_result(k))
		else:
			_start_task(k)


func _poll_tasks() -> void:
	for k: String in _tasks.keys():
		var id: int = _tasks[k]
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		_tasks.erase(k)
		var data := _take_result(k)
		if data == null:
			continue
		# Dropped while generating?
		var keep := wanted_units(focus_position(), unload_radius)
		if not keep.has(k):
			continue
		_begin_instancing(k, data)


func _begin_instancing(key: String, data: ChunkBuildData) -> void:
	if data == null:
		return
	var inst := ChunkInstancer.new(data, world, canal_fog_material)
	_units[key] = inst
	_building.append(inst)


func _build_step() -> void:
	var t0 := Time.get_ticks_usec()
	while not _building.is_empty():
		var inst: ChunkInstancer = _building[0]
		var left := frame_budget_usec - (Time.get_ticks_usec() - t0)
		if left <= 0:
			break
		if inst.step(left):
			_building.pop_front()
			_on_instanced(inst)


func _on_instanced(inst: ChunkInstancer) -> void:
	var key := inst.data.key
	unit_loaded.emit(key)
	if inst.data.nav_rect.size == Vector2.ZERO or inst.data.nav_faces.is_empty():
		inst.nav_ready = true
		_emit_nav_ready.call_deferred(key)
	else:
		_bake_queue.append(inst)


func _emit_nav_ready(key: String) -> void:
	unit_navigation_ready.emit(key)


func _unload(key: String) -> void:
	var inst: ChunkInstancer = _units[key]
	_units.erase(key)
	_building.erase(inst)
	_bake_queue.erase(inst)
	inst.free_nodes()
	unit_unloaded.emit(key)


## Unloads everything (e.g. before freeing the world). Waits for worker
## tasks and in-flight navmesh bakes so nothing outlives the world.
func unload_all() -> void:
	for k: String in _units.keys():
		(_units[k] as ChunkInstancer).wait_for_bake()
		_unload(k)
	for k: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


func _exit_tree() -> void:
	for k: String in _units:
		(_units[k] as ChunkInstancer).wait_for_bake()
	for k: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


## Returns the instancer for a loaded unit (or null).
func get_unit(key: String) -> ChunkInstancer:
	return _units.get(key)


func unit_count() -> int:
	return _units.size()
