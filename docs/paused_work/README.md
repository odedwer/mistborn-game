# Paused work

Development was paused on 2026-09-26. One agent was stopped partway through a task. Its unfinished changes are saved here as patches, so nothing is lost when the build container is deleted. The patches aren't applied, and they aren't part of the game.

## Resuming
```bash
git apply docs/paused_work/<name>.patch   # then run tools/run_tests.sh
```
After applying a patch, check the result visually with `tools/screenshot.gd` or `tools/screenshot_interior.gd` (see `docs/ARCHITECTURE.md`), then delete the patch.
