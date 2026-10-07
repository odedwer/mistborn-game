# Characters

There are six procedurally generated combat characters: `vin` (player), `guard`, `hazekiller`, `thug`, `coinshot` and `inquisitor`. There are also sixteen NPC models (see below). Each is a Godot scene at `res://assets/models/characters/<id>.tscn`. The root is a `Node3D` with `character_model.gd` (`class_name CharacterModel`), and its `Model` child is the imported `<id>.glb`.

| id | height | tris | materials | notes |
|---|---|---|---|---|
| vin | 1.65 m | 6.2k | Cloth, Cloak, Obsidian | mistcloak with 16 spring-simulated tassels; obsidian dagger in the right hand, a second one sheathed at the back |
| guard | 1.80 m | 5.2k | Cloth, Metal, Glow | steel cuirass, pauldrons, kettle helmet; spear; dark gloves with pale leather palms; lantern hung from the belt at the left hip (it adds an unshadowed OmniLight) |
| hazekiller | 1.79 m | 4.7k | Cloth | leather and wooden armour, hood and mask, round wooden shield, staff (no metal) |
| thug | 2.12 m | 4.3k | Cloth | huge build, bare arms, open vest, wooden club |
| coinshot | 1.82 m | 5.1k | Cloth, Cloak, Metal | dark long coat and a shorter mistcloak variant (11 tassels) |
| inquisitor | 1.99 m | 4.1k | Cloth, Metal, Obsidian | tall and gaunt; grey robes with red and black accents; spikes through both eyes (points jut out of the back of the skull); a spike between the shoulder blades that pokes out of the chest; obsidian axe |

Heights and triangle counts are measured from the generated assets: `height` and `tris` in `assets/models/characters/<id>.json`. The triangle counts match the index counts in the GLBs.

### NPCs (`tools/characters/chars_npc.py`)
Tris are body / body plus every optional garment. Every character is within 3–8k triangles (currently 4.0k–6.2k) and uses at most 3 materials.

| id | height | tris | notes |
|---|---|---|---|
| kelsier | 1.87 m | 5.0k | tall; mistcloak (18 tassels); sleeves rolled to the elbow over scarred forearms (Pits of Hathsin) |
| dockson | 1.78 m | 5.5k | stocky; short beard; knee-length practical coat; satchel |
| breeze | 1.76 m | 5.3k | portly; plum tailcoat, gold waistcoat, cravat, watch chain; dueling cane (aimed in the idle pose) |
| ham | 1.89 m | 4.7k | muscular; sleeveless vest, bare arms, wrist wraps; staff across the back |
| clubs | 1.66 m | 4.7k | old, balding with a grey fringe; stooped with a limp (`limp` gait style); leather apron and hammer |
| spook | 1.78 m | 4.6k | lanky teen; baggy sleeves, scarf; oversized cap |
| sazed | 2.01 m | 4.9k | very tall, bald; steward's robe with chevron V panels; stacked metal earrings and bracers (metalminds); hands clasped |
| marsh | 1.83 m | 4.0k | gaunt, stern; dark obligator-style robe with a stole |
| elend | 1.84 m | 4.5k | young noble; rumpled suit (skewed waistcoat, untucked shirt tail, loose cravat, one collar up); armful of books |
| vin_gown | 1.67 m | 4.8k | Vin as Lady Valette: pale blue silk ball gown, gloves, hair flower |
| noble_man | 1.82 m | 4.4k / 5.3k | garments `tails, longcoat, hat_top, hat_bowler, cape`; presets `noble_man_1..3` |
| noble_woman | 1.68 m | 4.8k / 5.3k | gown; garments `bustle, hat_wide, hat_small, shawl`; presets `noble_woman_1..3` |
| obligator | 1.81 m | 4.4k | senior: tall, grey robes, rank chain, dense eye tattoos, hands clasped in front |
| obligator_2 | 1.73 m | 4.5k | junior: stout, darker robe, skullcap, fewer tattoo spikes, hands behind the back |
| skaa_man | 1.76 m | 4.4k / 5.0k | ragged patched tunic, rope belt; garments `cap, hood, sack, scarf` |
| skaa_woman | 1.64 m | 4.7k / 5.1k | ragged dress and apron; garments `headscarf, shawl, basket` |

**Variants (crowd variety).**
- Optional garments are separate `G_<name>` meshes on the same skeleton.
- Dyeable regions are tagged in the vertex-colour alpha (1 = none, 0.75/0.5/0.25 = dye slot 1/2/3; see `body.dyed`). The shaders recolour them from the per-instance uniforms `dye_1..dye_3`. This keeps the material shared, so there are no extra draw-call materials.
- `CharacterModel` exports `garments`, `dye_colors` (sRGB), `body_scale` and `variant_pool`. `apply_variant(garments, dyes, scale)` sets a look explicitly. `randomize_variant(seed)` picks deterministically from the pool, which `godot_files.py` writes from `chars_npc.POOLS`.
- Presets (`noble_man_1` and so on) are extra wrapper scenes over the same GLB.

## NPC hookup
- **`NPCTalker`** shows a `CharacterModel`, picked in this order:
  1. `model_id`, if set;
  2. otherwise the first word of `display_name` ("Ham" → `ham`, "Elend Venture" → `elend`);
  3. otherwise a title or keyword ("Lord"/"Lady" → a noble base model, "Obligator", "Skaa"), with a variant seeded from the name.
  
  It falls back to the old capsule. It plays idle and walk while wandering, turns to face the player and plays `talk` on interact. `idle_chatter` makes it gesture now and then.
- **`CrowdMember`** (the Act II crowds) uses a skaa model with a random variant.
- **`DisguiseZone`**: add it to an interior and the player wears `vin_gown` inside that interior, through `Player.set_model_scene`. It is used in the ballroom and at the Keep Venture dinner.
- **`CrowdSystem`** (`src/world/crowd/`) adds ambient skaa and obligator pedestrians to the open world:
  - Agents are lightweight nodes parented per streamed chunk, so they stream out like the enemies. They walk sidewalk lanes derived from `ChunkLayout`.
  - Density and the obligator share depend on the district.
  - Only the nearest `max_visible` (30) agents within 70 m get pooled models. Beyond 25 m, animation is advanced manually every 3rd frame. Beyond 28 m, models cast no shadows. Mesh LODs come from the importer.
- **Previews:**
  - `scenes/test/character_lineup.tscn -- --group=crew|gentry|folk|all` (plus `--variants=N --only=skaa_man`)
  - `scenes/test/interior_preview.tscn -- --interior=hub|ballroom|office`
  - `scenes/test/crowd_preview.tscn`

## Conventions
- **Facing:** the `CharacterModel` root faces **+Z**, which matches `player.gd` and `enemy_base.gd` (`yaw = atan2(dir.x, dir.z)`), so `model_yaw_offset_deg = 0`. Inside, the glTF faces -Z and the `Model` child is rotated 180°.
- **Feet** are at the origin. Everything is in metres. Animations are in place, with no root motion.
- **Skeleton:** there is one `Skeleton3D` per character. It uses the Godot humanoid bone names: `Root, Hips, Spine, Chest, UpperChest, Neck, Head, Left/Right{Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes}`, so it can be retargeted. Cloak characters add `Tassel_NN_k` chains under `Chest`. The long robes and gowns add five skirt bones (`SkirtHips`, `Left/RightSkirtThigh`, `Left/RightSkirtShin`, see *Skirt weights*).
- **Materials** are shared `ShaderMaterial`s in `assets/models/characters/materials/`: cloth, cloak, metal, obsidian and glow. They are mapped at import time through `_subresources` in the `.glb.import` files (written by `godot_files.py`; the GLB's own materials are replaced). Albedo comes from vertex colours (stored as sRGB). Surface detail (weave/grain/grime) is procedural in UV space, where UVs are in metres. A rim term keeps silhouettes readable at night. The three shaders share `character_surface.gdshaderinc`:
  - `character_cloth.gdshader` (cloth, which also covers skin and leather) is double-sided, so the inside of a robe or gown shows through its open hem (lying down, crouching) and the end of a sleeve, where the floor and legs used to show through the missing faces. Godot lights a back face as if it faced the camera, so the cloth shader shades back faces dark (albedo × 0.22, no specular or rim, AO 0.4): the inside reads as shadow. Elsewhere the body is closed and its back faces fail the depth test.
  - `character_cloak.gdshader` (mistcloaks and capes) is double-sided too, with its back faces at 0.6 (the inside of a cloak is lit).
  - `character.gdshader` (metal, obsidian, glow) culls back faces.
- **LOD:** `meshes/generate_lods=true` is set on import (automatic mesh LODs), plus shadow meshes.

## API (`CharacterModel`)
```gdscript
set_locomotion(speed: float, grounded: bool, vertical_speed := 0.0)
set_crouching(on: bool)
play_action(name: StringName) -> bool
apply_variant(garments, dyes, scale) / randomize_variant(seed) -> bool / get_garment_names()
set_aim(world_dir: Vector3)
get_attachment(name: StringName) -> Node3D
revive()
is_dead() / is_crouching() / is_action_playing() / has_animation(name) / get_model_height()
signal action_started(name) / action_finished(name)
```
- **`set_locomotion`** drives an `AnimationTree` state machine with the states `ground`, `crouch`, `air` and `dead`:
  - `ground` = idle ↔ BlendSpace1D (walk 1.3 / run 4.2 / sprint 7.5 m/s, cyclic sync), with a time scale above sprint speed and below walk speed.
  - `crouch` = crouch_idle ↔ crouch_walk.
  - `air` = fall.
  - Landing faster than `auto_land_speed` (default -6 m/s) plays `land` automatically.
- **`play_action`** takes `jump, land, throw, melee, attack, hit, die, block, alert, push, pull, drink, talk`:
  - `throw, melee, push, pull, drink, talk` are upper-body one-shots (spine, arms and head filter), so they layer over running.
  - The others are full-body one-shots.
  - `die` moves to the `dead` state and holds the final pose until `revive()`. While dead, other actions return `false`. Unknown names also return `false`. The armed characters let the weapon fall flat beside them as they land (it used to stand straight up from the dead hand, and the spear and staff went 50–70 cm into the floor). The long robes and gowns settle over the legs (see *Death settle*).
  - Lying dead, the legs rest on the floor, relaxed: nearly straight, the left knee bent 14° and both thighs turned out (`ltwist`, 15° and 35°), so the bent knee falls sideways instead of standing up, with the feet on their heels, pointed. They used to lie 7–13 cm off the floor with the left knee raised. `DIE_LIE` in `anim.py` corrects the lying pose per style so nothing sinks into the floor: the bulkier hips and thighs (the thug, Ham, Dockson, Breeze, the junior obligator) lift the body 1.5–2.2 cm; the guard's helmet brim, the hazekiller's hood and the Inquisitor's skull spikes tip the head forward (they went 4–8 cm into the floor); Elend's and the junior obligator's left hands rise off it. `clearance.py --dead` checks it.
  - `attack` is character-specific: a dagger slash (vin), a spear thrust (guard), an overhead staff strike (hazekiller), a club smash (thug), a coin throw (coinshot) and a diagonal axe chop (inquisitor). Enemies strike with `attack`. Only the player plays `melee`.
  - `melee` is a wide one-handed swing: a dagger slash for Vin, a punch for the coinshot.
  - **Free hand.** The armed characters (guard, hazekiller, thug, Inquisitor) carry their weapon in the right hand. Their `melee`, `drink`, `talk`, `throw`, `push` and `pull` use the free left hand, while the weapon arm holds the weapon upright and clear of the head. In idle and the gaits, the Inquisitor carries his axe like the guard's spear, forearm level and haft upright (from the side and the front) beside the shoulder; in Push and Pull he holds it upright and low at his side. These poses are the right-handed keys mirrored by `free_hand()` and `arm()` in `anim.py`.
- **`set_aim`** uses a `CharacterAimModifier` (a `SkeletonModifier3D`) that spreads yaw and pitch over Spine→Head. It is clamped, smoothed, and fades out for targets behind the character. Pass `Vector3.ZERO` to turn it off.
- **`get_attachment`** takes `hand_r`, `hand_l` (the grip centre), `chest` (front of the UpperChest, e.g. where the guard's metal sits), `head`, `lantern` (guard) or any bone name. It returns a `Node3D` under a `BoneAttachment3D`, created on first use.
- **Cloak dynamics:** a `SpringBoneSimulator3D` has one setting per tassel chain, with capsule colliders on the hips and legs. It simulates in world space, so the tassels stream behind the character when it moves or turns. You can tune `cloak_stiffness`, `cloak_drag` and `cloak_gravity`, or turn it off with `cloak_physics = false`.

## Regenerating
```bash
tools/characters/build.sh                 # all characters (creates tools/characters/.venv-bpy with bpy==4.5.4 on first run)
tools/characters/build.sh vin guard       # a subset
```
The pipeline has these parts:
- `meshkit.py`: lofted tubes, ribbons and boxes, with proximity-based skin weights.
- `body.py`: the shared skeleton and the body-part builders (torso, head, hair, arms, hands, legs, feet, skirts, mistcloak and tassel chains).
  - `Body.hand(side, color, palm=None)`: the optional `palm` colour paints the palm and the inner faces of the curled fingers and thumb. A dark glove with a pale leather palm (as on the guard) reads as an open hand in a Push instead of a fist.
  - Clearance proxies, which never reach the GLB:
    - weapons register capsules in `Body.weapon_caps`;
    - shields register discs in `Body.shields` (the board and its boss);
    - `Body.skirt` records its hem in `Body.skirts` and its vertex grid (rings by columns, hem last) in `Body.skirt_grids`, so the checks can rebuild the cloth surface in any pose. A skirt on a garment mesh goes to `Body.garment_skirts[garment]` instead;
    - `with b.part(name):` tags vertex ranges in `Body.parts`. Props are tagged `weapon` or `shield`, and `Body.skirt` tags `skirt`.
  - **Skirt weights.** `Body.skirt` weights the cloth to the hips and, more and more towards the hem, to the thighs (`leg_share`). Every robe, gown, tunic and coat also sets:
    - `front_share`: over the front, the cloth follows the thighs from the upper thigh down, so a crouch or a sprint's knee lift carries it forward. It fades to a quarter at the sides and is off at the back;
    - `shin_share`: below the knee, this share of the leg weight goes to the shin, so the cloth hangs along it rather than flying up with the thigh;
    - `ease`: the rings below the waist band are this much wider, for the hip and the top of the thigh.

    The skirts of the optional garment meshes (noble men's tails and long coat) use the same shares; the cloth check found the knees 15 cm through the long coat without them.

    **Death settle (skirt bones).** A long skirt (hem below 10% of the height: the Inquisitor, Sazed, Marsh, both obligators, `vin_gown`, `noble_woman` and her bustle, `settle=` in `Body.skirt`) is skinned below its waist band to the skirt bones instead of the hips, thighs and shins. Each skirt bone is a child of the bone it replaces, so the weights are unchanged and the bones stay at rest in every clip but `die` (they are still keyed there, so a blend out of the death pose drops the squash). In `die` they scale (front to back and sideways) and shift (`SKIRT_CLASS` and `SETTLE` in `anim.py`): lying down, the robe flattens over the legs, strongly below the knee, less over the thighs and little round the hips. The robed styles also fold their legs less as they sit down (the thighs carried the robe's front past horizontal and showed its open hem around 0.55 s) and lie with them nearly flat, feet pointed. Before art pass 16, the lying robe stayed a stiff 50 cm tube: it stood 31–53 cm off the floor over the feet, open, with its back 14–40 cm under the floor. Now the hem lies 15–18 cm off the floor (the gowns 28 cm, over the upturned feet). The `SETTLE` values were fitted so the lower half of the cloth lies as low as it can while every leg and hip point it covers stays 1 cm inside it, allowing the cloth up to 2 cm under the floor (`fit_robe_settle.py`). Only rotation and the Hips' location were keyed before; the skirt bones also key scale and location (`bake_actions`).

    Before art pass 15, the legs showed through every long skirt. The knees came 24 cm through the Inquisitor's robe in the sprint and 31–37 cm in the crouch, 22–30 cm through the gowns in the crouch, and 28–38 cm through the obligators', Marsh's and Sazed's robes.
- `chars.py`: the six combat designs and their props.
- `chars_npc.py`: the NPC designs, hats and garments, plus the variant `POOLS` and `PRESETS`.
- `anim.py`: semantic pose parameters, 2-bone leg IK, gaits and one-shot keyframes. It also holds the per-character styles (spear arm, lantern arm, hunch, and so on).
- `build_characters.py`: builds the Blender armature, mesh and actions, then exports the GLB. Looping clips are named `-loop`, which makes the importer set the loop flag.
- `godot_files.py`: writes the materials, `.tscn` and `.import` files.
- `clearance.py`: the weapon and cloth clearance checks (see below).
- `fit_robe_settle.py`: fits the death-settle skirt bone poses of a long robe or gown (`SETTLE[style]["lie"]` in `anim.py`). Over the lying part of `die` (0.95 s and 1.3 s) and every character of the style, it lowers the lower half of the cloth and its hem as far as it can while every leg and hip point the cloth covers in the rest pose stays 1 cm inside it, and no cloth sinks more than 2 cm under the floor (differential evolution, then Powell; numpy and scipy, a few minutes per style). The robes fit the front-to-back flattening (`fb`) and shift (`lift`) of the hips, thigh and shin skirt bones, with the sideways spread fixed at 1.1 / 1.15 / 1.15; the gowns also fit the spread, and count the feet as covered (`--margin=0`; their hems reach the floor, and the toes poked through). Rerun it after changing a robe's shape, the robed styles' death legs or their `DIE_LIE`, paste the printed `_lie(...)` line into `SETTLE`, then run `clearance.py --settle` and `--cloth --anim=die`. `--check` refits every style and compares it with `SETTLE` (fb and spread within 0.06, lift within 1.5 cm). It reproduces the committed values within 0.003; the junior obligator's were refitted in art pass 17, after `DIE_LIE` lifted his body 2 cm.
    ```bash
    python3 tools/characters/fit_robe_settle.py inquisitor     # fit one style, print its SETTLE line
    python3 tools/characters/fit_robe_settle.py --check        # every style, against anim.SETTLE
    ```

Preview with `godot res://scenes/test/character_lineup.tscn -- <options>`. The options are documented at the top of `character_lineup.gd`, for example `--only=vin --anim=run --t=0.2 --cam=side --light=studio --shot=out.png`, or `--moving` for cloak dynamics.

Tests are in `tests/test_characters.gd`.

### Clearance checks (`clearance.py`)
**Weapon clearance.** The check poses each armed character (guard, hazekiller, thug, Inquisitor) frame by frame in every animation (every clip in `anim.ANIM_NAMES`, which is also the list the GLBs export). It needs only numpy, not Blender. It skins the mesh the same way `build_characters.py` bakes it, then measures the surface gap between the weapon capsules and these parts of the body:
- the head, neck and torso;
- the arms: the free arm and the weapon arm's upper arm, but not the gripping hand and forearm;
- the legs: thighs, shins and feet, wherever no skirt covers them in that frame. A leg point counts as covered while it is inside a skirt's posed cloth surface (see the cloth check), so a thigh that swings out past the hem mid-stride counts as exposed. Standing, that leaves the thug's whole leg, the guard's and hazekiller's below the tunic, and only the Inquisitor's feet below his robe;
- robe, tunic and coat skirts;
- the hazekiller's shield: the board as a disc, plus its boss as a stack of thinner discs (each at the widest radius of its slice).

The body is sampled at its vertices, face centroids and edge midpoints. A region fails when the weapon comes closer than 1 cm to the head, neck or torso, or when it penetrates the arms, legs, skirts or shield.
```bash
python3 tools/characters/clearance.py                                  # all four, every clip: each region's minimum (m) and when it occurs
python3 tools/characters/clearance.py inquisitor --anim=pull --frames  # per-frame table
python3 tools/characters/clearance.py vin --threshold=head=0.02        # other characters or thresholds
python3 tools/characters/clearance.py --cloth                          # cloth check, every skirted character
python3 tools/characters/clearance.py --cloth sazed --anim=crouch_walk --frames
python3 tools/characters/clearance.py --cloth noble_man:longcoat    # a garment mesh's skirt
python3 tools/characters/clearance.py --settle                     # robes and gowns lying down in `die`
python3 tools/characters/clearance.py --dead                       # everyone lying on the floor at the end of `die`
```
It exits with status 1 when any region falls below its threshold.

Closest gaps after art pass 16 (all clips clear):
- legs: guard `land` 4.1 cm, guard `jump` and hazekiller `land` 5.0 cm, guard `fall` 5.6 cm; sprint and crouch about 7 cm;
- skirts: hazekiller `push` 5.0 cm, guard `land` 5.1 cm, guard `attack` 5.7 cm; the Inquisitor's closest is `land` 6.9 cm. Art pass 15's fuller robes and tunics had brought these down to 1.9 cm (Inquisitor `push`), 2.1 cm (`land`), 3.1 cm (crouch) and 3.5 cm (guard `attack`, hazekiller `block`). The fixes: the Inquisitor's upper arm turns out 8° in his base carry (the haft stays upright: within 1° from the front in idle) and his weapon arm hangs 4° wider in Push and Pull; the guard's thrust wind-up holds the spear arm 6° wider; the hazekiller's block holds the staff arm 5° wider;
- head: Inquisitor `attack` 7.6 cm, guard Push and Pull 7.9 cm;
- shield: hazekiller `melee` 11 cm.

**Cloth clearance (`--cloth`).** This check covers every character whose main mesh has a skirt: the guard, hazekiller, coinshot, Inquisitor, Dockson, Breeze, Clubs (apron), Sazed, Marsh, Elend, `vin_gown`, `noble_woman`, both obligators, and the skaa man and woman. Name a garment as `<character>:<garment>` (`noble_man:tails`, `noble_man:longcoat`, `noble_woman:bustle`; all three are checked by default) to check its skirt against the legs. For each frame of every clip, it skins the legs and the skirt grids:
- **Cloth surface.** The skirt's posed cloth surface is sampled at its vertices, quad centres and boundary edge midpoints, each with an outward normal. The boundary samples (hem, waist band, the edges of an open arc) also carry a tangent pointing off the cloth.
- **Inside or outside.** A leg point is outside the cloth by its distance along the nearest sample's normal. If it is past a boundary sample's tangent, it has left the cloth below the hem or through a front slit, which leaves it uncovered rather than clipping. Where the cloth folds over itself, the closed tube's winding number decides inside from outside.
- **What must stay covered.** The leg vertices that the cloth covers in the rest pose, from 8 cm above the hem up, must stay inside it. Feet step out from under a long hem, as they would under real cloth.

A clip fails when a leg shows through by more than 1.5 cm (`CLOTH_THRESHOLD`). After art pass 15, the deepest are about 1.2 cm, on Clubs' apron in `sprint`, at the edge of Dockson's coat front in `crouch_walk` and at the hazekiller's waist band. None of them shows in the lineup. The robes and gowns all stay within 0.3 cm, through the death settle too, and the garment skirts within 0.7 cm (the bustle stays 5 cm clear; it also stays outside the gown).

**Death settle (`--settle`).** For each long robe or gown, from about 0.95 s into `die` (lying down), the hem may rise at most 32 cm off the floor (for a 1.75 m character, `SETTLE_HEM`), and no cloth may sink more than 3 cm under it (`SETTLE_FLOOR`).

**Lying dead (`--dead`).** For every character, from about 0.95 s into `die`, no part of the body may sink more than 1 cm under the floor (`DEAD_FLOOR`), and in the final pose the lowest point of each thigh, shin and foot must lie within 5 cm of it (for a 1.75 m character, `DEAD_LIFT`; not under the long robes, which `--settle` covers). The body is the main mesh without the soft or loose parts in `DEAD_SOFT`, which would flatten or push aside: props (`weapon`, `shield`, and `prop`, Ham's slung staff), skirts, tied hair tails (`hair`) and the mistcloak (its tassels and back panel). After art pass 17, the lowest body point of every character lies between -0.6 and +0.9 cm, and the legs of the characters without robes rest 0.1–4.7 cm off the floor at their lowest (Breeze's, lifted with his hips, are the highest).

**Carried weapons.** The guard, hazekiller and Inquisitor carry their weapon upright in a held (`arm_lock`) right arm. In the gaits the wrist takes back 60% of the run's forward lean and half the arm's sway (`CARRY_K` in `anim.py`), and the arm swings out a little as the knee lift grows (`CARRY_ABD`), so the shaft stays within about 20° of upright from idle to sprint (the axe within 14°) and clears the thigh. In the crouch the arm swings 6° wider; only the Inquisitor (`crouch_carry`) also stands his short axe upright there, since a long spear stood up this way drives its butt into the shin. The hazekiller's staff leant 21° in across the body in the crouch, so from the front its top crossed his face; his `crouch_hold` turns the arm and forearm out and stands the wrist up a little, and it passes 27 cm outside his face (it was 3 cm).

`tools/characters/test_clearance.py` holds 25 tests:
- the full weapon check, and the cloth check on every second frame;
- the death settle and lying dead checks;
- negative controls: a club through the torso and arm, a spear into the thigh, a hips-only robe that shows the crouching Inquisitor's knees, a hips-only noble long coat (a garment mesh), the Inquisitor's robe lying without its skirt bone poses (its back 20 cm under the floor), Vin's old raised death legs, and the guard's helmet in the floor without his `DIE_LIE`;
- a check that `ltwist` turns the thighs out;
- checks that every exported clip, every skirted character and garment, and every settling character is scanned, and that the skirt bones rest in every clip but `die`;
- geometry tests: capsule and disc distance, skirt coverage (inside, outside, below the hem, through a slit), the winding number, posed coverage (a knee raised past the guard's hem is exposed), and the shield boss.

Run it with `python3 -m unittest discover -s tools/characters -p 'test_*.py'`. It takes about 75 s, and pytest also collects it. `tools/run_tests.sh` runs it after the Godot suite when python3 has numpy, and otherwise prints a message and skips it. Run it after changing a weapon, a skirt, a style's arm pose, a gait or any one-shot.

## Licence
All meshes, rigs, animations, shaders and generator scripts are original work created for this project, with no third-party assets. They are dedicated to the public domain under **CC0 1.0**. Mistborn names and designs belong to Brandon Sanderson / Dragonsteel Entertainment. This is a non-commercial fan project.
