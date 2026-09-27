extends TestCase
## Accessibility settings: persistence, colour-blind palette remapping,
## hold/toggle input logic, glyph switching, deadzones and haptics.

const PLAYER_SCENE := preload("res://src/player/player.tscn")


func after_each() -> void:
	# Reset to defaults so other tests aren't affected by state this file sets.
	GameSettings.hold_to_use_push_pull = true
	GameSettings.hold_to_use_flare = true
	GameSettings.colorblind_mode = GameSettings.ColorBlindMode.OFF
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	GameSettings.vibration_enabled = true
	GameSettings.stick_deadzone = 0.2
	GameSettings.apply_controls()
	Input.action_release(&"push")
	Input.action_release(&"pull")
	Input.action_release(&"flare")


# --- Persistence -------------------------------------------------------------

func test_accessibility_settings_roundtrip() -> void:
	GameSettings.subtitle_size = GameSettings.SubtitleSize.XL
	GameSettings.subtitle_bg_opacity = 0.33
	GameSettings.ui_scale = 1.25
	GameSettings.colorblind_mode = GameSettings.ColorBlindMode.PROTANOPIA
	GameSettings.high_contrast_lines = true
	GameSettings.disable_fov_kick = true
	GameSettings.disable_speed_lines = true
	GameSettings.flash_reduction = 0.6
	GameSettings.hold_to_use_push_pull = false
	GameSettings.hold_to_use_flare = false
	GameSettings.aim_assist_strength = 1.7
	GameSettings.vibration_enabled = false
	GameSettings.stick_deadzone = 0.35
	GameSettings.game_speed_percent = 0.8
	GameSettings.auto_burn_basic_metals = true
	GameSettings.save_settings()

	GameSettings.subtitle_size = GameSettings.SubtitleSize.S
	GameSettings.subtitle_bg_opacity = 1.0
	GameSettings.ui_scale = 1.0
	GameSettings.colorblind_mode = GameSettings.ColorBlindMode.OFF
	GameSettings.high_contrast_lines = false
	GameSettings.disable_fov_kick = false
	GameSettings.disable_speed_lines = false
	GameSettings.flash_reduction = 0.0
	GameSettings.hold_to_use_push_pull = true
	GameSettings.hold_to_use_flare = true
	GameSettings.aim_assist_strength = 1.0
	GameSettings.vibration_enabled = true
	GameSettings.stick_deadzone = 0.2
	GameSettings.game_speed_percent = 1.0
	GameSettings.auto_burn_basic_metals = false

	GameSettings.load_settings()
	assert_eq(GameSettings.subtitle_size, GameSettings.SubtitleSize.XL)
	assert_almost(GameSettings.subtitle_bg_opacity, 0.33)
	assert_almost(GameSettings.ui_scale, 1.25)
	assert_eq(GameSettings.colorblind_mode, GameSettings.ColorBlindMode.PROTANOPIA)
	assert_true(GameSettings.high_contrast_lines)
	assert_true(GameSettings.disable_fov_kick)
	assert_true(GameSettings.disable_speed_lines)
	assert_almost(GameSettings.flash_reduction, 0.6)
	assert_false(GameSettings.hold_to_use_push_pull)
	assert_false(GameSettings.hold_to_use_flare)
	assert_almost(GameSettings.aim_assist_strength, 1.7)
	assert_false(GameSettings.vibration_enabled)
	assert_almost(GameSettings.stick_deadzone, 0.35)
	assert_almost(GameSettings.game_speed_percent, 0.8)
	assert_true(GameSettings.auto_burn_basic_metals)

	# Restore real defaults so later tests (and the on-disk settings file)
	# aren't left with this test's values.
	GameSettings.set_preset(GameSettings.detect_default_preset())
	GameSettings.subtitle_size = GameSettings.SubtitleSize.M
	GameSettings.subtitle_bg_opacity = 0.85
	GameSettings.ui_scale = 1.0
	GameSettings.colorblind_mode = GameSettings.ColorBlindMode.OFF
	GameSettings.high_contrast_lines = false
	GameSettings.disable_fov_kick = false
	GameSettings.disable_speed_lines = false
	GameSettings.flash_reduction = 0.0
	GameSettings.hold_to_use_push_pull = true
	GameSettings.hold_to_use_flare = true
	GameSettings.aim_assist_strength = 1.0
	GameSettings.vibration_enabled = true
	GameSettings.stick_deadzone = 0.2
	GameSettings.game_speed_percent = 1.0
	GameSettings.auto_burn_basic_metals = false
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	GameSettings.save_settings()


## Godot's built-in ui_accept/ui_cancel ship with no gamepad binding by
## default, which would strand gamepad-only players in every menu.
func test_ui_accept_and_cancel_have_gamepad_bindings() -> void:
	var accept_has_joy := false
	for e in InputMap.action_get_events(&"ui_accept"):
		if e is InputEventJoypadButton:
			accept_has_joy = true
	var cancel_has_joy := false
	for e in InputMap.action_get_events(&"ui_cancel"):
		if e is InputEventJoypadButton:
			cancel_has_joy = true
	assert_true(accept_has_joy, "ui_accept needs a gamepad (A) binding")
	assert_true(cancel_has_joy, "ui_cancel needs a gamepad (B) binding")


func test_stick_deadzone_applies_to_input_map() -> void:
	GameSettings.stick_deadzone = 0.4
	GameSettings.apply_controls()
	assert_almost(InputMap.action_get_deadzone(&"move_forward"), 0.4)
	assert_almost(InputMap.action_get_deadzone(&"look_left"), 0.4)


# --- Colour-blind palette remap ------------------------------------------------

func test_display_color_of_defaults_to_normal_palette() -> void:
	assert_eq(Metal.display_color_of(Metal.Type.STEEL, GameSettings.ColorBlindMode.OFF), Metal.color_of(Metal.Type.STEEL))


func test_display_color_of_remaps_for_each_mode() -> void:
	for mode in [GameSettings.ColorBlindMode.DEUTERANOPIA, GameSettings.ColorBlindMode.PROTANOPIA, GameSettings.ColorBlindMode.TRITANOPIA]:
		var remapped := Metal.display_color_of(Metal.Type.BRASS, mode)
		assert_true(remapped != Metal.color_of(Metal.Type.BRASS), "mode %d should retint brass" % mode)


func test_hud_vials_retint_on_colorblind_mode_change() -> void:
	var hud: CanvasLayer = load("res://src/ui/hud.tscn").instantiate()
	add_child(hud)
	GameSettings.colorblind_mode = GameSettings.ColorBlindMode.DEUTERANOPIA
	Events.settings_changed.emit()
	var bar: ProgressBar = hud._vials[Metal.Type.STEEL]
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill")
	assert_eq(style.bg_color, Metal.display_color_of(Metal.Type.STEEL, GameSettings.ColorBlindMode.DEUTERANOPIA))
	hud.queue_free()


# --- Hold vs. toggle -----------------------------------------------------------

## `drive_input` false stops the player's own `_physics_process` from also
## calling `_handle_metal_input`, so tests that manually drive input/toggle
## timing aren't double-ticked by the engine's automatic physics step.
func _spawn_player(drive_input: bool = true) -> Player:
	var p := PLAYER_SCENE.instantiate() as Player
	add_child(p)
	if not drive_input:
		p.set_physics_process(false)
	return p


func test_push_hold_mode_follows_button_state() -> void:
	GameSettings.hold_to_use_push_pull = true
	var p := _spawn_player()
	Input.action_press(&"push")
	assert_true(p._push_active())
	Input.action_release(&"push")
	assert_false(p._push_active())
	p.queue_free()


func test_push_toggle_mode_flips_on_press() -> void:
	GameSettings.hold_to_use_push_pull = false
	var p := _spawn_player(false)
	# Input's "just pressed" edge only appears after a frame boundary, so each
	# press/release is followed by one physics frame before checking it.
	Input.action_press(&"push")
	await physics_frames(1)
	p._handle_metal_input()
	assert_true(p._push_active(), "first press toggles on")
	Input.action_release(&"push")
	await physics_frames(1)
	p._handle_metal_input()
	assert_true(p._push_active(), "stays on after release (toggle, not hold)")
	Input.action_press(&"push")
	await physics_frames(1)
	p._handle_metal_input()
	assert_false(p._push_active(), "second press toggles back off")
	Input.action_release(&"push")
	p.queue_free()


func test_flare_toggle_mode() -> void:
	GameSettings.hold_to_use_flare = false
	var p := _spawn_player(false)
	Input.action_press(&"flare")
	await physics_frames(1)
	p._handle_metal_input()
	assert_true(p._flare_active())
	Input.action_release(&"flare")
	await physics_frames(1)
	p._handle_metal_input()
	assert_true(p._flare_active())
	p.queue_free()


# --- Story mode invincibility --------------------------------------------------

func test_story_mode_makes_player_invincible() -> void:
	var p := _spawn_player()
	GameSettings.difficulty = GameSettings.Difficulty.STORY
	var dealt := p.health.take_damage(50.0, null, &"blunt")
	assert_almost(dealt, 0.0)
	assert_almost(p.health.current, p.health.max_health)
	p.queue_free()


func test_normal_difficulty_takes_damage() -> void:
	var p := _spawn_player()
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	var dealt := p.health.take_damage(50.0, null, &"blunt")
	assert_almost(dealt, 50.0)
	p.queue_free()


# --- Glyph switching -----------------------------------------------------------

func test_glyph_for_keyboard_and_gamepad_differ() -> void:
	var kb := InputSetup.glyph_for("push", false)
	var pad := InputSetup.glyph_for("push", true)
	assert_eq(kb, "[LMB]")
	assert_eq(pad, "[RT]")


func test_input_device_switches_on_gamepad_button() -> void:
	var dev: Node = InputDevice
	assert_false(dev.is_gamepad(), "starts as keyboard/mouse by default")
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	ev.pressed = true
	dev._input(ev)
	assert_true(dev.is_gamepad())
	var kev := InputEventKey.new()
	kev.pressed = true
	kev.keycode = KEY_W
	dev._input(kev)
	assert_false(dev.is_gamepad())


# --- Haptics ---------------------------------------------------------------

func test_haptics_disabled_by_setting() -> void:
	GameSettings.vibration_enabled = false
	assert_false(Haptics._enabled())


func test_haptics_calls_are_safe_with_no_joypad() -> void:
	GameSettings.vibration_enabled = true
	# No joypad is connected in the headless test runner, so this must not
	# error even though push_pull()/landing()/damage()/coin_hit() all end up
	# calling into Input.start_joy_vibration.
	Haptics.push_pull(0.8)
	Haptics.landing(10.0)
	Haptics.damage(20.0)
	Haptics.coin_hit()
	assert_true(true)
