class_name ActivityManager
extends Node
## Runs open-world side activities alongside the main story (group
## "activity_manager"). Each activity is a `ActivityData` (JSON under
## `res://src/mission/activities/data/`) with a start marker in the open
## world ("activity_start" group, meta `activity_id`); walking/flying into
## its trigger starts it. See docs/OPEN_WORLD.md and `Mastery` for rewards.
##
## Three types (see `ActivityData` for the `params` each expects):
## - "coin_race": fly through rings within a time limit. Bronze/silver/gold
##   times from `params.medals`.
## - "rooftop_pursuit": chase a `ThiefRunner` along a precomputed path and
##   get within `params.catch_distance`.
## - "obligator_ambush": a patrol group spawns around the player (via
##   `EnemySpawner.spawn_type` at freshly-created Marker3Ds); defeat them all.
## - "crowd_riot" (Act II): a `CrowdMoodMeter` starts at `params.start_mood`
##   (a riot already boiling over); soothe it (brass) below
##   `params.calm_threshold` within `time_limit` or it fails. See
##   `CrowdMoodMeter`/`CrowdMember`.
##
## Also spawns collectibles (atium beads, crew notes) at "collectible_spawn"
## world markers; `GameState.collect_item`/`is_collected` persist them.
##
## Lifecycle methods below are called both by real 3D triggers/collisions and
## directly by tests, so the logic is exercised without needing physics.
##
## Streaming: start-trigger beacons are parented to their marker's own
## streamed chunk (like `CrowdSystem` pedestrians and the pickups spawned in
## `scenes/game.gd`), so they exist only while that chunk is loaded and are
## rebuilt from `markers_spawned` when it streams back in. `GameState`
## (`activity_records`, `collectibles`) is the actual source of truth for
## progress, not the node, so nothing is lost when a chunk unloads. While an
## activity is *running*, its rings/thief/enemies are parented to the start
## chunk too, but that chunk is pinned (`WorldStreamer.pin`) for the duration
## so it can't unload out from under a race in progress; the pin is released
## in `_cleanup`.

signal activity_started(id: StringName)
signal activity_completed(id: StringName, medal: StringName, elapsed: float)
signal activity_failed(id: StringName, reason: String)
signal collectible_found(id: StringName, kind: StringName)

const TRIGGER_RADIUS := 5.0
const RING_RADIUS := 2.5
const START_COOLDOWN := 2.0

var activities: Dictionary = {}   # StringName -> ActivityData
## Running state per activity id: {type, elapsed, nodes: Array, ...}
var _active: Dictionary = {}
var _cooldowns: Dictionary = {}   # StringName -> seconds remaining
var _start_triggers: Array[Area3D] = []
var _collectible_nodes: Dictionary = {}  # collectible id (String) -> Node3D
var _spawned_collectible_keys: Dictionary = {}


func _ready() -> void:
	add_to_group(&"activity_manager")
	for a in ActivityData.load_all():
		activities[a.id] = a
	# `_build_start_triggers`/`_spawn_collectibles` add nodes under the tree
	# root; deferred because the caller (game.gd's _ready) may still be busy
	# adding its own children when this runs.
	_build_start_triggers.call_deferred()
	_spawn_collectibles.call_deferred(get_tree().get_nodes_in_group(&"collectible_spawn"))
	var world := _find_world_node()
	if world != null and world.has_signal(&"markers_spawned"):
		world.connect(&"markers_spawned", _on_markers_spawned)
	TimeOfDay.phase_changed.connect(_on_phase_changed)


## True if `id`'s required phase (`ActivityData.phase`) matches the clock.
func is_available_now(id: StringName) -> bool:
	var a: ActivityData = activities.get(id)
	return a != null and TimeOfDay.allows(a.phase)


func _on_phase_changed(_phase: int) -> void:
	for area in _start_triggers:
		if is_instance_valid(area):
			_refresh_beacon(area)


## Phase-gated activities hide their beacon outside their phase.
func _refresh_beacon(area: Area3D) -> void:
	var aid: StringName = area.get_meta(&"activity_id", &"")
	for c in area.get_children():
		if c is ActivityBeacon:
			(c as Node3D).visible = is_available_now(aid)


func _exit_tree() -> void:
	for a in _start_triggers:
		if is_instance_valid(a):
			a.queue_free()
	for id: StringName in _active.keys():
		for n in _active[id].get("nodes", []):
			if is_instance_valid(n):
				n.queue_free()
	for cid in _collectible_nodes:
		var n = _collectible_nodes[cid]
		if is_instance_valid(n):
			n.queue_free()


func _physics_process(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)
	if _active.is_empty():
		return
	var player := get_tree().get_first_node_in_group(&"player")
	var player_pos: Vector3 = (player as Node3D).global_position if player is Node3D else Vector3.INF
	for id: StringName in _active.keys().duplicate():
		_tick_activity(id, delta, player_pos)


# --- Discovery ----------------------------------------------------------------

func _find_world_node() -> Node:
	return get_tree().get_first_node_in_group(&"world")


## The chunk key + node containing `pos`, if that chunk is loaded (streaming
## world) — else [`""`, `null`], so callers fall back to the tree root.
func _chunk_at(pos: Vector3) -> Array:
	var world := _find_world_node()
	if world == null or not ("plan" in world) or world.plan == null or not ("streamer" in world) or world.streamer == null:
		return ["", null]
	var key: String = ChunkGenerator.chunk_key(world.plan.chunk_of(Vector2(pos.x, pos.z)))
	var inst = world.streamer.get_unit(key)
	if inst == null or inst.root == null or not is_instance_valid(inst.root):
		return ["", null]
	return [key, inst.root]


## Parent node for a start/runtime node at `pos`: the owning chunk if loaded
## (so it streams and unloads with it), else the tree root as a fallback
## (tests, or a marker whose chunk isn't resident).
func _activity_parent(pos: Vector3) -> Node:
	var found: Array = _chunk_at(pos)
	return found[1] if found[1] != null else get_tree().root


## Keeps the chunk under `pos` loaded for the lifetime of a running activity
## (a race/ambush in progress must not have its start chunk stream out from
## under it). Returns the pinned key, or "" if there was nothing to pin.
func _pin_chunk(pos: Vector3) -> String:
	var world := _find_world_node()
	var found: Array = _chunk_at(pos)
	var key: String = found[0]
	if key != "" and world != null and "streamer" in world and world.streamer != null:
		world.streamer.pin(key)
		return key
	return ""


func _unpin_chunk(key: String) -> void:
	if key == "":
		return
	var world := _find_world_node()
	if world != null and "streamer" in world and world.streamer != null:
		world.streamer.unpin(key)


func _on_markers_spawned(nodes: Array) -> void:
	var starts: Array = []
	var collectibles: Array = []
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n.is_in_group(&"activity_start"):
			starts.append(n)
		elif n.is_in_group(&"collectible_spawn"):
			collectibles.append(n)
	for m in starts:
		_add_trigger_for_marker(m)
	_spawn_collectibles(collectibles)
	# Beacons are freed with their chunk (they're parented to it); drop the
	# stale references so `_start_triggers` doesn't grow forever as chunks
	# stream in and out.
	var live: Array[Area3D] = []
	for a in _start_triggers:
		if is_instance_valid(a):
			live.append(a)
	_start_triggers = live


func _build_start_triggers() -> void:
	# Only for chunks already resident at startup (near spawn); everywhere
	# else, a beacon is built when its chunk streams in (`_on_markers_spawned`)
	# and freed with it when it streams back out — `start_marker_position`
	# still resolves a citywide position via the marker index either way, so
	# the map/journal can point at an activity that isn't loaded right now.
	for m in get_tree().get_nodes_in_group(&"activity_start"):
		_add_trigger_for_marker(m)


func _add_trigger_for_marker(marker: Node) -> void:
	if not (marker is Node3D):
		return
	var aid: StringName = marker.get_meta("activity_id", &"")
	if aid == &"" or not activities.has(aid):
		return
	var pos := (marker as Node3D).global_position
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1  # "player" physics layer
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	area.add_child(shape)
	# Streams with the marker's own chunk (see the class doc comment), instead
	# of living forever under the tree root.
	var parent: Node = marker.get_parent() if marker.get_parent() != null else get_tree().root
	parent.add_child(area)
	area.global_position = pos
	area.body_entered.connect(_on_trigger_entered.bind(aid))
	area.set_meta(&"activity_id", aid)
	_start_triggers.append(area)
	var beacon := ActivityBeacon.new()
	area.add_child(beacon)
	beacon.position = Vector3.ZERO
	_refresh_beacon(area)


func _on_trigger_entered(body: Node, id: StringName) -> void:
	if body.is_in_group(&"player"):
		start_activity(id)


# --- Lifecycle ------------------------------------------------------------

func is_running(id: StringName) -> bool:
	return _active.has(id)


## Starts `id` if it isn't already running or cooling down. Returns true if
## it started. `override_pos` skips the marker lookup (used by tests, and by
## anything that already knows the start position).
func start_activity(id: StringName, override_pos: Vector3 = Vector3.INF) -> bool:
	if not activities.has(id) or is_running(id) or float(_cooldowns.get(id, 0.0)) > 0.0:
		return false
	var a: ActivityData = activities[id]
	if not TimeOfDay.allows(a.phase):
		_cooldowns[id] = START_COOLDOWN
		Events.hint_requested.emit("%s — only after nightfall." % a.title if a.phase == "night" else "%s — only by day." % a.title, 3.0)
		return false
	var pos := override_pos if override_pos != Vector3.INF else _marker_position(&"activity_start", id)
	if pos == Vector3.INF:
		return false
	match String(a.type):
		"coin_race":
			_start_coin_race(a, pos)
		"rooftop_pursuit":
			_start_pursuit(a, pos)
		"obligator_ambush":
			_start_ambush(a, pos)
		"crowd_riot":
			_start_crowd_riot(a, pos)
		_:
			return false
	# Pin the start chunk for the duration: its nodes are parented to it (see
	# `_activity_parent`), and it must not stream out mid-activity.
	_active[id]["pin_key"] = _pin_chunk(pos)
	Events.hint_requested.emit(a.title, 3.0)
	activity_started.emit(id)
	return true


func _tick_activity(id: StringName, delta: float, player_pos: Vector3) -> void:
	var st: Dictionary = _active[id]
	st["elapsed"] = float(st.get("elapsed", 0.0)) + delta
	var a: ActivityData = activities[id]
	var limit := float(a.params.get("time_limit", -1.0))
	match String(a.type):
		"rooftop_pursuit":
			var thief: Node3D = st.get("thief")
			if thief != null and is_instance_valid(thief) and player_pos != Vector3.INF:
				if player_pos.distance_to(thief.global_position) <= float(a.params.get("catch_distance", 2.5)):
					complete_activity(id)
					return
				if thief.has_method("reached_end") and thief.call("reached_end"):
					fail_activity(id, "thief_escaped")
					return
		"crowd_riot":
			var meter: Node = st.get("meter")
			if meter != null and is_instance_valid(meter):
				var threshold := float(a.params.get("calm_threshold", 25.0))
				if float(meter.get("mood")) <= threshold:
					complete_activity(id)
					return
	if limit > 0.0 and float(st["elapsed"]) >= limit:
		fail_activity(id, "time_up")


## Completes `id` successfully with the medal computed from elapsed time (or
## &"" if the activity has no time medals, e.g. an ambush).
func complete_activity(id: StringName) -> void:
	if not is_running(id):
		return
	var st: Dictionary = _active[id]
	var a: ActivityData = activities[id]
	var elapsed: float = st.get("elapsed", 0.0)
	var medal := medal_for_time(id, elapsed)
	GameState.record_activity_result(id, true, elapsed, medal, a.rewards)
	activity_completed.emit(id, medal, elapsed)
	var suffix := " — %s medal!" % String(medal).capitalize() if medal != &"" else " — complete!"
	Events.hint_requested.emit(a.title + suffix, 3.0)
	_cleanup(id)


func fail_activity(id: StringName, reason: String) -> void:
	if not is_running(id):
		return
	var a: ActivityData = activities[id]
	GameState.record_activity_result(id, false, 0.0, &"", {})
	activity_failed.emit(id, reason)
	Events.hint_requested.emit(a.title + " — failed.", 3.0)
	_cleanup(id)


## Bronze/silver/gold from `params.medals` (seconds, lower = better), or &""
## if the activity has none or none was reached.
func medal_for_time(id: StringName, elapsed: float) -> StringName:
	var a: ActivityData = activities.get(id)
	if a == null:
		return &""
	var medals: Dictionary = a.params.get("medals", {})
	if medals.is_empty():
		return &""
	if medals.has("gold") and elapsed <= float(medals["gold"]):
		return &"gold"
	if medals.has("silver") and elapsed <= float(medals["silver"]):
		return &"silver"
	if medals.has("bronze") and elapsed <= float(medals["bronze"]):
		return &"bronze"
	return &""


func _cleanup(id: StringName) -> void:
	var st: Dictionary = _active.get(id, {})
	for n in st.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	_unpin_chunk(str(st.get("pin_key", "")))
	_active.erase(id)
	_cooldowns[id] = START_COOLDOWN


# --- Coin race --------------------------------------------------------------

func _start_coin_race(a: ActivityData, start_pos: Vector3) -> void:
	var offsets: Array = a.params.get("ring_offsets", [])
	var rings: Array[Node3D] = []
	var nodes: Array = []
	var parent := _activity_parent(start_pos)
	for off: Array in offsets:
		var pos := start_pos + Vector3(float(off[0]), float(off[1]), float(off[2]))
		var ring := _make_ring(pos, parent)
		nodes.append(ring)
		rings.append(ring)
	_active[a.id] = {"type": "coin_race", "elapsed": 0.0, "nodes": nodes, "ring_index": 0, "rings": rings}
	for i in rings.size():
		var area := rings[i] as Area3D
		area.body_entered.connect(_on_ring_entered.bind(a.id, i))


func _make_ring(pos: Vector3, parent: Node) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RING_RADIUS
	shape.shape = sphere
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.35
	torus.outer_radius = RING_RADIUS
	mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.85, 0.4)
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	area.add_child(mesh)
	parent.add_child(area)
	area.global_position = pos
	return area


func _on_ring_entered(body: Node, id: StringName, ring_index: int) -> void:
	if not body.is_in_group(&"player") or not is_running(id):
		return
	var st: Dictionary = _active[id]
	if st.get("type") != "coin_race" or int(st.get("ring_index", 0)) != ring_index:
		return
	st["ring_index"] = ring_index + 1
	var rings: Array = st.get("rings", [])
	if is_instance_valid(rings[ring_index]):
		(rings[ring_index] as Node3D).visible = false
	if int(st["ring_index"]) >= rings.size():
		complete_activity(id)


# --- Rooftop pursuit ----------------------------------------------------------

func _start_pursuit(a: ActivityData, start_pos: Vector3) -> void:
	var offsets: Array = a.params.get("path_offsets", [[0, 0, 0]])
	var path := PackedVector3Array()
	for off: Array in offsets:
		path.append(start_pos + Vector3(float(off[0]), float(off[1]), float(off[2])))
	var thief := ThiefRunner.new()
	thief.speed = float(a.params.get("thief_speed", 6.0))
	thief.path = path
	_activity_parent(start_pos).add_child(thief)
	thief.global_position = path[0] if not path.is_empty() else start_pos
	_active[a.id] = {"type": "rooftop_pursuit", "elapsed": 0.0, "nodes": [thief], "thief": thief}


# --- Obligator ambush ---------------------------------------------------------

func _start_ambush(a: ActivityData, start_pos: Vector3) -> void:
	var types: Array = a.params.get("enemy_types", [&"guard", &"guard"])
	var radius := float(a.params.get("spawn_radius", 8.0))
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner")
	var spawned: Array = []
	var nodes: Array = []
	var parent := _activity_parent(start_pos)
	if spawner != null and spawner.has_method("spawn_type"):
		for i in types.size():
			var ang := TAU * float(i) / maxf(float(types.size()), 1.0)
			var pos := start_pos + Vector3(cos(ang), 0.0, sin(ang)) * radius
			var marker := Marker3D.new()
			parent.add_child(marker)
			marker.global_position = pos
			var enemy: Node = spawner.call("spawn_type", StringName(types[i]), marker)
			marker.queue_free()
			# spawn_type hands back the enemy already alive at a marker, so the
			# same enemy can come back twice (or from an earlier run of this
			# ambush). Count and wire each one once, or the ambush can't complete.
			if enemy != null and not spawned.has(enemy):
				spawned.append(enemy)
				nodes.append(enemy)
				var health := Health.find_on(enemy)
				var on_died := _on_ambush_enemy_died.bind(a.id, enemy)
				if health != null and not health.died.is_connected(on_died):
					health.died.connect(on_died)
	_active[a.id] = {"type": "obligator_ambush", "elapsed": 0.0, "nodes": nodes, "alive": spawned}


func _on_ambush_enemy_died(_killer: Node, id: StringName, enemy: Node) -> void:
	if not is_running(id):
		return
	var st: Dictionary = _active[id]
	var alive: Array = st.get("alive", [])
	alive.erase(enemy)
	st["alive"] = alive
	if alive.is_empty():
		complete_activity(id)


# --- Crowd riot (Act II) -----------------------------------------------------

func _start_crowd_riot(a: ActivityData, start_pos: Vector3) -> void:
	var parent := _activity_parent(start_pos)
	var meter := CrowdMoodMeter.new()
	# A riot in progress: no drift back to "neutral" here, it either gets
	# soothed down for good or stays boiling until the time limit runs out.
	meter.drift_per_sec = 0.0
	parent.add_child(meter)
	meter.mood = float(a.params.get("start_mood", 80.0))
	var nodes: Array = [meter]
	var count := int(a.params.get("member_count", 5))
	var radius := float(a.params.get("spawn_radius", 6.0))
	for i in count:
		var member := CrowdMember.new()
		var ang := TAU * float(i) / maxf(float(count), 1.0)
		# Placed before entering the tree, so it never spends a frame at the
		# parent's origin.
		var at := start_pos + Vector3(cos(ang), 0.0, sin(ang)) * radius
		member.position = (parent as Node3D).to_local(at) if parent is Node3D else at
		parent.add_child(member)
		nodes.append(member)
	_active[a.id] = {"type": "crowd_riot", "elapsed": 0.0, "nodes": nodes, "meter": meter}


# --- Collectibles ---------------------------------------------------------

func _spawn_collectibles(markers: Array) -> void:
	for m in markers:
		if not (m is Node3D) or not is_instance_valid(m):
			continue
		var cid: String = str(m.get_meta("collectible_id", ""))
		if cid == "" or GameState.is_collected(StringName(cid)) or _spawned_collectible_keys.has(cid):
			continue
		var kind: StringName = m.get_meta("collectible_kind", &"atium_bead")
		var node := _make_collectible_visual(kind)
		var parent: Node = m.get_parent() if m.get_parent() != null else self
		parent.add_child(node)
		(node as Node3D).global_position = (m as Node3D).global_position
		node.add_to_group(&"collectible")
		node.set_meta("collectible_id", cid)
		(node as Area3D).body_entered.connect(_on_collectible_entered.bind(cid, kind))
		_spawned_collectible_keys[cid] = true
		_collectible_nodes[cid] = node


func _make_collectible_visual(kind: StringName) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 1 << 5
	area.collision_mask = 1 << 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	shape.position.y = 0.6
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.22
	m.height = 0.44
	mesh.mesh = m
	mesh.position.y = 0.6
	var color := Color(1.0, 0.95, 0.75) if kind == &"atium_bead" else Color(0.8, 0.7, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mesh.material_override = mat
	area.add_child(mesh)
	return area


func _on_collectible_entered(body: Node, cid: String, kind: StringName) -> void:
	if not body.is_in_group(&"player"):
		return
	if not GameState.collect_item(StringName(cid)):
		return
	collectible_found.emit(StringName(cid), kind)
	Events.pickup_collected.emit(kind, 1.0)
	var node: Node = _collectible_nodes.get(cid)
	if node != null and is_instance_valid(node):
		node.queue_free()


# --- Helpers ------------------------------------------------------------------

## World position of activity `id`'s start marker (used by the map/journal to
## place its icon and set a waypoint), city-wide even if unloaded.
func start_marker_position(id: StringName) -> Vector3:
	return _marker_position(&"activity_start", id)


## World position of collectible `id`'s marker, city-wide even if unloaded
## (works after the collectible itself has been picked up and freed).
func collectible_marker_position(id: StringName) -> Vector3:
	return _marker_position_by_key(&"collectible_spawn", &"collectible_id", id)


func _marker_position(group: StringName, id: StringName) -> Vector3:
	return _marker_position_by_key(group, &"activity_id", id)


func _marker_position_by_key(group: StringName, meta_key: StringName, id: StringName) -> Vector3:
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D and str(n.get_meta(meta_key, "")) == String(id):
			return (n as Node3D).global_position
	var world := _find_world_node()
	if world != null and world.has_method("get_marker_data"):
		for entry: Dictionary in world.call("get_marker_data", group):
			var meta: Dictionary = entry.get("meta", {})
			if str(meta.get(meta_key, "")) == String(id):
				return entry.get("position", Vector3.INF)
	return Vector3.INF
