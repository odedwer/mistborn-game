extends TestCase
## Every mission JSON loads and validates, and the Act I story chain unlocks
## in the intended order:
## survivors_offer -> the_crew -> mistwalk_to_keep_venture ->
## lessons_in_the_mists -> lady_valette.

const CHAIN: Array[StringName] = [
	&"survivors_offer", &"the_crew", &"mistwalk_to_keep_venture",
	&"lessons_in_the_mists", &"lady_valette",
]


func test_all_missions_load() -> void:
	var missions := MissionData.load_all()
	# The 5 Act I missions plus the pre-existing vertical slice.
	assert_true(missions.size() >= CHAIN.size(), "expected at least %d missions, got %d" % [CHAIN.size(), missions.size()])
	var ids: Array[StringName] = []
	for m in missions:
		ids.append(m.id)
	for id in CHAIN:
		assert_true(ids.has(id), "missing mission '%s'" % id)


func test_every_mission_has_valid_structure() -> void:
	for m in MissionData.load_all():
		assert_true(m.id != &"", "mission with empty id")
		assert_true(m.title != "", "mission %s has no title" % m.id)
		assert_true(not m.stages.is_empty(), "mission %s has no stages" % m.id)
		for stage: Dictionary in m.stages:
			assert_true(stage.has("id"), "%s: stage missing id" % m.id)
			for obj: Dictionary in stage.get("objectives", []):
				assert_true(obj.has("id"), "%s/%s: objective missing id" % [m.id, stage.get("id")])
				assert_true(obj.has("type"), "%s/%s: objective %s missing type" % [m.id, stage.get("id"), obj.get("id")])


## Every `prerequisites` entry names a mission that actually exists.
func test_prerequisites_reference_real_missions() -> void:
	var missions := MissionData.load_all()
	var ids: Array[StringName] = []
	for m in missions:
		ids.append(m.id)
	for m in missions:
		for req in m.prerequisites:
			assert_true(ids.has(req), "%s requires missing mission '%s'" % [m.id, req])


## Every dialogue_id referenced by a mission JSON has a matching dialogue file.
func test_dialogue_ids_resolve() -> void:
	for m in MissionData.load_all():
		for stage: Dictionary in m.stages:
			for action: Dictionary in stage.get("on_enter", []):
				_check_dialogue_action(m.id, action)
			for obj: Dictionary in stage.get("objectives", []):
				if obj.get("type", "") == "dialogue":
					_assert_dialogue_exists(m.id, StringName(obj.get("dialogue_id", "")))
				for action: Dictionary in obj.get("on_complete", []):
					_check_dialogue_action(m.id, action)


func _check_dialogue_action(mission_id: StringName, action: Dictionary) -> void:
	if action.get("action", "") == "start_dialogue":
		_assert_dialogue_exists(mission_id, StringName(action.get("dialogue_id", "")))


func _assert_dialogue_exists(mission_id: StringName, dialogue_id: StringName) -> void:
	assert_true(dialogue_id != &"", "%s references an empty dialogue_id" % mission_id)
	var path := "res://src/mission/dialogues/%s.json" % dialogue_id
	assert_true(FileAccess.file_exists(path), "%s references missing dialogue '%s'" % [mission_id, dialogue_id])


## The chain unlocks one mission at a time, in the documented order.
func test_story_chain_unlocks_in_order() -> void:
	var story := StoryManager.new()
	story.refresh()
	var completed: Array[StringName] = []
	for expected in CHAIN:
		var next := story.next_story_mission(completed)
		assert_true(next != null, "no next mission after completing %s" % str(completed))
		assert_eq(next.id, expected, "expected '%s' next, got '%s'" % [expected, next.id if next != null else &"<null>"])
		completed.append(expected)
	# All five done: no Act I mission should still be "available" as next.
	var after := story.next_story_mission(completed)
	assert_true(after == null or not CHAIN.has(after.id), "chain re-offered a completed mission")


## A mission is not available before its prerequisite completes.
func test_locked_mission_is_not_available() -> void:
	var story := StoryManager.new()
	story.refresh()
	var avail := story.available_missions([])
	var ids: Array[StringName] = []
	for m in avail:
		ids.append(m.id)
	assert_true(ids.has(&"survivors_offer"), "survivors_offer should be available with nothing completed")
	assert_false(ids.has(&"the_crew"), "the_crew should be locked until survivors_offer completes")
	assert_false(ids.has(&"lady_valette"), "lady_valette should be locked at the start")
