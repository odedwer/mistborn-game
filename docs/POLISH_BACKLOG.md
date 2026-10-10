# Polish backlog

These are visual and feel issues found by reviewing screenshots. They're queued for the Polish roadmap phase. Each entry says where it was seen.

## Art

### Done (this pass)
- **Brick and cobblestone textures** (`tools/gen_textures.py`) — done. Brick is now heavily desaturated toward a grey-brown palette, darkens toward the top (ashfall accumulation), and has deeper recessed mortar joints with grime pooled in them. Cobblestone was rebuilt from scratch: instead of shading a Voronoi cell (which always reads as cracked flagstone, since Voronoi edges are straight), each stone is now its own circular/elliptical footprint with a true hemispherical height profile, giving real domed, rounded cobbles with dark ash-filled gaps between them. Added a generic `ash_dust_upward()` pass (settles a lighter ash film on locally-convex/upward-facing detail) and applied it to `stone_wall`, `brick_soot`, `cobblestone` and `slate_roof` (heaviest on roofs, which face the ashfall directly). `wood_planks`, `iron_rusty`, `plaster_dirty`, `cloth_mistcloak`, `leather` and `obsidian` were reviewed and left alone — plaster and iron already carry heavy soot/rust, and the others aren't exterior ash-catching surfaces. Regenerated and re-imported; `.import` normal-map flags are unchanged.
- **Pickups** (`src/world/pickup.gd`) — done. Vial/duralumin now render a small glass vial (transparent shell, cork, metal-flake liquid core); coins are a drawstring pouch with a small coin stack using the existing coin-face textures; atium is a metallic bead; health is a lidded jar with a red-cross bandage strip. Glow (light + emission energy) was toned down so it reads at pickup range without tripping bloom.
- **Keep Venture ballroom** (`src/mission/interiors/keep_venture_ballroom.gd`) — done. Stained glass is now a procedural shader (`assets/shaders/stained_glass.gdshader`): a leaded rectangular+diagonal lattice, a hashed 4-colour palette per pane, and a warm/cool emissive gradient, plus a coloured `SpotLight3D` behind each window casting a tinted light shaft onto the dance floor. Chandeliers gained a ring of small emissive candle bulbs; the centre one is the room's one shadowed light. Tables are dressed with a tablecloth and two lit candlesticks each (was a bare grey cylinder). Ambient is warmer and the room has a soft warm directional fill so nobles read clearly. Applied the same care (warmer ambient, a fill light, and — for the dinner hall — a dressed table with candlesticks) to `keep_venture_dinner.gd` and `keep_venture_library.gd`.
  - Found along the way: enabling `glow` in this room at a readable ambient level blows out lit character skin/hair into big white blobs (no fog/atmosphere here to soften it the way the open world's does). Left glow off in all three Keep Venture interiors; if a future pass wants glow back for the chandeliers/candles specifically, it should be on the emissive materials via a very high `glow_hdr_threshold`, not enabled at the environment's current exposure.
- **World look pass** (`src/world/environment_builder.gd`, `src/world/mist_controller.gd`) — done. Fog and volumetric mist were shifted from a cool blue-grey to an off-white/ash grey-brown (matches the design doc's "mist is off-white", and reads as airborne ash rather than blue atmospheric haze), with a faint warm emission in the volumetric fog so lantern light visibly scatters through it. Ambient light energy raised (1.6 → 1.8) and SSAO intensity lowered (2.2 → 1.7) so no interior corner or building-shadow side crushes to near-black up close. `MistController`'s tin-vision ambient override previously reset ambient to a flat `1.0 + 0.8*tin` regardless of the environment's own baseline — added `base_ambient` (defaulting to the new 1.8) so tin vision brightens *from* the readable baseline instead of undoing it. Steel/iron lines (`steel_lines.gdshader`) already render with `fog_disabled`, so they were already unaffected by fog/mist density — confirmed by reading the shader, no change needed there.
- **Main menu background** (`scenes/main_menu.gd`) — done. Replaced the two lone cylinder "spires" with a proper Luthadel silhouette: 16 dark building blocks plus a Kredik Shaw–style cluster (one tall central spire + a ring of 7 shorter needle spires). The mist particles now use `soft_particle.png` with a new depth-fade shader (`assets/shaders/soft_mist_particle.gdshader`, the standard "soft particles" technique) instead of a flat quad, so puffs fade out near the skyline/ground instead of showing a hard edge. The camera drift is now a slower, wider side-to-side pan with a gentle push in/out and matching yaw, instead of a single-axis rail slide.

### Still open
- **Keep Venture courtyard**: environment tuning above applies to it automatically (it shares `EnvironmentBuilder`), but it wasn't screenshotted directly in this pass — full open-world generation is expensive enough (multiple minutes even at a small streaming radius under headless llvmpipe) that verifying it needs a dedicated fast preview harness (e.g. an `initial_radius`/`build_far_lod`-aware screenshot tool), not an ad hoc one. Worth adding to `tools/` properly.

## Feel
- **Race rings and pursuit paths** are authored as offsets from their start marker, and some may clip buildings. Validate them against the geometry.
- **Fixed.** Activity beacons/rings/pursuit runners/ambush spawns/riot members now stream with their own chunk (`ActivityManager._activity_parent`), like the enemies and pickups in `scenes/game.gd`; a running activity's start chunk is pinned (`WorldStreamer.pin`/`unpin`) so it can't unload mid-race. Progress/records live in `GameState`, not on the node, so nothing is lost across an unload. See `tests/test_open_world_content.gd`.

## Engine
- **Freed-object error during tests**. The suite prints one "Trying to cast a freed object" error from `scene_transition.gd` during the SceneTransition tests.

## Review of polish pass 1
Found by screenshot review after the first polish pass.
- **Fixed.** The TitleLabel, HeadingLabel and DimLabel theme variations had no `base_type`, so every title and heading in the UI rendered as a plain label. Fixed in `src/ui/theme.tres`.

### Pass 2 (all three fixed)
- **Ballroom exposure — fixed.** Ambient dropped from 1.1 to 0.4, tonemap exposure 1.15 → 0.95, the warm fill light 0.35 → 0.12 energy, and the exit door's pale wood material (0.55, 0.45, 0.3) darkened to 0.24/0.19/0.13 — that door, facing the spawn point dead-on at close range, was the actual source of the "walls near the door blow out to white" report, not the walls themselves. Chandelier and window-shaft light energy raised slightly (1.3→1.9, 1.1→1.6) so they now visibly carry the room instead of the ambient. Confirmed with `keep_venture_ballroom` close-door and wide shots: walls read grey/moody, nobles stay lit, no blown highlights.
- **Stained glass — fixed.** Rewrote `stained_glass.gdshader`: leaded boundaries are now a jittered-grid Worley (irregular polygons, not grid squares), laid out as a rose window (concentric rings/radial spokes) in the upper arch tapering into narrow vertical lancet panes below, with the palette desaturated toward its own luminance (`saturation` uniform, 0.55) instead of raw primary colours. Applied to the library's windows too (`keep_venture_library.gd`), each with its own palette rotation. Confirmed both no longer read as a checkerboard.
- **Main-menu skyline — fixed.** Buildings are now boxes with a `PrismMesh` gable roof and an optional chimney stack (`_pitched_building`), matching the world generator's silhouette language instead of plain blocks. Added `_build_horizon_glow`: a faint red gradient plane low behind the skyline (echoing the Ashmounts' glow in `night_sky.gdshader`). The mist material now branches on `RenderingServer.get_current_rendering_method()`: Forward+ keeps the depth-fade shader, but `gl_compatibility` falls back to a plain additive `StandardMaterial3D` with the same soft-particle texture, since the depth-fade shader needs a depth prepass Compatibility doesn't provide the same way — confirmed the mist still renders (dim visible puffs, no shader error) under `--rendering-driver opengl3`.

## Review of polish pass 2 (all three fixed, pass 3)
- **Ballroom entrance walls — fixed.** Replaced the flat pale `StandardMaterial3D` (0.42, 0.4, 0.4) with a textured, darkened plaster material (`_plaster_wall_material()`, using `plaster_dirty_{albedo,normal,roughness}.png`, base tint 0.24/0.225/0.21) on every wall and the ceiling. A flat, bright, texture-less surface right next to the spawn camera reads as blown-out white the moment anything lights it; the grain and darker base fix that regardless of camera position. Confirmed with the same close-up and wide shots: jambs and walls now read as dark worked stone/plaster, not white.
- **NPC name labels — fixed.** The engine's default `Label3D` font at `font_size 40` with `outline_size 8` (a 20%-of-glyph-height outline) was eating the letterforms at normal talk range, rendering as illegible mush. Switched to the game's own body font (`EBGaramond.ttf`), raised `font_size` to 56, dropped `outline_size` to 3, and set an explicit `pixel_size`/`outline_modulate`. Confirmed "Lord Elariel", "Lord Fedren" and "Lady Hesting" all render crisp and legible in the same wide ballroom shot that used to show them as scrambled.
- **Main-menu horizon — fixed.** The old gradient ran from transparent at one edge straight to its most opaque colour at the *other* edge of the plane, so the plane's own boundary was a visible seam against the empty sky. Rebuilt the gradient so both the top and bottom of the (now taller, 60m) plane are fully transparent, with the glow as a soft hump around the middle (near the horizon) — no edge coincides with any colour value other than zero alpha. Confirmed: the previously sharp line across the whole frame is gone; a separate, much fainter, pre-existing soft band from the mist particle volume's own vertical extent remains (unrelated to the glow plane, not part of this report).

## Review of polish pass 3 (all three fixed, pass 4)
- **Ballroom spawn camera — fixed.** `interior_spawn` was only 1.5m in from the south doorway, and the exit door (right in that doorway, ~1.2m further on) sat directly in the opening view's line of sight. Moved the inset to 6.0m, putting spawn at the edge of the dance floor; the door is now behind the camera instead of filling the frame. Confirmed: the opening view frames the ball.
- **Character faces and hair variety, and Elend's books clipping — fixed** (the characters agent finished, lifting the "don't touch character models" constraint). `body.py`'s shared `head()` shape function got deeper eye sockets, a stronger brow ridge, sharper cheekbones, a subtle jaw-angle corner and a faint nose bridge — applied uniformly across the whole cast. `hair_shell()` gained a `style` parameter with 4 variants (short/default, long-tied, bun, bald), assigned sensibly: Ham → long, Marsh → bald, Vin's ball disguise → bun (hair put up for the occasion), noble_man → long; noble_woman/skaa_woman already had their own bespoke bun helper, and Clubs/Sazed/Obligators were already bald via `bald_top`. Elend's book stack was pushed further out and slightly forward from the hand so the open coat's flare no longer clips through it. Regenerated every character via `tools/characters/build.sh`; `test_characters.gd` and `test_npc_models.gd` both still pass. Verified with before/after crew and gentry lineup screenshots and a close side-view render of Elend's books.
- **Main-menu regression — fixed.** A prior fix for the horizon-glow edge had accidentally dimmed the glow into near-invisibility and left the mist as one tall field spanning the whole skyline height, which both washed the buildings into grey and (per the report) left new hard edges where that field's own bounding volume ended. Rebuilt the mist as two low emitters (a denser one in the foreground, a thinner one along the skyline's base line) and moved the "no hard edges" fix from the emission box into the shader itself: `soft_mist_particle.gdshader` and a new `mist_particle_compat.gdshader` (for the Compatibility renderer, no depth-texture dependency) both fade every particle by world height via `fade_height_min/max`, so the visible mist band has no edge anywhere regardless of the emitter's own bounds. The horizon glow is brighter and more saturated (a real red-orange hump, not a barely-visible smear) and confirmed visible through the gaps between the now-dark, crisp buildings, on both Forward+ and `--rendering-driver opengl3`.

## Review of polish pass 4
- **Main menu:** good now, with a crisp skyline, a red horizon glow and low mist. One faint lighter band edge remains at the bottom third (around y=610 at 720p), probably the ground or foreground mist plane. Minor.
- **Characters:** Marsh is bald and Ham has long hair, as intended. Faces are too small in the lineup to judge; take a `--zoom=head` close-up next pass.

## Open-world expansion follow-ups (pass 2)
- **Fixed: tilted roof slab.** It was a gable slope: outside skaa_slums the ridge ran parallel to the street even on lots wider than they are long, so each slope became a steep, near-square tilted plane. The ridge now runs along the lot's long axis, and touching near-square lots keep their neighbour's ridge. A top-down render confirmed every roof is axis-aligned; nothing was actually rotated. skaa_slums is untouched, so the mission route is identical.
- **Fixed: crowd fall-through.** `CrowdMember._snap_home_to_ground` gave up after one failed raycast (collision not yet synced in a freshly streamed chunk) and then fell. It now retries and holds still until ground is confirmed.
- **Done: merchant/noble architecture.** Pilasters and iron-railed balcony anchors, 13-15 m ash-tree/planter avenues (outside the slice only), and hedged, walled keep gardens. A real cornice and statue/signage set-pieces are still open.
- **Done: activities validated.** `ActivityValidator` checks every ring, chase path and spawn ring against the generated collision boxes; `tools/gen_activities.gd` authored/repaired 54 activities so skaa, merchant, noble and docks each hold at least 3 of every type (`tests/test_activity_validation.gd`). Clearance uses AABBs (convex roofs by their bounding box), so it is conservative. Legacy content was mostly clipping buildings; `coin_race_keep` never had a start marker at all (relocated).
- **Open:** validation does not check reachability (Push anchors along a ring path), only clearance. No day/night cycle, so obligator patrols stay a density skew.

## Review of open-world pass 2

Merged pass 2: ridge axis follows lot long axis outside the slums, crowd ground-snap retries until ground streams in, merchant/noble pilasters + iron balconies (anchors) + avenues + walled keep gardens, and 54 geometry-validated activities (>=3 per type in skaa/merchant/noble/docks). 281 tests green. Reviewed opengl3 shots (merchant overview, merchant + noble avenues).

Follow-ups:
- Roof slab is gone in the merchant overview; roofs read cleanly.
- Noble facade stone texture is scaled far too large (cobbles ~1 m across on the right-hand building in the noble avenue shot); cut the triplanar scale for ashlar walls.
- Avenue trees read as thin sticks at this distance; give the ash-dead trees more branch mass or larger planters.
- Iron balconies aren't readable in any shot; need a close eye-level shot and maybe a thicker rail.
- Cornices were not built (pass 2 item 3 partial).
- Walled keep gardens only test-covered; take a higher, wider top-down shot.
- Market district is below 3 activities per type; ring-path reachability not validated.
- Noble chunk gen went 8.9 -> 16.6 ms on the worker thread; watch it against the streaming budget.

## Review of art pass 5

Merged: face rings levelled (forehead crease gone), readable eyes/brows/lips/nostrils, hair clears the scalp, beards open at the mouth, Marsh shaved; main-menu band traced to the horizon-glow gradient stop order and removed. 281 tests green. Reviewed p5_after_faces_crew_34 and p5_after_menu_720_gl.

Follow-ups:
- Faces now read clearly at 3/4; the menu at 720p shows no band.
- Short dark hair (Dockson, Breeze, Ham) reads as a smooth helmet/cap; needs strand breakup (a noise-driven alpha fringe at the hairline or chunkier clumps).
- Spook's cap is oversized and blocky; scale it down about 35% and add a brim.
- Clubs' grey side fringe reads like a flat patch stuck to the scalp.
- Strong specular hotspot on Breeze's and Dockson's chest fabric; raise the roughness.
- Hazekiller hood opening is ragged; faces are flat in profile (the nose and brow ridge need depth).

## Review of world pass 3 (time of day)

Merged: TimeOfDay autoload (ash-haze day and misty night, saved; night missions and interiors force night; night-only obligator patrols; wait-until-night at safehouses; `--time=<h>` and F7/F8 in debug builds), ashlar merchant/noble walls with frieze and cornice, bushier forked trees, heavy iron balcony rails, and 10 validated market activities. 293 tests green. Reviewed p3_merchant_avenue_day, p3_noble_facade_night and p3_keep_garden_topdown.

Follow-ups:
- Day reads well: brown ash haze, lamps still glowing, trees now read as trees. Noble ashlar and balconies read clearly at night.
- The left-hand merchant building in the day avenue shot still uses the oversized crazy-paving stone; check which style or material path skips the new ashlar.
- The keep garden top-down shows the walls, but the enclosure is almost bare: no visible hedges or garden beds. Needs parterre beds, paths and a fountain or statue.
- The cornice reads only as a dark line; it needs more projection or a lighter trim colour.
- There's no on-screen clock or time-of-day indicator (add one to the HUD or the map tab).
- `test_save::test_latest_slot_picks_most_recent` failed twice while another worktree's test run was writing to the same `user://saves` folder. Isolate the test save dir (e.g. a per-run subfolder) so parallel runs can't collide.
- Activity ring-path reachability is still not validated.

## Review of art pass 6

Merged: 32-column torsos with a V shirt (the glare came from vertex colour bleeding across a single column), Spook's cap about 35% smaller with a real brim, tufted blended fringe for Clubs, swept hair clumps for Dockson/Breeze/Ham, deeper brow and nose, clean Hazekiller hood opening. 293 tests green. Reviewed p6_after_faces_crew_34 and enemies_34.

Follow-ups:
- Spook's cap, the Hazekiller hood and Dockson's hair are clearly better.
- Breeze's shirt V still reads as a glowing gold-white streak under studio light; drop the albedo (the pale shirt is about 0.9) or add fabric shading.
- Skin has fine white speckle/grain across every face (a noise texture or sparkle at close range); make it subtler or tint it to the skin tone.
- Vin, the coinshot and Breeze share the same black helmet-like hair silhouette; Vin needs her own short, choppier style.
- Lips vanish in profile; pale shirts and skin are too bright under studio light (check against the in-game night lighting before changing).

## Review of world pass 4

Merged: test saves/settings isolated per run under `user://test_runs/`, a real coursed ashlar texture, formal keep gardens (cross walks, octagonal fountain plaza, iron statue anchor, hedged beds), a three-step pale cornice, a HUD/map time-of-day readout, and coin-race reachability (every leg within 22 m of a Push anchor; 9 races re-authored). 295 tests green. Reviewed p4_keep_garden_oblique, p4_merchant_avenue_day and p4_noble_facade_day.

Follow-ups:
- The keep garden now reads as a proper formal parterre. The noble ashlar reads as stone.
- At street level the merchant ashlar blocks look oversized (roughly 0.6 × 0.3 m) and flat, closer to painted siding; halve the tile or add edge bevel/colour variation per block.
- The HUD clock is only test-covered; take an in-game HUD screenshot.
- Keep curtain-wall crenellations read as a jagged zig-zag from above; use regular merlons.
- Rooftop pursuits are only checked for clearance and step height, not jump reachability.
- Still open from earlier: the "Trying to cast a freed object" error in the SceneTransition tests, and a fast open-world preview harness (Keep Venture courtyard never screenshotted).

## Review of art pass 7 and world pass 5

Merged art pass 7: the root cause of the skin speckle was an export bug (`build_characters.py` never wrote UVs, so every GLB shipped placeholder UVs and the grain noise sparkled). Also Breeze's linen shirt, Vin's choppy cut and lips that read in profile. Merged world pass 5: the `tools/preview.gd` fast district preview (12–42 s per shot), bevelled and varied ashlar, a regular merlon parapet, a scene-transition freed-object guard (the original error never reproduced), pursuit gap reachability (all 13 pass) and a larger HUD clock. The full suite is 297 green after both merges.

Follow-ups:
- Faces are clean, with no speckle, and the merchant ashlar now reads as real stone blocks.
- **Flaky test:** `test_story_sweep::test_every_story_mission_completes` failed 1 of 3 runs after the art merge: a CrowdMember in `c_m1_1` fell out of the world. It passed 2/2 on the pre-merge commit, which isn't enough to rule out a pre-existing flake. The crowd fall-through fix from open-world pass 2 is not airtight; root-cause it.
- **Ears** show as flat orange diamonds pasted over the hair in profile (Vin, guard, coinshot, thug, inquisitor). The hair shell draws over the head, but the ear mesh sits outside it. Tuck the ears under the hair or cut the hair shell around them.
- Vin's hair in profile is still close to a helmet silhouette.
- Dockson's and Breeze's shirt V still streaks.
- noble_woman_1's white hat is very bright at night.
- **Night readability:** in p5w_hud_night the rooftop around the player is almost pure black and the player is a silhouette. Night needs a cool moonlight fill or ambient floor so the player and nearby roofs read (tin brightens it, but base night must still be playable).
- **Font glyph bug:** the dialogue line "That's steel in your blood" rendered as "That's sted in your blood" in the HUD shot. The text in `mistwalk_to_keep_venture.json` is correct, so check the dialogue font for missing or ligature glyphs ("el").
- **Keep Venture courtyard** (first review): a big flat empty paved yard with a few scattered crates and a well. Its perimeter walls still use the old crazy-paving stone. It needs dressing (planters, carriage, guards' posts, a fountain, banners) and the ashlar material on its walls.
- The HUD clock reads at the bottom-right.

## Review of art pass 8

Merged: C-shaped ear rims with an inner hollow, set in hair-shell cut-outs; fuller, rounder hair for Vin with nape and side flyaways; the shirt V as a separate crisp panel; the noble hat recoloured to mid grey with an ivory-straw dye (it no longer glows at night). The art agent confirmed crowd collision is a fixed capsule independent of the GLBs. 297 tests green. Reviewed p8_after_faces_crew_34 and enemies_side.

Follow-ups:
- Ears finally read as ears; the shirt V is crisp with no streak; Vin's silhouette is no longer a helmet.
- The hair cut-outs around the ears are square windows (clearly visible on the coinshot, thug and guard in profile). Round the cut, or feather it with a sideburn wedge.
- Breeze's gold waistcoat still has a hot orange glow blob at the chest (the emission or metallic-ish dye on the waistcoat).

## Review of world pass 6

Merged:
- **CrowdMember flake root-caused.** Riot activity members took their home in `_ready` before being moved to their spawn point, so home was the world origin and they walked off roofs. Home is now taken on the first physics frame, with a 10 m drop-reset. `test_story_sweep` passed 10/10 and there's a new `test_crowd_member`.
- **Font.** "steel" rendered as "sted" because EB Garamond's tight "el" at ~12 px looked like a "d". The fix is 1 px glyph spacing in the theme, plus `tools/font_check.gd`.
- **Night.** An open-world night fill light was added and night ambient raised from 1.8 to 3.0; mission scenes are unchanged.
- **Keep Venture courtyard.** Dressed with a fountain anchor, banners, a carriage, sentry booths, planters and ashlar curtain walls, with a new mission-safety test.

301 tests green. Reviewed p6w_hud_night and p6w_keep_venture_courtyard_day.

Follow-ups:
- The dialogue now reads "steel" correctly. At night the player, the roof walk and the city read; the foreground chimneys are still near-black silhouettes, which is acceptable.
- Night values were tuned only on opengl3, so take one Vulkan night shot to confirm Forward+ isn't over-bright.
- **Courtyard** still reads as a vast empty plaza: the planters and booths are invisible at this scale and the props are tiny. It needs mid-scale structure: a paved central carriage loop, hedged lawns or low walls breaking up the space, lamp posts along the approach, and guard figures. The keep facade still uses the busy crazy-paving stone rather than ashlar. A large dark shadow shape fills the foreground (gatehouse or camera placement?).

## Review of art pass 9, and an ambush fix

Merged art pass 9:
- Elliptical hair cut-outs with tapered sideburns around the ears.
- Breeze's gold waistcoat as its own crisp panel: the glow was paint bleeding into the coat, not emission.
- A `--pose=idle|walk|run|jump|push|pull` lineup flag and a poses group.
- Fixes for the three worst animation problems:
  - Armed characters now Push/Pull with the free hand, so the spear and axe no longer pass through their heads.
  - A tucked jump apex.
  - A lower knee lift for robed runners.

Reviewed p9_after_ears_side and p9_after_poses_34.

Also fixed on the main branch: `test_soak` caught "died already connected" in `ActivityManager._start_ambush`. `EnemySpawner.spawn_type` returns the enemy already alive at a marker, so an ambush could get the same enemy twice, wiring it twice and listing it twice in `alive`. Killing it then never completed the ambush. Each enemy is now counted once, with a regression test (`test_ambush_counts_a_reused_enemy_once`) that fails without the fix. Soak passed 2/2 after the fix.

Follow-ups:
- Ear profiles read cleanly now, and Push/Pull no longer clips weapons.
- The off-hand Push reaches across the chest at 3/4. The Inquisitor's Pull pose brings his hand up to his face. The guard's Push holds the lantern forward rather than an open palm.
- `test_world_gen::test_slice_metal_density_and_streaming` ("Keep Venture streamed in") failed once in a full run while another agent was running heavy jobs on the same machine. It looks like a timing/load sensitivity; watch it and make the streaming wait condition-based if it recurs.

## Review of world pass 7 and art pass 10

Merged world pass 7:
- **Keep Venture courtyard** now has mid-scale structure: a paved carriage loop round the fountain, two hedged lawn beds, lamp posts down the approach, sentry figures at posts (`src/world/sentry_posts.gd`), and an ashlar keep facade replacing the crazy-paving stone.
- **Night fill** toned down for Forward+ (Vulkan) while keeping opengl3 readable.

Merged art pass 10:
- Push is an open-palm thrust. Pull is a fist hauled back (`pull`, 0.44 s), with the reach still available as `pull_reach`.
- The guard's lantern hangs on his belt.
- The lineup gains attack/melee/throw/hit/fall/dead/crouch review poses and a `--zoom=upper` close-up.

302 tests green. Reviewed p7w_keep_venture_courtyard_day, p7w_vulkan_hud_night_tuned, and fresh p10_after_push / p10_after_pull lineups (`--group=poses --cam=34`).

The CI-setup worktree branch `worktree-agent-ab1d031367fe88822` was not merged: CI, the build scripts and export presets are already on the main branch, so it is stale.

Follow-ups:
- The courtyard reads as a place now. The lawns are ash-grey, which fits the setting. The two foreground lanterns are very large in the default camera framing.
- At 3/4, the guard's and the Inquisitor's off-hand Push still lifts the hand beside the face instead of driving it forward toward the target. Vin and Kelsier read correctly.

## Review of art pass 11

Merged:
- **Off-hand Push** for the guard and the Inquisitor now drives the open palm to the sternum. The shoulder leads, the torso leans in, and the weapon arm swings back as a counterweight. The cause was camera geometry, not the key: the lineup's 3/4 camera sees the right end of the line almost head-on, so a shoulder-height palm foreshortened to sit beside the face.
- **Pull:** `pull_reach` now reaches to the chest as well, and the haul's spine twist is smaller so the spear and axe no longer swing across the body.
- **Throw:** all four armed characters (guard, hazekiller, thug, Inquisitor) throw with the free hand. The wind-up previously put the guard's spear through his neck and the Inquisitor's axe in his face.

302 tests green. Reviewed p11_after_push_side and p11_wip3_enemies_throw_wind_34.

Follow-ups:
- `melee` for the armed characters hasn't been checked. It is a wide weapon-hand swing and may clip the way the throw did.
- In the side Push, the Inquisitor's axe lies nearly horizontal under the pushing forearm. It reads, but an upright, lowered axe would be cleaner.
- The guard's dark glove makes his open palm read as a fist at a distance.

## Review of world pass 8

Merged:
- **Keep Venture courtyard lamps.** The lamps were a normal size. The problem was placement: the first pair stood about 2 m from the camera just inside the gate. The approach now uses 0.8-scale garden lamps, set back. Lamp posts take an optional `"scale"`, and the collision, Metallic anchor, nav, light and validator all follow it.
- **Streaming test.** The new `WorldStreamer.is_settled()` is true when nothing is in flight or queued and every wanted unit is loaded. `test_world_gen` polls it with a 300 s timeout instead of a fixed window. Under heavy load it settles in 1.5–2.7 s.
- **Set pieces.**
  - Modillion brackets under the merchant/noble cornices: one shared MultiMesh with a 140 m range.
  - Wrought-iron shop signs on merchant shopfronts (style key `shop_signs`).
  - Deterministic avenue statues on plinths in the noble and merchant districts (style key `statues`). They are never placed in the slice and they collide.
  - Docs are in `docs/OPEN_WORLD.md` and `docs/PERFORMANCE.md`.

302 tests green. Reviewed p8w_courtyard_after, p8w_noble_statue_after and p8w_merchant_cornice_after.

Follow-ups:
- The courtyard now reads at a sensible scale from the gate.
- **Statue:** a stark, pale, blocky figure that glows against the dark street. Use a sculpted mesh, or at least a weathered, darker bronze or verdigris material. The plinth reads as brick; it should be dressed ashlar.
- Statues can repeat every 128 m on long boulevards, which is too regular. Add jitter or skip some slots.
- **Cost:** noble chunk generation is up about 1.2 ms and a merchant street frame draws about 15% more primitives, mostly the modillions. Consider a shorter modillion range, or LOD them out beyond about 60 m.
- **Steel-jump margin:** `test_traversal` cp_3 → keep_courtyard now lands in 1087 of 1500 frames, against 943 before. It still passes, but with less margin.
- There is no close-up shot of the shop signs yet.

## Review of art pass 12

Merged:
- **Armed characters' free-hand actions.** For the guard, hazekiller, thug and Inquisitor, `melee`, `drink` and `talk` now use the free hand, with the weapon held upright. From the front, the old melee laid the spear and axe flat across the face. This doesn't change enemy combat: enemies strike with `attack`, and only the player plays `melee`.
- **Clips outside melee.** A frame-by-frame clearance scan of the weapon against the head, neck and torso found real clips in `run` and `sprint`: the thug's club went about 4.5 cm into his head and the Inquisitor's axe about 2 cm. The guard's spear also grazed his helmet brim during Push and the Pull reach. All are fixed, and no clip now comes within 1 cm.
- **Inquisitor side Push:** the axe stands upright and lowered at his side.
- **Guard's glove:** `Body.hand` takes an optional palm colour, and the guard has a pale leather palm.

302 tests green. Reviewed p12_after2_inq_push_side and p12_after_guard_push_front_upper.

Follow-ups:
- In the Pull haul, the Inquisitor's axe still leans about 43° inward. It doesn't clip.
- The clearance scan (scratchpad only) checks the weapon against the head, neck and torso, but not against the arms, the hazekiller's shield or robe skirts. Consider committing it as `tools/characters/clearance.py`, with a test.
- `docs/CHARACTERS.md` still describes `melee` as a dagger swing for everyone, and its triangle counts are out of date.

## Review of art pass 13

Merged:
- **Weapon clearance checker:** `tools/characters/clearance.py` needs only numpy and takes about 12 s.
  - It poses the guard, hazekiller, thug and Inquisitor frame by frame through all 20 clips.
  - Thresholds: 1 cm for the head, neck and torso; no overlap allowed with the arms (excluding the gripping hand and forearm), robe skirts, or the hazekiller's shield.
  - Each weapon builder in `chars.py` records its own capsules, so the check stays in sync with the models. None of this reaches the GLBs.
  - `tools/characters/test_clearance.py` includes a deliberate bad pose that the checker must catch. It runs from `tools/run_tests.sh` after the Godot suite, only with no filter and only when numpy is present. `set -e` still makes a Godot failure fail the run.
- **Inquisitor Pull:** the axe stays 8–11° from vertical through the haul (it was 43°), with no new clips.
- **docs/CHARACTERS.md:**
  - Free-hand actions for armed characters, and enemies strike with `attack`.
  - The `palm=` option on `Body.hand` and the clearance tool.
  - Measured triangle counts (4.0k–6.2k).
  - The guard's belt lantern.
- Also fixed the outdated `melee` comment in `scenes/test/character_lineup.gd`.

302 Godot tests and 5 clearance tests green. Reviewed p13_after_inq_pull_haul_34.

Follow-ups:
- In idle and the base pose, the Inquisitor's axe still leans about 40° forward. Only the Push and Pull holds are upright.
- The checker doesn't cover the legs, and models the shield as a flat disc without its boss.
- **Done:** CI installs `python3-numpy` before the test step, so the clearance test runs there.
- Tightest remaining gaps: 3.6 cm from the guard's spear and the hazekiller's staff to their skirts (in `sprint` and `block`).

## Review of world pass 9

Merged:
- **Statues:**
  - Weathered dark bronze with verdigris (not a Metallic anchor), on a smooth lathed figure: robe, cloak, bent arms, and a standard with a banner.
  - The plinth is dressed stone with mouldings. Keep Venture's fountain uses the same figure in iron.
  - **Spacing:** only every other qualifying avenue segment gets a statue, and the slot is jittered ±24 m. Gaps on a line now run 232–1,780 m (they were a fixed 128 m), and the planting draws are untouched.
- **Modillion cost:**
  - Modillions are grouped in 24 m cells, each culled beyond 64 m, on a 16-triangle mesh.
  - Primitives fell 11–12% at all four test poses with draw calls flat. The merchant street is within 2% of its count before pass 8.
  - `tools/preview.gd` now prints draw calls.
- **Steel-jump margin:** `cp_3 → keep_courtyard` takes 949 of 1500 frames again (it was 1087). The cause was that scaling a lamp lowered its Metallic anchor. Scaled lamps now keep the anchor at full post height.
- **Shop signs:** 1,078 of 4,480 signs were clashing with balconies or door lanterns. Clashing lots now try the other pier or get no sign. The merchant share went from 0.45 to 0.52, giving 4,351 signs and 0 clashes.

302 Godot tests and 5 clearance tests green. Reviewed p9w_statue_close_after and p9w_shop_sign_close_after.

Follow-ups:
- **Fragile traversal leg:** run on its own, `cp_3 → keep_courtyard` times out, and its frame count swings by about 150 with small courtyard changes. Make that leg's start state deterministic, or route it through a reliable anchor, so it doesn't depend on the previous leg's landing.
- **Statue count:** down from 58 to 47 after the every-other rule. Raise the `statues` shares slightly if density matters.
- **Modillion popping:** they pop out at 60–90 m with no fade. It is small, but a distance fade (`visibility_range_fade_mode`) would hide it.
- **Statue head:** still a featureless egg. In shade, the bronze statue reads as a dark silhouette.

## Review of art pass 14

Merged:
- **Upright weapon carry:**
  - The Inquisitor carries the axe like the guard's spear: forearm level, haft upright beside the shoulder. Forward lean of the haft:

    | Clip | Before | After |
    |---|---|---|
    | idle | about 40° | −2 to +4° |
    | walk | up to 53° | +2 to +4° |
    | run | up to 41° | +3 to +9° |
    | sprint | up to 53° | +6 to +14° |

  - In the gaits, the guard, hazekiller and Inquisitor take back 60% of the body's forward lean at the wrist and half the arm sway.
  - Push and Pull holds are unchanged.
- **Clearance check:**
  - A new `legs` region covers the thighs, shins and feet wherever no skirt covers them, using coverage each skirt records when it is built.
  - The hazekiller's shield gains its boss.
  - A test fails if any exported clip isn't scanned.
  - There are now 10 clearance tests (they were 5). The only real clip found came from this pass's own first crouch change, and it is fixed.
- **Skirt gaps:**

  | Clip | Before | After |
  |---|---|---|
  | guard `sprint` | 3.6 cm | 10 cm |
  | hazekiller `sprint` | 4.4 cm | 9.4 cm |
  | hazekiller `block` | 3.6 cm | 6.5 cm |

302 Godot tests and 10 clearance tests green. Reviewed cmp2_inq (Inquisitor idle, walk, run, sprint, push and crouch) and cmp_gh (guard and hazekiller, before and after).

Follow-ups:
- **Robe clipping:** the Inquisitor's legs poke through the front of his robe in `sprint` and `crouch` (clearly visible in the crouch). This is the robe against the body, which the clearance check doesn't cover. Add a robe-to-leg check, or give robed characters more skirt flare and shorter strides.
- The hazekiller's staff leans up to 21° in `sprint`, because it already leans 5–11° in idle.
- The Inquisitor's one-shot clips (`attack`, `hit`, `throw`) start from the new carry pose. They pass the clearance check but haven't been screenshotted.
- Skirt coverage uses rest-pose positions, so a thigh that swings past the hem mid-stride still counts as covered.

## Review of world pass 10

Merged:
- **Fragile traversal leg, root-caused.** The bot was circling 10–50 m above the courtyard. Air control only adds speed along the input direction, so it never removed sideways speed, and every lamp push it chose came from below and off to one side, which added more. The bot now uses terminal guidance within 30 m of the goal: it works out the horizontal speed that drops it onto the goal, steers to correct the difference, and pushes only for what air control can't fix.
  - The assertions, `LEG_FRAMES` and `REACH` are unchanged.
  - New `test_courtyard_leg_from_a_fresh_world`.
  - `cp_3 → keep_courtyard` takes 314 frames in the full route (it was 949) and 330 on its own. With the start nudged up to 1.2 m it takes 323–543.
- **Modillion fade.** `visibility_range_fade_mode` doesn't work here: it moves Forward+ into the transparent pass and Compatibility ignores it. Each bracket now dithers out between 32 and 48 m using a per-pixel distance fade on its own copy of the material (`WorldMaterials.faded()`), which renders the same in both renderers. The cost is 0.2–0.7% more primitives.
- **Statues:**
  - A modelled head: brow, nose, jaw, hair and a laurel wreath (950 triangles).
  - Lighter, less metallic bronze with a faint rim.
  - The shares went to noble 0.38 / merchant 0.19, giving 55 statues with gaps of 220–1,232 m.

303 Godot tests and 10 clearance tests green.

**Review note:** none of the pass's statue "after" shots (`p10w_statue_*_after`, `p10w_statue_head*_after`) contains a statue. They were taken before the final share change moved the statues. I re-shot one myself from the merged tree, at (−1540.7, −1727.0), seed 1337: `rv10_statue_{front,34,west,east_close}`. The bronze reads brown with patina in daylight, and up close the face shows a brow, a nose and the wreath. To find statues, run ChunkGenerator over `plan.chunk_range()` and read `instances[&"statue_bronze"]`. Agents should screenshot from the final tree, and check that the subject is in frame.

Follow-ups:
- Statue faces are crude at eye level, and the patina blotches look a little like camouflage on the lighter bronze.
- The `cp_1 → cp_2` push frames differ between the full route and the leg on its own (231 against 59), so the world isn't identical from leg to leg. It passes comfortably either way.
- At one nudged start the bot landed short and hopped the fountain rim to reach the goal (543 frames).

## Review of art pass 15

Merged:
- **Cloth check:** `clearance.py --cloth` covers all 16 characters with a skirt on the main mesh. Each frame it measures how far each leg vertex the cloth covers at rest sits outside the posed cloth. It counts legs leaving below the hem or through a slit as uncovered, not clipping, and fails anything showing through by more than 1.5 cm.
  - **Before:** the Inquisitor's knees came 24–37 cm through his robe in `sprint` and `crouch`. Sazed, Marsh and the obligators were at 28–38 cm, the gowns at 22–30 cm, and the coats and aprons at 11–22 cm.
  - **Fix:** skirt fronts follow the thighs, cloth below the knee partly follows the shins, and each skirt has 1–4 cm more room below the waistband.
  - **After:** about 1.2 cm at worst (not visible), and every robe and gown is within 0.7 cm.
- **Death clip:** armed characters let the weapon fall nearly flat beside the body. It used to stand straight up from the dead hand, and the spear and staff went 50–70 cm into the floor.
- **Weapon check:** leg coverage now uses posed positions.
- 15 clearance tests (they were 10). They now take about 70 s, and the comment in `tools/run_tests.sh` is updated to match.

303 Godot tests and 15 clearance tests green. Reviewed p15_cmp_inquisitor (crouch, sprint and crouch walk, before and after) and cmp_die.

Follow-ups:
- **Narrower weapon-to-cloth gaps:** the fuller robes and tunics bring weapons closer. The Inquisitor's axe passes 1.9 cm from his robe in `push` (it was 6.5 cm). The guard's `attack` and the hazekiller's `block` are at 3.5 cm. These pass, but the margin is thin.
- **Death pose:** lying on his back, the Inquisitor's robe rides up to his thighs and leaves his legs bare below it. It also flips up for a moment around 0.55 s. Weight the hem more toward the shins in `die`, or add a `die`-specific cloth settle.
- **Not checked:** skirts on separate garment meshes, such as noble men's coat tails and the bustle.
- **Hazekiller crouch:** the staff leans in front of his face from the front, which comes from the existing carry pose.

## Review of world pass 11

Merged:
- **Statue face:** a displaced-grid head with eye sockets, brow, nose, mouth line, chin, cheekbones and ears, with recesses darkened in the vertex colour. The figure is 1,254 triangles. The Keep Venture fountain figure shares the mesh.
- **Verdigris shader:** `assets/shaders/bronze.gdshader`. The patina gathers in recesses, on upward-facing surfaces, and in vertical runs below the shoulders, belt and chin that fade toward the hem. Placement is unchanged (55 statues).
- **Traversal determinism, root-caused.**
  - **Cause:** leg starts differed because `Player.respawn` kept the roll timer, jump buffer, coyote time and Pull tether. A hard landing left the next leg starting mid-roll.
  - **Fix:** `respawn` now clears them, which is also correct gameplay behaviour (no roll or tether carried over after a death or checkpoint reload). The test's `_start_leg` drops the player 0.5 m and waits until it has stood for 5 frames.
  - Every leg is now identical in the full route, on its own and from a fresh world, down to the landing position. Frames for the six legs: 190, 280, 250, 231, 391 and 377, all with 0 hops. Assertions and limits are unchanged.
- **Short landing:** an obstacle-height probe in the terminal guidance changed none of 13 nudged courtyard starts, which now all land with 0 hops, so it was reverted.

303 Godot tests and 15 clearance tests green, and the leg frame counts match the agent's report exactly. Reviewed p11w_faceclose34_t11_after and p11w_street34_t16_after (statue in frame in both).

Follow-ups:
- At about 1 m the head is still faceted, and the laurel leaves stick out sideways like spikes. Lay the wreath flat against the head.
- Seen close, the verdigris runs on the chest are fairly straight and evenly spaced. Add per-run jitter in width and length.

## Review of art pass 16

Merged:
- **Robes settle in death:**
  - Long robes and gowns (Inquisitor, Sazed, Marsh, both obligators, vin_gown, noble_woman and her bustle) get five skirt bones each. They stay at rest in every clip except `die`, where they flatten the robe over the legs. A test checks that they don't move outside `die`.
  - Robed styles fold their legs less as they fall, which removes the flip-up around 0.55 s.
  - **Result:** the hem lies 15–28 cm off the floor over the feet, where it used to be a stiff tube 31–53 cm open, partly under the floor. The new `clearance.py --settle` guards it.
- **Weapon-to-cloth margins:** every weapon-to-skirt gap is now at least 5 cm. For example, the Inquisitor's `push` went from 1.9 to 8.4 cm, and the guard's `attack` from 3.5 to 5.7 cm.
- **Garment meshes:** the cloth check now covers `noble_man:tails`, `noble_man:longcoat` and `noble_woman:bustle`. The knees were coming 15 cm through the long coat; that is fixed, and the worst is now 0.7 cm.
- **Hazekiller crouch:** at face height the staff is 27 cm to the side. It used to be 3 cm, crossing his face.

303 Godot tests and 21 clearance tests green (about 64 s). Reviewed p16_cmp_inquisitor_die and p16_cmp_robes_die: the lying robes and gowns now cover the legs, with only the feet at the hem.

Follow-ups:
- **Hem opening:** from the 34 and front cameras you can see into the lowered hem opening, because the cloth doesn't draw its inside faces. Turn off back-face culling on the cloth materials, or add an inner shell.
- **Characters without robes:** in death they still lie with their legs 10–15 cm off the floor and the left knee raised.
- **Hard-coded tuning:** the robe-flattening values were fitted offline with an optimiser that isn't in the repo, and only `--settle` and the cloth check guard them. Commit the fitting script if robe shapes are likely to change.

## Review of polish pass 17

Merged:
- **Double-sided cloth:** `cloth.tres` (also used for skin and leather) uses the new `character_cloth.gdshader`. Back faces are darkened: albedo ×0.22, no specular or rim, AO 0.4. Hem openings now read as shadow rather than see-through. The three character shaders share `character_surface.gdshaderinc`. Metal, obsidian and glow still cull back faces.
- **Death legs:** for characters without robes, the final `die` pose has nearly straight legs, the bent knee falls sideways, and the heels rest on the floor. The per-style `DIE_LIE` table keeps helmets, hoods and spikes out of the floor.
  - The new `clearance.py --dead` fails anything more than 1 cm below the floor, or a leg more than 5 cm above it.
  - Every character's lowest point is now between −0.6 and +0.9 cm.
- **Robe-fit script:** `tools/characters/fit_robe_settle.py` is the cleaned-up optimiser. It reproduces the committed values within 0.003, and `--check` refits every style and compares. The junior obligator was refitted for his new lift.
- **Statue:** the laurel is flat leaves lying along the band (1,238 triangles). The verdigris runs are placed per cell with their own position, width, length and strength. A speckle bug in the run hash is fixed.

303 Godot tests and 25 clearance tests green. Reviewed p17_cmp_hem_vin_gown, p17_cmp_dead_groups and p17_cmp_statue_head.

Follow-ups:
- **Dark insides:** with double-sided cloth, the openings at the neckline and puff sleeves now show a dark inside where they used to show background through the hole. A small dark patch at Vin's gown neckline is visible in the crouch at 3/4. It is acceptable, but an inner collar facing would be cleaner.
- **Short skirts in the floor:** coat and tunic skirts on characters without robes sink 2–17 cm under the floor when lying (worst is `skaa_woman`). This is hidden by the floor and not counted by `--dead`; consider a settle for them as well.
- Spook's hips sit about 2 cm off the floor in death.
- `fit_robe_settle.py` has no unit test; a full refit takes minutes per style.
- **Suite time:** the full `tools/run_tests.sh` takes about 8 min. The Godot suite is the slow part, at about 6.5 min of that.

## Review of the test-suite speedup

Merged. `tools/run_tests.sh` now takes about 70–80 s (it took about 505 s). In my verification run it took 80 s, with 305 Godot tests over 4 shards and 25 clearance tests, all green. No assertion, tolerance, frame limit or test was removed or loosened.

**Three real game bugs fixed along the way.** I reviewed each diff:
- **`ChunkInstancer.wait_for_bake`:** it polled `is_baking_navigation_mesh`, which only clears on a main-thread sync that the wait itself blocks. So it always ran to its 10 s timeout, twice per world freed mid-bake: a 20 s freeze in the game too. It now also checks that the baked polygons have arrived. This is safe because every bake uses a fresh `NavigationMesh` (`chunk_instancer.gd:431`). This one fix took the sequential Godot suite from 423 s to 178 s.
- **Camera landing dip:** an explicit spring step on `delta / time_scale` diverged on a long frame during atium. The camera went to y = 1e30 and then NaN, and a coin throw aimed along a zero vector. It is now integrated in steps of at most 1/60 s, which is identical at 60 fps. There is a regression test.
- **`WorldStreamer.load_now`:** it cleared every in-flight task id, so other units still generating were never waited for. That caused an abort at exit after a fast travel, and those units were generated twice. It also skipped wanted units that were already generating. It now waits for exactly the wanted units. There is a regression test.

**Runner:**
- Godot files are sharded over `TEST_JOBS` processes (default: CPU cores, at most 4; `TEST_JOBS=1` is sequential), heaviest file first, each file whole in one process.
- The clearance tests run alongside, in 2 processes (`tools/characters/run_parallel.py`).
- The run fails on any failed test, a crashed shard, a shard with no summary, an unrun file, or a Python failure.
- It prints per-test times over 2 s and tables of the slowest files and tests. `--reverse` and `--shuffle=<seed>` change the order; the whole suite passed in reverse and shuffled order.
- The docs are in `docs/PERFORMANCE.md` ("Test suite") and the README.

Follow-ups:
- ~~**Python tests finish last:**~~ Done: the weapon and cloth scans are one test class per character (the Inquisitor's and guard's weapon scans per share of clips), in 3 processes. The clearance tests take 25 s idle (was 37 s) and 51–58 s next to the shards, so the Godot shards (55–69 s) now finish last. The run took 68–77 s over 6 runs (80 s in a baseline run the same day).
- **Real-time tests set the floor:** `test_story_sweep` (41 s), `test_traversal` (40 s) and `test_soak` (31 s) run at 60 physics frames per second. Running them faster than real time would need a fixed-step, fast-forward test mode.
- ~~**Leaks at exit:**~~ Done: sounds still playing at quit (`AudioManager.shutdown`), a `MassBattle` soldier target cycle, and three unfreed nodes in `test_act3_missions`. The suite exits clean and `tools/run_tests.sh` now fails on Godot's leak report; see "Leaks at exit" in `docs/PERFORMANCE.md`. Two more intermittent failures found on the way, both real streaming races, are fixed with regression tests: `load_now` skipping units still instancing, and a streamed-in checkpoint area missed before `unit_loaded`.
- **`FILE_WEIGHTS`:** the table in `tests/run_tests.gd` is maintained by hand. If it goes stale, only the shard balance suffers, never correctness.

## Review of the exit-leak pass

Merged. The suite exits with no leaks: 17 of the 44 test files used to leak when run alone. A new guard in `tools/run_tests.sh` fails the run if any shard prints Godot's leak report. In my verification run: 309 Godot tests over 4 shards and 51 clearance tests, all green in 69 s, with no leak lines.

I reviewed every game-code change:
- **`AudioManager.shutdown()`:**
  - **Cause:** sounds still playing at quit leaked their playbacks and streams, because the AudioServer frees a stopped playback only on a later mix step. This was 16 of the 17 leaking files.
  - **Fix:** it stops all voices, frees and remakes the players, and waits at most 2 s, usually about 30 ms, until every playback is released. The pause menu's Quit awaits it.
- **`MassBattle`:** two soldiers targeting each other formed a RefCounted cycle that outlived the battle. `NOTIFICATION_PREDELETE` now clears the targets.
- **`ChunkInstancer`:** stage 8, which adds markers and checkpoint areas, now sets `_done` in the same step. It was already the last real stage; the default branch only set `_done` one frame later. So `unit_loaded` (which connects the checkpoint areas) fires before a physics step can report a player already inside an area. This fixes an intermittent "streamed-in checkpoint recorded" e2e failure.
- **`WorldStreamer.load_now`:** it also finishes wanted units that are still instancing, instead of skipping them. Before, it could return with a half-built unit.

There are regression tests for the audio, battle and both streaming fixes. One test leak was fixed in `test_act3_missions`. The runner gains `--test=<text>`. The split clearance tests are per character and garment, with a check that every (character, clip) pair is scanned exactly once, in 3 processes. The docs are in `docs/PERFORMANCE.md` ("Leaks at exit").

Follow-ups:
- Closing the game window quits without `AudioManager.shutdown()`. This only affects what the engine prints at exit. It could be hooked to `NOTIFICATION_WM_CLOSE_REQUEST`.
- With `--verbose`, Godot prints "unclaimed string names at exit" for its built-in type names. These are engine-held, not part of the leak report, and documented.

## Visual overhaul ("looks indie, not AAA")
The player asked for a Spider-Man 2 or Horizon look instead of "lego people". This pass has two parts. The first rebuilds every character from MakeHuman bodies. The second rebuilds the city's surfaces, lighting and facade detail.

### Done
- **Characters**: all 22 GLBs come from `tools/characters/mh_build.py`. They are MakeHuman hm08 bodies built from npm/PyPI data, which `fetch_mh.py` downloads.
  - The body is morphed, and the hands are posed relaxed.
  - Skin uses SSS, eyes have a glossy cornea, and hair, brow and lash cards are alpha-hashed.
  - Garments are cut from the body surface and Taubin-smoothed with pinned hems.
  - Skirts, capes and the mistcloak hang under gravity, are pushed out of the body, and get folds. The mistcloak's ribbons have spring-bone chains.
  - Other parts: lathed hats and helmets, armour shells, props, beards, and Inquisitor spikes.
  - Optional `G_` garments and the `hd_cloth`/`hd_hair` dye slots cover the existing crowd pools.
  - Crowd bases skip one subdivision level, so they are 50-90k triangles; hero characters are 180-280k.
- **Surfaces**: `tools/gen_textures_hd.py` generates the 2048 px sets:
  - setts, coursed rubble, ashlar, brick, render over brick, overlapping slates, and boards;
  - each set has a 16-bit height map.
  
  `world_surface.gdshader` adds triplanar POM on the dominant projection and macro variation. It also adds global `world_wetness`: damp by day, wet at night with puddles. A new SSR setting covers High and Ultra.
- **Lighting**: brighter lantern pools and darker Forward+ ambient and fill. The moon is the key light.
- **Facades**: window surrounds (stone architrave or timber frame) and door cases.

### Still open
- **Network-blocked photoscans**: `polyhaven.com`, `dl.polyhaven.org` and `ambientcg.com` are denied by the environment's network policy. Allowing them would replace the procedural sets with CC0 photoscans. `tools/fetch_assets.py` already exists.
- **Clothing still reads as fitted knit**: garments follow the body. Real folds need a loose-garment pass, such as a cloth sim on a slack copy, or fold normal maps by bone.
- **Hands — fixed.** MakeHuman's rest hand fans the fingers apart, so they read as a claw once curled. `relax_hands` now turns the index, ring and little fingers 70% of the way towards the middle finger before curling them.
- **Animation**: the procedural clips are the next "indie" tell. Motion-capture data such as CMU or Mixamo is not reachable through the registries.
- **Roofs — done.** Gables have ridge caps, fascia boards with soffits and barge boards. Flat roofs have stone coping on the parapets. Gable eaves have iron gutters and downpipes. Taller gables carry rows of dormers (attic windows, own RNG so mission anchors are unchanged).
- **Party-wall holes — fixed.** Adjoining lots both skipped their shared wall, leaving a hole above a lower neighbour (visible at the opening spawn). Main walls now keep shared faces; they sit hidden inside the neighbour and show as a blank firewall above it.
- **Test flake**: `test_crowd_member::test_member_positioned_after_add_stays_home` once ended 5.02 m from home against a 5.0 m bound under full parallel load. It passed on rerun and in isolation.
