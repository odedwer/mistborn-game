class_name LoadingScreen
extends CanvasLayer
## Threaded loading screen with in-universe tips. Call `load_scene(path)` after
## instancing, or add to a scene with `target_scene` set in the inspector.
##
## To use it as the target of `change_scene_to_file`, set the static
## `pending_target` first: the loading screen picks it up in `_ready` if its
## own `target_scene` export is empty.

signal load_finished(scene: PackedScene)

@export var target_scene: String = ""
static var pending_target: String = ""

const TIPS := [
	"Burn tin to see through the mist, but flare it near a lantern and you'll wish you hadn't.",
	"A dropped coin makes a fine anchor. A dropped coin under a guard makes a finer one.",
	"Pewter dulls pain, not sense. You'll still remember every blow.",
	"Bronze hears the metal-born. Copper hides you from them. Guess which one the Inquisitor lacks.",
	"Steel pushes what's heavier than you away from you. Mind the rooftops.",
	"Atium shows you a heartbeat from now. It never shows you next week's rent.",
	"The mists don't care whose side you're on. Neither do the Steel Ministry's dogs.",
]

var _progress: ProgressBar
var _tip_label: Label
var _status_label: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if target_scene == "" and pending_target != "":
		target_scene = pending_target
		pending_target = ""
	if target_scene != "":
		load_scene(target_scene)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(700, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	box.add_child(UIHelpers.title_label("Crossing the Ash"))
	_tip_label = UIHelpers.dim_label(TIPS[randi() % TIPS.size()])
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_tip_label)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	box.add_child(_progress)

	_status_label = UIHelpers.dim_label("Loading...")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status_label)


func load_scene(path: String) -> void:
	target_scene = path
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("LoadingScreen: could not start loading %s (%d)" % [path, err])
		return
	set_process(true)


func _process(_delta: float) -> void:
	if target_scene == "":
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(target_scene, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_progress.value = progress[0] if progress.size() > 0 else _progress.value
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			var scene: PackedScene = ResourceLoader.load_threaded_get(target_scene)
			_status_label.text = "Ready."
			load_finished.emit(scene)
			get_tree().change_scene_to_packed(scene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			_status_label.text = "Failed to load."
			push_error("LoadingScreen: failed to load %s" % target_scene)
