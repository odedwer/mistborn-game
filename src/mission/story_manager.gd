class_name StoryManager
extends RefCounted
## Tracks the main story chain and side activities across the whole game.
##
## This is intentionally small today (the vertical slice ships one mission),
## but the shape is meant to scale: every mission and side activity is a
## `MissionData` loaded from `res://src/mission/missions/*.json`, and
## `GameState` persists which ones are unlocked/completed plus collectibles.
## `MissionDirector` asks a `StoryManager` for "what should run now" instead
## of hardcoding the vertical slice.

var all_missions: Array[MissionData] = []


func refresh(dir_path := "res://src/mission/missions") -> void:
	all_missions = MissionData.load_all(dir_path)


func get_mission(id: StringName) -> MissionData:
	for m in all_missions:
		if m.id == id:
			return m
	return null


## Missions whose prerequisites are all in `completed_ids` and that are not
## themselves completed yet. Side activities (coin races, pursuits, ambushes)
## are just `MissionData` with no downstream unlocks, so they show up here too
## once their own prerequisites (if any) are met.
func available_missions(completed_ids: Array[StringName]) -> Array[MissionData]:
	var out: Array[MissionData] = []
	for m in all_missions:
		if completed_ids.has(m.id):
			continue
		var ok := true
		for req in m.prerequisites:
			if not completed_ids.has(req):
				ok = false
				break
		if ok:
			out.append(m)
	return out


## The next main-story mission to run: the first available mission belonging
## to the lowest act/chapter not yet completed. Falls back to the first
## available mission of any kind (e.g. a side activity) if none qualifies.
func next_story_mission(completed_ids: Array[StringName]) -> MissionData:
	var avail := available_missions(completed_ids)
	if avail.is_empty():
		return null
	avail.sort_custom(func(a: MissionData, b: MissionData): return a.act < b.act)
	return avail[0]
