class_name MapView
extends Control
## Stylised top-down city map for the pause menu, drawn from
## `res://src/world/data/luthadel_plan.json` (`CityPlan`): district polygons,
## canals, the city wall and landmark icons, plus live overlays (player
## arrow, mission/activity icons, the current waypoint) supplied by
## `PauseMenu` from `LuthadelWorld`/`MissionDirector`/`ActivityManager`.
##
## Mouse: click sets a waypoint, right-click clears it, drag pans, wheel
## zooms. Gamepad: left stick pans, right stick moves a reticle, the
## push/pull triggers zoom, and "jump" (A) sets a waypoint at the reticle.
## `set_waypoint`/`clear_waypoint` are forwarded to `MissionDirector`.

signal waypoint_picked(world_pos: Vector3)
signal waypoint_cleared

const MIN_ZOOM := 1.0
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.25
const PAN_SPEED := 500.0   ## world units/sec at zoom 1
const RETICLE_SPEED := 260.0 ## world units/sec at zoom 1
const CLICK_DRAG_THRESHOLD := 6.0

const DISTRICT_COLORS := {
	&"skaa_slums": Color(0.16, 0.15, 0.14, 0.9),
	&"merchant": Color(0.20, 0.17, 0.12, 0.9),
	&"noble": Color(0.14, 0.13, 0.20, 0.9),
	&"market": Color(0.22, 0.18, 0.10, 0.9),
	&"docks": Color(0.12, 0.17, 0.19, 0.9),
	&"kredik_shaw": Color(0.05, 0.05, 0.07, 0.95),
	&"outside": Color(0.05, 0.05, 0.06, 0.6),
}
const CANAL_COLOR := Color(0.20, 0.35, 0.45, 0.75)
const WALL_COLOR := Color(0.55, 0.45, 0.25, 0.95)
const LANDMARK_COLOR := Color(0.85, 0.72, 0.35)
const ACTIVITY_COLORS := {
	&"coin_race": Color(0.95, 0.85, 0.4),
	&"rooftop_pursuit": Color(0.85, 0.4, 0.35),
	&"obligator_ambush": Color(0.6, 0.75, 0.95),
}

## World-space bounds the map represents (X/Z plane). Falls back to a small
## default rect if the city plan can't be loaded (e.g. in a minimal test).
var world_bounds := Rect2(-400, -400, 800, 800)
var plan: CityPlan

var mission_icons: Array[Dictionary] = []   # {position: Vector3, label: String}
## {position: Vector3, label: String, kind: StringName, completed: bool}
var activity_icons: Array[Dictionary] = []
var player_world_position: Vector3 = Vector3.ZERO
var player_forward: Vector2 = Vector2.UP
var waypoint: Vector3 = Vector3.INF

var _zoom := 1.0
var _pan := Vector2.ZERO   ## offset from world_bounds center, world units
var _reticle := Vector2.ZERO  ## world-space, gamepad cursor for waypoint picking
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_moved := false


func _ready() -> void:
	plan = CityPlan.load_from_file()
	if plan != null:
		world_bounds = plan.bounds
	_reticle = world_bounds.get_center()
	set_process(true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var pan_in := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pan_in != Vector2.ZERO:
		_pan += pan_in * (PAN_SPEED / _zoom) * delta
		_clamp_pan()
		queue_redraw()
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_reticle += look * (RETICLE_SPEED / _zoom) * delta
		queue_redraw()
	var zoom_in := Input.get_action_strength("push")
	var zoom_out := Input.get_action_strength("pull")
	if zoom_in > 0.05 or zoom_out > 0.05:
		_apply_zoom_delta((zoom_in - zoom_out) * delta * 2.0)
	if Input.is_action_just_pressed("jump"):
		waypoint_picked.emit(Vector3(_reticle.x, 0.0, _reticle.y))


# --- Projection (pure; covered by tests) -------------------------------------

## The world-space rectangle currently shown, given `bounds`/`zoom`/`pan`.
static func compute_view_rect(bounds: Rect2, zoom: float, pan: Vector2) -> Rect2:
	var z := maxf(zoom, 0.0001)
	var sz := bounds.size / z
	var center := bounds.get_center() + pan
	return Rect2(center - sz * 0.5, sz)


func _view_rect() -> Rect2:
	return compute_view_rect(world_bounds, _zoom, _pan)


func _world_to_screen(p: Vector3) -> Vector2:
	return world_to_screen_rect(Vector2(p.x, p.z), _view_rect(), size)


func _screen_to_world(p: Vector2) -> Vector3:
	var w := screen_to_world_rect(p, _view_rect(), size)
	return Vector3(w.x, 0.0, w.y)


static func world_to_screen_rect(p: Vector2, view: Rect2, screen_size: Vector2) -> Vector2:
	var t := Vector2((p.x - view.position.x) / maxf(view.size.x, 0.0001), (p.y - view.position.y) / maxf(view.size.y, 0.0001))
	return t * screen_size


static func screen_to_world_rect(p: Vector2, view: Rect2, screen_size: Vector2) -> Vector2:
	var t := Vector2(p.x / maxf(screen_size.x, 0.0001), p.y / maxf(screen_size.y, 0.0001))
	return view.position + t * view.size


func _clamp_pan() -> void:
	var half := world_bounds.size * 0.5 * (1.0 - 1.0 / _zoom)
	_pan.x = clampf(_pan.x, -half.x, half.x)
	_pan.y = clampf(_pan.y, -half.y, half.y)


func _apply_zoom_delta(d: float) -> void:
	_zoom = clampf(_zoom * pow(ZOOM_STEP, d), MIN_ZOOM, MAX_ZOOM)
	_clamp_pan()
	queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06, 1.0))
	if plan != null:
		_draw_plan()
	else:
		_draw_fallback()
	for icon: Dictionary in activity_icons:
		var p := _world_to_screen(icon.get("position", Vector3.ZERO))
		var color: Color = ACTIVITY_COLORS.get(icon.get("kind", &""), Color(0.8, 0.8, 0.8))
		if icon.get("completed", false):
			color = color.darkened(0.4)
		draw_circle(p, 5.0, color)
		draw_arc(p, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.0)
	for icon: Dictionary in mission_icons:
		var p := _world_to_screen(icon.get("position", Vector3.ZERO))
		draw_circle(p, 7.0, Color(0.85, 0.7, 0.3))
		draw_string(get_theme_default_font(), p + Vector2(10, 4), icon.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.85, 0.7))
	if waypoint != Vector3.INF:
		var wp := _world_to_screen(waypoint)
		draw_arc(wp, 10.0, 0.0, TAU, 20, Color(0.3, 0.9, 0.5), 2.0)
	if _has_gamepad():
		var rp := _world_to_screen(Vector3(_reticle.x, 0.0, _reticle.y))
		draw_arc(rp, 6.0, 0.0, TAU, 12, Color(1, 1, 1, 0.6), 1.5)

	var pp := _world_to_screen(player_world_position)
	var fwd := player_forward.normalized() * 12.0
	var left := fwd.rotated(deg_to_rad(150))
	var right := fwd.rotated(deg_to_rad(-150))
	draw_polygon(PackedVector2Array([pp + fwd, pp + left, pp + right]), PackedColorArray([Color(0.3, 0.75, 1.0)]))


func _has_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _draw_plan() -> void:
	var view := _view_rect()
	for d: Dictionary in plan.districts:
		var poly: PackedVector2Array = d["polygon"]
		if poly.is_empty():
			continue
		var screen_poly := PackedVector2Array()
		for v in poly:
			screen_poly.append(world_to_screen_rect(v, view, size))
		var color: Color = DISTRICT_COLORS.get(d["type"], Color(0.15, 0.14, 0.13, 0.9))
		draw_colored_polygon(screen_poly, color)
	for canal in plan.canals:
		var r := canal.rect
		var a := world_to_screen_rect(r.position, view, size)
		var b := world_to_screen_rect(r.end, view, size)
		draw_rect(Rect2(a, b - a), CANAL_COLOR)
	if plan.wall_points.size() >= 2:
		var wall_screen := PackedVector2Array()
		for v in plan.wall_points:
			wall_screen.append(world_to_screen_rect(v, view, size))
		wall_screen.append(wall_screen[0])
		draw_polyline(wall_screen, WALL_COLOR, 2.0)
	for lm in plan.landmarks:
		var p := world_to_screen_rect(lm.center, view, size)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), LANDMARK_COLOR)
		draw_string(get_theme_default_font(), p + Vector2(7, -6), lm.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.68, 0.5))


func _draw_fallback() -> void:
	var view := _view_rect()
	var r := Rect2(world_to_screen_rect(world_bounds.position, view, size), Vector2.ZERO)
	r = r.expand(world_to_screen_rect(world_bounds.end, view, size))
	draw_rect(r, Color(0.12, 0.11, 0.10, 0.9), false, 2.0)


# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom_delta(1.0)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom_delta(-1.0)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
				_drag_moved = false
			else:
				_dragging = false
				if not _drag_moved:
					waypoint_picked.emit(_screen_to_world(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			waypoint_cleared.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start) > CLICK_DRAG_THRESHOLD:
			_drag_moved = true
		var view := _view_rect()
		_pan -= mm.relative * (view.size / size)
		_clamp_pan()
		queue_redraw()
		accept_event()


func set_waypoint(pos: Vector3) -> void:
	waypoint = pos
	queue_redraw()


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	queue_redraw()


func refresh() -> void:
	queue_redraw()
