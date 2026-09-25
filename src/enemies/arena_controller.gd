extends Node3D
## Builds a flat arena with a runtime-baked NavigationRegion3D, a circling
## dummy "player", and one of every enemy type, so the AI can be watched (or
## driven headlessly, e.g. `godot --headless --quit-after 600
## res://scenes/test/enemy_arena.tscn`).

@export var arena_size: float = 60.0

var spawner: EnemySpawner


func _ready() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	add_child(region)
	_build_nav_region(region)

	var director := AlertDirector.new()
	director.name = "AlertDirector"
	add_child(director)

	var dummy := preload("res://src/enemies/arena_dummy_player.gd").new() as CharacterBody3D
	dummy.name = "DummyPlayer"
	dummy.collision_layer = 1 << 1  # player
	dummy.collision_mask = 1
	add_child(dummy)
	dummy.global_position = Vector3.ZERO
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	dummy.add_child(shape)
	var health_script: GDScript = load("res://src/combat/health.gd")
	var health: Node = health_script.new()
	health.name = "Health"
	dummy.add_child(health)

	_add_spawn_marker(&"guard", Vector3(8, 0, 0), PackedVector3Array([Vector3(8, 0, 0), Vector3(8, 0, 8)]))
	_add_spawn_marker(&"hazekiller", Vector3(-8, 0, 0), PackedVector3Array())
	_add_spawn_marker(&"thug", Vector3(0, 0, 8), PackedVector3Array())
	_add_spawn_marker(&"coinshot", Vector3(0, 0, -12), PackedVector3Array())
	_add_spawn_marker(&"inquisitor", Vector3(-12, 0, -12), PackedVector3Array())

	# Wait a frame so the navigation map picks up the freshly baked region
	# before enemies start pathing.
	await get_tree().process_frame

	spawner = EnemySpawner.new()
	spawner.name = "Spawner"
	spawner.defer_inquisitor = false
	add_child(spawner)
	spawner.spawn_all(self)


func _build_nav_region(region: NavigationRegion3D) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	region.add_child(ground)

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(arena_size, 1.0, arena_size)
	collider.shape = box
	collider.position = Vector3(0, -0.5, 0)
	ground.add_child(collider)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(arena_size, 1.0, arena_size)
	mesh_inst.mesh = box_mesh
	mesh_inst.position = Vector3(0, -0.5, 0)
	ground.add_child(mesh_inst)

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_slope = 60.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh = nav_mesh

	region.bake_navigation_mesh(false)


func _add_spawn_marker(enemy_type: StringName, pos: Vector3, patrol: PackedVector3Array) -> void:
	var marker := Marker3D.new()
	marker.name = "Spawn_%s" % enemy_type
	marker.add_to_group(&"enemy_spawn")
	marker.set_meta("enemy_type", enemy_type)
	marker.set_meta("patrol", patrol)
	add_child(marker)
	marker.global_position = pos
