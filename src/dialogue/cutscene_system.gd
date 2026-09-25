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

const CUTSCENE_DIR := "res://src/mission/cutscenes"

var playing := false
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
	Events.cutscene_started.emit(id)
	_ensure_letterbox()
	_show_letterbox(true)
	var prev_cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	if prev_cam != null:
		cam.global_transform = prev_cam.global_transform
	for shot: Dictionary in shots:
		if shot.has("pos"):
			cam.global_position = _v3(shot["pos"])
		if shot.has("look_at"):
			cam.look_at(_v3(shot["look_at"]), Vector3.UP)
		cam.current = true
		_subtitle.text = String(shot.get("subtitle", ""))
		_subtitle.visible = _subtitle.text != ""
		var duration := float(shot.get("duration", 2.0))
		if duration > 0.0:
			await get_tree().create_timer(duration).timeout
	cam.queue_free()
	if prev_cam != null and is_instance_valid(prev_cam):
		prev_cam.current = true
	_show_letterbox(false)
	playing = false
	Events.cutscene_finished.emit(id)


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
