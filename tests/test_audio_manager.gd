extends TestCase
## Tests for AudioManager: registry resolution, pool limits, missing-id
## safety and music intensity mapping. These are non-visual/non-audible
## checks (no actual sound output is verified, only state).


func test_registry_has_expected_ids() -> void:
	assert_true(AudioManager.REGISTRY.has(&"push"), "push registered")
	assert_true(AudioManager.REGISTRY.has(&"pull"), "pull registered")
	assert_true(AudioManager.REGISTRY.has(&"coin_hit"), "coin_hit registered")
	assert_true(AudioManager.UI_REGISTRY.has(&"ui_click"), "ui_click registered")
	assert_true(AudioManager.AMBIENCE_FILES.has(&"ambience_night_city"), "ambience registered")


func test_footstep_alias_matches_footstep_stone() -> void:
	var a: Array = AudioManager.REGISTRY[&"footstep"]
	var b: Array = AudioManager.REGISTRY[&"footstep_stone"]
	assert_eq(a, b, "footstep is an alias for footstep_stone")
	assert_true(a.size() >= 4, "footstep has multiple variants")


func test_variant_lists_are_non_empty() -> void:
	for id in AudioManager.REGISTRY.keys():
		var variants: Array = AudioManager.REGISTRY[id]
		assert_true(variants.size() > 0, "id '%s' has at least one variant" % id)


func test_play_3d_missing_id_does_not_crash() -> void:
	AudioManager.play_3d(&"totally_not_a_real_sound_id", Vector3.ZERO)
	# Calling it twice must not raise or spam differently; still no crash.
	AudioManager.play_3d(&"totally_not_a_real_sound_id", Vector3.ZERO)
	assert_true(true, "play_3d with an unknown id returned without error")


func test_play_ui_missing_id_does_not_crash() -> void:
	AudioManager.play_ui(&"nonexistent_ui_sound")
	assert_true(true, "play_ui with an unknown id returned without error")


func test_pool_never_exceeds_voice_capacity() -> void:
	var capacity := AudioManager.sfx_voice_capacity()
	for i in range(capacity * 3):
		AudioManager.play_3d(&"push", Vector3(i, 0, 0))
	assert_true(AudioManager.active_sfx_voice_count() <= capacity,
		"active voices never exceed the pool capacity")
	assert_eq(AudioManager.active_sfx_voice_count(), capacity,
		"pool is fully saturated after more requests than voices")


func test_music_intensity_mapping_calm() -> void:
	AudioManager.set_music_intensity(0.0)
	var w := AudioManager.debug_music_weights()
	assert_almost(w[0], 1.0, 0.01, "calm weight at intensity 0")
	assert_almost(w[2], 0.0, 0.01, "combat weight at intensity 0")


func test_music_intensity_mapping_tension() -> void:
	AudioManager.set_music_intensity(0.5)
	var w := AudioManager.debug_music_weights()
	assert_almost(w[1], 1.0, 0.01, "tension weight peaks at intensity 0.5")


func test_music_intensity_mapping_combat() -> void:
	AudioManager.set_music_intensity(1.0)
	var w := AudioManager.debug_music_weights()
	assert_almost(w[2], 1.0, 0.01, "combat weight at intensity 1")
	assert_almost(w[0], 0.0, 0.01, "calm weight fades out at intensity 1")


func test_alert_level_changed_drives_intensity() -> void:
	Events.alert_level_changed.emit(0)
	assert_almost(AudioManager.debug_music_weights()[0], 1.0, 0.01, "alert 0 -> calm")
	Events.alert_level_changed.emit(2)
	assert_almost(AudioManager.debug_music_weights()[2], 1.0, 0.01, "alert 2 -> combat")
	# Reset so later tests (and a real game session) start calm again.
	Events.alert_level_changed.emit(0)


func test_expected_audio_files_exist_on_disk() -> void:
	for id in AudioManager.REGISTRY.keys():
		for variant in AudioManager.REGISTRY[id]:
			var path := "res://assets/audio/sfx/%s.ogg" % variant
			assert_true(ResourceLoader.exists(path), "missing sfx file: %s" % path)
	for id in AudioManager.UI_REGISTRY.keys():
		for variant in AudioManager.UI_REGISTRY[id]:
			var path := "res://assets/audio/sfx/%s.ogg" % variant
			assert_true(ResourceLoader.exists(path), "missing ui sfx file: %s" % path)
	for id in AudioManager.AMBIENCE_FILES.keys():
		var path := "res://assets/audio/ambience/%s.ogg" % AudioManager.AMBIENCE_FILES[id]
		assert_true(ResourceLoader.exists(path), "missing ambience file: %s" % path)
	for layer in AudioManager.MUSIC_LAYERS:
		var path := "res://assets/audio/music/%s.ogg" % layer
		assert_true(ResourceLoader.exists(path), "missing music file: %s" % path)
