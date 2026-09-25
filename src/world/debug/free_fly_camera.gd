extends Camera3D
## Free-fly preview camera: hold right mouse to look, WASD/QE to move,
## Shift for speed, T toggles tin vision, 0-3 set mist quality.
##
## Command line (after `--`): `--shot=x,y,z,yaw,pitch,path.png[;...]` takes
## screenshots from the given poses and quits (used for visual checks).

@export var speed := 20.0
@export var look_sensitivity := 0.003

var _yaw := 0.0
var _pitch := -0.2
var _tin := false
var _shots: Array = []


func _ready() -> void:
	far = 4000.0
	_yaw = rotation.y
	_pitch = rotation.x
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for s in a.substr(7).split(";"):
				var p := s.split(",")
				if p.size() >= 6:
					_shots.append([Vector3(float(p[0]), float(p[1]), float(p[2])), deg_to_rad(float(p[3])), deg_to_rad(float(p[4])), p[5]])
	if not _shots.is_empty():
		_run_shots.call_deferred()


func _run_shots() -> void:
	for s: Array in _shots:
		global_position = s[0]
		_yaw = s[1]
		_pitch = s[2]
		rotation = Vector3(_pitch, _yaw, 0)
		# Stream the area in synchronously, then let textures/particles settle.
		var streamer := get_tree().get_first_node_in_group(&"world_streamer")
		if streamer != null:
			streamer.call(&"load_now", global_position, 260.0)
		for i in 40:
			await get_tree().process_frame
		var info := "draw_calls=%d objects=%d prims=%d metals=%d fps=%d" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			MetalRegistry.count(), Engine.get_frames_per_second()]
		print("SHOT ", s[3], " ", info)
		var img := get_viewport().get_texture().get_image()
		img.save_png(s[3])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * look_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * look_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		var mc := get_tree().get_first_node_in_group(&"mist_controller")
		if k == KEY_T and mc != null:
			_tin = not _tin
			mc.call(&"set_tin_vision", 1.0 if _tin else 0.0)
		elif k >= KEY_0 and k <= KEY_3 and mc != null:
			mc.call(&"set_quality", k - KEY_0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var s := speed * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += dir.normalized() * s * delta if dir != Vector3.ZERO else Vector3.ZERO
