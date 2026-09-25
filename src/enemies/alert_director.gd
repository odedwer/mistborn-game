class_name AlertDirector
extends Node
## Lightweight shared alert tracker. One instance lives in the level (group
## "alert_director"); every [EnemyBase] reports its own alert level to it on
## every state change, and it broadcasts the district-wide maximum through
## [signal Events.alert_level_changed] (0 calm, 1 suspicious, 2 combat).

var _levels: Dictionary = {}  # Node -> int
var _current_level: int = 0


func _ready() -> void:
	add_to_group(&"alert_director")


## Called by enemies; `level` is 0 (calm), 1 (suspicious) or 2 (combat).
func report(enemy: Node, level: int) -> void:
	if level <= 0:
		_levels.erase(enemy)
	else:
		_levels[enemy] = level
	var new_level := 0
	for v: int in _levels.values():
		new_level = maxi(new_level, v)
	if new_level != _current_level:
		_current_level = new_level
		Events.alert_level_changed.emit(_current_level)


func current_level() -> int:
	return _current_level
