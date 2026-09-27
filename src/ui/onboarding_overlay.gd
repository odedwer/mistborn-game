class_name OnboardingOverlay
extends CanvasLayer
## A short, skippable first-time controls overlay shown on New Game. Lists the
## core bindings (from `InputSetup`) for both keyboard/mouse and gamepad, and
## a full reference stays available afterwards in the pause menu's Controls
## tab. Emits `finished` when dismissed (button, Interact/ui_accept, or
## ui_cancel all skip it).

signal finished

## The handful of actions worth teaching up front; the pause menu's Controls
## tab lists everything else.
const HIGHLIGHT_ACTIONS := [
	"move_forward", "jump", "sprint", "push", "pull", "flare",
	"drink_vial", "metal_wheel", "interact", "pause",
]
const LABELS := {
	"move_forward": "Move", "jump": "Jump", "sprint": "Sprint",
	"push": "Push (Steel)", "pull": "Pull (Iron)", "flare": "Flare",
	"drink_vial": "Drink Vial", "metal_wheel": "Metal Wheel",
	"interact": "Interact", "pause": "Pause",
}

var _continue_btn: Button


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.register_ui_scale_target(self)
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(UIHelpers.title_label("Before You Begin"))
	vbox.add_child(UIHelpers.dim_label("A few core moves. The full control list is always in the Pause menu's Controls tab."))
	vbox.add_child(UIHelpers.vsep(6))

	for action in HIGHLIGHT_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var lbl := Label.new()
		lbl.text = LABELS.get(action, action.capitalize())
		lbl.custom_minimum_size = Vector2(200, 0)
		row.add_child(lbl)
		var kb := Label.new()
		kb.text = InputSetup.glyph_for(action, false)
		kb.custom_minimum_size = Vector2(120, 0)
		row.add_child(kb)
		var pad := Label.new()
		pad.text = InputSetup.glyph_for(action, true)
		row.add_child(pad)
		vbox.add_child(row)

	vbox.add_child(UIHelpers.vsep(10))
	_continue_btn = UIHelpers.button("Begin")
	_continue_btn.pressed.connect(_dismiss)
	vbox.add_child(_continue_btn)
	_continue_btn.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause"):
		_dismiss()
		get_viewport().set_input_as_handled()


func _dismiss() -> void:
	finished.emit()
	queue_free()
