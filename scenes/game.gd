extends Node3D
## Integration scene: assembles the world, player, enemies, pickups and UI.
##
## Every optional piece is guarded by `ResourceLoader.exists`, so this scene
## runs (and stays playable enough to test) before other systems land, and
## lights up piece by piece as `src/world`, `src/player`, `src/enemies` and
## `src/world/pickup.tscn` are filled in.

const WORLD_SCENE := "res://src/world/luthadel.tscn"
const PLAYER_SCENE := "res://src/player/player.tscn"
const ENEMY_SPAWNER_SCRIPT := "res://src/enemies/enemy_spawner.gd"
const PICKUP_SCENE := "res://src/world/pickup.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"
const PAUSE_SCENE := "res://src/ui/pause_menu.tscn"
const MISSION_COMPLETE_SCENE := "res://src/ui/mission_complete.tscn"
const DEATH_SCENE := "res://src/ui/death_screen.tscn"
const ACTIVITY_MANAGER_SCRIPT := "res://src/mission/activities/activity_manager.gd"

var world: Node3D
var enemy_spawner: Node
## Pickup marker keys already collected (never respawned) or currently present.
var _collected_pickups: Dictionary = {}
var _live_pickups: Dictionary = {}


func _ready() -> void:
	_build_world()
	_spawn_player()
	_build_enemy_spawner()
	_spawn_pickups(get_tree().get_nodes_in_group("pickup_spawn"))
	if world.has_signal(&"markers_spawned"):
		world.connect(&"markers_spawned", _on_markers_spawned)
	_add_ui()
	_add_mission_director()
	_add_activity_manager()


## A streamed world chunk loaded: populate its enemies and pickups.
func _on_markers_spawned(nodes: Array) -> void:
	var pickups: Array = []
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n.is_in_group(&"enemy_spawn") and n is Marker3D and enemy_spawner != null:
			enemy_spawner.call(&"spawn_for_marker", n)
		elif n.is_in_group(&"pickup_spawn"):
			pickups.append(n)
	_spawn_pickups(pickups)


func _build_world() -> void:
	if ResourceLoader.exists(WORLD_SCENE):
		var scene: PackedScene = load(WORLD_SCENE)
		world = scene.instantiate()
	else:
		world = _build_fallback_world()
	world.name = "World"
	world.add_to_group("world")
	add_child(world)


## A tiny flat floor with a single player_spawn marker, used until the world
## generator lands.
func _build_fallback_world() -> Node3D:
	var root := Node3D.new()

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.15, 0.15, 0.18)
	env.environment = e
	env.add_to_group("world_environment")
	root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -20, 0)
	sun.light_energy = 0.7
	root.add_child(sun)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(200, 1, 200)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0, 1, 0)
	spawn.add_to_group("player_spawn")
	root.add_child(spawn)

	# A camera so the fallback scene renders something even without a player.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3, 8)
	cam.rotation_degrees = Vector3(-15, 0, 0)
	root.add_child(cam)

	return root


func _spawn_player() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return
	# "Save anywhere": restore the player's exact open-world position (not
	# just the last mission checkpoint), with the surrounding chunks streamed
	# in synchronously first so they never spawn over unloaded ground.
	if GameState.has_open_world_position and world != null and "streamer" in world and world.streamer != null:
		var target: Vector3 = GameState.open_world_position.origin
		if not world.streamer.is_area_loaded(target):
			world.streamer.load_now(target, world.streamer.load_radius)
	var scene: PackedScene = load(PLAYER_SCENE)
	var player := scene.instantiate()
	add_child(player)
	var spawn := get_tree().get_first_node_in_group("player_spawn")
	if spawn is Node3D and player is Node3D:
		(player as Node3D).global_transform = (spawn as Node3D).global_transform
	if GameState.last_checkpoint_id != &"" and player is Node3D:
		(player as Node3D).global_transform = GameState.last_checkpoint_transform
	if GameState.has_open_world_position and player is Node3D:
		(player as Node3D).global_transform = GameState.open_world_position
	Mastery.apply_to(player, GameState.mastery_levels)


func _build_enemy_spawner() -> void:
	if not ResourceLoader.exists(ENEMY_SPAWNER_SCRIPT):
		return
	var script: Script = load(ENEMY_SPAWNER_SCRIPT)
	var spawner := Node.new()
	spawner.set_script(script)
	spawner.name = "EnemySpawner"
	spawner.add_to_group("enemy_spawner")
	add_child(spawner)
	enemy_spawner = spawner
	# Shared alert level (HUD indicator, detection stats, music intensity).
	if get_tree().get_first_node_in_group(&"alert_director") == null:
		var alert := AlertDirector.new()
		alert.name = "AlertDirector"
		add_child(alert)
	spawner.call(&"spawn_all", world)


## Spawns a pickup at each marker, parented to the marker's chunk so it
## streams with it. Collected pickups are remembered and never come back.
func _spawn_pickups(markers: Array) -> void:
	if not ResourceLoader.exists(PICKUP_SCENE):
		return
	var scene: PackedScene = load(PICKUP_SCENE)
	for marker in markers:
		if not (marker is Node3D) or not is_instance_valid(marker):
			continue
		var key := Vector3i(((marker as Node3D).global_position * 4.0).round())
		if _collected_pickups.has(key) or is_instance_valid(_live_pickups.get(key)):
			continue
		var pickup := scene.instantiate()
		var kind = marker.get_meta("pickup_kind", &"")
		if kind != &"" and "pickup_kind" in pickup:
			pickup.pickup_kind = kind
		var parent: Node = marker.get_parent() if marker.get_parent() != null else self
		parent.add_child(pickup)
		(pickup as Node3D).global_transform = (marker as Node3D).global_transform
		_live_pickups[key] = pickup
		if pickup.has_signal(&"collected"):
			pickup.connect(&"collected", func(_p: Node) -> void: _collected_pickups[key] = true)


func _add_ui() -> void:
	if ResourceLoader.exists(HUD_SCENE):
		add_child((load(HUD_SCENE) as PackedScene).instantiate())
	if ResourceLoader.exists(PAUSE_SCENE):
		add_child((load(PAUSE_SCENE) as PackedScene).instantiate())
	if ResourceLoader.exists(MISSION_COMPLETE_SCENE):
		add_child((load(MISSION_COMPLETE_SCENE) as PackedScene).instantiate())
	if ResourceLoader.exists(DEATH_SCENE):
		add_child((load(DEATH_SCENE) as PackedScene).instantiate())


func _add_mission_director() -> void:
	var director := MissionDirector.new()
	director.name = "MissionDirector"
	add_child(director)


func _add_activity_manager() -> void:
	if not ResourceLoader.exists(ACTIVITY_MANAGER_SCRIPT):
		return
	var manager := Node.new()
	manager.set_script(load(ACTIVITY_MANAGER_SCRIPT))
	manager.name = "ActivityManager"
	add_child(manager)
