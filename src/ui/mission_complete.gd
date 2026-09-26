extends CanvasLayer
## Mission complete / stats screen. Shown when `Events.mission_completed`
## fires; reads run stats from `GameState`.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Events.mission_completed.connect(_on_mission_completed)
	visible = false


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.name = "Stats"
	box.custom_minimum_size = Vector2(600, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(UIHelpers.title_label("Mission Complete"))

	var stats_label := Label.new()
	stats_label.name = "StatsLabel"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats_label)

	# Continue straight into the next story mission, in place (the save was
	# already written by `GameState` on `mission_completed`).
	var next_btn := UIHelpers.button("Continue")
	next_btn.name = "ContinueButton"
	next_btn.pressed.connect(_on_continue)
	box.add_child(next_btn)
	var continue_btn := UIHelpers.button("Main Menu")
	continue_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	box.add_child(continue_btn)


## Never leave the tree paused behind when the game scene goes away.
func _exit_tree() -> void:
	if visible and is_inside_tree():
		get_tree().paused = false


func _on_mission_completed(_id: StringName) -> void:
	# The finale hands over to the credits and then post-game free roam;
	# no stats card on top of that.
	if GameState.post_game:
		return
	get_tree().paused = true
	visible = true
	var stats_label: Label = find_child("StatsLabel", true, false)
	stats_label.text = _format_stats()


func _on_continue() -> void:
	visible = false
	get_tree().paused = false
	var director := get_tree().get_first_node_in_group("mission_director")
	if director != null and director.has_method("start_next_mission"):
		director.call("start_next_mission")


func _format_stats() -> String:
	var t := GameState.stat_time_seconds
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	return "Time: %d:%02d\nKills: %d\nCoins thrown: %d\nDeaths: %d\nTimes detected: %d" % [
		minutes, seconds, GameState.stat_kills, GameState.stat_coins_thrown,
		GameState.stat_deaths, GameState.stat_detected_count,
	]
