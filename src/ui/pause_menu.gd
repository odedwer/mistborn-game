extends CanvasLayer
## Pause menu: Esc toggles it and pauses the tree. Holds Resume, the map,
## the journal, settings, save/load, restart-at-checkpoint, main menu and quit.

var _root: Control
var _tabs: TabContainer
var _map: MapView
var _journal_list: VBoxContainer
var _settings_instance: CanvasLayer
var _slot_popup: PopupPanel
var _slot_mode := "save"  # or "load"

const SETTINGS_SCENE := "res://src/ui/settings_menu.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	# Don't toggle over another screen that paused the game (mission complete).
	if event.is_action_pressed("pause") and _settings_instance == null \
			and (visible or not get_tree().paused):
		toggle()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if visible and is_inside_tree():
		get_tree().paused = false


func toggle() -> void:
	set_paused(not visible)


func set_paused(paused: bool) -> void:
	visible = paused
	get_tree().paused = paused
	Events.pause_toggled.emit(paused)
	if paused:
		_refresh_map()
		_refresh_journal()
		AudioManager.play_ui(&"ui_click")
	else:
		AudioManager.play_ui(&"ui_back")


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIHelpers.theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 640)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(UIHelpers.title_label("Paused"))

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(860, 560)
	vbox.add_child(_tabs)

	_tabs.add_child(_build_menu_tab())
	_map = MapView.new()
	_map.name = "Map"
	_map.custom_minimum_size = Vector2(820, 480)
	_map.waypoint_picked.connect(_on_waypoint_picked)
	_map.waypoint_cleared.connect(_on_waypoint_cleared)
	_tabs.add_child(_map)
	_tabs.add_child(_build_journal_tab())

	_slot_popup = PopupPanel.new()
	add_child(_slot_popup)


func _build_menu_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Menu"
	box.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_child(box)

	var resume_btn := UIHelpers.button("Resume")
	resume_btn.pressed.connect(func(): set_paused(false))
	box.add_child(resume_btn)

	var save_btn := UIHelpers.button("Save Game")
	save_btn.pressed.connect(func(): _open_slot_popup("save"))
	box.add_child(save_btn)

	var load_btn := UIHelpers.button("Load Game")
	load_btn.pressed.connect(func(): _open_slot_popup("load"))
	box.add_child(load_btn)

	var restart_btn := UIHelpers.button("Restart at Checkpoint")
	restart_btn.pressed.connect(_on_restart_checkpoint)
	box.add_child(restart_btn)

	var settings_btn := UIHelpers.button("Settings")
	settings_btn.pressed.connect(_open_settings)
	box.add_child(settings_btn)

	var main_menu_btn := UIHelpers.button("Main Menu")
	main_menu_btn.pressed.connect(_on_main_menu)
	box.add_child(main_menu_btn)

	var quit_btn := UIHelpers.button("Quit")
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	return margin


func _build_journal_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Journal"
	_journal_list = VBoxContainer.new()
	_journal_list.add_theme_constant_override("separation", 6)
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_journal_list)
	return scroll


func _refresh_map() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_map.player_world_position = (player as Node3D).global_position
		_map.player_forward = Vector2((player as Node3D).global_transform.basis.z.x, (player as Node3D).global_transform.basis.z.z)
	var director := get_tree().get_first_node_in_group("mission_director")
	_map.mission_icons.clear()
	if director != null and director.has_method("current_marker_position"):
		var pos: Vector3 = director.call("current_marker_position")
		if pos != Vector3.INF:
			_map.mission_icons.append({"position": pos, "label": "Objective"})
	_map.refresh()


func _refresh_journal() -> void:
	for c in _journal_list.get_children():
		c.queue_free()
	var director := get_tree().get_first_node_in_group("mission_director")
	_journal_list.add_child(UIHelpers.heading_label("Main Story"))
	if director != null and "mission" in director and director.mission != null:
		var mission: MissionData = director.mission
		_journal_list.add_child(UIHelpers.dim_label(mission.title))
		for i in mission.stages.size():
			var stage: Dictionary = mission.stages[i]
			var stage_done: bool = i < int(director.stage_index)
			var stage_label := "[x] " if stage_done else ("[ ] " if i > director.stage_index else "> ")
			_journal_list.add_child(UIHelpers.dim_label(stage_label + stage.get("label", "")))
			if i == director.stage_index:
				for obj: Dictionary in stage.get("objectives", []):
					var done := GameState.completed_objectives.has(StringName(obj.get("id", "")))
					var l := Label.new()
					l.text = ("  [x] " if done else "  [ ] ") + obj.get("text", "")
					_journal_list.add_child(l)
	_journal_list.add_child(UIHelpers.vsep(10))
	_journal_list.add_child(UIHelpers.heading_label("Completed"))
	for m in GameState.completed_missions:
		_journal_list.add_child(UIHelpers.dim_label(String(m)))


func _on_waypoint_picked(world_pos: Vector3) -> void:
	var director := get_tree().get_first_node_in_group("mission_director")
	if director != null and director.has_method("set_waypoint"):
		director.call("set_waypoint", world_pos)
	_refresh_map()


func _on_waypoint_cleared() -> void:
	var director := get_tree().get_first_node_in_group("mission_director")
	if director != null and director.has_method("clear_waypoint"):
		director.call("clear_waypoint")
	_refresh_map()


func _on_restart_checkpoint() -> void:
	# The director restores the checkpoint snapshot (health, coins, reserves)
	# along with the position.
	var director := get_tree().get_first_node_in_group("mission_director")
	if director != null and director.has_method("respawn_at_checkpoint"):
		director.call("respawn_at_checkpoint")
	set_paused(false)


func _open_settings() -> void:
	if _settings_instance != null:
		return
	var scene: PackedScene = load(SETTINGS_SCENE)
	if scene == null:
		return
	_settings_instance = scene.instantiate()
	add_child(_settings_instance)
	if _settings_instance.has_signal("closed"):
		_settings_instance.closed.connect(func():
			_settings_instance.queue_free()
			_settings_instance = null
		)


func _on_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _open_slot_popup(mode: String) -> void:
	_slot_mode = mode
	for c in _slot_popup.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_slot_popup.add_child(box)
	box.add_child(UIHelpers.heading_label("Save" if mode == "save" else "Load"))
	for slot in range(1, 4):
		var has := GameState.has_save(slot)
		var b := UIHelpers.button("Slot %d %s" % [slot, "(occupied)" if has else "(empty)"])
		b.pressed.connect(_on_slot_chosen.bind(slot))
		box.add_child(b)
	_slot_popup.popup_centered(Vector2i(300, 220))


func _on_slot_chosen(slot: int) -> void:
	if _slot_mode == "save":
		GameState.save_game(slot)
	else:
		# MissionDirector listens to GameState.load_completed and resyncs the
		# mission and the player to the loaded state.
		GameState.load_game(slot)
	_slot_popup.hide()
