# Open world: streamed Luthadel

Luthadel is one seamless, streamed city. The vertical slice (Skaa quarter →
Keep Venture → east canal) is a small area near the origin inside it. Code
lives in `src/world/`.

## City plan (data)

`src/world/data/luthadel_plan.json` describes the whole city. `CityPlan`
(`city_plan.gd`) loads it.

| Key | Meaning |
|---|---|
| `chunk_size` | Streaming cell size (128 m). |
| `bounds` | Chunk-aligned XZ extent of the city: x −2176..2176, z −2688..1152. |
| `slice_bounds` | The vertical-slice district (used by tests and the map). |
| `city_wall` | Ring polygon, height and thickness. Buildings stay inside it. |
| `canals` | Axis-aligned water rectangles with quay width and water/bed heights. |
| `districts` | Polygons with a `type`. The first match wins; `default_district` covers the rest. Anything outside the wall is `outside`. |
| `styles` | Generator parameters per district type: block/street sizes, floors, lot sizes, roof mix, wall materials, soot tint, lit-window/bar/lantern ratios, lamp spacing, prop density, plazas, chimneys and rooftop metal. |
| `landmarks` | Hand-placed set pieces with a reserved `footprint`: Keep Venture, Kredik Shaw, Keeps Hasting, Lekal, Elariel, Tekiel and Erikeller, Fountain Square, Clubs' shop, the crew hideout, and the extraction dock. |
| `markers` | Mission anchors: `player_spawn`, objectives, checkpoints, enemy spawns, pickups. Each one has a `placement` of `rooftop`, `lamp`, `street` or `patrol`, and the generator resolves it against the real layout. |

To add a district, add a polygon and a style. To add a set piece, add a
landmark and handle its `type` in `landmark_builder.gd`.

## Generation pipeline (deterministic)

Every unit is a pure function of `(seed, unit id, plan)`.

1. **`ChunkLayout`** is pure data and cheap (about 1.5 ms per chunk).
   - Chunks are separated by boundary streets centred on the chunk borders. A street's width is hashed from the shared border, so both neighbours agree on it.
   - Inside a chunk, rows and then blocks are split with that chunk's own RNG. This produces staggered T-junctions.
   - Blocks are clipped against canals, landmarks and the wall. They then become terraced lots or a plaza.
   - The layout also places lamp posts, bridges, and plan markers (forcing flat roofs and heights where the mission needs them).
2. **`ChunkGenerator.generate_chunk`** runs on a worker thread. `GroundBuilder` builds the ground, canals and bridges; `BuildingBuilder` builds the buildings; `PropPlacer` places lamps, loose metal props and plazas; `CityWallBuilder` builds the wall. The output is a `ChunkBuildData`:
   - merged mesh arrays per material
   - collision shape specs
   - occluder boxes
   - metals
   - MultiMesh transforms
   - lights
   - rigid props
   - markers
   - navigation source (faces plus projected obstructions)
3. **`LandmarkBuilder` / `KeepBuilder`** produce the same `ChunkBuildData` for landmarks.
4. **`ChunkInstancer`** runs on the main thread. It adds nodes a few at a time under a per-frame budget (3 ms by default):
   - one or two merged MeshInstances plus windows and detail meshes
   - one StaticBody with box/convex shapes
   - an OccluderInstance3D
   - MultiMeshes for repeated ironwork
   - lamp posts as a StaticBody each, with a `Metallic` (mass 60)
   - OmniLights with distance fade
   - RigidBody props on layer 4, each with a `Metallic`
   - Marker3D and checkpoint Area3D nodes
   - canal FogVolumes

   It then starts an async navmesh bake. `WorldStreamer` polls for completion on the main thread, so no script callbacks run on worker threads.

## Streaming

`WorldStreamer` (group `world_streamer`) picks its focus in this order: the node in group `player`, then the active camera, then the spawn point.

- **Loading.** Units whose bounds lie within `load_radius` (400 m) are requested. Landmarks load from a further 120 m away.
- **Unloading.** Units are freed beyond `unload_radius` (500 m). Their Metallics unregister from `MetalRegistry`. Loose-prop state resets when a unit reloads.
- **Worker tasks.** At most `max_tasks` generation tasks run at once, nearest units first.
- **Startup.** `LuthadelWorld._ready` synchronously loads everything within `initial_radius` (170 m) of the spawn, so the player spawns on solid ground. This takes about 0.7 s headless.
- **`is_area_loaded(pos)`.** The player uses this to hold position instead of falling through ground that has not loaded yet.

## Far LOD

`FarLod` builds skyline meshes in the background: one merged mesh per 4×4-chunk superchunk (building boxes, roofs, ground and the city wall), plus one silhouette per landmark. They are built from the same `ChunkLayout` data, so the silhouettes match the real buildings.

The `far_silhouette.gdshader` shader:
- discards fragments inside chunks that are currently loaded, using a small R8 loaded-chunk mask texture
- fakes scattered lit windows

A landmark's silhouette hides while its full version is loaded. Kredik Shaw's 300 m spires and the keeps are therefore always on the skyline. The Ashmounts are drawn in the sky shader.

## Markers

`MarkerIndex` holds marker data for every chunk that has plan markers and for every landmark. It is computed at startup on the thread pool, whether or not those units are loaded. Other chunks are indexed when they load.

- `LuthadelWorld.get_marker_data(group)` returns `{group, position, pos, meta, unit}` for the whole city.
- `get_markers(group)` returns the live nodes in loaded units.
- `markers_spawned(nodes)` fires when a unit loads, so spawners can populate newly streamed areas.

## Navigation

Each chunk bakes its own `NavigationRegion3D` from the generated source geometry:
- cell 0.25 m
- agent radius 0.5 m (0.4 rounded up to the cell grid)
- `border_size` 2 m, and `filter_baking_aabb` set to the chunk area grown by 2 m, so the edges of neighbouring chunks line up and connect

Buildings are projected obstructions, so there are no nav islands inside them. Flat roofs are walkable islands for rooftop enemies. Landmark geometry is included in the bake of every chunk it overlaps.

`navigation_ready` fires once the initial area has baked and the navigation map has synced.

## Floating point

The city spans about ±2.7 km. At 2.7 km, 32-bit float precision is about 0.25 mm, which is fine for physics and rendering. If the world ever grows past about 8–10 km, add origin shifting: re-centre the player and every loaded unit root on chunk boundaries. Chunk roots already sit at the world origin with world-space vertices, so a shift only has to offset the units root and the far-LOD node.

## Remaining work / ideas

- Interiors beyond the gatehouse office, Kredik Shaw's interior and the other keeps' courtyards.
- Persisting the state of loose props per chunk. They currently reset on reload.
- Ambient patrols per district (the style hook exists; they are disabled so the slice's enemy count stays controlled).
- Distinct generator styles for the merchant and noble districts: facade ornaments, gardens and wider avenues.
- HLOD for the mid-range. Chunks currently switch from full detail straight to far-LOD boxes.
