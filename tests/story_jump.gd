extends RefCounted
## Test helper: put GameState at the start of a story mission, with every
## mission it (transitively) depends on marked complete.


static func jump_to(mission_id: StringName) -> void:
	var story := StoryManager.new()
	story.refresh()
	var done: Array[StringName] = []
	var todo: Array[StringName] = [mission_id]
	while not todo.is_empty():
		var m := story.get_mission(todo.pop_back())
		if m == null:
			continue
		for req in m.prerequisites:
			var r := StringName(req)
			if not done.has(r):
				done.append(r)
				todo.append(r)
	for r in done:
		GameState.record_mission_complete(r)
	GameState.mission_id = mission_id
	GameState.mission_stage = 0
