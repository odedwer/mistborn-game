extends TestCase
## GameSettings persistence and preset application.


func test_preset_low_sets_expected_values() -> void:
	GameSettings.set_preset(GameSettings.Preset.LOW)
	assert_eq(GameSettings.shadow_quality, GameSettings.Quality.LOW)
	assert_false(GameSettings.sdfgi_enabled)
	assert_almost(GameSettings.render_scale, 0.75)


func test_preset_ultra_enables_everything() -> void:
	GameSettings.set_preset(GameSettings.Preset.ULTRA)
	assert_true(GameSettings.ssao_enabled)
	assert_true(GameSettings.ssil_enabled)
	assert_true(GameSettings.sdfgi_enabled)
	assert_eq(GameSettings.shadow_quality, GameSettings.Quality.ULTRA)


func test_save_load_roundtrip() -> void:
	GameSettings.set_preset(GameSettings.Preset.HIGH)
	GameSettings.master_volume = 0.42
	GameSettings.mouse_sensitivity = 0.0033
	GameSettings.binding_overrides = {"jump": [[InputSetup.KEY, KEY_J]]}
	GameSettings.save_settings()

	GameSettings.master_volume = 1.0
	GameSettings.mouse_sensitivity = 0.0025
	GameSettings.binding_overrides = {}
	GameSettings.preset = GameSettings.Preset.LOW

	GameSettings.load_settings()
	assert_eq(GameSettings.preset, GameSettings.Preset.HIGH)
	assert_almost(GameSettings.master_volume, 0.42)
	assert_almost(GameSettings.mouse_sensitivity, 0.0033)
	assert_true(GameSettings.binding_overrides.has("jump"))


func test_audio_buses_created() -> void:
	GameSettings.apply_audio()
	for bus_name in GameSettings.AUDIO_BUSES:
		assert_true(AudioServer.get_bus_index(bus_name) != -1, "bus " + bus_name)


func test_detect_default_preset_is_a_valid_enum_value() -> void:
	var p := GameSettings.detect_default_preset()
	assert_true(p in [GameSettings.Preset.LOW, GameSettings.Preset.MEDIUM, GameSettings.Preset.HIGH, GameSettings.Preset.ULTRA])
