extends TestCase
## HUD reacts to Events without needing a real player/world.

var _hud: CanvasLayer


func before_each() -> void:
	var scene: PackedScene = load("res://src/ui/hud.tscn")
	_hud = scene.instantiate()
	add_child(_hud)


func after_each() -> void:
	_hud.queue_free()


func _make_fake_player() -> Node:
	var player := Node3D.new()
	player.set_script(load("res://tests/fake_player.gd"))
	player.add_to_group("player")
	add_child(player)
	return player


## `process_frame` fires before nodes' _process, so wait two frames for the
## HUD to have run once with the player present.
func _let_hud_find_player() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_reserve_change_updates_vial_bar() -> void:
	var player := _make_fake_player()
	await _let_hud_find_player()
	Events.metal_reserve_changed.emit(player.allomancer, Metal.Type.PEWTER, 42.0)
	var bar: ProgressBar = _hud._vials[Metal.Type.PEWTER]
	assert_almost(bar.value, 42.0)
	player.queue_free()


func test_hud_syncs_initial_reserves_from_player() -> void:
	var player := _make_fake_player()
	await _let_hud_find_player()
	var bar: ProgressBar = _hud._vials[Metal.Type.STEEL]
	assert_almost(bar.value, 100.0, 0.001, "full reserves shown before any change event")
	player.queue_free()


func test_enemy_reserve_change_ignored() -> void:
	var player := _make_fake_player()
	await _let_hud_find_player()
	var enemy_allomancer := Node.new()
	add_child(enemy_allomancer)
	Events.metal_reserve_changed.emit(enemy_allomancer, Metal.Type.STEEL, 5.0)
	var bar: ProgressBar = _hud._vials[Metal.Type.STEEL]
	assert_almost(bar.value, 100.0, 0.001, "enemy metal use must not move the player's bars")
	player.queue_free()
	enemy_allomancer.queue_free()


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


# --- Settings menu: Accessibility tab, keyboard/gamepad navigation ------------

func test_settings_menu_has_accessibility_tab() -> void:
	var menu: CanvasLayer = load("res://src/ui/settings_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var found := false
	for i in menu._tabs.get_tab_count():
		if menu._tabs.get_tab_title(i) == "Accessibility":
			found = true
	assert_true(found, "Settings has an Accessibility tab")
	menu.queue_free()


func test_settings_menu_ui_cancel_closes_it() -> void:
	var menu: CanvasLayer = load("res://src/ui/settings_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	menu._unhandled_input(InputEventAction.new())  # not ui_cancel: no-op
	assert_false(closed[0])
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	menu._unhandled_input(ev)
	assert_true(closed[0], "ui_cancel (Esc/gamepad B) always closes Settings")
	menu.queue_free()


func test_settings_menu_lb_rb_cycle_tabs() -> void:
	var menu: CanvasLayer = load("res://src/ui/settings_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._tabs.current_tab = 0
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	ev.pressed = true
	menu._unhandled_input(ev)
	assert_eq(menu._tabs.current_tab, 1)
	menu.queue_free()


func test_settings_menu_close_button_has_focus_mode() -> void:
	var menu: CanvasLayer = load("res://src/ui/settings_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	assert_eq(menu._close_btn.focus_mode, Control.FOCUS_ALL, "back/close is reachable by keyboard and gamepad")
	menu.queue_free()


# --- Pause menu: Controls tab lists live bindings ----------------------------

func test_pause_menu_controls_tab_lists_bindings() -> void:
	var menu: CanvasLayer = load("res://src/ui/pause_menu.tscn").instantiate()
	add_child(menu)
	menu.set_paused(true)
	await get_tree().process_frame
	assert_gt(float(menu._controls_list.get_child_count()), 1.0, "controls list is populated")
	menu.set_paused(false)
	menu.queue_free()


func test_pause_menu_ui_cancel_resumes() -> void:
	var menu: CanvasLayer = load("res://src/ui/pause_menu.tscn").instantiate()
	add_child(menu)
	menu.set_paused(true)
	await get_tree().process_frame
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	menu._unhandled_input(ev)
	assert_false(menu.visible, "ui_cancel resumes the game like Resume")
	get_tree().paused = false
