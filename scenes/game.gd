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

var world: Node3D


func _ready() -> void:
	_build_world()
	_spawn_player()
	_build_enemy_spawner()
	_spawn_pickups()
	_add_ui()
	_add_mission_director()


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
	var scene: PackedScene = load(PLAYER_SCENE)
	var player := scene.instantiate()
	add_child(player)
	var spawn := get_tree().get_first_node_in_group("player_spawn")
	if spawn is Node3D and player is Node3D:
		(player as Node3D).global_transform = (spawn as Node3D).global_transform
	if GameState.last_checkpoint_id != &"" and player is Node3D:
		(player as Node3D).global_transform = GameState.last_checkpoint_transform


func _build_enemy_spawner() -> void:
	if not ResourceLoader.exists(ENEMY_SPAWNER_SCRIPT):
		return
	var script: Script = load(ENEMY_SPAWNER_SCRIPT)
	var spawner := Node.new()
	spawner.set_script(script)
	spawner.name = "EnemySpawner"
	spawner.add_to_group("enemy_spawner")
	add_child(spawner)


func _spawn_pickups() -> void:
	if not ResourceLoader.exists(PICKUP_SCENE):
		return
	var scene: PackedScene = load(PICKUP_SCENE)
	for marker in get_tree().get_nodes_in_group("pickup_spawn"):
		if not (marker is Node3D):
			continue
		var pickup := scene.instantiate()
		add_child(pickup)
		(pickup as Node3D).global_transform = (marker as Node3D).global_transform
		var kind = marker.get_meta("pickup_kind", &"")
		if kind != &"" and "pickup_kind" in pickup:
			pickup.pickup_kind = kind


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
