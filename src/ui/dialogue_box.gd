extends CanvasLayer
## Dialogue box UI: speaker name, a colour-coded portrait swatch, the line of
## text, and choice buttons when the current line offers them. Purely a view
## over `DialogueSystem`/`Events.dialogue_*` — it holds no dialogue state of
## its own, so it works with any dialogue id without change.

var _panel: PanelContainer
var _portrait: ColorRect
var _name_label: Label
var _text_label: Label
var _choices_box: VBoxContainer
var _continue_hint: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	Events.dialogue_line_shown.connect(_on_line_shown)
	Events.dialogue_choices_shown.connect(_on_choices_shown)
	Events.dialogue_finished.connect(_on_finished)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 80
	_panel.offset_right = -80
	_panel.offset_top = -220
	_panel.offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.92)
	style.border_color = Color(0.5, 0.45, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(28, 28)
	_portrait.color = Color(0.6, 0.6, 0.6)
	header.add_child(_portrait)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	header.add_child(_name_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 18)
	_text_label.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	vbox.add_child(_choices_box)

	_continue_hint = Label.new()
	_continue_hint.text = "[Interact] to continue"
	_continue_hint.add_theme_font_size_override("font_size", 12)
	_continue_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_continue_hint)


func _unhandled_input(event: InputEvent) -> void:
	var has_choices := _choices_box.get_child_count() > 0
	if not visible or has_choices:
		return
	if event.is_action_pressed(&"interact") or (event is InputEventMouseButton and event.pressed):
		DialogueSystem.advance()
		get_viewport().set_input_as_handled()


func _on_line_shown(_id: StringName, speaker: String, text: String, color: Color) -> void:
	visible = true
	_name_label.text = speaker
	_text_label.text = text
	_portrait.color = color
	_clear_choices()
	_continue_hint.visible = true


func _on_choices_shown(_id: StringName, choices: Array) -> void:
	_clear_choices()
	_continue_hint.visible = false
	for i in choices.size():
		var c: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = String(c.get("text", "..."))
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(btn)


func _on_choice_pressed(index: int) -> void:
	DialogueSystem.choose(index)


func _on_finished(_id: StringName) -> void:
	visible = false
	_clear_choices()


func _clear_choices() -> void:
	for c in _choices_box.get_children():
		c.queue_free()
