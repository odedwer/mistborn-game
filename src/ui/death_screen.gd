extends CanvasLayer
## Brief "You Died" flash. Respawn/fade logic itself lives in
## `MissionDirector`; this is just the message layer.

var _label: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Events.player_died.connect(_on_player_died)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIHelpers.theme()
	add_child(root)
	_label = UIHelpers.title_label("You Died")
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.modulate.a = 0.0
	root.add_child(_label)


func _on_player_died() -> void:
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(_label, "modulate:a", 0.0, 0.6)
