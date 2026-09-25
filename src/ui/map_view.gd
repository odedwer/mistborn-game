class_name MapView
extends Control
## Stylised top-down city map for the pause menu.
##
## Godot draws it, rather than a background image, from a simple hardcoded
## district layout: good enough for the vertical slice. When
## `LuthadelWorld.get_marker_data()` (or a `world_bounds`/`district_plan`
## export) is available, swap `_districts`/`_bounds` for real data — the
## drawing code doesn't otherwise need to change.
##
## Left-click sets a waypoint (forwarded to `MissionDirector.set_waypoint`);
## right-click clears it.

signal waypoint_picked(world_pos: Vector3)
signal waypoint_cleared

## World-space bounds the map represents (X/Z plane). Replace with the real
## world's bounds once `LuthadelWorld` exposes them.
var world_bounds := Rect2(-400, -400, 800, 800)

## Simple placeholder district shapes: name -> Rect2 in world space.
var _districts := {
	"Skaa Quarter": Rect2(-380, -380, 320, 300),
	"Luthadel Canal District": Rect2(-380, -40, 760, 120),
	"Keep District": Rect2(80, -380, 300, 280),
	"Outer Slums": Rect2(-380, 120, 760, 260),
}

var mission_icons: Array[Dictionary] = []  # {position: Vector3, label: String}
var player_world_position: Vector3 = Vector3.ZERO
var player_forward: Vector2 = Vector2.UP


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06, 1.0))
	for district_name in _districts:
		var r: Rect2 = _districts[district_name]
		var screen_rect := _world_rect_to_screen(r)
		draw_rect(screen_rect, Color(0.14, 0.13, 0.12, 1.0))
		draw_rect(screen_rect, Color(0.35, 0.28, 0.16, 0.8), false, 2.0)
		draw_string(get_theme_default_font(), screen_rect.position + Vector2(6, 16), district_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.55, 0.45))

	for icon: Dictionary in mission_icons:
		var p := _world_to_screen(icon.get("position", Vector3.ZERO))
		draw_circle(p, 7.0, Color(0.85, 0.7, 0.3))
		draw_string(get_theme_default_font(), p + Vector2(10, 4), icon.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.85, 0.7))

	var pp := _world_to_screen(player_world_position)
	var fwd := player_forward.normalized() * 12.0
	var left := fwd.rotated(deg_to_rad(150))
	var right := fwd.rotated(deg_to_rad(-150))
	draw_polygon(PackedVector2Array([pp + fwd, pp + left, pp + right]), PackedColorArray([Color(0.3, 0.75, 1.0)]))


func _world_to_screen(p: Vector3) -> Vector2:
	var t := Vector2((p.x - world_bounds.position.x) / world_bounds.size.x, (p.z - world_bounds.position.y) / world_bounds.size.y)
	return t * size


func _world_rect_to_screen(r: Rect2) -> Rect2:
	var a := _world_to_screen(Vector3(r.position.x, 0, r.position.y))
	var b := _world_to_screen(Vector3(r.position.x + r.size.x, 0, r.position.y + r.size.y))
	return Rect2(a, b - a)


func _screen_to_world(p: Vector2) -> Vector3:
	var t := p / size
	return Vector3(world_bounds.position.x + t.x * world_bounds.size.x, 0.0, world_bounds.position.y + t.y * world_bounds.size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			waypoint_picked.emit(_screen_to_world(event.position))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			waypoint_cleared.emit()
			accept_event()


func refresh() -> void:
	queue_redraw()
