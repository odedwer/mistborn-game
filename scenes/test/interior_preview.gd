extends Node3D
## Interior preview: loads an interior, moves the real player in (as
## SceneTransition does, so e.g. the ballroom gown swap happens) and frames it
## with a fixed camera. For screenshots:
##   godot -s res://tools/screenshot.gd -- res://scenes/test/interior_preview.tscn out.png 60 --interior=hub
## Options: --interior=hub|ballroom|office   --cam=wide|close   --no-player

const INTERIORS := {
	"hub": "res://src/mission/interiors/clubs_shop_hub.tscn",
	"ballroom": "res://src/mission/interiors/keep_venture_ballroom.tscn",
	"office": "res://src/mission/interiors/canton_office.tscn",
}
## [camera position, look-at target] per interior and framing
const CAMERAS := {
	"hub:wide": [Vector3(0.5, 3.3, 5.3), Vector3(-0.5, 0.7, -1.0)],
	"hub:close": [Vector3(0.9, 1.75, -0.6), Vector3(-0.2, 1.25, -3.0)],
	"ballroom:wide": [Vector3(0, 3.2, 8.0), Vector3(0, 1.0, -1.0)],
	"ballroom:close": [Vector3(1.6, 1.7, 4.4), Vector3(0, 0.9, 7.0)],
	"office:wide": [Vector3(0, 2.2, -3.0), Vector3(0, 0.9, 2.5)],
	"office:close": [Vector3(0, 1.6, -0.5), Vector3(0, 1.1, 2.7)],
}

var _camera: Camera3D


func _ready() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var which: String = opts.get("interior", "hub")
	var room: Node = (load(INTERIORS.get(which, INTERIORS["hub"])) as PackedScene).instantiate()
	add_child(room)
	if not opts.has("no-player") and ResourceLoader.exists("res://src/player/player.tscn"):
		var player := (load("res://src/player/player.tscn") as PackedScene).instantiate() as Node3D
		add_child(player)  # ready outside, then moved in, like SceneTransition does
		remove_child(player)
		room.add_child(player)
		for n in room.find_children("*", "Marker3D", true, false):
			if n.is_in_group(&"interior_spawn"):
				player.global_position = (n as Node3D).global_position
				break
		player.process_mode = Node.PROCESS_MODE_DISABLED  # no input/camera rig in a preview
		var model := player.get(&"model") as Node
		if model != null:
			model.process_mode = Node.PROCESS_MODE_ALWAYS  # but keep breathing
		# face the room (the player model faces +Z; rooms are entered from +Z)
		var visual := player.get_node_or_null(^"Visual") as Node3D
		if visual != null:
			visual.rotation.y = PI if which != "office" else 0.0
	var cam_key := "%s:%s" % [which, opts.get("cam", "wide")]
	var c: Array = CAMERAS.get(cam_key, CAMERAS["hub:wide"])
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.position = c[0]
	_camera.look_at(c[1], Vector3.UP)
	_camera.make_current()


func _process(_delta: float) -> void:
	if _camera != null and not _camera.current:
		_camera.make_current()
