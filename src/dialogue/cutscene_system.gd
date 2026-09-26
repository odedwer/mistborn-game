extends Node
## Cutscene-lite (autoload `CutsceneSystem`): letterbox bars, a temporary
## camera cutting/panning between JSON-defined shots, and subtitles. No
## voice; text only, driven entirely by data.
##
## JSON is `res://src/mission/cutscenes/<id>.json`:
## `{"shots": [{"pos": [x,y,z], "look_at": [x,y,z], "duration": 2.5,
## "subtitle": "..."}]}`. A shot may omit `pos`/`look_at` to hold the previous
## shot's camera in place (a pure subtitle beat). `play(id)` swaps in a
## temporary `Camera3D`, so it never has to know how the player's own camera
## rig works, and restores whichever camera was active before it ran.
##
## Act III additions (all optional per shot):
## - `"to_pos"` / `"to_look_at"`: a camera pan — the camera glides from
##   `pos`/`look_at` to these over the shot's `duration` (smoothstep eased).
##   Either may be given alone; the other end holds still.
## - `"fov"`: field of view for the shot (degrees).
## - `"call"`: `{"group": ..., "method": ..., "args": [...]}` run via
##   `SceneTree.call_group` when the shot starts, so a scene can stage its
##   own beats (an actor falls, a crowd surges) in step with the camera.

const CUTSCENE_DIR := "res://src/mission/cutscenes"

var playing := false
var _skip := false
var _letterbox: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _subtitle: Label


static func load_shots(id: StringName) -> Array:
	var path := "%s/%s.json" % [CUTSCENE_DIR, String(id)]
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("shots", [])


## Plays cutscene `id` to completion, then emits `Events.cutscene_finished`.
## Safe to `await` (a test can drive it with very short `duration`s).
func play(id: StringName) -> void:
	var shots := load_shots(id)
	if shots.is_empty():
		Events.cutscene_finished.emit(id)
		return
	playing = true
	_skip = false
	Events.cutscene_started.emit(id)
	_ensure_letterbox()
	_show_letterbox(true)
	var prev_cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	# Freeze the player for the length of the shot list (no walking off a
	# rooftop while the camera is elsewhere); restored afterwards.
	var player := get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var player_mode := Node.PROCESS_MODE_INHERIT
	if player != null:
		player_mode = player.process_mode
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	if prev_cam != null:
		cam.global_transform = prev_cam.global_transform
	var look_target := cam.global_position - cam.global_basis.z * 10.0
	for shot: Dictionary in shots:
		# Skipping still runs every shot's `call`, so the scene ends up
		# staged exactly as if the cutscene had played through.
		if shot.has("pos"):
			cam.global_position = _v3(shot["pos"])
		if shot.has("look_at"):
			look_target = _v3(shot["look_at"])
		_aim(cam, look_target)
		if shot.has("fov"):
			cam.fov = float(shot["fov"])
		cam.current = true
		_subtitle.text = String(shot.get("subtitle", ""))
		_subtitle.visible = _subtitle.text != ""
		if shot.has("call"):
			_run_call(shot["call"])
		var duration := float(shot.get("duration", 2.0))
		if duration <= 0.0:
			continue
		if shot.has("to_pos") or shot.has("to_look_at"):
			var from_pos := cam.global_position
			var to_pos: Vector3 = _v3(shot["to_pos"]) if shot.has("to_pos") else from_pos
			var from_look := look_target
			var to_look: Vector3 = _v3(shot["to_look_at"]) if shot.has("to_look_at") else from_look
			var t := 0.0
			while t < duration and not _skip:
				await get_tree().process_frame
				if not is_instance_valid(cam):
					break
				t += get_process_delta_time()
				var k := smoothstep(0.0, 1.0, clampf(t / duration, 0.0, 1.0))
				cam.global_position = from_pos.lerp(to_pos, k)
				look_target = from_look.lerp(to_look, k)
				_aim(cam, look_target)
		else:
			var waited := 0.0
			while waited < duration and not _skip:
				await get_tree().process_frame
				waited += get_process_delta_time()
	cam.queue_free()
	if player != null and is_instance_valid(player):
		player.process_mode = player_mode
	if prev_cam != null and is_instance_valid(prev_cam):
		prev_cam.current = true
	_show_letterbox(false)
	playing = false
	_skip = false
	Events.cutscene_finished.emit(id)


## Pure pan interpolation (exposed for tests): camera position and look
## target `k` (0..1, already eased) of the way through a pan.
static func pan_sample(shot: Dictionary, k: float) -> Array:
	var p0 := _v3(shot.get("pos", [0, 0, 0]))
	var l0 := _v3(shot.get("look_at", [0, 0, -1]))
	var p1: Vector3 = _v3(shot["to_pos"]) if shot.has("to_pos") else p0
	var l1: Vector3 = _v3(shot["to_look_at"]) if shot.has("to_look_at") else l0
	var e := smoothstep(0.0, 1.0, clampf(k, 0.0, 1.0))
	return [p0.lerp(p1, e), l0.lerp(l1, e)]


static func _aim(cam: Camera3D, target: Vector3) -> void:
	var to := target - cam.global_position
	if to.length() < 0.01:
		return
	var up := Vector3.UP if absf(to.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	cam.look_at(target, up)


func _run_call(c: Dictionary) -> void:
	if not is_inside_tree():
		return
	var args: Array = [StringName(c.get("group", "")), StringName(c.get("method", ""))]
	args.append_array(c.get("args", []))
	get_tree().callv(&"call_group", args)


## Fast-forwards the playing cutscene to its end (Esc during a cutscene;
## tests). Every remaining shot's `call` still runs.
func skip() -> void:
	if playing:
		_skip = true


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO


func _ensure_letterbox() -> void:
	if _letterbox != null and is_instance_valid(_letterbox):
		return
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 30
	_letterbox.visible = false
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.custom_minimum_size = Vector2(0, 90)
	_top_bar.size.y = 90
	_letterbox.add_child(_top_bar)
	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.position.y = -90
	_bottom_bar.size.y = 90
	_letterbox.add_child(_bottom_bar)
	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.position.y = -76
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_letterbox.add_child(_subtitle)
	if is_inside_tree():
		get_tree().root.add_child.call_deferred(_letterbox)


func _show_letterbox(on: bool) -> void:
	if _letterbox != null and is_instance_valid(_letterbox):
		_letterbox.visible = on
