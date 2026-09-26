extends Node
## Interior scene transitions (autoload `SceneTransition`).
##
## Interior mission spaces (the canton office, Clubs' shop hub, Keep
## Venture's ballroom) are separate scenes from the open world. Entering one
## does not destroy or recreate the player: the live player node is
## reparented from the outdoor world into the interior scene (and back), so
## every bit of its state — health, coins, reserves, `allowed_metals` — comes
## along for free. A brief fade-to-black doubles as the loading screen.
##
## Interiors mark their spawn point with a `Marker3D` in group
## `"interior_spawn"` and (for a door back out) a return point in group
## `"interior_return"`. A `res://src/world/interior_door.gd` on a body/area
## calls `enter_interior`/`exit_interior` on interact.

const FADE_TIME := 0.35

var _interior_root: Node
var _outdoor_world: Node
var _saved_transform := Transform3D.IDENTITY
var _fade: CanvasLayer
var _fade_rect: ColorRect


func is_inside_interior() -> bool:
	return _interior_root != null and is_instance_valid(_interior_root)


## Loads `scene_path` as a child of the current scene, moves the player into
## it (positioned at its `"interior_spawn"` marker), and pauses/hides the
## outdoor world so it stops streaming/simulating while unused.
func enter_interior(scene_path: String) -> void:
	if is_inside_interior() or not ResourceLoader.exists(scene_path):
		return
	var player := get_tree().get_first_node_in_group(&"player")
	var host := _host_node()
	if player == null or host == null:
		return
	await _fade_to(1.0)
	# The player (or a test's stand-in) can be freed during the fade.
	if not is_instance_valid(player) or not is_instance_valid(host) or is_inside_interior():
		await _fade_to(0.0)
		return
	_saved_transform = (player as Node3D).global_transform
	_outdoor_world = get_tree().get_first_node_in_group(&"world")
	if _outdoor_world != null:
		_outdoor_world.visible = false
		_outdoor_world.process_mode = Node.PROCESS_MODE_DISABLED
	_interior_root = (load(scene_path) as PackedScene).instantiate()
	host.add_child(_interior_root)
	_reparent(player, _interior_root)
	var spawn := _find_in_group(_interior_root, &"interior_spawn")
	if spawn != null:
		(player as Node3D).global_transform = spawn.global_transform
	Events.interior_entered.emit(scene_path)
	await _fade_to(0.0)


## Swaps the current interior for `scene_path` under one fade, without
## surfacing to the open world in between (Act III: the rebel caves straight
## onto the battlefield, the palace halls down into the Pits). Falls back to a
## plain `enter_interior` when no interior is active. The saved open-world
## transform is kept, so the eventual `exit_interior` still returns the
## player to where the chain of interiors began.
func switch_interior(scene_path: String) -> void:
	if not is_inside_interior():
		await enter_interior(scene_path)
		return
	if not ResourceLoader.exists(scene_path):
		return
	var player := get_tree().get_first_node_in_group(&"player")
	var host := _host_node()
	if player == null or host == null:
		return
	await _fade_to(1.0)
	if not is_instance_valid(player) or not is_instance_valid(host):
		await _fade_to(0.0)
		return
	var next := (load(scene_path) as PackedScene).instantiate()
	host.add_child(next)
	_reparent(player, next)
	var old := _interior_root
	_interior_root = next
	if old != null and is_instance_valid(old):
		old.queue_free()
	var spawn := _find_in_group(next, &"interior_spawn")
	if spawn != null:
		(player as Node3D).global_transform = spawn.global_transform
	Events.interior_entered.emit(scene_path)
	await _fade_to(0.0)


## The live interior scene root, or null when in the open world.
func current_interior() -> Node:
	return _interior_root if is_inside_interior() else null


## Removes the interior scene and restores the player to the outdoor world at
## the transform it had before `enter_interior` (its exact open-world spot).
func exit_interior() -> void:
	if not is_inside_interior():
		return
	var player := get_tree().get_first_node_in_group(&"player")
	var host := _host_node()
	await _fade_to(1.0)
	if not is_inside_interior():
		await _fade_to(0.0)
		return
	if is_instance_valid(player) and is_instance_valid(host):
		_reparent(player, host)
		(player as Node3D).global_transform = _saved_transform
	if _outdoor_world != null and is_instance_valid(_outdoor_world):
		_outdoor_world.visible = true
		_outdoor_world.process_mode = Node.PROCESS_MODE_INHERIT
	_interior_root.queue_free()
	_interior_root = null
	Events.interior_exited.emit()
	await _fade_to(0.0)


## The current scene, or the tree root as a fallback (e.g. in headless tests,
## which run under a bare `SceneTree` with no `current_scene`).
func _host_node() -> Node:
	var cur := get_tree().current_scene
	return cur if cur != null else get_tree().root


func _reparent(node: Node, new_parent: Node) -> void:
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	new_parent.add_child(node)


func _find_in_group(root: Node, group: StringName) -> Node3D:
	if root.is_in_group(group) and root is Node3D:
		return root
	for c in root.get_children():
		var found := _find_in_group(c, group)
		if found != null:
			return found
	return null


func _ensure_fade() -> void:
	if _fade != null and is_instance_valid(_fade):
		return
	_fade = CanvasLayer.new()
	_fade.layer = 90
	_fade.process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "LoadingLabel"
	label.text = "Loading..."
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 24)
	label.modulate = Color(1, 1, 1, 0)
	_fade_rect.add_child(label)
	_fade.add_child(_fade_rect)
	if is_inside_tree():
		get_tree().root.add_child.call_deferred(_fade)
		await get_tree().process_frame


func _fade_to(alpha: float) -> void:
	await _ensure_fade()
	if _fade == null or not is_instance_valid(_fade):
		return
	_fade.visible = true
	var label := _fade_rect.get_node_or_null("LoadingLabel") as Label
	if is_inside_tree():
		var tw := get_tree().create_tween()
		tw.tween_property(_fade_rect, "color:a", alpha, FADE_TIME)
		if label != null:
			tw.parallel().tween_property(label, "modulate:a", alpha, FADE_TIME)
		await tw.finished
	else:
		_fade_rect.color.a = alpha
	if alpha <= 0.0:
		_fade.visible = false
