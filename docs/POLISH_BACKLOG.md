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
