class_name EnemySpawner
extends Node
## Instantiates enemies at every "enemy_spawn" marker in a world, keyed by
## the marker's `enemy_type` meta. The Inquisitor can be deferred until a
## mission objective completes (default: &"ledger"), matching the vertical
## slice's pacing.

const TYPE_SCENES := {
	&"guard": "res://src/enemies/guard.tscn",
	&"hazekiller": "res://src/enemies/hazekiller.tscn",
	&"thug": "res://src/enemies/thug.tscn",
	&"coinshot": "res://src/enemies/coinshot.tscn",
	&"inquisitor": "res://src/enemies/inquisitor.tscn",
	&"seeker": "res://src/enemies/seeker.tscn",
}

@export var defer_inquisitor: bool = true
@export var defer_objective_id: StringName = &"ledger"

var world_root: Node
var _spawned: Array[Node] = []
## Marker keys (see `marker_key`) whose enemy is currently alive.
var _alive_keys: Dictionary = {}
## Marker keys whose enemy was killed: never respawned when the chunk reloads.
var _killed_keys: Dictionary = {}
var _pending_inquisitor_markers: Array[Marker3D] = []
var _objective_unlocked: bool = false


func _ready() -> void:
	Events.objective_updated.connect(_on_objective_updated)


## Spawns one enemy per "enemy_spawn" marker found under `root`'s tree.
func spawn_all(root: Node) -> void:
	world_root = root
	for m in root.get_tree().get_nodes_in_group(&"enemy_spawn"):
		var marker := m as Marker3D
		if marker == null:
			continue
		if not root.is_ancestor_of(marker):
			continue
		spawn_for_marker(marker)


## Spawns the enemy for one marker, unless it is already alive or was killed.
## Called for every marker when a streamed world chunk loads. The enemy is
## parented to the marker's chunk, so it is freed (and later respawned) along
## with the chunk; killed enemies stay dead.
func spawn_for_marker(marker: Marker3D) -> Node:
	var key := marker_key(marker)
	if _alive_keys.has(key) or _killed_keys.has(key):
		return null
	var etype: StringName = marker.get_meta("enemy_type", &"guard")
	if etype == &"inquisitor" and defer_inquisitor and not _objective_unlocked:
		if not _pending_inquisitor_markers.has(marker):
			_pending_inquisitor_markers.append(marker)
		return null
	return _spawn_at(marker, etype)


## Stable identity for a marker across chunk reloads (the node is recreated,
## its position is deterministic).
static func marker_key(marker: Node3D) -> Vector3i:
	return Vector3i((marker.global_position * 4.0).round())


## Spawns a single enemy of `etype` immediately (bypasses deferral). With no
## marker, uses a deferred marker of that type, else a loaded enemy_spawn
## marker of that type. Returns the existing enemy if that marker's enemy is
## already alive, so a mission script and the spawner's own objective hook
## can't spawn duplicates.
func spawn_type(etype: StringName, at: Marker3D = null) -> Node:
	if at == null:
		at = _find_marker_for_type(etype)
	if at == null:
		push_warning("EnemySpawner: no loaded marker for '%s'" % etype)
		return null
	var key := marker_key(at)
	if _alive_keys.has(key):
		return _alive_keys[key]
	_pending_inquisitor_markers.erase(at)
	return _spawn_at(at, etype)


func _find_marker_for_type(etype: StringName) -> Marker3D:
	for m in _pending_inquisitor_markers:
		if is_instance_valid(m) and m.get_meta("enemy_type", &"") == etype:
			return m
	var tree := get_tree() if is_inside_tree() else null
	if tree == null:
		return null
	for m in tree.get_nodes_in_group(&"enemy_spawn"):
		if m is Marker3D and m.get_meta("enemy_type", &"") == etype:
			return m
	return null


func _spawn_at(marker: Marker3D, etype: StringName) -> Node:
	var path: String = TYPE_SCENES.get(etype, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("EnemySpawner: unknown enemy_type '%s'" % etype)
		return null
	var scene: PackedScene = load(path)
	var enemy := scene.instantiate()
	# Parent to the marker's chunk so the enemy streams out with its ground.
	var parent: Node = marker.get_parent()
	if parent == null:
		parent = world_root if world_root else marker.get_tree().current_scene
	parent.add_child(enemy)
	var key := marker_key(marker)
	_alive_keys[key] = enemy
	enemy.tree_exiting.connect(_on_enemy_exiting.bind(key, enemy))
	var health := Health.find_on(enemy)
	if health != null:
		health.died.connect(func(_k: Node) -> void: _killed_keys[key] = true)
	if enemy is Node3D:
		(enemy as Node3D).global_transform = marker.global_transform
	var patrol: PackedVector3Array = marker.get_meta("patrol", PackedVector3Array())
	if enemy.has_method("set_patrol_points") and not patrol.is_empty():
		enemy.call("set_patrol_points", patrol)
	_spawned.append(enemy)
	return enemy


func _on_enemy_exiting(key: Vector3i, enemy: Node) -> void:
	if _alive_keys.get(key) == enemy:
		_alive_keys.erase(key)
	_spawned.erase(enemy)


func _on_objective_updated(id: StringName, _text: String, done: bool) -> void:
	if id != defer_objective_id or not done or _objective_unlocked:
		return
	_objective_unlocked = true
	var pending := _pending_inquisitor_markers.duplicate()
	_pending_inquisitor_markers.clear()
	for marker in pending:
		if is_instance_valid(marker):
			spawn_for_marker(marker)


func spawned_enemies() -> Array[Node]:
	return _spawned
