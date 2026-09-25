extends CanvasLayer
## Pause menu: Esc toggles it and pauses the tree. Holds Resume, the map,
## the journal, settings, save/load, restart-at-checkpoint, main menu and quit.

var _root: Control
var _tabs: TabContainer
var _map: MapView
var _journal_list: VBoxContainer
var _skills_list: VBoxContainer
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
	if event.is_action_pressed("pause") and _settings_instance == null:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_paused(not visible)


func set_paused(paused: bool) -> void:
	visible = paused
	get_tree().paused = paused
	Events.pause_toggled.emit(paused)
	if paused:
		_refresh_map()
		_refresh_journal()
		_refresh_skills()
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
	_tabs.add_child(_build_skills_tab())

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


func _build_skills_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Skills"
	_skills_list = VBoxContainer.new()
	_skills_list.add_theme_constant_override("separation", 6)
	_skills_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_skills_list)
	return scroll


func _refresh_skills() -> void:
	for c in _skills_list.get_children():
		c.queue_free()
	_skills_list.add_child(UIHelpers.heading_label("Allomantic Mastery — %d point(s)" % GameState.mastery_points))
	for id in Mastery.ids():
		var level := GameState.mastery_level(id)
		var max_l := Mastery.max_level(id)
		var u: Dictionary = Mastery.UPGRADES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.custom_minimum_size = Vector2(420, 0)
		label.text = "%s (Lv %d/%d) — %s" % [u.get("label", String(id)), level, max_l, u.get("desc", "")]
		row.add_child(label)
		var cost := Mastery.cost_for_next(id, level)
		var btn := UIHelpers.button("Maxed" if cost < 0 else "Upgrade (%d pt)" % cost)
		btn.disabled = cost < 0 or GameState.mastery_points < cost
		btn.pressed.connect(_on_buy_mastery.bind(id))
		row.add_child(btn)
		_skills_list.add_child(row)


func _on_buy_mastery(id: StringName) -> void:
	if GameState.buy_mastery(id):
		_refresh_skills()


func _refresh_map() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_map.player_world_position = (player as Node3D).global_position
		_map.player_forward = Vector2((player as Node3D).global_transform.basis.z.x, (player as Node3D).global_transform.basis.z.z)
	var director := get_tree().get_first_node_in_group("mission_director")
	_map.mission_icons.clear()
	_map.waypoint = director.waypoint if director != null and "waypoint" in director else Vector3.INF
	if director != null and director.has_method("current_marker_position"):
		var pos: Vector3 = director.call("current_marker_position")
		if pos != Vector3.INF:
			_map.mission_icons.append({"position": pos, "label": "Objective"})
	_map.activity_icons.clear()
	var activities := get_tree().get_first_node_in_group("activity_manager")
	if activities != null:
		for id: StringName in activities.activities:
			var a: ActivityData = activities.activities[id]
			var pos: Vector3 = activities.call("start_marker_position", id)
			if pos == Vector3.INF:
				continue
			var rec: Dictionary = GameState.activity_record(id)
			_map.activity_icons.append({"position": pos, "label": a.title, "kind": a.type, "completed": rec.get("completed", false)})
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
	_journal_list.add_child(UIHelpers.heading_label("Completed Missions"))
	for m in GameState.completed_missions:
		_journal_list.add_child(UIHelpers.dim_label(String(m)))

	_journal_list.add_child(UIHelpers.vsep(10))
	_journal_list.add_child(UIHelpers.heading_label("Side Activities"))
	var activities := get_tree().get_first_node_in_group("activity_manager")
	if activities == null:
		_journal_list.add_child(UIHelpers.dim_label("None discovered yet."))
	else:
		for id: StringName in activities.activities:
			var a: ActivityData = activities.activities[id]
			var rec: Dictionary = GameState.activity_record(id)
			var medal: String = rec.get("medal", "")
			var best: float = rec.get("best_time", -1.0)
			var status := "not attempted"
			if rec.get("completed", false):
				status = "%s medal, best %.1fs" % [medal.capitalize(), best]
			elif int(rec.get("attempts", 0)) > 0:
				status = "attempted, not finished"
			var row := UIHelpers.button("%s — %s" % [a.title, status])
			row.pressed.connect(_on_journal_waypoint.bind(activities.call("start_marker_position", id)))
			_journal_list.add_child(row)

	_journal_list.add_child(UIHelpers.vsep(10))
	var found := 0
	for cid in CollectibleLore.all_ids():
		if GameState.is_collected(StringName(cid)):
			found += 1
	_journal_list.add_child(UIHelpers.heading_label("Collectibles (%d / %d)" % [found, CollectibleLore.total_count()]))
	for cid in CollectibleLore.all_ids():
		var got := GameState.is_collected(StringName(cid))
		var text: String = ("[x] " if got else "[ ] ") + (CollectibleLore.text_for(cid) if got else "???")
		if got:
			var row := UIHelpers.button(text)
			var pos := Vector3.INF
			if activities != null:
				pos = activities.call("collectible_marker_position", StringName(cid))
			row.pressed.connect(_on_journal_waypoint.bind(pos))
			_journal_list.add_child(row)
		else:
			_journal_list.add_child(UIHelpers.dim_label(text))


func _on_journal_waypoint(pos: Vector3) -> void:
	if pos == Vector3.INF:
		return
	_on_waypoint_picked(pos)


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
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D and GameState.last_checkpoint_id != &"":
		(player as Node3D).global_transform = GameState.last_checkpoint_transform
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
		if GameState.load_game(slot):
			var player := get_tree().get_first_node_in_group("player")
			var target := GameState.open_world_position if GameState.has_open_world_position else GameState.last_checkpoint_transform
			var world := get_tree().get_first_node_in_group("world")
			if world != null and "streamer" in world and world.streamer != null:
				world.streamer.load_now(target.origin, world.streamer.load_radius)
			if player is Node3D:
				(player as Node3D).global_transform = target
	_slot_popup.hide()
