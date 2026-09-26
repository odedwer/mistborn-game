extends TestCase
## The HUD's off-screen objective marker must point where the objective is
## relative to the camera's view, not along world axes.

var _hud: CanvasLayer
var _cam: Camera3D
var _director: Node
var _root: Node3D


class FakeDirector:
	extends Node
	var target := Vector3.INF

	func current_marker_position() -> Vector3:
		return target


func before_each() -> void:
	_root = Node3D.new()
	add_child(_root)
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.current = true
	_director = FakeDirector.new()
	_director.add_to_group("mission_director")
	add_child(_director)
	_hud = (load("res://src/ui/hud.tscn") as PackedScene).instantiate()
	add_child(_hud)


func after_each() -> void:
	_hud.queue_free()
	_director.queue_free()
	_root.queue_free()


func _marker_center() -> Vector2:
	_hud._update_objective_marker()
	var m: Control = _hud._objective_marker
	return m.position + m.custom_minimum_size * 0.5


func test_offscreen_marker_is_camera_relative() -> void:
	# Camera looking east (+X). North (-Z) is to its left, south to its right.
	_cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3.ZERO)
	await get_tree().process_frame
	var center := _hud.get_viewport().get_visible_rect().size * 0.5
	(_director as FakeDirector).target = Vector3(0, 0, -100)
	var p := _marker_center()
	assert_true(_hud._objective_marker.visible, "marker shown")
	assert_lt(p.x, center.x - 1.0, "objective to the camera's left -> marker on the left edge (%s)" % p)
	(_director as FakeDirector).target = Vector3(0, 0, 100)
	p = _marker_center()
	assert_gt(p.x, center.x + 1.0, "objective to the camera's right -> marker on the right edge (%s)" % p)
	# Straight behind: bottom of the screen.
	(_director as FakeDirector).target = Vector3(-100, 0, 0)
	p = _marker_center()
	assert_gt(p.y, center.y, "objective behind -> marker in the bottom half (%s)" % p)
	# Above and ahead but outside the view: top edge.
	(_director as FakeDirector).target = Vector3(10, 200, 0)
	p = _marker_center()
	assert_lt(p.y, center.y, "objective high above -> marker at the top (%s)" % p)
