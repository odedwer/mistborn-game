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
}

@export var defer_inquisitor: bool = true
@export var defer_objective_id: StringName = &"ledger"

var world_root: Node
var _spawned: Array[Node] = []
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
		var etype: StringName = marker.get_meta("enemy_type", &"guard")
		if etype == &"inquisitor" and defer_inquisitor and not _objective_unlocked:
			_pending_inquisitor_markers.append(marker)
			continue
		_spawn_at(marker, etype)


## Spawns a single enemy of `etype` at `at` immediately (bypasses deferral).
func spawn_type(etype: StringName, at: Marker3D) -> Node:
	if at == null:
		return null
	return _spawn_at(at, etype)


func _spawn_at(marker: Marker3D, etype: StringName) -> Node:
	var path: String = TYPE_SCENES.get(etype, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("EnemySpawner: unknown enemy_type '%s'" % etype)
		return null
	var scene: PackedScene = load(path)
	var enemy := scene.instantiate()
	var parent: Node = world_root if world_root else marker.get_tree().current_scene
	parent.add_child(enemy)
	if enemy is Node3D:
		(enemy as Node3D).global_transform = marker.global_transform
	var patrol: PackedVector3Array = marker.get_meta("patrol", PackedVector3Array())
	if enemy.has_method("set_patrol_points") and not patrol.is_empty():
		enemy.call("set_patrol_points", patrol)
	_spawned.append(enemy)
	return enemy


func _on_objective_updated(id: StringName, _text: String, done: bool) -> void:
	if id != defer_objective_id or not done or _objective_unlocked:
		return
	_objective_unlocked = true
	for marker in _pending_inquisitor_markers:
		if is_instance_valid(marker):
			_spawn_at(marker, &"inquisitor")
	_pending_inquisitor_markers.clear()


func spawned_enemies() -> Array[Node]:
	return _spawned
