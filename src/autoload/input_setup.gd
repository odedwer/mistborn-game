extends Node
## Registers every input action at startup (keyboard/mouse + gamepad), so the
## bindings live in code rather than in project.godot, and applies any user
## rebinds saved by GameSettings.

const KEY := 0
const MOUSE := 1
const JOY_BTN := 2
const JOY_AXIS := 3

## action -> list of [kind, code, (axis sign)]
const DEFAULT_BINDINGS := {
	"move_forward": [[KEY, KEY_W], [JOY_AXIS, JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[KEY, KEY_S], [JOY_AXIS, JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[KEY, KEY_A], [JOY_AXIS, JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[KEY, KEY_D], [JOY_AXIS, JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [[JOY_AXIS, JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [[JOY_AXIS, JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS, JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [[JOY_AXIS, JOY_AXIS_RIGHT_Y, 1.0]],
	"jump": [[KEY, KEY_SPACE], [JOY_BTN, JOY_BUTTON_A]],
	"sprint": [[KEY, KEY_SHIFT], [JOY_BTN, JOY_BUTTON_LEFT_STICK]],
	"crouch": [[KEY, KEY_CTRL], [JOY_BTN, JOY_BUTTON_B]],
	"interact": [[KEY, KEY_E], [JOY_BTN, JOY_BUTTON_X]],
	# Allomancy
	"push": [[MOUSE, MOUSE_BUTTON_LEFT], [JOY_AXIS, JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"pull": [[MOUSE, MOUSE_BUTTON_RIGHT], [JOY_AXIS, JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"flare": [[KEY, KEY_ALT], [JOY_BTN, JOY_BUTTON_RIGHT_STICK]],
	"throw_coins": [[KEY, KEY_Q], [JOY_BTN, JOY_BUTTON_RIGHT_SHOULDER]],
	"drop_coin": [[KEY, KEY_G], [JOY_BTN, JOY_BUTTON_DPAD_DOWN]],
	"melee": [[KEY, KEY_F], [MOUSE, MOUSE_BUTTON_XBUTTON1], [JOY_BTN, JOY_BUTTON_Y]],
	"drink_vial": [[KEY, KEY_R], [JOY_BTN, JOY_BUTTON_DPAD_UP]],
	"metal_wheel": [[KEY, KEY_TAB], [JOY_BTN, JOY_BUTTON_LEFT_SHOULDER]],
	"toggle_steel": [[KEY, KEY_1]],
	"toggle_iron": [[KEY, KEY_2]],
	"toggle_pewter": [[KEY, KEY_3], [JOY_BTN, JOY_BUTTON_DPAD_LEFT]],
	"toggle_tin": [[KEY, KEY_4], [JOY_BTN, JOY_BUTTON_DPAD_RIGHT]],
	"toggle_bronze": [[KEY, KEY_5]],
	"toggle_copper": [[KEY, KEY_6]],
	"toggle_zinc": [[KEY, KEY_7]],
	"toggle_brass": [[KEY, KEY_8]],
	"toggle_atium": [[KEY, KEY_9]],
	"burn_duralumin": [[KEY, KEY_0]],
	"burn_all_basic": [[KEY, KEY_B]],
	"target_cycle_next": [[MOUSE, MOUSE_BUTTON_WHEEL_UP]],
	"target_cycle_prev": [[MOUSE, MOUSE_BUTTON_WHEEL_DOWN]],
	"pause": [[KEY, KEY_ESCAPE], [JOY_BTN, JOY_BUTTON_START]],
	"quick_save": [[KEY, KEY_F5]],
	"quick_load": [[KEY, KEY_F9]],
	"toggle_debug": [[KEY, KEY_F3]],
	"toggle_camera": [[KEY, KEY_V], [JOY_BTN, JOY_BUTTON_BACK]],
}

## Maps the toggle_* actions to metals, for the allomancer and the HUD.
const TOGGLE_TO_METAL := {
	"toggle_steel": Metal.Type.STEEL,
	"toggle_iron": Metal.Type.IRON,
	"toggle_pewter": Metal.Type.PEWTER,
	"toggle_tin": Metal.Type.TIN,
	"toggle_bronze": Metal.Type.BRONZE,
	"toggle_copper": Metal.Type.COPPER,
	"toggle_zinc": Metal.Type.ZINC,
	"toggle_brass": Metal.Type.BRASS,
	"toggle_atium": Metal.Type.ATIUM,
}


func _ready() -> void:
	apply_bindings({})


## Rebuilds the InputMap. `overrides` maps action -> Array of binding triples
## in the same format as DEFAULT_BINDINGS (as saved by GameSettings).
func apply_bindings(overrides: Dictionary) -> void:
	for action: String in DEFAULT_BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.25)
		var binds: Array = overrides.get(action, DEFAULT_BINDINGS[action])
		for b: Array in binds:
			var ev := make_event(b)
			if ev != null:
				InputMap.action_add_event(action, ev)


static func make_event(b: Array) -> InputEvent:
	match int(b[0]):
		KEY:
			var k := InputEventKey.new()
			k.physical_keycode = int(b[1])
			return k
		MOUSE:
			var m := InputEventMouseButton.new()
			m.button_index = int(b[1])
			return m
		JOY_BTN:
			var j := InputEventJoypadButton.new()
			j.button_index = int(b[1])
			return j
		JOY_AXIS:
			var a := InputEventJoypadMotion.new()
			a.axis = int(b[1])
			a.axis_value = float(b[2])
			return a
	return null


static func event_to_binding(ev: InputEvent) -> Array:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return [KEY, code]
	if ev is InputEventMouseButton:
		return [MOUSE, ev.button_index]
	if ev is InputEventJoypadButton:
		return [JOY_BTN, ev.button_index]
	if ev is InputEventJoypadMotion:
		return [JOY_AXIS, ev.axis, signf(ev.axis_value)]
	return []


static func binding_label(b: Array) -> String:
	match int(b[0]):
		KEY:
			return OS.get_keycode_string(int(b[1]))
		MOUSE:
			return ["", "LMB", "RMB", "MMB", "Wheel Up", "Wheel Down", "Wheel L", "Wheel R", "Mouse 4", "Mouse 5"][clampi(int(b[1]), 0, 9)]
		JOY_BTN:
			return _JOY_BTN_NAMES.get(int(b[1]), "Pad %d" % int(b[1]))
		JOY_AXIS:
			return _JOY_AXIS_NAMES.get(int(b[1]), "Axis %d%s" % [int(b[1]), "+" if float(b[2]) > 0 else "-"])
	return "?"


## Friendly Xbox-style gamepad button/axis names (no image assets: plain text
## glyphs like "[RT]" are built from these by `glyph_label`).
const _JOY_BTN_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS Click", JOY_BUTTON_RIGHT_STICK: "RS Click",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}
const _JOY_AXIS_NAMES := {
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "Left Stick", JOY_AXIS_LEFT_Y: "Left Stick",
	JOY_AXIS_RIGHT_X: "Right Stick", JOY_AXIS_RIGHT_Y: "Right Stick",
}


## Bracketed glyph text for a binding, e.g. "[LMB]", "[RT]", "[E]". Used by
## on-screen prompts so they read correctly for the last-used input device.
static func glyph_label(b: Array) -> String:
	return "[%s]" % binding_label(b)


## The first binding of `kind` for `action` (keyboard/mouse if `gamepad` is
## false, else gamepad), falling back to whatever binding exists.
static func binding_for(action: String, gamepad: bool) -> Array:
	var binds: Array = GameSettings.binding_overrides.get(action, DEFAULT_BINDINGS.get(action, []))
	for b: Array in binds:
		var k := int(b[0])
		if gamepad == (k == JOY_BTN or k == JOY_AXIS):
			return b
	return binds[0] if not binds.is_empty() else []


## Bracketed glyph for `action`'s current binding on the given device kind.
static func glyph_for(action: String, gamepad: bool) -> String:
	var b := binding_for(action, gamepad)
	return glyph_label(b) if not b.is_empty() else "?"
