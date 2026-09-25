# Mistborn: Ashes of Luthadel

> **Fan Game Disclaimer:** This is a non-commercial fan game set in Brandon Sanderson's Mistborn universe. Mistborn © Brandon Sanderson / Dragonsteel Entertainment. This game is not affiliated with or endorsed by Dragonsteel Entertainment.

A 3D action game exploring the allomantic magic system from the Mistborn series, featuring physics-based Push/Pull mechanics and procedurally generated environments.

## Features

- **Engine:** Godot 4.7.2 with Vulkan/OpenGL
- **Physics:** Jolt Physics 3D with physics-based allomancy
- **Gameplay:** Push/Pull mechanics, allomantic metals, procedural Luthadel city
- **Graphics:** Forward+ rendering with volumetric fog, dynamic shadows, LOD
- **Audio:** Spatial 3D audio with pooled effects and adaptive music intensity
- **Input:** Full keyboard/mouse and gamepad support

## System Requirements

### Minimum
- **GPU:** GTX 1050 / RX 560 / Intel Iris Xe (Vulkan 1.1+)
- **RAM:** 8 GB
- **OS:** Windows 10+ or Linux (Ubuntu 18.04+)
- **CPU:** 4-core modern processor

### Recommended
- **GPU:** RTX 2070 / RX 5700
- **RAM:** 16 GB
- **SSD:** 2 GB free space

## Controls

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| **Movement** | | |
| Move Forward | W | Left Stick ↑ |
| Move Backward | S | Left Stick ↓ |
| Move Left | A | Left Stick ← |
| Move Right | D | Left Stick → |
| Sprint | Shift | Left Stick Click |
| Jump | Space | A Button |
| Crouch | Ctrl | B Button |
| **Allomancy** | | |
| Push | LMB | Right Trigger |
| Pull | RMB | Left Trigger |
| Flare (×10 effect) | Alt | Right Stick Click |
| Metal Wheel | Tab | Left Shoulder |
| Throw Coins | Q | Right Shoulder |
| Drop Coin | G | Dpad Down |
| **Metal Selection** | | |
| Steel | 1 | |
| Iron | 2 | |
| Pewter | 3 | Dpad Left |
| Tin | 4 | Dpad Right |
| Bronze | 5 | |
| Copper | 6 | |
| Zinc | 7 | |
| Brass | 8 | |
| Atium | 9 | |
| Duralumin Pulse | 0 | |
| Burn All (Basic) | B | |
| **Combat** | | |
| Melee | F, Mouse 4 | Y Button |
| Drink Vial | R | Dpad Up |
| Interact | E | X Button |
| **Utility** | | |
| Pause | Esc | Start |
| Quick Save | F5 | |
| Quick Load | F9 | |
| Toggle Debug | F3 | |
| Cycle Target | Scroll Up/Down | |

## Getting Started

### From Source

1. **Install Godot 4.7.2**
   - Download from [godotengine.org](https://godotengine.org/download/archive/4.7.2-stable/)
   - Extract and add to PATH

2. **Clone and Open**
   ```bash
   git clone https://github.com/yourusername/mistborn-game.git
   cd mistborn-game
   godot
   ```

3. **First Run**
   - Godot will import the project (first launch takes a minute)
   - Press Play or F5 in the editor

### Build & Export

**Linux/macOS:**
```bash
./tools/build.sh
```

**Windows (PowerShell):**
```powershell
.\tools\build.ps1
```

**Options:**
- `--clean`: Remove build directory before building
- Set `GODOT` env var to use a custom Godot path

**Output:** Distribution zips in `build/dist/`

### Running Tests

```bash
bash tools/run_tests.sh
```

Tests are GDScript headless tests in `tests/test_*.gd`, extending `res://tests/test_case.gd`.

## Project Layout

| Path | Purpose |
|------|---------|
| `src/` | Game code (allomancy, player, combat, enemies, world, UI) |
| `scenes/` | Top-level scenes (main_menu, game, test scenes) |
| `assets/` | Generated textures, audio, models, shaders |
| `tests/` | Headless test suite |
| `tools/` | Build scripts and asset generators |
| `docs/` | Architecture and design docs |

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for:
- Core physics contracts (Push/Pull, allomantic forces)
- Component architecture (Metallic, Allomancer, Health)
- Performance rules and optimization
- Physics layers and collision setup

## Development

### Code Style
- Statically typed GDScript (`var x: float`)
- Cached node references (no `get_node` in hot loops)
- Manager-based systems (not per-object scripts for frequent updates)
- Use `Events` signal bus instead of cross-references

### Key Scripts
- `src/autoload/input_setup.gd` — All input actions and key bindings
- `src/autoload/events.gd` — Global signal bus
- `src/allomancy/allomancer.gd` — Metal burning, Push/Pull
- `src/combat/health.gd` — Damage system
- `src/world/luthadel.gd` — Procedural world generation

### Benchmarks
- **Target:** 60 FPS at 1080p on GTX 1060 (High preset)
- **Low preset:** Runs on integrated GPUs
- Coins capped at 256 (recycled per frame)
- Single directional light with 3-4 cascades

## License

**Code:** MIT License (see [LICENSE](LICENSE))
**Assets:** Copyright notice in [LICENSE-ASSETS.md](LICENSE-ASSETS.md) — all assets are original or CC0

## Contributing

This is a fan project. Contributions are welcome for bug fixes, optimization, and features that respect the original design. See ARCHITECTURE.md for structure guidelines.

## Credits

- Engine: [Godot 4.7.2](https://godotengine.org)
- Physics: [Jolt Physics](https://github.com/jrouwe/JoltPhysics)
- Mistborn world/setting: Brandon Sanderson / Dragonsteel Entertainment
