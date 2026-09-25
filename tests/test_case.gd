class_name TestCase
extends Node
## Base class for headless tests. Methods named `test_*` are run in order.
## Tests may be async (use `await`). Tests run inside the SceneTree root, so
## they can add nodes; everything added under `self` is freed afterwards.

var _failures: Array[String] = []
var _current := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		_fail("expected true. " + msg)


func assert_false(cond: bool, msg := "") -> void:
	if cond:
		_fail("expected false. " + msg)


func assert_eq(a: Variant, b: Variant, msg := "") -> void:
	if a != b:
		_fail("expected %s == %s. %s" % [str(a), str(b), msg])


func assert_almost(a: float, b: float, eps := 0.001, msg := "") -> void:
	if absf(a - b) > eps:
		_fail("expected %f ~= %f (eps %f). %s" % [a, b, eps, msg])


func assert_gt(a: float, b: float, msg := "") -> void:
	if not a > b:
		_fail("expected %f > %f. %s" % [a, b, msg])


func assert_lt(a: float, b: float, msg := "") -> void:
	if not a < b:
		_fail("expected %f < %f. %s" % [a, b, msg])


## Advances the physics simulation by `frames` physics ticks.
func physics_frames(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])
