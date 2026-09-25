extends Node
## Global event bus. Systems emit here instead of holding references to each
## other, so the HUD, audio, AI and mission scripts stay decoupled.

# --- Allomancy -------------------------------------------------------------
signal metal_burn_changed(allomancer: Node, metal: int, burning: bool)
signal metal_flare_changed(allomancer: Node, metal: int, flaring: bool)
signal metal_reserve_changed(allomancer: Node, metal: int, amount: float)
signal metal_depleted(allomancer: Node, metal: int)
## Emitted each frame a Push/Pull is applied. `strength` is 0..1 for VFX/audio.
signal allomantic_line_used(allomancer: Node, target: Node, metal: int, strength: float)
## Bronze-detectable pulse. Copperclouds suppress it.
signal allomantic_pulse(source: Node, metal: int, position: Vector3)
signal duralumin_burst(allomancer: Node, metals: Array)
## Atium started/stopped for an allomancer (the player's slows time to ~60%).
signal atium_vision_changed(allomancer: Node, active: bool)
## The local player's bronze sensed a pulse from `source`.
signal allomantic_pulse_sensed(source: Node, metal: int, position: Vector3)
## The Push/Pull target under the crosshair changed (null = none).
signal line_target_changed(allomancer: Node, target: Node)

# --- Combat ----------------------------------------------------------------
signal damage_dealt(target: Node, amount: float, source: Node, kind: StringName)
signal actor_died(actor: Node, killer: Node)
signal player_health_changed(current: float, maximum: float)
signal player_died
## Player coin pouch / vial count changed.
signal player_inventory_changed(coins: int, vials: int)

# --- Stealth / AI ----------------------------------------------------------
signal noise_emitted(position: Vector3, loudness: float, source: Node)
signal alert_level_changed(level: int)  # 0 = calm, 1 = suspicious, 2 = combat

# --- Mission / world -------------------------------------------------------
signal objective_updated(id: StringName, text: String, done: bool)
signal mission_completed(id: StringName)
signal mission_failed(id: StringName, reason: String)
signal checkpoint_reached(id: StringName)
signal pickup_collected(kind: StringName, amount: float)
signal hint_requested(text: String, duration: float)

# --- Game flow -------------------------------------------------------------
signal pause_toggled(paused: bool)
signal settings_changed

# --- Act I: dialogue / cutscenes / social stealth ---------------------------
## A `DialogueData` started/finished playing (see `src/dialogue/`).
signal dialogue_started(id: StringName)
signal dialogue_line_shown(dialogue_id: StringName, speaker: String, text: String)
signal dialogue_finished(id: StringName)
## A story flag changed (dialogue choice, mission action). `value` is
## free-form (usually `true`, sometimes a count or string).
signal dialogue_flag_set(flag: StringName, value: Variant)
## Lady Valette's suspicion meter (0..max_value) changed.
signal suspicion_changed(value: float, max_value: float)
## A `CutsceneData` letterbox/pan/subtitle sequence started/finished.
signal cutscene_started(id: StringName)
signal cutscene_finished(id: StringName)
## The player crossed a scene-transition door into/out of an interior.
signal interior_entered(scene_path: String)
signal interior_exited
