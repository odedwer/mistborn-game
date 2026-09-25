class_name LuthadelWorld
extends Node3D
## Procedural, streamed Luthadel at night.
##
## On `_ready` it loads the city plan, indexes every mission marker (as data,
## even in chunks that are not loaded), builds the environment and the
## MistController, synchronously streams in the area around the player spawn
## (so the player can spawn on the first frame), then keeps streaming chunks
## and landmarks around the player (`WorldStreamer`) while the far-LOD
## skyline builds in the background. See docs/OPEN_WORLD.md.

## Emitted once the navmeshes of the initially loaded area are baked.
signal navigation_ready
## Emitted when a streamed unit (chunk "c:x,z" or landmark "lm:id") is instantiated.
signal unit_loaded(key: String)
signal unit_unloaded(key: String)
## Marker nodes that just entered the tree with a newly loaded unit
## (spawn enemies/pickups for them here).
signal markers_spawned(nodes: Array[Node3D])

@export var seed := 1337
@export_file("*.json") var plan_path := CityPlan.DEFAULT_PATH
## Units within this radius of the spawn are generated synchronously in _ready.
@export var initial_radius := 170.0
@export var load_radius := 400.0
@export var unload_radius := 500.0
@export var build_environment := true
@export var build_far_lod := true
## 0 low .. 3 ultra (GameSettings overrides this through the mist controller).
@export_range(0, 3) var mist_quality := 2

var plan: CityPlan
var marker_index: MarkerIndex
var streamer: WorldStreamer
var mist: MistController
var far_lod: FarLod
var environment: Environment
var moon: DirectionalLight3D
var units_root: Node3D
## Wall-clock time spent in _ready (ms).
var generation_time_ms := 0.0
var is_navigation_ready := false
var _pending_nav: Dictionary = {}
var _initial_phase := false
## Navigation map iteration to wait for before announcing navigation_ready (-1 = not waiting).
var _nav_wait_iteration := -1


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	add_to_group(&"luthadel_world")
	plan = CityPlan.load_from_file(plan_path)
	if plan == null:
		push_error("LuthadelWorld: no city plan")
		return
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)

	var prebuilt := _build_marker_index()

	if build_environment:
		var env := EnvironmentBuilder.build(self)
		environment = env["environment"]
		moon = env["moon"]
		(env["world_env"] as Node).add_to_group(&"world_environment")
	mist = MistController.new()
	mist.quality = mist_quality
	add_child(mist)
	if environment != null:
		mist.setup(environment)

	streamer = WorldStreamer.new()
	streamer.name = "WorldStreamer"
	streamer.load_radius = load_radius
	streamer.unload_radius = unload_radius
	add_child(streamer)
	streamer.setup(units_root, plan, seed)
	streamer.canal_fog_material = mist.canal_material
	streamer.fallback_focus = spawn_position()
	for d: ChunkBuildData in prebuilt:
		streamer.add_prebuilt(d)
	streamer.unit_loaded.connect(_on_unit_loaded)
	streamer.unit_unloaded.connect(_on_unit_unloaded)
	streamer.unit_navigation_ready.connect(_on_unit_nav_ready)

	if build_far_lod:
		far_lod = FarLod.new()
		far_lod.name = "FarLod"
		add_child(far_lod)
		far_lod.setup(plan, seed)

	_initial_phase = true
	streamer.load_now(spawn_position(), initial_radius)
	_initial_phase = false
	if _pending_nav.is_empty():
		_on_unit_nav_ready.call_deferred("")
	generation_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print_verbose("LuthadelWorld: generated in %.0f ms (%d units, %d metals)" % [generation_time_ms, streamer.unit_count(), MetalRegistry.count()])


## Computes marker data for every chunk the plan places markers in, and for
## every landmark (their full data is handed to the streamer to reuse).
func _build_marker_index() -> Array[ChunkBuildData]:
	marker_index = MarkerIndex.new()
	var chunks: Dictionary = {}
	for m: Dictionary in plan.markers:
		var pa: Array = m.get("pos", [0, 0])
		chunks[plan.chunk_of(Vector2(float(pa[0]), float(pa[1])))] = true
	var coords: Array = chunks.keys()
	var layouts: Array = []
	layouts.resize(coords.size())
	var lms: Array[ChunkBuildData] = []
	lms.resize(plan.landmarks.size())
	var p := plan
	var s := seed
	var n_chunks := coords.size()
	var job := func(i: int) -> void:
		if i < n_chunks:
			layouts[i] = ChunkLayout.generate(p, s, coords[i])
		else:
			lms[i - n_chunks] = ChunkGenerator.generate_landmark(p, s, p.landmarks[i - n_chunks])
	var gid := WorkerThreadPool.add_group_task(job, n_chunks + plan.landmarks.size(), -1, true, "marker index")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for i in n_chunks:
		var L: ChunkLayout = layouts[i]
		marker_index.add_unit(ChunkGenerator.chunk_key(L.coord), L.markers)
	for d in lms:
		marker_index.add_unit(d.key, d.markers)
	return lms


func _on_unit_loaded(key: String) -> void:
	var inst := streamer.get_unit(key)
	if inst == null:
		return
	if not marker_index.has_unit(key):
		marker_index.add_unit(key, inst.data.markers)
	if far_lod != null:
		if key.begins_with("c:"):
			far_lod.set_chunk_loaded(inst.data.coord, true)
		else:
			far_lod.set_landmark_loaded(StringName(key.substr(3)), true)
	if _initial_phase:
		_pending_nav[key] = true
	var nodes: Array[Node3D] = []
	if inst.root != null:
		for c in inst.root.get_children():
			if c is Marker3D:
				nodes.append(c)
	unit_loaded.emit(key)
	if not nodes.is_empty():
		markers_spawned.emit(nodes)


func _on_unit_unloaded(key: String) -> void:
	if far_lod != null:
		if key.begins_with("c:"):
			var parts := key.substr(2).split(",")
			far_lod.set_chunk_loaded(Vector2i(int(parts[0]), int(parts[1])), false)
		else:
			far_lod.set_landmark_loaded(StringName(key.substr(3)), false)
	_pending_nav.erase(key)
	unit_unloaded.emit(key)


func _on_unit_nav_ready(key: String) -> void:
	_pending_nav.erase(key)
	if not is_navigation_ready and _pending_nav.is_empty() and _nav_wait_iteration < 0:
		# Wait until the navigation map has synced the new regions.
		_nav_wait_iteration = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) + 2


func _physics_process(_delta: float) -> void:
	if _nav_wait_iteration < 0 or is_navigation_ready:
		return
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) >= _nav_wait_iteration:
		is_navigation_ready = true
		navigation_ready.emit()


# --- Public API -------------------------------------------------------------

## Marker nodes currently in the tree (loaded units) in `group`.
func get_markers(group: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D and is_ancestor_of(n):
			out.append(n)
	return out


## Marker data for `group` across the whole city, loaded or not. Each entry:
## {"group", "position" (Vector3), "pos" (same), "meta" (Dictionary), "unit" (String)}.
func get_marker_data(group: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marker_index == null:
		return out
	for e in marker_index.by_group(group):
		out.append({"group": e["group"], "position": e["pos"], "pos": e["pos"], "meta": e["meta"], "unit": e["unit"]})
	return out


## Position of the (first) player spawn marker.
func spawn_position() -> Vector3:
	if marker_index != null:
		var s: Array[Dictionary] = marker_index.by_group(&"player_spawn")
		if not s.is_empty():
			return s[0]["pos"]
	return Vector3.ZERO


## Axis-aligned bounds of the whole generated city.
func bounds() -> AABB:
	if plan == null:
		return AABB()
	var b := plan.bounds
	return AABB(Vector3(b.position.x, -10.0, b.position.y), Vector3(b.size.x, 420.0, b.size.y))


## Bounds of the vertical-slice district (Skaa quarter -> Keep Venture -> canal).
func slice_bounds() -> AABB:
	if plan == null:
		return AABB()
	var b := plan.slice_bounds
	return AABB(Vector3(b.position.x, -10.0, b.position.y), Vector3(b.size.x, 120.0, b.size.y))


## True if full-detail geometry is resident at `p` (used by the player to
## hold position rather than fall through unloaded ground).
func is_area_loaded(p: Vector3) -> bool:
	return streamer != null and streamer.is_area_loaded(p)


## District type at a world position (e.g. &"skaa_slums", &"noble").
func district_at(p: Vector3) -> StringName:
	return plan.district_at(Vector2(p.x, p.z)) if plan != null else &""


func _exit_tree() -> void:
	if streamer != null:
		streamer.unload_all()
