class_name SentryPosts
extends RefCounted
## Static guard figures at "sentry_post" world markers (meta `yaw`, radians):
## set dressing, not enemies. Each is a `CharacterModel` guard standing at
## ease, parented to the marker's streamed chunk so it comes and goes with
## it. No collision and no AI; the real patrols are `enemy_spawn` guards.
## Called by `scenes/game.gd` and `tools/preview.gd` for newly loaded markers.

const MODEL := "res://assets/models/characters/guard.tscn"


## Spawns a figure for every sentry marker in `nodes` that has none yet.
## Returns how many were spawned.
static func populate(nodes: Array) -> int:
	var ps := load(MODEL) as PackedScene
	if ps == null:
		return 0
	var n := 0
	for m in nodes:
		if not (m is Marker3D) or not is_instance_valid(m) or not m.is_in_group(&"sentry_post"):
			continue
		if m.get_meta(&"sentry_spawned", false) or m.get_parent() == null:
			continue
		var fig := ps.instantiate() as Node3D
		if fig == null:
			continue
		fig.name = "Sentry"
		fig.add_to_group(&"sentry_figure")
		m.get_parent().add_child(fig)
		fig.global_position = (m as Marker3D).global_position
		fig.rotation.y = float(m.get_meta(&"yaw", 0.0))
		if fig is CharacterModel:
			(fig as CharacterModel).randomize_variant(int((m as Marker3D).global_position.x * 13.0 + (m as Marker3D).global_position.z))
			(fig as CharacterModel).set_locomotion(0.0, true)
		m.set_meta(&"sentry_spawned", true)
		n += 1
	return n
