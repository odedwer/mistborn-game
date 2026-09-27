extends Node
## Tracks whether the player last used the keyboard/mouse or a gamepad, so UI
## can show the right button-prompt glyphs (see `InputSetup.glyph_for`) and
## switch automatically. Emits `device_changed` on every switch.

signal device_changed(is_gamepad: bool)

## Stick motion below this magnitude doesn't count as "gamepad input" (avoids
## flip-flopping the prompt style from drift/noise).
const AXIS_THRESHOLD := 0.35

var _is_gamepad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_gamepad() -> bool:
	return _is_gamepad


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_gamepad(false)
	elif event is InputEventJoypadButton:
		_set_gamepad(true)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= AXIS_THRESHOLD:
			_set_gamepad(true)


func _set_gamepad(v: bool) -> void:
	if v == _is_gamepad:
		return
	_is_gamepad = v
	device_changed.emit(v)
