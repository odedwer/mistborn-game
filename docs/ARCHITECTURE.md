# Architecture

**Mistborn: Ashes of Luthadel** is a non-commercial fan game.
Engine: **Godot 4.7.2** (Forward+ renderer, Vulkan; OpenGL fallback) · Physics: **Jolt** · Language: **GDScript** (statically typed).
Targets: Windows x86_64 and Linux x86_64.

## Directory layout

| Path | Contents | Owner |
|---|---|---|
| `src/autoload/` | Global singletons (see below) | shared |
| `src/allomancy/` | Metal definitions, `Metallic`, `Allomancer`, line VFX | allomancy |
| `src/player/` | Player controller, camera, player scene | allomancy |
| `src/combat/` | `Health`, coins, melee hitboxes, damage helpers | allomancy (coin), enemies (melee) |
| `src/enemies/` | Enemy actors, AI, perception | enemies |
| `src/world/` | Procedural Luthadel generator, environment, mists, ash, props | world |
| `src/ui/` | HUD, menus, settings screens | ui |
| `src/mission/` | Mission director, objectives, triggers, checkpoints | ui |
| `assets/` | Generated textures, audio, models, shaders | assets |
| `tools/` | Python asset generators, build scripts | assets / build |
| `tests/` | Headless test runner and tests | everyone |
| `scenes/` | Top-level scenes: `main_menu.tscn`, `game.tscn`, `test/*.tscn` | integration |

## Autoloads (singletons)

| Name | File | Purpose |
|---|---|---|
| `Events` | `src/autoload/events.gd` | Global signal bus. **Use it instead of cross-references.** |
| `GameSettings` | `src/autoload/game_settings.gd` | Settings persisted to `user://settings.cfg`; applies graphics presets. |
| `InputSetup` | `src/autoload/input_setup.gd` | Registers all input actions in code. Action names are defined there. |
| `MetalRegistry` | `src/autoload/metal_registry.gd` | Spatial hash of every `Metallic`. `query_radius(origin, r)`. |
| `GameState` | `src/autoload/game_state.gd` | Mission progress, checkpoints, save/load (`user://saves/`). |
| `AudioManager` | `src/autoload/audio_manager.gd` | Pooled SFX `play_3d(id, pos)`, `play_ui(id)`, music intensity. |

## Physics layers

| # | Name | Used by |
|---|---|---|
| 1 | world | Static level geometry |
| 2 | player | Player body |
| 3 | enemies | Enemy bodies |
| 4 | metal_props | Loose rigid props (carts, scrap, lamps) |
| 5 | coins | Coins and thrown metal projectiles |
| 6 | triggers | Area3D triggers for missions and pickups |
| 7 | ragdoll | Dead bodies / debris |

Bitmask helper: layer *n* has the value `1 << (n-1)`.

## Core contracts

### Metals
`Metal.Type` enum in `src/allomancy/metal.gd`. Always refer to metals by this enum. Colours, names, burn rates and max reserve live there.

### `Metallic` (src/allomancy/metallic.gd)
A child node of any physics body that contains metal. It registers itself with `MetalRegistry`.
- `metal_mass`: the amount of metal. It scales the line's visual thickness and lets the target pick heavy anchors.
- `anchored`: the object can't move, so the allomancer gets the whole reaction.
- `shielded`: metal inside a body, which can't be affected (e.g. Inquisitor spikes).
- `apply_allomantic_force(force, delta)`:
  - For a RigidBody3D, it calls `apply_force` at the metal's position.
  - For any other body, it calls `receive_allomantic_force(force, delta, metallic)`.

### Bodies that receive allomantic forces
Characters (player and enemies wearing metal) implement:
```gdscript
func get_allomantic_mass() -> float        # kg
func receive_allomantic_force(force: Vector3, delta: float, from: Metallic) -> void
```
Enemies wearing metal armour carry a `Metallic` child on the armour. The player can Push them off their feet, and a Push on an armoured guard also pushes the player away from them.

### Push/Pull physics (Newton's third law, mass-weighted)
When an allomancer at `A` Pushes metal at `M`:
- `dir = (M - A).normalized()`
- `F = base_force * strength * falloff(distance)`
  - `base_force` defaults to 3000 N.
  - `strength` is 1.0, or `Metal.FLARE_EFFECT_MULT` while flaring (×10 with duralumin).
  - `falloff` is full strength to 10 m, fading to zero at `current_range()` (40 m, or 60 m flared).
- The reaction is split by mass: the lighter side takes the motion.
  - A free coin flies away and barely moves the allomancer.
  - An anchored or braced target gives the allomancer the full reaction. That covers `anchored`, static bodies, and a coin pressed against the world along the push direction (checked with a short raycast).
  - Metal heavier than the allomancer moves the allomancer mostly.
- The reaction on the allomancer fades once their speed along the line passes ~34 m/s (higher when flaring). This keeps steel-jumps controllable. Flaring, duralumin and dives are how you reach 60–80 m/s.
- Pulling a heavy anchor (>60 kg) while airborne tethers the allomancer, which gives a swing/zip.
See `src/allomancy/allomancer.gd` for the exact code; the tuning values are `@export`.

### `Allomancer` (src/allomancy/allomancer.gd)
This is a generic component used by the player **and** by enemy allomancers (coinshots, Inquisitor):
- `reserves: Dictionary[int, float]`, plus `add_reserve(metal, amt)`, `get_reserve(metal)`
- `set_burning(metal, on)`, `toggle_burn(metal)`, `is_burning(metal)`, `set_flaring(on)`
- `effect_strength(metal) -> float`: 0 if the metal isn't burning.
- `push(target: Metallic, intensity: float, delta)` / `pull(...)`
- `lines_in_range() -> Array[Metallic]`
- It emits the `Events.metal_*` signals so the HUD and audio can react.

### `Health` (src/combat/health.gd)
It's a child node named `Health`.
- `take_damage(amount, source, kind)`
- Modifiers are Callables, e.g. pewter reduces damage.
- `Health.find_on(node)` walks up from a hitbox to the actor.

Damage kinds are `&"blunt" &"blade" &"coin" &"fall" &"crush" &"fire"`.

### Groups
- `player`: the player body (exactly one).
- `enemy`: every enemy body.
- `enemy_spawn`: Marker3D nodes placed by the world generator. Their `meta` holds `enemy_type` (StringName) and `patrol` (PackedVector3Array).
- `pickup`: pickups.
- `objective_point`: Marker3D with meta `objective_id`.
- `player_spawn`: Marker3D, the player start point.
- `checkpoint`: an Area3D checkpoint with meta `checkpoint_id`.

### Scenes that integration relies on
- `res://src/player/player.tscn`: root is `Player` (CharacterBody3D, group `player`). It contains `Allomancer`, `Health` and the camera rig.
- `res://src/world/luthadel.tscn`: root is `LuthadelWorld` (Node3D). It generates the district in `_ready()` from `@export var seed`. It also provides `WorldEnvironment` + a `MistController` with `set_tin_vision(0..1)` and markers in the groups above.
- `res://src/enemies/<type>.tscn`: enemy scenes. `type` is one of `guard`, `hazekiller`, `coinshot`, `thug`, `inquisitor`.
- `res://src/ui/hud.tscn`: a CanvasLayer that listens to `Events` only.
- `res://src/ui/pause_menu.tscn`, `res://scenes/main_menu.tscn`.
- `res://src/mission/mission_director.gd`: drives objectives for the vertical slice.
- `res://scenes/game.tscn`: the integration scene. It loads the world, spawns the player at `player_spawn`, spawns enemies at `enemy_spawn` markers, and adds the HUD, pause menu and mission director.

## Performance rules
- Use statically typed GDScript everywhere (`var x: float`, typed arrays). No `get_node` in hot loops; cache references in `_ready`.
- Work that runs every frame for many objects belongs in `_physics_process` on a manager, not in per-object scripts. Examples: allomantic line gathering and coin cleanup.
- Draw repeated geometry with `MultiMeshInstance3D`. Merge static geometry per chunk. Give distant buildings `visibility_range` / LOD. Add `OccluderInstance3D` for large buildings.
- Pool coins, particles and audio players. Cap active coins at 256; recycle the oldest.
- Steel/iron lines are drawn with a single `MultiMeshInstance3D` (no per-line nodes).
- Shadows: one directional light (the moon) with 3–4 cascades, and few shadowed omni lights. Most lanterns are unshadowed omni lights with a short range and a `distance_fade`.
- Target: 60 FPS at 1080p on a GTX 1060-class GPU at the "High" preset. The "Low" preset must run on integrated GPUs.

## Story missions (Acts I–III)
Missions are JSON under `src/mission/missions/` run by `MissionDirector` (the objective types and actions are documented in `src/mission/mission_data.gd`). Mission spaces are scenes under `src/mission/interiors/` entered through `SceneTransition` (`enter_interior`, `switch_interior`, `exit_interior`). The player node is reparented rather than recreated.
- A mission space marks `interior_spawn`, `objective_point` markers (meta `objective_id`) and an exit door (`src/world/interior_door.gd` with `is_exit`). The Act III spaces are built from `InteriorKit` helpers.
- Open-air mission scenes add a `MissionBackdrop` (`src/world/mission_backdrop.gd`) for the night sky and far skyline.
- Scripted beats: a scene joins a group and exposes methods. The mission JSON's `call_group` action (held until a pending interior transition finishes) or a cutscene shot's `call` invokes them.
- `MassBattle` (`src/mission/battle/`) simulates up to 60 data-only soldiers on one manager and draws them with MultiMesh.
- `LordRuler` (`src/enemies/lord_ruler.gd`) is phase-driven through `set_phase`. It emits `Events.boss_phase_changed`.
- The finale's `roll_credits` action shows `CreditsScreen` and then sets `GameState.post_game`. Post-game free roam has no story mission, and every activity stays open.

## Testing
Run `tools/run_tests.sh`: it runs `godot --headless` on `tests/run_tests.gd`. That runner discovers `tests/test_*.gd` files, which extend `res://tests/test_case.gd`. Every system should ship tests for its non-visual logic. Before committing, check that scripts parse with `godot --headless --check-only --script <file>` or by importing the project with `godot --headless --import`.
