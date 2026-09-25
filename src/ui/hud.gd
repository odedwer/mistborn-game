extends CanvasLayer
## Heads-up display. Listens to `Events` and the `player` group only, per the
## architecture contract, so it works standalone even before the player or
## world scenes exist.

const METAL_ORDER := [
	Metal.Type.STEEL, Metal.Type.IRON, Metal.Type.PEWTER, Metal.Type.TIN,
	Metal.Type.ZINC, Metal.Type.BRASS, Metal.Type.COPPER, Metal.Type.BRONZE,
	Metal.Type.ATIUM, Metal.Type.DURALUMIN,
]

var _player: Node
var _health_bar: ProgressBar
var _coin_label: Label
var _vial_label: Label
var _crosshair: ColorRect
var _vials: Dictionary = {}          # metal -> ProgressBar
var _vial_glow: Dictionary = {}      # metal -> Panel (burning glow)
var _objective_label: Label
var _objective_marker: Control
var _hint_box: PanelContainer
var _hint_label: Label
var _hint_timer := 0.0
var _vignette: ColorRect
var _vignette_alpha := 0.0
var _alert_label: Label
var _pulse_layer: Control
var _fps_label: Label
var _show_fps := false
var _wheel: Control
var _wheel_open := false
var _steel_locked := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Events.player_health_changed.connect(_on_health_changed)
	Events.metal_reserve_changed.connect(_on_reserve_changed)
	Events.metal_burn_changed.connect(_on_burn_changed)
	Events.metal_flare_changed.connect(_on_flare_changed)
	Events.metal_depleted.connect(_on_depleted)
	Events.allomantic_line_used.connect(_on_line_used)
	Events.allomantic_pulse.connect(_on_pulse)
	Events.alert_level_changed.connect(_on_alert_changed)
	Events.objective_updated.connect(_on_objective_updated)
	Events.hint_requested.connect(_on_hint_requested)
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.pickup_collected.connect(_on_pickup_collected)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player != null:
			_sync_from_player()
	_update_counts()
	_update_objective_marker()
	_update_vignette(delta)
	_update_hint(delta)
	if _show_fps:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if Input.is_action_just_pressed("toggle_debug"):
		_show_fps = not _show_fps
		_fps_label.visible = _show_fps
	_update_wheel()


# --- Build ---------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIHelpers.theme()
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.5, 0, 0, 0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	# Health bar, bottom-left.
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = 100
	_health_bar.value = 100
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(260, 22)
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.position = Vector2(24, -100)
	_health_bar.add_theme_stylebox_override("fill", _flat_style(Color(0.7, 0.12, 0.12)))
	_health_bar.add_theme_stylebox_override("background", _flat_style(Color(0.1, 0.1, 0.1, 0.7)))
	root.add_child(_health_bar)

	_coin_label = Label.new()
	_coin_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_coin_label.position = Vector2(300, -100)
	root.add_child(_coin_label)

	_vial_label = Label.new()
	_vial_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_vial_label.position = Vector2(300, -72)
	root.add_child(_vial_label)

	# Metal reserve vials, bottom-left row above health.
	var vial_row := HBoxContainer.new()
	vial_row.add_theme_constant_override("separation", 4)
	vial_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vial_row.position = Vector2(24, -170)
	root.add_child(vial_row)
	var no_pad_style := StyleBoxEmpty.new()
	for metal in METAL_ORDER:
		var container := PanelContainer.new()
		container.add_theme_stylebox_override("panel", no_pad_style)
		container.custom_minimum_size = Vector2(22, 60)
		var glow := Panel.new()
		glow.custom_minimum_size = Vector2(22, 60)
		var glow_style := _flat_style(Metal.color_of(metal))
		glow_style.bg_color.a = 0.0
		glow.add_theme_stylebox_override("panel", glow_style)
		container.add_child(glow)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = Metal.MAX_RESERVE
		bar.value = 0
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(18, 56)
		bar.add_theme_stylebox_override("fill", _flat_style(Metal.color_of(metal)))
		bar.add_theme_stylebox_override("background", _flat_style(Color(0.08, 0.08, 0.08, 0.8)))
		container.add_child(bar)
		vial_row.add_child(container)
		_vials[metal] = bar
		_vial_glow[metal] = glow

	# Crosshair, screen center.
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.85)
	_crosshair.custom_minimum_size = Vector2(6, 6)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_crosshair)

	# Objective tracker, top-left.
	_objective_label = Label.new()
	_objective_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_label.position = Vector2(24, 24)
	_objective_label.custom_minimum_size = Vector2(420, 0)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_objective_label)

	# On-screen/off-screen objective marker.
	_objective_marker = _make_marker()
	root.add_child(_objective_marker)

	# Alert indicator, top-right.
	_alert_label = Label.new()
	_alert_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_alert_label.position = Vector2(-160, 24)
	_alert_label.text = ""
	root.add_child(_alert_label)

	# Hint / subtitle box, bottom-center.
	_hint_box = PanelContainer.new()
	_hint_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_box.position = Vector2(-260, -110)
	_hint_box.custom_minimum_size = Vector2(520, 0)
	_hint_box.visible = false
	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_box.add_child(_hint_label)
	root.add_child(_hint_box)

	# Bronze pulse ripple layer.
	_pulse_layer = Control.new()
	_pulse_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pulse_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pulse_layer)

	# FPS counter.
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-120, 60)
	_fps_label.visible = false
	root.add_child(_fps_label)

	# Metal wheel (hold Tab).
	_wheel = _make_wheel()
	_wheel.visible = false
	root.add_child(_wheel)


static func _flat_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s


func _make_marker() -> Control:
	var m := ColorRect.new()
	m.color = Color(1, 0.8, 0.3, 0.9)
	m.custom_minimum_size = Vector2(14, 14)
	m.pivot_offset = Vector2(7, 7)
	m.rotation_degrees = 45
	m.visible = false
	return m


func _make_wheel() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.custom_minimum_size = Vector2(360, 360)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(grid)
	for metal in METAL_ORDER:
		if metal == Metal.Type.DURALUMIN:
			continue
		var lbl := Label.new()
		lbl.text = Metal.name_of(metal)
		lbl.add_theme_color_override("font_color", Metal.color_of(metal))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(70, 70)
		lbl.name = "wheel_%d" % metal
		grid.add_child(lbl)
	return c


# --- Frame updates --------------------------------------------------------------

func _update_counts() -> void:
	if _player == null:
		return
	if "coins" in _player:
		_coin_label.text = "Coins: %d" % int(_player.coins)
	if "vials" in _player:
		_vial_label.text = "Vials: %d" % int(_player.vials)


func _update_objective_marker() -> void:
	var director := get_tree().get_first_node_in_group("mission_director")
	if director == null or not director.has_method("current_marker_position"):
		_objective_marker.visible = false
		return
	var pos: Vector3 = director.call("current_marker_position")
	if pos == Vector3.INF:
		_objective_marker.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_objective_marker.visible = false
		return
	var to_target := pos - cam.global_position
	var behind := cam.global_transform.basis.z.dot(to_target) > 0.0
	var screen := get_viewport().get_visible_rect().size
	if not behind and cam.is_position_in_frustum(pos):
		var p := cam.unproject_position(pos)
		_objective_marker.position = p - _objective_marker.custom_minimum_size * 0.5
		_objective_marker.visible = true
		_objective_marker.rotation_degrees = 45
	else:
		# Off-screen: clamp to the edge of the screen, pointing toward the
		# target in *camera* space (screen right = camera X, screen up =
		# camera Y). Targets behind the camera go to the bottom half.
		var center := screen * 0.5
		var local := cam.global_basis.inverse() * to_target
		var dir2 := Vector2(local.x, -local.y)
		if behind:
			dir2.y = absf(dir2.y) + 0.25 * absf(dir2.x) + 0.001
		dir2 = dir2.normalized() if dir2.length() > 0.0001 else Vector2.DOWN
		var margin := 40.0
		var half := center - Vector2(margin, margin)
		var scale := minf(absf(half.x / maxf(absf(dir2.x), 0.0001)), absf(half.y / maxf(absf(dir2.y), 0.0001)))
		var edge_pos := center + dir2 * scale
		_objective_marker.position = edge_pos - _objective_marker.custom_minimum_size * 0.5
		_objective_marker.visible = true
		_objective_marker.rotation_degrees = rad_to_deg(dir2.angle()) + 90.0


func _update_vignette(delta: float) -> void:
	_vignette_alpha = maxf(_vignette_alpha - delta * 0.6, 0.0)
	_vignette.color.a = _vignette_alpha * 0.5


func _update_hint(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_box.visible = false


func _update_wheel() -> void:
	var open := Input.is_action_pressed("metal_wheel")
	if open != _wheel_open:
		_wheel_open = open
		_wheel.visible = open
	if open and _player != null and "allomancer" in _player:
		for i in InputSetup.TOGGLE_TO_METAL.keys():
			if Input.is_action_just_pressed(i):
				_player.allomancer.toggle_burn(InputSetup.TOGGLE_TO_METAL[i])


# --- Event handlers --------------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


## Pulls the full current state from a newly found player, since the HUD only
## hears about changes after it connects.
func _sync_from_player() -> void:
	var al: Node = _player.get("allomancer")
	if al != null:
		for metal: int in _vials:
			(_vials[metal] as ProgressBar).value = al.get_reserve(metal)
			_on_burn_changed(al, metal, al.is_burning(metal))
	var h: Health = Health.find_on(_player)
	if h != null:
		_on_health_changed(h.current, h.max_health)


## True if the signal came from the local player's allomancer (enemies emit the
## same metal signals).
func _is_player_allomancer(allomancer: Node) -> bool:
	return _player != null and is_instance_valid(_player) and (allomancer == _player or allomancer == _player.get("allomancer"))


func _on_reserve_changed(allomancer: Node, metal: int, amount: float) -> void:
	if not _is_player_allomancer(allomancer):
		return
	if _vials.has(metal):
		(_vials[metal] as ProgressBar).value = amount


func _on_burn_changed(allomancer: Node, metal: int, burning: bool) -> void:
	if not _is_player_allomancer(allomancer) or not _vial_glow.has(metal):
		return
	var glow: Panel = _vial_glow[metal]
	var style: StyleBoxFlat = glow.get_theme_stylebox("panel")
	var tw := create_tween()
	tw.tween_property(style, "bg_color:a", 0.55 if burning else 0.0, 0.25)


func _on_flare_changed(allomancer: Node, metal: int, flaring: bool) -> void:
	if not _is_player_allomancer(allomancer) or not flaring or not _vial_glow.has(metal):
		return
	var glow: Panel = _vial_glow[metal]
	var style: StyleBoxFlat = glow.get_theme_stylebox("panel")
	var tw := create_tween()
	tw.tween_property(style, "bg_color:a", 1.0, 0.08)
	tw.tween_property(style, "bg_color:a", 0.55, 0.3)


func _on_depleted(allomancer: Node, metal: int) -> void:
	if not _is_player_allomancer(allomancer) or not _vials.has(metal):
		return
	var bar: ProgressBar = _vials[metal]
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill")
	var base_color := Metal.color_of(metal)
	var tw := create_tween()
	tw.tween_property(style, "bg_color", Color(1, 0.2, 0.2), 0.08)
	tw.tween_property(style, "bg_color", base_color, 0.3)


func _on_line_used(allomancer: Node, _target: Node, metal: int, strength: float) -> void:
	if not _is_player_allomancer(allomancer) or metal != Metal.Type.STEEL:
		return
	_steel_locked = strength > 0.0
	_crosshair.color = Color(0.4, 0.7, 1.0, 1.0) if _steel_locked else Color(1, 1, 1, 0.85)
	_crosshair.custom_minimum_size = Vector2(10, 10) if _steel_locked else Vector2(6, 6)


func _on_pulse(_source: Node, _metal: int, position: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_target := position - cam.global_position
	var dir2 := Vector2(to_target.x, -to_target.z).normalized()
	var screen := get_viewport().get_visible_rect().size
	var center := screen * 0.5
	var ring := Panel.new()
	ring.custom_minimum_size = Vector2(24, 24)
	ring.pivot_offset = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Metal.color_of(Metal.Type.BRONZE)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	ring.add_theme_stylebox_override("panel", style)
	var edge_pos := center + dir2 * (minf(center.x, center.y) - 40.0)
	ring.position = edge_pos - ring.custom_minimum_size * 0.5
	_pulse_layer.add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector2(2.2, 2.2), 0.6)
	tw.parallel().tween_property(style, "border_color:a", 0.0, 0.6)
	tw.tween_callback(ring.queue_free)


func _on_alert_changed(level: int) -> void:
	match level:
		0:
			_alert_label.text = ""
		1:
			_alert_label.text = "! Suspicious"
			_alert_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		2:
			_alert_label.text = "!! Combat"
			_alert_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))


func _on_objective_updated(_id: StringName, text: String, done: bool) -> void:
	if text != "":
		_objective_label.text = text + (" (done)" if done else "")


func _on_hint_requested(text: String, duration: float) -> void:
	if not GameSettings.hints_enabled:
		return
	_hint_label.text = text
	_hint_box.visible = true
	_hint_timer = duration


func _on_damage_dealt(target: Node, _amount: float, _source: Node, _kind: StringName) -> void:
	if _player != null and target == _player:
		_vignette_alpha = 1.0


func _on_pickup_collected(kind: StringName, amount: float) -> void:
	_objective_label.tooltip_text = "Picked up %s x%s" % [kind, amount]
