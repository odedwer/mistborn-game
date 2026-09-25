extends Node3D
## Minimal stand-in for the player used by UI tests: exposes `allomancer`,
## `coins` and `vials` like src/player/player.gd.

var coins := 60
var vials := 2
var allomancer: FakeAllomancer


class FakeAllomancer:
	extends Node

	func get_reserve(_metal: int) -> float:
		return 100.0

	func is_burning(_metal: int) -> bool:
		return false


func _init() -> void:
	allomancer = FakeAllomancer.new()
	add_child(allomancer)
