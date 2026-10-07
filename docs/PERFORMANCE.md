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
