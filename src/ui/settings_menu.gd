extends CanvasLayer
## Settings screen with tabs for Graphics/Audio/Controls/Gameplay. Applies
## every change live via `GameSettings`. Emits `closed` so a host (pause menu
## or main menu) can free/hide it.

signal closed

var _listening_for: String = ""
var _rebind_label: Label
const REBIND_ACTIONS := [
	"push", "pull", "flare", "throw_coins", "drop_coin", "melee", "drink_vial",
	"metal_wheel", "jump", "sprint", "interact",
]


var _close_btn: Button
var _tabs: TabContainer


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameSettings.register_ui_scale_target(self)
	_close_btn.grab_focus.call_deferred()




func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 660)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(UIHelpers.title_label("Settings"))

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(880, 560)
	vbox.add_child(_tabs)
	_tabs.add_child(_build_graphics_tab())
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_controls_tab())
	_tabs.add_child(_build_gameplay_tab())
	_tabs.add_child(_build_accessibility_tab())

	_close_btn = UIHelpers.button("Close")
	_close_btn.pressed.connect(_on_close)
	vbox.add_child(_close_btn)


func _scroll_box(title: String) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.name = title
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return {"root": scroll, "box": box}


func _build_graphics_tab() -> Control:
	var sb := _scroll_box("Graphics")
	var box: VBoxContainer = sb.box

	var preset_row := UIHelpers.labeled_option("Preset", ["Low", "Medium", "High", "Ultra", "Custom"], int(GameSettings.preset))
	UIHelpers.get_option(preset_row).item_selected.connect(func(i: int):
		GameSettings.set_preset(i as GameSettings.Preset)
		_rebuild_graphics_values(box)
	)
	box.add_child(preset_row)

	var vsync_row := UIHelpers.labeled_checkbox("V-Sync", GameSettings.vsync)
	UIHelpers.get_checkbox(vsync_row).toggled.connect(func(v: bool):
		GameSettings.vsync = v
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(vsync_row)

	var window_row := UIHelpers.labeled_option("Window Mode", ["Windowed", "Borderless", "Fullscreen"], int(GameSettings.window_mode))
	UIHelpers.get_option(window_row).item_selected.connect(func(i: int):
		GameSettings.window_mode = i as GameSettings.WindowMode
		GameSettings.apply_graphics()
	)
	box.add_child(window_row)

	var fps_row := UIHelpers.labeled_slider("FPS Cap (0 = uncapped)", 0, 240, 5, GameSettings.fps_cap)
	UIHelpers.get_slider(fps_row).value_changed.connect(func(v: float):
		GameSettings.fps_cap = int(v)
		GameSettings.apply_graphics()
	)
	box.add_child(fps_row)

	var render_scale_row := UIHelpers.labeled_slider("Render Scale", 0.5, 1.0, 0.05, GameSettings.render_scale)
	UIHelpers.get_slider(render_scale_row).value_changed.connect(func(v: float):
		GameSettings.render_scale = v
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(render_scale_row)

	var upscale_row := UIHelpers.labeled_option("Upscaling", ["Off/Bilinear", "FSR1", "FSR2"], _upscale_index(GameSettings.upscale_mode))
	UIHelpers.get_option(upscale_row).item_selected.connect(func(i: int):
		GameSettings.upscale_mode = _index_to_upscale(i)
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(upscale_row)

	var aa_row := UIHelpers.labeled_option("Anti-Aliasing", ["Off", "TAA", "FXAA", "MSAA 2x", "MSAA 4x"], _aa_index())
	UIHelpers.get_option(aa_row).item_selected.connect(func(i: int):
		_apply_aa_index(i)
	)
	box.add_child(aa_row)

	var shadow_row := UIHelpers.labeled_option("Shadow Quality", ["Off", "Low", "Medium", "High", "Ultra"], int(GameSettings.shadow_quality))
	UIHelpers.get_option(shadow_row).item_selected.connect(func(i: int):
		GameSettings.shadow_quality = i as GameSettings.Quality
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(shadow_row)

	var ssao_row := UIHelpers.labeled_checkbox("SSAO", GameSettings.ssao_enabled)
	UIHelpers.get_checkbox(ssao_row).toggled.connect(func(v: bool):
		GameSettings.ssao_enabled = v
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(ssao_row)

	var ssil_row := UIHelpers.labeled_checkbox("SSIL", GameSettings.ssil_enabled)
	UIHelpers.get_checkbox(ssil_row).toggled.connect(func(v: bool):
		GameSettings.ssil_enabled = v
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(ssil_row)

	var sdfgi_row := UIHelpers.labeled_checkbox("SDFGI", GameSettings.sdfgi_enabled)
	UIHelpers.get_checkbox(sdfgi_row).toggled.connect(func(v: bool):
		GameSettings.sdfgi_enabled = v
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(sdfgi_row)

	var fog_row := UIHelpers.labeled_option("Volumetric Fog", ["Off", "Low", "Medium", "High", "Ultra"], int(GameSettings.volumetric_fog_quality))
	UIHelpers.get_option(fog_row).item_selected.connect(func(i: int):
		GameSettings.volumetric_fog_quality = i as GameSettings.Quality
		GameSettings.mark_custom()
		GameSettings.apply_graphics()
	)
	box.add_child(fog_row)

	var ash_row := UIHelpers.labeled_slider("Ash Particle Density", 0.0, 1.0, 0.05, GameSettings.ash_particle_density)
	UIHelpers.get_slider(ash_row).value_changed.connect(func(v: float):
		GameSettings.ash_particle_density = v
		GameSettings.mark_custom()
	)
	box.add_child(ash_row)

	var lod_row := UIHelpers.labeled_slider("LOD Bias", 0.25, 3.0, 0.05, GameSettings.lod_bias)
	UIHelpers.get_slider(lod_row).value_changed.connect(func(v: float):
		GameSettings.lod_bias = v
		GameSettings.mark_custom()
	)
	box.add_child(lod_row)

	var view_row := UIHelpers.labeled_slider("View Distance", 100.0, 600.0, 10.0, GameSettings.view_distance)
	UIHelpers.get_slider(view_row).value_changed.connect(func(v: float):
		GameSettings.view_distance = v
		GameSettings.mark_custom()
	)
	box.add_child(view_row)

	return sb.root


func _rebuild_graphics_values(_box: VBoxContainer) -> void:
	pass  # Sliders keep their old visual value on preset change; acceptable for the slice.


static func _upscale_index(mode: Viewport.Scaling3DMode) -> int:
	match mode:
		Viewport.SCALING_3D_MODE_FSR: return 1
		Viewport.SCALING_3D_MODE_FSR2: return 2
	return 0


static func _index_to_upscale(i: int) -> Viewport.Scaling3DMode:
	match i:
		1: return Viewport.SCALING_3D_MODE_FSR
		2: return Viewport.SCALING_3D_MODE_FSR2
	return Viewport.SCALING_3D_MODE_BILINEAR


func _aa_index() -> int:
	if GameSettings.use_taa:
		return 1
	if GameSettings.use_fxaa:
		return 2
	if GameSettings.msaa == Viewport.MSAA_2X:
		return 3
	if GameSettings.msaa == Viewport.MSAA_4X:
		return 4
	return 0


func _apply_aa_index(i: int) -> void:
	GameSettings.use_taa = i == 1
	GameSettings.use_fxaa = i == 2
	GameSettings.msaa = Viewport.MSAA_2X if i == 3 else (Viewport.MSAA_4X if i == 4 else Viewport.MSAA_DISABLED)
	GameSettings.mark_custom()
	GameSettings.apply_graphics()


func _build_audio_tab() -> Control:
	var sb := _scroll_box("Audio")
	var box: VBoxContainer = sb.box
	box.add_child(_volume_row("Master", GameSettings.master_volume, func(v: float): GameSettings.master_volume = v))
	box.add_child(_volume_row("Music", GameSettings.music_volume, func(v: float): GameSettings.music_volume = v))
	box.add_child(_volume_row("SFX", GameSettings.sfx_volume, func(v: float): GameSettings.sfx_volume = v))
	box.add_child(_volume_row("Voice", GameSettings.voice_volume, func(v: float): GameSettings.voice_volume = v))
	box.add_child(_volume_row("Ambience", GameSettings.ambience_volume, func(v: float): GameSettings.ambience_volume = v))
	return sb.root


func _volume_row(label: String, value: float, setter: Callable) -> Control:
	var row := UIHelpers.labeled_slider(label, 0.0, 1.5, 0.05, value)
	UIHelpers.get_slider(row).value_changed.connect(func(v: float):
		setter.call(v)
		GameSettings.apply_audio()
	)
	return row


func _build_controls_tab() -> Control:
	var sb := _scroll_box("Controls")
	var box: VBoxContainer = sb.box

	var sens_row := UIHelpers.labeled_slider("Mouse Sensitivity", 0.0005, 0.01, 0.0005, GameSettings.mouse_sensitivity)
	UIHelpers.get_slider(sens_row).value_changed.connect(func(v: float):
		GameSettings.mouse_sensitivity = v
		GameSettings.apply_controls()
	)
	box.add_child(sens_row)

	var invert_row := UIHelpers.labeled_checkbox("Invert Y", GameSettings.invert_y)
	UIHelpers.get_checkbox(invert_row).toggled.connect(func(v: bool): GameSettings.invert_y = v)
	box.add_child(invert_row)

	var fov_row := UIHelpers.labeled_slider("Field of View", 60.0, 110.0, 1.0, GameSettings.fov)
	UIHelpers.get_slider(fov_row).value_changed.connect(func(v: float): GameSettings.fov = v)
	box.add_child(fov_row)

	box.add_child(UIHelpers.vsep(10))
	box.add_child(UIHelpers.heading_label("Key Bindings"))
	for action in REBIND_ACTIONS:
		box.add_child(_binding_row(action))

	var reset_btn := UIHelpers.button("Reset Bindings")
	reset_btn.pressed.connect(func():
		GameSettings.reset_bindings()
		_rebuild_binding_labels(box)
	)
	box.add_child(reset_btn)
	return sb.root


func _binding_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.name = "bind_" + action
	var lbl := Label.new()
	lbl.text = action.capitalize()
	lbl.custom_minimum_size = Vector2(220, 0)
	row.add_child(lbl)
	var current := Label.new()
	current.name = "current"
	current.text = _current_binding_label(action)
	current.custom_minimum_size = Vector2(140, 0)
	row.add_child(current)
	var rebind_btn := UIHelpers.button("Rebind")
	rebind_btn.pressed.connect(func(): _start_listening(action, current))
	row.add_child(rebind_btn)
	return row


func _current_binding_label(action: String) -> String:
	var binds: Array = GameSettings.binding_overrides.get(action, InputSetup.DEFAULT_BINDINGS.get(action, []))
	if binds.is_empty():
		return "?"
	return InputSetup.binding_label(binds[0])


func _rebuild_binding_labels(box: VBoxContainer) -> void:
	for action in REBIND_ACTIONS:
		var row := box.get_node_or_null("bind_" + action)
		if row != null:
			(row.get_node("current") as Label).text = _current_binding_label(action)


func _start_listening(action: String, label: Label) -> void:
	_listening_for = action
	_rebind_label = label
	label.text = "Press a key..."


## Gamepad/keyboard: Esc or the gamepad B/East button always backs out, even
## while a tab's control has focus (TabContainer already handles ui_left/right
## and D-pad to switch tabs, and every Button/Slider/OptionButton/CheckBox
## here has focus_mode = ALL, so Tab/arrows never get stuck).
func _unhandled_input(event: InputEvent) -> void:
	if _listening_for == "":
		if event.is_action_pressed(&"ui_cancel"):
			_on_close()
			get_viewport().set_input_as_handled()
			return
		# LB/RB cycle tabs directly (D-pad/left-stick only move focus within
		# a tab's controls otherwise, so this is how a gamepad reaches every tab).
		if event is InputEventJoypadButton and event.pressed:
			var btn := (event as InputEventJoypadButton).button_index
			if btn == JOY_BUTTON_LEFT_SHOULDER or btn == JOY_BUTTON_RIGHT_SHOULDER:
				var step := -1 if btn == JOY_BUTTON_LEFT_SHOULDER else 1
				_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
				get_viewport().set_input_as_handled()
		return
	var is_press: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if not is_press:
		return
	var binding := InputSetup.event_to_binding(event)
	if binding.is_empty():
		return
	GameSettings.set_binding(_listening_for, binding)
	_rebind_label.text = InputSetup.binding_label(binding)
	_listening_for = ""
	_rebind_label = null
	get_viewport().set_input_as_handled()


func _build_gameplay_tab() -> Control:
	var sb := _scroll_box("Gameplay")
	var box: VBoxContainer = sb.box

	var diff_row := UIHelpers.labeled_option("Difficulty", ["Story", "Normal", "Hard"], int(GameSettings.difficulty))
	UIHelpers.get_option(diff_row).item_selected.connect(func(i: int): GameSettings.difficulty = i as GameSettings.Difficulty)
	box.add_child(diff_row)

	var hints_row := UIHelpers.labeled_checkbox("Hints", GameSettings.hints_enabled)
	UIHelpers.get_checkbox(hints_row).toggled.connect(func(v: bool): GameSettings.hints_enabled = v)
	box.add_child(hints_row)

	var subs_row := UIHelpers.labeled_checkbox("Subtitles", GameSettings.subtitles_enabled)
	UIHelpers.get_checkbox(subs_row).toggled.connect(func(v: bool): GameSettings.subtitles_enabled = v)
	box.add_child(subs_row)

	var speed_row := UIHelpers.labeled_option("Game Speed", ["80%", "90%", "100%"], _game_speed_index())
	UIHelpers.get_option(speed_row).item_selected.connect(func(i: int): GameSettings.game_speed_percent = [0.8, 0.9, 1.0][i])
	box.add_child(speed_row)

	return sb.root


static func _game_speed_index() -> int:
	if GameSettings.game_speed_percent <= 0.85:
		return 0
	if GameSettings.game_speed_percent <= 0.95:
		return 1
	return 2


func _build_accessibility_tab() -> Control:
	var sb := _scroll_box("Accessibility")
	var box: VBoxContainer = sb.box

	box.add_child(UIHelpers.heading_label("Subtitles / Dialogue"))
	var subtitle_size_row := UIHelpers.labeled_option("Text Size", ["Small", "Medium", "Large", "Extra Large"], int(GameSettings.subtitle_size))
	UIHelpers.get_option(subtitle_size_row).item_selected.connect(func(i: int):
		GameSettings.subtitle_size = i as GameSettings.SubtitleSize
		Events.settings_changed.emit()
	)
	box.add_child(subtitle_size_row)

	var subtitle_bg_row := UIHelpers.labeled_slider("Subtitle Background Opacity", 0.0, 1.0, 0.05, GameSettings.subtitle_bg_opacity)
	UIHelpers.get_slider(subtitle_bg_row).value_changed.connect(func(v: float):
		GameSettings.subtitle_bg_opacity = v
		Events.settings_changed.emit()
	)
	box.add_child(subtitle_bg_row)

	box.add_child(UIHelpers.vsep(6))
	box.add_child(UIHelpers.heading_label("Display"))
	var ui_scale_row := UIHelpers.labeled_slider("UI Scale", 0.8, 1.5, 0.05, GameSettings.ui_scale)
	UIHelpers.get_slider(ui_scale_row).value_changed.connect(func(v: float):
		GameSettings.ui_scale = v
		GameSettings.apply_accessibility()
	)
	box.add_child(ui_scale_row)

	var cb_row := UIHelpers.labeled_option("Colour-Blind Mode", ["Off", "Deuteranopia", "Protanopia", "Tritanopia"], int(GameSettings.colorblind_mode))
	UIHelpers.get_option(cb_row).item_selected.connect(func(i: int):
		GameSettings.colorblind_mode = i as GameSettings.ColorBlindMode
		Events.settings_changed.emit()
	)
	box.add_child(cb_row)

	var hc_row := UIHelpers.labeled_checkbox("High-Contrast Lines", GameSettings.high_contrast_lines)
	UIHelpers.get_checkbox(hc_row).toggled.connect(func(v: bool):
		GameSettings.high_contrast_lines = v
		Events.settings_changed.emit()
	)
	box.add_child(hc_row)

	box.add_child(UIHelpers.vsep(6))
	box.add_child(UIHelpers.heading_label("Motion & Flashing"))
	var shake_row := UIHelpers.labeled_slider("Camera Shake", 0.0, 1.0, 0.05, GameSettings.camera_shake_scale)
	UIHelpers.get_slider(shake_row).value_changed.connect(func(v: float): GameSettings.camera_shake_scale = v)
	box.add_child(shake_row)

	var fov_row := UIHelpers.labeled_checkbox("FOV Kick at High Speed", not GameSettings.disable_fov_kick)
	UIHelpers.get_checkbox(fov_row).toggled.connect(func(v: bool): GameSettings.disable_fov_kick = not v)
	box.add_child(fov_row)

	var speed_lines_row := UIHelpers.labeled_checkbox("Speed Lines", not GameSettings.disable_speed_lines)
	UIHelpers.get_checkbox(speed_lines_row).toggled.connect(func(v: bool): GameSettings.disable_speed_lines = not v)
	box.add_child(speed_lines_row)

	var flash_row := UIHelpers.labeled_slider("Reduce Flashing (flare pulse, damage vignette)", 0.0, 1.0, 0.05, GameSettings.flash_reduction)
	UIHelpers.get_slider(flash_row).value_changed.connect(func(v: float): GameSettings.flash_reduction = v)
	box.add_child(flash_row)

	box.add_child(UIHelpers.vsep(6))
	box.add_child(UIHelpers.heading_label("Allomancy Input"))
	var hold_push_row := UIHelpers.labeled_checkbox("Hold to Push/Pull (off = toggle)", GameSettings.hold_to_use_push_pull)
	UIHelpers.get_checkbox(hold_push_row).toggled.connect(func(v: bool): GameSettings.hold_to_use_push_pull = v)
	box.add_child(hold_push_row)

	var hold_flare_row := UIHelpers.labeled_checkbox("Hold to Flare (off = toggle)", GameSettings.hold_to_use_flare)
	UIHelpers.get_checkbox(hold_flare_row).toggled.connect(func(v: bool): GameSettings.hold_to_use_flare = v)
	box.add_child(hold_flare_row)

	var assist_row := UIHelpers.labeled_slider("Aim Assist Strength", 0.0, 2.0, 0.1, GameSettings.aim_assist_strength)
	UIHelpers.get_slider(assist_row).value_changed.connect(func(v: float): GameSettings.aim_assist_strength = v)
	box.add_child(assist_row)

	var autoburn_row := UIHelpers.labeled_checkbox("Auto-Burn Basic Metals (Steel/Iron/Pewter/Tin)", GameSettings.auto_burn_basic_metals)
	UIHelpers.get_checkbox(autoburn_row).toggled.connect(func(v: bool): GameSettings.auto_burn_basic_metals = v)
	box.add_child(autoburn_row)

	box.add_child(UIHelpers.vsep(6))
	box.add_child(UIHelpers.heading_label("Controller"))
	var vibration_row := UIHelpers.labeled_checkbox("Vibration", GameSettings.vibration_enabled)
	UIHelpers.get_checkbox(vibration_row).toggled.connect(func(v: bool): GameSettings.vibration_enabled = v)
	box.add_child(vibration_row)

	var deadzone_row := UIHelpers.labeled_slider("Stick Deadzone", 0.0, 0.6, 0.02, GameSettings.stick_deadzone)
	UIHelpers.get_slider(deadzone_row).value_changed.connect(func(v: float):
		GameSettings.stick_deadzone = v
		GameSettings.apply_controls()
	)
	box.add_child(deadzone_row)

	return sb.root


func _on_close() -> void:
	GameSettings.save_settings()
	closed.emit()
