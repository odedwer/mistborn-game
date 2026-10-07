# Performance

CPU frame time for the vertical slice (`scenes/game.tscn`, mission "Mistwalk
to Keep Venture"), measured headless on the 4-core dev container. Headless
has no rendering, so these numbers are game logic plus physics only. The
target is **process + physics under 8 ms per frame**, with **no streaming
hitch over 30 ms**.

## How to measure

| Tool | What it does |
|---|---|
| `godot --headless -s res://tools/perf.gd` | Settles at the start rooftop, cp_2 (mid-route), the keep courtyard and the canal extraction, with steel burning. It measures 600 frames at each spot, then flies the whole route at 30 m/s. The player moves every physics tick, so chunks stream in and out exactly as in play. Add `-- bisect` to disable subsystems one at a time, or `-- micro` for micro-benchmarks of MetalRegistry, lines, enemy AI and the streamer/instancer stages. |
| `tools/soak.sh [frames] [report.json]` | Runs the scripted-bot soak (`tests/soak_bot.gd`). It reports errors, leaks and CPU per route stop. |
| `tests/frame_timer.gd` | Per-frame timing from SceneTree signals. `physics` covers the first `physics_frame` of the iteration up to `process_frame`, and `process` is the rest. |

Two things skew naive measurements:
- Headless Godot sleeps `low_processor_usage_mode_sleep_usec` (about 7 ms) every frame, and that sleep gets counted as process time. `FrameTimer` sets it to 0.
- `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` report the *maximum over the last second*, not a per-frame average.

## Results

All values are in milliseconds. Each spot shows *process / physics tick*, with the maximum frame in brackets.

| Where | Before | After |
|---|---|---|
| Start rooftop | 5.95 / 7.85 (max 78.7) | 1.05 / 2.40 (max 6.2) |
| cp_2, mid-route | 3.69 / 8.25 (max 300.9) | 1.30 / 2.74 (max 13.8) |
| Keep courtyard, 19 enemies awake | 2.32 / 10.66 (max 214.4) | 1.29 / 3.20 (max 18.0) |
| Canal extraction | 3.86 / 9.43 (max 280.5) | 1.44 / 2.83 (max 29.9) |
| Fly the route at 30 m/s: average CPU per frame | 10.0 | 3.6 |
| Fly the route: max frame | 100.7 | 19.7 |
| Fly the route: max physics tick | 21.8 | 9.4 |
| Fly the route: frames over 30 ms | 19 | 0 |

"Before" is `5ce939d`, measured with the same probe.

In the soak (`tools/soak.sh 3000`), the bot flies around, throws 570 coins, keeps 256 of them live, and uses duralumin, atium, activities, saves and loads. It averages 3.8–6.8 ms CPU per route stop. The frames that still go over 30 ms are:
- the first ~2 s after load (world startup: far LOD, navmesh bakes);
- opening the pause menu (map/journal rebuild, 50–75 ms, UI only, while paused);
- a teleport across the city (deliberately instant; excluded from the stops).

## City-wide content re-measurement

After bringing the merchant, noble, docks, market and kredik_shaw districts up
to the slice's anchor-density standard, streaming activity beacons/rings per
chunk, and adding ~40 collectibles and city-wide activities/safehouses (see
docs/OPEN_WORLD.md), the soak route was extended
(`tests/soak_bot.gd` `STOPS`) with three stops outside the slice — merchant
(`-1200,30,-1000`), noble (`100,30,-1550`) and docks (`900,30,400`) — and run
for 4200 frames (`tools/soak.sh 4200`):

| Stop (district) | avg process / avg physics / avg CPU (ms) | max frame (ms) |
|---|---|---|
| merchant (`-1200,-1000`) | 2.56 / 4.80 / 7.37 | 65.0 |
| noble (`100,-1550`) | 1.99 / 4.62 / 6.62 | 42.6 |
| docks (`900,400`) | 1.03 / 4.55 / 5.58 | 38.7 |

These are in the same range as the existing slice stops (3.9–7.7 ms average
CPU) — the extra districts don't cost more per frame than the slice does.
0 errors and 0 warnings over the full 4200-frame run; the only max-frame
outlier (374.7 ms) is the deliberately-instant teleport back to spawn after
the docks stop, same class of excluded hitch as before. Anchor density per
district type is now also covered by a dedicated test
(`tests/test_district_generation.gd`), measured at seed 1337:

| District type | anchors / 100 sq m |
|---|---|
| skaa_slums (slice baseline) | 0.42 |
| merchant | 0.66 |
| noble | 0.76 |
| market | 0.81 |
| docks | 0.65 |
| kredik_shaw (bare approach grounds by design) | 0.07 |

## What was fixed

| Area | Problem | Fix |
|---|---|---|
| Collision instancing (`chunk_instancer.gd`) | Collision shapes were added one by one to a StaticBody already in the tree. Jolt rebuilt the compound shape on every add, which cost 30 ms per chunk, with 12 ms single steps even under the 3 ms budget. | Shapes go into StaticBodies of 48 that are filled *before* they enter the tree. It now takes about 6 ms per chunk, and every step is under 1 ms. |
| Navmesh bakes (`world_streamer.gd`) | Up to 4 navmesh bakes ran at once. They filled the WorkerThreadPool, and Jolt's physics jobs queued behind them, causing 30–70 ms physics ticks while streaming. | One bake runs at a time, nearest first. |
| Unloading (`world_streamer.gd`) | A teleport freed a dozen chunk trees in one frame, taking 50 ms. | At most 2 unloads per update, farthest first. |
| MetalRegistry | All ~5–6k metals were re-bucketed every physics frame, costing 3–4 ms. `unregister` was an O(n) `Array.erase` per metal on chunk unload. It also used a 3D 8 m hash: a 60 m query walked 4096 cells in 0.58 ms. | Only movable metals (about 500) are re-bucketed, taking about 0.3 ms. Removal is O(1) swap-remove. A 2D 16 m column hash brings the 60 m query down to about 0.07 ms. |
| Enemy AI (`enemy_base.gd`) | Setting `NavigationAgent3D.target_position` every tick repaths every tick. That cost 0.7–0.8 ms per patrolling guard, and 3 ms in the courtyard. | Re-target only when the goal moved more than 4 m, or more than 0.5 m and 0.35 s have passed. Enemy AI in the courtyard now takes 0.39 ms. |

## Remaining hotspots and ideas

- **Pause-menu map/journal rebuild** (50–75 ms on open). Build it incrementally or cache it.
- **Startup.** Far-LOD and navmesh work compete with gameplay for the first couple of seconds. The loading screen could wait for `navigation_ready`.
- **Physics tick.** It is about 2.5–3 ms, mostly Jolt with the city's static geometry, and it has headroom. If mass battles (Act III) push it up, the next steps are to sleep far rigid props and to use lower-rate AI for distant enemies.

## Pass 2: district architecture cost

`ChunkGenerator.generate_chunk` on a worker thread (headless, one core), per chunk:

| Chunk | Before | After |
|---|---|---|
| skaa | 8.1 ms | 8.8 ms (noise; unchanged code path) |
| merchant | 7.5 ms | 10.0 ms |
| merchant, avenue | 8.9 ms | 13.5 ms |
| noble | 8.9 ms | 16.6 ms |
| docks | 5.6 ms | 8.3 ms |
| keep_hasting (garden) | 4.8 ms | 4.9 ms |

The extra cost is the pilaster boxes and balcony/planter/tree instances.
Generation runs off the main thread and instancing stays under the per-frame
budget; avenue trees/planters are MultiMesh instances, so draw calls barely
move. Activity validation adds no runtime cost (tool and test only).

## Pass 3: cornices, trees, balconies

Pass 3 added a frieze and a projecting crown cornice on every free merchant/noble
face, forked ash-dead trees and heavier balcony ironwork. To pay for them,
pilasters now emit only their three visible faces (they were full boxes), and
`WorldMeshBuilder.add_quad` is unrolled (it is the hottest call in chunk
generation). The benchmark ran the same chunks back to back, old tree against
new, with 2 x 6 runs each on a noisy one-core VM:

| Chunk | Before | After |
|---|---|---|
| noble | 14.7 ms | 13.5 ms |
| merchant avenue | 13.8 ms | 12.9 ms |
| merchant | 17.6 ms | 15.9 ms |

Noble chunk generation got slightly faster, not slower. The absolute numbers
are higher than in pass 2 because this VM is slower.


## World pass 8: modillions, shop signs, statues

These are all MultiMesh instances, with no new merged geometry. A noble or merchant chunk gains about 900 modillions (24 triangles each, 140 m visibility range), about 4 shop signs (110 m), and occasionally a statue and plinth (400 m). The benchmark generated 3 chunks per district, best of 6 runs, with 2 x 2 runs per tree back to back:

| Chunk | Before | After |
|---|---|---|
| noble | 10.6-10.8 ms | 11.4-12.5 ms |
| merchant | 12.3 ms | 12.7-13.2 ms |

A merchant preview frame draws about 15% more primitives (357k -> 414k at street level), and most of that is the modillions. World pass 9 brings most of that back (next section).

## World pass 9: modillion cost

Modillions were one MultiMesh per chunk with a 140 m range. A visibility range
is measured to the AABB centre, so a whole-chunk MultiMesh can't use a short
range: it would drop brackets right next to the camera or keep the whole
chunk's set. Two changes:

- **Cells.** `ChunkInstancer.INSTANCE_CELL` splits a kind into 24 m cells, one
  MultiMesh each. Modillions use a 64 m range (plus the usual 10 m margin)
  measured to each cell's centre, so every bracket within about 50 m is drawn
  and none beyond about 90 m. Past 60 m a 0.2 m bracket covers 2-3 px.
- **Mesh.** Only the eight faces that can be seen: 16 triangles instead of 24.
  The tops sit on the soffit and the backs sit against the bed moulding and
  the frieze.

Measured with `tools/preview.gd` at `--time=11`, one process per pose so each
count is a cold first shot. The tool now also prints draw calls.

| Pose | Before (prims / draws) | After (prims / draws) |
|---|---|---|
| merchant street `-374,2,-1990` (the pass 8 pose) | 413.6k / 306 | 364.6k / 304 |
| merchant avenue from 13 m `-381,13,-1955` | 393.3k / 291 | 346.0k / 292 |
| merchant cornice close-up `-381,3,-2040` | 480.1k / 326 | 432.7k / 332 |
| noble street `-451,2,-1155` | 385.0k / 292 | 339.3k / 293 |

That is 11-12% fewer primitives at every pose, with draw calls flat (the cells
in range replace one draw per chunk). The merchant street pose is back within
2% of its count before pass 8 (357k). The "after" numbers also include the new
statue figure (about 600 triangles per statue), which is negligible.

## World pass 10: modillion fade

Modillion cells used to pop at 54-74 m. `visibility_range_fade_mode` doesn't
fix that: Forward+ alpha-blends the whole cell (into the transparent pass),
and Compatibility ignores the mode and keeps the plain hysteresis. Instead,
each bracket dithers out between 32 and 48 m with a per-pixel distance fade
(`BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER` on a copy of the ashlar
material). This stays in the opaque pass and looks the same in both
renderers. The cells now only have to come and go out of sight. They have a
68 m range with a 3 m margin, so a cell appears at 65 m and goes at 71 m,
measured to its centre. No bracket of a 24 m cell is then nearer than 48 m.

The statues also gained a head (about 950 triangles per figure, up from about
680), and there are 55 of them instead of 47. Measured as in pass 9, with
one cold process per pose:

| Pose | Pass 9 (prims / draws) | Pass 10 (prims / draws) |
|---|---|---|
| merchant street `-374,2,-1990` | 364.6k / 304 | 365.3k / 305 |
| merchant avenue from 13 m `-381,13,-1955` | 346.0k / 292 | 348.4k / 297 |
| merchant cornice close-up `-381,3,-2040` | 432.7k / 332 | 433.8k / 334 |
| noble street `-451,2,-1155` | 339.3k / 293 | 340.8k / 296 |

That is 0.2-0.7% more primitives and up to 5 more draws, from the cells that
now stay up to 65-71 m instead of 54 m on a cold shot. Forward+ (Vulkan on
lavapipe) draws the same 348.1k primitives at the avenue pose.

## Fast preview shots (`tools/preview.gd`)

The full game or `scenes/test/world_preview.tscn` streams a 260-400 m radius,
builds the far-LOD skyline and the citywide marker index, and bakes navmeshes,
so one opengl3/llvmpipe screenshot took 3-10 minutes. `tools/preview.gd` skips
all of that. It streams only the chunks and landmarks within `--radius`
(default 140 m) of each pose, synchronously, with no far LOD, no marker index,
no navmesh bakes, no crowd or enemies, the lowest mist setting and a 500 m far
plane:

    xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
      --resolution 1280x720 -s res://tools/preview.gd -- \
      --shot=x,y,z,yaw,pitch,out.png[;...] [--time=<hour>] [--radius=140] [--far=500] [--frames=6]

Yaw and pitch are in degrees: yaw 0 looks -Z, -90 looks +X, and pitch -90
looks straight down. `--time` is read by the TimeOfDay autoload (11 = day,
22 = night). A Keep Venture courtyard shot takes about 17 s end to end
(0.3 s world setup, 11 units, 236k primitives). Each shot prints its unit
count, primitives and draw calls. Distant skyline and mist are
missing by design, so use the full preview for skyline shots.

## Test suite

`tools/run_tests.sh` runs everything CI runs (`.github/workflows/ci.yml`
calls it as is):

- the Godot suite, `tests/test_*.gd` through `tests/run_tests.gd`, split
  over `TEST_JOBS` headless Godot processes ("shards", default: CPU cores,
  at most 4). The shards share a claim directory: each takes the next test
  file nobody has claimed (an atomic `mkdir`), heaviest first by the
  runner's `FILE_WEIGHTS`, so they balance themselves. A file always runs
  whole, its tests in order, in one process;
- at the same time, the Python clearance tests (`tools/characters`, numpy
  only), split over `CLEARANCE_JOBS` processes (default 3) by
  `tools/characters/run_parallel.py`, heaviest test class first by each
  class's `WEIGHT`. The long weapon and cloth scans are one class per
  character (the Inquisitor's and the guard's weapon scans per share of
  their clips), so no class takes more than about 5 s.

The shard logs are printed one after the other at the end, then the
failures again, the totals and the merged tables of the slowest files and
tests. The run fails on any failed test, a shard that exits non-zero or
prints no summary (a crash), a test file that no shard ran, a failed
Python test, or a runner that prints Godot's leak report at exit (see
"Leaks at exit" below).

| Command | What it does |
|---|---|
| `tools/run_tests.sh` | The whole suite, sharded. |
| `tools/run_tests.sh <filter>` | Only the Godot test files whose name contains `<filter>`. No Python tests. |
| `TEST_JOBS=1 tools/run_tests.sh` | The Godot suite in one process, its output streamed live (the old behaviour). |
| `TEST_SLOWEST=<n> tools/run_tests.sh` | `<n>` rows in the slowest files/tests tables (default 10). |
| `CLEARANCE_JOBS=<n> tools/run_tests.sh` | `<n>` Python clearance processes (default 3). |
| `godot --headless -s res://tests/run_tests.gd -- [filter] [--test=<text>] [--reverse \| --shuffle=<seed>]` | One runner. `--test` runs only the test methods whose name contains `<text>`. `--reverse` and `--shuffle` change the file order, to check that no file depends on what ran before it. |

Every test that takes 2 s or more prints its time under its `ok` line.

### Timing

Measured on the 4-core dev container. The GitHub `ubuntu-latest` runner for
this public repository also has 4 vCPUs (and 16 GB), so CI uses 4 shards.
One shard peaks at about 580 MB (the story sweep).

| | Before | After |
|---|---|---|
| `tools/run_tests.sh`, wall | about 8 min (423 s Godot, then 78 s Python) | 68-76 s (6 runs); 68-77 s (6 runs) since the clearance scans are split, the Godot shards now last |
| Godot suite in one process | 423 s | 178 s |
| Python clearance tests | 70-78 s, after the Godot suite | 37 s idle, 64-71 s next to the shards in 2 processes. Since the split: 25 s idle and 51-58 s next to the shards in 3 processes, before the Godot shards (55-69 s) |

Slowest files, one process, before -> after:

| File | Before | After |
|---|---|---|
| `test_story_sweep.gd` | 124.0 s | 41.5 s |
| `test_world_gen.gd` | 64.4 s | 4.2 s |
| `test_traversal.gd` | 60.6 s | 40.4 s |
| `test_soak.gd` | 50.9 s | 30.7 s |
| `test_open_world_content.gd` | 44.3 s | 3.2 s |
| `test_e2e_mission.gd` | 29.3 s | 7.2 s |
| `test_crowd_member.gd` | 9.7 s | 9.7 s |
| `test_characters.gd` | 8.8 s | 8.7 s |

The slowest tests are now `test_story_sweep` (41 s: every story mission in
the real game scene), `test_soak_full_game` (31 s: 1800 frames) and
`test_route_is_traversable_with_steel_jumps` (32 s: about 1900 frames of
flight). The headless runner keeps real time, so a test that waits N physics
frames takes at least N / 60 s: these three are bound by their frame counts,
not by the CPU, and they set the floor of a sharded run (about 45-65 s with
four shards sharing the CPU).

### What made it faster

- **A 20 s wait whenever a world was freed mid-bake.** `ChunkInstancer.wait_for_bake`
  waited for `NavigationServer3D.is_baking_navigation_mesh` to clear, but
  that flag only clears when the server syncs on the main thread, which the
  wait was blocking: it always ran to its 10 s timeout, twice (the streamer's
  `_exit_tree`, then `unload_all`). It now waits for the baked polygons,
  which the worker stores into the mesh when it is done (about 70 ms). That
  was most of `test_world_gen`, `test_open_world_content`,
  `test_e2e_mission` and `test_story_sweep`, and also a 20 s freeze in the
  game when a world was freed during a bake.
- **Sharding and running the Python tests alongside**, as above.

### Bugs the faster runs found

Running the shards in parallel changed the timing and which test file ran
last in a process, and showed two latent bugs (each now has a regression
test):

- **The camera's landing dip blew up in a long frame during atium.** It is
  an explicit spring step on `delta / time_scale`, unstable past about
  0.1 s: under CPU load the soak's camera went to y = 1e30, then NaN, and a
  coin throw aimed along a zero vector. It now integrates in steps of at
  most 1/60 s (one step at 60 fps, as before).
- **`WorldStreamer.load_now` dropped the streamer's other in-flight tasks.**
  It cleared every task id, so units still generating in the background
  were never waited for (Godot aborted at exit after a fast travel, about 1
  run in 5 when `test_open_world_content` was the last file of a process)
  and were generated again; and it skipped wanted units that were already
  generating, so they did not load synchronously.
- **`load_now` also skipped wanted units still instancing** (in `_units`
  but built over several frames), so it could return with one half built
  (`test_load_now_during_background_streaming`, now and then). It finishes
  them now.
- **A streamed-in checkpoint could be missed.** A unit's checkpoint areas
  entered the tree one build step before the unit was done; when the frame
  budget ran out in between, a physics step ran before `unit_loaded`, on
  which the `MissionDirector` connects them, and a player already standing
  there was never recorded (`test_full_mission_playthrough`, now and then:
  "streamed-in checkpoint recorded"). The step that adds the markers now
  finishes the unit.

### Leaks at exit

Godot prints a leak report when a process exits with objects or resources
still alive: "N ObjectDB instances leaked at exit" (nodes never freed,
RefCounted objects kept alive by a cycle or a static) and "N resources
still in use at exit". The suite exits clean, and `tools/run_tests.sh`
fails a run whose shard (or sequential run) prints either line, naming the
files that runner ran. To find a leak, run those files one at a time with
`--verbose`, which lists the leaked objects and resources, then bisect the
file's tests with `--test=<name>`:

    godot --headless --verbose -s res://tests/run_tests.gd -- test_mass_battle.gd --test=rout

The leaks it found (17 of the 44 files leaked):

- **Sounds playing at quit (game).** The AudioServer frees a stopped
  playback only on a later mix step, and never frees the ones still
  pending when the engine shuts down. A sound still playing at exit leaked
  its `AudioStreamPlaybackOggVorbis`, `OggPacketSequencePlayback` and the
  `.ogg` stream itself: 16 of the 17 files, a different set on each run.
  `AudioManager.shutdown()` stops every voice and waits until weak
  references to their playbacks clear (at most 2 s). The test runner and
  the pause menu's Quit await it before `quit()`. Closing the window
  quits without it.
- **`MassBattle` soldiers (game).** Two soldiers fighting each other hold
  each other in `Soldier.target`, a RefCounted cycle that outlived the
  battle. The battle clears the targets on `NOTIFICATION_PREDELETE`.
- **`test_act3_missions` (test).** It emitted `allomantic_line_used` with
  three `Node.new()` stand-ins that were never freed.

Left alone: with `--verbose`, a few files also print "N unclaimed string
names at exit" listing Godot's built-in type names (`Vector3`, `int`,
`PackedByteArray`, ...), after a scene with the player is loaded. Those are
StringNames held by the engine itself, not objects or resources, and are
not in the report the runner checks.
