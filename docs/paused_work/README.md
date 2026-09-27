# Paused work

Development was paused on 2026-09-26. Two agents were stopped partway through a task. Their unfinished changes are saved here as patches, so nothing is lost when the build container is deleted. The patches aren't applied, and they aren't part of the game.

## `qa_perf_wip.patch` (QA / performance)
- Adds a draft `docs/PERFORMANCE.md` with CPU frame-time measurements.
- Adds extra MetalRegistry tests.
- Tweaks `tests/perf_probe.gd` and `tools/soak.gd`.

Already merged from this task:
- The end-to-end mission test.
- The story sweep over all 17 missions and the post-game.
- The fix for guards rendering as white orbs (NaN pixels in the character shading).
- The faster 2D spatial hash in MetalRegistry.

Still to do:
- Finish and verify PERFORMANCE.md.
- The remaining items from the QA brief: traversal validation, the soak run, the freed-object error in SceneTransition, and saving the interior vs. open-world position.

## `art_polish_pass2_wip.patch` (art polish, pass 2)
This is the unfinished second pass on the review items in `docs/POLISH_BACKLOG.md` ("Review of polish pass 1"):
- A reworked stained-glass shader.
- Ballroom lighting that's less overexposed.
- Library windows that use the stained-glass shader.

It hasn't been screenshot-verified yet. The main-menu skyline rework hadn't started.

## Resuming
```bash
git apply docs/paused_work/<name>.patch   # then run tools/run_tests.sh
```
After applying a patch, check the result visually with `tools/screenshot.gd` or `tools/screenshot_interior.gd` (see `docs/ARCHITECTURE.md`), then delete the patch.
