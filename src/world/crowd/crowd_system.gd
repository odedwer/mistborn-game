class_name CrowdSystem
extends Node3D
## Ambient skaa and obligator pedestrians on the open-world streets.
##
## Pedestrians are cheap *agents*: `CrowdAgent` Node3Ds parented to their
## streamed chunk (like the enemies EnemySpawner parents per chunk), so they
## are freed with it. Each walks back and forth along a sidewalk lane of one of
## the chunk's streets (recomputed from the deterministic `ChunkLayout`),
## pausing at the ends and now and then to talk.
##
## Only the nearest `max_visible` agents within `view_radius` of the camera get
## a `CharacterModel`, taken from a per-kind pool (models are re-dyed/re-dressed
## per agent with `randomize_variant`, so the crowd doesn't look cloned). LOD:
## full-rate animation within `full_anim_radius`, a manually advanced
## AnimationTree at 1/`far_anim_stride` rate beyond it, shadows only within
## `shadow_radius`, and automatic mesh LODs from the importer. Agents beyond
## `sim_radius` don't move at all.
##
## Usage (scenes/game.gd): add as a child of the game scene and call
## `setup(world)` with a `LuthadelWorld`. Tests can call `populate_unit()` and
## `update_crowd()` directly with `focus_override`.

const MODEL_DIR := "res://assets/models/characters/"
const SKAA_KINDS: Array[StringName] = [&"skaa_man", &"skaa_woman"]
const OBLIGATOR_KINDS: Array[StringName] = [&"obligator", &"obligator_2"]
## district type -> [agents per chunk, obligator share]
const DENSITY := {
	&"skaa_slums": [7, 0.08], &"docks": [6, 0.1], &"market": [8, 0.18], &"merchant": [5, 0.25],
	&"noble": [3, 0.4],
}
const DEFAULT_DENSITY := [5, 0.12]

@export var max_visible := 30
@export var view_radius := 70.0
@export var full_anim_radius := 25.0
@export var shadow_radius := 28.0
@export var sim_radius := 110.0
@export var far_anim_stride := 3
## Models created per assignment pass at most (spreads instantiation hitches).
@export var max_new_per_pass := 3
@export var assign_interval := 0.3
## If set (not INF), used instead of the camera position (tests, previews).
var focus_override := Vector3.INF

var world: Node
var plan: CityPlan
var world_seed := 1337

var _agents: Array[CrowdAgent] = []
var _pool: Dictionary = {}  # kind -> Array[CharacterModel] (free, hidden)
var _active: Array[CrowdAgent] = []
var _created := 0
var _pending_units: Array[String] = []
var _assign_t := 0.0
var _frame := 0


## A pedestrian: pure data plus a transform, parented to its chunk's root.
class CrowdAgent:
	extends Node3D
	var kind: StringName = &"skaa_man"
	var variant_seed := 0
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var t := 0.0
	var dir := 1.0
	var speed := 1.2
	var pause := 0.0
	var talk_on_pause := false
	var model: CharacterModel
	var moving := false
	var anim_acc := 0.0


func _init() -> void:
	name = "Crowd"


## Hooks up a LuthadelWorld: populates loaded chunks now and streamed ones later.
func setup(p_world: Node) -> void:
	world = p_world
	if "plan" in world:
		plan = world.plan
	if "seed" in world:
		world_seed = world.seed
	if world.has_signal(&"unit_loaded"):
		world.connect(&"unit_loaded", _on_unit_loaded)
	if "streamer" in world and world.streamer != null:
		for key: String in world.streamer.loaded_keys():
			_pending_units.append(key)


func _on_unit_loaded(key: String) -> void:
	_pending_units.append(key)


## Spawns the agents of chunk `coord` under `root` (the chunk's node). Returns how many.
func populate_unit(root: Node3D, coord: Vector2i) -> int:
	if plan == null or root == null:
		return 0
	var layout := ChunkLayout.generate(plan, world_seed, coord)
	if layout.empty:
		return 0
	var dens: Array = DENSITY.get(layout.district, DEFAULT_DENSITY)
	var lanes := _lanes(layout)
	if lanes.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = CityPlan.hash_ints(world_seed, coord.x, coord.y, 7717)
	var count := int(dens[0])
	for i in count:
		var lane: Array = lanes[rng.randi() % lanes.size()]
		var kind: StringName
		if rng.randf() < float(dens[1]):
			kind = OBLIGATOR_KINDS[rng.randi() % OBLIGATOR_KINDS.size()]
		else:
			kind = SKAA_KINDS[rng.randi() % SKAA_KINDS.size()]
		spawn_agent(root, lane[0], lane[1], kind, rng.randi(), rng.randf())
	return count


## Spawns one pedestrian walking between world points `a` and `b` (y = ground).
func spawn_agent(parent: Node3D, a: Vector3, b: Vector3, kind: StringName, seed_value: int,
		start_t := 0.5) -> CrowdAgent:
	var ag := CrowdAgent.new()
	ag.name = "Pedestrian"
	ag.kind = kind
	ag.variant_seed = seed_value
	ag.a = a
	ag.b = b
	ag.t = start_t
	ag.dir = 1.0 if seed_value % 2 == 0 else -1.0
	var obligator := kind in OBLIGATOR_KINDS
	ag.speed = (0.95 if obligator else 1.15) + float(seed_value % 7) * 0.04
	ag.pause = float(seed_value % 5) * 0.6
	parent.add_child(ag)
	ag.global_position = a.lerp(b, start_t)
	_agents.append(ag)
	return ag


## Sidewalk lanes of a chunk: [a, b] world points along each street, off to one
## side, clipped to the longest stretch that stays out of canals and landmarks.
func _lanes(layout: ChunkLayout) -> Array:
	var out: Array = []
	for st: ChunkLayout.Street in layout.streets:
		if st.length() < 10.0:
			continue
		var d := st.direction()
		var perp := Vector2(-d.y, d.x)
		for side: float in [1.0, -1.0]:
			var off := maxf(st.width * 0.5 - 1.3, 0.8) * side
			var best := Vector2(-1, -1)
			var run_start := -1.0
			var steps := int(st.length() / 2.0)
			for k in steps + 1:
				var f := float(k) / float(steps)
				var p := st.a.lerp(st.b, f) + perp * off
				var ok := layout.rect.grow(-0.5).has_point(p) and not layout._blocked(plan, p)
				if ok and run_start < 0.0:
					run_start = f
				if (not ok or k == steps) and run_start >= 0.0:
					var run_end := f if ok else float(k - 1) / float(steps)
					if run_end - run_start > best.y - best.x:
						best = Vector2(run_start, run_end)
					run_start = -1.0
			if (best.y - best.x) * st.length() >= 8.0:
				var pa := st.a.lerp(st.b, best.x) + perp * off
				var pb := st.a.lerp(st.b, best.y) + perp * off
				out.append([Vector3(pa.x, 0.0, pa.y), Vector3(pb.x, 0.0, pb.y)])
	return out


func _process(delta: float) -> void:
	var live := world == null or not (world is Node3D) or (world as Node3D).is_visible_in_tree()
	visible = live
	if not live:
		return
	if not _pending_units.is_empty():
		_populate_pending()
	update_crowd(delta)


func _populate_pending() -> void:
	# one chunk per frame keeps streaming hitches small
	var key: String = _pending_units.pop_front()
	if not key.begins_with("c:") or world == null or not ("streamer" in world) or world.streamer == null:
		return
	var inst = world.streamer.get_unit(key)
	if inst == null or inst.root == null or not is_instance_valid(inst.root):
		return
	var parts := key.substr(2).split(",")
	populate_unit(inst.root, Vector2i(int(parts[0]), int(parts[1])))


## Moves agents near the focus, reassigns models every `assign_interval` and
## applies animation/shadow LOD. Public so tests can drive it.
func update_crowd(delta: float) -> void:
	_frame += 1
	var focus := _focus()
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = assign_interval
		_assign(focus)
	var i := _agents.size() - 1
	while i >= 0:
		var ag := _agents[i]
		if not is_instance_valid(ag) or not ag.is_inside_tree():
			_agents.remove_at(i)
			i -= 1
			continue
		if ag.global_position.distance_squared_to(focus) < sim_radius * sim_radius:
			_step(ag, delta)
		i -= 1
	for ag in _active:
		if is_instance_valid(ag) and ag.model != null:
			_drive_model(ag, focus, delta)


func _focus() -> Vector3:
	if focus_override != Vector3.INF:
		return focus_override
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	var p := get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null
	return p.global_position if p != null else Vector3.ZERO


func _step(ag: CrowdAgent, delta: float) -> void:
	if ag.pause > 0.0:
		ag.pause -= delta
		ag.moving = false
		return
	var length := maxf(ag.a.distance_to(ag.b), 0.1)
	ag.t += ag.dir * ag.speed * delta / length
	ag.moving = true
	if ag.t >= 1.0 or ag.t <= 0.0:
		ag.t = clampf(ag.t, 0.0, 1.0)
		ag.dir = -ag.dir
		ag.pause = 1.5 + float((ag.variant_seed >> 3) % 5)
		ag.talk_on_pause = (ag.variant_seed + int(ag.t * 10.0) + _frame) % 3 == 0
	elif (ag.variant_seed + _frame) % 2400 == 0:
		ag.pause = 2.0  # stops for a moment mid-street
	ag.global_position = ag.a.lerp(ag.b, ag.t)


func _assign(focus: Vector3) -> void:
	var cands: Array = []
	var r2 := view_radius * view_radius
	for ag in _agents:
		if not is_instance_valid(ag) or not ag.is_inside_tree():
			continue
		var d2 := ag.global_position.distance_squared_to(focus)
		if d2 < r2:
			cands.append([d2, ag])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var wanted: Dictionary = {}
	for k in mini(cands.size(), max_visible):
		wanted[cands[k][1]] = true
	# release models of agents that fell out (or were freed with their chunk)
	var keep: Array[CrowdAgent] = []
	for ag in _active:
		if is_instance_valid(ag) and wanted.has(ag) and ag.model != null:
			keep.append(ag)
		else:
			_release(ag)
	_active = keep
	var budget := max_new_per_pass
	for k in mini(cands.size(), max_visible):
		var ag: CrowdAgent = cands[k][1]
		if ag.model != null:
			continue
		var m := _acquire(ag.kind, budget > 0)
		if m == null:
			continue
		if m.get_meta(&"crowd_new", false):
			budget -= 1
			m.remove_meta(&"crowd_new")
		ag.model = m
		m.randomize_variant(ag.variant_seed)
		m.visible = true
		m.process_mode = Node.PROCESS_MODE_INHERIT
		m.global_transform = ag.global_transform
		_active.append(ag)


func _acquire(kind: StringName, may_create: bool) -> CharacterModel:
	var free: Array = _pool.get(kind, [])
	if not free.is_empty():
		return free.pop_back()
	if not may_create or _created >= max_visible + 8:
		return null
	var ps := load(MODEL_DIR + String(kind) + ".tscn") as PackedScene
	if ps == null:
		return null
	var m := ps.instantiate() as CharacterModel
	m.name = "%s_%d" % [kind, _created]
	m.set_meta(&"crowd_kind", kind)
	m.set_meta(&"crowd_new", true)
	m.cloak_physics = false
	add_child(m)
	_created += 1
	return m


func _release(ag: Variant) -> void:  # untyped: may be an agent freed with its chunk
	if ag == null or not is_instance_valid(ag) or ag.model == null:
		# the agent was freed with its chunk: find its model among ours instead
		_reclaim_orphans()
		return
	_park(ag.model)
	ag.model = null


func _park(m: CharacterModel) -> void:
	m.visible = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	var kind: StringName = m.get_meta(&"crowd_kind", &"skaa_man")
	if not _pool.has(kind):
		_pool[kind] = []
	if not (_pool[kind] as Array).has(m):
		(_pool[kind] as Array).append(m)


## Models whose agent disappeared (chunk unloaded) go back to the pool.
func _reclaim_orphans() -> void:
	var owned: Dictionary = {}
	for ag in _active:
		if is_instance_valid(ag) and ag.model != null:
			owned[ag.model] = true
	for c in get_children():
		if c is CharacterModel and c.visible and not owned.has(c):
			_park(c)


func _drive_model(ag: CrowdAgent, focus: Vector3, delta: float) -> void:
	var m := ag.model
	var p := ag.global_position
	m.global_position = p
	if ag.moving:
		var d := (ag.b - ag.a) * ag.dir
		m.rotation.y = atan2(d.x, d.z)  # CharacterModel roots face +Z
	m.set_locomotion(ag.speed if ag.moving else 0.0, true)
	if not ag.moving and ag.talk_on_pause and not m.is_action_playing():
		ag.talk_on_pause = false
		m.play_action(&"talk")
	var dist := p.distance_to(focus)
	_set_anim_lod(ag, dist < full_anim_radius, delta)
	var shadows := dist < shadow_radius
	if m.get_meta(&"crowd_shadows", true) != shadows:
		m.set_meta(&"crowd_shadows", shadows)
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _set_anim_lod(ag: CrowdAgent, full: bool, delta: float) -> void:
	var tree := ag.model.animation_tree
	if tree == null:
		return
	if full:
		if tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE:
			tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	if tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ag.anim_acc += delta
	if (_frame + ag.variant_seed) % far_anim_stride == 0:
		tree.advance(ag.anim_acc)
		ag.anim_acc = 0.0


# ---------------------------------------------------------------- inspection
func agent_count() -> int:
	return _agents.size()


## Crowd models currently shown.
func visible_count() -> int:
	var n := 0
	for ag in _active:
		if is_instance_valid(ag) and ag.model != null and ag.model.visible:
			n += 1
	return n


func model_count() -> int:
	return _created
