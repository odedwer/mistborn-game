extends TestCase
## HUD reacts to Events without needing a real player/world.

var _hud: CanvasLayer


func before_each() -> void:
	var scene: PackedScene = load("res://src/ui/hud.tscn")
	_hud = scene.instantiate()
	add_child(_hud)


func after_each() -> void:
	_hud.queue_free()


func test_reserve_change_updates_vial_bar() -> void:
	var fake_allomancer := Node.new()
	add_child(fake_allomancer)
	Events.metal_reserve_changed.emit(fake_allomancer, Metal.Type.PEWTER, 42.0)
	var bar: ProgressBar = _hud._vials[Metal.Type.PEWTER]
	assert_almost(bar.value, 42.0)
	fake_allomancer.queue_free()


func test_health_change_updates_bar() -> void:
	Events.player_health_changed.emit(30.0, 100.0)
	assert_almost(_hud._health_bar.value, 30.0)
	assert_almost(_hud._health_bar.max_value, 100.0)


func test_alert_level_sets_label_text() -> void:
	Events.alert_level_changed.emit(2)
	assert_true(_hud._alert_label.text.length() > 0)
	Events.alert_level_changed.emit(0)
	assert_eq(_hud._alert_label.text, "")


func test_hint_requested_shows_hint_box() -> void:
	GameSettings.hints_enabled = true
	Events.hint_requested.emit("Test hint", 3.0)
	assert_true(_hud._hint_box.visible)
	assert_eq(_hud._hint_label.text, "Test hint")


func test_objective_updated_sets_tracker_text() -> void:
	Events.objective_updated.emit(&"test_obj", "Do the thing", false)
	assert_eq(_hud._objective_label.text, "Do the thing")
