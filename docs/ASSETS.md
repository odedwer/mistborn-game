# Assets: textures & audio

All textures and audio in `assets/` are **procedurally generated** by the
Python scripts in `tools/`, with fixed seeds for determinism. They are
**original works** produced for this project — safe to redistribute under
the same non-commercial fan-project terms as the rest of the repo (CC0 for
anything reusable outside it: no samples, no third-party assets, no network
downloads are used to build them).

## Regenerating

```bash
pip install -r tools/requirements.txt
python3 tools/gen_textures.py          # -> assets/textures/*.png
python3 tools/gen_audio.py             # -> assets/audio/{sfx,ambience,music}/*.ogg
godot --headless --import              # re-import everything
```

Both generators are deterministic (seeded by a fixed base seed derived from
the project date plus a stable per-asset hash), so re-running them produces
byte-identical output. `tools/gen_textures.py --only <name1,name2>` limits
the run to specific materials while iterating.

Regenerate + reimport + retest in one go with `tools/run_tests.sh`.

### A libsndfile gotcha

The `soundfile`/libsndfile build used here **segfaults** when writing a
single large OGG Vorbis buffer in one `sf.write()` call (observed above
~45 seconds of audio, e.g. the ambience and music loops). `gen_audio.py`'s
`save()` works around this by streaming the buffer to `sf.SoundFile` in
64k-frame chunks, which is entirely stable. Keep using that helper (don't
switch back to a single `sf.write()`) if you extend the script.

## Textures (`assets/textures/`)

Ten seamless, tileable 1024×1024 PBR material sets, each with
`<name>_albedo.png`, `<name>_normal.png` (OpenGL/Y+ convention, matching
Godot), `<name>_roughness.png` and `<name>_ao.png`:

| id | look |
|---|---|
| `stone_wall` | irregular masonry blocks, mortar joints |
| `brick_soot` | running-bond brick, soot streaks |
| `cobblestone` | flagstone-style street paving |
| `slate_roof` | overlapping staggered slate shingles |
| `wood_planks` | vertical plank siding with grain |
| `iron_rusty` | brushed iron with rust patches |
| `plaster_dirty` | cracked, stained plaster render |
| `cloth_mistcloak` | dark grey twill-weave fabric |
| `leather` | pored, wrinkled leather |
| `obsidian` | near-black glossy volcanic glass |

Tiling is exact by construction: albedo/height noise is synthesized directly
in the Fourier domain (`spectral_noise`, periodic by definition) or via
Worley/cellular noise on a wrapped 3×3 torus of points (`tileable_worley`),
and normal maps are derived from height with periodic (wrap-around) central
differences. Soot/ash accumulation (Luthadel's constant ashfall) is added as
a periodic vertical cosine envelope so it darkens the "upper" band of the
tile without breaking the vertical seam.

Effect textures (all in the same folder):

| file | use |
|---|---|
| `ash_flake.png` | 4×4 atlas of small alpha ash-flake sprites |
| `coin_face_albedo.png` / `coin_face_normal.png` | 512² coin face |
| `vial_label_albedo.png` | metal vial paper label |
| `spark.png` | additive spark/glint sprite |
| `soft_particle.png` | generic soft round particle (dust, mist puffs) |

Import settings: VRAM compression (`compress/mode=2`, BPTC/S3TC on desktop),
mipmaps on for every texture, and `compress/normal_map=1` on every
`*_normal.png` so Godot treats it as a normal map. These are baked into the
committed `.import` files — after `godot --headless --import` there is
nothing left to fix by hand. If you add a new material to
`gen_textures.py`, re-run the import and re-check its `.import` file picked
up the same settings (the importer copies them from the last-imported PNG of
the same type, but a first-time normal map should be checked).

## Audio (`assets/audio/`)

Everything is synthesized (additive/FM/modal synthesis, filtered noise,
envelopes, a synthetic convolution "room" impulse response for reverb) —
OGG Vorbis, 44.1 kHz. SFX are **mono** (for 3D positional playback);
ambience and music are **stereo**.

### SFX (`assets/audio/sfx/`)

Single-shot ids (`push`, `pull`, `coin_throw`, `flare`, `metal_burn_start`,
`metal_depleted`, `vial_drink`, `dagger_hit`, `jump`, `land_hard`,
`spear_swing`, `javelin_throw`, `guard_alert`, `thug_roar`,
`inquisitor_scream`, `enemy_death`, `ui_hover`, `ui_click`, `ui_back`,
`objective_complete`, `mission_complete`) plus multi-variant ids picked at
random by `AudioManager` (`coin_hit_1..3`, `coin_clink_1..3`,
`dagger_swing_1..2`, `hit_flesh_1..2`, `footstep_stone_1..4`).

### Ambience (`assets/audio/ambience/`, 60 s seamless loops)

`ambience_night_city` (wind, distant creaks, ash hiss), `ambience_mist`
(airy, thin), `ambience_canal_water` (lapping water, bubbles). Looped by
crossfading filtered noise's tail into its head before the cut point, plus
strictly periodic tonal components (integer cycle count over the loop
length), so the loop point is inaudible.

### Music (`assets/audio/music/`, ~64 s seamless loops)

Three layers at the same tempo (66 BPM) and key, meant to be played
simultaneously and crossfaded by `AudioManager.set_music_intensity()`:

- `music_calm` — pads + sparse plucked notes.
- `music_tension` — adds a rhythmic ostinato.
- `music_combat` — adds percussion on top.

Loop length is an exact integer number of beats, so all three loop in
lock-step forever without drifting out of sync.

Import settings: `loop=true` is baked into every ambience/music `.import`
file (the `oggvorbisstr` importer's loop flag).

## `src/autoload/audio_manager.gd`

Replaces the stub with the same public surface plus additions:

```gdscript
play_3d(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void
play_ui(id: StringName, volume_db := 0.0) -> void
set_music_intensity(level: float) -> void   # 0..1, crossfades calm/tension/combat
play_ambience(id: StringName) -> void
stop_ambience(id: StringName) -> void
play_music() -> void
stop_music() -> void
```

- A `REGISTRY` / `UI_REGISTRY` dictionary maps ids to one or more file
  variants; `play_3d`/`play_ui` pick a random variant and apply a small
  random pitch jitter (±4%) each call. `"footstep"` is an alias for
  `"footstep_stone"`.
- 48 pooled `AudioStreamPlayer3D` voices (SFX) and 8 pooled
  `AudioStreamPlayer` voices (UI). When the pool is full, the oldest voice
  is stolen. 3D SFX are culled (silently skipped) beyond 60 m from the
  active camera, if one exists.
- Buses `Master`, `Music`, `SFX`, `Voice`, `Ambience`, `UI` are created in
  code on `_ready()` if missing (idempotent — safe to call repeatedly, e.g.
  across test runs). A light `AudioEffectReverb` sits on `SFX`; a
  compressor + limiter sit on `Master`.
- Music plays all three layers simultaneously and crossfades their volume
  by intensity (0 = calm only, 0.5 = tension peak, 1.0 = combat only).
  `Events.alert_level_changed` (0/1/2) is wired automatically to
  intensity 0.0 / 0.5 / 1.0.
- A missing id never crashes: it's silently ignored and warned once (not
  spammed on repeat calls).

## `tools/fetch_assets.py` (optional, needs real internet)

The sandbox this was built in blocks Poly Haven, ambientCG, Kenney,
OpenGameArt and Freesound, so this project ships fully art-complete without
them. If you (a developer, on your own machine, with normal internet
access) want higher-fidelity real-world PBR textures or an HDRI for
lighting reference, `tools/fetch_assets.py` downloads CC0 assets from the
[Poly Haven API](https://api.polyhaven.com) into `assets/external/`
(gitignored — nothing it downloads is committed) and writes a
`manifest.json` recording what was fetched and its license:

```bash
pip install requests
python3 tools/fetch_assets.py --list textures
python3 tools/fetch_assets.py --textures cobblestone_02,brick_wall_001 --res 2k
python3 tools/fetch_assets.py --hdri qwantani_dusk_2 --res 2k
```

Everything Poly Haven serves is CC0 (public domain).

## Known issues / follow-ups

- Roughness/AO maps are exported as full RGB (grayscale replicated across
  channels) rather than packed into a single ORM texture; fine for now,
  worth packing into one `<name>_orm.png` (R=AO, G=Roughness, B=Metallic)
  later if texture-fetch overhead matters on lower-end hardware.
- `cobblestone` reads more like large flagstone paving than small rounded
  cobbles at 1024² — adequate for the "narrow cobbled streets" look at
  normal viewing distance, but a tighter Worley point count would give
  smaller stones if a closer look is needed.
- Voice pool statistics (`active_sfx_voice_count`, `sfx_voice_capacity`) are
  exposed on `AudioManager` for tests/debugging; feel free to wire them into
  a debug overlay.
