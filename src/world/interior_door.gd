extends StaticBody3D
## A door the player can interact with to cross into (or out of) an interior
## mission scene, via `SceneTransition`. Place one at Clubs' shop, Keep
## Venture's gate, etc.; give it a `CollisionShape3D` child for the player's
## interact raycast to hit.

## Interior scene to enter. Leave empty for an exit door (see `is_exit`).
@export var interior_scene := ""
## True for a door placed *inside* an interior that leads back outside.
@export var is_exit := false


## Called by `Player.interact()` (matches its `n.has_method(&"interact")`).
func interact(_player: Node) -> void:
	if is_exit:
		SceneTransition.exit_interior()
	elif interior_scene != "":
		SceneTransition.enter_interior(interior_scene)
