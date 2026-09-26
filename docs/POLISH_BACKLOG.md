# Polish backlog

These are visual and feel issues found by reviewing screenshots. They're queued for the Polish roadmap phase. Each entry says where it was seen.

## Art
- **Brick and cobblestone textures** (`tools/gen_textures.py`). The brick is too clean and saturated for ash-covered Luthadel; add soot, grime and desaturation. The cobblestone reads as cracked flagstone, not rounded cobbles.
- **Keep Venture ballroom** (`src/mission/interiors/keep_venture_ballroom*`).
  - The stained glass is flat solid-colour quads. It needs leaded patterns, emissive gradients and coloured light shafts on the floor.
  - The hall is too dark and the nobles are barely lit; add chandelier lights and warm fill.
  - The tables read as plain grey cylinders.
- **Character faces** (`tools/characters/`). The shared head builder gives simple faces; add more facial structure and hair variety.
- **Elend's books** clip into his coat.
- **Pickups**. They're still a plain white/pale cylinder up close; give them a proper vial/coin-pouch mesh.

## Feel
- **Race rings and pursuit paths** are authored as offsets from their start marker, and some may clip buildings. Validate them against the geometry.
- **Activity nodes** (rings, beacons) are parented to the root instead of their streamed chunk. That's fine for the slice district, but they need to stream at full-city scale.

## Engine
- **Freed-object error during tests**. The suite prints one "Trying to cast a freed object" error from `scene_transition.gd` during the SceneTransition tests.
