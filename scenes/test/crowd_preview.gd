extends Node3D
## Street crowd preview: the streamed Luthadel world plus a CrowdSystem, seen
## from a street-level camera near the player spawn. For screenshots:
##   godot -s res://tools/screenshot.gd -- res://scenes/test/crowd_preview.tscn out.png 400
## Prints the crowd stats (agents / visible models / pooled models) periodically.

var world: Node3D
var crowd: CrowdSystem
var _camera: Camera3D
var _t := 0.0
var _placed := false


func _ready() -> void:
	world = (load("res://src/world/luthadel.tscn") as PackedScene).instantiate()
	add_child(world)
	crowd = CrowdSystem.new()
	add_child(crowd)
	crowd.setup(world)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.make_current()
	_place_camera()


## On the lane of the nearest pedestrian, looking along the street.
func _place_camera() -> void:
	var spawn: Vector3 = world.call(&"spawn_position")
	var best: Node3D = null
	var best_d := INF
	for ag in crowd._agents:
		if is_instance_valid(ag):
			var d := ag.global_position.distance_to(spawn)
			if d < best_d:
				best_d = d
				best = ag
	if best == null:
		_camera.position = spawn + Vector3(0, 1.7, 0)
		return
	var ag := best as CrowdSystem.CrowdAgent
	var along := (ag.b - ag.a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var mid := ag.a.lerp(ag.b, 0.5)
	_camera.position = mid - along * 6.0 - side * 2.0 + Vector3(0, 1.9, 0)
	_camera.look_at(mid + along * 8.0 + Vector3(0, 1.0, 0), Vector3.UP)
	crowd.focus_override = _camera.position
	_placed = true


func _process(delta: float) -> void:
	_t += delta
	if not _placed and crowd.agent_count() > 0:
		_place_camera()
	if int(_t) != int(_t - delta):
		print("crowd: agents=%d visible=%d models=%d" % [crowd.agent_count(), crowd.visible_count(), crowd.model_count()])
