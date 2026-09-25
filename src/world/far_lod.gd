class_name FarLod
extends Node3D
## Far-LOD skyline for the whole city, so buildings, the city wall, the keeps
## and Kredik Shaw are always visible beyond the streamed radius.
##
## Built in the background (WorkerThreadPool) from the same deterministic
## ChunkLayout data: one merged mesh per "superchunk" (4x4 chunks) of plain
## building boxes and roofs, plus one silhouette per landmark. A tiny
## loaded-chunk mask texture lets the shader discard far geometry wherever
## the full-detail chunk is resident; landmark silhouettes hide while their
## full version is loaded.

const SUPER := 4
const M := WorldMaterials.Mat

@export var max_tasks := 2

var plan: CityPlan
var seed_value := 0
var material: ShaderMaterial
var _mask_img: Image
var _mask_tex: ImageTexture
var _range: Rect2i
var _queue: Array = []          # pending job descriptors
var _tasks: Dictionary = {}     # job key -> task id
var _results: Dictionary = {}   # job key -> Array (mesh arrays) or null
var _mutex := Mutex.new()
var _landmark_nodes: Dictionary = {}   # landmark id -> MeshInstance3D
var _landmark_loaded: Dictionary = {}  # landmark id -> bool
var _mask_dirty := false
var built_meshes := 0


func setup(p_plan: CityPlan, p_seed: int) -> void:
	plan = p_plan
	seed_value = p_seed
	_range = plan.chunk_range()
	_mask_img = Image.create(_range.size.x, _range.size.y, false, Image.FORMAT_R8)
	_mask_img.fill(Color(0, 0, 0))
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/far_silhouette.gdshader") as Shader
	material.set_shader_parameter("loaded_mask", _mask_tex)
	material.set_shader_parameter("mask_origin", Vector2(_range.position) * plan.chunk_size)
	material.set_shader_parameter("mask_cells", Vector2(_range.size))
	material.set_shader_parameter("chunk_size", plan.chunk_size)
	# Landmarks first (they dominate the skyline), then superchunks.
	for lm in plan.landmarks:
		_queue.append({"key": "lm:%s" % lm.id, "landmark": lm})
	var sx0 := floori(float(_range.position.x) / SUPER)
	var sz0 := floori(float(_range.position.y) / SUPER)
	var sx1 := floori(float(_range.end.x - 1) / SUPER)
	var sz1 := floori(float(_range.end.y - 1) / SUPER)
	var supers: Array = []
	for sx in range(sx0, sx1 + 1):
		for sz in range(sz0, sz1 + 1):
			supers.append(Vector2i(sx, sz))
	# Nearest to the origin (the slice) first.
	supers.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).length_squared() < Vector2(b).length_squared())
	for s: Vector2i in supers:
		_queue.append({"key": "s:%d,%d" % [s.x, s.y], "super": s})


## Marks a chunk as streamed in/out (updates the discard mask).
func set_chunk_loaded(c: Vector2i, loaded: bool) -> void:
	if _mask_img == null:
		return
	var p := c - _range.position
	if p.x < 0 or p.y < 0 or p.x >= _range.size.x or p.y >= _range.size.y:
		return
	_mask_img.set_pixel(p.x, p.y, Color(1, 1, 1) if loaded else Color(0, 0, 0))
	_mask_dirty = true


func set_landmark_loaded(id: StringName, loaded: bool) -> void:
	_landmark_loaded[id] = loaded
	var n: MeshInstance3D = _landmark_nodes.get(id)
	if n != null:
		n.visible = not loaded


func is_complete() -> bool:
	return _queue.is_empty() and _tasks.is_empty()


func _process(_delta: float) -> void:
	if _mask_dirty:
		_mask_dirty = false
		_mask_tex.update(_mask_img)
	while _tasks.size() < max_tasks and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		_start(job)
	for k: String in _tasks.keys():
		if not WorkerThreadPool.is_task_completed(_tasks[k]):
			continue
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_tasks.erase(k)
		_mutex.lock()
		var arrays: Variant = _results.get(k)
		_results.erase(k)
		_mutex.unlock()
		if arrays != null:
			_add_mesh(k, arrays as Array)


func _start(job: Dictionary) -> void:
	var key: String = job["key"]
	var p := plan
	var s := seed_value
	var results := _results
	var mutex := _mutex
	var task := func() -> void:
		var b: WorldMeshBuilder
		if job.has("landmark"):
			b = FarLod.build_landmark(p, s, job["landmark"])
		else:
			b = FarLod.build_super(p, s, job["super"])
		var out: Variant = null if b.is_empty() else b.to_arrays()
		mutex.lock()
		results[key] = out
		mutex.unlock()
	_tasks[key] = WorkerThreadPool.add_task(task, false, "far %s" % key)


func _add_mesh(key: String, arrays: Array) -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = key.replace(":", "_").replace(",", "_").replace("-", "m")
	add_child(mi)
	built_meshes += 1
	if key.begins_with("lm:"):
		var id := StringName(key.substr(3))
		_landmark_nodes[id] = mi
		# Landmark silhouettes never use the chunk mask (they tower above it).
		var own := material.duplicate() as ShaderMaterial
		own.set_shader_parameter("use_mask", false)
		mi.material_override = own
		mi.visible = not _landmark_loaded.get(id, false)


## Appends `src` into `dst` with vertex alpha forced to `alpha` (window density).
static func _merge(dst: WorldMeshBuilder, src: WorldMeshBuilder, alpha: float) -> void:
	var base := dst.colors.size()
	dst.append_builder(src)
	for i in range(base, dst.colors.size()):
		var c := dst.colors[i]
		c.a = alpha
		dst.colors[i] = c


## Far geometry for a 4x4 block of chunks (thread-safe).
static func build_super(p: CityPlan, s: int, sc: Vector2i) -> WorldMeshBuilder:
	var b := WorldMeshBuilder.new()
	var rng := p.chunk_range()
	for dx in SUPER:
		for dz in SUPER:
			var c := Vector2i(sc.x * SUPER + dx, sc.y * SUPER + dz)
			if not rng.has_point(c):
				continue
			var rect := p.chunk_rect(c)
			var ground := Color(0.35, 0.35, 0.36, 0.0)
			b.add_quad(Vector3(rect.position.x, -0.05, rect.end.y), Vector3(rect.end.x, -0.05, rect.end.y),
					Vector3(rect.end.x, -0.05, rect.position.y), Vector3(rect.position.x, -0.05, rect.position.y),
					Vector3.UP, ground, ground)
			var L := ChunkLayout.generate(p, s, c)
			for lot in L.lots:
				var cols := BuildingBuilder.wall_colors(lot)
				var col := cols[1]
				col.a = 1.0
				var top := col * 0.6
				top.a = 0.0
				var lo := Vector3(lot.rect.position.x, 0, lot.rect.position.y)
				var hi := Vector3(lot.rect.end.x, lot.height, lot.rect.end.y)
				b.add_box(lo, hi, Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 1.0), col, top)
				if lot.roof != ChunkLayout.Roof.FLAT:
					var rc := Color(0.45, 0.47, 0.52, 0.0)
					b.add_gable_roof(lot.rect.position, lot.rect.end, lot.height, lot.roof_rise(),
							lot.roof == ChunkLayout.Roof.GABLE_X, 0.3, rc, b, Color(col.r, col.g, col.b, 0.0))
			var tmp := ChunkBuildData.new()
			CityWallBuilder.build(tmp, p, rect)
			for k: int in tmp.builders:
				_merge(b, tmp.builders[k], 0.0)
	return b


## Far silhouette of a landmark (all main geometry merged).
static func build_landmark(p: CityPlan, s: int, lm: CityPlan.Landmark) -> WorldMeshBuilder:
	var b := WorldMeshBuilder.new()
	var data := LandmarkBuilder.build(p, s, lm)
	for k: int in data.builders:
		if k == M.WATER:
			continue
		_merge(b, data.builders[k], 0.35)
	return b


func _exit_tree() -> void:
	for k: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()
