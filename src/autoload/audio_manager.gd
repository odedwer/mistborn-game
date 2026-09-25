extends Node
## Pooled positional/UI audio playback, ambience loops and layered music.
## See docs/ARCHITECTURE.md and docs/ASSETS.md for the API and asset list.
##
## API (kept stable for other systems):
##   play_3d(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void
##   play_ui(id: StringName, volume_db := 0.0) -> void
##   set_music_intensity(level: float) -> void   # 0..1
##   play_ambience(id: StringName) -> void
##   stop_ambience(id: StringName) -> void
##   play_music() -> void
##   stop_music() -> void

const SFX_DIR := "res://assets/audio/sfx/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const MUSIC_DIR := "res://assets/audio/music/"

const SFX_VOICE_COUNT := 48
const UI_VOICE_COUNT := 8
const MAX_HEAR_DISTANCE := 60.0
const PITCH_JITTER := 0.04  # +/- random pitch variation applied per play

const BUS_NAMES := ["Master", "Music", "SFX", "Voice", "Ambience", "UI"]

## id (StringName) -> Array[String] of file basenames (without extension), for
## random-variant selection. "footstep" is an alias for footstep_stone.
const REGISTRY := {
	&"push": ["push"],
	&"pull": ["pull"],
	&"coin_throw": ["coin_throw"],
	&"coin_hit": ["coin_hit_1", "coin_hit_2", "coin_hit_3"],
	&"coin_clink": ["coin_clink_1", "coin_clink_2", "coin_clink_3"],
	&"flare": ["flare"],
	&"metal_burn_start": ["metal_burn_start"],
	&"metal_depleted": ["metal_depleted"],
	&"vial_drink": ["vial_drink"],
	&"dagger_swing": ["dagger_swing_1", "dagger_swing_2"],
	&"dagger_hit": ["dagger_hit"],
	&"hit_flesh": ["hit_flesh_1", "hit_flesh_2"],
	&"jump": ["jump"],
	&"land_hard": ["land_hard"],
	&"footstep": ["footstep_stone_1", "footstep_stone_2", "footstep_stone_3", "footstep_stone_4"],
	&"footstep_stone": ["footstep_stone_1", "footstep_stone_2", "footstep_stone_3", "footstep_stone_4"],
	&"spear_swing": ["spear_swing"],
	&"javelin_throw": ["javelin_throw"],
	&"guard_alert": ["guard_alert"],
	&"thug_roar": ["thug_roar"],
	&"inquisitor_scream": ["inquisitor_scream"],
	&"enemy_death": ["enemy_death"],
}

const UI_REGISTRY := {
	&"ui_hover": ["ui_hover"],
	&"ui_click": ["ui_click"],
	&"ui_back": ["ui_back"],
	&"objective_complete": ["objective_complete"],
	&"mission_complete": ["mission_complete"],
}

const AMBIENCE_FILES := {
	&"ambience_night_city": "ambience_night_city",
	&"ambience_mist": "ambience_mist",
	&"ambience_canal_water": "ambience_canal_water",
}

const MUSIC_LAYERS := ["music_calm", "music_tension", "music_combat"]

var _stream_cache: Dictionary = {}   # String path -> AudioStream
var _missing_warned: Dictionary = {} # StringName -> true

var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _sfx_started_at: Array[int] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_started_at: Array[int] = []
var _next_token := 0

var _ambience_players: Dictionary = {} # StringName -> AudioStreamPlayer

var _music_players: Array[AudioStreamPlayer] = []
var _music_intensity := 0.0
var _music_playing := false

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_setup_buses()
	_setup_sfx_pool()
	_setup_ui_pool()
	_setup_music_players()
	if Events.has_signal("alert_level_changed"):
		Events.alert_level_changed.connect(_on_alert_level_changed)
	set_process(true)


func _process(_delta: float) -> void:
	_update_music_mix()


# ---------------------------------------------------------------------------
# Bus setup
# ---------------------------------------------------------------------------

func _setup_buses() -> void:
	for i in range(1, BUS_NAMES.size()):
		var bus_name: String = BUS_NAMES[i]
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1 and AudioServer.get_bus_effect_count(sfx_idx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.35
		reverb.wet = 0.12
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx_idx, reverb)

	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		var has_limiter := false
		for i in range(AudioServer.get_bus_effect_count(master_idx)):
			if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var comp := AudioEffectCompressor.new()
			comp.threshold = -18.0
			comp.ratio = 3.0
			AudioServer.add_bus_effect(master_idx, comp)
			var limiter := AudioEffectLimiter.new()
			limiter.ceiling_db = -0.3
			AudioServer.add_bus_effect(master_idx, limiter)


# ---------------------------------------------------------------------------
# Pools
# ---------------------------------------------------------------------------

func _setup_sfx_pool() -> void:
	for i in SFX_VOICE_COUNT:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = MAX_HEAR_DISTANCE
		add_child(p)
		_sfx_pool.append(p)
		_sfx_started_at.append(-1)


func _setup_ui_pool() -> void:
	for i in UI_VOICE_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_pool.append(p)
		_ui_started_at.append(-1)


func _setup_music_players() -> void:
	for name in MUSIC_LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music_players.append(p)


# ---------------------------------------------------------------------------
# Stream loading
# ---------------------------------------------------------------------------

func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	_stream_cache[path] = stream
	return stream


func _resolve_variant(id: StringName, table: Dictionary, dir: String) -> AudioStream:
	if not table.has(id):
		_warn_missing(id)
		return null
	var variants: Array = table[id]
	if variants.is_empty():
		_warn_missing(id)
		return null
	var pick: String = variants[_rng.randi_range(0, variants.size() - 1)]
	var stream := _load_stream(dir + pick + ".ogg")
	if stream == null:
		_warn_missing(id)
	return stream


func _warn_missing(id: StringName) -> void:
	if _missing_warned.has(id):
		return
	_missing_warned[id] = true
	push_warning("AudioManager: no audio registered/found for id '%s'" % id)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Plays a 3D positional sound effect. Picks a random variant and applies a
## small random pitch jitter for variety. Culls silently if too far from the
## active listener/camera, and steals the oldest voice when the pool is full.
func play_3d(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _resolve_variant(id, REGISTRY, SFX_DIR)
	if stream == null:
		return

	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and camera.global_position.distance_to(position) > MAX_HEAR_DISTANCE:
		return

	var player := _acquire_sfx_player()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch * (1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER))
	player.play()


## Plays a non-positional UI sound.
func play_ui(id: StringName, volume_db := 0.0) -> void:
	var stream := _resolve_variant(id, UI_REGISTRY, SFX_DIR)
	if stream == null:
		return
	var player := _acquire_ui_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	player.play()


func _acquire_sfx_player() -> AudioStreamPlayer3D:
	for i in _sfx_pool.size():
		if not _sfx_pool[i].playing:
			_sfx_started_at[i] = _next_token
			_next_token += 1
			return _sfx_pool[i]
	# Pool full: steal the oldest voice.
	var oldest_i := 0
	var oldest_token := _sfx_started_at[0]
	for i in range(1, _sfx_pool.size()):
		if _sfx_started_at[i] < oldest_token:
			oldest_token = _sfx_started_at[i]
			oldest_i = i
	_sfx_started_at[oldest_i] = _next_token
	_next_token += 1
	return _sfx_pool[oldest_i]


func _acquire_ui_player() -> AudioStreamPlayer:
	for i in _ui_pool.size():
		if not _ui_pool[i].playing:
			_ui_started_at[i] = _next_token
			_next_token += 1
			return _ui_pool[i]
	var oldest_i := 0
	var oldest_token := _ui_started_at[0]
	for i in range(1, _ui_pool.size()):
		if _ui_started_at[i] < oldest_token:
			oldest_token = _ui_started_at[i]
			oldest_i = i
	_ui_started_at[oldest_i] = _next_token
	_next_token += 1
	return _ui_pool[oldest_i]


## Number of SFX voices currently in use (for tests / debugging).
func active_sfx_voice_count() -> int:
	var n := 0
	for p in _sfx_pool:
		if p.playing:
			n += 1
	return n


func sfx_voice_capacity() -> int:
	return _sfx_pool.size()


# ---------------------------------------------------------------------------
# Ambience
# ---------------------------------------------------------------------------

func play_ambience(id: StringName) -> void:
	if _ambience_players.has(id):
		var existing: AudioStreamPlayer = _ambience_players[id]
		if not existing.playing:
			existing.play()
		return
	if not AMBIENCE_FILES.has(id):
		_warn_missing(id)
		return
	var stream := _load_stream(AMBIENCE_DIR + AMBIENCE_FILES[id] + ".ogg")
	if stream == null:
		_warn_missing(id)
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	var player := AudioStreamPlayer.new()
	player.bus = "Ambience"
	player.stream = stream
	add_child(player)
	_ambience_players[id] = player
	player.play()


func stop_ambience(id: StringName) -> void:
	if not _ambience_players.has(id):
		return
	var player: AudioStreamPlayer = _ambience_players[id]
	player.stop()
	player.queue_free()
	_ambience_players.erase(id)


# ---------------------------------------------------------------------------
# Music: three synced, looping layers crossfaded by intensity (0..1)
# ---------------------------------------------------------------------------

func play_music() -> void:
	if _music_playing:
		return
	for i in _music_players.size():
		var stream := _load_stream(MUSIC_DIR + MUSIC_LAYERS[i] + ".ogg")
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_music_players[i].stream = stream
		_music_players[i].play()
	_music_playing = true
	_update_music_mix()


func stop_music() -> void:
	for p in _music_players:
		p.stop()
	_music_playing = false


## `level` is 0..1. 0 = calm layer only, 0.5 = calm+tension blended,
## 1.0 = full combat layer. Crossfades continuously (not a hard switch).
func set_music_intensity(level: float) -> void:
	_music_intensity = clampf(level, 0.0, 1.0)
	_update_music_mix()


func _update_music_mix() -> void:
	if _music_players.size() < 3:
		return
	# 3-band crossfade: calm dominant at 0, tension at 0.5, combat at 1.0.
	var calm_w := clampf(1.0 - _music_intensity * 2.0, 0.0, 1.0)
	var tension_w := clampf(1.0 - absf(_music_intensity - 0.5) * 2.0, 0.0, 1.0)
	var combat_w := clampf((_music_intensity - 0.5) * 2.0, 0.0, 1.0)
	_music_players[0].volume_db = _weight_to_db(calm_w)
	_music_players[1].volume_db = _weight_to_db(tension_w)
	_music_players[2].volume_db = _weight_to_db(combat_w)


func _weight_to_db(w: float) -> float:
	if w <= 0.001:
		return -80.0
	return linear_to_db(w)


## [calm_weight, tension_weight, combat_weight] at the current intensity.
## Exposed for tests; also handy for a debug HUD overlay.
func debug_music_weights() -> Array[float]:
	var calm_w := clampf(1.0 - _music_intensity * 2.0, 0.0, 1.0)
	var tension_w := clampf(1.0 - absf(_music_intensity - 0.5) * 2.0, 0.0, 1.0)
	var combat_w := clampf((_music_intensity - 0.5) * 2.0, 0.0, 1.0)
	return [calm_w, tension_w, combat_w]


func _on_alert_level_changed(level: int) -> void:
	match level:
		0:
			set_music_intensity(0.0)
		1:
			set_music_intensity(0.5)
		2:
			set_music_intensity(1.0)
		_:
			set_music_intensity(0.0)
