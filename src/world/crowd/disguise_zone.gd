class_name DisguiseZone
extends Node
## Add as a child of an interior: while the player is anywhere inside that
## interior (SceneTransition reparents the player in and out), it wears
## `model_path` (default: Vin's ball gown, for Lady Valette) via
## `Player.set_model_scene`, and its usual model again once it leaves.

@export_file("*.tscn") var model_path := "res://assets/models/characters/vin_gown.tscn"


func _ready() -> void:
	var host := get_parent()
	host.child_entered_tree.connect(_on_entered)
	host.child_exiting_tree.connect(_on_exiting)
	for c in host.get_children():
		_on_entered(c)


func _on_entered(node: Node) -> void:
	if node.is_in_group(&"player") and node.has_method(&"set_model_scene"):
		node.call(&"set_model_scene", model_path)


func _on_exiting(node: Node) -> void:
	if node.is_in_group(&"player") and node.has_method(&"set_model_scene"):
		node.call_deferred(&"set_model_scene", "")
