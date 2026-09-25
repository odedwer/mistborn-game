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


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


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

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(880, 560)
	vbox.add_child(tabs)
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_controls_tab())
	tabs.add_child(_build_gameplay_tab())

	var close_btn := UIHelpers.button("Close")
	close_btn.pressed.connect(_on_close)
	vbox.add_child(close_btn)


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


func _unhandled_input(event: InputEvent) -> void:
	if _listening_for == "":
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

	var shake_row := UIHelpers.labeled_slider("Camera Shake", 0.0, 2.0, 0.1, GameSettings.camera_shake_scale)
	UIHelpers.get_slider(shake_row).value_changed.connect(func(v: float): GameSettings.camera_shake_scale = v)
	box.add_child(shake_row)

	var subs_row := UIHelpers.labeled_checkbox("Subtitles", GameSettings.subtitles_enabled)
	UIHelpers.get_checkbox(subs_row).toggled.connect(func(v: bool): GameSettings.subtitles_enabled = v)
	box.add_child(subs_row)

	return sb.root


func _on_close() -> void:
	GameSettings.save_settings()
	closed.emit()
