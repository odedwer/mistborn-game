# Characters

There are six procedurally generated characters: `vin` (player), `guard`, `hazekiller`, `thug`, `coinshot` and `inquisitor`. Each is a Godot scene at `res://assets/models/characters/<id>.tscn`. The root is a `Node3D` with `character_model.gd` (`class_name CharacterModel`), and its `Model` child is the imported `<id>.glb`.

| id | height | tris | materials | notes |
|---|---|---|---|---|
| vin | 1.66 m | ~4.0k | Cloth, Cloak, Obsidian | mistcloak with 16 spring-simulated tassels; obsidian dagger in the right hand, a second one sheathed at the back |
| guard | 1.80 m | ~4.3k | Cloth, Metal, Glow | steel cuirass, pauldrons, kettle helmet; spear; lantern in the left hand (it adds an unshadowed OmniLight) |
| hazekiller | 1.79 m | ~3.7k | Cloth | leather and wooden armour, hood and mask, round wooden shield, staff (no metal) |
| thug | 2.11 m | ~3.4k | Cloth | huge build, bare arms, open vest, wooden club |
| coinshot | 1.81 m | ~4.2k | Cloth, Cloak, Metal | dark long coat and a shorter mistcloak variant (11 tassels) |
| inquisitor | 1.99 m | ~3.5k | Cloth, Metal, Obsidian | tall and gaunt; grey robes with red and black accents; spikes through both eyes (points jut out of the back of the skull); a spike between the shoulder blades that pokes out of the chest; obsidian axe |

## Conventions
- **Facing:** the `CharacterModel` root faces **+Z**, which matches `player.gd` and `enemy_base.gd` (`yaw = atan2(dir.x, dir.z)`), so `model_yaw_offset_deg = 0`. Inside, the glTF faces -Z and the `Model` child is rotated 180°.
- **Feet** are at the origin. Everything is in metres. Animations are in place, with no root motion.
- **Skeleton:** there is one `Skeleton3D` per character. It uses the Godot humanoid bone names: `Root, Hips, Spine, Chest, UpperChest, Neck, Head, Left/Right{Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes}`, so it can be retargeted. Cloak characters add `Tassel_NN_k` chains under `Chest`.
- **Materials** are shared `ShaderMaterial`s in `assets/models/characters/materials/`: cloth, cloak (double-sided), metal, obsidian and glow. They are mapped at import time through `_subresources` in the `.glb.import` files. Albedo comes from vertex colours (stored as sRGB). Surface detail (weave/grain/grime) is procedural in UV space, where UVs are in metres. A rim term keeps silhouettes readable at night.
- **LOD:** `meshes/generate_lods=true` is set on import (automatic mesh LODs), plus shadow meshes.

## API (`CharacterModel`)
```gdscript
set_locomotion(speed: float, grounded: bool, vertical_speed := 0.0)
set_crouching(on: bool)
play_action(name: StringName) -> bool
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
- **`play_action`** takes `jump, land, throw, melee, attack, hit, die, block, alert, push, pull, drink`:
  - `throw, melee, push, pull, drink` are upper-body one-shots (spine, arms and head filter), so they layer over running.
  - The others are full-body one-shots.
  - `die` moves to the `dead` state and holds the final pose until `revive()`. While dead, other actions return `false`. Unknown names also return `false`.
  - `attack` is character-specific: a dagger slash (vin), a spear thrust (guard), an overhead staff strike (hazekiller), a club smash (thug), a coin throw (coinshot) and a diagonal axe chop (inquisitor).
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
- `chars.py`: the six designs and their props.
- `anim.py`: semantic pose parameters, 2-bone leg IK, gaits and one-shot keyframes. It also holds the per-character styles (spear arm, lantern arm, hunch, and so on).
- `build_characters.py`: builds the Blender armature, mesh and actions, then exports the GLB. Looping clips are named `-loop`, which makes the importer set the loop flag.
- `godot_files.py`: writes the materials, `.tscn` and `.import` files.

Preview with `godot res://scenes/test/character_lineup.tscn -- <options>`. The options are documented at the top of `character_lineup.gd`, for example `--only=vin --anim=run --t=0.2 --cam=side --light=studio --shot=out.png`, or `--moving` for cloak dynamics.

Tests are in `tests/test_characters.gd`.

## Licence
All meshes, rigs, animations, shaders and generator scripts are original work created for this project, with no third-party assets. They are dedicated to the public domain under **CC0 1.0**. Mistborn names and designs belong to Brandon Sanderson / Dragonsteel Entertainment. This is a non-commercial fan project.
