extends TestCase
## MapView: pure projection math (view rect / world<->screen) and waypoint
## state, without needing to actually render.

var _map: MapView


func before_each() -> void:
	_map = MapView.new()
	_map.size = Vector2(800, 600)
	add_child(_map)


func after_each() -> void:
	_map.queue_free()


func test_loads_city_plan_bounds() -> void:
	assert_true(_map.plan != null, "city plan loaded")
	assert_eq(_map.world_bounds, _map.plan.bounds)


func test_view_rect_at_zoom_one_is_full_bounds() -> void:
	var bounds := Rect2(-100, -100, 200, 200)
	var view := MapView.compute_view_rect(bounds, 1.0, Vector2.ZERO)
	assert_eq(view, bounds)


func test_view_rect_shrinks_with_zoom() -> void:
	var bounds := Rect2(-100, -100, 200, 200)
	var view := MapView.compute_view_rect(bounds, 2.0, Vector2.ZERO)
	assert_almost(view.size.x, 100.0)
	assert_almost(view.size.y, 100.0)
	assert_almost(view.get_center().x, bounds.get_center().x)


func test_view_rect_pans() -> void:
	var bounds := Rect2(-100, -100, 200, 200)
	var view := MapView.compute_view_rect(bounds, 1.0, Vector2(30, -10))
	assert_almost(view.position.x, -70.0)
	assert_almost(view.position.y, -110.0)


func test_world_to_screen_and_back_round_trips() -> void:
	var view := Rect2(-200, -150, 400, 300)
	var screen_size := Vector2(800, 600)
	var world_p := Vector2(37.5, -62.0)
	var screen_p := MapView.world_to_screen_rect(world_p, view, screen_size)
	var back := MapView.screen_to_world_rect(screen_p, view, screen_size)
	assert_almost(back.x, world_p.x, 0.01)
	assert_almost(back.y, world_p.y, 0.01)


func test_world_to_screen_corners() -> void:
	var view := Rect2(-100, -100, 200, 200)
	var screen_size := Vector2(800, 600)
	assert_eq(MapView.world_to_screen_rect(Vector2(-100, -100), view, screen_size), Vector2.ZERO)
	assert_eq(MapView.world_to_screen_rect(Vector2(100, 100), view, screen_size), screen_size)


func test_zoom_clamps_to_min_and_max() -> void:
	_map._zoom = 1.0
	_map._apply_zoom_delta(-10.0)
	assert_eq(_map._zoom, MapView.MIN_ZOOM)
	_map._apply_zoom_delta(10.0)
	assert_eq(_map._zoom, MapView.MAX_ZOOM)


func test_pan_is_clamped_within_bounds() -> void:
	_map.world_bounds = Rect2(-100, -100, 200, 200)
	_map._zoom = 2.0
	_map._pan = Vector2(10000, 10000)
	_map._clamp_pan()
	# At zoom 2, half*(1 - 1/zoom) = 100*0.5 = 50: the furthest the view
	# centre can move from the world centre before showing empty space.
	assert_almost(_map._pan.x, 50.0)
	assert_almost(_map._pan.y, 50.0)


func test_set_and_clear_waypoint() -> void:
	assert_eq(_map.waypoint, Vector3.INF)
	_map.set_waypoint(Vector3(1, 0, 2))
	assert_eq(_map.waypoint, Vector3(1, 0, 2))
	_map.clear_waypoint()
	assert_eq(_map.waypoint, Vector3.INF)


func test_click_without_drag_emits_waypoint_picked() -> void:
	var got := [Vector3.INF]
	_map.waypoint_picked.connect(func(p): got[0] = p)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(400, 300)
	_map._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(400, 300)
	_map._gui_input(up)
	assert_true(got[0] != Vector3.INF, "waypoint set on plain click")


func test_drag_pans_instead_of_setting_waypoint() -> void:
	var got := [false]
	_map.waypoint_picked.connect(func(_p): got[0] = true)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(400, 300)
	_map._gui_input(down)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(500, 300)
	move.relative = Vector2(100, 0)
	_map._gui_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(500, 300)
	_map._gui_input(up)
	assert_false(got[0], "a drag must not also set a waypoint")


func test_right_click_clears_waypoint() -> void:
	var got := [false]
	_map.waypoint_cleared.connect(func(): got[0] = true)
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	_map._gui_input(rc)
	assert_true(got[0])
