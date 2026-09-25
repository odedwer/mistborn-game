extends CanvasLayer
## Small "suspicion" meter shown during the Lady Valette ball (see
## `SuspicionMeter`). Purely a view over `Events.suspicion_changed`; add it
## alongside a `SuspicionMeter` node (e.g. in the ballroom interior scene).

var _bar: ProgressBar
var _label: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Events.suspicion_changed.connect(_on_suspicion_changed)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -220
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = 60
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.75)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	_label = Label.new()
	_label.text = "Suspicion"
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.6))
	vbox.add_child(_label)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.8, 0.25, 0.2)
	_bar.add_theme_stylebox_override("fill", fg)
	vbox.add_child(_bar)


func _on_suspicion_changed(value: float, max_value: float) -> void:
	_bar.max_value = max_value
	_bar.value = value
