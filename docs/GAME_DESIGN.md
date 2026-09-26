# Game Design — Vertical Slice "Ashes of Luthadel"

> Non-commercial fan game. Mistborn and all related names are © Brandon Sanderson / Dragonsteel Entertainment. This project is not affiliated with or endorsed by them.

## Pillars
1. **Allomancy is physics.** Pushes and Pulls obey Newton's third law and mass. Traversal and combat come from the same mechanic.
2. **The mists are alive.** It's a night-time city under ashfall with thick, swirling volumetric mist. Tin lets you see through it.
3. **Mistborn fantasy.** You're fragile but lethal. Flaring pewter lets you shrug off a blow, a coin can kill, and you arc between spires.

## Camera and controls
- Third-person over-the-shoulder camera, with a toggle to first person. The crosshair targets steel lines.
- WASD, mouse, Space and Shift. **LMB: Push, RMB: Pull.** They target the steel line nearest the crosshair, and holding the button keeps the line locked.
- Q throws a handful of coins (Push them to shoot). G drops a coin beneath you (the classic steel-jump anchor). Alt flares, R drinks a vial, and F is an obsidian dagger strike.
- Keys 1–9 toggle metals and B burns steel, iron, pewter and tin together. 0 is duralumin, used once for a massive enhanced Push/Pull.

## Metals in the slice
| Metal | Player effect |
|---|---|
| Steel | Blue lines to metals in range (~40 m, ~60 m flared). Push. |
| Iron | Same lines. Pull. |
| Pewter | +50% speed and jump. Takes 50% less damage (70% flared). No fall damage. Stamina-free sprint. Flaring drains fast. |
| Tin | Sees through mist (fog density drops, exposure rises), hears enemies through walls (outline markers), sees in the dark. Flaring near bright light causes a brief glare. |
| Bronze | Shows allomantic pulses from enemy allomancers (Coinshots, the Inquisitor) as ripples on screen, unless they burn copper. |
| Copper | Hides your own pulses from enemy Seekers and the Inquisitor, which lowers detection. |
| Zinc | Riot the targeted enemy: they rush aggressively. |
| Brass | Soothe the targeted enemy: they calm down or lose track of you. |
| Atium | For ~8 s, enemies show golden "shadows" of their next move, and time slows to 60%. Very scarce. |
| Duralumin | One-shot enhancement. It burns away every other burning metal in a ×10 burst. |

Reserves run from 0–100 per metal. Vials (pickups) restore steel, iron, pewter and tin. Atium beads and duralumin are rare pickups.

## Enemies
| Type | Description |
|---|---|
| **Guard (Obligator's guard)** | Spear and steel breastplate. You can Push them off roofs. Patrols with a lantern. |
| **Hazekiller** | Wooden weapons, no metal, and a wooden shield that blocks coins. Throws wooden javelins. Counters coinshots. |
| **Thug (Pewterarm)** | Big and fast melee. Burns pewter. Has no metal, so only coins can hurt them. |
| **Coinshot** | Enemy allomancer. Throws and Pushes coins, steel-jumps between roofs, and Pushes your coins back. |
| **Steel Inquisitor** | Boss/chaser. Spikes are shielded (can't be pushed). Burns all metals, Pushes and Pulls aggressively, and regenerates. It can only be escaped or slowed in the slice. |

Guards and thugs are standard AI. Hazekillers use cover and flanking. Coinshots and the Inquisitor use the same `Allomancer` component as the player.

## Mission: "Mistwalk to Keep Venture"
1. **Rooftop lessons.** You start on a rooftop in the Skaa quarter. Kelsier's voice appears as text hints. Burn steel and see the lines. Push off the lamp post to jump. Pull a coin back. Drop a coin and steel-jump to the next roof.
2. **The mists.** Cross the district over rooftops toward Keep Venture's spire, reaching three checkpoints. Burn tin to see through the thick mist. Patrol guards are in the streets below.
3. **The courtyard.** Keep Venture's walled courtyard holds guards, 2 hazekillers and a thug. Sneak in or fight. Retrieve the ledger from the gatehouse office, which is the objective.
4. **The Inquisitor.** A Steel Inquisitor arrives (bronze reveals its pulses). Escape to the canal extraction point 300 m away with the Inquisitor chasing you. Atium pickups are placed along the route.
5. **Extraction.** Reach the canal boat. Mission complete and stats screen.

Failure: death sends you back to the last checkpoint.

## Look and feel
- The palette is ash grey, soot black, cold moonlight and warm orange lanterns. The mist is off-white and lit by lanterns.
- Luthadel is dense 3–6 storey soot-stained stone and brick with pitched slate roofs and chimneys. Narrow cobbled streets, canals, and Kredik Shaw's black spires dominate the skyline.
- Steel lines are thin, glowing blue lines from the chest to each metal. Their brightness scales with metal mass and they fade with distance.
- Ash drifts constantly. Mist tendrils coil around allomancers while they burn.

## Long-term vision: the full story in an open-world Luthadel
The end goal is to play the whole story of *The Final Empire* in a seamless, traversal-first open world in the style of Spider-Man 2. Later books can follow as expansions.

- **World.** All of Luthadel, several kilometres across and streamed in chunks. It has the Skaa slums, the merchant quarters, the noble keeps (Venture, Hasting, Lekal, Elariel), Fountain Square, the canals, the city wall, and Kredik Shaw at the centre. The Ashmounts sit on the horizon. The Pits of Hathsin and the rebel caves are separate mission spaces. The layout is a data-driven city plan with hand-placed landmarks, and procedural generation fills in the rest. See `docs/OPEN_WORLD.md`.
- **Traversal first.** Steel and iron are the web-swinging. Momentum-preserving Push/Pull chains, coin-jumps and Pull-swings toward spires are optionally assisted by automatic anchor selection.
- **Story.** Missions are data files, grouped into acts that follow the book's arc: recruitment, training, the crew's plans, noble balls, the Pits, the skaa army, Kredik Shaw, and the Lord Ruler. The dialogue and hint text is original; book passages are never copied.
- **Open-world activities.** Coin races through rings, rooftop pursuits, obligator patrol ambushes, Hazekiller hideouts, and collectibles (atium beads, crew notes, lost metal caches). Kelsier's training challenges double as skill trees.
- **Progression.** Allomantic mastery upgrades cover Push strength, range, flare efficiency, pewter endurance and tin range. Coin-pouch and vial capacity also grow. The noble-ball disguise sections are a social stealth mode.

## Roadmap
1. **Vertical slice**, done: core allomancy, one mission, the streamed city core around the slice route.
2. **Open-world foundation**, done: full city plan and streaming, map/journal, side activities, save anywhere.
3. **Act I**, done: Vin's recruitment ("The Survivor's Offer"), meeting
   the crew at Clubs' shop ("The Crew"), the rooftop mistwalk to Keep
   Venture, advanced training with Kelsier ("Lessons in the Mists"), and the
   first noble ball as Lady Valette — five chained mission JSONs under
   `src/mission/missions/`, plus a lightweight dialogue system
   (`src/dialogue/`), interior scene transitions (`src/world/scene_transition.gd`),
   cutscene-lite letterboxing, and the ball's suspicion meter. Crew/noble
   NPCs are placeholder tinted capsules pending real `CharacterModel` GLB
   variants (in progress in parallel).
4. **Act II**, done: the crew's plan unfolding — noble politics, heists and
   the Pits — six chained mission JSONs continuing after `lady_valette`:
   - **Dinner at Keep Venture**: a second, quieter social mission at the
     Ventures'. Meeting Elend Venture (a choice-driven dialogue sets one of
     three relationship flags), eavesdropping on house politics with tin,
     and picking a pocket with Pull.
   - **The Canton of Resource**: a night heist for the obligators' ledgers.
     A stealth interior with patrolling guards and a bronze-burning
     `Seeker` (`src/enemies/seeker.gd`) that senses the player's own
     allomantic pulses — copper, not just staying in shadow, is the real
     counter. One guard going hostile is a quiet takedown; several at once
     trips the heist's alarm state and fails the mission.
   - **Soothing the Masses**: Breeze teaches brass and zinc on a skaa
     street crowd. A shared `CrowdMoodMeter`/`CrowdMember` pair (reusing
     `receive_emotional_allomancy`) tracks the square's temper, soothed or
     riled to steer the confrontation, alongside recruiting a soldier for
     the rebellion.
   - **House War**: a covert rooftop strike on Keep Tekiel — coinshots and
     hazekillers — ending with a `push_target` set piece: Pushing or
     Pulling down a suspended iron gate to stoke the Venture/Tekiel feud.
   - **The Pits of Hathsin**: a separate mission space — a stepped crevasse
     shaft with embedded iron spikes to Pull down onto, an atium geode
     vein, a short stealth stretch past guards, and Kelsier's history told
     through original dialogue and environmental storytelling (no book
     text reproduced).
   - **The Inquisitor's Shadow**: a Steel Inquisitor hunts the crew across
     a rooftop chase protecting Spook, ending in a survivable first clash
     (the new `survive` objective type).

   Plus three new open-world activities between missions: "Obligator
   Courier Interception" (a rooftop chase), "Soothing Riots" (a
   `crowd_riot` `ActivityManager` type — calm a boiling-over crowd before
   time runs out) and "Noble Carriage Coin-Heist" (a pursuit). All new
   interiors bake their own `NavigationRegion3D` so real enemies can patrol
   them; see `src/mission/interiors/` and `tests/test_act2_missions.gd` /
   `test_act2_interiors.gd`.
5. **Act III**, done: the finale of *The Final Empire*, six chained mission
   JSONs (act "3") continuing after `the_inquisitors_shadow`:
   - **The Army in the Caves**: the skaa rebellion's hidden caverns outside
     the city (a new mission space, the army drilling as a `MassBattle`),
     then Yeden marches early and the army is crushed on the plain below
     the south wall. A battlefield set piece: rescue three of five wounded
     rebels and fall back to the ridge as the garrison advances. Many cheap
     soldiers (`src/mission/battle/mass_battle.gd`: two factions, morale,
     rout, at most 60 simulated with reinforcements queued, MultiMesh
     rendering, distance-throttled thinking).
   - **Fountain Square**: the executions. Fight through an Inquisitor-guarded
     crowd to the front, but the platform is sealed off. Kelsier duels an
     Inquisitor and the Lord Ruler strikes him down (the `kelsier_last_stand`
     cutscene, with eased camera pans and staged `call_group` beats), then
     escape. The Lord Ruler appears as a `LordRuler` placeholder boss (a tall
     imperial figure, `src/enemies/lord_ruler.gd`).
   - **The Survivor's Legacy**: the crew regroups under Clubs' shop (Sazed
     and the logbook, Kelsier's eleventh metal), then an investigation in
     Keep Venture's library: clues, a tin-gated annotation revealing the
     bracers, eavesdropping on Straff, and Elend's choice-driven political
     beat (he stays in Luthadel when his father leaves).
   - **Into Kredik Shaw**: a hand-built palace distinct from the procedural
     keeps. The Spire Court under the black spires, the vast Hall of Spires
     with Inquisitor patrols, a Seeker and high iron braziers, and the Hall
     of Gazes duel against an Inquisitor that hunts by bronze
     (`Inquisitor.senses_pulses`; copper hides you). It ends in a scripted
     capture (`vin_captured`).
   - **The Pits Beneath the Palace**: Vin wakes drained (`drain_metals`).
     Sazed opens her cell, Elend is in the next one, she rebuilds her
     reserves from three smuggled vials and climbs an iron-runged shaft.
   - **The Lord Ruler**: the final boss in the throne hall. He regenerates
     and shrugs off coins. Phase 1: he Pushes on the metal inside you, so
     burn it away. Phase 2: Soothe then Riot the skaa mob in the square
     below the gallery. Phase 3: stagger him and Iron-Pull his bracers (his
     metalminds) off, which works only while he's staggered, then finish
     him. The finale cutscene (the city rising, Elend) rolls the credits,
     then the game continues as **post-game free roam** with every activity
     open (`GameState.post_game`).

   Supporting systems: `MissionBackdrop` (`src/world/mission_backdrop.gd`)
   gives every isolated open-air scene the real night sky and far Luthadel
   skyline, reusing `EnvironmentBuilder` and a filtered `FarLod`. It is
   applied to the Act II rooftop, chase and street scenes too. Also:
   `SceneTransition.switch_interior`; new director actions (`switch_interior`,
   `call_group`, `drain_metals`, `grant_metals`, `roll_credits`) and the
   `cutscene` objective type; mission `journal` entries in the pause menu;
   interior deaths respawn inside the interior; a scrolling `CreditsScreen`
   (fan-game disclaimer, tools, CC0/OFL assets); and the Inquisitor chase
   now starts its hunter 40 m back. Tests: `tests/test_act3_missions.gd`
   and `tests/test_mass_battle.gd`.
6. **Polish** (next): authored hero assets to replace procedural ones
   (starting with the Lord Ruler, Inquisitors and the crew), voice, full
   cinematics in place of the cutscene-lite set pieces, accessibility,
   and performance passes (the mass battle, backdropped scenes and palace
   halls on the Low preset).
7. **Beyond *The Final Empire***: *The Well of Ascension* and *The Hero of
   Ages* as expansions on the same open-world Luthadel.
