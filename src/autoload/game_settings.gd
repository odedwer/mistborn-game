extends Node
## Persistent user settings (graphics, audio, controls, gameplay).
##
## Persisted to `user://settings.cfg` as a ConfigFile. Call `apply_all()` after
## `load_settings()` (done automatically in `_ready`) or after changing values
## in bulk. Individual setters apply immediately and emit `Events.settings_changed`.
##
## Environment-related graphics settings (SSAO/SSIL/SDFGI/volumetric fog/render
## scale) are applied to the first `WorldEnvironment` found among nodes in the
## group `"world_environment"`. World code should add its `WorldEnvironment`
## node to that group so these settings take effect. Volumetric fog *density*
## (mist look) is left to the world's `MistController`; this file only forwards
## a quality level to any node in the group `"mist_controller"` that implements
## `set_quality(level: int)`.

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum Quality { OFF, LOW, MEDIUM, HIGH, ULTRA }
enum Difficulty { STORY, NORMAL, HARD }

# --- Graphics ---------------------------------------------------------------
var preset: Preset = Preset.MEDIUM
var resolution: Vector2i = Vector2i(1920, 1080)
var window_mode: WindowMode = WindowMode.WINDOWED
var vsync: bool = true
var fps_cap: int = 0
var render_scale: float = 1.0
var upscale_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_FSR2
var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var use_taa: bool = true
var use_fxaa: bool = false
var shadow_quality: Quality = Quality.MEDIUM
var ssao_enabled: bool = false
var ssil_enabled: bool = false
var sdfgi_enabled: bool = false
var volumetric_fog_quality: Quality = Quality.MEDIUM
var ash_particle_density: float = 1.0
var lod_bias: float = 1.0
var view_distance: float = 300.0

# --- Audio -------------------------------------------------------------------
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var voice_volume: float = 1.0
var ambience_volume: float = 0.9

const AUDIO_BUSES := ["Music", "SFX", "Voice", "Ambience", "UI"]

# --- Controls (kept for compatibility with existing callers) ----------------
var mouse_sensitivity := 0.0025
var invert_y := false
var fov := 80.0
## action name (String) -> Array of binding triples, see InputSetup.
var binding_overrides: Dictionary = {}

# --- Gameplay ------------------------------------------------------------------
var difficulty: Difficulty = Difficulty.NORMAL
var hints_enabled: bool = true
var camera_shake_scale: float = 1.0
var subtitles_enabled: bool = true


func _ready() -> void:
	load_settings()
	apply_all()


## Picks a sane default preset from the GPU. Integrated GPUs default to Low.
func detect_default_preset() -> Preset:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var integrated_markers := ["intel", "uhd", "iris", "vega 3", "vega 8", "radeon graphics"]
	for marker in integrated_markers:
		if adapter.contains(marker) or vendor.contains(marker):
			return Preset.LOW
	if adapter == "" :
		return Preset.LOW
	return Preset.MEDIUM


## Applies a graphics preset, overwriting the individual graphics fields.
func set_preset(p: Preset) -> void:
	preset = p
	match p:
		Preset.LOW:
			render_scale = 0.75
			msaa = Viewport.MSAA_DISABLED
			use_taa = false
			use_fxaa = true
			shadow_quality = Quality.LOW
			ssao_enabled = false
			ssil_enabled = false
			sdfgi_enabled = false
			volumetric_fog_quality = Quality.LOW
			ash_particle_density = 0.3
			lod_bias = 2.0
			view_distance = 150.0
		Preset.MEDIUM:
			render_scale = 0.9
			msaa = Viewport.MSAA_2X
			use_taa = true
			use_fxaa = false
			shadow_quality = Quality.MEDIUM
			ssao_enabled = true
			ssil_enabled = false
			sdfgi_enabled = false
			volumetric_fog_quality = Quality.MEDIUM
			ash_particle_density = 0.7
			lod_bias = 1.5
			view_distance = 250.0
		Preset.HIGH:
			render_scale = 1.0
			msaa = Viewport.MSAA_4X
			use_taa = true
			use_fxaa = false
			shadow_quality = Quality.HIGH
			ssao_enabled = true
			ssil_enabled = true
			sdfgi_enabled = false
			volumetric_fog_quality = Quality.HIGH
			ash_particle_density = 1.0
			lod_bias = 1.0
			view_distance = 350.0
		Preset.ULTRA:
			render_scale = 1.0
			msaa = Viewport.MSAA_4X
			use_taa = true
			use_fxaa = false
			shadow_quality = Quality.ULTRA
			ssao_enabled = true
			ssil_enabled = true
			sdfgi_enabled = true
			volumetric_fog_quality = Quality.ULTRA
			ash_particle_density = 1.0
			lod_bias = 0.5
			view_distance = 500.0
		Preset.CUSTOM:
			pass
	apply_graphics()
	Events.settings_changed.emit()


func mark_custom() -> void:
	preset = Preset.CUSTOM


# --- Persistence -------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("graphics", "preset", int(preset))
	cfg.set_value("graphics", "resolution", resolution)
	cfg.set_value("graphics", "window_mode", int(window_mode))
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "upscale_mode", int(upscale_mode))
	cfg.set_value("graphics", "msaa", int(msaa))
	cfg.set_value("graphics", "use_taa", use_taa)
	cfg.set_value("graphics", "use_fxaa", use_fxaa)
	cfg.set_value("graphics", "shadow_quality", int(shadow_quality))
	cfg.set_value("graphics", "ssao_enabled", ssao_enabled)
	cfg.set_value("graphics", "ssil_enabled", ssil_enabled)
	cfg.set_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value("graphics", "volumetric_fog_quality", int(volumetric_fog_quality))
	cfg.set_value("graphics", "ash_particle_density", ash_particle_density)
	cfg.set_value("graphics", "lod_bias", lod_bias)
	cfg.set_value("graphics", "view_distance", view_distance)

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "voice_volume", voice_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)

	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("controls", "binding_overrides", binding_overrides)

	cfg.set_value("gameplay", "difficulty", int(difficulty))
	cfg.set_value("gameplay", "hints_enabled", hints_enabled)
	cfg.set_value("gameplay", "camera_shake_scale", camera_shake_scale)
	cfg.set_value("gameplay", "subtitles_enabled", subtitles_enabled)

	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		preset = detect_default_preset()
		set_preset(preset)
		return

	preset = int(cfg.get_value("graphics", "preset", Preset.MEDIUM)) as Preset
	resolution = cfg.get_value("graphics", "resolution", Vector2i(1920, 1080))
	window_mode = int(cfg.get_value("graphics", "window_mode", WindowMode.WINDOWED)) as WindowMode
	vsync = cfg.get_value("graphics", "vsync", true)
	fps_cap = cfg.get_value("graphics", "fps_cap", 0)
	render_scale = cfg.get_value("graphics", "render_scale", 1.0)
	upscale_mode = int(cfg.get_value("graphics", "upscale_mode", Viewport.SCALING_3D_MODE_FSR2)) as Viewport.Scaling3DMode
	msaa = int(cfg.get_value("graphics", "msaa", Viewport.MSAA_DISABLED)) as Viewport.MSAA
	use_taa = cfg.get_value("graphics", "use_taa", true)
	use_fxaa = cfg.get_value("graphics", "use_fxaa", false)
	shadow_quality = int(cfg.get_value("graphics", "shadow_quality", Quality.MEDIUM)) as Quality
	ssao_enabled = cfg.get_value("graphics", "ssao_enabled", false)
	ssil_enabled = cfg.get_value("graphics", "ssil_enabled", false)
	sdfgi_enabled = cfg.get_value("graphics", "sdfgi_enabled", false)
	volumetric_fog_quality = int(cfg.get_value("graphics", "volumetric_fog_quality", Quality.MEDIUM)) as Quality
	ash_particle_density = cfg.get_value("graphics", "ash_particle_density", 1.0)
	lod_bias = cfg.get_value("graphics", "lod_bias", 1.0)
	view_distance = cfg.get_value("graphics", "view_distance", 300.0)

	master_volume = cfg.get_value("audio", "master_volume", 1.0)
	music_volume = cfg.get_value("audio", "music_volume", 0.8)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
	voice_volume = cfg.get_value("audio", "voice_volume", 1.0)
	ambience_volume = cfg.get_value("audio", "ambience_volume", 0.9)

	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", 0.0025)
	invert_y = cfg.get_value("controls", "invert_y", false)
	fov = cfg.get_value("controls", "fov", 80.0)
	binding_overrides = cfg.get_value("controls", "binding_overrides", {})

	difficulty = int(cfg.get_value("gameplay", "difficulty", Difficulty.NORMAL)) as Difficulty
	hints_enabled = cfg.get_value("gameplay", "hints_enabled", true)
	camera_shake_scale = cfg.get_value("gameplay", "camera_shake_scale", 1.0)
	subtitles_enabled = cfg.get_value("gameplay", "subtitles_enabled", true)


# --- Apply --------------------------------------------------------------------

func apply_all() -> void:
	apply_graphics()
	apply_audio()
	apply_controls()
	Events.settings_changed.emit()


func apply_graphics() -> void:
	# Window / display. Skipped headlessly (no window to configure).
	if DisplayServer.get_name() != "headless":
		match window_mode:
			WindowMode.WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			WindowMode.BORDERLESS:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			WindowMode.FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if window_mode == WindowMode.WINDOWED:
			DisplayServer.window_set_size(resolution)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap

	var vp := get_tree().root
	vp.scaling_3d_scale = render_scale
	vp.scaling_3d_mode = upscale_mode
	vp.msaa_3d = msaa
	vp.use_taa = use_taa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if use_fxaa else Viewport.SCREEN_SPACE_AA_DISABLED

	_apply_shadow_quality()
	_apply_world_environment()
	_apply_mist_controller()


func _apply_shadow_quality() -> void:
	var sizes := {Quality.OFF: 0, Quality.LOW: 1024, Quality.MEDIUM: 2048, Quality.HIGH: 4096, Quality.ULTRA: 8192}
	RenderingServer.directional_shadow_atlas_set_size(sizes.get(shadow_quality, 2048), true)


## Applies environment-related settings to the active WorldEnvironment, found
## via nodes in the group "world_environment" (see class doc comment).
func _apply_world_environment() -> void:
	var nodes := get_tree().get_nodes_in_group("world_environment")
	for n in nodes:
		var we := n as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.ssao_enabled = ssao_enabled
		env.ssil_enabled = ssil_enabled
		env.sdfgi_enabled = sdfgi_enabled
		env.volumetric_fog_enabled = volumetric_fog_quality != Quality.OFF


func _apply_mist_controller() -> void:
	for n in get_tree().get_nodes_in_group("mist_controller"):
		if n.has_method("set_quality"):
			n.call("set_quality", int(volumetric_fog_quality))


func apply_audio() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Voice")
	_ensure_bus("Ambience")
	_ensure_bus("UI")
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	_set_bus_volume("Ambience", ambience_volume)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.5)))


func apply_controls() -> void:
	InputSetup.apply_bindings(binding_overrides)


## Stores a rebind for `action` (see InputSetup for the binding-triple format).
func set_binding(action: String, binding: Array) -> void:
	binding_overrides[action] = [binding]
	apply_controls()
	Events.settings_changed.emit()


func reset_bindings() -> void:
	binding_overrides.clear()
	apply_controls()
	Events.settings_changed.emit()
