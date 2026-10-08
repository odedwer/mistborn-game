extends SceneTree
## Records a short gameplay clip: the full game (HUD, camera, mist) in the
## "Mistwalk to Keep Venture" mission, with the player steel-jumping the
## rooftop route under the traversal autopilot from tests/test_traversal.gd.
## Use Godot's Movie Maker (needs a display; use xvfb-run):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /path/out.avi \
##     -s res://tools/record_gameplay.gd -- [--time=<hour>] [--legs=<n>]
##
## Movie Maker renders every frame at a fixed step, so the clip plays at real
## speed however slowly the machine renders it. Quits after the last leg.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bot: Node = (load("res://tools/record_gameplay_bot.gd") as GDScript).new()
	bot.name = "RecordBot"
	root.add_child(bot)
