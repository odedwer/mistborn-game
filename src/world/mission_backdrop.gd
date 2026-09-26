class_name MissionBackdrop
extends Node3D
## Reusable night sky and far skyline for isolated mission scenes (rooftop
## chases, Fountain Square, the battlefield outside the walls, the throne
## room's open gallery), so they stop rendering against a flat black void.
##
## It reuses the open world's own pieces rather than faking a skyline:
## - `EnvironmentBuilder.build` supplies the WorldEnvironment (ash-overcast
##   night sky shader, Ashmounts, moon, fog, glow). It is added to group
##   `"world_environment"` so `GameSettings` presets apply to it too.
## - A `FarLod`, restricted to the superchunks within `skyline_radius` of
##   `anchor` (plus every landmark silhouette), provides the actual Luthadel
##   skyline: the same merged far meshes and lit-window shader the streamed
##   city uses. Chunks within `clear_radius` of the anchor are masked out
##   (the shader's "loaded" mask), so the far city never pokes through the
##   mission's own hand-built geometry.
##
## `anchor` is where in the city plan (XZ, metres) the mission scene sits;
## the scene's local origin maps onto it, with `ground_y` the height of the
## city streets relative to the scene (negative for a rooftop scene, whose
## floor is a roof several storeys up).
##
## Usage (from an interior's `_ready`):
##     var bd := MissionBackdrop.new()
##     bd.anchor = Vector2(-250, -500)   # Fountain Square
##     add_child(bd)

## Plan-space XZ the mission scene's origin stands in for.
@export var anchor := Vector2.ZERO
## City street level relative to the scene origin.
@export var ground_y := 0.0
## Superchunks further than this from the anchor are skipped (cost cap).
@export var skyline_radius := 900.0
## Chunks within this radius of the anchor are discarded by the far shader.
@export var clear_radius := 90.0
@export var build_skyline := true
## Hide these landmarks' far silhouettes (e.g. Kredik Shaw when the scene
## *is* Kredik Shaw).
@export var hide_landmarks: Array[StringName] = []
## Exponential depth fog override (<0 keeps EnvironmentBuilder's default).
## Lower = the far skyline reads more clearly.
@export var fog_density := 0.0028
@export var seed_value := 1337
## Volumetric haze density. The open city's mist look (lanterns haloed in
## fog) at the default; lower it for scenes that are mostly roofed halls.
@export var volumetric_density := 0.008

var environment: Environment
var world_env: WorldEnvironment
var moon: DirectionalLight3D
var far_lod: FarLod
var plan: CityPlan


func _ready() -> void:
	add_to_group(&"mission_backdrop")
	name = "MissionBackdrop"
	var env := EnvironmentBuilder.build(self)
	environment = env["environment"]
	world_env = env["world_env"]
	moon = env["moon"]
	world_env.add_to_group(&"world_environment")
	if fog_density >= 0.0:
		environment.fog_density = fog_density
	# The mission scenes are small; keep the volumetric haze light so their
	# own lanterns still carry.
	environment.volumetric_fog_density = volumetric_density
	_build_ground()
	if build_skyline:
		_build_skyline()


## A dark street-level ground under the masked-out clear zone, so looking
## down off a rooftop scene shows soot-dark streets rather than the void.
func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "BackdropGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(clear_radius * 2.6, clear_radius * 2.6)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.068, 0.066)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, ground_y - 0.1, 0)
	add_child(mi)


func _build_skyline() -> void:
	plan = CityPlan.load_from_file()
	if plan == null:
		return
	far_lod = FarLod.new()
	far_lod.name = "FarSkyline"
	far_lod.max_tasks = 3
	var offset := Vector3(-anchor.x, ground_y, -anchor.y)
	far_lod.position = offset
	add_child(far_lod)
	far_lod.setup(plan, seed_value)
	# Keep only nearby superchunks (and every landmark).
	var kept: Array = []
	var span := plan.chunk_size * FarLod.SUPER
	for job: Dictionary in far_lod._queue:
		if job.has("super"):
			var sc: Vector2i = job["super"]
			var centre := (Vector2(sc) + Vector2(0.5, 0.5)) * span
			if centre.distance_to(anchor) > skyline_radius + span * 0.71:
				continue
		kept.append(job)
	far_lod._queue = kept
	# The far shader's mask is in world space; shift it by our offset.
	var rng := plan.chunk_range()
	far_lod.material.set_shader_parameter("mask_origin", Vector2(rng.position) * plan.chunk_size + Vector2(offset.x, offset.z))
	for cx in range(rng.position.x, rng.end.x):
		for cz in range(rng.position.y, rng.end.y):
			var r := plan.chunk_rect(Vector2i(cx, cz))
			var nearest := Vector2(clampf(anchor.x, r.position.x, r.end.x), clampf(anchor.y, r.position.y, r.end.y))
			if nearest.distance_to(anchor) < clear_radius:
				far_lod.set_chunk_loaded(Vector2i(cx, cz), true)
	for id in hide_landmarks:
		far_lod.set_landmark_loaded(id, true)


## Number of skyline jobs (landmarks + superchunks) this backdrop will build.
func skyline_job_count() -> int:
	if far_lod == null:
		return 0
	return far_lod._queue.size() + far_lod._tasks.size() + far_lod.built_meshes


## Blocks until every skyline mesh is built (screenshots, tests).
func finish_now() -> void:
	if far_lod == null:
		return
	while not far_lod.is_complete():
		far_lod._process(0.0)
		OS.delay_msec(1)
